# Face Recognition Design

## Goal

Add face recognition to aksabot using a standalone ESP32-CAM as a camera peripheral. Backend runs buffalo_l ONNX inference and pgvector similarity search. Identified faces are injected into the LLM conversation context so the bot knows who is present.

## Architecture

```
ESP32-CAM ──WebSocket──► Backend (vision module)
                              │
                              ├─ buffalo_l ONNX (detect + embed)
                              ├─ pgvector (face profiles)
                              └─ gateway ──► ESP32-S3 (aksabot main)
                                                └─ LLM context updated

Flutter app ──REST──► Backend (enrollment API)
```

Two separate devices on the same WiFi network and same user account:
- **ESP32-CAM** — camera peripheral only. WebSocket to backend. No display, no audio, no BLE.
- **ESP32-S3 (aksabot main)** — voice/display/face animation/BLE. No camera.

Backend links them — when ESP32-CAM identifies a face, backend pushes identity to the conversation session on the paired aksabot device.

## Data Flow

**Recognition (runtime):**
1. ESP32-CAM sends `vision:frame` (binary JPEG) at 1fps
2. Backend runs buffalo_l: detect face → crop → 512-dim ArcFace embedding (~100ms)
3. pgvector cosine search: `SELECT ... ORDER BY embedding <=> $1 LIMIT 1`
4. If distance < 0.4 → known person; if distance ≥ 0.4 → unknown
5. Backend pushes `face:identity {name, confidence, unknown}` to aksabot main device WebSocket session
6. SessionManager updates `currentIdentity` on active conversation
7. LLM orchestrator injects identity into system prompt on next turn

**Enrollment:**
1. Flutter uploads JPEG(s) via `POST /vision/enroll` (phone camera, gallery, or ESP32-CAM capture)
2. Backend detects face → embeds → stores in `face_profiles` table
3. For ESP32-CAM capture: `POST /vision/enroll/capture` → backend sends `vision:capture` WS event to ESP32-CAM → camera captures 8 frames 500ms apart → sends as `vision:enroll_frames` → backend embeds all 8, averages → stores single averaged embedding

**LLM context injection:**
- Known face: inject "Mark is present at the desk" into system prompt
- Unknown face: inject "An unknown person is present at the desk" into system prompt
- No face: inject nothing (or clear previous identity)
- LLM decides whether to verbally acknowledge or silently incorporate — no forced announcement

## Backend: Vision Module

**Location:** `backend/src/modules/vision/`

**New entity — `face_profile`:**
```typescript
@Entity('face_profiles')
export class FaceProfile {
  @PrimaryGeneratedColumn('uuid') id: string;
  @ManyToOne(() => User) user: User;
  @Column() name: string;
  @Column('vector', { length: 512 }) embedding: number[];  // pgvector
  @Column({ nullable: true }) thumbnailUrl: string;
  @CreateDateColumn() createdAt: Date;
  @UpdateDateColumn() updatedAt: Date;
}
```

**pgvector migration:**
```sql
CREATE EXTENSION IF NOT EXISTS vector;
ALTER TABLE face_profiles ADD COLUMN embedding vector(512);
CREATE INDEX ON face_profiles USING ivfflat (embedding vector_cosine_ops) WITH (lists = 10);
```

**REST endpoints (all JWT-protected, scoped to user):**
- `POST /vision/enroll` — upload JPEG(s), detect, embed, store profile
- `GET /vision/profiles` — list enrolled faces for user
- `DELETE /vision/profiles/:id` — remove person
- `POST /vision/enroll/capture` — trigger ESP32-CAM live capture for enrollment

**Recognition pipeline (WebSocket handler in gateway):**
- `vision:frame` binary → buffalo_l detect → crop → embed
- pgvector cosine search with threshold 0.4
- Push `face:identity` to paired aksabot device session

**ONNX model:** InsightFace buffalo_l (RetinaFace detector + ArcFace R50 recognizer). Models stored at `backend/models/buffalo_l/`. Loaded once on NestJS startup, resident in RAM (~1.5GB on 32GB VPS).

**New WebSocket events:**

Inbound (ESP32-CAM → backend):
- `vision:frame` — binary JPEG frame for recognition
- `vision:enroll_frames` — binary JPEG frames for enrollment (8 frames)

Outbound (backend → ESP32-CAM):
- `vision:start` — begin sending frames (conversation active)
- `vision:stop` — stop sending frames (conversation ended)
- `vision:capture` — capture 8 enrollment frames now
- `config:update {vision_mode: "always"|"conversation"}` — mode toggle

Outbound (backend → aksabot main):
- `face:identity {name: string, confidence: number, unknown: boolean}` — push identity to main device

**Gateway integration:**
- `SessionManager` gains `currentIdentity` field per device session
- `face:identity` event updates `currentIdentity`
- `AiOrchestrator` reads `currentIdentity` from session, injects into system prompt on each LLM call

## firmware-cam: WebSocket Integration

**New files:**
- `src/websocket.cpp/h` — ArduinoWebsockets client, connect on boot, auto-reconnect
- `src/vision.cpp/h` — 1fps frame send loop, event handler for vision:start/stop/capture/config:update

**Boot sequence:**
1. WiFi connect (existing)
2. `POST /devices/claim` with device token → register as camera-type device
3. WebSocket connect to `ws://<backend>/` with device token auth header
4. Vision loop starts in default mode (conversation-only)

**Vision modes:**
- **Conversation-only (default):** Idle until `vision:start` received. Send 1fps frames. Stop on `vision:stop`.
- **Always-on:** Send 1fps frames continuously regardless of conversation state.

**Enrollment capture:**
- On `vision:capture`: capture 8 JPEGs 500ms apart, send each as `vision:enroll_frames` binary message

**Frame format:** Raw JPEG binary. Message type identified by WebSocket message prefix byte or separate text event preceding binary.

**Credentials:** Device token in `firmware-cam/include/credentials.h` (same pattern as main firmware). Backend URL in same file.

## Flutter: Face Recognition UI

**New file:** `app/lib/features/devices/presentation/pages/face_recognition_page.dart`

**Access:** Device detail page → quick actions grid → "Face Recognition" tile

**New BLoC:** `VisionBloc` in `app/lib/features/devices/bloc/`
- Events: `LoadProfiles`, `EnrollFaceFromFile`, `EnrollFaceFromCamera`, `TriggerDeskCapture`, `DeleteProfile`, `ToggleVisionMode`
- States: `VisionLoading`, `VisionLoaded`, `VisionError`

**Page sections:**

1. **Mode toggle** — "Always on" vs "Conversation only" switch. PATCH device settings → backend pushes `config:update` to ESP32-CAM via existing config sync mechanism.

2. **Enrolled faces list** — Cards with name + thumbnail + delete button. Loaded via `GET /vision/profiles`.

3. **Add person (bottom sheet):**
   - Name text field
   - "Take photo" → `image_picker` camera → `POST /vision/enroll`
   - "Choose from gallery" → `image_picker` gallery → `POST /vision/enroll`
   - "Use desk camera" → `POST /vision/enroll/capture` → polling or WebSocket confirmation → success state
   - Upload progress indicator

**Dependencies:** `image_picker` (already likely in project), no new native dependencies needed.

## Recognition Threshold

- Distance < 0.4: confident match → inject person name
- Distance 0.4–0.6: low confidence → treat as unknown (do not inject wrong name)
- Distance > 0.6: unknown person

Threshold configurable via device settings in future but hardcoded at 0.4 for V1.

## ESP32-CAM Device Registration

ESP32-CAM registered as a separate device in the `devices` table with:
- `deviceType: "camera"` (new field or existing `settingsJson`)
- Paired to user account via device token claim flow (existing `POST /devices/claim`)
- Associated with main aksabot device via `settingsJson: { pairedDeviceId: "<aksabot-device-id>" }` — backend uses this to know which aksabot session to push `face:identity` to

## Out of Scope (V1)

- Multiple simultaneous face tracking (largest face in frame = primary)
- Face recognition accuracy metrics / false positive reporting
- Cloud backup of face embeddings
- Cross-user face profile sharing

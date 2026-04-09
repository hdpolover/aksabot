# 03 — Database Schema

---

## Overview

PostgreSQL database with six core tables. The schema is designed around device ownership: a user owns devices, devices have conversations, memories, and a pool of pre-generated responses.

---

## Entity relationship

```
users
  |-- 1:N --> devices
                |-- 1:N --> conversations
                |             |-- 1:N --> messages
                |
                |-- 1:N --> memories
                |
                |-- 1:N --> response_pool
```

---

## Tables

### users

User accounts for app login and device ownership.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, default gen_random_uuid() | User identifier |
| email | VARCHAR(255) | UNIQUE, NOT NULL | Login email |
| password_hash | VARCHAR(255) | NOT NULL | bcrypt hash |
| name | VARCHAR(100) | NOT NULL | Display name |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | Account creation time |
| updated_at | TIMESTAMPTZ | NOT NULL, default now() | Last update time |

### devices

Registered ESP32 devices linked to a user.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, default gen_random_uuid() | Device identifier |
| user_id | UUID | FK -> users.id, NOT NULL | Owner |
| name | VARCHAR(100) | NOT NULL, default 'My Bot' | User-facing device name |
| device_token | VARCHAR(255) | UNIQUE, NOT NULL | Auth token for WebSocket connection |
| token_revoked | BOOLEAN | NOT NULL, default false | Whether token has been revoked |
| wifi_ssid | VARCHAR(100) | | Last known Wi-Fi network |
| settings_json | JSONB | NOT NULL, default '{}' | Device settings (volume, brightness, etc.) |
| personality_json | JSONB | NOT NULL, default '{}' | Bot personality config (name, tone, quirks) |
| firmware_version | VARCHAR(20) | | Current firmware version reported by device |
| last_seen_at | TIMESTAMPTZ | | Last WebSocket connection time |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | Registration time |
| updated_at | TIMESTAMPTZ | NOT NULL, default now() | Last update time |

### conversations

Conversation sessions between a user and their device.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, default gen_random_uuid() | Conversation identifier |
| device_id | UUID | FK -> devices.id, NOT NULL | Which device this conversation happened on |
| started_at | TIMESTAMPTZ | NOT NULL, default now() | When the conversation started |
| ended_at | TIMESTAMPTZ | | When the conversation ended (null if ongoing) |

### messages

Individual messages within a conversation.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, default gen_random_uuid() | Message identifier |
| conversation_id | UUID | FK -> conversations.id, NOT NULL | Parent conversation |
| role | VARCHAR(20) | NOT NULL, CHECK (role IN ('user', 'assistant')) | Who said it |
| content | TEXT | NOT NULL | Transcript text |
| audio_url | VARCHAR(500) | | Optional link to stored audio file |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | Message timestamp |

Index: `(conversation_id, created_at)` for ordered message retrieval.

### memories

Long-term facts extracted from conversations, per device.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, default gen_random_uuid() | Memory identifier |
| device_id | UUID | FK -> devices.id, NOT NULL | Which device learned this |
| fact | TEXT | NOT NULL | The stored fact (e.g., "User's name is Hendra") |
| category | VARCHAR(50) | NOT NULL | Tag: preference, personal, work, hobby, etc. |
| source_message_id | UUID | FK -> messages.id | The message this fact was extracted from |
| confidence | DECIMAL(3,2) | NOT NULL, default 1.0, CHECK (0 <= confidence <= 1) | Confidence score, decays over time |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | When the fact was learned |
| last_accessed_at | TIMESTAMPTZ | NOT NULL, default now() | Last time this memory was used in context |

Index: `(device_id, confidence DESC)` for efficient memory retrieval by priority.

### response_pool

Pre-generated bot response variations for recurring interactions (reminders, greetings, etc.). Used to avoid calling Gemini for every reminder or greeting — the LLM generates responses in batches, and they're rotated by least-recently-used.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, default gen_random_uuid() | Response identifier |
| device_id | UUID | FK -> devices.id, NOT NULL | Per-device (responses use the device's personality/language) |
| category | VARCHAR(50) | NOT NULL | Response type: stand_up, hydration, eye_break, stretch, posture, welcome_back_short, welcome_back_long, pomodoro_break, pomodoro_focus, error |
| text | TEXT | NOT NULL | The response text |
| tts_cache_key | VARCHAR(100) | | Redis/SD cache key for the pre-generated TTS audio |
| use_count | INTEGER | NOT NULL, default 0 | How many times this response has been used |
| last_accessed_at | TIMESTAMPTZ | | Last time this response was served (null = never used) |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | When this response was generated |

Index: `(device_id, category, last_accessed_at NULLS FIRST)` for efficient LRU retrieval — responses that have never been used (NULL) come first, then oldest-accessed.

Key relationships:
- A **device** has many **response_pool** entries across different categories
- Responses are device-specific because they're generated with the device's personality and language

---

## Settings JSON structure

`devices.settings_json` follows this shape:

```json
{
  "volume": 80,
  "brightness": 100,
  "display_transcript": false,
  "idle_timeout_seconds": 300
}
```

## Personality JSON structure

`devices.personality_json` follows this shape:

```json
{
  "name": "Aksa",
  "tone": "friendly and slightly sarcastic",
  "language": "id",
  "system_prompt": "You are Aksa, a helpful desk companion. You speak Indonesian by default but can switch to English. You have a warm personality with a touch of humor."
}
```

---

## TypeORM entities

### User

```typescript
// src/database/entities/user.entity.ts
@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  email: string;

  @Column()
  passwordHash: string;

  @Column({ length: 100 })
  name: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  @OneToMany(() => Device, (device) => device.user)
  devices: Device[];
}
```

### Device

```typescript
// src/database/entities/device.entity.ts
@Entity('devices')
export class Device {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => User, (user) => user.devices, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column('uuid')
  userId: string;

  @Column({ length: 100, default: 'My Bot' })
  name: string;

  @Column({ unique: true })
  deviceToken: string;

  @Column({ default: false })
  tokenRevoked: boolean;

  @Column({ length: 100, nullable: true })
  wifiSsid: string;

  @Column({ type: 'jsonb', default: {} })
  settingsJson: Record<string, any>;

  @Column({ type: 'jsonb', default: {} })
  personalityJson: Record<string, any>;

  @Column({ length: 20, nullable: true })
  firmwareVersion: string;

  @Column({ nullable: true })
  lastSeenAt: Date;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  @OneToMany(() => Conversation, (conv) => conv.device)
  conversations: Conversation[];

  @OneToMany(() => Memory, (memory) => memory.device)
  memories: Memory[];
}
```

### Conversation

```typescript
// src/database/entities/conversation.entity.ts
@Entity('conversations')
export class Conversation {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Device, (device) => device.conversations, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'device_id' })
  device: Device;

  @Column('uuid')
  deviceId: string;

  @CreateDateColumn()
  startedAt: Date;

  @Column({ nullable: true })
  endedAt: Date;

  @OneToMany(() => Message, (message) => message.conversation)
  messages: Message[];
}
```

### Message

```typescript
// src/database/entities/message.entity.ts
@Entity('messages')
@Index(['conversationId', 'createdAt'])
export class Message {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Conversation, (conv) => conv.messages, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @Column('uuid')
  conversationId: string;

  @Column({ length: 20 })
  role: 'user' | 'assistant';

  @Column('text')
  content: string;

  @Column({ length: 500, nullable: true })
  audioUrl: string;

  @CreateDateColumn()
  createdAt: Date;
}
```

### Memory

```typescript
// src/database/entities/memory.entity.ts
@Entity('memories')
@Index(['deviceId', 'confidence'])
export class Memory {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Device, (device) => device.memories, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'device_id' })
  device: Device;

  @Column('uuid')
  deviceId: string;

  @Column('text')
  fact: string;

  @Column({ length: 50 })
  category: string;

  @ManyToOne(() => Message, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'source_message_id' })
  sourceMessage: Message;

  @Column('uuid', { nullable: true })
  sourceMessageId: string;

  @Column({ type: 'decimal', precision: 3, scale: 2, default: 1.0 })
  confidence: number;

  @CreateDateColumn()
  createdAt: Date;

  @Column({ type: 'timestamptz', default: () => 'now()' })
  lastAccessedAt: Date;
}
```

### ResponsePool

```typescript
// src/database/entities/response-pool.entity.ts
@Entity('response_pool')
@Index(['deviceId', 'category', 'lastAccessedAt'])
export class ResponsePool {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Device, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'device_id' })
  device: Device;

  @Column('uuid')
  deviceId: string;

  @Column({ length: 50 })
  category: string;

  @Column('text')
  text: string;

  @Column({ length: 100, nullable: true })
  ttsCacheKey: string;

  @Column({ default: 0 })
  useCount: number;

  @Column({ type: 'timestamptz', nullable: true })
  lastAccessedAt: Date;

  @CreateDateColumn()
  createdAt: Date;
}
```

---

## Migrations

Migrations should be created in order using TypeORM CLI (`typeorm migration:generate`):

1. `create_users` — users table
2. `create_devices` — devices table with FK to users
3. `create_conversations` — conversations table with FK to devices
4. `create_messages` — messages table with FK to conversations + composite index
5. `create_memories` — memories table with FKs to devices and messages + confidence index
6. `create_response_pool` — response_pool table with FK to devices + LRU index

### TypeORM config

```typescript
// src/database/data-source.ts
import { DataSource } from 'typeorm';

export const AppDataSource = new DataSource({
  type: 'postgres',
  host: process.env.DB_HOST ?? 'localhost',
  port: parseInt(process.env.DB_PORT ?? '5432'),
  username: process.env.DB_USER ?? 'aksabot',
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME ?? 'aksabot',
  entities: ['src/database/entities/*.entity.ts'],
  migrations: ['src/database/migrations/*.ts'],
  synchronize: false,  // always use migrations in production
});
```

```typescript
// src/database/database.module.ts
@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        host: config.get('DB_HOST', 'localhost'),
        port: config.get('DB_PORT', 5432),
        username: config.get('DB_USER', 'aksabot'),
        password: config.get('DB_PASSWORD'),
        database: config.get('DB_NAME', 'aksabot'),
        entities: [User, Device, Conversation, Message, Memory, ResponsePool],
        synchronize: false,
      }),
    }),
  ],
})
export class DatabaseModule {}
```

---

## Related docs

- [02-auth.md](02-auth.md) — How device_token and user credentials are used
- [06-backend-api.md](06-backend-api.md) — NestJS module structure and service layer
- [07-memory-service.md](07-memory-service.md) — How the memories table is populated and decayed

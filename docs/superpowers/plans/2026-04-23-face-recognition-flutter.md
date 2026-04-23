# Face Recognition — Flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Face Recognition page to the Flutter app where users can enroll faces (phone camera, gallery, or desk camera capture), manage enrolled profiles, and toggle the vision mode (always-on vs conversation-only).

**Architecture:** New `VisionBloc` manages state. `VisionRepository` calls backend REST endpoints (`/vision/profiles`, `/vision/enroll`, `/vision/enroll/capture`). New page `FaceRecognitionPage` accessible from device detail quick actions. Uses `image_picker` for photo capture.

**Tech Stack:** Flutter (FVM 3.41.6), BLoC pattern, `image_picker`, `dio` (existing HTTP client), existing JwtInterceptor for auth.

---

## File Structure

```
app/lib/
  features/devices/
    data/
      vision_repository.dart        ← CREATE
    bloc/
      vision_bloc.dart              ← CREATE
      vision_event.dart             ← CREATE
      vision_state.dart             ← CREATE
    presentation/pages/
      face_recognition_page.dart    ← CREATE
      device_detail_page.dart       ← MODIFY: add Face Recognition quick action
  core/di/
    injection_container.dart        ← MODIFY: register VisionBloc + VisionRepository
```

Check where existing repositories and blocs are registered. The project uses GetIt for DI based on the CLAUDE.md description of DevicesBloc being registered in GetIt.

---

## Task 1: VisionRepository

**Files:**
- Create: `app/lib/features/devices/data/vision_repository.dart`

- [ ] **Step 1: Write failing test**

Create `app/test/features/devices/data/vision_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:aksabot/features/devices/data/vision_repository.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late VisionRepository repository;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    repository = VisionRepository(dio: mockDio);
  });

  group('getProfiles', () {
    test('returns list of profiles on success', () async {
      when(() => mockDio.get('/vision/profiles')).thenAnswer(
        (_) async => Response(
          data: [
            {'id': 'fp1', 'name': 'Hendra', 'thumbnailUrl': null, 'createdAt': '2026-01-01T00:00:00Z'}
          ],
          statusCode: 200,
          requestOptions: RequestOptions(path: '/vision/profiles'),
        ),
      );
      final result = await repository.getProfiles();
      expect(result, hasLength(1));
      expect(result.first.name, 'Hendra');
    });
  });

  group('deleteProfile', () {
    test('calls DELETE endpoint', () async {
      when(() => mockDio.delete('/vision/profiles/fp1')).thenAnswer(
        (_) async => Response(
          statusCode: 204,
          requestOptions: RequestOptions(path: '/vision/profiles/fp1'),
        ),
      );
      await repository.deleteProfile('fp1');
      verify(() => mockDio.delete('/vision/profiles/fp1')).called(1);
    });
  });

  group('triggerDeskCapture', () {
    test('calls POST enroll/capture with deviceId and name', () async {
      when(() => mockDio.post(
            '/vision/enroll/capture',
            queryParameters: {'deviceId': 'cam-device-id'},
            data: {'name': 'Hendra'},
          )).thenAnswer(
        (_) async => Response(
          data: {'ok': true},
          statusCode: 201,
          requestOptions: RequestOptions(path: '/vision/enroll/capture'),
        ),
      );
      await repository.triggerDeskCapture(cameraDeviceId: 'cam-device-id', name: 'Hendra');
      verify(() => mockDio.post(
            '/vision/enroll/capture',
            queryParameters: {'deviceId': 'cam-device-id'},
            data: {'name': 'Hendra'},
          )).called(1);
    });
  });
}
```

Run: `cd app && flutter test test/features/devices/data/vision_repository_test.dart`
Expected: FAIL with "Target file not found" or import error.

- [ ] **Step 2: Create FaceProfile model**

Create `app/lib/features/devices/data/vision_repository.dart`:
```dart
import 'dart:io';
import 'package:dio/dio.dart';

class FaceProfileModel {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final DateTime createdAt;

  const FaceProfileModel({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory FaceProfileModel.fromJson(Map<String, dynamic> json) => FaceProfileModel(
        id: json['id'] as String,
        name: json['name'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class VisionRepository {
  final Dio dio;

  const VisionRepository({required this.dio});

  Future<List<FaceProfileModel>> getProfiles() async {
    final response = await dio.get<List<dynamic>>('/vision/profiles');
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(FaceProfileModel.fromJson)
        .toList();
  }

  Future<FaceProfileModel> enrollFromFile({required File photo, required String name}) async {
    final formData = FormData.fromMap({
      'photos': await MultipartFile.fromFile(photo.path, filename: 'photo.jpg'),
      'name': name,
    });
    final response = await dio.post<Map<String, dynamic>>(
      '/vision/enroll',
      data: formData,
    );
    return FaceProfileModel.fromJson(response.data!);
  }

  Future<void> triggerDeskCapture({
    required String cameraDeviceId,
    required String name,
  }) async {
    await dio.post(
      '/vision/enroll/capture',
      queryParameters: {'deviceId': cameraDeviceId},
      data: {'name': name},
    );
  }

  Future<void> deleteProfile(String profileId) async {
    await dio.delete('/vision/profiles/$profileId');
  }

  Future<void> setVisionMode({required String deviceId, required String mode}) async {
    await dio.patch(
      '/devices/$deviceId',
      data: {
        'settingsJson': {'vision_mode': mode},
      },
    );
  }
}
```

- [ ] **Step 3: Run test**

```bash
cd app && flutter test test/features/devices/data/vision_repository_test.dart
```
Expected: PASS

- [ ] **Step 4: Verify no analysis issues**

```bash
cd app && flutter analyze lib/features/devices/data/vision_repository.dart
```
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/devices/data/vision_repository.dart \
        app/test/features/devices/data/vision_repository_test.dart
git commit -m "feat(flutter): add VisionRepository (enroll, profiles, delete, mode toggle)"
```

---

## Task 2: VisionBloc

**Files:**
- Create: `app/lib/features/devices/bloc/vision_event.dart`
- Create: `app/lib/features/devices/bloc/vision_state.dart`
- Create: `app/lib/features/devices/bloc/vision_bloc.dart`

- [ ] **Step 1: Write failing test**

Create `app/test/features/devices/bloc/vision_bloc_test.dart`:
```dart
import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aksabot/features/devices/bloc/vision_bloc.dart';
import 'package:aksabot/features/devices/bloc/vision_event.dart';
import 'package:aksabot/features/devices/bloc/vision_state.dart';
import 'package:aksabot/features/devices/data/vision_repository.dart';

class MockVisionRepository extends Mock implements VisionRepository {}
class MockFile extends Mock implements File {}

final tProfile = FaceProfileModel(
  id: 'fp1',
  name: 'Hendra',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late MockVisionRepository mockRepo;

  setUp(() {
    mockRepo = MockVisionRepository();
  });

  group('LoadProfiles', () {
    blocTest<VisionBloc, VisionState>(
      'emits [VisionLoading, VisionLoaded] on success',
      build: () {
        when(() => mockRepo.getProfiles()).thenAnswer((_) async => [tProfile]);
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const LoadProfiles()),
      expect: () => [
        isA<VisionLoading>(),
        isA<VisionLoaded>().having((s) => s.profiles, 'profiles', hasLength(1)),
      ],
    );

    blocTest<VisionBloc, VisionState>(
      'emits [VisionLoading, VisionError] on failure',
      build: () {
        when(() => mockRepo.getProfiles()).thenThrow(Exception('network error'));
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const LoadProfiles()),
      expect: () => [isA<VisionLoading>(), isA<VisionError>()],
    );
  });

  group('DeleteProfile', () {
    blocTest<VisionBloc, VisionState>(
      'reloads profiles after delete',
      build: () {
        when(() => mockRepo.deleteProfile('fp1')).thenAnswer((_) async {});
        when(() => mockRepo.getProfiles()).thenAnswer((_) async => []);
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const DeleteProfile(profileId: 'fp1')),
      expect: () => [
        isA<VisionLoading>(),
        isA<VisionLoaded>().having((s) => s.profiles, 'profiles', isEmpty),
      ],
    );
  });

  group('ToggleVisionMode', () {
    blocTest<VisionBloc, VisionState>(
      'updates mode and reloads',
      build: () {
        when(() => mockRepo.setVisionMode(deviceId: 'dev1', mode: 'always'))
            .thenAnswer((_) async {});
        when(() => mockRepo.getProfiles()).thenAnswer((_) async => [tProfile]);
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const ToggleVisionMode(deviceId: 'dev1', mode: 'always')),
      expect: () => [
        isA<VisionLoading>(),
        isA<VisionLoaded>(),
      ],
    );
  });
}
```

Run: `cd app && flutter test test/features/devices/bloc/vision_bloc_test.dart`
Expected: FAIL with import errors.

- [ ] **Step 2: Create vision_event.dart**

Create `app/lib/features/devices/bloc/vision_event.dart`:
```dart
import 'dart:io';
import 'package:equatable/equatable.dart';

abstract class VisionEvent extends Equatable {
  const VisionEvent();
  @override
  List<Object?> get props => [];
}

class LoadProfiles extends VisionEvent {
  const LoadProfiles();
}

class EnrollFromFile extends VisionEvent {
  final File photo;
  final String name;
  const EnrollFromFile({required this.photo, required this.name});
  @override
  List<Object?> get props => [photo.path, name];
}

class TriggerDeskCapture extends VisionEvent {
  final String cameraDeviceId;
  final String name;
  const TriggerDeskCapture({required this.cameraDeviceId, required this.name});
  @override
  List<Object?> get props => [cameraDeviceId, name];
}

class DeleteProfile extends VisionEvent {
  final String profileId;
  const DeleteProfile({required this.profileId});
  @override
  List<Object?> get props => [profileId];
}

class ToggleVisionMode extends VisionEvent {
  final String deviceId;
  final String mode; // 'always' | 'conversation'
  const ToggleVisionMode({required this.deviceId, required this.mode});
  @override
  List<Object?> get props => [deviceId, mode];
}
```

- [ ] **Step 3: Create vision_state.dart**

Create `app/lib/features/devices/bloc/vision_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:aksabot/features/devices/data/vision_repository.dart';

abstract class VisionState extends Equatable {
  const VisionState();
  @override
  List<Object?> get props => [];
}

class VisionInitial extends VisionState {
  const VisionInitial();
}

class VisionLoading extends VisionState {
  const VisionLoading();
}

class VisionLoaded extends VisionState {
  final List<FaceProfileModel> profiles;
  const VisionLoaded({required this.profiles});
  @override
  List<Object?> get props => [profiles];
}

class VisionError extends VisionState {
  final String message;
  const VisionError({required this.message});
  @override
  List<Object?> get props => [message];
}

class VisionEnrolling extends VisionState {
  const VisionEnrolling();
}

class VisionEnrollSuccess extends VisionState {
  final String name;
  const VisionEnrollSuccess({required this.name});
  @override
  List<Object?> get props => [name];
}
```

- [ ] **Step 4: Create vision_bloc.dart**

Create `app/lib/features/devices/bloc/vision_bloc.dart`:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:aksabot/features/devices/data/vision_repository.dart';
import 'vision_event.dart';
import 'vision_state.dart';

class VisionBloc extends Bloc<VisionEvent, VisionState> {
  final VisionRepository repository;

  VisionBloc({required this.repository}) : super(const VisionInitial()) {
    on<LoadProfiles>(_onLoadProfiles);
    on<EnrollFromFile>(_onEnrollFromFile);
    on<TriggerDeskCapture>(_onTriggerDeskCapture);
    on<DeleteProfile>(_onDeleteProfile);
    on<ToggleVisionMode>(_onToggleVisionMode);
  }

  Future<void> _onLoadProfiles(LoadProfiles event, Emitter<VisionState> emit) async {
    emit(const VisionLoading());
    try {
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onEnrollFromFile(EnrollFromFile event, Emitter<VisionState> emit) async {
    emit(const VisionEnrolling());
    try {
      await repository.enrollFromFile(photo: event.photo, name: event.name);
      emit(VisionEnrollSuccess(name: event.name));
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onTriggerDeskCapture(TriggerDeskCapture event, Emitter<VisionState> emit) async {
    emit(const VisionEnrolling());
    try {
      await repository.triggerDeskCapture(
        cameraDeviceId: event.cameraDeviceId,
        name: event.name,
      );
      emit(VisionEnrollSuccess(name: event.name));
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onDeleteProfile(DeleteProfile event, Emitter<VisionState> emit) async {
    emit(const VisionLoading());
    try {
      await repository.deleteProfile(event.profileId);
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onToggleVisionMode(ToggleVisionMode event, Emitter<VisionState> emit) async {
    emit(const VisionLoading());
    try {
      await repository.setVisionMode(deviceId: event.deviceId, mode: event.mode);
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }
}
```

- [ ] **Step 5: Run test**

```bash
cd app && flutter test test/features/devices/bloc/vision_bloc_test.dart
```
Expected: PASS (all tests)

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/devices/bloc/vision_event.dart \
        app/lib/features/devices/bloc/vision_state.dart \
        app/lib/features/devices/bloc/vision_bloc.dart \
        app/test/features/devices/bloc/vision_bloc_test.dart
git commit -m "feat(flutter): add VisionBloc (load, enroll, delete, mode toggle)"
```

---

## Task 3: FaceRecognitionPage

**Files:**
- Create: `app/lib/features/devices/presentation/pages/face_recognition_page.dart`

- [ ] **Step 1: Add image_picker dependency**

Check if `image_picker` is already in `app/pubspec.yaml`. If not:
```bash
cd app && flutter pub add image_picker
```

Add iOS permission in `app/ios/Runner/Info.plist` (if not present):
```xml
<key>NSCameraUsageDescription</key>
<string>Used to enroll your face for recognition by Aksabot.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to select a photo for face enrollment.</string>
```

Add Android permission in `app/android/app/src/main/AndroidManifest.xml` (if not present):
```xml
<uses-permission android:name="android.permission.CAMERA" />
```

- [ ] **Step 2: Create FaceRecognitionPage**

Create `app/lib/features/devices/presentation/pages/face_recognition_page.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:aksabot/features/devices/bloc/vision_bloc.dart';
import 'package:aksabot/features/devices/bloc/vision_event.dart';
import 'package:aksabot/features/devices/bloc/vision_state.dart';
import 'package:aksabot/features/devices/data/vision_repository.dart';
import 'dart:io';

class FaceRecognitionPage extends StatefulWidget {
  final String deviceId;          // aksabot main device ID
  final String? cameraDeviceId;   // ESP32-CAM device ID (null if not paired)
  final String visionMode;        // 'conversation' | 'always'

  const FaceRecognitionPage({
    super.key,
    required this.deviceId,
    this.cameraDeviceId,
    required this.visionMode,
  });

  @override
  State<FaceRecognitionPage> createState() => _FaceRecognitionPageState();
}

class _FaceRecognitionPageState extends State<FaceRecognitionPage> {
  late String _currentMode;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentMode = widget.visionMode;
    context.read<VisionBloc>().add(const LoadProfiles());
  }

  void _showAddPersonSheet() {
    final nameController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Person', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            _enrollOption(
              icon: Icons.camera_alt,
              label: 'Take photo',
              onTap: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(sheetCtx);
                final xFile = await _picker.pickImage(source: ImageSource.camera);
                if (xFile != null && mounted) {
                  context.read<VisionBloc>().add(
                    EnrollFromFile(photo: File(xFile.path), name: name),
                  );
                }
              },
            ),
            _enrollOption(
              icon: Icons.photo_library,
              label: 'Choose from gallery',
              onTap: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(sheetCtx);
                final xFile = await _picker.pickImage(source: ImageSource.gallery);
                if (xFile != null && mounted) {
                  context.read<VisionBloc>().add(
                    EnrollFromFile(photo: File(xFile.path), name: name),
                  );
                }
              },
            ),
            if (widget.cameraDeviceId != null)
              _enrollOption(
                icon: Icons.videocam,
                label: 'Use desk camera',
                onTap: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(sheetCtx);
                  context.read<VisionBloc>().add(
                    TriggerDeskCapture(
                      cameraDeviceId: widget.cameraDeviceId!,
                      name: name,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _enrollOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: onTap,
      );

  void _confirmDelete(BuildContext ctx, FaceProfileModel profile) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Remove person'),
        content: Text('Remove ${profile.name} from face recognition?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ctx.read<VisionBloc>().add(DeleteProfile(profileId: profile.id));
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Recognition')),
      body: BlocConsumer<VisionBloc, VisionState>(
        listener: (ctx, state) {
          if (state is VisionEnrollSuccess) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text('${state.name} enrolled successfully')),
            );
          }
          if (state is VisionError) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text('Error: ${state.message}'), backgroundColor: Colors.red),
            );
          }
        },
        builder: (ctx, state) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Mode toggle
            Card(
              child: SwitchListTile(
                title: const Text('Always-on mode'),
                subtitle: const Text(
                  'When off, face recognition only runs during conversations.',
                ),
                value: _currentMode == 'always',
                onChanged: (value) {
                  final newMode = value ? 'always' : 'conversation';
                  setState(() => _currentMode = newMode);
                  ctx.read<VisionBloc>().add(
                    ToggleVisionMode(deviceId: widget.deviceId, mode: newMode),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Profiles list
            Row(
              children: [
                Text('Enrolled People',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (state is VisionLoading || state is VisionEnrolling)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (state is VisionLoaded && state.profiles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No people enrolled yet.')),
              ),

            if (state is VisionLoaded)
              ...state.profiles.map(
                (p) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                    title: Text(p.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDelete(ctx, p),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPersonSheet,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Person'),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify no analysis issues**

```bash
cd app && flutter analyze lib/features/devices/presentation/pages/face_recognition_page.dart
```
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/devices/presentation/pages/face_recognition_page.dart
git commit -m "feat(flutter): add FaceRecognitionPage (enroll, profiles list, mode toggle)"
```

---

## Task 4: DI Registration + Device Detail Integration

**Files:**
- Modify: `app/lib/core/di/injection_container.dart` (or wherever GetIt registrations live)
- Modify: `app/lib/features/devices/presentation/pages/device_detail_page.dart`

- [ ] **Step 1: Find DI file**

Search for the GetIt registration file:
```bash
grep -r "GetIt\|get_it\|sl\." app/lib/core/ --include="*.dart" -l
```

Open the file found.

- [ ] **Step 2: Register VisionRepository and VisionBloc**

In the DI registration file, add (following the existing pattern for other repositories and blocs):
```dart
import 'package:aksabot/features/devices/data/vision_repository.dart';
import 'package:aksabot/features/devices/bloc/vision_bloc.dart';

// In your setup function, alongside other registrations:
sl.registerLazySingleton<VisionRepository>(
  () => VisionRepository(dio: sl<Dio>()),
);

sl.registerFactory<VisionBloc>(
  () => VisionBloc(repository: sl<VisionRepository>()),
);
```

- [ ] **Step 3: Add Face Recognition tile to device detail quick actions**

Open `app/lib/features/devices/presentation/pages/device_detail_page.dart`.

Find the quick actions grid (look for existing tiles like "Settings", "Battery", "Presence"). Add a Face Recognition tile following the same pattern:

```dart
// Import at top of file:
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:aksabot/features/devices/bloc/vision_bloc.dart';
import 'package:aksabot/features/devices/presentation/pages/face_recognition_page.dart';

// In the quick actions list/grid, add:
QuickActionTile(  // use existing tile widget class
  icon: Icons.face,
  label: 'Face Recognition',
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => sl<VisionBloc>(),
        child: FaceRecognitionPage(
          deviceId: device.id,
          // cameraDeviceId: set from device.settingsJson['pairedCameraDeviceId'] if available
          cameraDeviceId: device.settingsJson?['pairedCameraDeviceId'] as String?,
          visionMode: (device.settingsJson?['vision_mode'] as String?) ?? 'conversation',
        ),
      ),
    ),
  ),
),
```

- [ ] **Step 4: Run full Flutter test suite**

```bash
cd app && flutter test
```
Expected: All existing 60 tests pass + new vision tests pass. Zero failures.

- [ ] **Step 5: Verify zero analysis issues**

```bash
cd app && flutter analyze
```
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/di/injection_container.dart \
        app/lib/features/devices/presentation/pages/device_detail_page.dart
git commit -m "feat(flutter): wire VisionBloc into DI + add Face Recognition entry in device detail"
```

---

## Self-Review

**Spec coverage:**
- ✅ Enrolled faces list — Task 3 (VisionLoaded state → profile cards)
- ✅ Add person: take photo — Task 3 (image_picker camera)
- ✅ Add person: choose from gallery — Task 3 (image_picker gallery)
- ✅ Add person: use desk camera — Task 3 (TriggerDeskCapture event)
- ✅ Delete person — Task 3 (DeleteProfile event + confirm dialog)
- ✅ Mode toggle always/conversation — Task 3 (SwitchListTile)
- ✅ VisionBloc events: Load, EnrollFromFile, TriggerDeskCapture, Delete, ToggleMode — Task 2
- ✅ VisionRepository: all 5 API methods — Task 1
- ✅ DI registration — Task 4
- ✅ Device detail entry point — Task 4
- ✅ BLoC tests — Tasks 1, 2

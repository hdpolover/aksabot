import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../bloc/vision_bloc.dart';
import '../bloc/vision_event.dart';
import '../bloc/vision_state.dart';
import '../../data/repositories/vision_repository.dart';

const _minPhotos = 5;

class FaceRecognitionPage extends StatefulWidget {
  final String deviceId;
  final String? cameraDeviceId;
  final String visionMode;

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

  @override
  void initState() {
    super.initState();
    _currentMode = widget.visionMode;
    context.read<VisionBloc>().add(const LoadProfiles());
  }

  void _showEnrollSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EnrollSheet(
        cameraDeviceId: widget.cameraDeviceId,
        onEnroll: (name, photos) {
          Navigator.pop(context);
          context.read<VisionBloc>().add(EnrollFromFiles(photos: photos, name: name));
        },
        onDeskCapture: widget.cameraDeviceId != null
            ? (name) {
                Navigator.pop(context);
                context.read<VisionBloc>().add(
                  TriggerDeskCapture(cameraDeviceId: widget.cameraDeviceId!, name: name),
                );
              }
            : null,
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, FaceProfileModel profile) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Remove person'),
        content: Text('Remove ${profile.name}?'),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Face Recognition')),
      body: BlocConsumer<VisionBloc, VisionState>(
        listener: (ctx, state) {
          if (state is VisionEnrollSuccess) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text('${state.name} enrolled')),
            );
          }
          if (state is VisionError) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: cs.error,
              ),
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
                subtitle: const Text('When off, recognition only runs during conversations.'),
                value: _currentMode == 'always',
                onChanged: (val) {
                  final mode = val ? 'always' : 'conversation';
                  setState(() => _currentMode = mode);
                  ctx.read<VisionBloc>().add(
                    ToggleVisionMode(deviceId: widget.deviceId, mode: mode),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Profiles header
            Row(
              children: [
                Text('Enrolled People', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (state is VisionLoading || state is VisionEnrolling)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (state is VisionEnrolling)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('Enrolling…', style: TextStyle(color: Colors.grey))),
              ),

            if (state is VisionLoaded && state.profiles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No people enrolled yet.')),
              ),

            if (state is VisionLoaded)
              ...state.profiles.map(
                (p) => Card(
                  child: ListTile(
                    leading: p.thumbnailUrl != null
                        ? ClipOval(
                            child: Image.network(
                              p.thumbnailUrl!,
                              width: 40, height: 40, fit: BoxFit.cover,
                              errorBuilder: (context, e, s) => _initials(p.name),
                            ),
                          )
                        : _initials(p.name),
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
        onPressed: _showEnrollSheet,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Person'),
      ),
    );
  }

  Widget _initials(String name) => CircleAvatar(child: Text(name[0].toUpperCase()));
}

// ── Enrollment bottom sheet ───────────────────────────────────────────────────

class _EnrollSheet extends StatefulWidget {
  final String? cameraDeviceId;
  final void Function(String name, List<File> photos) onEnroll;
  final void Function(String name)? onDeskCapture;

  const _EnrollSheet({
    required this.cameraDeviceId,
    required this.onEnroll,
    this.onDeskCapture,
  });

  @override
  State<_EnrollSheet> createState() => _EnrollSheetState();
}

class _EnrollSheetState extends State<_EnrollSheet> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  final List<File> _photos = [];
  bool _enrolling = false; // ignore: prefer_final_fields

  bool get _canEnroll => _photos.length >= _minPhotos && _nameController.text.trim().isNotEmpty;

  Future<void> _addFromCamera() async {
    final xFile = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (xFile != null) setState(() => _photos.add(File(xFile.path)));
  }

  Future<void> _addFromGallery() async {
    final xFiles = await _picker.pickMultiImage(imageQuality: 90);
    if (xFiles.isNotEmpty) {
      setState(() => _photos.addAll(xFiles.map((f) => File(f.path))));
    }
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _photos.length < _minPhotos) return;
    widget.onEnroll(name, List.unmodifiable(_photos));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _photos.length;
    final needed = (_minPhotos - count).clamp(0, _minPhotos);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Person', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),

          // Name field
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Photo count indicator
          Row(
            children: [
              Text(
                '$count / $_minPhotos photos',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: count >= _minPhotos ? cs.primary : cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              if (needed > 0)
                Text(
                  'Add $needed more for enrollment',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              if (count >= _minPhotos)
                Icon(Icons.check_circle, color: cs.primary, size: 18),
            ],
          ),
          const SizedBox(height: 8),

          // Photo grid
          if (_photos.isNotEmpty) ...[
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (context, i) => const SizedBox(width: 6),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_photos[i], width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2, right: 2,
                      child: GestureDetector(
                        onTap: () => _removePhoto(i),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Add photo buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addFromCamera,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addFromGallery,
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Gallery'),
                ),
              ),
              if (widget.onDeskCapture != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a name first')),
                        );
                        return;
                      }
                      widget.onDeskCapture!(name);
                    },
                    icon: const Icon(Icons.videocam, size: 18),
                    label: const Text('Desk cam'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Enroll button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _canEnroll && !_enrolling ? _submit : null,
              child: Text(_enrolling
                  ? 'Enrolling…'
                  : _canEnroll
                      ? 'Enroll ${_nameController.text.trim()} (${_photos.length} photos)'
                      : 'Add $_minPhotos+ photos to enroll'),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../bloc/vision_bloc.dart';
import '../bloc/vision_event.dart';
import '../bloc/vision_state.dart';
import '../../data/repositories/vision_repository.dart';

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

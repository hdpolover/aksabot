import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/memory_entity.dart';
import '../bloc/memories_bloc.dart';
import '../../../../core/di/injection.dart';

/// Page displaying a device's extracted memories, grouped by category.
///
/// Supports filtering via chips, swipe-to-delete, and tap-to-edit.
class MemoriesPage extends StatelessWidget {
  final String deviceId;

  const MemoriesPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<MemoriesBloc>()..add(LoadMemories(deviceId)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Memories')),
        body: BlocBuilder<MemoriesBloc, MemoriesState>(
          builder: (context, state) {
            if (state is MemoriesLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is MemoriesError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => context.read<MemoriesBloc>().add(LoadMemories(deviceId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            if (state is MemoriesLoaded) {
              if (state.memories.isEmpty) {
                return const Center(child: Text('No memories yet.'));
              }
              return _MemoriesContent(
                memories: state.memories,
                selectedCategory: state.selectedCategory,
                deviceId: deviceId,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _MemoriesContent extends StatelessWidget {
  final List<Memory> memories;
  final String? selectedCategory;
  final String deviceId;

  const _MemoriesContent({
    required this.memories,
    required this.selectedCategory,
    required this.deviceId,
  });

  Set<String> get _categories => memories.map((m) => m.category).toSet();

  Map<String, List<Memory>> get _grouped {
    final map = <String, List<Memory>>{};
    for (final memory in memories) {
      map.putIfAbsent(memory.category, () => []).add(memory);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final sortedCategories = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () async {
        context.read<MemoriesBloc>().add(LoadMemories(deviceId, category: selectedCategory));
      },
      child: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: selectedCategory == null,
                  onSelected: (_) => context.read<MemoriesBloc>().add(LoadMemories(deviceId)),
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: selectedCategory == cat,
                        onSelected: (_) {
                          final newCat = selectedCategory == cat ? null : cat;
                          context.read<MemoriesBloc>().add(LoadMemories(deviceId, category: newCat));
                        },
                      ),
                    )),
              ],
            ),
          ),
          // Grouped list
          Expanded(
            child: ListView.builder(
              itemCount: sortedCategories.length,
              itemBuilder: (context, index) {
                final category = sortedCategories[index];
                final items = grouped[category]!;
                return _CategorySection(
                  category: category,
                  memories: items,
                  deviceId: deviceId,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String category;
  final List<Memory> memories;
  final String deviceId;

  const _CategorySection({
    required this.category,
    required this.memories,
    required this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            category,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...memories.map(
          (memory) => Dismissible(
            key: ValueKey(memory.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: theme.colorScheme.error,
              child: Icon(Icons.delete, color: theme.colorScheme.onError),
            ),
            confirmDismiss: (_) => showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete memory?'),
                content: Text(memory.fact),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
            onDismissed: (_) =>
                context.read<MemoriesBloc>().add(DeleteMemory(memory.id)),
            child: ListTile(
              onTap: () => _editMemory(context, memory),
              title: Text(memory.fact),
              subtitle: Text(
                'Confidence: ${(memory.confidence * 100).toStringAsFixed(0)}%',
              ),
              trailing: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editMemory(BuildContext context, Memory memory) async {
    final factController = TextEditingController(text: memory.fact);
    final categoryController = TextEditingController(text: memory.category);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: factController,
              decoration: const InputDecoration(labelText: 'Fact'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true || !context.mounted) return;

    final newFact = factController.text.trim();
    final newCategory = categoryController.text.trim();

    context.read<MemoriesBloc>().add(UpdateMemory(
      memory.id,
      fact: newFact != memory.fact ? newFact : null,
      category: newCategory != memory.category ? newCategory : null,
    ));
  }
}

import 'package:flutter/material.dart';

import '../../domain/entities/memory_entity.dart';
import '../../domain/repositories/memories_repository.dart';
import '../../../../core/di/injection.dart';

/// Page displaying a device's extracted memories, grouped by category.
///
/// Supports filtering via chips, swipe-to-delete, and tap-to-edit.
class MemoriesPage extends StatefulWidget {
  final String deviceId;

  const MemoriesPage({super.key, required this.deviceId});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  late final MemoriesRepository _repository;

  List<Memory> _memories = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _repository = sl<MemoriesRepository>();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _repository.getMemories(
      widget.deviceId,
      category: _selectedCategory,
    );
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _isLoading = false;
      }),
      (memories) => setState(() {
        _memories = memories;
        _isLoading = false;
      }),
    );
  }

  Set<String> get _categories =>
      _memories.map((m) => m.category).toSet();

  Map<String, List<Memory>> get _grouped {
    final map = <String, List<Memory>>{};
    for (final memory in _memories) {
      map.putIfAbsent(memory.category, () => []).add(memory);
    }
    return map;
  }

  Future<void> _deleteMemory(Memory memory) async {
    final result = await _repository.deleteMemory(memory.id);
    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${failure.message}')),
        );
      },
      (_) {
        setState(() => _memories.remove(memory));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Memory deleted')),
        );
      },
    );
  }

  Future<void> _editMemory(Memory memory) async {
    final factController = TextEditingController(text: memory.fact);
    final categoryController = TextEditingController(text: memory.category);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true) return;

    final newFact = factController.text.trim();
    final newCategory = categoryController.text.trim();

    final result = await _repository.updateMemory(
      memory.id,
      fact: newFact != memory.fact ? newFact : null,
      category: newCategory != memory.category ? newCategory : null,
    );

    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: ${failure.message}')),
        );
      },
      (_) => _loadMemories(),
    );
  }

  void _onCategorySelected(String? category) {
    setState(() => _selectedCategory = category);
    _loadMemories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memories')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadMemories,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_memories.isEmpty) {
      return const Center(
        child: Text('No memories yet.'),
      );
    }

    final grouped = _grouped;
    final sortedCategories = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _loadMemories,
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
                  selected: _selectedCategory == null,
                  onSelected: (_) => _onCategorySelected(null),
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        onSelected: (_) => _onCategorySelected(
                          _selectedCategory == cat ? null : cat,
                        ),
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
                  onDelete: _deleteMemory,
                  onEdit: _editMemory,
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
  final ValueChanged<Memory> onDelete;
  final ValueChanged<Memory> onEdit;

  const _CategorySection({
    required this.category,
    required this.memories,
    required this.onDelete,
    required this.onEdit,
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
            onDismissed: (_) => onDelete(memory),
            child: ListTile(
              onTap: () => onEdit(memory),
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
}

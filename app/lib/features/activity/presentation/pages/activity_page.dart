import 'package:flutter/material.dart';

import '../../../conversations/domain/entities/conversation_entity.dart';
import '../../../conversations/domain/entities/message_entity.dart';
import '../../../conversations/domain/repositories/conversations_repository.dart';
import '../../../devices/domain/repositories/devices_repository.dart';
import '../../../memories/domain/entities/memory_entity.dart';
import '../../../memories/domain/repositories/memories_repository.dart';
import '../../../../core/di/injection.dart';

/// Activity tab with segmented toggle between Conversations and Memories.
///
/// If the user has multiple devices, this shows data across all devices.
/// For now, it requires a device selection — we default to the first device
/// from the devices repository.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  int _selectedSegment = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Conversations'),
                  icon: Icon(Icons.chat_bubble_outline),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Memories'),
                  icon: Icon(Icons.psychology),
                ),
              ],
              selected: {_selectedSegment},
              onSelectionChanged: (selection) {
                setState(() => _selectedSegment = selection.first);
              },
              style: SegmentedButton.styleFrom(
                selectedForegroundColor: theme.colorScheme.onPrimary,
                selectedBackgroundColor: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: _selectedSegment == 0
                ? const _ConversationsView()
                : const _MemoriesView(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversations view (inlined from ConversationsPage logic)
// ---------------------------------------------------------------------------

class _ConversationsView extends StatefulWidget {
  const _ConversationsView();

  @override
  State<_ConversationsView> createState() => _ConversationsViewState();
}

class _ConversationsViewState extends State<_ConversationsView> {
  late final ConversationsRepository _repository;

  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;
  String? _expandedId;
  final Map<String, List<Message>> _messagesCache = {};
  final Set<String> _loadingMessages = {};

  // TODO: when multi-device support is added, let the user pick a device.
  // For now we attempt to load conversations for the first device via the
  // devices repository, but Activity is accessible even without a device.
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _repository = sl<ConversationsRepository>();
    _resolveDeviceAndLoad();
  }

  Future<void> _resolveDeviceAndLoad() async {
    // Resolve the first device to load its conversations.
    final devicesResult = await sl<DevicesRepository>().getDevices();
    devicesResult.fold(
      (_) => setState(() => _isLoading = false),
      (devices) {
        if (devices.isNotEmpty) {
          _deviceId = devices.first.id;
          _loadConversations();
        } else {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  Future<void> _loadConversations() async {
    if (_deviceId == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await _repository.getConversations(_deviceId!);
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _isLoading = false;
      }),
      (conversations) => setState(() {
        _conversations = conversations;
        _isLoading = false;
      }),
    );
  }

  Future<void> _loadMessages(String conversationId) async {
    if (_messagesCache.containsKey(conversationId)) return;
    setState(() => _loadingMessages.add(conversationId));
    final result = await _repository.getMessages(conversationId);
    result.fold(
      (_) => null,
      (messages) => _messagesCache[conversationId] = messages,
    );
    setState(() => _loadingMessages.remove(conversationId));
  }

  void _toggleExpanded(String conversationId) {
    setState(() {
      if (_expandedId == conversationId) {
        _expandedId = null;
      } else {
        _expandedId = conversationId;
        _loadMessages(conversationId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_deviceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 48, color: colors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'View conversations from your device dashboard',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: colors.error)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadConversations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Text(
          'No conversations yet.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conversation = _conversations[index];
          final isExpanded = _expandedId == conversation.id;
          return _ConversationTile(
            conversation: conversation,
            isExpanded: isExpanded,
            isLoadingMessages: _loadingMessages.contains(conversation.id),
            messages: _messagesCache[conversation.id],
            onTap: () => _toggleExpanded(conversation.id),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool isExpanded;
  final bool isLoadingMessages;
  final List<Message>? messages;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.isExpanded,
    required this.isLoadingMessages,
    required this.messages,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = conversation.duration;
    final durationText = duration != null
        ? _formatDuration(duration)
        : 'Ongoing';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          ListTile(
            onTap: onTap,
            leading: Icon(
              conversation.endedAt != null
                  ? Icons.chat_bubble_outline
                  : Icons.chat_bubble,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              _formatDate(conversation.startedAt),
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text('Duration: $durationText'),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
          ),
          if (isExpanded) _buildMessages(context),
        ],
      ),
    );
  }

  Widget _buildMessages(BuildContext context) {
    if (isLoadingMessages) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final msgs = messages;
    if (msgs == null || msgs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No messages.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...msgs.map((msg) => _MessageBubble(message: msg)),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final mins = d.inMinutes % 60;
      return '${d.inHours}h ${mins}m';
    }
    if (d.inMinutes > 0) {
      final secs = d.inSeconds % 60;
      return '${d.inMinutes}m ${secs}s';
    }
    return '${d.inSeconds}s';
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'You' : 'Aksa',
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(message.content),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Memories view (inlined from MemoriesPage logic)
// ---------------------------------------------------------------------------

class _MemoriesView extends StatefulWidget {
  const _MemoriesView();

  @override
  State<_MemoriesView> createState() => _MemoriesViewState();
}

class _MemoriesViewState extends State<_MemoriesView> {
  late final MemoriesRepository _repository;

  List<Memory> _memories = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCategory;

  // Same device resolution issue as conversations.
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _repository = sl<MemoriesRepository>();
    _resolveDeviceAndLoad();
  }

  Future<void> _resolveDeviceAndLoad() async {
    final devicesResult = await sl<DevicesRepository>().getDevices();
    devicesResult.fold(
      (_) => setState(() => _isLoading = false),
      (devices) {
        if (devices.isNotEmpty) {
          _deviceId = devices.first.id;
          _loadMemories();
        } else {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  Future<void> _loadMemories() async {
    if (_deviceId == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await _repository.getMemories(
      _deviceId!,
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

  Set<String> get _categories => _memories.map((m) => m.category).toSet();

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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Memory deleted')));
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

    final result = await _repository.updateMemory(
      memory.id,
      fact: factController.text.trim() != memory.fact
          ? factController.text.trim()
          : null,
      category: categoryController.text.trim() != memory.category
          ? categoryController.text.trim()
          : null,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_deviceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.psychology, size: 48, color: colors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'View memories from your device dashboard',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: colors.error)),
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
      return Center(
        child: Text(
          'No memories yet.',
          style:
              theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }

    final grouped = _grouped;
    final sortedCategories = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _loadMemories,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _selectedCategory == null,
                  onSelected: (_) {
                    setState(() => _selectedCategory = null);
                    _loadMemories();
                  },
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        onSelected: (_) {
                          setState(() => _selectedCategory =
                              _selectedCategory == cat ? null : cat);
                          _loadMemories();
                        },
                      ),
                    )),
              ],
            ),
          ),
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

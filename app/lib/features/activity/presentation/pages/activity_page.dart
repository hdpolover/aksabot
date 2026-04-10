import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../conversations/domain/entities/conversation_entity.dart';
import '../../../conversations/domain/entities/message_entity.dart';
import '../../../conversations/presentation/bloc/conversations_bloc.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/domain/repositories/devices_repository.dart';
import '../../../memories/domain/entities/memory_entity.dart';
import '../../../memories/presentation/bloc/memories_bloc.dart';
import '../../../../core/di/injection.dart';

/// Activity tab with segmented toggle between Conversations and Memories.
///
/// Shows a device picker when the user has multiple devices.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  int _selectedSegment = 0;
  List<Device> _devices = [];
  Device? _selectedDevice;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final result = await sl<DevicesRepository>().getDevices();
    result.fold(
      (_) => setState(() => _resolving = false),
      (devices) {
        setState(() {
          _devices = devices;
          _selectedDevice = devices.isNotEmpty ? devices.first : null;
          _resolving = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          if (_devices.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedDevice?.id,
                  icon: Icon(Icons.smart_toy_outlined, color: colors.onSurface),
                  items: _devices.map((d) {
                    return DropdownMenuItem(
                      value: d.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.smart_toy_outlined, size: 16, color: colors.primary),
                          const SizedBox(width: 8),
                          Text(d.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (deviceId) {
                    if (deviceId == null) return;
                    final device = _devices.firstWhere((d) => d.id == deviceId);
                    setState(() => _selectedDevice = device);
                  },
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_resolving) {
      return const Center(child: CircularProgressIndicator());
    }

    final colors = theme.colorScheme;

    if (_selectedDevice == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 48, color: colors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Add a device to see activity',
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

    return Column(
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
              selectedForegroundColor: colors.onPrimary,
              selectedBackgroundColor: colors.primary,
            ),
          ),
        ),
        Expanded(
          child: _selectedSegment == 0
              ? _ConversationsView(
                  key: ValueKey('conv_${_selectedDevice!.id}'),
                  deviceId: _selectedDevice!.id,
                )
              : _MemoriesView(
                  key: ValueKey('mem_${_selectedDevice!.id}'),
                  deviceId: _selectedDevice!.id,
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Conversations view (uses ConversationsBloc)
// ---------------------------------------------------------------------------

class _ConversationsView extends StatelessWidget {
  final String deviceId;

  const _ConversationsView({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return BlocProvider(
      create: (_) => sl<ConversationsBloc>()..add(LoadConversations(deviceId)),
      child: BlocBuilder<ConversationsBloc, ConversationsState>(
        builder: (context, state) {
          if (state is ConversationsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ConversationsError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, style: TextStyle(color: colors.error)),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => context.read<ConversationsBloc>().add(LoadConversations(deviceId)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (state is ConversationsLoaded) {
            if (state.conversations.isEmpty) {
              return Center(
                child: Text(
                  'No conversations yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              );
            }
            return _ConversationsList(
              conversations: state.conversations,
              messagesCache: state.messagesCache,
              deviceId: deviceId,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _ConversationsList extends StatefulWidget {
  final List<Conversation> conversations;
  final Map<String, List<Message>> messagesCache;
  final String deviceId;

  const _ConversationsList({
    required this.conversations,
    required this.messagesCache,
    required this.deviceId,
  });

  @override
  State<_ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends State<_ConversationsList> {
  String? _expandedId;

  void _toggleExpanded(String conversationId) {
    setState(() {
      if (_expandedId == conversationId) {
        _expandedId = null;
      } else {
        _expandedId = conversationId;
        context.read<ConversationsBloc>().add(LoadMessages(conversationId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ConversationsBloc>().add(LoadConversations(widget.deviceId));
      },
      child: ListView.builder(
        itemCount: widget.conversations.length,
        itemBuilder: (context, index) {
          final conversation = widget.conversations[index];
          final isExpanded = _expandedId == conversation.id;
          return _ConversationTile(
            conversation: conversation,
            isExpanded: isExpanded,
            messages: widget.messagesCache[conversation.id],
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
  final List<Message>? messages;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.isExpanded,
    required this.messages,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = conversation.duration;
    final durationText = duration != null ? _formatDuration(duration) : 'Ongoing';

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
    final msgs = messages;
    if (msgs == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (msgs.isEmpty) {
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
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
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
// Memories view (uses MemoriesBloc)
// ---------------------------------------------------------------------------

class _MemoriesView extends StatelessWidget {
  final String deviceId;

  const _MemoriesView({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return BlocProvider(
      create: (_) => sl<MemoriesBloc>()..add(LoadMemories(deviceId)),
      child: BlocBuilder<MemoriesBloc, MemoriesState>(
        builder: (context, state) {
          if (state is MemoriesLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is MemoriesError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, style: TextStyle(color: colors.error)),
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
              return Center(
                child: Text(
                  'No memories yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              );
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
          Expanded(
            child: ListView.builder(
              itemCount: sortedCategories.length,
              itemBuilder: (context, index) {
                final category = sortedCategories[index];
                final items = grouped[category]!;
                return _CategorySection(
                  category: category,
                  memories: items,
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

  const _CategorySection({
    required this.category,
    required this.memories,
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
              title: Text(memory.fact),
              subtitle: Text(
                'Confidence: ${(memory.confidence * 100).toStringAsFixed(0)}%',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

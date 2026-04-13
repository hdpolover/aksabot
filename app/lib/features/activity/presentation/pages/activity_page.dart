import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../conversations/domain/entities/conversation_entity.dart';
import '../../../conversations/presentation/bloc/conversations_bloc.dart';
import '../../../conversations/presentation/pages/conversation_detail_page.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/domain/repositories/devices_repository.dart';
import '../../../memories/domain/entities/memory_entity.dart';
import '../../../memories/presentation/bloc/memories_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/empty_state.dart';

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
      return const AppLoadingIndicator();
    }

    if (_selectedDevice == null) {
      return const EmptyState(
        icon: Icons.smart_toy_outlined,
        title: 'No devices yet',
        subtitle: 'Add a device from the Home tab to see conversations and memories.',
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
              selectedForegroundColor: theme.colorScheme.onPrimary,
              selectedBackgroundColor: theme.colorScheme.primary,
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
            return const AppLoadingIndicator();
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
              return const EmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'No conversations',
                subtitle: 'Start talking to Aksa and your conversations will appear here.',
              );
            }
            return _ConversationsList(
              conversations: state.conversations,
              deviceId: deviceId,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _ConversationsList extends StatelessWidget {
  final List<Conversation> conversations;
  final String deviceId;

  const _ConversationsList({
    required this.conversations,
    required this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ConversationsBloc>().add(LoadConversations(deviceId));
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          return Dismissible(
            key: ValueKey(conversation.id),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.onError,
              ),
            ),
            confirmDismiss: (_) => showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Delete conversation?'),
                content: const Text(
                  'This will permanently remove the conversation and all its messages.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
            onDismissed: (_) {
              context
                  .read<ConversationsBloc>()
                  .add(DeleteConversation(conversation.id));
            },
            child: _ConversationTile(conversation: conversation),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isOngoing = conversation.endedAt == null;
    final duration = conversation.duration;

    // Build subtitle: preview text + message count
    final preview = conversation.preview;
    final count = conversation.messageCount;
    final countLabel = '$count msg${count == 1 ? '' : 's'}';
    final subtitleText = (preview != null && preview.isNotEmpty)
        ? '$preview · $countLabel'
        : countLabel;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: context.read<ConversationsBloc>(),
              child: ConversationDetailPage(conversation: conversation),
            ),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor:
              isOngoing ? colors.primaryContainer : colors.surfaceContainerHigh,
          child: Icon(
            isOngoing ? Icons.chat_bubble : Icons.chat_bubble_outline,
            size: 18,
            color: isOngoing ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
        title: Text(
          _formatDate(conversation.startedAt),
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOngoing)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Live',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.primary),
                ),
              )
            else if (duration != null)
              Text(
                _formatDuration(duration),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: colors.outlineVariant),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final d = date.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(d.year, d.month, d.day);
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    if (dateOnly == today) return 'Today at $timeStr';
    if (dateOnly == yesterday) return 'Yesterday at $timeStr';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (d.year == now.year) {
      return '${months[d.month - 1]} ${d.day} at $timeStr';
    }
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
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
    return BlocProvider(
      create: (_) => sl<MemoriesBloc>()..add(LoadMemories(deviceId)),
      child: _MemoriesViewBody(deviceId: deviceId),
    );
  }
}

class _MemoriesViewBody extends StatelessWidget {
  final String deviceId;
  const _MemoriesViewBody({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return BlocConsumer<MemoriesBloc, MemoriesState>(
      listenWhen: (prev, curr) {
        if (curr is! MemoriesLoaded || prev is! MemoriesLoaded) return false;
        return prev.scanning && !curr.scanning;
      },
      listener: (context, state) {
        if (state is MemoriesLoaded) {
          final extracted = state.lastScanExtracted;
          final msg = extracted == null
              ? 'Scan failed'
              : extracted == 0
                  ? 'No new memories found'
                  : 'Extracted $extracted new ${extracted == 1 ? 'memory' : 'memories'}';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      },
      builder: (context, state) {
        if (state is MemoriesLoading) {
          return const AppLoadingIndicator();
        }
        if (state is MemoriesError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message, style: TextStyle(color: colors.error)),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () =>
                      context.read<MemoriesBloc>().add(LoadMemories(deviceId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (state is MemoriesLoaded) {
          final scanning = state.scanning;
          return Column(
            children: [
              // Scan action bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (scanning)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Scanning...'),
                        ],
                      )
                    else
                      TextButton.icon(
                        onPressed: () => context
                            .read<MemoriesBloc>()
                            .add(ScanMemories(deviceId)),
                        icon: const Icon(Icons.manage_search_rounded, size: 18),
                        label: const Text('Scan for memories'),
                      ),
                  ],
                ),
              ),
              if (state.memories.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.psychology_outlined,
                    title: 'No memories',
                    subtitle:
                        'Aksa will remember things about you as you chat.',
                  ),
                )
              else
                Expanded(
                  child: _MemoriesContent(
                    memories: state.memories,
                    selectedCategory: state.selectedCategory,
                    deviceId: deviceId,
                  ),
                ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../conversations/domain/entities/conversation_entity.dart';
import '../../../conversations/presentation/bloc/conversations_bloc.dart';
import '../../../conversations/presentation/pages/conversation_detail_page.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/domain/repositories/devices_repository.dart';
import '../../../memories/domain/entities/memory_entity.dart';
import '../../../memories/presentation/bloc/memories_bloc.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/empty_state.dart';

/// Activity tab — segmented Conversations / Memories view with device picker.
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
      (devices) => setState(() {
        _devices = devices;
        _selectedDevice = devices.isNotEmpty ? devices.first : null;
        _resolving = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _selectedDevice == null
            ? const Text('Activity')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Activity'),
                  Text(
                    _selectedDevice!.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
        actions: [
          if (_devices.length > 1) _DevicePicker(
            devices: _devices,
            selected: _selectedDevice,
            onChanged: (d) => setState(() => _selectedDevice = d),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_resolving) return const AppLoadingIndicator();

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
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingLg, AppConstants.spacingSm,
            AppConstants.spacingLg, AppConstants.spacingXs,
          ),
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
                icon: Icon(Icons.psychology_outlined),
              ),
            ],
            selected: {_selectedSegment},
            onSelectionChanged: (s) => setState(() => _selectedSegment = s.first),
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
// Device picker (multi-device)
// ---------------------------------------------------------------------------

class _DevicePicker extends StatelessWidget {
  final List<Device> devices;
  final Device? selected;
  final ValueChanged<Device> onChanged;

  const _DevicePicker({
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: AppConstants.spacingSm),
      child: PopupMenuButton<String>(
        tooltip: 'Switch device',
        initialValue: selected?.id,
        onSelected: (id) => onChanged(devices.firstWhere((d) => d.id == id)),
        itemBuilder: (_) => devices.map((d) {
          final isSelected = d.id == selected?.id;
          return PopupMenuItem<String>(
            value: d.id,
            child: Row(
              children: [
                Icon(
                  d.isOnline ? Icons.smart_toy : Icons.smart_toy_outlined,
                  size: AppConstants.iconSm,
                  color: d.isOnline ? colors.primary : colors.outline,
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Text(
                  d.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : null,
                    color: isSelected ? colors.primary : null,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(Icons.check, size: AppConstants.iconSm, color: colors.primary),
                ],
              ],
            ),
          );
        }).toList(),
        child: Chip(
          avatar: Icon(
            Icons.smart_toy_outlined,
            size: AppConstants.iconSm,
            color: colors.onSecondaryContainer,
          ),
          label: Text(
            selected?.name ?? '',
            style: theme.textTheme.labelMedium,
          ),
          side: BorderSide.none,
          backgroundColor: colors.secondaryContainer,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversations view
// ---------------------------------------------------------------------------

class _ConversationsView extends StatelessWidget {
  final String deviceId;

  const _ConversationsView({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return BlocProvider(
      create: (_) => sl<ConversationsBloc>()..add(LoadConversations(deviceId)),
      child: BlocBuilder<ConversationsBloc, ConversationsState>(
        builder: (context, state) {
          if (state is ConversationsLoading) return const AppLoadingIndicator();

          if (state is ConversationsError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, style: TextStyle(color: colors.error)),
                  const SizedBox(height: AppConstants.spacingLg),
                  FilledButton.tonal(
                    onPressed: () => context
                        .read<ConversationsBloc>()
                        .add(LoadConversations(deviceId)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is ConversationsLoaded) {
            // Filter handshake-only sessions (< 30s), same as conversations_page.dart
            final real = state.conversations.where((c) {
              if (c.endedAt == null) return true;
              return c.duration!.inSeconds >= 30;
            }).toList();

            if (real.isEmpty) {
              return const EmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'No conversations',
                subtitle: 'Start talking to Aksa and your conversations will appear here.',
              );
            }

            return RefreshIndicator(
              onRefresh: () async =>
                  context.read<ConversationsBloc>().add(LoadConversations(deviceId)),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingLg,
                  vertical: AppConstants.spacingSm,
                ),
                itemCount: real.length,
                itemBuilder: (context, index) {
                  final conv = real[index];
                  return Dismissible(
                    key: ValueKey(conv.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusMd),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: AppConstants.spacingXl),
                      child: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                    confirmDismiss: (_) => AppDialog.confirm(
                      context,
                      title: 'Delete conversation?',
                      body: 'This will permanently remove the conversation and all its messages.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    ),
                    onDismissed: (_) => context
                        .read<ConversationsBloc>()
                        .add(DeleteConversation(conv.id)),
                    child: _ConversationCard(
                      conversation: conv,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: context.read<ConversationsBloc>(),
                            child: ConversationDetailPage(conversation: conv),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

/// Conversation card — matches the design in conversations_page.dart.
class _ConversationCard extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationCard({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ac = theme.extension<AppColors>()!;
    final isOngoing = conversation.endedAt == null;
    final duration = conversation.duration;

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOngoing
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(
                  isOngoing ? Icons.chat_bubble : Icons.chat_bubble_outline,
                  size: AppConstants.iconMd,
                  color: isOngoing
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppConstants.radiusMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatDate(conversation.startedAt),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (conversation.guestMode) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.spacingXs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ac.warningContainer,
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusSm),
                            ),
                            child: Text(
                              'Guest',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: ac.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppConstants.spacingXs),
                        ],
                        if (isOngoing)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.spacingXs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusSm),
                            ),
                            child: Text(
                              'Live',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          )
                        else if (duration != null)
                          Text(
                            _formatDuration(duration),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (conversation.preview != null &&
                        conversation.preview!.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.spacingXs),
                      Text(
                        conversation.preview!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (conversation.messageCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${conversation.messageCount} '
                        '${conversation.messageCount == 1 ? 'message' : 'messages'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
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
    if (d.year == now.year) return '${months[d.month - 1]} ${d.day} at $timeStr';
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}

// ---------------------------------------------------------------------------
// Memories view
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
                  : 'Extracted $extracted new '
                      '${extracted == 1 ? 'memory' : 'memories'}';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      },
      builder: (context, state) {
        if (state is MemoriesLoading) return const AppLoadingIndicator();

        if (state is MemoriesError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message, style: TextStyle(color: colors.error)),
                const SizedBox(height: AppConstants.spacingLg),
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
          return Column(
            children: [
              // Scan action bar
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingLg, AppConstants.spacingXs,
                  AppConstants.spacingLg, 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${state.memories.length} '
                      '${state.memories.length == 1 ? 'memory' : 'memories'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    if (state.scanning)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: AppConstants.spacingSm),
                          Text('Scanning...'),
                        ],
                      )
                    else
                      TextButton.icon(
                        onPressed: () => context
                            .read<MemoriesBloc>()
                            .add(ScanMemories(deviceId)),
                        icon: const Icon(Icons.manage_search_rounded, size: 16),
                        label: const Text('Scan'),
                      ),
                  ],
                ),
              ),
              if (state.memories.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.psychology_outlined,
                    title: 'No memories yet',
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
    for (final m in memories) {
      map.putIfAbsent(m.category, () => []).add(m);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final sortedCategories = grouped.keys.toList()..sort();
    final categories = _categories.toList()..sort();

    return Column(
      children: [
        // Category filter chips — outside RefreshIndicator (not scrollable itself)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLg,
            vertical: AppConstants.spacingSm,
          ),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All'),
                selected: selectedCategory == null,
                onSelected: (_) =>
                    context.read<MemoriesBloc>().add(LoadMemories(deviceId)),
              ),
              ...categories.map(
                (cat) => Padding(
                  padding:
                      const EdgeInsets.only(left: AppConstants.spacingSm),
                  child: FilterChip(
                    label: Text(cat),
                    selected: selectedCategory == cat,
                    onSelected: (_) {
                      final next = selectedCategory == cat ? null : cat;
                      context
                          .read<MemoriesBloc>()
                          .add(LoadMemories(deviceId, category: next));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Memories list — RefreshIndicator wraps only the scrollable ListView
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => context
                .read<MemoriesBloc>()
                .add(LoadMemories(deviceId, category: selectedCategory)),
            child: ListView.builder(
              padding: const EdgeInsets.only(
                bottom: AppConstants.spacingXxxl,
              ),
              itemCount: sortedCategories.length,
              itemBuilder: (context, index) {
                final category = sortedCategories[index];
                return _CategorySection(
                  category: category,
                  memories: grouped[category]!,
                  deviceId: deviceId,
                );
              },
            ),
          ),
        ),
      ],
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
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingLg,
            AppConstants.spacingLg,
            AppConstants.spacingLg,
            AppConstants.spacingXs,
          ),
          child: Text(
            category,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...memories.map(
          (memory) => _DismissibleMemory(memory: memory),
        ),
      ],
    );
  }
}

class _DismissibleMemory extends StatelessWidget {
  final Memory memory;

  const _DismissibleMemory({required this.memory});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Dismissible(
      key: ValueKey(memory.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingLg,
          vertical: AppConstants.spacingXs,
        ),
        decoration: BoxDecoration(
          color: colors.error,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.spacingXl),
        child: Icon(Icons.delete_outline, color: colors.onError),
      ),
      confirmDismiss: (_) => AppDialog.confirm(
        context,
        title: 'Delete memory?',
        body: memory.fact,
        confirmLabel: 'Delete',
        destructive: true,
      ),
      onDismissed: (_) =>
          context.read<MemoriesBloc>().add(DeleteMemory(memory.id)),
      child: _MemoryCard(memory: memory),
    );
  }
}

/// Memory card with confidence indicator and edit action.
class _MemoryCard extends StatelessWidget {
  final Memory memory;

  const _MemoryCard({required this.memory});

  Color _confidenceColor(double confidence, ColorScheme colors) {
    if (confidence >= 0.7) return colors.primary;
    if (confidence >= 0.4) return colors.tertiary;
    return colors.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final pct = (memory.confidence * 100).round();
    final confColor = _confidenceColor(memory.confidence, colors);
    final date = memory.createdAt.toLocal();

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingLg,
        vertical: AppConstants.spacingXs,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingLg,
          AppConstants.radiusMd,
          AppConstants.spacingSm,
          AppConstants.radiusMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fact text
                  Text(
                    memory.fact,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppConstants.spacingSm),
                  // Confidence bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusFull),
                          child: LinearProgressIndicator(
                            value: memory.confidence,
                            backgroundColor:
                                colors.surfaceContainerHighest,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(confColor),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingSm),
                      Text(
                        '$pct%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: confColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacingXs),
                  // Created date
                  Text(
                    _formatDate(date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.outline,
                    ),
                  ),
                ],
              ),
            ),
            // Edit button
            IconButton(
              onPressed: () => _showEditDialog(context),
              icon: const Icon(Icons.edit_outlined),
              iconSize: AppConstants.iconMd,
              color: colors.onSurfaceVariant,
              tooltip: 'Edit memory',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final bloc = context.read<MemoriesBloc>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditMemoryDialog(initialText: memory.fact),
    );

    if (result != null && result.isNotEmpty && result != memory.fact) {
      bloc.add(UpdateMemory(memory.id, fact: result));
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Edit memory dialog ────────────────────────────────────────────────────────

/// Owns its TextEditingController so dispose() is tied to the widget lifecycle,
/// not the caller — avoids "controller used after dispose" during exit animation.
class _EditMemoryDialog extends StatefulWidget {
  final String initialText;
  const _EditMemoryDialog({required this.initialText});

  @override
  State<_EditMemoryDialog> createState() => _EditMemoryDialogState();
}

class _EditMemoryDialogState extends State<_EditMemoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit memory'),
      content: TextField(
        controller: _controller,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Memory fact',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

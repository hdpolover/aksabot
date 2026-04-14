import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/conversation_entity.dart';
import '../bloc/conversations_bloc.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import 'conversation_detail_page.dart';

class ConversationsPage extends StatelessWidget {
  final String deviceId;

  const ConversationsPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ConversationsBloc>()..add(LoadConversations(deviceId)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Conversations')),
        body: BlocBuilder<ConversationsBloc, ConversationsState>(
          builder: (context, state) {
            if (state is ConversationsLoading) {
              return const AppLoadingIndicator();
            }
            if (state is ConversationsError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
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
              // Filter out very short conversations (< 30s) — those are just
              // connection handshakes, not real conversations
              final real = state.conversations.where((c) {
                if (c.endedAt == null) return true; // ongoing = show
                return c.duration!.inSeconds >= 30;
              }).toList();

              if (real.isEmpty) {
                return const Center(child: Text('No conversations yet.'));
              }
              return RefreshIndicator(
                onRefresh: () async {
                  context
                      .read<ConversationsBloc>()
                      .add(LoadConversations(deviceId));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: real.length,
                  itemBuilder: (context, index) {
                    final conversation = real[index];
                    return Dismissible(
                      key: ValueKey(conversation.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
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
                      onDismissed: (_) {
                        context
                            .read<ConversationsBloc>()
                            .add(DeleteConversation(conversation.id));
                      },
                      child: _ConversationCard(
                        conversation: conversation,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BlocProvider.value(
                              value: context.read<ConversationsBloc>(),
                              child: ConversationDetailPage(
                                  conversation: conversation),
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
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationCard({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isOngoing = conversation.endedAt == null;
    final duration = conversation.duration;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOngoing
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(
                  isOngoing ? Icons.chat_bubble : Icons.chat_bubble_outline,
                  size: 20,
                  color: isOngoing
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
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
                        Text(
                          isOngoing
                              ? 'Ongoing'
                              : _formatDuration(duration!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isOngoing
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (conversation.preview != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        conversation.preview!.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim(),
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
                        '${conversation.messageCount} messages',
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

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
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

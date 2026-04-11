import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../bloc/conversations_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';

/// Page displaying a device's conversation history.
///
/// Each conversation can be tapped to expand and show its messages inline.
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
                    Text(state.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                return const Center(child: Text('No conversations yet.'));
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
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(message.content),
          ],
        ),
      ),
    );
  }
}

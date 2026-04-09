import 'package:flutter/material.dart';

import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversations_repository.dart';
import '../../../../core/di/injection.dart';

/// Page displaying a device's conversation history.
///
/// Each conversation can be tapped to expand and show its messages inline.
class ConversationsPage extends StatefulWidget {
  final String deviceId;

  const ConversationsPage({super.key, required this.deviceId});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  late final ConversationsRepository _repository;

  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  /// Tracks which conversation is currently expanded.
  String? _expandedId;

  /// Cached messages per conversation id.
  final Map<String, List<Message>> _messagesCache = {};

  /// Tracks loading state for individual message fetches.
  final Set<String> _loadingMessages = {};

  @override
  void initState() {
    super.initState();
    _repository = sl<ConversationsRepository>();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _repository.getConversations(widget.deviceId);
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
      (_) => null, // Silently fail — the user can tap again.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Conversations')),
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
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
      return const Center(
        child: Text('No conversations yet.'),
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
        ? '${duration.inMinutes}m ${duration.inSeconds % 60}s'
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

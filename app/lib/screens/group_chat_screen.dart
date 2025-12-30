import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../providers/group_provider.dart';
import '../models/models.dart';
import '../services/identity_service.dart';
import 'group_info_screen.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupChatScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  String? _replyToId;

  @override
  void initState() {
    super.initState();
    // Mark as read when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupActionsProvider).markAsRead(widget.groupId);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    final messagesAsync = ref.watch(groupMessagesProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(
        title: groupAsync.when(
          data: (group) {
            if (group == null) return const Text('Group');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  '${group.memberCount} members',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDarkSecondary,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            );
          },
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Error'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupInfoScreen(groupId: widget.groupId),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const _EmptyGroupMessages();
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final previousMessage = index < messages.length - 1
                        ? messages[messages.length - 2 - index]
                        : null;
                    final showSenderName = !message.isOutgoing &&
                        (previousMessage == null ||
                            previousMessage.senderId != message.senderId);

                    return groupAsync.when(
                      data: (group) => _GroupMessageBubble(
                        message: message,
                        group: group,
                        showSenderName: showSenderName,
                        onReply: () => _setReplyTo(message),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),

          // Reply indicator
          if (_replyToId != null) _ReplyIndicator(onCancel: _cancelReply),

          // Input
          _MessageInput(
            controller: _textController,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  void _setReplyTo(Message message) {
    setState(() {
      _replyToId = message.id;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyToId = null;
    });
  }

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    final replyTo = _replyToId;
    _cancelReply();

    await ref.read(groupActionsProvider).sendMessage(
          groupId: widget.groupId,
          content: text,
          replyToId: replyTo,
        );
  }
}

class _EmptyGroupMessages extends StatelessWidget {
  const _EmptyGroupMessages();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_outlined,
            size: 48,
            color: AppColors.textDarkSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'Group messages are end-to-end encrypted',
            style: TextStyle(
              color: AppColors.textDarkSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: TextStyle(
              color: AppColors.textDarkSecondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupMessageBubble extends StatelessWidget {
  final Message message;
  final Group? group;
  final bool showSenderName;
  final VoidCallback onReply;

  const _GroupMessageBubble({
    required this.message,
    required this.group,
    required this.showSenderName,
    required this.onReply,
  });

  String _getSenderDisplayName() {
    if (message.isOutgoing) return 'You';

    // Check if sender is in group members
    if (group != null) {
      final member = group!.getMember(message.senderId ?? '');
      if (member != null) {
        return member.displayText;
      }
    }

    // Fallback to truncated node ID
    final senderId = message.senderId ?? 'Unknown';
    if (senderId.length > 8) {
      return senderId.substring(0, 8);
    }
    return senderId;
  }

  Color _getSenderColor() {
    // Generate consistent color based on sender ID
    final senderId = message.senderId ?? 'Unknown';
    final hash = senderId.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sender avatar for incoming messages
          if (!isOutgoing) ...[
            if (showSenderName)
              CircleAvatar(
                radius: 14,
                backgroundColor: _getSenderColor().withOpacity(0.2),
                child: Text(
                  _getSenderDisplayName()[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _getSenderColor(),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const SizedBox(width: 28), // Placeholder for alignment
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onLongPress: () => _showMessageOptions(context),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.70,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isOutgoing
                    ? AppColors.primary
                    : AppColors.bgDarkSecondary,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
                  bottomRight: Radius.circular(isOutgoing ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name for incoming messages
                  if (!isOutgoing && showSenderName) ...[
                    Text(
                      _getSenderDisplayName(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getSenderColor(),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  // Message content
                  if (message.isDeleted)
                    Text(
                      'Message deleted',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: isOutgoing
                            ? Colors.white.withOpacity(0.7)
                            : AppColors.textDarkSecondary,
                      ),
                    )
                  else
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isOutgoing
                            ? Colors.white
                            : AppColors.textDark,
                      ),
                    ),
                  const SizedBox(height: 4),
                  // Timestamp and status
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.timeString,
                        style: TextStyle(
                          fontSize: 11,
                          color: isOutgoing
                              ? Colors.white.withOpacity(0.7)
                              : AppColors.textDarkSecondary,
                        ),
                      ),
                      if (message.isEdited) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(edited)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isOutgoing
                                ? Colors.white.withOpacity(0.7)
                                : AppColors.textDarkSecondary,
                          ),
                        ),
                      ],
                      if (isOutgoing) ...[
                        const SizedBox(width: 4),
                        Text(
                          message.status.icon,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDarkSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDarkSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  onReply();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  // TODO: Copy to clipboard
                  Navigator.pop(context);
                },
              ),
              if (message.isOutgoing && !message.isDeleted) ...[
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    // TODO: Edit message
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text('Delete', style: TextStyle(color: AppColors.error)),
                  onTap: () {
                    // TODO: Delete message
                    Navigator.pop(context);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _ReplyIndicator extends StatelessWidget {
  final VoidCallback onCancel;

  const _ReplyIndicator({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgDarkSecondary,
        border: Border(
          top: BorderSide(
            color: AppColors.bgDarkTertiary,
          ),
          left: BorderSide(
            color: AppColors.primary,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Replying to message',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textDarkSecondary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onCancel,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: AppColors.textDarkSecondary,
          ),
        ],
      ),
    );
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _MessageInput({
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        border: Border(
          top: BorderSide(
            color: AppColors.bgDarkTertiary,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              color: AppColors.textDarkSecondary,
              onPressed: () {
                // TODO: Attach file
              },
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.bgDarkSecondary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: AppColors.textDarkSecondary),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: TextStyle(color: AppColors.textDark),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send),
                color: Colors.white,
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

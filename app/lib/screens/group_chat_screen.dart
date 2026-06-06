import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../providers/group_provider.dart';
import '../providers/conversation_provider.dart';
import '../models/models.dart';
import '../services/identity_service.dart';
import '../services/group_service.dart';
import '../widgets/media_message_content.dart';
import 'group_info_screen.dart';
import 'group_media_gallery_screen.dart';

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
  Message? _editingMessage;
  dynamic _messageSubscription;

  @override
  void initState() {
    super.initState();
    // Mark as read when opening and refresh messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Force refresh messages from database in case new ones arrived
      // while the group chat screen was not active
      ref.invalidate(groupMessagesProvider(widget.groupId));
      ref.read(groupActionsProvider).markAsRead(widget.groupId);
      _setupMessageListener();
    });
  }

  /// Listen for incoming group messages and refresh UI
  void _setupMessageListener() {
    // Direct stream subscription for reliable real-time updates
    _messageSubscription = GroupService.instance.messageStream.listen((message) {
      if (message.conversationId == widget.groupId && mounted) {
        ref.invalidate(groupMessagesProvider(widget.groupId));
        setState(() {});
      }
      ref.invalidate(groupsProvider);
      ref.invalidate(conversationsProvider);
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    final messagesAsync = ref.watch(groupMessagesProvider(widget.groupId));
    final pinnedCountAsync = ref.watch(pinnedMessagesCountProvider(widget.groupId));

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
          // Pinned messages banner
          pinnedCountAsync.when(
            data: (count) {
              if (count == 0) return const SizedBox.shrink();
              return _PinnedMessagesBanner(
                groupId: widget.groupId,
                count: count,
                onTap: () => _showPinnedMessages(context),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

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
                        onEdit: _showEditDialog,
                        onDelete: _deleteMessage,
                        onPin: _togglePin,
                        onForward: _showForwardDialog,
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

          // Edit indicator
          if (_editingMessage != null)
            _EditIndicator(
              message: _editingMessage!,
              onCancel: _cancelEdit,
            ),

          // Reply indicator
          if (_replyToId != null && _editingMessage == null)
            _ReplyIndicator(onCancel: _cancelReply),

          // Input
          _MessageInput(
            controller: _textController,
            onSend: _editingMessage != null ? _submitEdit : _sendMessage,
            isEditing: _editingMessage != null,
            onAttachFile: _pickFile,
            onAttachImage: _pickImage,
            onOpenGallery: _openMediaGallery,
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

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null || file.bytes == null && file.path == null) {
        _showError('Could not read file');
        return;
      }

      final bytes = file.bytes ?? await _readFileBytes(file.path!);
      if (bytes == null) {
        _showError('Could not read file');
        return;
      }

      // Check file size (max 10MB)
      if (bytes.length > 10 * 1024 * 1024) {
        _showError('File too large (max 10MB)');
        return;
      }

      await ref.read(groupActionsProvider).sendFile(
        groupId: widget.groupId,
        filename: file.name,
        fileData: bytes,
        localPath: file.path,
      );
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        _showError('Could not read image');
        return;
      }

      final bytes = file.bytes ?? await _readFileBytes(file.path!);
      if (bytes == null) {
        _showError('Could not read image');
        return;
      }

      // Check file size (max 10MB)
      if (bytes.length > 10 * 1024 * 1024) {
        _showError('Image too large (max 10MB)');
        return;
      }

      // TODO: Get actual image dimensions
      await ref.read(groupActionsProvider).sendImage(
        groupId: widget.groupId,
        filename: file.name,
        imageData: bytes,
        width: 800,
        height: 600,
        localPath: file.path,
      );
    } catch (e) {
      _showError('Error picking image: $e');
    }
  }

  Future<List<int>?> _readFileBytes(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return bytes;
    } catch (e) {
      return null;
    }
  }

  void _openMediaGallery() {
    final groupAsync = ref.read(groupProvider(widget.groupId));
    final groupName = groupAsync.valueOrNull?.name ?? 'Group';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupMediaGalleryScreen(
          groupId: widget.groupId,
          groupName: groupName,
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showEditDialog(Message message) {
    setState(() {
      _editingMessage = message;
      _textController.text = message.content;
      _replyToId = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _textController.clear();
    });
  }

  void _submitEdit() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _editingMessage == null) return;

    final message = _editingMessage!;
    _textController.clear();
    _cancelEdit();

    final groupService = ref.read(groupServiceProvider);
    final success = await groupService.editMessage(
      groupId: widget.groupId,
      messageId: message.id,
      newContent: text,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to edit message'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      // Refresh messages
      ref.invalidate(groupMessagesProvider(widget.groupId));
    }
  }

  void _deleteMessage(Message message, bool deleteForAll) async {
    final groupService = ref.read(groupServiceProvider);
    final success = await groupService.deleteMessage(
      groupId: widget.groupId,
      messageId: message.id,
      deleteForAll: deleteForAll,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete message'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      // Refresh messages
      ref.invalidate(groupMessagesProvider(widget.groupId));
    }
  }

  void _togglePin(Message message) async {
    final groupService = ref.read(groupServiceProvider);
    final isPinned = await groupService.isMessagePinned(
      groupId: widget.groupId,
      messageId: message.id,
    );

    bool success;
    if (isPinned) {
      success = await groupService.unpinMessage(
        groupId: widget.groupId,
        messageId: message.id,
      );
    } else {
      success = await groupService.pinMessage(
        groupId: widget.groupId,
        messageId: message.id,
      );
    }

    if (mounted) {
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPinned ? 'Failed to unpin message' : 'Failed to pin message'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPinned ? 'Message unpinned' : 'Message pinned'),
            duration: const Duration(seconds: 2),
          ),
        );
        // Refresh pinned count
        ref.invalidate(pinnedMessagesCountProvider(widget.groupId));
        ref.invalidate(pinnedMessagesProvider(widget.groupId));
      }
    }
  }

  void _showForwardDialog(Message message) async {
    // Get list of groups user is a member of
    final groupService = ref.read(groupServiceProvider);
    final groups = await groupService.getGroups();

    if (!mounted) return;

    // Filter out current group
    final otherGroups = groups.where((g) => g.id != widget.groupId).toList();

    if (otherGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other groups to forward to'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDarkSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDarkSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Forward to...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...otherGroups.map((group) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: Text(
                    group.name[0].toUpperCase(),
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
                title: Text(group.name),
                subtitle: Text('${group.memberCount} members'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _forwardToGroup(message, group.id);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _forwardToGroup(Message message, String targetGroupId) async {
    final groupService = ref.read(groupServiceProvider);
    final result = await groupService.forwardMessage(
      fromGroupId: widget.groupId,
      toGroupId: targetGroupId,
      messageId: message.id,
    );

    if (mounted) {
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to forward message'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message forwarded'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showPinnedMessages(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDarkSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return _PinnedMessagesSheet(
              groupId: widget.groupId,
              scrollController: scrollController,
            );
          },
        );
      },
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

class _GroupMessageBubble extends ConsumerWidget {
  final Message message;
  final Group? group;
  final bool showSenderName;
  final VoidCallback onReply;
  final void Function(Message) onEdit;
  final void Function(Message, bool) onDelete;
  final void Function(Message) onPin;
  final void Function(Message) onForward;

  const _GroupMessageBubble({
    required this.message,
    required this.group,
    required this.showSenderName,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    required this.onForward,
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
  Widget build(BuildContext context, WidgetRef ref) {
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
            onLongPress: () => _showMessageOptions(context, ref),
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
                  // Forwarded indicator
                  if (message.isForwarded) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forward,
                          size: 12,
                          color: isOutgoing
                              ? Colors.white.withOpacity(0.7)
                              : AppColors.textDarkSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Forwarded',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: isOutgoing
                                ? Colors.white.withOpacity(0.7)
                                : AppColors.textDarkSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
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
                  else if (message.type.isMedia)
                    MediaMessageContent(
                      message: message,
                      isOutgoing: isOutgoing,
                      colorScheme: Theme.of(context).colorScheme,
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

  void _showMessageOptions(BuildContext context, WidgetRef ref) async {
    // Check if user is admin for pin option
    final groupService = ref.read(groupServiceProvider);
    final identity = IdentityService.instance.currentIdentity;
    final localNodeId = identity?.nodeId ?? '';
    final isAdmin = group?.isAdmin(localNodeId) ?? false;
    final isPinned = group != null
        ? await groupService.isMessagePinned(
            groupId: group!.id,
            messageId: message.id,
          )
        : false;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDarkSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
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
              // Reply
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onReply();
                },
              ),
              // Copy
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              // Forward
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.forward),
                  title: const Text('Forward'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onForward(message);
                  },
                ),
              // Pin/Unpin (admin only)
              if (isAdmin && !message.isDeleted)
                ListTile(
                  leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                  title: Text(isPinned ? 'Unpin' : 'Pin'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onPin(message);
                  },
                ),
              // Edit (own messages only, not deleted)
              if (message.isOutgoing && !message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onEdit(message);
                  },
                ),
              // Delete (own messages, or admin can delete any)
              if ((message.isOutgoing || isAdmin) && !message.isDeleted)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text('Delete', style: TextStyle(color: AppColors.error)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showDeleteConfirmation(context, isAdmin && !message.isOutgoing);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, bool canDeleteForAll) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.bgDarkSecondary,
          title: const Text('Delete message?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            if (canDeleteForAll)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  onDelete(message, true); // Delete for everyone
                },
                child: Text('Delete for everyone', style: TextStyle(color: AppColors.error)),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onDelete(message, false); // Delete for me only
              },
              child: Text(
                canDeleteForAll ? 'Delete for me' : 'Delete',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
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
  final bool isEditing;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;
  final VoidCallback? onOpenGallery;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    this.isEditing = false,
    this.onAttachFile,
    this.onAttachImage,
    this.onOpenGallery,
  });

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDarkSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text('Photo', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onAttachImage?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.orange),
              title: const Text('File', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onAttachFile?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.purple),
              title: const Text('Media Gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onOpenGallery?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

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
            if (!isEditing)
              IconButton(
                icon: const Icon(Icons.attach_file),
                color: AppColors.textDarkSecondary,
                onPressed: () => _showAttachMenu(context),
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
                    hintText: isEditing ? 'Edit message' : 'Message',
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
                icon: Icon(isEditing ? Icons.check : Icons.send),
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

class _EditIndicator extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;

  const _EditIndicator({
    required this.message,
    required this.onCancel,
  });

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
          Icon(Icons.edit, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Editing message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  message.content,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textDarkSecondary,
                  ),
                ),
              ],
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

class _PinnedMessagesBanner extends StatelessWidget {
  final String groupId;
  final int count;
  final VoidCallback onTap;

  const _PinnedMessagesBanner({
    required this.groupId,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgDarkSecondary,
          border: Border(
            bottom: BorderSide(
              color: AppColors.bgDarkTertiary,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count pinned message${count > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textDarkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedMessagesSheet extends ConsumerWidget {
  final String groupId;
  final ScrollController scrollController;

  const _PinnedMessagesSheet({
    required this.groupId,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinnedMessagesAsync = ref.watch(pinnedMessagesProvider(groupId));

    return Column(
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.push_pin, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Pinned Messages',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: pinnedMessagesAsync.when(
            data: (messages) {
              if (messages.isEmpty) {
                return Center(
                  child: Text(
                    'No pinned messages',
                    style: TextStyle(color: AppColors.textDarkSecondary),
                  ),
                );
              }
              return ListView.builder(
                controller: scrollController,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return _PinnedMessageItem(
                    message: message,
                    onTap: () => Navigator.pop(context),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(
                'Error: $error',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PinnedMessageItem extends StatelessWidget {
  final Message message;
  final VoidCallback onTap;

  const _PinnedMessageItem({
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withOpacity(0.2),
        child: Icon(
          message.isOutgoing ? Icons.person : Icons.person_outline,
          color: AppColors.primary,
          size: 20,
        ),
      ),
      title: Text(
        message.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textDark),
      ),
      subtitle: Text(
        message.timeString,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textDarkSecondary,
        ),
      ),
      trailing: Icon(
        Icons.push_pin,
        size: 16,
        color: AppColors.primary,
      ),
    );
  }
}

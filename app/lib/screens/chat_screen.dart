import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/conversation_provider.dart';
import '../providers/file_provider.dart';
import '../models/models.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  String? _replyToId;

  @override
  void initState() {
    super.initState();
    // Mark as read when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatActionsProvider).markAsRead(widget.conversationId);
    });
  }

  /// Listen for incoming messages and refresh UI
  void _setupMessageListener() {
    ref.listen<AsyncValue<Message>>(messageStreamProvider, (previous, next) {
      next.whenData((message) {
        // Refresh if message is for this conversation
        if (message.conversationId == widget.conversationId) {
          ref.invalidate(messagesProvider(widget.conversationId));
        }
        // Also refresh conversation list for unread count
        ref.invalidate(conversationsProvider);
      });
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
    // Listen for incoming messages
    _setupMessageListener();

    final conversationAsync = ref.watch(conversationProvider(widget.conversationId));
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));

    return Scaffold(
      appBar: AppBar(
        title: conversationAsync.when(
          data: (conv) => Text(conv?.title ?? 'Chat'),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Error'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: Chat options
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
                  return const _EmptyMessages();
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  clipBehavior: Clip.hardEdge,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return _MessageBubble(
                      message: message,
                      conversationId: widget.conversationId,
                      onReply: () => _setReplyTo(message),
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
            conversationId: widget.conversationId,
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

    await ref.read(chatActionsProvider).sendMessage(
          conversationId: widget.conversationId,
          content: text,
          replyToId: replyTo,
        );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Messages are end-to-end encrypted',
            style: TextStyle(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: TextStyle(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends ConsumerStatefulWidget {
  final Message message;
  final String conversationId;
  final VoidCallback onReply;

  const _MessageBubble({
    required this.message,
    required this.conversationId,
    required this.onReply,
  });

  @override
  ConsumerState<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<_MessageBubble> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.message.isOutgoing;
    final colorScheme = Theme.of(context).colorScheme;
    final maxBubbleHeight = 250.0; // Fixed max height for any message

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: () => _showMessageOptions(context),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
              maxHeight: maxBubbleHeight,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isOutgoing
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
                bottomRight: Radius.circular(isOutgoing ? 4 : 16),
              ),
            ),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.message.isDeleted)
                      Text(
                        'Message deleted',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: isOutgoing
                              ? colorScheme.onPrimary.withOpacity(0.7)
                              : colorScheme.onSurface.withOpacity(0.7),
                        ),
                      )
                    else if (widget.message.type == MessageType.file)
                      _FileMessageContent(
                        message: widget.message,
                        isOutgoing: isOutgoing,
                        colorScheme: colorScheme,
                      )
                    else
                      Text(
                        widget.message.content,
                        softWrap: true,
                        style: TextStyle(
                          color: isOutgoing
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.message.timeString}${widget.message.isEdited ? ' (edited)' : ''}${isOutgoing ? ' ${widget.message.status.icon}' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOutgoing
                            ? colorScheme.onPrimary.withOpacity(0.7)
                            : colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onReply();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.message.content));
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              if (widget.message.isOutgoing && !widget.message.isDeleted) ...[
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showEditDialog(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showDeleteConfirmation(context);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.message.content);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: TextField(
            controller: controller,
            maxLines: null,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter new message',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newContent = controller.text.trim();
                if (newContent.isEmpty) return;
                if (newContent == widget.message.content) {
                  Navigator.pop(dialogContext);
                  return;
                }

                Navigator.pop(dialogContext);
                await ref.read(chatActionsProvider).editMessage(
                  widget.message.id,
                  widget.conversationId,
                  newContent,
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Message'),
          content: const Text('Are you sure you want to delete this message? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await ref.read(chatActionsProvider).deleteMessage(
                  widget.message.id,
                  widget.conversationId,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

/// File message content widget
class _FileMessageContent extends StatelessWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;

  const _FileMessageContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    // Parse file info from content (format: "filename|size|fileId" or just filename)
    final parts = message.content.split('|');
    final filename = parts.isNotEmpty ? parts[0] : 'Unknown file';
    final sizeStr = parts.length > 1 ? parts[1] : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.insert_drive_file,
          size: 32,
          color: isOutgoing ? colorScheme.onPrimary : colorScheme.onSurface,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filename,
                style: TextStyle(
                  color: isOutgoing ? colorScheme.onPrimary : colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (sizeStr.isNotEmpty)
                Text(
                  sizeStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: isOutgoing
                        ? colorScheme.onPrimary.withOpacity(0.7)
                        : colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
            ],
          ),
        ),
      ],
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Replying to message',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onCancel,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _MessageInput extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final String conversationId;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.conversationId,
  });

  @override
  ConsumerState<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<_MessageInput> {
  bool _isSendingFile = false;

  Future<void> _pickFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true, // Load file bytes for small files
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final fileSize = file.size;
      final maxSize = 64 * 1024; // 64KB limit as per COMPARISON.md

      if (fileSize > maxSize) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File too large (${(fileSize / 1024).toStringAsFixed(1)} KB). '
                'Maximum size is 64 KB.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Get peer ID from conversation
      final conversationAsync = ref.read(conversationProvider(widget.conversationId));
      final conversation = conversationAsync.value;
      if (conversation == null || conversation.peerId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot send file: peer not found')),
          );
        }
        return;
      }

      // Get file data
      final fileBytes = file.bytes;
      if (fileBytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot read file data')),
          );
        }
        return;
      }

      setState(() => _isSendingFile = true);

      // Send file via FileProvider
      final sendResult = await ref.read(fileActionsProvider).sendFile(
        toPeerId: conversation.peerId!,
        filename: file.name,
        data: Uint8List.fromList(fileBytes),
      );

      setState(() => _isSendingFile = false);

      if (sendResult.success) {
        // Save file message to conversation
        final sizeStr = fileSize < 1024
            ? '$fileSize B'
            : '${(fileSize / 1024).toStringAsFixed(1)} KB';
        await ref.read(chatActionsProvider).sendFileMessage(
          conversationId: widget.conversationId,
          filename: file.name,
          fileSize: sizeStr,
          fileId: sendResult.fileId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sending ${file.name}...'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(sendResult.error ?? 'Failed to send file'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSendingFile = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            _isSendingFile
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: () => _pickFile(context),
                  ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: widget.controller,
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: InputBorder.none,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
                  onSubmitted: (_) => widget.onSend(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: widget.onSend,
            ),
          ],
        ),
      ),
    );
  }
}

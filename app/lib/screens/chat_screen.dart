import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/conversation_provider.dart';
import '../providers/file_provider.dart';
import '../providers/voice_provider.dart';
import '../providers/call_provider.dart';
import '../providers/settings_provider.dart';
import '../ffi/bindings.dart' show CyxChatFileState, CyxChatFileConst;
import '../models/models.dart';
import 'active_call_screen.dart';

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
          // Voice call button
          IconButton(
            icon: const Icon(Icons.phone),
            tooltip: 'Voice call',
            onPressed: () => _startCall(context, ref, video: false),
          ),
          // Video call button
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video call',
            onPressed: () => _startCall(context, ref, video: true),
          ),
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

  Future<void> _startCall(BuildContext context, WidgetRef ref, {required bool video}) async {
    // Check if video calls are enabled in settings
    final settings = ref.read(settingsNotifierProvider);
    if (video && !settings.videoCallsEnabled) {
      _showVideoCallDisabledDialog(context);
      return;
    }

    // Get peer info from conversation
    final conversationAsync = ref.read(conversationProvider(widget.conversationId));
    final conversation = conversationAsync.value;
    if (conversation == null || conversation.peerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot call: peer not found')),
      );
      return;
    }

    // Show privacy warning for first call
    final hasSeenWarning = settings.hasSeenCallPrivacyWarning;
    if (!hasSeenWarning) {
      final proceed = await _showCallPrivacyWarning(context, video);
      if (!proceed) return;
      ref.read(settingsNotifierProvider.notifier).setHasSeenCallPrivacyWarning(true);
    }

    // Start the call
    final success = await ref.read(callActionsProvider).startCall(
      peerId: conversation.peerId!,
      peerName: conversation.title,
      video: video,
    );

    if (success && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ActiveCallScreen(
            peerId: conversation.peerId!,
            peerName: conversation.title,
            isVideo: video,
          ),
        ),
      );
    }
  }

  void _showVideoCallDisabledDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Video Calls Disabled'),
        content: const Text(
          'Video calls are disabled in settings. Enable them in Settings > Privacy > Video Calls to make video calls.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showCallPrivacyWarning(BuildContext context, bool video) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.amber),
            const SizedBox(width: 8),
            Text(video ? 'Video Call Privacy' : 'Voice Call Privacy'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calls use direct P2P connections for real-time communication.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('The peer you call can see your IP address.'),
                  SizedBox(height: 4),
                  Text('Calls are still end-to-end encrypted.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This is necessary for low-latency real-time communication.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I Understand, Continue'),
          ),
        ],
      ),
    ) ?? false;
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
                    else if (widget.message.type == MessageType.audio)
                      _VoiceMessageContent(
                        message: widget.message,
                        isOutgoing: isOutgoing,
                        colorScheme: colorScheme,
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

/// File message content widget with transfer progress and controls
class _FileMessageContent extends ConsumerWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;

  const _FileMessageContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Parse file info - supports both formats:
    // 1. Pipe-separated (sent files): "filename|size|fileId"
    // 2. JSON (received files): {"fileId":"xxx","filename":"xxx","size":"xxx"}
    String filename = 'Unknown file';
    String sizeStr = '';
    String? fileId;

    final content = message.content;
    if (content.startsWith('{')) {
      // JSON format (received files)
      try {
        final json = jsonDecode(content) as Map<String, dynamic>;
        filename = json['filename'] as String? ?? 'Unknown file';
        sizeStr = json['size'] as String? ?? '';
        fileId = json['fileId'] as String?;
      } catch (e) {
        debugPrint('Failed to parse file message JSON: $e');
      }
    } else {
      // Pipe-separated format (sent files)
      final parts = content.split('|');
      filename = parts.isNotEmpty ? parts[0] : 'Unknown file';
      sizeStr = parts.length > 1 ? parts[1] : '';
      fileId = parts.length > 2 ? parts[2] : null;
    }

    // Watch file provider for transfer state and received files
    final fileProvider = ref.watch(fileNotifierProvider);
    final hasFileData = fileId != null && fileProvider.getReceivedFile(fileId) != null;
    final transfer = fileId != null ? fileProvider.transfers[fileId] : null;

    // Determine transfer state
    final isTransferring = transfer != null &&
        (transfer.state == CyxChatFileState.sending || transfer.state == CyxChatFileState.receiving);
    final isPaused = transfer?.state == CyxChatFileState.paused;
    final isFailed = transfer?.state == CyxChatFileState.failed;
    final isCompleted = hasFileData || transfer?.state == CyxChatFileState.completed;

    return InkWell(
      onTap: hasFileData && !isTransferring && !isPaused
          ? () => _saveFile(context, ref, fileId!, filename)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main row: icon, filename, size
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFileIcon(isTransferring, isPaused, isFailed, isCompleted),
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
                    // Status text
                    _buildStatusText(
                      transfer: transfer,
                      hasFileData: hasFileData,
                    ),
                  ],
                ),
              ),
              // Download icon for completed files
              if (hasFileData && !isTransferring && !isPaused) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.download,
                  size: 20,
                  color: isOutgoing ? colorScheme.onPrimary : colorScheme.primary,
                ),
              ],
            ],
          ),

          // Progress bar and controls (only during active transfer or paused)
          if ((isTransferring || isPaused) && transfer != null && fileId != null) ...[
            const SizedBox(height: 8),
            _buildProgressSection(
              context: context,
              ref: ref,
              transfer: transfer,
              fileId: fileId,
              isPaused: isPaused,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileIcon(bool isTransferring, bool isPaused, bool isFailed, bool isCompleted) {
    IconData icon;
    Color? iconColor;

    if (isFailed) {
      icon = Icons.error_outline;
      iconColor = Colors.red;
    } else if (isPaused) {
      icon = Icons.pause_circle_outline;
      iconColor = Colors.orange;
    } else if (isTransferring) {
      icon = Icons.sync;
      iconColor = Colors.cyan;
    } else if (isCompleted) {
      icon = Icons.check_circle_outline;
      iconColor = Colors.green;
    } else {
      icon = Icons.insert_drive_file;
      iconColor = isOutgoing ? colorScheme.onPrimary : colorScheme.onSurface;
    }

    return Icon(icon, size: 32, color: iconColor);
  }

  Widget _buildStatusText({
    required FileTransferInfo? transfer,
    required bool hasFileData,
  }) {
    if (transfer == null) {
      if (hasFileData) {
        return Text(
          'Tap to save',
          style: TextStyle(
            fontSize: 11,
            color: isOutgoing ? colorScheme.onPrimary.withOpacity(0.6) : colorScheme.primary,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    String statusText;
    Color statusColor;

    switch (transfer.state) {
      case CyxChatFileState.sending:
        statusText = 'Sending... ${(transfer.progress * 100).toInt()}%';
        statusColor = Colors.cyan;
        break;
      case CyxChatFileState.receiving:
        statusText = 'Receiving... ${(transfer.progress * 100).toInt()}%';
        statusColor = Colors.cyan;
        break;
      case CyxChatFileState.paused:
        statusText = 'Paused - ${(transfer.progress * 100).toInt()}%';
        statusColor = Colors.orange;
        break;
      case CyxChatFileState.failed:
        statusText = 'Failed';
        statusColor = Colors.red;
        break;
      case CyxChatFileState.cancelled:
        statusText = 'Cancelled';
        statusColor = Colors.grey;
        break;
      case CyxChatFileState.completed:
        statusText = hasFileData ? 'Tap to save' : 'Completed';
        statusColor = hasFileData
            ? (isOutgoing ? colorScheme.onPrimary.withOpacity(0.6) : colorScheme.primary)
            : Colors.green;
        break;
      default:
        statusText = transfer.stateName;
        statusColor = isOutgoing
            ? colorScheme.onPrimary.withOpacity(0.6)
            : colorScheme.onSurface.withOpacity(0.6);
    }

    return Text(
      statusText,
      style: TextStyle(fontSize: 11, color: statusColor),
    );
  }

  Widget _buildProgressSection({
    required BuildContext context,
    required WidgetRef ref,
    required FileTransferInfo transfer,
    required String fileId,
    required bool isPaused,
  }) {
    return Column(
      children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: transfer.progress,
            minHeight: 4,
            backgroundColor: isOutgoing
                ? colorScheme.onPrimary.withOpacity(0.2)
                : colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              isPaused ? Colors.orange : Colors.cyan,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Control buttons row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pause/Resume button
            _TransferControlButton(
              icon: isPaused ? Icons.play_arrow : Icons.pause,
              tooltip: isPaused ? 'Resume' : 'Pause',
              onPressed: () async {
                if (isPaused) {
                  await ref.read(fileNotifierProvider).resumeTransfer(fileId);
                } else {
                  await ref.read(fileNotifierProvider).pauseTransfer(fileId);
                }
              },
              isOutgoing: isOutgoing,
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 8),

            // Cancel button
            _TransferControlButton(
              icon: Icons.close,
              tooltip: 'Cancel',
              onPressed: () => _showCancelConfirmation(context, ref, fileId, transfer.filename),
              isOutgoing: isOutgoing,
              colorScheme: colorScheme,
              isDestructive: true,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showCancelConfirmation(
    BuildContext context,
    WidgetRef ref,
    String fileId,
    String filename,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Transfer'),
        content: Text('Cancel transfer of "$filename"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(fileActionsProvider).cancelTransfer(fileId);
    }
  }

  Future<void> _saveFile(BuildContext context, WidgetRef ref, String fileId, String filename) async {
    try {
      final fileData = ref.read(fileNotifierProvider).getReceivedFile(fileId);
      if (fileData == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File data not available')),
          );
        }
        return;
      }

      // Use file_picker to get save location
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save file',
        fileName: filename,
      );

      if (outputPath == null) return; // User cancelled

      // Write file to disk
      final file = await io.File(outputPath).writeAsBytes(fileData);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${file.path}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }
}

/// Small icon button for transfer controls
class _TransferControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isOutgoing;
  final ColorScheme colorScheme;
  final bool isDestructive;

  const _TransferControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.isOutgoing,
    required this.colorScheme,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? Colors.red
        : (isOutgoing ? colorScheme.onPrimary : colorScheme.primary);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Voice message content widget with playback controls
class _VoiceMessageContent extends ConsumerWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;

  const _VoiceMessageContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Parse voice message info from content JSON
    // Format: {"fileId":"xxx","duration":30,"filename":"voice.m4a"}
    String? fileId;
    int durationSecs = 0;

    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      fileId = json['fileId'] as String?;
      durationSecs = json['duration'] as int? ?? 0;
    } catch (e) {
      debugPrint('Failed to parse voice message: $e');
    }

    final player = ref.watch(voicePlayerProvider);
    final fileProvider = ref.watch(fileNotifierProvider);
    final isThisPlaying = player.currentFileId == fileId;
    final isPlaying = isThisPlaying && player.isPlaying;
    final isPaused = isThisPlaying && player.state == VoicePlaybackState.paused;
    final hasFileData = fileId != null && fileProvider.getReceivedFile(fileId) != null;

    // Format duration
    final duration = Duration(seconds: durationSecs);
    final durationStr = VoiceRecorderProvider.formatDuration(duration);

    // Progress for playback
    final progress = isThisPlaying ? player.progress : 0.0;
    final currentPosition = isThisPlaying
        ? VoiceRecorderProvider.formatDuration(player.position)
        : durationStr;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play/pause button
        GestureDetector(
          onTap: hasFileData ? () => _togglePlayback(ref, fileId!, fileProvider) : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOutgoing
                  ? colorScheme.onPrimary.withOpacity(0.2)
                  : colorScheme.primary.withOpacity(0.1),
            ),
            child: Icon(
              isPlaying
                  ? Icons.pause
                  : (isPaused ? Icons.play_arrow : Icons.play_arrow),
              color: isOutgoing ? colorScheme.onPrimary : colorScheme.primary,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Waveform / progress bar
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Simple progress bar (waveform could be added later)
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: isOutgoing
                      ? colorScheme.onPrimary.withOpacity(0.2)
                      : colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    isOutgoing ? colorScheme.onPrimary : colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currentPosition,
                    style: TextStyle(
                      fontSize: 11,
                      color: isOutgoing
                          ? colorScheme.onPrimary.withOpacity(0.7)
                          : colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  // Playback speed button (only while playing)
                  if (isThisPlaying)
                    GestureDetector(
                      onTap: () => ref.read(voicePlayerProvider).cycleSpeed(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: isOutgoing
                              ? colorScheme.onPrimary.withOpacity(0.2)
                              : colorScheme.primary.withOpacity(0.1),
                        ),
                        child: Text(
                          '${player.playbackSpeed}x',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isOutgoing
                                ? colorScheme.onPrimary
                                : colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _togglePlayback(WidgetRef ref, String fileId, FileProvider fileProvider) {
    final player = ref.read(voicePlayerProvider);
    final fileData = fileProvider.getReceivedFile(fileId);

    if (fileData == null) return;

    if (player.currentFileId == fileId) {
      // Toggle current playback
      if (player.isPlaying) {
        player.pause();
      } else {
        player.resume();
      }
    } else {
      // Play new file
      player.playFromBytes(fileId, fileData);
    }
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
  bool _hasText = false;
  double _dragOffset = 0;
  static const _cancelThreshold = -100.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

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

      // Check file size limit based on direct mode
      final fileProvider = ref.read(fileNotifierProvider);
      final isDirectMode = fileProvider.isDirectMode;
      final maxSize = isDirectMode
          ? CyxChatFileConst.directMaxFileSize
          : CyxChatFileConst.maxFileSize;

      if (fileSize > maxSize) {
        if (context.mounted) {
          final sizeStr = isDirectMode
              ? '${(maxSize / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB'
              : '${(maxSize / 1024).toStringAsFixed(0)} KB';
          final fileSizeStr = fileSize >= 1024 * 1024
              ? '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '${(fileSize / 1024).toStringAsFixed(1)} KB';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File too large ($fileSizeStr). Maximum size is $sizeStr.'
                '${!isDirectMode ? ' Enable "Fast File Transfer" in settings for larger files.' : ''}',
              ),
              duration: const Duration(seconds: 4),
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

  Future<void> _startRecording() async {
    final recorder = ref.read(voiceRecorderProvider);
    final started = await recorder.startRecording();
    if (!started && mounted) {
      final error = recorder.errorMessage ?? 'Failed to start recording';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> _stopRecordingAndSend() async {
    final recorder = ref.read(voiceRecorderProvider);
    final voiceMessage = await recorder.stopRecording();

    if (voiceMessage == null || !mounted) return;

    // Get peer ID from conversation
    final conversationAsync = ref.read(conversationProvider(widget.conversationId));
    final conversation = conversationAsync.value;
    if (conversation == null || conversation.peerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot send voice message: peer not found')),
      );
      return;
    }

    // Send voice message via file transfer
    final sendResult = await ref.read(fileActionsProvider).sendFile(
      toPeerId: conversation.peerId!,
      filename: voiceMessage.filename,
      data: voiceMessage.data,
      mimeType: 'audio/mp4',
    );

    if (sendResult.success && sendResult.fileId != null) {
      // Save audio message to conversation
      await ref.read(chatActionsProvider).sendAudioMessage(
        conversationId: widget.conversationId,
        fileId: sendResult.fileId!,
        duration: voiceMessage.duration.inSeconds,
        filename: voiceMessage.filename,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending voice message...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sendResult.error ?? 'Failed to send voice message'),
        ),
      );
    }
  }

  void _cancelRecording() {
    ref.read(voiceRecorderProvider).cancelRecording();
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final recorder = ref.watch(voiceRecorderProvider);
    final isRecording = recorder.isRecording;
    final colorScheme = Theme.of(context).colorScheme;

    // Recording UI
    if (isRecording) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Cancel indicator
              AnimatedOpacity(
                opacity: _dragOffset < _cancelThreshold ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 100),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: _dragOffset < _cancelThreshold
                          ? Colors.red
                          : colorScheme.onSurface.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Slide to cancel',
                      style: TextStyle(
                        fontSize: 12,
                        color: _dragOffset < _cancelThreshold
                            ? Colors.red
                            : colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Recording indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      VoiceRecorderProvider.formatDuration(recorder.recordingDuration),
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Mic button (draggable to cancel)
              GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _dragOffset += details.delta.dx;
                    if (_dragOffset > 0) _dragOffset = 0;
                  });
                },
                onHorizontalDragEnd: (details) {
                  if (_dragOffset < _cancelThreshold) {
                    _cancelRecording();
                  }
                  setState(() => _dragOffset = 0);
                },
                onTapUp: (_) => _stopRecordingAndSend(),
                child: Transform.translate(
                  offset: Offset(_dragOffset.clamp(-150.0, 0.0), 0),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _dragOffset < _cancelThreshold
                          ? Colors.red
                          : colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _dragOffset < _cancelThreshold ? Icons.close : Icons.mic,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Normal input UI
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
            // Send button when text, mic button when empty
            _hasText
                ? IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: widget.onSend,
                  )
                : GestureDetector(
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) {
                      if (ref.read(voiceRecorderProvider).isRecording) {
                        _stopRecordingAndSend();
                      }
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

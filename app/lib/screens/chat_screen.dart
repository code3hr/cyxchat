import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/conversation_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/network_provider.dart';
import '../providers/file_provider.dart';
import '../providers/voice_provider.dart';
import '../providers/call_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/group_ffi_provider.dart';
import '../providers/queue_provider.dart';
import '../models/queued_message.dart';
import '../models/connection_progress.dart';
import '../ffi/bindings.dart' show CyxChatFileState, CyxChatFileConst;
import '../models/models.dart';
import '../services/chat_service.dart';
import '../services/group_service.dart';
import '../widgets/voice_recorder.dart';
import 'active_call_screen.dart';
import 'group_chat_screen.dart';

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
  bool _hasPreConnected = false;

  @override
  void initState() {
    super.initState();
    // Mark as read when opening and refresh messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Force refresh messages from database in case new ones arrived
      // while the chat screen was not active
      ref.invalidate(messagesProvider(widget.conversationId));
      ref.read(chatActionsProvider).markAsRead(widget.conversationId);
      // Pre-connect triggered when conversation loads (see build)
      // _preConnectToPeer() called from build when peerId available
    });
  }

  /// Pre-connect to peer to establish connection before sending
  void _preConnectToPeer() async {
    if (_hasPreConnected) return;
    _hasPreConnected = true;

    final connectionProvider = ref.read(connectionNotifierProvider);
    if (!connectionProvider.initialized) return;

    // Load conversation to get the actual peer ID (not the conversation DB id)
    final conv = await ChatService.instance.getConversation(widget.conversationId);
    final peerId = conv?.peerId;
    if (peerId != null && peerId.isNotEmpty) {
      final progress = connectionProvider.getProgress(peerId);
      if (connectionProvider.hasPeerKey(peerId) ||
          (progress != null && progress.isConnecting)) {
        return;
      }
      final result = await connectionProvider.connect(peerId);
      final shortId = peerId.length > 16 ? peerId.substring(0, 16) : peerId;
      debugPrint('Pre-connect to $shortId...: $result');
    }
  }

  /// Listen for incoming messages and refresh UI
  void _setupMessageListener() {
    ref.listen<AsyncValue<Message>>(messageStreamProvider, (previous, next) {
      next.whenData((message) {
        // Only refresh if message is for this conversation
        if (message.conversationId == widget.conversationId) {
          ref.invalidate(messagesProvider(widget.conversationId));
          ref.invalidate(conversationsProvider);
        }
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


    // Get connection status for this peer
    final connectionProvider = ref.watch(connectionNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: conversationAsync.when(
          data: (conv) {
            // Use the actual peer ID from the conversation, not the conversation ID
            final peerId = conv?.peerId;

            // Pre-connect to peer (loads conversation internally)
            _preConnectToPeer();

            // Get connection progress for real-time feedback
            final progress = peerId != null && connectionProvider.initialized
                ? connectionProvider.getProgress(peerId)
                : null;

            // Fallback to old method if no progress yet
            final hasKey = peerId != null &&
                connectionProvider.initialized &&
                connectionProvider.hasPeerKey(peerId);
            final isRelayed = peerId != null &&
                connectionProvider.initialized &&
                connectionProvider.isRelayed(peerId);

            // Determine connection status text and color
            String statusText;
            Color statusColor;
            bool showSpinner = false;

            if (progress != null && progress.phase != ConnectionPhase.idle) {
              // Use granular progress from callback
              statusText = progress.statusText;
              statusColor = progress.statusColor;
              showSpinner = progress.isConnecting;
            } else if (hasKey && isRelayed) {
              statusText = 'Secured (via relay)';
              statusColor = Colors.blue;
            } else if (hasKey) {
              statusText = 'Secured (direct P2P)';
              statusColor = Colors.green;
            } else if (peerId != null && connectionProvider.initialized) {
              // No progress yet but peer exists - still connecting
              statusText = 'Establishing secure connection...';
              statusColor = Colors.orange;
              showSpinner = true;
            } else {
              statusText = '';
              statusColor = Colors.grey;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conv?.title ?? 'Chat'),
                if (statusText.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showSpinner)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation(statusColor),
                            ),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          statusText,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: statusColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'save_contact') {
                _showSaveContactDialog(context, ref);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'save_contact',
                child: ListTile(
                  leading: Icon(Icons.person_add),
                  title: Text('Save Contact'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages with wallpaper
          Expanded(
            child: _ChatBackground(
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

    // Check connection status and wait briefly if needed
    final connectionProvider = ref.read(connectionNotifierProvider);
    if (!connectionProvider.initialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connecting to network...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Wait a bit for connection
      await Future.delayed(const Duration(seconds: 2));
    }

    // Pre-connect to peer before sending (ensures route is established)
    final conversationAsync = ref.read(conversationProvider(widget.conversationId));
    final conversation = conversationAsync.value;
    final peerId = conversation?.peerId ?? widget.conversationId;

    if (connectionProvider.initialized) {
      if (!connectionProvider.hasPeerKey(peerId)) {
        final progress = connectionProvider.getProgress(peerId);
        if (progress == null || !progress.isConnecting) {
          debugPrint('ChatScreen: Ensuring connection to peer before sending...');
          await connectionProvider.connect(peerId);
        } else {
          debugPrint('ChatScreen: Waiting for existing peer connection...');
        }
      }

      // Wait for key exchange to complete (up to 5 seconds)
      // Uses increasing delays to avoid blocking UI thread with tight polling
      int waited = 0;
      const maxWait = 5000;
      int checkInterval = 200;

      while (!connectionProvider.hasPeerKey(peerId) && waited < maxWait) {
        await Future.delayed(Duration(milliseconds: checkInterval));
        waited += checkInterval;
        if (checkInterval < 800) checkInterval = (checkInterval * 1.5).toInt();
      }

      if (!connectionProvider.hasPeerKey(peerId)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not establish secure connection. Try again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      debugPrint('ChatScreen: Key exchange complete, sending message');
    }

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

  void _showSaveContactDialog(BuildContext context, WidgetRef ref) {
    final conversationAsync = ref.read(conversationProvider(widget.conversationId));
    final conversation = conversationAsync.value;

    if (conversation == null || conversation.peerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot save contact: peer not found')),
      );
      return;
    }

    final displayNameController = TextEditingController(text: conversation.title);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Node ID: ${conversation.peerId!.length > 16 ? "${conversation.peerId!.substring(0, 16)}..." : conversation.peerId!}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'Enter a name for this contact',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final displayName = displayNameController.text.trim();

              try {
                // Add/update contact
                await ref.read(contactActionsProvider).addContact(
                  nodeId: conversation.peerId!,
                  displayName: displayName.isEmpty ? null : displayName,
                );

                // Also update the conversation's display name directly
                if (displayName.isNotEmpty) {
                  await ref.read(chatActionsProvider).updateConversationDisplayName(
                    widget.conversationId,
                    displayName,
                  );
                }

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Contact saved${displayName.isNotEmpty ? " as $displayName" : ""}'),
                    ),
                  );
                }

                // Refresh conversation to update the title
                ref.invalidate(conversationProvider(widget.conversationId));
                ref.invalidate(conversationsProvider);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save contact: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
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

/// Chat background with wallpaper support
class _ChatBackground extends ConsumerWidget {
  final Widget child;

  const _ChatBackground({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final wallpaper = settings.chatWallpaper;
    final colorScheme = Theme.of(context).colorScheme;

    if (wallpaper == null) {
      // No wallpaper - use default background
      return child;
    }

    // Parse wallpaper setting
    if (wallpaper.startsWith('solid:')) {
      // Solid color wallpaper
      final hex = wallpaper.replaceFirst('solid:', '');
      Color? color;
      try {
        color = Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {
        color = null;
      }

      return Container(
        color: color ?? colorScheme.surface,
        child: child,
      );
    } else if (wallpaper.startsWith('pattern:')) {
      // Pattern wallpaper
      final patternName = wallpaper.replaceFirst('pattern:', '');
      return Stack(
        children: [
          Positioned.fill(
            child: _PatternBackground(
              pattern: patternName,
              colorScheme: colorScheme,
            ),
          ),
          child,
        ],
      );
    } else if (wallpaper.startsWith('file:')) {
      // Custom image wallpaper
      final path = wallpaper.replaceFirst('file:', '');
      final file = io.File(path);
      if (file.existsSync()) {
        return Stack(
          children: [
            Positioned.fill(
              child: Image.file(
                file,
                fit: BoxFit.cover,
              ),
            ),
            // Subtle overlay to ensure text readability
            Positioned.fill(
              child: Container(
                color: colorScheme.surface.withOpacity(0.3),
              ),
            ),
            child,
          ],
        );
      }
    }

    // Fallback to default
    return child;
  }
}

/// Pattern background painter
class _PatternBackground extends StatelessWidget {
  final String pattern;
  final ColorScheme colorScheme;

  const _PatternBackground({
    required this.pattern,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PatternPainter(
        pattern: pattern,
        color: colorScheme.primary.withOpacity(0.1),
        backgroundColor: colorScheme.surface,
      ),
      size: Size.infinite,
    );
  }
}

class _PatternPainter extends CustomPainter {
  final String pattern;
  final Color color;
  final Color backgroundColor;

  _PatternPainter({
    required this.pattern,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    switch (pattern) {
      case 'circuit':
        _paintCircuit(canvas, size, paint);
        break;
      case 'matrix':
        _paintMatrix(canvas, size, paint);
        break;
      case 'hex':
        _paintHex(canvas, size, paint);
        break;
      case 'binary':
        _paintBinary(canvas, size, paint);
        break;
      case 'terminal':
        _paintTerminal(canvas, size, paint);
        break;
      default:
        _paintGrid(canvas, size, paint);
    }
  }

  void _paintCircuit(Canvas canvas, Size size, Paint paint) {
    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        // Draw small circuits
        canvas.drawCircle(Offset(x, y), 2, paint);
        if ((x / spacing).toInt() % 2 == 0) {
          canvas.drawLine(Offset(x, y), Offset(x + spacing, y), paint);
        }
        if ((y / spacing).toInt() % 3 == 0) {
          canvas.drawLine(Offset(x, y), Offset(x, y + spacing), paint);
        }
      }
    }
  }

  void _paintMatrix(Canvas canvas, Size size, Paint paint) {
    const spacing = 20.0;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing * 1.5) {
        final char = String.fromCharCode(0x30 + ((x + y).toInt() % 10));
        textPainter.text = TextSpan(
          text: char,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x, y));
      }
    }
  }

  void _paintHex(Canvas canvas, Size size, Paint paint) {
    const hexRadius = 20.0;
    const hexWidth = hexRadius * 1.732;
    var row = 0;

    for (var y = 0.0; y < size.height + hexRadius; y += hexRadius * 1.5) {
      final offset = (row % 2) * (hexWidth / 2);
      for (var x = offset; x < size.width + hexWidth; x += hexWidth) {
        _drawHexagon(canvas, Offset(x, y), hexRadius, paint);
      }
      row++;
    }
  }

  void _drawHexagon(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * math.pi / 180;
      final point = Offset(
        center.dx + radius * 0.8 * math.cos(angle),
        center.dy + radius * 0.8 * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _paintBinary(Canvas canvas, Size size, Paint paint) {
    const spacing = 16.0;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        final char = ((x + y).toInt() % 2).toString();
        textPainter.text = TextSpan(
          text: char,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x, y));
      }
    }
  }

  void _paintTerminal(Canvas canvas, Size size, Paint paint) {
    const spacing = 24.0;
    for (var y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(8, y),
        Offset(size.width - 8, y),
        paint..strokeWidth = 0.5,
      );
    }
    // Draw prompt symbols
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    for (var y = spacing; y < size.height; y += spacing * 3) {
      textPainter.text = TextSpan(
        text: '>',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(12, y - 8));
    }
  }

  void _paintGrid(Canvas canvas, Size size, Paint paint) {
    const spacing = 30.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint..strokeWidth = 0.3);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint..strokeWidth = 0.3);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    final settings = ref.watch(settingsProvider);
    final bubbleRadius = settings.bubbleRadius;

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
                topLeft: Radius.circular(bubbleRadius),
                topRight: Radius.circular(bubbleRadius),
                bottomLeft: Radius.circular(isOutgoing ? bubbleRadius : 4),
                bottomRight: Radius.circular(isOutgoing ? 4 : bubbleRadius),
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
                    else if (widget.message.type == MessageType.system &&
                             widget.message.content.startsWith('GROUP_INVITE|'))
                      _GroupInviteMessageContent(
                        message: widget.message,
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.message.timeString}${widget.message.isEdited ? ' (edited)' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isOutgoing
                                ? colorScheme.onPrimary.withOpacity(0.7)
                                : colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        if (isOutgoing) ...[
                          const SizedBox(width: 4),
                          _buildStatusIndicator(context, colorScheme, isOutgoing),
                        ],
                      ],
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

  Future<void> _retryMessage(BuildContext context) async {
    debugPrint('Retrying message: ${widget.message.id}');

    // Show sending indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Retrying...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Retry sending via chat actions
    final success = await ref.read(chatActionsProvider).retryMessage(
      widget.message.id,
      widget.conversationId,
    );

    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message sent'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send. Try again later.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildStatusIndicator(
    BuildContext context,
    ColorScheme colorScheme,
    bool isOutgoing,
  ) {
    final message = widget.message;

    if (message.status == MessageStatus.failed) {
      // Check if message is in offline queue
      final queueState = ref.watch(queueNotifierProvider).state;
      final queuedMessage = queueState.pendingMessages
          .cast<QueuedMessage?>()
          .firstWhere((m) => m?.messageId == message.id, orElse: () => null);

      if (queuedMessage != null) {
        // Message is queued for retry - show clock icon with retry count
        return GestureDetector(
          onTap: () => _showQueuedMessageSheet(context, queuedMessage),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule,
                size: 14,
                color: Colors.orange.shade400,
              ),
              const SizedBox(width: 2),
              Text(
                'Queued (${queuedMessage.retryCount})',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      } else {
        // Failed but not queued - show retry button
        return GestureDetector(
          onTap: () => _retryMessage(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 14,
                color: Colors.red.shade300,
              ),
              const SizedBox(width: 2),
              Text(
                'Retry',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade300,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }
    }

    // Normal status icon with color coding
    Color statusColor;
    switch (message.status) {
      case MessageStatus.read:
        statusColor = Colors.blue.shade300; // Blue for read
        break;
      case MessageStatus.delivered:
        statusColor = colorScheme.onPrimary.withOpacity(0.8); // White/light for delivered
        break;
      case MessageStatus.sent:
        statusColor = colorScheme.onPrimary.withOpacity(0.6); // Dimmer for sent
        break;
      case MessageStatus.sending:
        statusColor = colorScheme.onPrimary.withOpacity(0.5); // Dimmer for sending
        break;
      case MessageStatus.pending:
        statusColor = Colors.orange.shade300; // Orange for pending
        break;
      case MessageStatus.failed:
        statusColor = Colors.red.shade300; // Red for failed
        break;
    }
    
    return Tooltip(
      message: message.status.label,
      child: Text(
        message.status.icon,
        style: TextStyle(
          fontSize: 12,
          color: statusColor,
        ),
      ),
    );
  }

  void _showQueuedMessageSheet(BuildContext context, QueuedMessage qm) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.orange.shade400),
                    const SizedBox(width: 8),
                    Text(
                      'Message Queued',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Retry attempts', '${qm.retryCount}'),
                _buildInfoRow('Next retry', _formatNextRetry(qm.nextRetryAt)),
                _buildInfoRow('Queued since', _formatDuration(qm.createdAt)),
                if (qm.lastError != null)
                  _buildInfoRow('Last error', qm.lastError!),
                _buildInfoRow('Expires', _formatExpiry(qm.createdAt)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _removeFromQueue(qm.messageId);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _retryNow(qm.messageId);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Now'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNextRetry(DateTime? nextRetry) {
    if (nextRetry == null) return 'Soon';
    final diff = nextRetry.difference(DateTime.now());
    if (diff.isNegative) return 'Now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }

  String _formatDuration(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatExpiry(DateTime createdAt) {
    final expiryTime = createdAt.add(const Duration(days: 7));
    final diff = expiryTime.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours < 24) return 'In ${diff.inHours}h';
    return 'In ${diff.inDays}d';
  }

  Future<void> _removeFromQueue(String messageId) async {
    await ref.read(queueActionsProvider).removeFromQueue(messageId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message removed from queue'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _retryNow(String messageId) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Retrying...'),
        duration: Duration(seconds: 1),
      ),
    );

    final success = await ref.read(queueActionsProvider).retryMessage(messageId);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message sent'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still queued. Will retry automatically.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
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
    String? localPath;

    final content = message.content;
    if (content.startsWith('{')) {
      // JSON format (received files)
      try {
        final json = jsonDecode(content) as Map<String, dynamic>;
        filename = json['filename'] as String? ?? 'Unknown file';
        sizeStr = json['size'] as String? ?? '';
        fileId = json['fileId'] as String?;
        localPath = json['localPath'] as String?;
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
    final hasFileData = fileId != null &&
        fileProvider.hasFileData(fileId, localPath: localPath);
    final transfer = fileId != null ? fileProvider.transfers[fileId] : null;

    // Determine transfer state
    final isTransferring = transfer != null &&
        (transfer.state == CyxChatFileState.sending || transfer.state == CyxChatFileState.receiving);
    final isPaused = transfer?.state == CyxChatFileState.paused;
    final isFailed = transfer?.state == CyxChatFileState.failed;
    final isCompleted = hasFileData || transfer?.state == CyxChatFileState.completed;
    final isPendingIncoming = !isOutgoing &&
        transfer != null &&
        transfer.state == CyxChatFileState.pending;

    return InkWell(
      onTap: hasFileData && !isTransferring && !isPaused
          ? () => _saveFile(context, ref, fileId!, filename, localPath)
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
          if (isPendingIncoming && fileId != null) ...[
            const SizedBox(height: 8),
            _buildAcceptSection(context, ref, fileId, filename),
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
      case CyxChatFileState.pending:
        statusText = isOutgoing
            ? 'Waiting for recipient to accept'
            : 'Waiting for you to accept';
        statusColor = Colors.orange;
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

  Widget _buildAcceptSection(
    BuildContext context,
    WidgetRef ref,
    String fileId,
    String filename,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: () async {
            final accepted = await ref.read(fileActionsProvider).acceptFile(fileId);
            if (!accepted && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not accept "$filename"')),
              );
            }
          },
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('Accept'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final rejected = await ref.read(fileActionsProvider).rejectFile(fileId);
            if (!rejected && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not decline "$filename"')),
              );
            }
          },
          icon: const Icon(Icons.close_rounded, size: 16),
          label: const Text('Decline'),
        ),
      ],
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

  Future<void> _saveFile(
    BuildContext context,
    WidgetRef ref,
    String fileId,
    String filename,
    String? localPath,
  ) async {
    try {
      final fileData = ref
          .read(fileNotifierProvider)
          .getReceivedFile(fileId, localPath: localPath);
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
    String? localPath;
    int durationSecs = 0;

    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      fileId = json['fileId'] as String?;
      localPath = json['localPath'] as String?;
      durationSecs = json['duration'] as int? ?? 0;
    } catch (e) {
      debugPrint('Failed to parse voice message: $e');
    }

    final player = ref.watch(voicePlayerProvider);
    final fileProvider = ref.watch(fileNotifierProvider);
    final isThisPlaying = player.currentFileId == fileId;
    final isPlaying = isThisPlaying && player.isPlaying;
    final isPaused = isThisPlaying && player.state == VoicePlaybackState.paused;
    final hasFileData = fileId != null &&
        fileProvider.hasFileData(fileId, localPath: localPath);

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
          onTap: hasFileData
              ? () => _togglePlayback(ref, fileId!, fileProvider, localPath)
              : null,
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

  void _togglePlayback(
    WidgetRef ref,
    String fileId,
    FileProvider fileProvider,
    String? localPath,
  ) {
    final player = ref.read(voicePlayerProvider);
    final fileData = fileProvider.getReceivedFile(fileId, localPath: localPath);

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

/// Group invite message widget with accept button
class _GroupInviteMessageContent extends ConsumerWidget {
  final Message message;
  final ColorScheme colorScheme;

  const _GroupInviteMessageContent({
    required this.message,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Parse invite: GROUP_INVITE|groupId|groupName
    final parts = message.content.split('|');
    final groupId = parts.length > 1 ? parts[1] : '';
    final groupName = parts.length > 2 ? parts[2] : 'Unknown Group';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.group_add,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Group Invitation',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ve been invited to join "$groupName"',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _declineInvite(context, ref, groupId),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Decline'),
              ),
              ElevatedButton.icon(
                onPressed: () => _acceptInvite(context, ref, groupId, groupName),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Accept'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acceptInvite(
    BuildContext context,
    WidgetRef ref,
    String groupId,
    String groupName,
  ) async {
    // Check if we have a pending invite in FFI provider
    final ffiProvider = ref.read(groupFFINotifierProvider);
    final pendingInvite = ffiProvider.pendingInvites
        .where((inv) => inv.groupId == groupId)
        .firstOrNull;

    if (pendingInvite != null) {
      // Accept via FFI
      final success = await GroupService.instance.acceptInvite(groupId);
      if (success && context.mounted) {
        ref.invalidate(conversationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined "$groupName"!')),
        );
        // Navigate to group chat
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(groupId: groupId),
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to join group. Try again.')),
        );
      }
    } else {
      // No pending invite in FFI - show instructions
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite expired. Ask for a new invitation.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _declineInvite(
    BuildContext context,
    WidgetRef ref,
    String groupId,
  ) async {
    final success = await GroupService.instance.declineInvite(groupId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Invitation declined' : 'Failed to decline')),
      );
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
  bool _isRecordingUi = false;

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
          localPath: sendResult.localPath,
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

  Future<bool> _startRecording() async {
    debugPrint('VoiceMessage: Starting recording...');
    final recorder = ref.read(voiceRecorderProvider);
    final started = await recorder.startRecording();
    debugPrint('VoiceMessage: Recording started=$started, state=${recorder.state}');
    if (!started && mounted) {
      final error = recorder.errorMessage ?? 'Failed to start recording';
      debugPrint('VoiceMessage: Recording error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return false;
    }
    return started;
  }

  Future<void> _stopRecordingAndSend() async {
    final recorder = ref.read(voiceRecorderProvider);
    final voiceMessage = await recorder.stopRecording();

    debugPrint('VoiceMessage: stopRecording returned ${voiceMessage != null ? "${voiceMessage.sizeBytes} bytes, ${voiceMessage.duration.inSeconds}s" : "null"}');

    if (voiceMessage == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording failed - no audio captured')),
        );
      }
      return;
    }
    if (!mounted) return;

    // Get peer ID from conversation
    final conversationAsync = ref.read(conversationProvider(widget.conversationId));
    final conversation = conversationAsync.value;
    debugPrint('VoiceMessage: conversation=${conversation?.id}, peerId=${conversation?.peerId}');

    if (conversation == null || conversation.peerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot send voice message: peer not found')),
      );
      return;
    }

    // Send voice message via file transfer
    debugPrint('VoiceMessage: Sending ${voiceMessage.sizeBytes} bytes to ${conversation.peerId}');
    final sendResult = await ref.read(fileActionsProvider).sendFile(
      toPeerId: conversation.peerId!,
      filename: voiceMessage.filename,
      data: voiceMessage.data,
      mimeType: 'audio/mp4',
    );

    debugPrint('VoiceMessage: sendResult success=${sendResult.success}, fileId=${sendResult.fileId}, error=${sendResult.error}');

    if (sendResult.success && sendResult.fileId != null) {
      // Save audio message to conversation
      await ref.read(chatActionsProvider).sendAudioMessage(
        conversationId: widget.conversationId,
        fileId: sendResult.fileId!,
        duration: voiceMessage.duration.inSeconds,
        filename: voiceMessage.filename,
        localPath: sendResult.localPath,
      );
      debugPrint('VoiceMessage: Audio message saved to conversation');
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
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final recorderControl = VoiceRecorder(
      key: const ValueKey('voice_recorder'),
      onRecordingStart: _startRecording,
      onRecordingComplete: (_, __) => _stopRecordingAndSend(),
      onRecordingCancel: _cancelRecording,
      onRecordingStateChanged: (isRecording) {
        if (mounted) {
          setState(() => _isRecordingUi = isRecording);
        }
      },
      activeColor: colorScheme.primary,
      inactiveColor: colorScheme.primary,
    );

    final showRecorder = _isRecordingUi || !_hasText;
    final showSend = !_isRecordingUi && _hasText;

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
            if (!_isRecordingUi)
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
            if (!_isRecordingUi)
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: Builder(
                    builder: (context) {
                      final settings = ref.watch(settingsProvider);
                      return TextField(
                        controller: widget.controller,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: null,
                        onSubmitted: (_) => widget.onSend(),
                        // Incognito keyboard - request keyboard to not learn from typing
                        enableIMEPersonalizedLearning: !settings.incognitoKeyboard,
                      );
                    },
                  ),
                ),
              ),
            if (showSend)
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: widget.onSend,
              ),
            if (showRecorder)
              recorderControl,
          ],
        ),
      ),
    );
  }
}

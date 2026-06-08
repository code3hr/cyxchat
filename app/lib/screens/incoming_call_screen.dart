import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/call_provider.dart';
import 'active_call_screen.dart';

/// Full-screen incoming call overlay
class IncomingCallScreen extends ConsumerStatefulWidget {
  final String peerId;
  final String? peerName;
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.peerId,
    this.peerName,
    required this.isVideo,
  });

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  ProviderSubscription<CallState>? _callSubscription;

  @override
  void initState() {
    super.initState();
    _callSubscription = ref.listenManual<CallState>(
      callNotifierProvider.select((p) => p.state),
      (previous, next) {
        if (!mounted) return;
        if (next.status == CallStatus.ended ||
            next.status == CallStatus.failed ||
            next.status == CallStatus.idle) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  void dispose() {
    _callSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Privacy warning
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Direct P2P connection will be established. Peer can see your IP address.',
                      style: TextStyle(
                        color: Colors.amber.shade100,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Call type indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: widget.isVideo ? Colors.blue.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isVideo ? Icons.videocam : Icons.phone,
                    color: widget.isVideo ? Colors.blue : Colors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
                    style: TextStyle(
                      color: widget.isVideo ? Colors.blue.shade100 : Colors.green.shade100,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Caller avatar
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withOpacity(0.2),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.5),
                  width: 3,
                ),
              ),
              child: Center(
                child: Text(
                  _getInitials(widget.peerName ?? widget.peerId),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Caller name
            Text(
              widget.peerName ?? 'Unknown Caller',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 8),

            // Caller ID (truncated)
            Text(
              _truncatePeerId(widget.peerId),
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
                fontFamily: 'monospace',
              ),
            ),

            const Spacer(flex: 3),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  _CallActionButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    label: 'Decline',
                    onTap: () => _declineCall(context, ref),
                  ),

                  // Accept audio button
                  _CallActionButton(
                    icon: Icons.phone,
                    color: Colors.green,
                    label: 'Audio',
                    onTap: () => _acceptCall(context, ref, video: false),
                  ),

                  // Accept video button (only for video calls)
                  if (widget.isVideo)
                    _CallActionButton(
                      icon: Icons.videocam,
                      color: Colors.blue,
                      label: 'Video',
                      onTap: () => _acceptCall(context, ref, video: true),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  String _truncatePeerId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }

  Future<void> _acceptCall(BuildContext context, WidgetRef ref, {required bool video}) async {
    final success = await ref.read(callActionsProvider).acceptCall();
    if (success && context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ActiveCallScreen(
            peerId: widget.peerId,
            peerName: widget.peerName,
            isVideo: video,
          ),
        ),
      );
    }
  }

  void _declineCall(BuildContext context, WidgetRef ref) {
    ref.read(callActionsProvider).rejectCall();
    Navigator.of(context).pop();
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

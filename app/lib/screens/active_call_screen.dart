import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../providers/call_provider.dart';

/// Active call screen with video and controls
class ActiveCallScreen extends ConsumerStatefulWidget {
  final String peerId;
  final String? peerName;
  final bool isVideo;

  const ActiveCallScreen({
    super.key,
    required this.peerId,
    this.peerName,
    required this.isVideo,
  });

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _showControls = true;
  bool _localVideoMinimized = true;
  bool _closing = false;
  Offset _localVideoPosition = const Offset(16, 100);

  @override
  void initState() {
    super.initState();
    _initRenderers();
    // Hide controls after a few seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _updateStreams();
  }

  void _updateStreams() {
    final callProvider = ref.read(callNotifierProvider);
    if (callProvider.localStream != null) {
      _localRenderer.srcObject = callProvider.localStream;
    }
    if (callProvider.remoteStream != null) {
      _remoteRenderer.srcObject = callProvider.remoteStream;
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callNotifierProvider).state;
    final callProvider = ref.watch(callNotifierProvider);

    // Update renderers when streams change
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateStreams());

    // Handle call ended
    if (callState.status == CallStatus.ended ||
        callState.status == CallStatus.failed ||
        callState.status == CallStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _closeCallScreen();
      });
    }

    return WillPopScope(
      onWillPop: () async {
        await _endCall();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          child: Stack(
            children: [
              // Remote video (full screen) or avatar for audio call
              if (widget.isVideo && callProvider.hasRemoteStream)
                Positioned.fill(
                  child: RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else
                _buildAudioOnlyBackground(callState),

              // Call status overlay (top)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        // Status
                        Text(
                          _getStatusText(callState.status),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Duration
                        if (callState.status == CallStatus.connected)
                          Text(
                            _formatDuration(callState.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        // Peer name
                        const SizedBox(height: 4),
                        Text(
                          widget.peerName ?? 'Peer',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Local video (PiP, draggable)
              if (widget.isVideo &&
                  callProvider.localStream != null &&
                  !callState.isCameraOff)
                Positioned(
                  left: _localVideoPosition.dx,
                  top: _localVideoPosition.dy,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _localVideoPosition = Offset(
                          _localVideoPosition.dx + details.delta.dx,
                          _localVideoPosition.dy + details.delta.dy,
                        );
                      });
                    },
                    onTap: () => setState(
                        () => _localVideoMinimized = !_localVideoMinimized),
                    child: Container(
                      width: _localVideoMinimized ? 100 : 150,
                      height: _localVideoMinimized ? 150 : 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),

              // Controls (bottom)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 32,
                      top: 32,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mute button
                        _ControlButton(
                          icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                          label: callState.isMuted ? 'Unmute' : 'Mute',
                          isActive: callState.isMuted,
                          onTap: ref.read(callActionsProvider).toggleMute,
                        ),

                        // Camera toggle (video calls only)
                        if (widget.isVideo)
                          _ControlButton(
                            icon: callState.isCameraOff
                                ? Icons.videocam_off
                                : Icons.videocam,
                            label: callState.isCameraOff
                                ? 'Camera On'
                                : 'Camera Off',
                            isActive: callState.isCameraOff,
                            onTap: ref.read(callActionsProvider).toggleCamera,
                          ),

                        // End call button
                        _EndCallButton(onTap: _endCall),

                        // Switch camera (video calls only)
                        if (widget.isVideo)
                          _ControlButton(
                            icon: Icons.cameraswitch,
                            label: 'Flip',
                            onTap: ref.read(callActionsProvider).switchCamera,
                          ),

                        // Speaker toggle
                        _ControlButton(
                          icon: callState.isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_off,
                          label: callState.isSpeakerOn ? 'Speaker' : 'Earpiece',
                          isActive: !callState.isSpeakerOn,
                          onTap: ref.read(callActionsProvider).toggleSpeaker,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Connection quality indicator
              if (callState.status == CallStatus.reconnecting)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Reconnecting...',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioOnlyBackground(CallState callState) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  width: 3,
                ),
              ),
              child: Center(
                child: Text(
                  _getInitials(widget.peerName ?? widget.peerId),
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Peer name
            Text(
              widget.peerName ?? 'Peer',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            // Duration or status
            Text(
              callState.status == CallStatus.connected
                  ? _formatDuration(callState.duration)
                  : _getStatusText(callState.status),
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(CallStatus status) {
    switch (status) {
      case CallStatus.connecting:
        return 'Connecting...';
      case CallStatus.outgoing:
        return 'Calling...';
      case CallStatus.incoming:
        return 'Incoming call';
      case CallStatus.connected:
        return 'Connected';
      case CallStatus.reconnecting:
        return 'Reconnecting...';
      case CallStatus.ended:
        return 'Call ended';
      case CallStatus.failed:
        return 'Call failed';
      default:
        return '';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  Future<void> _endCall() async {
    await ref.read(callActionsProvider).endCall();
    _closeCallScreen();
  }

  void _closeCallScreen() {
    if (_closing || !mounted) return;
    _closing = true;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.2),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black : Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Colors.red,
            ),
            child: const Icon(
              Icons.call_end,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'End',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

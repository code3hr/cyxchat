import 'dart:async';
import 'package:flutter/material.dart';

/// Callback when recording completes with audio data
typedef VoiceRecordingCallback = void Function(
  List<int> audioData,
  int durationMs,
);

/// Widget for recording voice messages
/// Shows a record button that can be pressed and held to record
class VoiceRecorder extends StatefulWidget {
  final VoiceRecordingCallback onRecordingComplete;
  final VoidCallback? onRecordingStart;
  final VoidCallback? onRecordingCancel;
  final int maxDurationMs;
  final Color? activeColor;
  final Color? inactiveColor;

  const VoiceRecorder({
    super.key,
    required this.onRecordingComplete,
    this.onRecordingStart,
    this.onRecordingCancel,
    this.maxDurationMs = 60000, // 60 seconds default
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  int _recordingDurationMs = 0;
  Timer? _durationTimer;
  Offset _dragOffset = Offset.zero;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _cancelThreshold = -80.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = widget.activeColor ?? Colors.red;
    final inactiveColor = widget.inactiveColor ?? colorScheme.primary;

    if (_isRecording) {
      return _buildRecordingUI(colorScheme, activeColor);
    }

    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: inactiveColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.mic,
          color: inactiveColor,
        ),
      ),
    );
  }

  Widget _buildRecordingUI(ColorScheme colorScheme, Color activeColor) {
    final durationStr = _formatDuration(_recordingDurationMs);
    final isCancelling = _dragOffset.dx < _cancelThreshold;

    return GestureDetector(
      onLongPressEnd: (_) => _stopRecording(),
      onLongPressMoveUpdate: (details) {
        setState(() {
          _dragOffset = details.localOffsetFromOrigin;
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cancel indicator
          AnimatedOpacity(
            opacity: isCancelling ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 100),
            child: Text(
              '< Slide to cancel',
              style: TextStyle(
                color: isCancelling ? Colors.red : colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Duration
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
                  durationStr,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Mic button (pulsing)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _startRecording() async {
    setState(() {
      _isRecording = true;
      _recordingDurationMs = 0;
      _dragOffset = Offset.zero;
    });

    _pulseController.repeat(reverse: true);

    // Start duration timer
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _recordingDurationMs += 100;
      });

      // Auto-stop at max duration
      if (_recordingDurationMs >= widget.maxDurationMs) {
        _stopRecording();
      }
    });

    widget.onRecordingStart?.call();

    // TODO: Start actual audio recording using record package
    // For now, this is a UI-only implementation
  }

  void _stopRecording() {
    _durationTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    final wasCancelled = _dragOffset.dx < _cancelThreshold;

    if (wasCancelled) {
      widget.onRecordingCancel?.call();
    } else if (_recordingDurationMs > 500) {
      // Minimum 500ms recording
      // TODO: Get actual audio data from recorder
      // For now, return empty data with the duration
      widget.onRecordingComplete([], _recordingDurationMs);
    }

    setState(() {
      _isRecording = false;
      _recordingDurationMs = 0;
      _dragOffset = Offset.zero;
    });
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).floor();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

/// Compact voice recorder button for chat input bar
class VoiceRecorderButton extends StatelessWidget {
  final VoiceRecordingCallback onRecordingComplete;
  final bool isEnabled;

  const VoiceRecorderButton({
    super.key,
    required this.onRecordingComplete,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!isEnabled) {
      return IconButton(
        icon: Icon(Icons.mic, color: colorScheme.onSurface.withOpacity(0.3)),
        onPressed: null,
      );
    }

    return VoiceRecorder(
      onRecordingComplete: onRecordingComplete,
    );
  }
}

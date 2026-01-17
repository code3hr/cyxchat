import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/message.dart';

/// Widget to display media content in message bubbles
/// Handles image, video, voice, and file message types
class MediaMessageContent extends StatelessWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;

  const MediaMessageContent({
    super.key,
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
    this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return _ImageContent(
          message: message,
          isOutgoing: isOutgoing,
          colorScheme: colorScheme,
          onTap: onTap,
        );
      case MessageType.video:
        return _VideoContent(
          message: message,
          isOutgoing: isOutgoing,
          colorScheme: colorScheme,
          onTap: onTap,
        );
      case MessageType.voice:
        return _VoiceContent(
          message: message,
          isOutgoing: isOutgoing,
          colorScheme: colorScheme,
        );
      case MessageType.audio:
        return _AudioContent(
          message: message,
          isOutgoing: isOutgoing,
          colorScheme: colorScheme,
        );
      case MessageType.file:
        return _FileContent(
          message: message,
          isOutgoing: isOutgoing,
          colorScheme: colorScheme,
          onDownload: onDownload,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Image message content with thumbnail
class _ImageContent extends StatelessWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  const _ImageContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = _parseMetadata();
    final width = metadata['width'] as int? ?? 200;
    final height = metadata['height'] as int? ?? 150;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 250,
            maxHeight: 300,
          ),
          child: _buildImage(width, height),
        ),
      ),
    );
  }

  Widget _buildImage(int width, int height) {
    // If thumbnail path exists, show the thumbnail
    if (message.thumbnailPath != null &&
        File(message.thumbnailPath!).existsSync()) {
      return Image.file(
        File(message.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(width, height),
      );
    }

    // If content is a file path, show the image
    if (message.content.isNotEmpty && File(message.content).existsSync()) {
      return Image.file(
        File(message.content),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(width, height),
      );
    }

    return _placeholder(width, height);
  }

  Widget _placeholder(int width, int height) {
    final aspectRatio = width / height;
    return AspectRatio(
      aspectRatio: aspectRatio.clamp(0.5, 2.0),
      child: Container(
        color: isOutgoing
            ? colorScheme.primary.withOpacity(0.3)
            : colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.image,
            size: 48,
            color: isOutgoing
                ? colorScheme.onPrimary.withOpacity(0.5)
                : colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _parseMetadata() {
    if (message.mediaMetadata == null) return {};
    try {
      return jsonDecode(message.mediaMetadata!) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

/// Video message content with play button overlay
class _VideoContent extends StatelessWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  const _VideoContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = _parseMetadata();
    final duration = metadata['duration'] as int? ?? 0;
    final durationStr = _formatDuration(duration);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 250,
            maxHeight: 300,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildThumbnail(),
              // Play button overlay
              Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              // Duration badge
              if (duration > 0)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      durationStr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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

  Widget _buildThumbnail() {
    if (message.thumbnailPath != null &&
        File(message.thumbnailPath!).existsSync()) {
      return Image.file(
        File(message.thumbnailPath!),
        fit: BoxFit.cover,
        width: double.infinity,
      );
    }

    return Container(
      width: 200,
      height: 150,
      color: isOutgoing
          ? colorScheme.primary.withOpacity(0.3)
          : colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.videocam,
          size: 48,
          color: isOutgoing
              ? colorScheme.onPrimary.withOpacity(0.5)
              : colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
    );
  }

  Map<String, dynamic> _parseMetadata() {
    if (message.mediaMetadata == null) return {};
    try {
      return jsonDecode(message.mediaMetadata!) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).floor();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

/// Voice message content with waveform visualization
class _VoiceContent extends StatefulWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;

  const _VoiceContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
  });

  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent> {
  bool _isPlaying = false;
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    final metadata = _parseMetadata();
    final duration = metadata['duration'] as int? ?? 0;
    final durationStr = _formatDuration(duration);

    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Play/pause button
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isOutgoing
                    ? Colors.white.withOpacity(0.2)
                    : widget.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: widget.isOutgoing
                    ? Colors.white
                    : widget.colorScheme.primary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Waveform/progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWaveform(),
                const SizedBox(height: 4),
                Text(
                  durationStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.isOutgoing
                        ? Colors.white.withOpacity(0.7)
                        : widget.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 20,
      child: CustomPaint(
        painter: _WaveformPainter(
          progress: _progress,
          color: widget.isOutgoing
              ? Colors.white
              : widget.colorScheme.primary,
          backgroundColor: widget.isOutgoing
              ? Colors.white.withOpacity(0.3)
              : widget.colorScheme.primary.withOpacity(0.2),
        ),
        size: const Size(double.infinity, 20),
      ),
    );
  }

  void _togglePlayback() {
    // TODO: Implement actual audio playback
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  Map<String, dynamic> _parseMetadata() {
    if (widget.message.mediaMetadata == null) return {};
    try {
      return jsonDecode(widget.message.mediaMetadata!) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).floor();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

/// Simple waveform painter for voice messages
class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _WaveformPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 3.0;
    final spacing = 2.0;
    final barCount = (size.width / (barWidth + spacing)).floor();
    final progressBars = (barCount * progress).floor();

    // Simulated waveform heights
    final heights = List.generate(barCount, (i) {
      return 0.3 + 0.7 * ((i * 7) % 10) / 10;
    });

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final barHeight = size.height * heights[i];
      final y = (size.height - barHeight) / 2;

      final paint = Paint()
        ..color = i < progressBars ? color : backgroundColor
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Audio message content (music files)
class _AudioContent extends StatelessWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;

  const _AudioContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = _parseMetadata();
    final filename = metadata['filename'] as String? ?? 'Audio file';
    final duration = metadata['duration'] as int? ?? 0;
    final durationStr = _formatDuration(duration);

    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOutgoing
                  ? Colors.white.withOpacity(0.2)
                  : colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.audiotrack,
              color: isOutgoing ? Colors.white : colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isOutgoing ? Colors.white : colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (duration > 0)
                  Text(
                    durationStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: isOutgoing
                          ? Colors.white.withOpacity(0.7)
                          : colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _parseMetadata() {
    if (message.mediaMetadata == null) return {};
    try {
      return jsonDecode(message.mediaMetadata!) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).floor();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

/// File message content
class _FileContent extends StatelessWidget {
  final Message message;
  final bool isOutgoing;
  final ColorScheme colorScheme;
  final VoidCallback? onDownload;

  const _FileContent({
    required this.message,
    required this.isOutgoing,
    required this.colorScheme,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = _parseMetadata();
    final filename = metadata['filename'] as String? ?? 'File';
    final size = metadata['size'] as int? ?? 0;
    final sizeStr = _formatFileSize(size);

    return GestureDetector(
      onTap: onDownload,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isOutgoing
                    ? Colors.white.withOpacity(0.2)
                    : colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(filename),
                color: isOutgoing ? Colors.white : colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filename,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isOutgoing ? Colors.white : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (size > 0)
                    Text(
                      sizeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: isOutgoing
                            ? Colors.white.withOpacity(0.7)
                            : colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                ],
              ),
            ),
            if (onDownload != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.download,
                size: 20,
                color: isOutgoing
                    ? Colors.white.withOpacity(0.7)
                    : colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Map<String, dynamic> _parseMetadata() {
    if (message.mediaMetadata == null) return {};
    try {
      return jsonDecode(message.mediaMetadata!) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

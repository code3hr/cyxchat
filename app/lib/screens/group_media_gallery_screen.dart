import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../services/database_service.dart';

/// Screen for browsing media shared in a group
/// Displays media in a grid with tabs for different media types
class GroupMediaGalleryScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const GroupMediaGalleryScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<GroupMediaGalleryScreen> createState() =>
      _GroupMediaGalleryScreenState();
}

class _GroupMediaGalleryScreenState
    extends ConsumerState<GroupMediaGalleryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Message> _allMedia = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadMedia();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    setState(() => _isLoading = true);

    try {
      final db = await DatabaseService.instance.database;

      // Load all messages with media from this group's conversation
      final results = await db.query(
        'messages',
        where:
            'conversation_id = ? AND media_type IS NOT NULL AND is_deleted = 0',
        whereArgs: [widget.groupId],
        orderBy: 'timestamp DESC',
      );

      _allMedia = results.map((map) => Message.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error loading media: $e');
    }

    setState(() => _isLoading = false);
  }

  List<Message> _getFilteredMedia(MediaType? filterType) {
    if (filterType == null) return _allMedia;
    return _allMedia.where((m) => m.mediaType == filterType).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.groupName} Media'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.photo_library), text: 'All'),
            Tab(icon: Icon(Icons.image), text: 'Images'),
            Tab(icon: Icon(Icons.videocam), text: 'Videos'),
            Tab(icon: Icon(Icons.insert_drive_file), text: 'Files'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _MediaGridView(
                  media: _getFilteredMedia(null),
                  colorScheme: colorScheme,
                  onMediaTap: _openMedia,
                ),
                _MediaGridView(
                  media: _getFilteredMedia(MediaType.image),
                  colorScheme: colorScheme,
                  onMediaTap: _openMedia,
                ),
                _MediaGridView(
                  media: _getFilteredMedia(MediaType.video),
                  colorScheme: colorScheme,
                  onMediaTap: _openMedia,
                ),
                _FileListView(
                  media: _allMedia
                      .where((m) =>
                          m.mediaType == MediaType.document ||
                          m.mediaType == MediaType.archive ||
                          m.mediaType == MediaType.other)
                      .toList(),
                  colorScheme: colorScheme,
                  onFileTap: _openFile,
                ),
              ],
            ),
    );
  }

  void _openMedia(Message message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _MediaViewerScreen(message: message),
      ),
    );
  }

  void _openFile(Message message) {
    // TODO: Open file with system handler
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening ${message.content}...')),
    );
  }
}

/// Grid view for images and videos
class _MediaGridView extends StatelessWidget {
  final List<Message> media;
  final ColorScheme colorScheme;
  final void Function(Message) onMediaTap;

  const _MediaGridView({
    required this.media,
    required this.colorScheme,
    required this.onMediaTap,
  });

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No media yet',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: media.length,
      itemBuilder: (context, index) {
        final message = media[index];
        return _MediaThumbnail(
          message: message,
          colorScheme: colorScheme,
          onTap: () => onMediaTap(message),
        );
      },
    );
  }
}

/// Individual media thumbnail in grid
class _MediaThumbnail extends StatelessWidget {
  final Message message;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _MediaThumbnail({
    required this.message,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildThumbnail(),
              if (message.mediaType == MediaType.video) _buildVideoOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    // Check for thumbnail
    if (message.thumbnailPath != null &&
        File(message.thumbnailPath!).existsSync()) {
      return Image.file(
        File(message.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    // Check for actual file
    if (message.content.isNotEmpty && File(message.content).existsSync()) {
      return Image.file(
        File(message.content),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          message.mediaType == MediaType.video ? Icons.videocam : Icons.image,
          color: colorScheme.onSurface.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildVideoOverlay() {
    return Positioned(
      bottom: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.play_arrow,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }
}

/// List view for files
class _FileListView extends StatelessWidget {
  final List<Message> media;
  final ColorScheme colorScheme;
  final void Function(Message) onFileTap;

  const _FileListView({
    required this.media,
    required this.colorScheme,
    required this.onFileTap,
  });

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No files yet',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: media.length,
      itemBuilder: (context, index) {
        final message = media[index];
        return _FileListTile(
          message: message,
          colorScheme: colorScheme,
          onTap: () => onFileTap(message),
        );
      },
    );
  }
}

/// Individual file list item
class _FileListTile extends StatelessWidget {
  final Message message;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _FileListTile({
    required this.message,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filename = message.content.split('/').last;
    final ext = filename.split('.').last.toLowerCase();

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getFileIcon(ext),
          color: colorScheme.primary,
        ),
      ),
      title: Text(
        filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        message.timeString,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
      trailing: Icon(
        Icons.download_outlined,
        color: colorScheme.primary,
      ),
    );
  }

  IconData _getFileIcon(String ext) {
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
}

/// Full-screen media viewer
class _MediaViewerScreen extends StatelessWidget {
  final Message message;

  const _MediaViewerScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(message.timeString),
      ),
      body: Center(
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (message.mediaType == MediaType.video) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.videocam,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          const Text(
            'Video playback not implemented',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      );
    }

    // Try to load image
    if (message.content.isNotEmpty && File(message.content).existsSync()) {
      return InteractiveViewer(
        child: Image.file(
          File(message.content),
          fit: BoxFit.contain,
        ),
      );
    }

    if (message.thumbnailPath != null &&
        File(message.thumbnailPath!).existsSync()) {
      return InteractiveViewer(
        child: Image.file(
          File(message.thumbnailPath!),
          fit: BoxFit.contain,
        ),
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.broken_image,
          size: 64,
          color: Colors.white54,
        ),
        SizedBox(height: 16),
        Text(
          'Image not available',
          style: TextStyle(color: Colors.white54),
        ),
      ],
    );
  }
}

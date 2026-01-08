import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../services/log_service.dart';

/// Provider for log service
final logServiceProvider = ChangeNotifierProvider<LogService>((ref) {
  return LogService.instance;
});

/// Log viewer screen
class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen> {
  LogLevel _selectedFilter = LogLevel.all;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logService = ref.watch(logServiceProvider);
    final logs = _selectedFilter == LogLevel.all
        ? logService.logs
        : logService.filteredLogs;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(
                Icons.article_outlined,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Logs',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          // Export button
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Export logs',
            onPressed: () => _exportLogs(logService),
          ),
          // Clear button
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear logs',
            onPressed: () => _showClearDialog(logService),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: LogLevel.values.map((level) {
                  final isSelected = _selectedFilter == level;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(level.label),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = level;
                          logService.setFilter(level);
                        });
                      },
                      backgroundColor: AppColors.bgDarkSecondary,
                      selectedColor: _getLevelColor(level).withOpacity(0.2),
                      checkmarkColor: _getLevelColor(level),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? _getLevelColor(level)
                            : AppColors.textDarkSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? _getLevelColor(level).withOpacity(0.5)
                            : AppColors.bgDarkTertiary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Log count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${logs.length} logs',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDarkSecondary.withOpacity(0.7),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                  label: const Text('Newest'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textDarkSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.bgDarkTertiary),

          // Log list
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 48,
                          color: AppColors.textDarkSecondary.withOpacity(0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No logs yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textDarkSecondary.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Logs will appear here as you use the app',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textDarkSecondary.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return _LogEntryTile(entry: log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return AppColors.textDarkSecondary;
      case LogLevel.info:
        return AppColors.accent;
      case LogLevel.warning:
        return AppColors.accentOrange;
      case LogLevel.error:
        return AppColors.error;
      case LogLevel.all:
        return AppColors.primary;
    }
  }

  void _exportLogs(LogService logService) {
    final exported = logService.export();
    Clipboard.setData(ClipboardData(text: exported));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Logs copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showClearDialog(LogService logService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs?'),
        content: const Text('This will delete all log entries.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              logService.clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// Individual log entry tile
class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Log entry copied'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level indicator
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: _getLevelColor(entry.level),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      // Time
                      Text(
                        entry.formattedTime,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.textDarkSecondary.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Level badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getLevelColor(entry.level).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.level,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: _getLevelColor(entry.level),
                          ),
                        ),
                      ),
                      // Source badge
                      if (entry.source != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bgDarkTertiary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.source!,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textDarkSecondary.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Message
                  Text(
                    entry.message,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textDark.withOpacity(0.9),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'DEBUG':
        return AppColors.textDarkSecondary;
      case 'INFO':
        return AppColors.accent;
      case 'WARN':
        return AppColors.accentOrange;
      case 'ERROR':
        return AppColors.error;
      default:
        return AppColors.textDarkSecondary;
    }
  }
}

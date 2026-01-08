import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Log entry with timestamp and level
class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? source;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    final src = source != null ? '[$source] ' : '';
    return '[$formattedTime] [$level] $src$message';
  }
}

/// Log level filter
enum LogLevel {
  debug,
  info,
  warning,
  error,
  all;

  String get label {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.all:
        return 'ALL';
    }
  }
}

/// Singleton logging service that captures app logs
class LogService extends ChangeNotifier {
  static final LogService _instance = LogService._internal();
  static LogService get instance => _instance;

  LogService._internal();

  // Circular buffer of logs (keep last 500 entries)
  static const int _maxLogs = 500;
  final Queue<LogEntry> _logs = Queue<LogEntry>();

  // Current filter
  LogLevel _filter = LogLevel.all;
  LogLevel get filter => _filter;

  /// Get all logs (newest first)
  List<LogEntry> get logs => _logs.toList().reversed.toList();

  /// Get filtered logs
  List<LogEntry> get filteredLogs {
    if (_filter == LogLevel.all) return logs;
    return logs.where((log) => log.level == _filter.label).toList();
  }

  /// Set log filter
  void setFilter(LogLevel level) {
    _filter = level;
    notifyListeners();
  }

  /// Add a log entry
  void log(String level, String message, {String? source}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      source: source,
    );

    _logs.add(entry);

    // Trim old logs
    while (_logs.length > _maxLogs) {
      _logs.removeFirst();
    }

    notifyListeners();
  }

  /// Convenience methods
  void debug(String message, {String? source}) => log('DEBUG', message, source: source);
  void info(String message, {String? source}) => log('INFO', message, source: source);
  void warning(String message, {String? source}) => log('WARN', message, source: source);
  void error(String message, {String? source}) => log('ERROR', message, source: source);

  /// Clear all logs
  void clear() {
    _logs.clear();
    notifyListeners();
  }

  /// Export logs as text
  String export() {
    final buffer = StringBuffer();
    buffer.writeln('=== CyxChat Logs ===');
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln('');
    for (final log in logs.reversed) {
      buffer.writeln(log.toString());
    }
    return buffer.toString();
  }
}

/// Custom debug print that also logs to LogService
void appLog(String message, {String? source, String level = 'DEBUG'}) {
  // Also print to console in debug mode
  debugPrint(message);

  // Add to log service
  LogService.instance.log(level, message, source: source);
}

/// Capture Flutter's debugPrint output
void setupLogging() {
  // Override debugPrint to capture logs
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;

    // Parse source from common patterns
    String? source;
    String logMessage = message;
    String level = 'DEBUG';

    // Parse [timestamp] [LEVEL] format from C library
    if (message.contains('[INFO]')) {
      level = 'INFO';
      source = 'Native';
    } else if (message.contains('[WARN]')) {
      level = 'WARN';
      source = 'Native';
    } else if (message.contains('[ERROR]')) {
      level = 'ERROR';
      source = 'Native';
    } else if (message.startsWith('VoiceRecorder:')) {
      source = 'Voice';
      logMessage = message.substring('VoiceRecorder:'.length).trim();
    } else if (message.startsWith('VoiceMessage:')) {
      source = 'Voice';
      logMessage = message.substring('VoiceMessage:'.length).trim();
    } else if (message.startsWith('ChatService:')) {
      source = 'Chat';
      logMessage = message.substring('ChatService:'.length).trim();
    } else if (message.startsWith('ChatScreen:')) {
      source = 'Chat';
      logMessage = message.substring('ChatScreen:'.length).trim();
    } else if (message.startsWith('FileProvider:')) {
      source = 'File';
      logMessage = message.substring('FileProvider:'.length).trim();
    } else if (message.startsWith('CyxChat:')) {
      source = 'App';
      logMessage = message.substring('CyxChat:'.length).trim();
    }

    LogService.instance.log(level, logMessage, source: source);

    // Also print to console (use debugPrintSynchronously to avoid recursion)
    debugPrintSynchronously(message, wrapWidth: wrapWidth);
  };
}

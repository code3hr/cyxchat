import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../providers/settings_provider.dart';
import 'log_service.dart';

/// Callback type for handling notification taps
typedef NotificationTapCallback = void Function(String conversationId);

/// Service for displaying local notifications when messages arrive.
///
/// Supports:
/// - Linux, macOS (desktop platforms)
/// - Android, iOS (mobile platforms)
///
/// Respects user's notification preview settings:
/// - Full: shows sender name and message content
/// - Sender only: shows sender name, hides message content
/// - None: shows "New Message" only
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  NotificationTapCallback? onNotificationTap;

  /// Current notification preview setting
  NotificationPreview _previewLevel = NotificationPreview.full;

  /// Track if app is in foreground (don't show notifications when app is visible)
  bool _appInForeground = true;
  bool get appInForeground => _appInForeground;
  set appInForeground(bool value) => _appInForeground = value;

  /// Notification channel ID (Android)
  static const String _channelId = 'cyxchat_messages';
  static const String _channelName = 'Messages';
  static const String _channelDescription = 'New message notifications';

  bool get _platformSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;

  /// Initialize the notification plugin
  Future<bool> initialize() async {
    if (_initialized) return true;

    final log = LogService.instance;

    if (!_platformSupported) {
      log.info(
        'Local notifications are not supported on this platform',
        source: 'Notifications',
      );
      return true;
    }

    try {
      // Platform-specific initialization settings
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open notification',
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      // Initialize with tap handler
      final result = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );

      if (result == true) {
        _initialized = true;
        log.info('Notification service initialized', source: 'Notifications');

        // Create notification channel for Android
        if (Platform.isAndroid) {
          await _createAndroidChannel();
          await _requestAndroidNotificationPermission();
        }

        return true;
      } else {
        log.warning('Notification initialization returned false',
            source: 'Notifications');
        return false;
      }
    } catch (e) {
      log.error('Failed to initialize notifications: $e',
          source: 'Notifications');
      return false;
    }
  }

  /// Create Android notification channel
  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Request runtime notification permission on Android 13+.
  Future<void> _requestAndroidNotificationPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await androidPlugin?.requestNotificationsPermission();
    if (granted == false) {
      LogService.instance.warning(
        'Android notification permission was denied',
        source: 'Notifications',
      );
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(NotificationResponse response) {
    final log = LogService.instance;
    final payload = response.payload;

    if (payload != null && onNotificationTap != null) {
      log.info('Notification tapped for conversation: $payload',
          source: 'Notifications');
      onNotificationTap!(payload);
    }
  }

  /// Update notification preview level from settings
  void setPreviewLevel(NotificationPreview level) {
    _previewLevel = level;
  }

  /// Stable notification ID for a conversation.
  /// Avoids `String.hashCode`, which is not guaranteed to stay stable across runs.
  int _notificationIdForConversation(String conversationId) {
    var hash = 0x811C9DC5;
    for (final unit in conversationId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Show a notification for an incoming message
  ///
  /// [conversationId] - The conversation ID (used as payload for navigation)
  /// [senderName] - Display name or ID of the sender
  /// [messageContent] - The message content (may be hidden based on settings)
  /// [isGroupMessage] - Whether this is a group message
  /// [groupName] - Name of the group (if group message)
  Future<void> showMessageNotification({
    required String conversationId,
    required String senderName,
    required String messageContent,
    bool isGroupMessage = false,
    String? groupName,
  }) async {
    if (!_platformSupported) return;

    if (!_initialized) {
      debugPrint('Notification service not initialized');
      return;
    }

    // Don't show notification if app is in foreground
    if (_appInForeground) {
      debugPrint('Skipping notification - app in foreground');
      return;
    }

    final log = LogService.instance;

    // Format notification based on preview level
    String title;
    String body;

    switch (_previewLevel) {
      case NotificationPreview.full:
        if (isGroupMessage && groupName != null) {
          title = groupName;
          body = '$senderName: $messageContent';
        } else {
          title = senderName;
          body = messageContent;
        }
        break;

      case NotificationPreview.senderOnly:
        if (isGroupMessage && groupName != null) {
          title = groupName;
          body = 'Message from $senderName';
        } else {
          title = senderName;
          body = 'New message';
        }
        break;

      case NotificationPreview.none:
        title = 'CyxChat';
        body = 'New message';
        break;
    }

    // Truncate long messages
    if (body.length > 100) {
      body = '${body.substring(0, 97)}...';
    }

    try {
      // Generate a unique notification ID based on conversation
      final notificationId = _notificationIdForConversation(conversationId);

      // Platform-specific notification details
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        autoCancel: true,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const linuxDetails = LinuxNotificationDetails();

      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
        linux: linuxDetails,
      );

      await _plugin.show(
        notificationId,
        title,
        body,
        details,
        payload: conversationId,
      );

      log.debug('Showed notification for $conversationId: $title',
          source: 'Notifications');
    } catch (e) {
      log.error('Failed to show notification: $e', source: 'Notifications');
    }
  }

  /// Cancel notifications for a specific conversation
  Future<void> cancelConversationNotifications(String conversationId) async {
    if (!_initialized) return;

    try {
      await _plugin.cancel(_notificationIdForConversation(conversationId));
    } catch (e) {
      debugPrint('Failed to cancel notification: $e');
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    if (!_initialized) return;

    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Failed to cancel all notifications: $e');
    }
  }

  /// Request notification permissions (iOS/macOS)
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    } else if (Platform.isMacOS) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    }
    return true; // Other platforms don't need explicit permission
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyxchat/theme/app_themes.dart';

/// Settings keys
class SettingsKeys {
  static const String bootstrapServer = 'bootstrap_server';
  static const String relayServer = 'relay_server';
  static const String directFileTransfer = 'direct_file_transfer';
  static const String videoCallsEnabled = 'video_calls_enabled';
  static const String hasSeenCallPrivacyWarning = 'has_seen_call_privacy_warning';
  static const String onionHopCount = 'onion_hop_count';
  // Appearance settings
  static const String theme = 'app_theme';
  static const String fontFamily = 'font_family';
  static const String fontScale = 'font_scale';
  static const String chatWallpaper = 'chat_wallpaper';
  static const String bubbleRadius = 'bubble_radius';
  static const String showMessagePreview = 'show_message_preview';
  // Presence settings
  static const String presenceSyncEnabled = 'presence_sync_enabled';
  // Security settings
  static const String appLockEnabled = 'app_lock_enabled';
  static const String appLockTimeout = 'app_lock_timeout';
  static const String screenSecurityEnabled = 'screen_security_enabled';
  static const String hideInAppSwitcher = 'hide_in_app_switcher';
  static const String disappearingMessagesDefault = 'disappearing_messages_default';
  static const String sendReadReceipts = 'send_read_receipts';
  static const String sendTypingIndicators = 'send_typing_indicators';
  static const String notificationPreview = 'notification_preview';
  static const String incognitoKeyboard = 'incognito_keyboard';
}

/// Check for dart-define override
/// Set via --dart-define=BOOTSTRAP_SERVER=127.0.0.1:7777
const String _bootstrapServerOverride = String.fromEnvironment('BOOTSTRAP_SERVER', defaultValue: '');

/// Notification preview options
enum NotificationPreview {
  full,        // Show sender and message
  senderOnly,  // Show sender name only
  none,        // Show "New Message" only
}

/// Default values
class SettingsDefaults {
  // Default to public CyxChat server
  // Users can change in Settings → Network → Bootstrap Server
  static String get bootstrapServer => _bootstrapServerOverride.isNotEmpty
      ? _bootstrapServerOverride
      : '129.151.146.219:7777';
  static const String relayServer = '';
  static const bool directFileTransfer = false;
  static const bool videoCallsEnabled = false; // Off by default for privacy
  static const bool hasSeenCallPrivacyWarning = false;
  static const int onionHopCount = 1; // Default 1 hop (direct, best reliability)
  // Appearance defaults
  static const AppTheme theme = AppTheme.cyxchat; // Original CyxChat theme
  static const AppFont fontFamily = AppFont.system;
  static const FontScale fontScale = FontScale.medium;
  static const String? chatWallpaper = null; // No wallpaper by default
  static const double bubbleRadius = 12.0;
  static const bool showMessagePreview = true;
  // Presence defaults
  static const bool presenceSyncEnabled = true; // On by default
  // Security defaults
  static const bool appLockEnabled = false;
  static const int appLockTimeout = 60; // 1 minute
  static const bool screenSecurityEnabled = false;
  static const bool hideInAppSwitcher = false;
  static const int? disappearingMessagesDefault = null; // Off by default
  static const bool sendReadReceipts = true;
  static const bool sendTypingIndicators = true;
  static const NotificationPreview notificationPreview = NotificationPreview.full;
  static const bool incognitoKeyboard = false;
}

/// Settings state
class AppSettings {
  final String bootstrapServer;
  final String relayServer;
  final bool directFileTransfer;
  final bool videoCallsEnabled;
  final bool hasSeenCallPrivacyWarning;
  final int onionHopCount;
  // Appearance settings
  final AppTheme theme;
  final AppFont fontFamily;
  final FontScale fontScale;
  final String? chatWallpaper;
  final double bubbleRadius;
  final bool showMessagePreview;
  // Presence settings
  final bool presenceSyncEnabled;
  // Security settings
  final bool appLockEnabled;
  final int appLockTimeout; // seconds
  final bool screenSecurityEnabled;
  final bool hideInAppSwitcher;
  final int? disappearingMessagesDefault; // seconds, null = off
  final bool sendReadReceipts;
  final bool sendTypingIndicators;
  final NotificationPreview notificationPreview;
  final bool incognitoKeyboard;

  const AppSettings({
    this.bootstrapServer = '',
    this.relayServer = '',
    this.directFileTransfer = false,
    this.videoCallsEnabled = false,
    this.hasSeenCallPrivacyWarning = false,
    this.onionHopCount = 1,
    this.theme = AppTheme.cyxchat,
    this.fontFamily = AppFont.system,
    this.fontScale = FontScale.medium,
    this.chatWallpaper,
    this.bubbleRadius = 12.0,
    this.showMessagePreview = true,
    // Presence settings
    this.presenceSyncEnabled = true,
    // Security defaults
    this.appLockEnabled = false,
    this.appLockTimeout = 60,
    this.screenSecurityEnabled = false,
    this.hideInAppSwitcher = false,
    this.disappearingMessagesDefault,
    this.sendReadReceipts = true,
    this.sendTypingIndicators = true,
    this.notificationPreview = NotificationPreview.full,
    this.incognitoKeyboard = false,
  });

  AppSettings copyWith({
    String? bootstrapServer,
    String? relayServer,
    bool? directFileTransfer,
    bool? videoCallsEnabled,
    bool? hasSeenCallPrivacyWarning,
    int? onionHopCount,
    AppTheme? theme,
    AppFont? fontFamily,
    FontScale? fontScale,
    String? chatWallpaper,
    bool clearWallpaper = false,
    double? bubbleRadius,
    bool? showMessagePreview,
    // Presence settings
    bool? presenceSyncEnabled,
    // Security settings
    bool? appLockEnabled,
    int? appLockTimeout,
    bool? screenSecurityEnabled,
    bool? hideInAppSwitcher,
    int? disappearingMessagesDefault,
    bool clearDisappearingMessages = false,
    bool? sendReadReceipts,
    bool? sendTypingIndicators,
    NotificationPreview? notificationPreview,
    bool? incognitoKeyboard,
  }) {
    return AppSettings(
      bootstrapServer: bootstrapServer ?? this.bootstrapServer,
      relayServer: relayServer ?? this.relayServer,
      directFileTransfer: directFileTransfer ?? this.directFileTransfer,
      videoCallsEnabled: videoCallsEnabled ?? this.videoCallsEnabled,
      hasSeenCallPrivacyWarning: hasSeenCallPrivacyWarning ?? this.hasSeenCallPrivacyWarning,
      onionHopCount: onionHopCount ?? this.onionHopCount,
      theme: theme ?? this.theme,
      fontFamily: fontFamily ?? this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
      chatWallpaper: clearWallpaper ? null : (chatWallpaper ?? this.chatWallpaper),
      bubbleRadius: bubbleRadius ?? this.bubbleRadius,
      showMessagePreview: showMessagePreview ?? this.showMessagePreview,
      // Presence settings
      presenceSyncEnabled: presenceSyncEnabled ?? this.presenceSyncEnabled,
      // Security settings
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      appLockTimeout: appLockTimeout ?? this.appLockTimeout,
      screenSecurityEnabled: screenSecurityEnabled ?? this.screenSecurityEnabled,
      hideInAppSwitcher: hideInAppSwitcher ?? this.hideInAppSwitcher,
      disappearingMessagesDefault: clearDisappearingMessages ? null : (disappearingMessagesDefault ?? this.disappearingMessagesDefault),
      sendReadReceipts: sendReadReceipts ?? this.sendReadReceipts,
      sendTypingIndicators: sendTypingIndicators ?? this.sendTypingIndicators,
      notificationPreview: notificationPreview ?? this.notificationPreview,
      incognitoKeyboard: incognitoKeyboard ?? this.incognitoKeyboard,
    );
  }

  /// Get combined server string for connection
  /// Format: "ip:port" for bootstrap, same server used for relay
  String get connectionBootstrap => bootstrapServer;

  /// Get payload capacity for current hop count
  String get hopPayloadCapacity {
    switch (onionHopCount) {
      case 1: return '1.3 KB';
      case 2: return '1.2 KB';
      case 3: return '1.1 KB';
      case 4: return '977 B';
      case 5: return '873 B';
      case 6: return '769 B';
      case 7: return '665 B';
      case 8: return '561 B';
      default: return '1.2 KB';
    }
  }
}

/// Settings notifier
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // If dart-define override is set, use it; otherwise use stored preference
    final storedBootstrap = prefs.getString(SettingsKeys.bootstrapServer);
    final bootstrap = _bootstrapServerOverride.isNotEmpty
        ? _bootstrapServerOverride
        : (storedBootstrap ?? SettingsDefaults.bootstrapServer);

    // Load theme
    final themeIndex = prefs.getInt(SettingsKeys.theme);
    final theme = themeIndex != null && themeIndex < AppTheme.values.length
        ? AppTheme.values[themeIndex]
        : SettingsDefaults.theme;

    // Load font family
    final fontIndex = prefs.getInt(SettingsKeys.fontFamily);
    final fontFamily = fontIndex != null && fontIndex < AppFont.values.length
        ? AppFont.values[fontIndex]
        : SettingsDefaults.fontFamily;

    // Load font scale
    final scaleIndex = prefs.getInt(SettingsKeys.fontScale);
    final fontScale = scaleIndex != null && scaleIndex < FontScale.values.length
        ? FontScale.values[scaleIndex]
        : SettingsDefaults.fontScale;

    // Load notification preview
    final notificationIndex = prefs.getInt(SettingsKeys.notificationPreview);
    final notificationPreview = notificationIndex != null && notificationIndex < NotificationPreview.values.length
        ? NotificationPreview.values[notificationIndex]
        : SettingsDefaults.notificationPreview;

    state = AppSettings(
      bootstrapServer: bootstrap,
      relayServer: prefs.getString(SettingsKeys.relayServer) ??
          SettingsDefaults.relayServer,
      directFileTransfer: prefs.getBool(SettingsKeys.directFileTransfer) ??
          SettingsDefaults.directFileTransfer,
      videoCallsEnabled: prefs.getBool(SettingsKeys.videoCallsEnabled) ??
          SettingsDefaults.videoCallsEnabled,
      hasSeenCallPrivacyWarning: prefs.getBool(SettingsKeys.hasSeenCallPrivacyWarning) ??
          SettingsDefaults.hasSeenCallPrivacyWarning,
      onionHopCount: prefs.getInt(SettingsKeys.onionHopCount) ??
          SettingsDefaults.onionHopCount,
      theme: theme,
      fontFamily: fontFamily,
      fontScale: fontScale,
      chatWallpaper: prefs.getString(SettingsKeys.chatWallpaper),
      bubbleRadius: prefs.getDouble(SettingsKeys.bubbleRadius) ??
          SettingsDefaults.bubbleRadius,
      showMessagePreview: prefs.getBool(SettingsKeys.showMessagePreview) ??
          SettingsDefaults.showMessagePreview,
      // Presence settings
      presenceSyncEnabled: prefs.getBool(SettingsKeys.presenceSyncEnabled) ??
          SettingsDefaults.presenceSyncEnabled,
      // Security settings
      appLockEnabled: prefs.getBool(SettingsKeys.appLockEnabled) ??
          SettingsDefaults.appLockEnabled,
      appLockTimeout: prefs.getInt(SettingsKeys.appLockTimeout) ??
          SettingsDefaults.appLockTimeout,
      screenSecurityEnabled: prefs.getBool(SettingsKeys.screenSecurityEnabled) ??
          SettingsDefaults.screenSecurityEnabled,
      hideInAppSwitcher: prefs.getBool(SettingsKeys.hideInAppSwitcher) ??
          SettingsDefaults.hideInAppSwitcher,
      disappearingMessagesDefault: prefs.getInt(SettingsKeys.disappearingMessagesDefault),
      sendReadReceipts: prefs.getBool(SettingsKeys.sendReadReceipts) ??
          SettingsDefaults.sendReadReceipts,
      sendTypingIndicators: prefs.getBool(SettingsKeys.sendTypingIndicators) ??
          SettingsDefaults.sendTypingIndicators,
      notificationPreview: notificationPreview,
      incognitoKeyboard: prefs.getBool(SettingsKeys.incognitoKeyboard) ??
          SettingsDefaults.incognitoKeyboard,
    );
  }

  Future<void> setBootstrapServer(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsKeys.bootstrapServer, value);
    state = state.copyWith(bootstrapServer: value);
  }

  Future<void> setRelayServer(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsKeys.relayServer, value);
    state = state.copyWith(relayServer: value);
  }

  /// Set both servers to the same address (common for cyxchat-server)
  Future<void> setServer(String value) async {
    await setBootstrapServer(value);
    await setRelayServer(value);
  }

  /// Set direct file transfer mode (bypasses onion routing for files)
  Future<void> setDirectFileTransfer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.directFileTransfer, value);
    state = state.copyWith(directFileTransfer: value);
  }

  /// Set video calls enabled
  Future<void> setVideoCallsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.videoCallsEnabled, value);
    state = state.copyWith(videoCallsEnabled: value);
  }

  /// Set has seen call privacy warning
  Future<void> setHasSeenCallPrivacyWarning(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.hasSeenCallPrivacyWarning, value);
    state = state.copyWith(hasSeenCallPrivacyWarning: value);
  }

  /// Set onion routing hop count (1-8)
  Future<void> setOnionHopCount(int value) async {
    // Clamp to valid range
    final clampedValue = value.clamp(1, 8);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsKeys.onionHopCount, clampedValue);
    state = state.copyWith(onionHopCount: clampedValue);
  }

  /// Set app theme
  Future<void> setTheme(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsKeys.theme, theme.index);
    state = state.copyWith(theme: theme);
  }

  /// Set font family
  Future<void> setFontFamily(AppFont fontFamily) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsKeys.fontFamily, fontFamily.index);
    state = state.copyWith(fontFamily: fontFamily);
  }

  /// Set font scale
  Future<void> setFontScale(FontScale fontScale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsKeys.fontScale, fontScale.index);
    state = state.copyWith(fontScale: fontScale);
  }

  /// Set chat wallpaper
  /// Format: null (none), 'solid:#RRGGBB', 'pattern:name', 'file:path'
  Future<void> setChatWallpaper(String? wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    if (wallpaper == null) {
      await prefs.remove(SettingsKeys.chatWallpaper);
      state = state.copyWith(clearWallpaper: true);
    } else {
      await prefs.setString(SettingsKeys.chatWallpaper, wallpaper);
      state = state.copyWith(chatWallpaper: wallpaper);
    }
  }

  /// Set message bubble corner radius
  Future<void> setBubbleRadius(double radius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsKeys.bubbleRadius, radius);
    state = state.copyWith(bubbleRadius: radius);
  }

  /// Set whether to show message preview in chat list
  Future<void> setShowMessagePreview(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.showMessagePreview, show);
    state = state.copyWith(showMessagePreview: show);
  }

  /// Set presence sync enabled
  Future<void> setPresenceSyncEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.presenceSyncEnabled, value);
    state = state.copyWith(presenceSyncEnabled: value);
  }

  // Security settings setters

  /// Set app lock enabled
  Future<void> setAppLockEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.appLockEnabled, value);
    state = state.copyWith(appLockEnabled: value);
  }

  /// Set app lock timeout in seconds
  Future<void> setAppLockTimeout(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsKeys.appLockTimeout, seconds);
    state = state.copyWith(appLockTimeout: seconds);
  }

  /// Set screen security (block screenshots)
  Future<void> setScreenSecurityEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.screenSecurityEnabled, value);
    state = state.copyWith(screenSecurityEnabled: value);
  }

  /// Set hide in app switcher
  Future<void> setHideInAppSwitcher(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.hideInAppSwitcher, value);
    state = state.copyWith(hideInAppSwitcher: value);
  }

  /// Set default disappearing messages duration (null = off)
  Future<void> setDisappearingMessagesDefault(int? seconds) async {
    final prefs = await SharedPreferences.getInstance();
    if (seconds == null) {
      await prefs.remove(SettingsKeys.disappearingMessagesDefault);
      state = state.copyWith(clearDisappearingMessages: true);
    } else {
      await prefs.setInt(SettingsKeys.disappearingMessagesDefault, seconds);
      state = state.copyWith(disappearingMessagesDefault: seconds);
    }
  }

  /// Set send read receipts
  Future<void> setSendReadReceipts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.sendReadReceipts, value);
    state = state.copyWith(sendReadReceipts: value);
  }

  /// Set send typing indicators
  Future<void> setSendTypingIndicators(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.sendTypingIndicators, value);
    state = state.copyWith(sendTypingIndicators: value);
  }

  /// Set notification preview level
  Future<void> setNotificationPreview(NotificationPreview preview) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsKeys.notificationPreview, preview.index);
    state = state.copyWith(notificationPreview: preview);
  }

  /// Set incognito keyboard
  Future<void> setIncognitoKeyboard(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.incognitoKeyboard, value);
    state = state.copyWith(incognitoKeyboard: value);
  }
}

/// Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

/// Alias for consistency with other providers
final settingsNotifierProvider = settingsProvider;

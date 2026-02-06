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
}

/// Check for dart-define override
/// Set via --dart-define=BOOTSTRAP_SERVER=127.0.0.1:7777
const String _bootstrapServerOverride = String.fromEnvironment('BOOTSTRAP_SERVER', defaultValue: '');

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
}

/// Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

/// Alias for consistency with other providers
final settingsNotifierProvider = settingsProvider;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings keys
class SettingsKeys {
  static const String bootstrapServer = 'bootstrap_server';
  static const String relayServer = 'relay_server';
  static const String directFileTransfer = 'direct_file_transfer';
  static const String videoCallsEnabled = 'video_calls_enabled';
  static const String hasSeenCallPrivacyWarning = 'has_seen_call_privacy_warning';
  static const String onionHopCount = 'onion_hop_count';
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
}

/// Settings state
class AppSettings {
  final String bootstrapServer;
  final String relayServer;
  final bool directFileTransfer;
  final bool videoCallsEnabled;
  final bool hasSeenCallPrivacyWarning;
  final int onionHopCount;

  const AppSettings({
    this.bootstrapServer = '',
    this.relayServer = '',
    this.directFileTransfer = false,
    this.videoCallsEnabled = false,
    this.hasSeenCallPrivacyWarning = false,
    this.onionHopCount = 1,
  });

  AppSettings copyWith({
    String? bootstrapServer,
    String? relayServer,
    bool? directFileTransfer,
    bool? videoCallsEnabled,
    bool? hasSeenCallPrivacyWarning,
    int? onionHopCount,
  }) {
    return AppSettings(
      bootstrapServer: bootstrapServer ?? this.bootstrapServer,
      relayServer: relayServer ?? this.relayServer,
      directFileTransfer: directFileTransfer ?? this.directFileTransfer,
      videoCallsEnabled: videoCallsEnabled ?? this.videoCallsEnabled,
      hasSeenCallPrivacyWarning: hasSeenCallPrivacyWarning ?? this.hasSeenCallPrivacyWarning,
      onionHopCount: onionHopCount ?? this.onionHopCount,
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
}

/// Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

/// Alias for consistency with other providers
final settingsNotifierProvider = settingsProvider;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings keys
class SettingsKeys {
  static const String bootstrapServer = 'bootstrap_server';
  static const String relayServer = 'relay_server';
}

/// Default values
class SettingsDefaults {
  // Empty means use STUN only (no P2P discovery)
  static const String bootstrapServer = '';
  static const String relayServer = '';
}

/// Settings state
class AppSettings {
  final String bootstrapServer;
  final String relayServer;

  const AppSettings({
    this.bootstrapServer = '',
    this.relayServer = '',
  });

  AppSettings copyWith({
    String? bootstrapServer,
    String? relayServer,
  }) {
    return AppSettings(
      bootstrapServer: bootstrapServer ?? this.bootstrapServer,
      relayServer: relayServer ?? this.relayServer,
    );
  }

  /// Get combined server string for connection
  /// Format: "ip:port" for bootstrap, same server used for relay
  String get connectionBootstrap => bootstrapServer;
}

/// Settings notifier
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      bootstrapServer: prefs.getString(SettingsKeys.bootstrapServer) ??
          SettingsDefaults.bootstrapServer,
      relayServer: prefs.getString(SettingsKeys.relayServer) ??
          SettingsDefaults.relayServer,
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
}

/// Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

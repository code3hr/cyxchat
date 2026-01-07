import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings keys
class SettingsKeys {
  static const String bootstrapServer = 'bootstrap_server';
  static const String relayServer = 'relay_server';
  static const String directFileTransfer = 'direct_file_transfer';
}

/// Check for dart-define override
/// Set via --dart-define=BOOTSTRAP_SERVER=127.0.0.1:7777
const String _bootstrapServerOverride = String.fromEnvironment('BOOTSTRAP_SERVER', defaultValue: '');

/// Default values
class SettingsDefaults {
  // Default to localhost for local development
  // Users can change to public server (e.g., 147.185.221.16:50841) in settings
  static String get bootstrapServer => _bootstrapServerOverride.isNotEmpty
      ? _bootstrapServerOverride
      : '127.0.0.1:7777';
  static const String relayServer = '';
  static const bool directFileTransfer = false;
}

/// Settings state
class AppSettings {
  final String bootstrapServer;
  final String relayServer;
  final bool directFileTransfer;

  const AppSettings({
    this.bootstrapServer = '',
    this.relayServer = '',
    this.directFileTransfer = false,
  });

  AppSettings copyWith({
    String? bootstrapServer,
    String? relayServer,
    bool? directFileTransfer,
  }) {
    return AppSettings(
      bootstrapServer: bootstrapServer ?? this.bootstrapServer,
      relayServer: relayServer ?? this.relayServer,
      directFileTransfer: directFileTransfer ?? this.directFileTransfer,
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
}

/// Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

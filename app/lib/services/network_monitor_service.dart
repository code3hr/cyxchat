import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'log_service.dart';

/// Service that monitors network connectivity changes and triggers reconnection.
///
/// This service watches for network transitions (offline -> online) and
/// notifies listeners when the device regains connectivity, allowing the
/// app to automatically reconnect to the bootstrap server.
class NetworkMonitorService {
  static final NetworkMonitorService _instance =
      NetworkMonitorService._internal();
  static NetworkMonitorService get instance => _instance;

  NetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _wasOffline = false;
  bool _isMonitoring = false;

  /// Callback triggered when network comes back online
  void Function()? onNetworkRestored;

  /// Current connectivity status
  List<ConnectivityResult> _currentStatus = [];
  List<ConnectivityResult> get currentStatus => _currentStatus;

  /// Check if currently connected to any network
  bool get isConnected =>
      _currentStatus.isNotEmpty &&
      !_currentStatus.contains(ConnectivityResult.none);

  /// Start monitoring network changes
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;

    final log = LogService.instance;

    // Get initial status
    try {
      _currentStatus = await _connectivity.checkConnectivity();
      _wasOffline = !isConnected;
      log.info('Network monitor started: ${_statusString()}',
          source: 'Network');
    } catch (e) {
      log.warning('Failed to get initial connectivity: $e', source: 'Network');
      _currentStatus = [ConnectivityResult.none];
      _wasOffline = true;
    }

    // Subscribe to changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _handleConnectivityChange(results);
    });
  }

  /// Stop monitoring network changes
  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
    _isMonitoring = false;
    LogService.instance.info('Network monitor stopped', source: 'Network');
  }

  /// Handle connectivity change event
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final log = LogService.instance;
    final previousStatus = _currentStatus;
    _currentStatus = results;

    final nowConnected = isConnected;

    log.debug(
        'Connectivity changed: ${_statusString(previousStatus)} -> ${_statusString()}',
        source: 'Network');

    if (_wasOffline && nowConnected) {
      // Just came back online
      log.info('Network restored: ${_statusString()}', source: 'Network');
      _wasOffline = false;

      // Notify listeners to trigger reconnection
      if (onNetworkRestored != null) {
        log.info('Triggering automatic reconnection...', source: 'Network');
        onNetworkRestored!();
      }
    } else if (!_wasOffline && !nowConnected) {
      // Just went offline
      log.warning('Network lost', source: 'Network');
      _wasOffline = true;
    }
  }

  /// Get human-readable status string
  String _statusString([List<ConnectivityResult>? status]) {
    final results = status ?? _currentStatus;
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return 'offline';
    }
    return results.map((r) => r.name).join(', ');
  }

  /// Force check current connectivity (useful for debugging)
  Future<bool> checkConnectivity() async {
    try {
      _currentStatus = await _connectivity.checkConnectivity();
      return isConnected;
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
      return false;
    }
  }
}

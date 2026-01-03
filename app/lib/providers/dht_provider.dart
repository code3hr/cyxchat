import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';

/// DHT node discovered event
class DhtNodeDiscoveredEvent {
  final String nodeId;
  final DateTime timestamp;

  DhtNodeDiscoveredEvent({
    required this.nodeId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// DHT statistics
class DhtStats {
  final int totalNodes;
  final int activeBuckets;
  final bool isReady;

  DhtStats({
    required this.totalNodes,
    required this.activeBuckets,
    required this.isReady,
  });
}

/// DHT provider for decentralized peer discovery
class DhtProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  // Stream controller for node discovery events
  final _nodeDiscoveredController =
      StreamController<DhtNodeDiscoveredEvent>.broadcast();

  // State
  bool _initialized = false;
  DhtStats _stats = DhtStats(totalNodes: 0, activeBuckets: 0, isReady: false);

  // Getters
  bool get initialized => _initialized;
  DhtStats get stats => _stats;

  /// Stream of node discovered events
  Stream<DhtNodeDiscoveredEvent> get nodeDiscoveredStream =>
      _nodeDiscoveredController.stream;

  /// Check if DHT is ready for lookups
  bool get isReady => _bindings.dhtIsReady();

  /// Initialize DHT provider
  /// DHT is automatically created when connection is created
  void initialize() {
    _initialized = _bindings.dhtIsReady();
    _updateStats();
    notifyListeners();
  }

  /// Update DHT statistics
  void _updateStats() {
    _stats = DhtStats(
      totalNodes: 0, // TODO: Get from native when API is exposed
      activeBuckets: 0,
      isReady: _bindings.dhtIsReady(),
    );
  }

  /// Bootstrap DHT with seed nodes
  /// [seedNodeIds] - List of seed node ID hex strings
  Future<bool> bootstrap(List<String> seedNodeIds) async {
    if (seedNodeIds.isEmpty) return false;

    // Convert hex strings to bytes
    final nodeBytes = <int>[];
    for (final nodeIdHex in seedNodeIds) {
      final bytes = _hexToBytes(nodeIdHex);
      if (bytes.length != 32) continue;
      nodeBytes.addAll(bytes);
    }

    if (nodeBytes.isEmpty) return false;

    // Allocate and copy to native memory
    final seedNodesPtr = calloc<Uint8>(nodeBytes.length);
    try {
      for (int i = 0; i < nodeBytes.length; i++) {
        seedNodesPtr[i] = nodeBytes[i];
      }

      final result = _bindings.dhtBootstrap(
        seedNodesPtr,
        nodeBytes.length ~/ 32,
      );

      if (result == CyxChatError.ok) {
        _updateStats();
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(seedNodesPtr);
    }
  }

  /// Add a known node to DHT
  Future<bool> addNode(String nodeIdHex) async {
    final bytes = _hexToBytes(nodeIdHex);
    if (bytes.length != 32) return false;

    final nodeIdPtr = calloc<Uint8>(32);
    try {
      for (int i = 0; i < 32; i++) {
        nodeIdPtr[i] = bytes[i];
      }

      final result = _bindings.dhtAddNode(nodeIdPtr);
      if (result == CyxChatError.ok) {
        _updateStats();
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(nodeIdPtr);
    }
  }

  /// Find a node via DHT (fire-and-forget)
  /// The node will be added to the routing table if found
  Future<bool> findNode(String targetIdHex) async {
    final bytes = _hexToBytes(targetIdHex);
    if (bytes.length != 32) return false;

    final targetIdPtr = calloc<Uint8>(32);
    try {
      for (int i = 0; i < 32; i++) {
        targetIdPtr[i] = bytes[i];
      }

      final result = _bindings.dhtFindNode(targetIdPtr);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(targetIdPtr);
    }
  }

  /// Get closest known nodes to target
  /// Returns list of node ID hex strings
  List<String> getClosestNodes(String targetIdHex, {int maxNodes = 8}) {
    final bytes = _hexToBytes(targetIdHex);
    if (bytes.length != 32) return [];

    final targetIdPtr = calloc<Uint8>(32);
    try {
      for (int i = 0; i < 32; i++) {
        targetIdPtr[i] = bytes[i];
      }

      final nodesList =
          _bindings.dhtGetClosest(targetIdPtr, maxNodes: maxNodes);
      return nodesList.map((bytes) => _bytesToHex(bytes)).toList();
    } finally {
      calloc.free(targetIdPtr);
    }
  }

  /// Refresh stats
  void refresh() {
    _updateStats();
    notifyListeners();
  }

  // Helper methods
  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        result.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    }
    return result;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void dispose() {
    _nodeDiscoveredController.close();
    super.dispose();
  }
}

/// Riverpod provider for DhtProvider
final dhtNotifierProvider = ChangeNotifierProvider<DhtProvider>((ref) {
  return DhtProvider();
});

/// Provider for DHT actions
final dhtActionsProvider = Provider((ref) => DhtActions(ref));

/// DHT actions helper class
class DhtActions {
  final Ref _ref;

  DhtActions(this._ref);

  /// Bootstrap DHT with seed nodes
  Future<bool> bootstrap(List<String> seedNodeIds) {
    return _ref.read(dhtNotifierProvider).bootstrap(seedNodeIds);
  }

  /// Add a node to DHT
  Future<bool> addNode(String nodeIdHex) {
    return _ref.read(dhtNotifierProvider).addNode(nodeIdHex);
  }

  /// Find a node via DHT
  Future<bool> findNode(String targetIdHex) {
    return _ref.read(dhtNotifierProvider).findNode(targetIdHex);
  }

  /// Get closest nodes
  List<String> getClosestNodes(String targetIdHex, {int maxNodes = 8}) {
    return _ref
        .read(dhtNotifierProvider)
        .getClosestNodes(targetIdHex, maxNodes: maxNodes);
  }

  /// Check if DHT is ready
  bool get isReady => _ref.read(dhtNotifierProvider).isReady;
}

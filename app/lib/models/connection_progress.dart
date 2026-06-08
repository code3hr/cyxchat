import 'package:flutter/material.dart';
import 'package:cyxchat/ffi/bindings.dart';

/// Connection phase in the peer connection lifecycle
enum ConnectionPhase {
  idle,           // No connection attempt
  lookingUp,      // "Querying network..."
  peerFound,      // "Found peer..."
  exchangingKeys, // "Exchanging keys (2/10)..."
  keyExchanged,   // "Keys exchanged..."
  connecting,     // "Connecting..."
  connectedP2p,   // "Connected (direct P2P)"
  connectedRelay, // "Connected (via relay)"
  failed,         // "Failed: [reason]"
}

/// Real-time progress tracking for peer connections
class PeerConnectionProgress {
  final String peerId;
  final ConnectionPhase phase;
  final int retryCount;
  final int maxRetries;
  final String? failReason;
  final DateTime timestamp;

  PeerConnectionProgress({
    required this.peerId,
    required this.phase,
    this.retryCount = 0,
    this.maxRetries = 10,
    this.failReason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  PeerConnectionProgress copyWith({
    String? peerId,
    ConnectionPhase? phase,
    int? retryCount,
    int? maxRetries,
    String? failReason,
    DateTime? timestamp,
  }) {
    return PeerConnectionProgress(
      peerId: peerId ?? this.peerId,
      phase: phase ?? this.phase,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      failReason: failReason ?? this.failReason,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Get human-readable status text for UI display
  String get statusText {
    switch (phase) {
      case ConnectionPhase.idle:
        return '';
      case ConnectionPhase.lookingUp:
        return 'Querying network...';
      case ConnectionPhase.peerFound:
        return 'Found peer, exchanging keys...';
      case ConnectionPhase.exchangingKeys:
        if (retryCount > 1) {
          return 'Exchanging keys ($retryCount/$maxRetries)...';
        }
        return 'Exchanging keys...';
      case ConnectionPhase.keyExchanged:
        return 'Keys exchanged, connecting...';
      case ConnectionPhase.connecting:
        return 'Connecting...';
      case ConnectionPhase.connectedP2p:
        return 'Connected (direct P2P)';
      case ConnectionPhase.connectedRelay:
        return 'Connected (via relay)';
      case ConnectionPhase.failed:
        return 'Failed: ${failReason ?? "Unknown error"}';
    }
  }

  /// Get color for status display
  Color get statusColor {
    switch (phase) {
      case ConnectionPhase.connectedP2p:
        return Colors.green;
      case ConnectionPhase.connectedRelay:
        return Colors.blue;
      case ConnectionPhase.failed:
        return Colors.red;
      case ConnectionPhase.idle:
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  /// Check if connection is established (P2P or relay)
  bool get isConnected =>
      phase == ConnectionPhase.connectedP2p ||
      phase == ConnectionPhase.connectedRelay;

  /// Check if connection is in progress
  bool get isConnecting =>
      phase != ConnectionPhase.idle &&
      phase != ConnectionPhase.connectedP2p &&
      phase != ConnectionPhase.connectedRelay &&
      phase != ConnectionPhase.failed;

  /// Convert C library event to ConnectionPhase
  static ConnectionPhase eventToPhase(int event) {
    switch (event) {
      case CyxChatConnEvent.lookupStarted:
        return ConnectionPhase.lookingUp;
      case CyxChatConnEvent.peerFound:
        return ConnectionPhase.peerFound;
      case CyxChatConnEvent.announceSent:
        return ConnectionPhase.exchangingKeys;
      case CyxChatConnEvent.announceRetry:
        return ConnectionPhase.exchangingKeys;
      case CyxChatConnEvent.keyReceived:
        return ConnectionPhase.keyExchanged;
      case CyxChatConnEvent.holePunchStart:
        return ConnectionPhase.connecting;
      case CyxChatConnEvent.connectedP2p:
        return ConnectionPhase.connectedP2p;
      case CyxChatConnEvent.relayFallback:
        return ConnectionPhase.connecting;
      case CyxChatConnEvent.connectedRelay:
        return ConnectionPhase.connectedRelay;
      case CyxChatConnEvent.disconnected:
        return ConnectionPhase.idle;
      case CyxChatConnEvent.failed:
        return ConnectionPhase.failed;
      default:
        return ConnectionPhase.idle;
    }
  }

  @override
  String toString() {
    return 'PeerConnectionProgress(peerId: $peerId, phase: $phase, '
        'retry: $retryCount/$maxRetries, failReason: $failReason)';
  }
}

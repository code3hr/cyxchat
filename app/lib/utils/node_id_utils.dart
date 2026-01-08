import 'dart:ffi';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

/// Utility functions for node ID handling.
///
/// Node IDs can be in two formats:
/// - UUID format: "550e8400-e29b-41d4-a716-446655440000" (36 chars with hyphens)
/// - Hex format: "550e8400e29b41d4a716446655440000..." (64 chars, legacy)
class NodeIdUtils {
  static const _uuid = Uuid();

  /// Generate a new UUID v4 as node ID
  static String generate() {
    return _uuid.v4();
  }

  /// Check if a string is in UUID format (contains hyphens)
  static bool isUuidFormat(String nodeId) {
    return nodeId.contains('-');
  }

  /// Get short display version of node ID (first 8 chars)
  static String shortId(String nodeId) {
    if (isUuidFormat(nodeId)) {
      // UUID format: return first segment (before first hyphen)
      final firstHyphen = nodeId.indexOf('-');
      return firstHyphen > 0 ? nodeId.substring(0, firstHyphen) : nodeId.substring(0, 8);
    } else {
      // Legacy hex format: return first 8 chars
      return nodeId.length >= 8 ? nodeId.substring(0, 8) : nodeId;
    }
  }

  /// Convert node ID (UUID or hex) to bytes for FFI.
  /// Always returns 32 bytes (padded with zeros if needed).
  static Uint8List toBytes(String nodeId) {
    final result = Uint8List(32);

    // Remove hyphens if UUID format
    final hexOnly = nodeId.replaceAll('-', '');

    // Convert hex to bytes
    int byteIndex = 0;
    for (int i = 0; i < hexOnly.length && byteIndex < 32; i += 2) {
      if (i + 2 <= hexOnly.length) {
        result[byteIndex++] = int.parse(hexOnly.substring(i, i + 2), radix: 16);
      }
    }

    // Remaining bytes are already zero (Uint8List is zero-initialized)
    return result;
  }

  /// Convert node ID to List<int> for FFI (same as toBytes but returns List)
  static List<int> toBytesAsList(String nodeId) {
    return toBytes(nodeId).toList();
  }

  /// Convert bytes to UUID format string.
  /// Takes 16 bytes and formats as UUID (with hyphens).
  static String bytesToUuid(Uint8List bytes) {
    if (bytes.length < 16) {
      // Pad if too short
      final padded = Uint8List(16);
      for (int i = 0; i < bytes.length; i++) {
        padded[i] = bytes[i];
      }
      bytes = padded;
    }

    // Format as UUID: 8-4-4-4-12
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Convert bytes (from FFI) to node ID string.
  /// Returns UUID format if first 16 bytes can form a valid UUID.
  static String bytesToNodeId(List<int> bytes, int length) {
    if (length >= 16) {
      // Check if it looks like a UUID (bytes 17-32 would be zeros if so)
      bool isLikelyUuid = true;
      for (int i = 16; i < length && i < 32; i++) {
        if (bytes[i] != 0) {
          isLikelyUuid = false;
          break;
        }
      }

      if (isLikelyUuid) {
        // Format first 16 bytes as UUID
        final uuidBytes = Uint8List.fromList(bytes.sublist(0, 16));
        return bytesToUuid(uuidBytes);
      }
    }

    // Fall back to full hex format
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Convert FFI pointer to node ID string.
  /// Returns UUID format if first 16 bytes form a valid UUID (rest zeros).
  static String ptrToNodeId(Pointer<Uint8> ptr, int len) {
    final bytes = <int>[];
    for (int i = 0; i < len; i++) {
      bytes.add(ptr[i]);
    }
    return bytesToNodeId(bytes, len);
  }

  /// Convert FFI pointer to hex string (for non-node-ID data like message IDs)
  static String ptrToHex(Pointer<Uint8> ptr, int len) {
    final buffer = StringBuffer();
    for (int i = 0; i < len; i++) {
      buffer.write(ptr[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Validate node ID format (either UUID or 64-char hex)
  static bool isValid(String nodeId) {
    if (isUuidFormat(nodeId)) {
      // UUID format validation: 8-4-4-4-12
      final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      );
      return uuidRegex.hasMatch(nodeId);
    } else {
      // Legacy hex format: 64 hex chars
      final hexRegex = RegExp(r'^[0-9a-fA-F]{64}$');
      return hexRegex.hasMatch(nodeId);
    }
  }

  /// Normalize node ID to lowercase
  static String normalize(String nodeId) {
    return nodeId.toLowerCase();
  }
}

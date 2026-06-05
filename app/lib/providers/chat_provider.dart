import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';
import '../services/log_service.dart';
import '../services/identity_service.dart';
import '../utils/node_id_utils.dart';
import 'settings_provider.dart';

/// Received message from native layer
class ReceivedMessage {
  final String fromNodeId;
  final int type;
  final List<int> rawData;
  final DateTime receivedAt;

  ReceivedMessage({
    required this.fromNodeId,
    required this.type,
    required this.rawData,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  /// Parse text message from raw data
  /// Wire format: text_len(2 bytes LE) + text(N) + reply_to(8 optional)
  TextMessageData? parseTextMessage() {
    if (type != CyxChatMsgType.text || rawData.length < 2) return null;

    // 2-byte little-endian length
    final textLen = rawData[0] | (rawData[1] << 8);
    if (rawData.length < 2 + textLen) return null;

    final textBytes = rawData.sublist(2, 2 + textLen);
    final text = utf8.decode(textBytes, allowMalformed: true);

    String? replyToMsgId;
    if (rawData.length >= 2 + textLen + 8) {
      final replyToBytes = rawData.sublist(2 + textLen, 2 + textLen + 8);
      if (!replyToBytes.every((b) => b == 0)) {
        replyToMsgId = _bytesToHex(replyToBytes);
      }
    }

    return TextMessageData(
      text: text,
      replyToMsgId: replyToMsgId,
    );
  }

  /// Parse ACK from raw data
  /// Wire format: msg_id(8) + status(1)
  AckData? parseAck() {
    if (type != CyxChatMsgType.ack || rawData.length < 9) return null;

    final msgIdBytes = rawData.sublist(0, 8);
    final msgId = _bytesToHex(msgIdBytes);
    final status = rawData[8];

    return AckData(
      msgId: msgId,
      status: status,
    );
  }

  /// Parse typing indicator from raw data
  /// Wire format: is_typing(1)
  bool? parseTyping() {
    if (type != CyxChatMsgType.typing || rawData.isEmpty) return null;
    return rawData[0] != 0;
  }

  /// Parse reaction from raw data
  /// Wire format: msg_id(8) + remove(1) + reaction(N)
  ReactionData? parseReaction() {
    if (type != CyxChatMsgType.reaction || rawData.length < 10) return null;

    final msgIdBytes = rawData.sublist(0, 8);
    final msgId = _bytesToHex(msgIdBytes);
    final remove = rawData[8] != 0;
    final reactionBytes = rawData.sublist(9);
    final reaction = utf8.decode(reactionBytes, allowMalformed: true);

    return ReactionData(
      msgId: msgId,
      reaction: reaction,
      remove: remove,
    );
  }

  /// Parse delete request from raw data
  /// Wire format: msg_id(8)
  String? parseDelete() {
    if (type != CyxChatMsgType.delete || rawData.length < 8) return null;
    return _bytesToHex(rawData.sublist(0, 8));
  }

  /// Parse edit from raw data
  /// Wire format: msg_id(8) + text_len(2) + text(N)
  EditData? parseEdit() {
    if (type != CyxChatMsgType.edit || rawData.length < 10) return null;

    final msgIdBytes = rawData.sublist(0, 8);
    final msgId = _bytesToHex(msgIdBytes);
    final textLen = rawData[8] | (rawData[9] << 8);

    if (rawData.length < 10 + textLen) return null;

    final textBytes = rawData.sublist(10, 10 + textLen);
    final text = utf8.decode(textBytes, allowMalformed: true);

    return EditData(
      msgId: msgId,
      newText: text,
    );
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Parsed text message data
class TextMessageData {
  final String text;
  final String? replyToMsgId;

  TextMessageData({
    required this.text,
    this.replyToMsgId,
  });
}

/// Parsed ACK data
class AckData {
  final String msgId;
  final int status;

  AckData({
    required this.msgId,
    required this.status,
  });

  bool get isDelivered => status == 1;
  bool get isRead => status == 2;
}

/// Parsed reaction data
class ReactionData {
  final String msgId;
  final String reaction;
  final bool remove;

  ReactionData({
    required this.msgId,
    required this.reaction,
    required this.remove,
  });
}

/// Parsed edit data
class EditData {
  final String msgId;
  final String newText;

  EditData({
    required this.msgId,
    required this.newText,
  });
}

/// Typing status for a peer
class TypingStatus {
  final String peerId;
  final bool isTyping;
  final DateTime timestamp;

  TypingStatus({
    required this.peerId,
    required this.isTyping,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Result of sending a message
class SendResult {
  final bool success;
  final String? nativeMsgId;
  final String? error;

  SendResult.success(this.nativeMsgId)
      : success = true,
        error = null;
  SendResult.failure(this.error)
      : success = false,
        nativeMsgId = null;
}

/// Tracks a sent message awaiting ACK
class _PendingAck {
  final String nativeMsgId;
  final String localMsgId;
  final String recipientId;
  final String content;
  final DateTime sentAt;

  _PendingAck({
    required this.nativeMsgId,
    required this.localMsgId,
    required this.recipientId,
    required this.content,
    required this.sentAt,
  });

  bool isTimedOut(Duration timeout) {
    return DateTime.now().difference(sentAt) > timeout;
  }
}

/// Data for ACK timeout event
class AckTimeoutData {
  final String localMsgId;
  final String recipientId;
  final String content;

  AckTimeoutData({
    required this.localMsgId,
    required this.recipientId,
    required this.content,
  });
}

/// Chat provider for managing peer-to-peer messaging via FFI
class ChatProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  // State
  bool _initialized = false;
  String? _localNodeId;
  List<int> _localIdBytes = const [];

  // Polling timer — must stay fast since chatPoll() drives the transport layer
  // (hole punching, key exchange, peer discovery), not just chat messages.
  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 50);

  // Stream controllers
  final _messageController = StreamController<ReceivedMessage>.broadcast();
  final _callSignalController = StreamController<ReceivedMessage>.broadcast();
  final _ackController = StreamController<AckData>.broadcast();
  final _typingController = StreamController<TypingStatus>.broadcast();
  final _reactionController = StreamController<ReactionData>.broadcast();
  final _deleteController = StreamController<String>.broadcast();
  final _editController = StreamController<EditData>.broadcast();

  // Typing status tracking (auto-expire after 5s)
  final Map<String, TypingStatus> _typingStatuses = {};
  static const _typingTimeout = Duration(seconds: 5);

  // ACK timeout tracking
  final Map<String, _PendingAck> _pendingAcks = {};
  Timer? _ackTimeoutTimer;
  static const _ackTimeout = Duration(seconds: 30);
  static const _ackTimeoutCheckInterval = Duration(seconds: 5);
  final _ackTimeoutController = StreamController<AckTimeoutData>.broadcast();

  // Getters
  bool get initialized => _initialized;
  String? get localNodeId => _localNodeId;

  /// Stream of incoming text messages
  Stream<ReceivedMessage> get messageStream => _messageController.stream;

  /// Stream of call signaling messages
  Stream<ReceivedMessage> get callSignalStream => _callSignalController.stream;

  /// Stream of ACKs (delivery/read receipts)
  Stream<AckData> get ackStream => _ackController.stream;

  /// Stream of typing indicators
  Stream<TypingStatus> get typingStream => _typingController.stream;

  /// Stream of reactions
  Stream<ReactionData> get reactionStream => _reactionController.stream;

  /// Stream of delete requests
  Stream<String> get deleteStream => _deleteController.stream;

  /// Stream of edit requests
  Stream<EditData> get editStream => _editController.stream;

  /// Stream of ACK timeouts (messages that weren't acknowledged in time)
  Stream<AckTimeoutData> get ackTimeoutStream => _ackTimeoutController.stream;

  /// Get current typing statuses (filtered by timeout)
  Map<String, TypingStatus> get typingStatuses {
    final now = DateTime.now();
    _typingStatuses.removeWhere(
      (_, status) => now.difference(status.timestamp) > _typingTimeout,
    );
    return Map.unmodifiable(_typingStatuses);
  }

  /// Initialize chat provider
  Future<bool> initialize({required List<int> localId}) async {
    if (_initialized) return true;

    // Store local node ID (convert 32-byte array to UUID/hex string)
    _localNodeId = NodeIdUtils.bytesToNodeId(localId, localId.length);
    _localIdBytes = List<int>.from(localId);

    // Convert local ID to native pointer
    final localIdPtr = calloc<Uint8>(32);
    for (int i = 0; i < 32 && i < localId.length; i++) {
      localIdPtr[i] = localId[i];
    }

    try {
      final result = _bindings.chatCreate(localIdPtr);
      if (result != CyxChatError.ok) {
        debugPrint(
            'Failed to create chat context: ${_bindings.errorString(result)}');
        return false;
      }

      // Restore onion keypair from storage if available
      // This enables decryption of queued offline messages
      await _restoreOnionKeypair();

      _initialized = true;
      _startPolling();
      _startAckTimeoutCheck();
      notifyListeners();
      return true;
    } finally {
      calloc.free(localIdPtr);
    }
  }

  /// Restore onion keypair from storage (for offline message decryption)
  Future<void> _restoreOnionKeypair() async {
    try {
      final savedSecret = await IdentityService.instance.loadOnionSecret();
      if (savedSecret != null) {
        final success = _bindings.setOnionKeypair(savedSecret);
        if (success) {
          debugPrint('[ChatProvider] Restored onion keypair from storage');
        } else {
          debugPrint('[ChatProvider] WARNING: Failed to restore onion keypair');
        }
      } else {
        // First run - save the onion secret for future restarts
        await _saveOnionSecret();
      }
    } catch (e) {
      debugPrint('[ChatProvider] Error restoring onion keypair: $e');
    }
  }

  /// Save onion secret key to storage (call after first connection)
  Future<void> _saveOnionSecret() async {
    try {
      final secret = _bindings.getOnionSecret();
      if (secret != null) {
        await IdentityService.instance.saveOnionSecret(secret);
        debugPrint('[ChatProvider] Saved onion secret for future sessions');
      } else {
        debugPrint(
            '[ChatProvider] WARNING: Could not get onion secret to save');
      }
    } catch (e) {
      debugPrint('[ChatProvider] Error saving onion secret: $e');
    }
  }

  /// Shutdown chat provider
  void shutdown() {
    _stopPolling();
    _stopAckTimeoutCheck();

    if (_initialized) {
      _bindings.chatDestroy();
      _initialized = false;
      _localNodeId = null;
      _localIdBytes = const [];
      _typingStatuses.clear();
      _pendingAcks.clear();
      notifyListeners();
    }
  }

  /// Send text message to peer
  /// Returns SendResult with native message ID on success
  /// If localMsgId is provided, the message will be tracked for ACK timeout
  /// If nativeMsgIdHex is provided (for retries), it will be reused instead of generating a new one
  Future<SendResult> sendText({
    required String toPeerId,
    required String text,
    String? replyToMsgId,
    String? localMsgId,
    String? nativeMsgIdHex, // For retries - reuse original msg_id
  }) async {
    final log = LogService.instance;
    if (!_initialized) {
      log.error('Cannot send: chat not initialized', source: 'Chat');
      return SendResult.failure('Chat not initialized');
    }

    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);
    final shortPeerId =
        toPeerId.length > 8 ? toPeerId.substring(0, 8) : toPeerId;

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      // Set msg_id override for retries (must be called immediately before send)
      if (nativeMsgIdHex != null) {
        log.debug('Retry: setting msg_id override to $nativeMsgIdHex',
            source: 'Chat');
        _bindings.chatSetNextMsgId(nativeMsgIdHex);
      }

      final msgIdHex = _bindings.chatSendText(
        peerIdPtr,
        text,
        replyToHex: replyToMsgId,
      );

      if (msgIdHex != null) {
        log.info('Message sent to $shortPeerId... (${text.length} chars)',
            source: 'Chat');

        // Track for ACK timeout if localMsgId provided
        if (localMsgId != null) {
          _pendingAcks[msgIdHex] = _PendingAck(
            nativeMsgId: msgIdHex,
            localMsgId: localMsgId,
            recipientId: toPeerId,
            content: text,
            sentAt: DateTime.now(),
          );
        }

        return SendResult.success(msgIdHex);
      } else {
        log.error('Failed to send message to $shortPeerId...', source: 'Chat');
        return SendResult.failure('Send failed');
      }
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Track a sent message for ACK timeout (used by external retry logic)
  void trackForAck({
    required String nativeMsgId,
    required String localMsgId,
    required String recipientId,
    required String content,
  }) {
    _pendingAcks[nativeMsgId] = _PendingAck(
      nativeMsgId: nativeMsgId,
      localMsgId: localMsgId,
      recipientId: recipientId,
      content: content,
      sentAt: DateTime.now(),
    );
  }

  /// Remove a message from ACK tracking (e.g., when manually retrying)
  void cancelAckTracking(String nativeMsgId) {
    _pendingAcks.remove(nativeMsgId);
  }

  /// Send ACK for received message
  Future<bool> sendAck({
    required String toPeerId,
    required String msgId,
    int status = 1,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendAck(peerIdPtr, msgId, status);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send read receipt for message
  Future<bool> sendReadReceipt({
    required String toPeerId,
    required String msgId,
  }) {
    return sendAck(toPeerId: toPeerId, msgId: msgId, status: 2);
  }

  /// Send typing indicator
  Future<bool> sendTyping({
    required String toPeerId,
    required bool isTyping,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendTyping(peerIdPtr, isTyping);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send reaction to message
  Future<bool> sendReaction({
    required String toPeerId,
    required String msgId,
    required String reaction,
    bool remove = false,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendReaction(
        peerIdPtr,
        msgId,
        reaction,
        remove: remove,
      );
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Request message deletion
  Future<bool> sendDelete({
    required String toPeerId,
    required String msgId,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendDelete(peerIdPtr, msgId);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send edited message
  Future<bool> sendEdit({
    required String toPeerId,
    required String msgId,
    required String newText,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendEdit(peerIdPtr, msgId, newText);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send call signaling payload (uses raw wire format)
  Future<bool> sendCallSignal({
    required String toPeerId,
    required int type,
    required String payload,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);
    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final payloadBytes = utf8.encode(payload);

      if (payloadBytes.length <= _callSignalMaxUnfragmentedBytes) {
        return _sendRawCallPacket(peerIdPtr, type, payloadBytes);
      }

      final callId = _bindings.chatGenerateMsgId();
      if (callId == null || callId.length != 8) {
        debugPrint('ChatProvider: Failed to generate call_id for call signal');
        return false;
      }

      final totalFragments =
          (payloadBytes.length / _callSignalFragmentChunkSize).ceil();
      if (totalFragments > 255) {
        debugPrint(
          'ChatProvider: Call signal too large to fragment: ${payloadBytes.length} bytes',
        );
        return false;
      }

      for (int index = 0; index < totalFragments; index++) {
        final start = index * _callSignalFragmentChunkSize;
        final end = (start + _callSignalFragmentChunkSize < payloadBytes.length)
            ? start + _callSignalFragmentChunkSize
            : payloadBytes.length;
        final chunkLen = end - start;
        final fragment = Uint8List(_callSignalFragmentHeaderSize + chunkLen);
        fragment[0] = _callSignalFragmentMagic;
        fragment[1] = _callSignalFragmentVersion;
        fragment[2] = index;
        fragment[3] = totalFragments;
        fragment.setAll(4, callId);
        fragment.setRange(_callSignalFragmentHeaderSize, fragment.length,
            payloadBytes, start);

        final sent = _sendRawCallPacket(peerIdPtr, type, fragment);
        if (!sent) return false;
      }

      return true;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  // Private methods

  static const int _callSignalMaxUnfragmentedBytes = 80;
  static const int _callSignalFragmentMagic = 0xC7;
  static const int _callSignalFragmentVersion = 1;
  static const int _callSignalFragmentHeaderSize = 12;
  static const int _callSignalFragmentChunkSize = 72;

  bool _sendRawCallPacket(
      Pointer<Uint8> peerIdPtr, int type, List<int> payload) {
    final msgId = _bindings.chatGenerateMsgId();
    if (msgId == null || msgId.length != 8) {
      debugPrint('ChatProvider: Failed to generate msg_id for call signal');
      return false;
    }

    final header = _buildWireHeader(type, msgId, _localIdBytes);
    final data = Uint8List(header.length + payload.length);
    data.setAll(0, header);
    if (payload.isNotEmpty) {
      data.setAll(header.length, payload);
    }

    final result = _bindings.chatSendRaw(peerIdPtr, data);
    return result == CyxChatError.ok;
  }

  Uint8List _buildWireHeader(
    int type,
    List<int> msgId,
    List<int> senderId, {
    int flags = 0,
  }) {
    final header = Uint8List(42);
    header[0] = type & 0xFF;
    header[1] = flags & 0xFF;

    for (int i = 0; i < 8; i++) {
      header[2 + i] = i < msgId.length ? msgId[i] : 0;
    }

    for (int i = 0; i < 32; i++) {
      header[10 + i] = i < senderId.length ? senderId[i] : 0;
    }

    return header;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _poll() {
    if (!_initialized) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    _bindings.chatPoll(now);

    // Process all queued messages
    while (true) {
      final msg = _bindings.chatRecvNext();
      if (msg == null) break;

      _processReceivedMessage(msg);
    }
  }

  void _processReceivedMessage(Map<String, dynamic> msg) {
    final log = LogService.instance;
    final fromBytes = msg['from'] as List<int>;
    final type = msg['type'] as int;
    final data = msg['data'] as List<int>;

    final fromNodeId = NodeIdUtils.bytesToNodeId(fromBytes, fromBytes.length);
    final shortFromId =
        fromNodeId.length > 8 ? fromNodeId.substring(0, 8) : fromNodeId;

    final received = ReceivedMessage(
      fromNodeId: fromNodeId,
      type: type,
      rawData: data,
    );

    switch (type) {
      case CyxChatMsgType.text:
        final textData = received.parseTextMessage();
        final textLen = textData?.text.length ?? 0;
        final preview = textLen > 20
            ? '${textData?.text.substring(0, 20)}...'
            : textData?.text ?? '';
        log.info('Message received from $shortFromId... "$preview"',
            source: 'Chat');
        _messageController.add(received);
        break;

      case CyxChatMsgType.ack:
        final ack = received.parseAck();
        if (ack != null) {
          // Remove from pending ACKs - message was acknowledged
          _pendingAcks.remove(ack.msgId);
          _ackController.add(ack);
        }
        break;

      case CyxChatMsgType.typing:
        final isTyping = received.parseTyping();
        if (isTyping != null) {
          final status = TypingStatus(
            peerId: fromNodeId,
            isTyping: isTyping,
          );
          if (isTyping) {
            _typingStatuses[fromNodeId] = status;
          } else {
            _typingStatuses.remove(fromNodeId);
          }
          _typingController.add(status);
          notifyListeners();
        }
        break;

      case CyxChatMsgType.reaction:
        final reaction = received.parseReaction();
        if (reaction != null) {
          _reactionController.add(reaction);
        }
        break;

      case CyxChatMsgType.delete:
        final msgId = received.parseDelete();
        if (msgId != null) {
          _deleteController.add(msgId);
        }
        break;

      case CyxChatMsgType.edit:
        final edit = received.parseEdit();
        if (edit != null) {
          _editController.add(edit);
        }
        break;

      case CyxChatMsgType.callOffer:
      case CyxChatMsgType.callAnswer:
      case CyxChatMsgType.callIce:
      case CyxChatMsgType.callEnd:
      case CyxChatMsgType.callReject:
      case CyxChatMsgType.callBusy:
        _callSignalController.add(received);
        break;

      default:
        // Unknown message type - could be group message, etc.
        debugPrint(
            'ChatProvider: Unknown message type 0x${type.toRadixString(16)}');
        break;
    }
  }

  /// Set preferred onion routing hop count
  void setHopCount(int hopCount) {
    _bindings.setHopCount(hopCount);
  }

  /// Get current onion routing hop count
  int getHopCount() {
    return _bindings.getHopCount();
  }

  // ============================================================
  // ACK Timeout Handling
  // ============================================================

  /// Start the ACK timeout check timer
  void _startAckTimeoutCheck() {
    _ackTimeoutTimer?.cancel();
    _ackTimeoutTimer = Timer.periodic(_ackTimeoutCheckInterval, (_) {
      _checkAckTimeouts();
    });
  }

  /// Stop the ACK timeout check timer
  void _stopAckTimeoutCheck() {
    _ackTimeoutTimer?.cancel();
    _ackTimeoutTimer = null;
  }

  /// Check for messages that haven't received an ACK in time
  void _checkAckTimeouts() {
    final timedOut = _pendingAcks.entries
        .where((e) => e.value.isTimedOut(_ackTimeout))
        .toList();

    for (final entry in timedOut) {
      final pending = entry.value;
      _pendingAcks.remove(entry.key);

      debugPrint('ChatProvider: ACK timeout for message ${pending.localMsgId}');

      // Emit timeout event so queue provider can handle it
      _ackTimeoutController.add(AckTimeoutData(
        localMsgId: pending.localMsgId,
        recipientId: pending.recipientId,
        content: pending.content,
      ));
    }
  }

  /// Get count of pending ACKs (for debugging)
  int get pendingAckCount => _pendingAcks.length;

  @override
  void dispose() {
    shutdown();
    _messageController.close();
    _callSignalController.close();
    _ackController.close();
    _ackTimeoutController.close();
    _typingController.close();
    _reactionController.close();
    _deleteController.close();
    _editController.close();
    super.dispose();
  }
}

/// Riverpod provider for ChatProvider
final chatNotifierProvider = ChangeNotifierProvider<ChatProvider>((ref) {
  return ChatProvider();
});

/// Provider for chat actions
final chatActionsProvider = Provider((ref) => ChatActions(ref));

/// Chat actions helper class
class ChatActions {
  final Ref _ref;

  ChatActions(this._ref);

  /// Send text message
  Future<SendResult> sendText({
    required String toPeerId,
    required String text,
    String? replyToMsgId,
  }) {
    return _ref.read(chatNotifierProvider).sendText(
          toPeerId: toPeerId,
          text: text,
          replyToMsgId: replyToMsgId,
        );
  }

  /// Send ACK
  Future<bool> sendAck({
    required String toPeerId,
    required String msgId,
    int status = 1,
  }) {
    return _ref.read(chatNotifierProvider).sendAck(
          toPeerId: toPeerId,
          msgId: msgId,
          status: status,
        );
  }

  /// Send read receipt (respects privacy settings)
  Future<bool> sendReadReceipt({
    required String toPeerId,
    required String msgId,
  }) {
    // Check if read receipts are enabled in settings
    final settings = _ref.read(settingsProvider);
    if (!settings.sendReadReceipts) {
      return Future.value(true); // Silently succeed without sending
    }
    return _ref.read(chatNotifierProvider).sendReadReceipt(
          toPeerId: toPeerId,
          msgId: msgId,
        );
  }

  /// Send typing indicator (respects privacy settings)
  Future<bool> sendTyping({
    required String toPeerId,
    required bool isTyping,
  }) {
    // Check if typing indicators are enabled in settings
    final settings = _ref.read(settingsProvider);
    if (!settings.sendTypingIndicators) {
      return Future.value(true); // Silently succeed without sending
    }
    return _ref.read(chatNotifierProvider).sendTyping(
          toPeerId: toPeerId,
          isTyping: isTyping,
        );
  }

  /// Send reaction
  Future<bool> sendReaction({
    required String toPeerId,
    required String msgId,
    required String reaction,
    bool remove = false,
  }) {
    return _ref.read(chatNotifierProvider).sendReaction(
          toPeerId: toPeerId,
          msgId: msgId,
          reaction: reaction,
          remove: remove,
        );
  }

  /// Send delete request
  Future<bool> sendDelete({
    required String toPeerId,
    required String msgId,
  }) {
    return _ref.read(chatNotifierProvider).sendDelete(
          toPeerId: toPeerId,
          msgId: msgId,
        );
  }

  /// Send edit
  Future<bool> sendEdit({
    required String toPeerId,
    required String msgId,
    required String newText,
  }) {
    return _ref.read(chatNotifierProvider).sendEdit(
          toPeerId: toPeerId,
          msgId: msgId,
          newText: newText,
        );
  }

  /// Set preferred onion routing hop count (1-8, or 0 for auto)
  void setHopCount(int hopCount) {
    _ref.read(chatNotifierProvider).setHopCount(hopCount);
  }

  /// Get current onion routing hop count (0 = auto)
  int getHopCount() {
    return _ref.read(chatNotifierProvider).getHopCount();
  }
}

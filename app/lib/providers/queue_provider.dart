import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/queued_message.dart';
import '../services/queue_service.dart';

/// Provider for offline message queue state and retry logic
class QueueProvider extends ChangeNotifier {
  final QueueService _queueService = QueueService.instance;

  // State
  QueueState _state = const QueueState();
  Timer? _retryTimer;
  Timer? _cleanupTimer;
  bool _isConnected = false;
  bool _isInitialized = false;

  // Callback for retry attempts
  Future<bool> Function(String messageId, String recipientId, List<int> data)?
      _retrySendCallback;

  // Configuration
  static const Duration retryCheckInterval = Duration(seconds: 5);
  static const Duration cleanupInterval = Duration(hours: 1);

  QueueState get state => _state;
  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  // ============================================================
  // Initialization
  // ============================================================

  /// Initialize the queue provider
  /// Should be called when app starts
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('QueueProvider: Initializing offline message queue');

    await _loadQueueState();
    _startTimers();
    _isInitialized = true;

    debugPrint(
        'QueueProvider: Initialized with ${_state.totalQueued} queued messages');
  }

  /// Set the callback for retry attempts
  void setRetrySendCallback(
    Future<bool> Function(String messageId, String recipientId, List<int> data)
        callback,
  ) {
    _retrySendCallback = callback;
  }

  /// Shutdown and cleanup
  void shutdown() {
    debugPrint('QueueProvider: Shutting down');
    _retryTimer?.cancel();
    _retryTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _isInitialized = false;
    _isConnected = false;
  }

  // ============================================================
  // Connection Events
  // ============================================================

  /// Called when network connection is established
  /// Triggers immediate queue flush
  Future<void> onConnected() async {
    if (_isConnected) return;

    debugPrint('QueueProvider: Network connected, flushing queue');
    _isConnected = true;

    // Immediate flush on connect
    await flushQueue();
  }

  /// Called when network connection is lost
  void onDisconnected() {
    if (!_isConnected) return;

    debugPrint('QueueProvider: Network disconnected, pausing retries');
    _isConnected = false;
  }

  // ============================================================
  // Queue Management
  // ============================================================

  /// Add a failed message to the queue
  Future<bool> addToQueue({
    required String messageId,
    required String recipientId,
    required String content,
  }) async {
    final data = utf8.encode(content);

    final success = await _queueService.enqueue(
      messageId: messageId,
      recipientId: recipientId,
      data: data,
    );

    if (success) {
      debugPrint(
          'QueueProvider: Message $messageId added to queue for $recipientId');
      await _loadQueueState();
    } else {
      debugPrint(
          'QueueProvider: Failed to add message $messageId to queue (full or duplicate)');
    }

    return success;
  }

  /// Add a failed message to the queue with raw data
  Future<bool> addToQueueRaw({
    required String messageId,
    required String recipientId,
    required List<int> data,
  }) async {
    final success = await _queueService.enqueue(
      messageId: messageId,
      recipientId: recipientId,
      data: data,
    );

    if (success) {
      debugPrint(
          'QueueProvider: Message $messageId added to queue for $recipientId');
      await _loadQueueState();
    } else {
      debugPrint(
          'QueueProvider: Failed to add message $messageId to queue (full or duplicate)');
    }

    return success;
  }

  /// Remove a message from the queue (after successful send)
  Future<void> removeFromQueue(String messageId) async {
    await _queueService.dequeue(messageId);
    debugPrint('QueueProvider: Message $messageId removed from queue');
    await _loadQueueState();
  }

  /// Flush the queue - attempt to send all pending messages
  Future<void> flushQueue() async {
    if (!_isConnected || _state.isProcessing) {
      debugPrint(
          'QueueProvider: Skipping flush (connected=$_isConnected, processing=${_state.isProcessing})');
      return;
    }

    if (_retrySendCallback == null) {
      debugPrint('QueueProvider: No retry callback set, cannot flush');
      return;
    }

    _state = _state.copyWith(isProcessing: true);
    notifyListeners();

    try {
      final readyMessages = await _queueService.getReadyForRetry();
      debugPrint(
          'QueueProvider: Flushing ${readyMessages.length} messages');

      for (final qm in readyMessages) {
        if (!_isConnected) {
          debugPrint('QueueProvider: Disconnected during flush, stopping');
          break;
        }

        // Skip expired messages
        if (qm.isExpired) {
          debugPrint(
              'QueueProvider: Message ${qm.messageId} expired, removing');
          await _queueService.dequeue(qm.messageId);
          continue;
        }

        await _attemptSend(qm);
      }
    } finally {
      _state = _state.copyWith(
        isProcessing: false,
        lastFlushAt: DateTime.now(),
      );
      await _loadQueueState();
    }
  }

  /// Manually retry a specific message
  Future<bool> retryMessage(String messageId) async {
    if (!_isConnected) {
      debugPrint(
          'QueueProvider: Cannot retry $messageId - not connected');
      return false;
    }

    if (_retrySendCallback == null) {
      debugPrint('QueueProvider: No retry callback set');
      return false;
    }

    final qm = await _queueService.getQueueEntry(messageId);
    if (qm == null) {
      debugPrint('QueueProvider: Message $messageId not in queue');
      return false;
    }

    if (qm.isExpired) {
      debugPrint(
          'QueueProvider: Message $messageId expired, removing from queue');
      await _queueService.dequeue(messageId);
      await _loadQueueState();
      return false;
    }

    return await _attemptSend(qm);
  }

  /// Check if a message is queued
  Future<bool> isQueued(String messageId) async {
    return await _queueService.isQueued(messageId);
  }

  /// Get queued message info for UI
  QueuedMessage? getQueuedMessageSync(String messageId) {
    return _state.pendingMessages
        .cast<QueuedMessage?>()
        .firstWhere((m) => m?.messageId == messageId, orElse: () => null);
  }

  // ============================================================
  // Private Methods
  // ============================================================

  /// Attempt to send a single queued message
  Future<bool> _attemptSend(QueuedMessage qm) async {
    debugPrint(
        'QueueProvider: Attempting to send ${qm.messageId} (retry ${qm.retryCount})');

    try {
      final success =
          await _retrySendCallback!(qm.messageId, qm.recipientId, qm.data);

      if (success) {
        debugPrint(
            'QueueProvider: Message ${qm.messageId} sent successfully');
        await _queueService.dequeue(qm.messageId);
        return true;
      } else {
        await _scheduleNextRetry(qm, 'Send failed');
        return false;
      }
    } catch (e) {
      debugPrint('QueueProvider: Error sending ${qm.messageId}: $e');
      await _scheduleNextRetry(qm, e.toString());
      return false;
    }
  }

  /// Schedule next retry with exponential backoff
  Future<void> _scheduleNextRetry(QueuedMessage qm, String error) async {
    final newRetryCount = qm.retryCount + 1;
    final delay = QueuedMessage(
      id: 0,
      messageId: '',
      recipientId: '',
      data: [],
      createdAt: DateTime.now(),
      retryCount: newRetryCount,
    ).nextRetryDelay;

    final nextRetryAt = DateTime.now().add(delay);

    debugPrint(
        'QueueProvider: Scheduling retry ${newRetryCount} for ${qm.messageId} at $nextRetryAt');

    await _queueService.updateRetryState(
      messageId: qm.messageId,
      retryCount: newRetryCount,
      nextRetryAt: nextRetryAt,
      lastError: error,
    );
  }

  /// Load queue state from database
  Future<void> _loadQueueState() async {
    final messages = await _queueService.getQueuedMessages();
    final stats = await _queueService.getStats();

    // Filter out expired messages from the state
    final activeMessages = messages.where((m) => !m.isExpired).toList();

    _state = _state.copyWith(
      pendingMessages: activeMessages,
      totalQueued: stats.totalQueued,
      failedPermanently: stats.failedPermanently,
    );

    notifyListeners();
  }

  /// Start background timers
  void _startTimers() {
    // Retry timer - checks for messages ready to retry
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(retryCheckInterval, (_) async {
      if (_isConnected && !_state.isProcessing) {
        await _processRetryQueue();
      }
    });

    // Cleanup timer - removes expired messages
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) async {
      await _cleanupExpired();
    });
  }

  /// Process messages ready for retry
  Future<void> _processRetryQueue() async {
    if (!_isConnected || _state.isProcessing || _retrySendCallback == null) {
      return;
    }

    final readyMessages = await _queueService.getReadyForRetry();
    if (readyMessages.isEmpty) return;

    // Process one message at a time to avoid overwhelming
    for (final qm in readyMessages.take(3)) {
      if (!_isConnected) break;
      if (qm.isExpired) {
        await _queueService.dequeue(qm.messageId);
        continue;
      }
      await _attemptSend(qm);
    }

    await _loadQueueState();
  }

  /// Remove expired messages
  Future<void> _cleanupExpired() async {
    final removed = await _queueService.removeExpired();
    if (removed > 0) {
      debugPrint('QueueProvider: Cleaned up $removed expired messages');
      await _loadQueueState();
    }
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}

/// Riverpod provider for QueueProvider
final queueNotifierProvider = ChangeNotifierProvider<QueueProvider>((ref) {
  return QueueProvider();
});

/// Provider for queue actions
final queueActionsProvider = Provider((ref) => QueueActions(ref));

/// Queue actions helper
class QueueActions {
  final Ref _ref;
  QueueActions(this._ref);

  QueueProvider get _provider => _ref.read(queueNotifierProvider);

  /// Initialize the queue
  Future<void> initialize() => _provider.initialize();

  /// Add message to queue
  Future<bool> addToQueue({
    required String messageId,
    required String recipientId,
    required String content,
  }) =>
      _provider.addToQueue(
        messageId: messageId,
        recipientId: recipientId,
        content: content,
      );

  /// Add message to queue with raw data
  Future<bool> addToQueueRaw({
    required String messageId,
    required String recipientId,
    required List<int> data,
  }) =>
      _provider.addToQueueRaw(
        messageId: messageId,
        recipientId: recipientId,
        data: data,
      );

  /// Remove message from queue
  Future<void> removeFromQueue(String messageId) =>
      _provider.removeFromQueue(messageId);

  /// Flush entire queue
  Future<void> flushQueue() => _provider.flushQueue();

  /// Retry specific message
  Future<bool> retryMessage(String messageId) =>
      _provider.retryMessage(messageId);

  /// Notify connected
  Future<void> onConnected() => _provider.onConnected();

  /// Notify disconnected
  void onDisconnected() => _provider.onDisconnected();
}

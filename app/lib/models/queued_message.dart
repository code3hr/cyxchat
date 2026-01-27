/// Represents a message in the offline queue awaiting delivery
class QueuedMessage {
  final int id;
  final String messageId;
  final String recipientId;
  final List<int> data;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final DateTime? nextRetryAt;
  final String? lastError;

  /// Time-to-live for queued messages (7 days)
  static const Duration messageTTL = Duration(days: 7);

  /// Exponential backoff delays in seconds
  static const List<int> backoffDelays = [1, 2, 5, 10, 30, 60, 300];

  QueuedMessage({
    required this.id,
    required this.messageId,
    required this.recipientId,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.lastError,
  });

  /// Check if message has expired (exceeded TTL)
  bool get isExpired {
    return DateTime.now().difference(createdAt) > messageTTL;
  }

  /// Check if message is ready for retry
  bool get isReadyForRetry {
    if (nextRetryAt == null) return true;
    return DateTime.now().isAfter(nextRetryAt!);
  }

  /// Calculate next retry delay using exponential backoff
  Duration get nextRetryDelay {
    final index = retryCount.clamp(0, backoffDelays.length - 1);
    return Duration(seconds: backoffDelays[index]);
  }

  /// Time until next retry (for UI display)
  Duration? get timeUntilRetry {
    if (nextRetryAt == null) return null;
    final diff = nextRetryAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Time remaining before expiry (for UI display)
  Duration get timeUntilExpiry {
    final expiryTime = createdAt.add(messageTTL);
    final diff = expiryTime.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Create from database map
  factory QueuedMessage.fromMap(Map<String, dynamic> map) {
    return QueuedMessage(
      id: map['id'] as int,
      messageId: map['message_id'] as String,
      recipientId: map['recipient_id'] as String,
      data: map['data'] is List<int>
          ? map['data'] as List<int>
          : (map['data'] as List).cast<int>(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      retryCount: map['retry_count'] as int? ?? 0,
      lastAttemptAt: map['last_attempt_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_attempt_at'] as int)
          : null,
      nextRetryAt: map['next_retry_at'] != null && map['next_retry_at'] != 0
          ? DateTime.fromMillisecondsSinceEpoch(map['next_retry_at'] as int)
          : null,
      lastError: map['last_error'] as String?,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'message_id': messageId,
      'recipient_id': recipientId,
      'data': data,
      'created_at': createdAt.millisecondsSinceEpoch,
      'retry_count': retryCount,
      'last_attempt_at': lastAttemptAt?.millisecondsSinceEpoch,
      'next_retry_at': nextRetryAt?.millisecondsSinceEpoch ?? 0,
      'last_error': lastError,
    };
  }

  /// Create a copy with updated fields
  QueuedMessage copyWith({
    int? id,
    String? messageId,
    String? recipientId,
    List<int>? data,
    DateTime? createdAt,
    int? retryCount,
    DateTime? lastAttemptAt,
    DateTime? nextRetryAt,
    String? lastError,
  }) {
    return QueuedMessage(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      recipientId: recipientId ?? this.recipientId,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  String toString() {
    return 'QueuedMessage(id: $id, messageId: $messageId, recipientId: $recipientId, '
        'retryCount: $retryCount, isExpired: $isExpired, isReadyForRetry: $isReadyForRetry)';
  }
}

/// State of the offline message queue
class QueueState {
  final List<QueuedMessage> pendingMessages;
  final bool isProcessing;
  final int totalQueued;
  final int failedPermanently;
  final DateTime? lastFlushAt;

  const QueueState({
    this.pendingMessages = const [],
    this.isProcessing = false,
    this.totalQueued = 0,
    this.failedPermanently = 0,
    this.lastFlushAt,
  });

  /// Whether there are messages waiting to be sent
  bool get hasQueuedMessages => totalQueued > 0;

  /// Number of messages ready for immediate retry
  int get readyForRetryCount =>
      pendingMessages.where((m) => m.isReadyForRetry && !m.isExpired).length;

  /// Number of messages expiring within 24 hours
  int get expiringWithin24h => pendingMessages
      .where((m) => m.timeUntilExpiry < const Duration(hours: 24))
      .length;

  /// Create a copy with updated fields
  QueueState copyWith({
    List<QueuedMessage>? pendingMessages,
    bool? isProcessing,
    int? totalQueued,
    int? failedPermanently,
    DateTime? lastFlushAt,
  }) {
    return QueueState(
      pendingMessages: pendingMessages ?? this.pendingMessages,
      isProcessing: isProcessing ?? this.isProcessing,
      totalQueued: totalQueued ?? this.totalQueued,
      failedPermanently: failedPermanently ?? this.failedPermanently,
      lastFlushAt: lastFlushAt ?? this.lastFlushAt,
    );
  }

  @override
  String toString() {
    return 'QueueState(totalQueued: $totalQueued, isProcessing: $isProcessing, '
        'readyForRetry: $readyForRetryCount, expiringWithin24h: $expiringWithin24h)';
  }
}

/// Statistics about the queue
class QueueStats {
  final int totalQueued;
  final int pendingRetry;
  final int failedPermanently;
  final int expiringWithin24h;
  final DateTime? oldestMessage;
  final DateTime? newestMessage;

  const QueueStats({
    this.totalQueued = 0,
    this.pendingRetry = 0,
    this.failedPermanently = 0,
    this.expiringWithin24h = 0,
    this.oldestMessage,
    this.newestMessage,
  });

  @override
  String toString() {
    return 'QueueStats(total: $totalQueued, pending: $pendingRetry, '
        'failed: $failedPermanently, expiring: $expiringWithin24h)';
  }
}

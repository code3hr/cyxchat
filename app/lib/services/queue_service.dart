import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import '../models/queued_message.dart';

/// Service for managing the offline message queue database operations
class QueueService {
  static final QueueService instance = QueueService._();
  QueueService._();

  /// Maximum number of messages in the queue
  static const int maxQueueSize = 100;

  /// ACK timeout before moving message to queue
  static const Duration ackTimeout = Duration(seconds: 30);

  // ============================================================
  // Queue Operations
  // ============================================================

  /// Add a message to the offline queue
  /// Returns true if successfully enqueued, false if queue is full or duplicate
  Future<bool> enqueue({
    required String messageId,
    required String recipientId,
    required List<int> data,
  }) async {
    final db = await DatabaseService.instance.database;

    // Check if message is already queued
    final existing = await db.query(
      'offline_queue',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return false; // Already queued
    }

    // Check queue size limit
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as count FROM offline_queue');
    final currentCount = Sqflite.firstIntValue(countResult) ?? 0;
    if (currentCount >= maxQueueSize) {
      // Remove oldest expired message to make room
      final removed = await _removeOldestExpired(db);
      if (!removed) {
        return false; // Queue is full
      }
    }

    final now = DateTime.now();
    await db.insert('offline_queue', {
      'message_id': messageId,
      'recipient_id': recipientId,
      'data': data,
      'created_at': now.millisecondsSinceEpoch,
      'retry_count': 0,
      'last_attempt_at': null,
      'next_retry_at': now.millisecondsSinceEpoch, // Ready for immediate retry
      'last_error': null,
    });

    return true;
  }

  /// Remove a message from the queue (after successful send)
  Future<void> dequeue(String messageId) async {
    final db = await DatabaseService.instance.database;
    await db.delete(
      'offline_queue',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Get all queued messages (ordered by created_at ASC - oldest first)
  Future<List<QueuedMessage>> getQueuedMessages() async {
    final db = await DatabaseService.instance.database;
    final results = await db.query(
      'offline_queue',
      orderBy: 'created_at ASC',
    );
    return results.map((map) => QueuedMessage.fromMap(map)).toList();
  }

  /// Get queued messages ready for retry (next_retry_at <= now)
  Future<List<QueuedMessage>> getReadyForRetry() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final results = await db.query(
      'offline_queue',
      where: 'next_retry_at <= ?',
      whereArgs: [now],
      orderBy: 'next_retry_at ASC',
    );
    return results.map((map) => QueuedMessage.fromMap(map)).toList();
  }

  /// Get queued messages for a specific recipient
  Future<List<QueuedMessage>> getQueuedForRecipient(String recipientId) async {
    final db = await DatabaseService.instance.database;
    final results = await db.query(
      'offline_queue',
      where: 'recipient_id = ?',
      whereArgs: [recipientId],
      orderBy: 'created_at ASC',
    );
    return results.map((map) => QueuedMessage.fromMap(map)).toList();
  }

  /// Update retry count and schedule next retry
  Future<void> updateRetryState({
    required String messageId,
    required int retryCount,
    required DateTime nextRetryAt,
    String? lastError,
  }) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();

    await db.update(
      'offline_queue',
      {
        'retry_count': retryCount,
        'last_attempt_at': now.millisecondsSinceEpoch,
        'next_retry_at': nextRetryAt.millisecondsSinceEpoch,
        'last_error': lastError,
      },
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Remove expired messages (TTL exceeded)
  /// Returns count of removed messages
  Future<int> removeExpired() async {
    final db = await DatabaseService.instance.database;
    final expiryThreshold = DateTime.now()
        .subtract(QueuedMessage.messageTTL)
        .millisecondsSinceEpoch;

    return await db.delete(
      'offline_queue',
      where: 'created_at < ?',
      whereArgs: [expiryThreshold],
    );
  }

  /// Clear entire queue (for logout/reset)
  Future<void> clearAll() async {
    final db = await DatabaseService.instance.database;
    await db.delete('offline_queue');
  }

  /// Check if a message is queued
  Future<bool> isQueued(String messageId) async {
    final db = await DatabaseService.instance.database;
    final results = await db.query(
      'offline_queue',
      columns: ['id'],
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// Get queue entry for a specific message
  Future<QueuedMessage?> getQueueEntry(String messageId) async {
    final db = await DatabaseService.instance.database;
    final results = await db.query(
      'offline_queue',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return QueuedMessage.fromMap(results.first);
  }

  /// Get queue statistics
  Future<QueueStats> getStats() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();
    final expiryThreshold =
        now.subtract(QueuedMessage.messageTTL).millisecondsSinceEpoch;

    // Total queued (not expired)
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_queue WHERE created_at >= ?',
      [expiryThreshold],
    );
    final totalQueued = Sqflite.firstIntValue(totalResult) ?? 0;

    // Pending retry (ready now)
    final pendingResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_queue WHERE next_retry_at <= ? AND created_at >= ?',
      [now.millisecondsSinceEpoch, expiryThreshold],
    );
    final pendingRetry = Sqflite.firstIntValue(pendingResult) ?? 0;

    // Expired (failed permanently)
    final expiredResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_queue WHERE created_at < ?',
      [expiryThreshold],
    );
    final failedPermanently = Sqflite.firstIntValue(expiredResult) ?? 0;

    // Expiring within 24h
    final expiringThreshold = now
        .subtract(QueuedMessage.messageTTL)
        .add(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final expiringResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_queue WHERE created_at >= ? AND created_at < ?',
      [expiryThreshold, expiringThreshold],
    );
    final expiringWithin24h = Sqflite.firstIntValue(expiringResult) ?? 0;

    // Oldest and newest messages
    DateTime? oldestMessage;
    DateTime? newestMessage;
    final oldestResult = await db.rawQuery(
      'SELECT MIN(created_at) as oldest FROM offline_queue WHERE created_at >= ?',
      [expiryThreshold],
    );
    if (oldestResult.isNotEmpty && oldestResult.first['oldest'] != null) {
      oldestMessage = DateTime.fromMillisecondsSinceEpoch(
        oldestResult.first['oldest'] as int,
      );
    }
    final newestResult = await db.rawQuery(
      'SELECT MAX(created_at) as newest FROM offline_queue WHERE created_at >= ?',
      [expiryThreshold],
    );
    if (newestResult.isNotEmpty && newestResult.first['newest'] != null) {
      newestMessage = DateTime.fromMillisecondsSinceEpoch(
        newestResult.first['newest'] as int,
      );
    }

    return QueueStats(
      totalQueued: totalQueued,
      pendingRetry: pendingRetry,
      failedPermanently: failedPermanently,
      expiringWithin24h: expiringWithin24h,
      oldestMessage: oldestMessage,
      newestMessage: newestMessage,
    );
  }

  /// Get count of queued messages
  Future<int> getQueueCount() async {
    final db = await DatabaseService.instance.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM offline_queue');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ============================================================
  // Private Helpers
  // ============================================================

  /// Remove oldest expired message to make room in queue
  Future<bool> _removeOldestExpired(Database db) async {
    final expiryThreshold = DateTime.now()
        .subtract(QueuedMessage.messageTTL)
        .millisecondsSinceEpoch;

    // Try to remove an expired message
    final deleted = await db.delete(
      'offline_queue',
      where: 'created_at < ?',
      whereArgs: [expiryThreshold],
    );

    return deleted > 0;
  }
}

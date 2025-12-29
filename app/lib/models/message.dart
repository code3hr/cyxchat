import 'package:equatable/equatable.dart';

/// Message delivery status
enum MessageStatus {
  pending,
  sending,
  sent,
  delivered,
  read,
  failed;

  String get icon {
    switch (this) {
      case MessageStatus.pending:
        return '○';
      case MessageStatus.sending:
        return '◐';
      case MessageStatus.sent:
        return '●';
      case MessageStatus.delivered:
        return '●●';
      case MessageStatus.read:
        return '●●';
      case MessageStatus.failed:
        return '⚠';
    }
  }

  static MessageStatus fromInt(int value) {
    if (value >= 0 && value < MessageStatus.values.length) {
      return MessageStatus.values[value];
    }
    return MessageStatus.pending;
  }
}

/// Message type
enum MessageType {
  text,
  image,
  file,
  audio,
  system;

  static MessageType fromInt(int value) {
    if (value >= 0 && value < MessageType.values.length) {
      return MessageType.values[value];
    }
    return MessageType.text;
  }
}

/// Chat message
class Message extends Equatable {
  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final String? replyToId;
  final bool isOutgoing;
  final bool isEdited;
  final bool isDeleted;
  final Map<String, int>? reactions;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.type = MessageType.text,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.pending,
    this.replyToId,
    required this.isOutgoing,
    this.isEdited = false,
    this.isDeleted = false,
    this.reactions,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      type: MessageType.fromInt(map['type'] as int? ?? 0),
      content: map['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      status: MessageStatus.fromInt(map['status'] as int? ?? 0),
      replyToId: map['reply_to_id'] as String?,
      isOutgoing: (map['is_outgoing'] as int?) == 1,
      isEdited: (map['is_edited'] as int?) == 1,
      isDeleted: (map['is_deleted'] as int?) == 1,
      reactions: null, // Parsed from separate table
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'type': type.index,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status.index,
      'reply_to_id': replyToId,
      'is_outgoing': isOutgoing ? 1 : 0,
      'is_edited': isEdited ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Format timestamp for display
  String get timeString {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (msgDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:'
          '${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (today.difference(msgDate).inDays == 1) {
      return 'Yesterday';
    } else {
      return '${timestamp.month}/${timestamp.day}';
    }
  }

  @override
  List<Object?> get props => [
        id,
        conversationId,
        senderId,
        type,
        content,
        timestamp,
        status,
        replyToId,
        isOutgoing,
        isEdited,
        isDeleted,
        reactions,
      ];

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    MessageType? type,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
    String? replyToId,
    bool? isOutgoing,
    bool? isEdited,
    bool? isDeleted,
    Map<String, int>? reactions,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      reactions: reactions ?? this.reactions,
    );
  }
}

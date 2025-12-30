import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'email_attachment.dart';
import 'email_folder.dart';

/// Email status
enum EmailStatus {
  draft,
  queued,
  sent,
  delivered,
  failed;

  static EmailStatus fromInt(int value) {
    if (value >= 0 && value < EmailStatus.values.length) {
      return EmailStatus.values[value];
    }
    return EmailStatus.draft;
  }

  String get displayName {
    switch (this) {
      case EmailStatus.draft:
        return 'Draft';
      case EmailStatus.queued:
        return 'Queued';
      case EmailStatus.sent:
        return 'Sent';
      case EmailStatus.delivered:
        return 'Delivered';
      case EmailStatus.failed:
        return 'Failed';
    }
  }
}

/// Email flags (matches C bitfield)
class EmailFlags {
  static const int seen = 1 << 0;
  static const int flagged = 1 << 1;
  static const int answered = 1 << 2;
  static const int draft = 1 << 3;
  static const int deleted = 1 << 4;
  static const int attachment = 1 << 5;

  static bool isSeen(int flags) => (flags & seen) != 0;
  static bool isFlagged(int flags) => (flags & flagged) != 0;
  static bool isAnswered(int flags) => (flags & answered) != 0;
  static bool isDraft(int flags) => (flags & draft) != 0;
  static bool isDeleted(int flags) => (flags & deleted) != 0;
  static bool hasAttachment(int flags) => (flags & attachment) != 0;
}

/// Email address (node_id + display name)
class EmailAddress extends Equatable {
  final String nodeId;
  final String? displayName;

  const EmailAddress({
    required this.nodeId,
    this.displayName,
  });

  factory EmailAddress.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return EmailAddress(
      nodeId: map['node_id'] as String,
      displayName: map['display_name'] as String?,
    );
  }

  String toJson() {
    return jsonEncode({
      'node_id': nodeId,
      'display_name': displayName,
    });
  }

  /// Display string (name or truncated node ID)
  String get display {
    if (displayName != null && displayName!.isNotEmpty) {
      return displayName!;
    }
    // Show first 8 chars of node ID
    if (nodeId.length > 16) {
      return '${nodeId.substring(0, 8)}...';
    }
    return nodeId;
  }

  @override
  List<Object?> get props => [nodeId, displayName];
}

/// Email message
class EmailMessage extends Equatable {
  final int? id;
  final String mailId;
  final int folderId;
  final EmailFolderType folderType;
  final EmailAddress from;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final String? subject;
  final String? body;
  final DateTime timestamp;
  final String? inReplyTo;
  final String? threadId;
  final int flags;
  final EmailStatus status;
  final bool signatureValid;
  final DateTime createdAt;
  final List<EmailAttachment> attachments;

  const EmailMessage({
    this.id,
    required this.mailId,
    required this.folderId,
    this.folderType = EmailFolderType.inbox,
    required this.from,
    required this.to,
    this.cc = const [],
    this.subject,
    this.body,
    required this.timestamp,
    this.inReplyTo,
    this.threadId,
    this.flags = 0,
    this.status = EmailStatus.draft,
    this.signatureValid = false,
    required this.createdAt,
    this.attachments = const [],
  });

  /// Parse recipients from JSON array string
  static List<EmailAddress> _parseAddresses(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => EmailAddress.fromJson(jsonEncode(e))).toList();
    } catch (_) {
      return [];
    }
  }

  /// Encode addresses to JSON array string
  static String _encodeAddresses(List<EmailAddress> addresses) {
    return jsonEncode(addresses.map((a) => jsonDecode(a.toJson())).toList());
  }

  factory EmailMessage.fromMap(Map<String, dynamic> map) {
    return EmailMessage(
      id: map['id'] as int?,
      mailId: map['mail_id'] as String,
      folderId: map['folder_id'] as int,
      from: EmailAddress(
        nodeId: map['from_node_id'] as String,
        displayName: map['from_name'] as String?,
      ),
      to: _parseAddresses(map['to_addrs'] as String?),
      cc: _parseAddresses(map['cc_addrs'] as String?),
      subject: map['subject'] as String?,
      body: map['body'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      inReplyTo: map['in_reply_to'] as String?,
      threadId: map['thread_id'] as String?,
      flags: map['flags'] as int? ?? 0,
      status: EmailStatus.fromInt(map['status'] as int? ?? 0),
      signatureValid: (map['signature_valid'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      attachments: [], // Loaded separately
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'mail_id': mailId,
      'folder_id': folderId,
      'from_node_id': from.nodeId,
      'from_name': from.displayName,
      'to_addrs': _encodeAddresses(to),
      'cc_addrs': _encodeAddresses(cc),
      'subject': subject,
      'body': body,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'in_reply_to': inReplyTo,
      'thread_id': threadId,
      'flags': flags,
      'status': status.index,
      'signature_valid': signatureValid ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  // Flag helpers
  bool get isRead => EmailFlags.isSeen(flags);
  bool get isFlagged => EmailFlags.isFlagged(flags);
  bool get isAnswered => EmailFlags.isAnswered(flags);
  bool get isDraft => EmailFlags.isDraft(flags);
  bool get isDeleted => EmailFlags.isDeleted(flags);
  bool get hasAttachments => EmailFlags.hasAttachment(flags) || attachments.isNotEmpty;

  /// Short preview of body (first 100 chars)
  String get preview {
    if (body == null || body!.isEmpty) return '';
    final clean = body!.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 100) return clean;
    return '${clean.substring(0, 100)}...';
  }

  /// Format date for display
  String get dateString {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (msgDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:'
          '${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (now.year == timestamp.year) {
      return '${_monthName(timestamp.month)} ${timestamp.day}';
    } else {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
    }
  }

  static String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }

  @override
  List<Object?> get props => [
        id,
        mailId,
        folderId,
        from,
        to,
        cc,
        subject,
        body,
        timestamp,
        inReplyTo,
        threadId,
        flags,
        status,
        signatureValid,
        createdAt,
        attachments,
      ];

  EmailMessage copyWith({
    int? id,
    String? mailId,
    int? folderId,
    EmailFolderType? folderType,
    EmailAddress? from,
    List<EmailAddress>? to,
    List<EmailAddress>? cc,
    String? subject,
    String? body,
    DateTime? timestamp,
    String? inReplyTo,
    String? threadId,
    int? flags,
    EmailStatus? status,
    bool? signatureValid,
    DateTime? createdAt,
    List<EmailAttachment>? attachments,
  }) {
    return EmailMessage(
      id: id ?? this.id,
      mailId: mailId ?? this.mailId,
      folderId: folderId ?? this.folderId,
      folderType: folderType ?? this.folderType,
      from: from ?? this.from,
      to: to ?? this.to,
      cc: cc ?? this.cc,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      inReplyTo: inReplyTo ?? this.inReplyTo,
      threadId: threadId ?? this.threadId,
      flags: flags ?? this.flags,
      status: status ?? this.status,
      signatureValid: signatureValid ?? this.signatureValid,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
    );
  }
}

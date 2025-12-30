import 'package:equatable/equatable.dart';

/// Email folder types
enum EmailFolderType {
  inbox,
  sent,
  drafts,
  archive,
  trash,
  spam,
  custom;

  static EmailFolderType fromInt(int value) {
    if (value >= 0 && value < EmailFolderType.values.length) {
      return EmailFolderType.values[value];
    }
    return EmailFolderType.inbox;
  }

  String get icon {
    switch (this) {
      case EmailFolderType.inbox:
        return 'inbox';
      case EmailFolderType.sent:
        return 'send';
      case EmailFolderType.drafts:
        return 'edit_note';
      case EmailFolderType.archive:
        return 'archive';
      case EmailFolderType.trash:
        return 'delete';
      case EmailFolderType.spam:
        return 'report';
      case EmailFolderType.custom:
        return 'folder';
    }
  }
}

/// Email folder
class EmailFolder extends Equatable {
  final int id;
  final String name;
  final EmailFolderType type;
  final int? parentId;
  final int unreadCount;
  final int totalCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmailFolder({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
    this.unreadCount = 0,
    this.totalCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmailFolder.fromMap(Map<String, dynamic> map) {
    return EmailFolder(
      id: map['id'] as int,
      name: map['name'] as String,
      type: EmailFolderType.fromInt(map['folder_type'] as int),
      parentId: map['parent_id'] as int?,
      unreadCount: map['unread_count'] as int? ?? 0,
      totalCount: map['total_count'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'folder_type': type.index,
      'parent_id': parentId,
      'unread_count': unreadCount,
      'total_count': totalCount,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        parentId,
        unreadCount,
        totalCount,
        createdAt,
        updatedAt,
      ];

  EmailFolder copyWith({
    int? id,
    String? name,
    EmailFolderType? type,
    int? parentId,
    int? unreadCount,
    int? totalCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmailFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      unreadCount: unreadCount ?? this.unreadCount,
      totalCount: totalCount ?? this.totalCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

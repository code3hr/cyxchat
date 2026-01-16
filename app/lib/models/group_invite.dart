import 'package:equatable/equatable.dart';
import '../utils/node_id_utils.dart';

/// Pending group invitation
class GroupInvite extends Equatable {
  final String groupId;
  final String groupName;
  final String inviterId;
  final DateTime receivedAt;

  const GroupInvite({
    required this.groupId,
    required this.groupName,
    required this.inviterId,
    required this.receivedAt,
  });

  factory GroupInvite.fromMap(Map<String, dynamic> map) {
    return GroupInvite(
      groupId: map['group_id'] as String,
      groupName: map['group_name'] as String,
      inviterId: map['inviter_id'] as String,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(map['received_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'group_id': groupId,
      'group_name': groupName,
      'inviter_id': inviterId,
      'received_at': receivedAt.millisecondsSinceEpoch,
    };
  }

  String get shortGroupId => groupId.length >= 8 ? groupId.substring(0, 8) : groupId;

  String get shortInviterId => NodeIdUtils.shortId(inviterId);

  @override
  List<Object?> get props => [groupId, groupName, inviterId, receivedAt];

  GroupInvite copyWith({
    String? groupId,
    String? groupName,
    String? inviterId,
    DateTime? receivedAt,
  }) {
    return GroupInvite(
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      inviterId: inviterId ?? this.inviterId,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }
}

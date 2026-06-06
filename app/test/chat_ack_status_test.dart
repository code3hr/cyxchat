import 'package:cyxchat/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ACK data uses native message status values', () {
    expect(
      AckData(msgId: '0102030405060708', status: NativeMessageStatus.delivered)
          .isDelivered,
      isTrue,
    );
    expect(
      AckData(msgId: '0102030405060708', status: NativeMessageStatus.read)
          .isRead,
      isTrue,
    );
    expect(
      AckData(msgId: '0102030405060708', status: NativeMessageStatus.sent)
          .isDelivered,
      isFalse,
    );
  });
}

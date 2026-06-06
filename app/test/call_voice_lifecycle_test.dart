import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cyxchat/providers/call_provider.dart';
import 'package:cyxchat/providers/voice_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('call lifecycle', () {
    test('desktop permission check does not require permission plugin channel',
        () async {
      final provider = CallProvider();

      expect(await provider.checkPermissions(video: true), isTrue);
      expect(provider.state.status, CallStatus.idle);

      provider.dispose();
    }, skip: !(Platform.isWindows || Platform.isLinux || Platform.isMacOS));

    test('rejecting an incoming call sends reject and returns to idle',
        () async {
      final provider = CallProvider();
      final sentSignals = <({String peerId, int type, String payload})>[];
      provider.onSendSignal = (peerId, type, payload) {
        sentSignals.add((peerId: peerId, type: type, payload: payload));
      };

      await provider.handleOffer(
        peerId: 'peer-1',
        peerName: 'Peer One',
        sdp: 'offer-sdp',
        type: 'offer',
        video: true,
      );

      expect(provider.state.status, CallStatus.incoming);
      expect(provider.state.peerId, 'peer-1');
      expect(provider.state.isVideo, isTrue);

      await provider.rejectCall();

      expect(provider.state.status, CallStatus.idle);
      expect(sentSignals, hasLength(1));
      expect(sentSignals.single.peerId, 'peer-1');
      expect(sentSignals.single.type, CallSignalingType.reject);

      provider.dispose();
    });

    test('second offer while incoming sends busy and keeps first call',
        () async {
      final provider = CallProvider();
      final sentSignals = <({String peerId, int type, String payload})>[];
      provider.onSendSignal = (peerId, type, payload) {
        sentSignals.add((peerId: peerId, type: type, payload: payload));
      };

      await provider.handleOffer(
        peerId: 'peer-1',
        sdp: 'offer-sdp-1',
        type: 'offer',
        video: false,
      );
      await provider.handleOffer(
        peerId: 'peer-2',
        sdp: 'offer-sdp-2',
        type: 'offer',
        video: false,
      );

      expect(provider.state.status, CallStatus.incoming);
      expect(provider.state.peerId, 'peer-1');
      expect(sentSignals, hasLength(1));
      expect(sentSignals.single.peerId, 'peer-2');
      expect(sentSignals.single.type, CallSignalingType.busy);

      await provider.rejectCall();
      provider.dispose();
    });

    test('delayed ended reset does not clear a newer incoming call', () async {
      final provider = CallProvider();

      await provider.handleOffer(
        peerId: 'peer-1',
        sdp: 'offer-sdp-1',
        type: 'offer',
        video: false,
      );

      provider.handleCallEnd(peerId: 'peer-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.state.status, CallStatus.ended);

      await provider.handleOffer(
        peerId: 'peer-2',
        sdp: 'offer-sdp-2',
        type: 'offer',
        video: true,
      );
      expect(provider.state.status, CallStatus.incoming);
      expect(provider.state.peerId, 'peer-2');
      expect(provider.state.isVideo, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(provider.state.status, CallStatus.incoming);
      expect(provider.state.peerId, 'peer-2');

      await provider.rejectCall();
      provider.dispose();
    });
  });

  group('voice message metadata', () {
    test('content JSON escapes filenames safely', () {
      final info = VoiceMessageInfo(
        filename: 'voice "quote" \\ sample.m4a',
        data: Uint8List.fromList(const [1, 2, 3]),
        duration: const Duration(seconds: 12, milliseconds: 500),
        sizeBytes: 3,
      );

      final decoded = jsonDecode(info.toContentJson('file-1'));

      expect(decoded['fileId'], 'file-1');
      expect(decoded['duration'], 12);
      expect(decoded['filename'], 'voice "quote" \\ sample.m4a');
    });

    test('duration formatting remains stable', () {
      expect(
        VoiceRecorderProvider.formatDuration(
          const Duration(minutes: 3, seconds: 7),
        ),
        '03:07',
      );
    });

    test('active recording dispose stops recorder and deletes temp file',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('cyx_voice_test_');
      final recorder = _FakeVoiceRecorderBackend();
      final provider = VoiceRecorderProvider(
        recorder: recorder,
        tempDirectoryProvider: () async => tempDir,
      );

      try {
        expect(await provider.startRecording(), isTrue);
        final recordedPath = recorder.startedPath;
        expect(recordedPath, isNotNull);
        expect(await File(recordedPath!).exists(), isTrue);

        provider.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(recorder.stopCalls, 1);
        expect(recorder.disposeCalls, 1);
        expect(await File(recordedPath).exists(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}

class _FakeVoiceRecorderBackend implements VoiceRecorderBackend {
  String? startedPath;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startedPath = path;
    await File(path).writeAsBytes(const [1, 2, 3]);
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    return startedPath;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

import 'package:cyxchat/widgets/voice_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap starts and second tap completes a recording', (tester) async {
    var started = 0;
    var completed = 0;
    var completedDurationMs = 0;
    final stateChanges = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceRecorder(
            onRecordingStart: () async {
              started++;
              return true;
            },
            onRecordingComplete: (_, durationMs) {
              completed++;
              completedDurationMs = durationMs;
            },
            onRecordingStateChanged: stateChanges.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();

    expect(started, 1);
    expect(stateChanges, [true]);
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    expect(completed, 1);
    expect(completedDurationMs, greaterThanOrEqualTo(500));
    expect(stateChanges, [true, false]);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}

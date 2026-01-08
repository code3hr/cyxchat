import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';

/// Voice recording state
enum VoiceRecordingState {
  idle,
  permissionDenied,
  recording,
  processing,
  sending,
  error,
}

/// Voice playback state
enum VoicePlaybackState {
  stopped,
  loading,
  playing,
  paused,
  error,
}

/// Voice message info for sending
class VoiceMessageInfo {
  final String filename;
  final Uint8List data;
  final Duration duration;
  final int sizeBytes;

  VoiceMessageInfo({
    required this.filename,
    required this.data,
    required this.duration,
    required this.sizeBytes,
  });

  /// Format for message content JSON
  String toContentJson(String fileId) {
    return '{"fileId":"$fileId","duration":${duration.inSeconds},"filename":"$filename"}';
  }
}

/// Voice recorder provider
class VoiceRecorderProvider extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  VoiceRecordingState _state = VoiceRecordingState.idle;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  String? _tempFilePath;
  String? _errorMessage;

  // Max recording duration (5 minutes)
  static const Duration maxDuration = Duration(minutes: 5);

  VoiceRecordingState get state => _state;
  Duration get recordingDuration => _recordingDuration;
  String? get errorMessage => _errorMessage;
  bool get isRecording => _state == VoiceRecordingState.recording;
  bool get isProcessing => _state == VoiceRecordingState.processing;

  /// Check and request microphone permission
  Future<bool> checkPermission() async {
    // On desktop platforms, permission_handler may not work
    // Try to check if we can record directly
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final hasPermission = await _recorder.hasPermission();
        if (!hasPermission) {
          _state = VoiceRecordingState.permissionDenied;
          notifyListeners();
          return false;
        }
        return true;
      } catch (e) {
        debugPrint('VoiceRecorder: Permission check error: $e');
        // On desktop, assume permission is granted if we can't check
        return true;
      }
    }

    // Mobile platforms use permission_handler
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }

    final result = await Permission.microphone.request();
    if (result.isGranted) {
      return true;
    }

    _state = VoiceRecordingState.permissionDenied;
    _errorMessage = 'Microphone permission denied';
    notifyListeners();
    return false;
  }

  /// Start recording
  Future<bool> startRecording() async {
    debugPrint('VoiceRecorder: startRecording called, current state=$_state');
    if (_state == VoiceRecordingState.recording) {
      debugPrint('VoiceRecorder: Already recording');
      return false;
    }

    // Check permission first
    debugPrint('VoiceRecorder: Checking permission...');
    final hasPermission = await checkPermission();
    if (!hasPermission) {
      debugPrint('VoiceRecorder: No permission');
      return false;
    }
    debugPrint('VoiceRecorder: Permission granted');

    try {
      // Get temp directory for recording
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _tempFilePath = '${tempDir.path}/voice_$timestamp.m4a';
      debugPrint('VoiceRecorder: Will record to $_tempFilePath');

      // Configure recording - AAC codec for best compatibility
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000, // 64kbps - good quality, small file
        sampleRate: 44100,
        numChannels: 1, // Mono
      );

      debugPrint('VoiceRecorder: Calling recorder.start()...');
      await _recorder.start(config, path: _tempFilePath!);
      debugPrint('VoiceRecorder: recorder.start() completed');

      _state = VoiceRecordingState.recording;
      _recordingDuration = Duration.zero;
      _errorMessage = null;

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _recordingDuration += const Duration(milliseconds: 100);
        notifyListeners();

        // Auto-stop at max duration
        if (_recordingDuration >= maxDuration) {
          stopRecording();
        }
      });

      notifyListeners();
      debugPrint('VoiceRecorder: Recording started successfully, state=$_state');
      return true;
    } catch (e, stackTrace) {
      _state = VoiceRecordingState.error;
      _errorMessage = 'Failed to start recording: $e';
      notifyListeners();
      debugPrint('VoiceRecorder: Error starting: $e');
      debugPrint('VoiceRecorder: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Stop recording and return voice message info
  Future<VoiceMessageInfo?> stopRecording() async {
    debugPrint('VoiceRecorder: stopRecording called, state=$_state');
    if (_state != VoiceRecordingState.recording) {
      debugPrint('VoiceRecorder: Not recording, returning null');
      return null;
    }

    // Check minimum duration (at least 500ms)
    if (_recordingDuration.inMilliseconds < 500) {
      debugPrint('VoiceRecorder: Recording too short (${_recordingDuration.inMilliseconds}ms), cancelling');
      await cancelRecording();
      return null;
    }

    _durationTimer?.cancel();
    _durationTimer = null;

    try {
      _state = VoiceRecordingState.processing;
      notifyListeners();

      // Stop recording
      debugPrint('VoiceRecorder: Stopping recorder...');
      final path = await _recorder.stop();
      debugPrint('VoiceRecorder: Recorder stopped, path=$path, tempFilePath=$_tempFilePath');
      if (path == null || _tempFilePath == null) {
        _state = VoiceRecordingState.error;
        _errorMessage = 'Recording failed - no file created';
        notifyListeners();
        return null;
      }

      // Read file data
      final file = File(_tempFilePath!);
      if (!await file.exists()) {
        _state = VoiceRecordingState.error;
        _errorMessage = 'Recording file not found';
        notifyListeners();
        return null;
      }

      final data = await file.readAsBytes();
      final duration = _recordingDuration;

      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'voice_$timestamp.m4a';

      // Clean up temp file
      try {
        await file.delete();
      } catch (e) {
        debugPrint('VoiceRecorder: Could not delete temp file: $e');
      }

      _state = VoiceRecordingState.idle;
      _tempFilePath = null;
      _recordingDuration = Duration.zero;
      notifyListeners();

      debugPrint('VoiceRecorder: Finished recording - ${data.length} bytes, ${duration.inSeconds}s');

      return VoiceMessageInfo(
        filename: filename,
        data: Uint8List.fromList(data),
        duration: duration,
        sizeBytes: data.length,
      );
    } catch (e) {
      _state = VoiceRecordingState.error;
      _errorMessage = 'Failed to process recording: $e';
      notifyListeners();
      debugPrint('VoiceRecorder: Error stopping: $e');
      return null;
    }
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    if (_state != VoiceRecordingState.recording) {
      return;
    }

    _durationTimer?.cancel();
    _durationTimer = null;

    try {
      await _recorder.stop();

      // Delete temp file if exists
      if (_tempFilePath != null) {
        final file = File(_tempFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('VoiceRecorder: Error cancelling: $e');
    }

    _state = VoiceRecordingState.idle;
    _tempFilePath = null;
    _recordingDuration = Duration.zero;
    _errorMessage = null;
    notifyListeners();
    debugPrint('VoiceRecorder: Recording cancelled');
  }

  /// Format duration for display
  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

/// Voice player for playing voice messages
class VoicePlayerProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  VoicePlaybackState _state = VoicePlaybackState.stopped;
  String? _currentFileId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;

  VoicePlaybackState get state => _state;
  String? get currentFileId => _currentFileId;
  Duration get position => _position;
  Duration get duration => _duration;
  double get playbackSpeed => _playbackSpeed;
  bool get isPlaying => _state == VoicePlaybackState.playing;
  double get progress => _duration.inMilliseconds > 0
      ? _position.inMilliseconds / _duration.inMilliseconds
      : 0.0;

  VoicePlayerProvider() {
    _positionSub = _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _stateSub = _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _state = VoicePlaybackState.stopped;
        _position = Duration.zero;
        _currentFileId = null;
        notifyListeners();
      }
    });
  }

  /// Play voice message from bytes
  Future<void> playFromBytes(String fileId, Uint8List data) async {
    try {
      // If already playing this file, toggle pause
      if (_currentFileId == fileId) {
        if (_state == VoicePlaybackState.playing) {
          await pause();
          return;
        } else if (_state == VoicePlaybackState.paused) {
          await resume();
          return;
        }
      }

      // Stop any current playback
      await stop();

      _state = VoicePlaybackState.loading;
      _currentFileId = fileId;
      notifyListeners();

      // Write to temp file for playback
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/playback_$fileId.m4a');
      await tempFile.writeAsBytes(data);

      // Load and play
      final audioDuration = await _player.setFilePath(tempFile.path);
      _duration = audioDuration ?? Duration.zero;
      await _player.setSpeed(_playbackSpeed);
      await _player.play();

      _state = VoicePlaybackState.playing;
      notifyListeners();

      debugPrint('VoicePlayer: Playing $fileId');
    } catch (e) {
      _state = VoicePlaybackState.error;
      notifyListeners();
      debugPrint('VoicePlayer: Error playing: $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (_state == VoicePlaybackState.playing) {
      await _player.pause();
      _state = VoicePlaybackState.paused;
      notifyListeners();
    }
  }

  /// Resume playback
  Future<void> resume() async {
    if (_state == VoicePlaybackState.paused) {
      await _player.play();
      _state = VoicePlaybackState.playing;
      notifyListeners();
    }
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
    _state = VoicePlaybackState.stopped;
    _position = Duration.zero;
    _currentFileId = null;
    notifyListeners();
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set playback speed (1.0, 1.5, 2.0)
  Future<void> setSpeed(double speed) async {
    _playbackSpeed = speed;
    await _player.setSpeed(speed);
    notifyListeners();
  }

  /// Cycle through playback speeds
  Future<void> cycleSpeed() async {
    if (_playbackSpeed == 1.0) {
      await setSpeed(1.5);
    } else if (_playbackSpeed == 1.5) {
      await setSpeed(2.0);
    } else {
      await setSpeed(1.0);
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

/// Global voice recorder provider
final voiceRecorderProvider = ChangeNotifierProvider<VoiceRecorderProvider>((ref) {
  return VoiceRecorderProvider();
});

/// Global voice player provider
final voicePlayerProvider = ChangeNotifierProvider<VoicePlayerProvider>((ref) {
  return VoicePlayerProvider();
});

/// Voice actions helper
final voiceActionsProvider = Provider((ref) => VoiceActions(ref));

class VoiceActions {
  final Ref _ref;

  VoiceActions(this._ref);

  VoiceRecorderProvider get recorder => _ref.read(voiceRecorderProvider);
  VoicePlayerProvider get player => _ref.read(voicePlayerProvider);

  /// Start recording
  Future<bool> startRecording() => recorder.startRecording();

  /// Stop recording and get voice message
  Future<VoiceMessageInfo?> stopRecording() => recorder.stopRecording();

  /// Cancel recording
  Future<void> cancelRecording() => recorder.cancelRecording();

  /// Play voice message
  Future<void> play(String fileId, Uint8List data) => player.playFromBytes(fileId, data);

  /// Pause/resume current playback
  Future<void> togglePlayback() async {
    if (player.isPlaying) {
      await player.pause();
    } else if (player.state == VoicePlaybackState.paused) {
      await player.resume();
    }
  }

  /// Stop playback
  Future<void> stopPlayback() => player.stop();

  /// Cycle playback speed
  Future<void> cycleSpeed() => player.cycleSpeed();
}

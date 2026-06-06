import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// Call status states
enum CallStatus {
  idle,
  outgoing, // Calling, waiting for answer
  incoming, // Receiving call
  connecting, // Setting up WebRTC
  connected, // Call active
  reconnecting, // Reconnecting after disconnect
  ended, // Call ended normally
  failed, // Call failed
}

/// Call end reason
enum CallEndReason {
  normal, // Normal hangup
  rejected, // Callee rejected
  busy, // Callee busy
  noAnswer, // No answer (timeout)
  networkError, // Network issue
  error, // Other error
}

/// Call state
class CallState {
  final CallStatus status;
  final String? peerId;
  final String? peerName;
  final bool isVideo;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final Duration duration;
  final CallEndReason? endReason;
  final String? errorMessage;

  const CallState({
    this.status = CallStatus.idle,
    this.peerId,
    this.peerName,
    this.isVideo = false,
    this.isMuted = false,
    this.isCameraOff = false,
    this.isSpeakerOn = true,
    this.duration = Duration.zero,
    this.endReason,
    this.errorMessage,
  });

  CallState copyWith({
    CallStatus? status,
    String? peerId,
    String? peerName,
    bool? isVideo,
    bool? isMuted,
    bool? isCameraOff,
    bool? isSpeakerOn,
    Duration? duration,
    CallEndReason? endReason,
    String? errorMessage,
  }) {
    return CallState(
      status: status ?? this.status,
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      isVideo: isVideo ?? this.isVideo,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      duration: duration ?? this.duration,
      endReason: endReason ?? this.endReason,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool get isActive =>
      status == CallStatus.connected ||
      status == CallStatus.connecting ||
      status == CallStatus.outgoing ||
      status == CallStatus.incoming;
}

/// Signaling message types (matches C library)
class CallSignalingType {
  static const int offer = 0x50;
  static const int answer = 0x51;
  static const int ice = 0x52;
  static const int end = 0x53;
  static const int reject = 0x54;
  static const int busy = 0x55;
}

/// Call provider managing WebRTC calls
class CallProvider extends ChangeNotifier {
  CallState _state = const CallState();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  Timer? _durationTimer;
  Timer? _callTimeoutTimer;
  DateTime? _callStartTime;
  final List<RTCIceCandidate> _pendingRemoteIceCandidates = [];
  bool _remoteDescriptionSet = false;
  int _callGeneration = 0;

  // Callbacks for signaling (set by network layer)
  void Function(String peerId, int type, String payload)? onSendSignal;
  void Function()? onIncomingCall;
  void Function()? onCallConnected;
  void Function()? onCallEnded;

  // WebRTC configuration
  static const Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  static const Map<String, dynamic> _mediaConstraints = {
    'audio': true,
    'video': {
      'facingMode': 'user',
      'width': {'ideal': 1280},
      'height': {'ideal': 720},
    },
  };

  static const Map<String, dynamic> _audioOnlyConstraints = {
    'audio': true,
    'video': false,
  };

  static const Duration _outgoingCallTimeout = Duration(seconds: 45);
  static const Duration _incomingCallTimeout = Duration(seconds: 60);
  static const int _maxPendingRemoteIceCandidates = 32;

  CallState get state => _state;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get hasRemoteStream => _remoteStream != null;

  /// Check camera and microphone permissions
  Future<bool> checkPermissions({required bool video}) async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _state = _state.copyWith(
        status: CallStatus.failed,
        errorMessage: 'Microphone permission denied',
      );
      notifyListeners();
      return false;
    }

    if (video) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        _state = _state.copyWith(
          status: CallStatus.failed,
          errorMessage: 'Camera permission denied',
        );
        notifyListeners();
        return false;
      }
    }

    return true;
  }

  /// Start an outgoing call
  Future<bool> startCall({
    required String peerId,
    String? peerName,
    required bool video,
  }) async {
    if (_state.isActive) {
      debugPrint('CallProvider: Already in a call');
      return false;
    }

    debugPrint(
        'CallProvider: Starting ${video ? "video" : "audio"} call to $peerId');
    _resetPendingSignaling();

    // Check permissions
    if (!await checkPermissions(video: video)) {
      return false;
    }

    _callGeneration++;
    _state = CallState(
      status: CallStatus.outgoing,
      peerId: peerId,
      peerName: peerName,
      isVideo: video,
    );
    notifyListeners();

    try {
      // Get local media stream
      await _createLocalStream(video);

      // Create peer connection
      await _createPeerConnection();

      // Create and send offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer via signaling
      _sendSignal(
          peerId,
          CallSignalingType.offer,
          jsonEncode({
            'sdp': offer.sdp,
            'type': offer.type,
            'video': video,
          }));
      _startCallTimeout(_outgoingCallTimeout, CallEndReason.noAnswer);

      debugPrint('CallProvider: Sent offer to $peerId');
      return true;
    } catch (e) {
      debugPrint('CallProvider: Failed to start call: $e');
      await _cleanup();
      _state = CallState(
        status: CallStatus.failed,
        errorMessage: 'Failed to start call: $e',
      );
      notifyListeners();
      return false;
    }
  }

  /// Handle incoming call offer
  Future<void> handleOffer({
    required String peerId,
    String? peerName,
    required String sdp,
    required String type,
    required bool video,
  }) async {
    if (_state.isActive) {
      // Already in a call, send busy signal
      _sendSignal(peerId, CallSignalingType.busy, '');
      return;
    }

    debugPrint(
        'CallProvider: Received ${video ? "video" : "audio"} call offer from $peerId');
    _resetPendingSignaling();

    _callGeneration++;
    _state = CallState(
      status: CallStatus.incoming,
      peerId: peerId,
      peerName: peerName,
      isVideo: video,
    );
    notifyListeners();

    // Store offer for later use when call is accepted
    _pendingOffer = RTCSessionDescription(sdp, type);
    _pendingVideo = video;
    _startCallTimeout(_incomingCallTimeout, CallEndReason.noAnswer);

    // Notify UI of incoming call
    onIncomingCall?.call();
  }

  RTCSessionDescription? _pendingOffer;
  bool _pendingVideo = false;

  /// Accept incoming call
  Future<bool> acceptCall() async {
    if (_state.status != CallStatus.incoming || _pendingOffer == null) {
      debugPrint('CallProvider: No incoming call to accept');
      return false;
    }

    final peerId = _state.peerId!;
    final video = _pendingVideo;

    debugPrint(
        'CallProvider: Accepting ${video ? "video" : "audio"} call from $peerId');

    // Check permissions
    if (!await checkPermissions(video: video)) {
      _cancelCallTimeout();
      _sendSignal(peerId, CallSignalingType.reject, '');
      _resetPendingSignaling();
      onCallEnded?.call();
      return false;
    }

    _cancelCallTimeout();
    _state = _state.copyWith(status: CallStatus.connecting);
    notifyListeners();

    try {
      // Get local media stream
      await _createLocalStream(video);

      // Create peer connection
      await _createPeerConnection();

      // Set remote description (the offer)
      await _peerConnection!.setRemoteDescription(_pendingOffer!);
      _remoteDescriptionSet = true;
      _pendingOffer = null;
      await _flushPendingRemoteIceCandidates();

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _sendSignal(
          peerId,
          CallSignalingType.answer,
          jsonEncode({
            'sdp': answer.sdp,
            'type': answer.type,
          }));

      debugPrint('CallProvider: Sent answer to $peerId');
      return true;
    } catch (e) {
      debugPrint('CallProvider: Failed to accept call: $e');
      await _cleanup();
      _state = CallState(
        status: CallStatus.failed,
        errorMessage: 'Failed to accept call: $e',
      );
      notifyListeners();
      return false;
    }
  }

  /// Reject incoming call
  Future<void> rejectCall() async {
    if (_state.status != CallStatus.incoming) {
      return;
    }

    final peerId = _state.peerId!;
    debugPrint('CallProvider: Rejecting call from $peerId');
    _cancelCallTimeout();

    _sendSignal(peerId, CallSignalingType.reject, '');

    _resetPendingSignaling();
    _state = const CallState(status: CallStatus.idle);
    notifyListeners();
    onCallEnded?.call();
  }

  /// Handle call answer
  Future<void> handleAnswer({
    required String peerId,
    required String sdp,
    required String type,
  }) async {
    if (!_isCurrentCallSignal(peerId, const [CallStatus.outgoing])) {
      return;
    }

    debugPrint('CallProvider: Received answer from $peerId');

    try {
      _cancelCallTimeout();
      _state = _state.copyWith(status: CallStatus.connecting);
      notifyListeners();

      if (_peerConnection == null) {
        debugPrint('CallProvider: Missing peer connection for answer');
        await endCall(reason: CallEndReason.error);
        return;
      }

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );
      _remoteDescriptionSet = true;
      await _flushPendingRemoteIceCandidates();
    } catch (e) {
      debugPrint('CallProvider: Failed to set remote description: $e');
      await endCall(reason: CallEndReason.error);
    }
  }

  /// Handle ICE candidate
  Future<void> handleIceCandidate({
    required String peerId,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    if (!_isCurrentCallSignal(peerId, const [
      CallStatus.incoming,
      CallStatus.outgoing,
      CallStatus.connecting,
      CallStatus.connected,
      CallStatus.reconnecting,
    ])) {
      return;
    }

    final iceCandidate = RTCIceCandidate(
      candidate,
      sdpMid,
      sdpMLineIndex,
    );

    if (_peerConnection == null || !_remoteDescriptionSet) {
      _bufferRemoteIceCandidate(iceCandidate);
      return;
    }

    try {
      await _addRemoteIceCandidate(iceCandidate);
    } catch (e) {
      debugPrint('CallProvider: Failed to add ICE candidate: $e');
    }
  }

  /// Handle call end from remote
  void handleCallEnd(
      {required String peerId, CallEndReason reason = CallEndReason.normal}) {
    if (!_isCurrentCallSignal(peerId, const [
      CallStatus.incoming,
      CallStatus.outgoing,
      CallStatus.connecting,
      CallStatus.connected,
      CallStatus.reconnecting,
    ])) {
      return;
    }

    debugPrint('CallProvider: Call ended by $peerId: $reason');
    _endCallInternal(reason);
  }

  /// Handle call rejection
  void handleReject({required String peerId}) {
    if (!_isCurrentCallSignal(peerId, const [CallStatus.outgoing])) {
      return;
    }

    debugPrint('CallProvider: Call rejected by $peerId');
    _endCallInternal(CallEndReason.rejected);
  }

  /// Handle busy signal
  void handleBusy({required String peerId}) {
    if (!_isCurrentCallSignal(peerId, const [CallStatus.outgoing])) {
      return;
    }

    debugPrint('CallProvider: $peerId is busy');
    _endCallInternal(CallEndReason.busy);
  }

  /// End current call
  Future<void> endCall({CallEndReason reason = CallEndReason.normal}) async {
    if (!_state.isActive && _state.status != CallStatus.incoming) {
      return;
    }

    final peerId = _state.peerId;
    if (peerId != null) {
      _sendSignal(peerId, CallSignalingType.end, '');
    }

    _endCallInternal(reason);
  }

  void _endCallInternal(CallEndReason reason) async {
    final endingGeneration = _callGeneration;
    await _cleanup();

    _state = CallState(
      status: CallStatus.ended,
      endReason: reason,
      duration: _callStartTime != null
          ? DateTime.now().difference(_callStartTime!)
          : Duration.zero,
    );
    notifyListeners();

    onCallEnded?.call();

    // Reset to idle after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (_state.status == CallStatus.ended &&
          _callGeneration == endingGeneration) {
        _state = const CallState(status: CallStatus.idle);
        notifyListeners();
      }
    });
  }

  /// Toggle mute
  void toggleMute() {
    if (_localStream == null) return;

    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      final muted = !_state.isMuted;
      audioTracks.first.enabled = !muted;
      _state = _state.copyWith(isMuted: muted);
      notifyListeners();
    }
  }

  /// Toggle camera
  void toggleCamera() {
    if (_localStream == null || !_state.isVideo) return;

    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      final off = !_state.isCameraOff;
      videoTracks.first.enabled = !off;
      _state = _state.copyWith(isCameraOff: off);
      notifyListeners();
    }
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    if (_localStream == null || !_state.isVideo) return;

    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
    }
  }

  /// Toggle speaker
  void toggleSpeaker() {
    final speakerOn = !_state.isSpeakerOn;
    // Note: Actual speaker toggle depends on platform
    // For mobile, we'd use platform-specific APIs
    _state = _state.copyWith(isSpeakerOn: speakerOn);
    notifyListeners();
  }

  // Private methods

  Future<void> _createLocalStream(bool video) async {
    final constraints = video ? _mediaConstraints : _audioOnlyConstraints;
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    debugPrint(
        'CallProvider: Created local stream with ${_localStream!.getTracks().length} tracks');
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_configuration);

    // Add local tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // Handle remote stream
    _peerConnection!.onTrack = (event) {
      debugPrint('CallProvider: onTrack - ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        notifyListeners();
      }
    };

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (_state.peerId != null && candidate.candidate != null) {
        _sendSignal(
            _state.peerId!,
            CallSignalingType.ice,
            jsonEncode({
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            }));
      }
    };

    // Handle connection state
    _peerConnection!.onConnectionState = (state) {
      debugPrint('CallProvider: Connection state: $state');
      if (!_state.isActive || _peerConnection == null) {
        return;
      }

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _onConnected();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _state = _state.copyWith(status: CallStatus.reconnecting);
          notifyListeners();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          endCall(reason: CallEndReason.networkError);
          break;
        default:
          break;
      }
    };
  }

  void _onConnected() {
    if (!_state.isActive) {
      return;
    }

    debugPrint('CallProvider: Call connected');
    _cancelCallTimeout();
    _callStartTime = DateTime.now();
    _state = _state.copyWith(status: CallStatus.connected);
    notifyListeners();

    // Start duration timer
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_callStartTime != null) {
        _state = _state.copyWith(
          duration: DateTime.now().difference(_callStartTime!),
        );
        notifyListeners();
      }
    });

    onCallConnected?.call();
  }

  void _sendSignal(String peerId, int type, String payload) {
    onSendSignal?.call(peerId, type, payload);
  }

  void _startCallTimeout(Duration timeout, CallEndReason reason) {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(timeout, () {
      if (!_state.isActive || _state.status == CallStatus.connected) return;
      debugPrint('CallProvider: Call timed out: $reason');
      if (_state.status == CallStatus.outgoing && _state.peerId != null) {
        _sendSignal(_state.peerId!, CallSignalingType.end, '');
      }
      _endCallInternal(reason);
    });
  }

  void _cancelCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }

  bool _isCurrentCallSignal(String peerId, List<CallStatus> allowedStatuses) {
    if (_state.peerId == peerId && allowedStatuses.contains(_state.status)) {
      return true;
    }

    debugPrint(
      'CallProvider: Ignoring stale signal from $peerId while '
      '${_state.status} with peer ${_state.peerId}',
    );
    return false;
  }

  void _bufferRemoteIceCandidate(RTCIceCandidate candidate) {
    if (_pendingRemoteIceCandidates.length >= _maxPendingRemoteIceCandidates) {
      _pendingRemoteIceCandidates.removeAt(0);
    }

    _pendingRemoteIceCandidates.add(candidate);
    debugPrint(
      'CallProvider: Buffered remote ICE candidate '
      '(${_pendingRemoteIceCandidates.length} pending)',
    );
  }

  Future<void> _flushPendingRemoteIceCandidates() async {
    if (_peerConnection == null ||
        !_remoteDescriptionSet ||
        _pendingRemoteIceCandidates.isEmpty) {
      return;
    }

    final pending = List<RTCIceCandidate>.from(_pendingRemoteIceCandidates);
    _pendingRemoteIceCandidates.clear();
    for (final candidate in pending) {
      await _addRemoteIceCandidate(candidate);
    }
  }

  Future<void> _addRemoteIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection!.addCandidate(candidate);
  }

  void _resetPendingSignaling() {
    _pendingOffer = null;
    _pendingVideo = false;
    _pendingRemoteIceCandidates.clear();
    _remoteDescriptionSet = false;
  }

  Future<void> _cleanup() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _cancelCallTimeout();
    _callStartTime = null;
    _resetPendingSignaling();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    if (_remoteStream != null) {
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    final peerConnection = _peerConnection;
    _peerConnection = null;
    if (peerConnection != null) {
      await peerConnection.close();
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

/// Global call provider
final callNotifierProvider = ChangeNotifierProvider<CallProvider>((ref) {
  return CallProvider();
});

/// Call actions helper
final callActionsProvider = Provider((ref) => CallActions(ref));

class CallActions {
  final Ref _ref;

  CallActions(this._ref);

  CallProvider get _provider => _ref.read(callNotifierProvider);

  /// Start a call
  Future<bool> startCall({
    required String peerId,
    String? peerName,
    bool video = false,
  }) {
    return _provider.startCall(
        peerId: peerId, peerName: peerName, video: video);
  }

  /// Accept incoming call
  Future<bool> acceptCall() => _provider.acceptCall();

  /// Reject incoming call
  Future<void> rejectCall() => _provider.rejectCall();

  /// End current call
  Future<void> endCall() => _provider.endCall();

  /// Toggle mute
  void toggleMute() => _provider.toggleMute();

  /// Toggle camera
  void toggleCamera() => _provider.toggleCamera();

  /// Switch camera
  Future<void> switchCamera() => _provider.switchCamera();

  /// Toggle speaker
  void toggleSpeaker() => _provider.toggleSpeaker();
}

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../ffi/bindings.dart';
import '../utils/node_id_utils.dart';

/// File transfer info
class FileTransferInfo {
  final String fileId;
  final String filename;
  final String mimeType;
  final int size;
  final int state;
  final int chunksDone;
  final int chunksTotal;
  final String peerId;
  final bool isOutgoing;
  final DateTime startedAt;

  FileTransferInfo({
    required this.fileId,
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.state,
    required this.chunksDone,
    required this.chunksTotal,
    required this.peerId,
    required this.isOutgoing,
    required this.startedAt,
  });

  double get progress => chunksTotal > 0 ? chunksDone / chunksTotal : 0;
  String get stateName => CyxChatFileState.name(state);
  bool get isActive => CyxChatFileState.isActive(state);
  bool get isComplete => CyxChatFileState.isComplete(state);
}

/// Incoming file request
class FileRequest {
  final String fileId;
  final String filename;
  final String mimeType;
  final int size;
  final String fromPeerId;
  final DateTime receivedAt;

  FileRequest({
    required this.fileId,
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.fromPeerId,
    required this.receivedAt,
  });

  String get formattedSize => CyxChatBindings.instance.fileFormatSize(size);
}

/// File transfer result
class FileSendResult {
  final bool success;
  final String? fileId;
  final String? localPath;
  final String? error;

  FileSendResult({
    required this.success,
    this.fileId,
    this.localPath,
    this.error,
  });
}

/// File provider for managing file transfers
class FileProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  bool _initialized = false;
  Timer? _pollTimer;

  // Active transfers
  final Map<String, FileTransferInfo> _transfers = {};

  // Pending incoming requests (by fileId for lookup)
  final Map<String, FileRequest> _pendingRequestsById = {};
  final List<FileRequest> _pendingRequests = [];

  // Completed file data (for received files)
  final Map<String, Uint8List> _receivedFiles = {};
  final Map<String, String> _storedFilePaths = {};

  /// Callback when a file is fully received
  /// Parameters: fromPeerId, filename, fileSize (formatted), fileId
  void Function(
          String fromPeerId, String filename, String fileSize, String fileId)?
      onFileReceived;
  void Function(FileRequest request)? onFileRequest;
  void Function(String fileId)? onTransferComplete;
  void Function(String fileId)? onTransferError;

  // Stream controllers for events
  final _requestController = StreamController<FileRequest>.broadcast();
  final _progressController = StreamController<FileTransferInfo>.broadcast();
  final _completeController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  bool get isInitialized => _initialized;
  Map<String, FileTransferInfo> get transfers => Map.unmodifiable(_transfers);
  List<FileRequest> get pendingRequests => List.unmodifiable(_pendingRequests);

  Stream<FileRequest> get requestStream => _requestController.stream;
  Stream<FileTransferInfo> get progressStream => _progressController.stream;
  Stream<String> get completeStream => _completeController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// Initialize file transfer context
  Future<bool> initialize() async {
    if (_initialized) return true;

    final result = _bindings.fileCtxCreate();
    if (result != 0) {
      debugPrint('FileProvider: Failed to create file context: $result');
      return false;
    }

    // Set up callbacks
    _setupCallbacks();
    _bindings.fileSetupCallbacks();

    _initialized = true;
    _startPolling();
    debugPrint('FileProvider: Initialized');
    notifyListeners();
    return true;
  }

  /// Set direct mode for file transfers
  /// When enabled, files are sent via direct P2P (faster but less anonymous)
  /// When disabled, files go through onion routing (slower but anonymous)
  void setDirectMode(bool enabled) {
    if (!_initialized) return;

    // Get router from connection context and set it on file context
    final router = _bindings.connGetRouter();
    if (router != null) {
      _bindings.fileSetRouter(router);
    }

    final result = _bindings.fileSetDirectMode(enabled ? 1 : 0);
    if (result == 0) {
      debugPrint(
          'FileProvider: Direct mode ${enabled ? "enabled" : "disabled"}');
    } else {
      debugPrint('FileProvider: Failed to set direct mode: $result');
    }
  }

  /// Get current direct mode setting
  bool get isDirectMode {
    if (!_initialized) return false;
    return _bindings.fileGetDirectMode() == 1;
  }

  /// Set up Dart callbacks for file events
  void _setupCallbacks() {
    // Handle incoming file request
    _bindings.onFileRequest = (fromPeerId, fileId, filename, mimeType, size) {
      debugPrint(
          'FileProvider: Incoming file request from $fromPeerId: $filename ($size bytes)');

      // Add to pending requests
      final request = FileRequest(
        fileId: fileId,
        filename: filename,
        mimeType: mimeType,
        size: size,
        fromPeerId: fromPeerId,
        receivedAt: DateTime.now(),
      );
      _pendingRequests.removeWhere((r) => r.fileId == fileId);
      _pendingRequests.add(request);
      _pendingRequestsById[fileId] = request; // Also store by ID for lookup
      _requestController.add(request);

      // Calculate chunk size based on mode (for progress estimation)
      final chunkSize = isDirectMode
          ? CyxChatFileConst.directChunkSize
          : CyxChatFileConst.chunkSize;

      // Create transfer entry for tracking
      _transfers[fileId] = FileTransferInfo(
        fileId: fileId,
        filename: filename,
        mimeType: mimeType,
        size: size,
        state: CyxChatFileState.pending,
        chunksDone: 0,
        chunksTotal: (size / chunkSize).ceil(),
        peerId: fromPeerId,
        isOutgoing: false, // Incoming file
        startedAt: DateTime.now(),
      );

      onFileRequest?.call(request);
      notifyListeners();
    };

    // Handle file transfer complete
    _bindings.onFileComplete = (fileId, data) {
      debugPrint(
          'FileProvider: File transfer complete: $fileId (${data.length} bytes)');

      // Find the request (check both maps)
      FileRequest? request = _pendingRequestsById.remove(fileId);
      final requestIndex =
          _pendingRequests.indexWhere((r) => r.fileId == fileId);
      if (requestIndex >= 0) {
        request ??= _pendingRequests[requestIndex];
        _pendingRequests.removeAt(requestIndex);
      }

      final fileData = Uint8List.fromList(data);
      _receivedFiles[fileId] = fileData;

      // Update transfer state if tracking
      if (_transfers.containsKey(fileId)) {
        final transfer = _transfers[fileId]!;
        _transfers[fileId] = FileTransferInfo(
          fileId: transfer.fileId,
          filename: transfer.filename,
          mimeType: transfer.mimeType,
          size: transfer.size,
          state: CyxChatFileState.completed,
          chunksDone: transfer.chunksTotal,
          chunksTotal: transfer.chunksTotal,
          peerId: transfer.peerId,
          isOutgoing: transfer.isOutgoing,
          startedAt: transfer.startedAt,
        );
      }

      notifyListeners();

      unawaited(_persistCompletedFile(
        fileId: fileId,
        filename: request?.filename ?? _transfers[fileId]?.filename ?? fileId,
        data: fileData,
        request: request,
      ));
    };

    // Handle progress updates
    _bindings.onFileProgress = (fileId, chunksDone, chunksTotal) {
      debugPrint('FileProvider: Progress $fileId: $chunksDone/$chunksTotal');

      if (_transfers.containsKey(fileId)) {
        final transfer = _transfers[fileId]!;
        _transfers[fileId] = FileTransferInfo(
          fileId: transfer.fileId,
          filename: transfer.filename,
          mimeType: transfer.mimeType,
          size: transfer.size,
          state: transfer.state == CyxChatFileState.pending
              ? (transfer.isOutgoing
                  ? CyxChatFileState.sending
                  : CyxChatFileState.receiving)
              : transfer.state,
          chunksDone: chunksDone,
          chunksTotal: chunksTotal,
          peerId: transfer.peerId,
          isOutgoing: transfer.isOutgoing,
          startedAt: transfer.startedAt,
        );
        _progressController.add(_transfers[fileId]!);
        notifyListeners();
      }
    };

    // Handle errors
    _bindings.onFileError = (fileId, error) {
      debugPrint('FileProvider: Error on $fileId: $error');

      if (_transfers.containsKey(fileId)) {
        final transfer = _transfers[fileId]!;
        _transfers[fileId] = FileTransferInfo(
          fileId: transfer.fileId,
          filename: transfer.filename,
          mimeType: transfer.mimeType,
          size: transfer.size,
          state: CyxChatFileState.failed,
          chunksDone: transfer.chunksDone,
          chunksTotal: transfer.chunksTotal,
          peerId: transfer.peerId,
          isOutgoing: transfer.isOutgoing,
          startedAt: transfer.startedAt,
        );
      }

      _errorController.add(fileId);
      onTransferError?.call(fileId);
      notifyListeners();
    };
  }

  /// Shutdown file transfer context
  void shutdown() {
    _stopPolling();
    // Clear callbacks before destroying context
    _bindings.onFileRequest = null;
    _bindings.onFileComplete = null;
    _bindings.onFileProgress = null;
    _bindings.onFileError = null;
    onFileRequest = null;
    onTransferComplete = null;
    onTransferError = null;
    _bindings.fileCtxDestroy();
    _initialized = false;
    _transfers.clear();
    _pendingRequests.clear();
    _pendingRequestsById.clear();
    _receivedFiles.clear();
    _storedFilePaths.clear();
    debugPrint('FileProvider: Shutdown');
    notifyListeners();
  }

  Future<void> _persistCompletedFile({
    required String fileId,
    required String filename,
    required Uint8List data,
    required FileRequest? request,
  }) async {
    try {
      await _storeFileData(fileId, filename, data);
    } catch (e) {
      debugPrint('FileProvider: Could not persist completed file $fileId: $e');
    }

    _completeController.add(fileId);
    onTransferComplete?.call(fileId);

    if (request != null) {
      debugPrint(
          'FileProvider: Received file "${request.filename}" from ${request.fromPeerId}');
      final formattedSize = _bindings.fileFormatSize(data.length);
      onFileReceived?.call(
          request.fromPeerId, request.filename, formattedSize, fileId);
    }
    notifyListeners();
  }

  /// Start polling for file events
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _poll();
    });
  }

  /// Stop polling
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Poll for file transfer events
  void _poll() {
    if (!_initialized) return;
    final now = _bindings.timestampMs();
    _bindings.filePoll(now);
    // Note: In a full implementation, we would check for callbacks here
    // For now, the C library handles events via callbacks
  }

  /// Send file to peer
  Future<FileSendResult> sendFile({
    required String toPeerId,
    required String filename,
    required Uint8List data,
    String? mimeType,
  }) async {
    if (!_initialized) {
      return FileSendResult(
          success: false, error: 'File provider not initialized');
    }

    // Check file size limit based on mode
    final maxSize = isDirectMode
        ? CyxChatFileConst.directMaxFileSize
        : CyxChatFileConst.maxFileSize;

    if (data.length > maxSize) {
      if (isDirectMode) {
        return FileSendResult(
          success: false,
          error:
              'File too large. Maximum size is ${maxSize ~/ (1024 * 1024)} GB',
        );
      } else {
        return FileSendResult(
          success: false,
          error:
              'File too large. Maximum size is ${maxSize ~/ 1024} KB. Enable "Fast File Transfer" in settings for larger files.',
        );
      }
    }

    // Convert peer ID to native pointer
    final peerIdBytes = NodeIdUtils.toBytesAsList(toPeerId);
    if (peerIdBytes.length != 32) {
      return FileSendResult(success: false, error: 'Invalid peer ID');
    }

    final peerIdPtr = calloc<Uint8>(32);
    try {
      for (int i = 0; i < 32; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      // Detect MIME type if not provided
      final mime = mimeType ?? _bindings.fileDetectMime(filename);

      // Send file
      final fileId = _bindings.fileSend(
        to: peerIdPtr,
        filename: filename,
        mimeType: mime,
        data: data.toList(),
      );

      if (fileId != null) {
        debugPrint(
            'FileProvider: Sending file $filename (${data.length} bytes) to $toPeerId, direct=$isDirectMode');

        // Calculate chunk count based on mode
        final chunkSize = isDirectMode
            ? CyxChatFileConst.directChunkSize
            : CyxChatFileConst.chunkSize;

        // Track the transfer
        _transfers[fileId] = FileTransferInfo(
          fileId: fileId,
          filename: filename,
          mimeType: mime,
          size: data.length,
          state: CyxChatFileState.sending,
          chunksDone: 0,
          chunksTotal: (data.length / chunkSize).ceil(),
          peerId: toPeerId,
          isOutgoing: true,
          startedAt: DateTime.now(),
        );

        // Persist sent file data so sender can play/export after restart.
        final fileData = Uint8List.fromList(data);
        _receivedFiles[fileId] = fileData;
        String? localPath;
        try {
          localPath = await _storeFileData(fileId, filename, fileData);
        } catch (e) {
          debugPrint('FileProvider: Could not persist sent file $fileId: $e');
        }

        notifyListeners();

        return FileSendResult(
          success: true,
          fileId: fileId,
          localPath: localPath,
        );
      } else {
        return FileSendResult(success: false, error: 'Failed to send file');
      }
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Accept incoming file request
  Future<bool> acceptFile(String fileId) async {
    if (!_initialized) return false;

    final result = _bindings.fileAccept(fileId);
    if (result == 0) {
      debugPrint('FileProvider: Accepted file $fileId');
      _pendingRequests.removeWhere((r) => r.fileId == fileId);
      _pendingRequestsById.remove(fileId);
      final transfer = _transfers[fileId];
      if (transfer != null) {
        _transfers[fileId] = FileTransferInfo(
          fileId: transfer.fileId,
          filename: transfer.filename,
          mimeType: transfer.mimeType,
          size: transfer.size,
          state: CyxChatFileState.receiving,
          chunksDone: transfer.chunksDone,
          chunksTotal: transfer.chunksTotal,
          peerId: transfer.peerId,
          isOutgoing: transfer.isOutgoing,
          startedAt: transfer.startedAt,
        );
      }
      notifyListeners();
      return true;
    }
    debugPrint('FileProvider: Failed to accept file $fileId: $result');
    return false;
  }

  /// Reject incoming file request
  Future<bool> rejectFile(String fileId) async {
    if (!_initialized) return false;

    final result = _bindings.fileReject(fileId);
    if (result == 0) {
      debugPrint('FileProvider: Rejected file $fileId');
      _pendingRequests.removeWhere((r) => r.fileId == fileId);
      _pendingRequestsById.remove(fileId);
      final transfer = _transfers[fileId];
      if (transfer != null) {
        _transfers[fileId] = FileTransferInfo(
          fileId: transfer.fileId,
          filename: transfer.filename,
          mimeType: transfer.mimeType,
          size: transfer.size,
          state: CyxChatFileState.failed,
          chunksDone: transfer.chunksDone,
          chunksTotal: transfer.chunksTotal,
          peerId: transfer.peerId,
          isOutgoing: transfer.isOutgoing,
          startedAt: transfer.startedAt,
        );
      }
      notifyListeners();
      return true;
    }
    debugPrint('FileProvider: Failed to reject file $fileId: $result');
    return false;
  }

  /// Cancel ongoing transfer
  Future<bool> cancelTransfer(String fileId) async {
    if (!_initialized) return false;

    final result = _bindings.fileCancel(fileId);
    if (result == 0) {
      debugPrint('FileProvider: Cancelled transfer $fileId');
      _transfers.remove(fileId);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Pause transfer
  Future<bool> pauseTransfer(String fileId) async {
    if (!_initialized) return false;

    final result = _bindings.filePause(fileId);
    if (result == 0) {
      debugPrint('FileProvider: Paused transfer $fileId');
      final transfer = _transfers[fileId];
      if (transfer != null) {
        _transfers[fileId] = FileTransferInfo(
          fileId: transfer.fileId,
          filename: transfer.filename,
          mimeType: transfer.mimeType,
          size: transfer.size,
          state: CyxChatFileState.paused,
          chunksDone: transfer.chunksDone,
          chunksTotal: transfer.chunksTotal,
          peerId: transfer.peerId,
          isOutgoing: transfer.isOutgoing,
          startedAt: transfer.startedAt,
        );
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  /// Resume paused transfer
  Future<bool> resumeTransfer(String fileId) async {
    if (!_initialized) return false;

    final result = _bindings.fileResume(fileId);
    if (result == 0) {
      debugPrint('FileProvider: Resumed transfer $fileId');
      final transfer = _transfers[fileId];
      if (transfer != null) {
        _transfers[fileId] = FileTransferInfo(
          fileId: transfer.fileId,
          filename: transfer.filename,
          mimeType: transfer.mimeType,
          size: transfer.size,
          state: transfer.isOutgoing
              ? CyxChatFileState.sending
              : CyxChatFileState.receiving,
          chunksDone: transfer.chunksDone,
          chunksTotal: transfer.chunksTotal,
          peerId: transfer.peerId,
          isOutgoing: transfer.isOutgoing,
          startedAt: transfer.startedAt,
        );
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  /// Get received file data
  Uint8List? getReceivedFile(String fileId, {String? localPath}) {
    final cached = _receivedFiles[fileId];
    if (cached != null) return cached;

    final path = localPath ?? _storedFilePaths[fileId];
    if (path == null) return null;

    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final data = file.readAsBytesSync();
      final bytes = Uint8List.fromList(data);
      _receivedFiles[fileId] = bytes;
      _storedFilePaths[fileId] = path;
      return bytes;
    } catch (e) {
      debugPrint('FileProvider: Could not load stored file $fileId: $e');
      return null;
    }
  }

  bool hasFileData(String fileId, {String? localPath}) {
    if (_receivedFiles.containsKey(fileId)) return true;
    final path = localPath ?? _storedFilePaths[fileId];
    return path != null && File(path).existsSync();
  }

  String? getStoredFilePath(String fileId) => _storedFilePaths[fileId];

  Future<void> deleteStoredMedia({String? fileId, String? localPath}) async {
    if (fileId != null) {
      _receivedFiles.remove(fileId);
      localPath ??= _storedFilePaths[fileId];
      _storedFilePaths.remove(fileId);
    }

    if (localPath != null) {
      _storedFilePaths.removeWhere((_, path) => path == localPath);
      await deleteStoredMediaPath(localPath);
    }
    notifyListeners();
  }

  static Future<void> deleteStoredMediaPath(String localPath) async {
    if (localPath.isEmpty) return;

    final mediaDir = await _mediaDirectory();
    final context = path.Context(
      style: Platform.isWindows ? path.Style.windows : path.Style.posix,
    );
    final mediaRoot = context.normalize(mediaDir.absolute.path);
    final targetPath = context.normalize(File(localPath).absolute.path);
    final compareMediaRoot =
        Platform.isWindows ? mediaRoot.toLowerCase() : mediaRoot;
    final compareTargetPath =
        Platform.isWindows ? targetPath.toLowerCase() : targetPath;
    final mediaRootWithSeparator = compareMediaRoot.endsWith(context.separator)
        ? compareMediaRoot
        : '$compareMediaRoot${context.separator}';

    if (compareTargetPath != compareMediaRoot &&
        !compareTargetPath.startsWith(mediaRootWithSeparator)) {
      debugPrint('FileProvider: Refusing to delete media outside app storage');
      return;
    }

    final file = File(targetPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> _storeFileData(
    String fileId,
    String filename,
    Uint8List data,
  ) async {
    final dir = await _mediaDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}${_safeFileId(fileId)}${_safeExtension(filename)}';
    final file = File(path);
    await file.writeAsBytes(data, flush: true);
    _storedFilePaths[fileId] = file.path;
    return file.path;
  }

  /// Clear received file from memory
  void clearReceivedFile(String fileId) {
    _receivedFiles.remove(fileId);
  }

  static Future<Directory> _mediaDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _safeFileId(String fileId) {
    return fileId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _safeExtension(String filename) {
    final basename = filename.split(RegExp(r'[\\/]')).last;
    final dot = basename.lastIndexOf('.');
    if (dot <= 0 || dot == basename.length - 1) return '';
    final extension = basename.substring(dot);
    if (extension.length > 16 ||
        !RegExp(r'^\.[A-Za-z0-9]+$').hasMatch(extension)) {
      return '';
    }
    return extension;
  }

  /// Get active transfer count
  int get activeTransferCount => _bindings.fileActiveCount();

  @override
  void dispose() {
    shutdown();
    _requestController.close();
    _progressController.close();
    _completeController.close();
    _errorController.close();
    super.dispose();
  }
}

/// Global file provider instance
final fileNotifierProvider = ChangeNotifierProvider<FileProvider>((ref) {
  return FileProvider();
});

/// Provider for file actions
final fileActionsProvider = Provider((ref) => FileActions(ref));

/// File actions helper class
class FileActions {
  final Ref _ref;

  FileActions(this._ref);

  /// Initialize file provider
  Future<bool> initialize() {
    return _ref.read(fileNotifierProvider).initialize();
  }

  /// Send file to peer
  Future<FileSendResult> sendFile({
    required String toPeerId,
    required String filename,
    required Uint8List data,
    String? mimeType,
  }) {
    return _ref.read(fileNotifierProvider).sendFile(
          toPeerId: toPeerId,
          filename: filename,
          data: data,
          mimeType: mimeType,
        );
  }

  /// Accept incoming file
  Future<bool> acceptFile(String fileId) {
    return _ref.read(fileNotifierProvider).acceptFile(fileId);
  }

  /// Reject incoming file
  Future<bool> rejectFile(String fileId) {
    return _ref.read(fileNotifierProvider).rejectFile(fileId);
  }

  /// Cancel transfer
  Future<bool> cancelTransfer(String fileId) {
    return _ref.read(fileNotifierProvider).cancelTransfer(fileId);
  }

  /// Pause transfer
  Future<bool> pauseTransfer(String fileId) {
    return _ref.read(fileNotifierProvider).pauseTransfer(fileId);
  }

  /// Resume transfer
  Future<bool> resumeTransfer(String fileId) {
    return _ref.read(fileNotifierProvider).resumeTransfer(fileId);
  }

  /// Set direct mode for file transfers
  void setDirectMode(bool enabled) {
    _ref.read(fileNotifierProvider).setDirectMode(enabled);
  }

  /// Get current direct mode status
  bool get isDirectMode => _ref.read(fileNotifierProvider).isDirectMode;
}

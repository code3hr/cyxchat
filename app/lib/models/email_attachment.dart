import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Attachment disposition
enum AttachmentDisposition {
  attachment,
  inline;

  static AttachmentDisposition fromInt(int value) {
    if (value >= 0 && value < AttachmentDisposition.values.length) {
      return AttachmentDisposition.values[value];
    }
    return AttachmentDisposition.attachment;
  }
}

/// Attachment storage type
enum AttachmentStorageType {
  inline,   // Stored in database (small files <64KB)
  chunked,  // P2P chunked transfer
  cyxcloud; // Stored in CyxCloud

  static AttachmentStorageType fromInt(int value) {
    if (value >= 0 && value < AttachmentStorageType.values.length) {
      return AttachmentStorageType.values[value];
    }
    return AttachmentStorageType.inline;
  }
}

/// Download state
enum DownloadState {
  notStarted,
  downloading,
  completed,
  failed;

  static DownloadState fromInt(int value) {
    if (value >= 0 && value < DownloadState.values.length) {
      return DownloadState.values[value];
    }
    return DownloadState.notStarted;
  }
}

/// Email attachment
class EmailAttachment extends Equatable {
  final int? id;
  final String mailId;
  final String fileId;
  final String filename;
  final String? mimeType;
  final int fileSize;
  final String? fileHash;
  final AttachmentDisposition disposition;
  final AttachmentStorageType storageType;
  final String? contentId;
  final Uint8List? inlineData;
  final DownloadState downloadState;
  final String? localPath;

  const EmailAttachment({
    this.id,
    required this.mailId,
    required this.fileId,
    required this.filename,
    this.mimeType,
    required this.fileSize,
    this.fileHash,
    this.disposition = AttachmentDisposition.attachment,
    this.storageType = AttachmentStorageType.inline,
    this.contentId,
    this.inlineData,
    this.downloadState = DownloadState.notStarted,
    this.localPath,
  });

  factory EmailAttachment.fromMap(Map<String, dynamic> map) {
    return EmailAttachment(
      id: map['id'] as int?,
      mailId: map['mail_id'] as String,
      fileId: map['file_id'] as String,
      filename: map['filename'] as String,
      mimeType: map['mime_type'] as String?,
      fileSize: map['file_size'] as int,
      fileHash: map['file_hash'] as String?,
      disposition: AttachmentDisposition.fromInt(map['disposition'] as int? ?? 0),
      storageType: AttachmentStorageType.fromInt(map['storage_type'] as int? ?? 0),
      contentId: map['content_id'] as String?,
      inlineData: map['inline_data'] as Uint8List?,
      downloadState: DownloadState.fromInt(map['download_state'] as int? ?? 0),
      localPath: map['local_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'mail_id': mailId,
      'file_id': fileId,
      'filename': filename,
      'mime_type': mimeType,
      'file_size': fileSize,
      'file_hash': fileHash,
      'disposition': disposition.index,
      'storage_type': storageType.index,
      'content_id': contentId,
      'inline_data': inlineData,
      'download_state': downloadState.index,
      'local_path': localPath,
    };
  }

  /// Get human-readable file size
  String get fileSizeString {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// Check if attachment is an image
  bool get isImage {
    final mime = mimeType?.toLowerCase() ?? '';
    return mime.startsWith('image/');
  }

  /// Get icon name for attachment type
  String get iconName {
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video_file';
    if (mime.startsWith('audio/')) return 'audio_file';
    if (mime.contains('pdf')) return 'picture_as_pdf';
    if (mime.contains('zip') || mime.contains('rar') || mime.contains('tar')) {
      return 'folder_zip';
    }
    if (mime.contains('word') || mime.contains('document')) return 'description';
    if (mime.contains('excel') || mime.contains('spreadsheet')) return 'table_chart';
    return 'attach_file';
  }

  @override
  List<Object?> get props => [
        id,
        mailId,
        fileId,
        filename,
        mimeType,
        fileSize,
        fileHash,
        disposition,
        storageType,
        contentId,
        downloadState,
        localPath,
      ];

  EmailAttachment copyWith({
    int? id,
    String? mailId,
    String? fileId,
    String? filename,
    String? mimeType,
    int? fileSize,
    String? fileHash,
    AttachmentDisposition? disposition,
    AttachmentStorageType? storageType,
    String? contentId,
    Uint8List? inlineData,
    DownloadState? downloadState,
    String? localPath,
  }) {
    return EmailAttachment(
      id: id ?? this.id,
      mailId: mailId ?? this.mailId,
      fileId: fileId ?? this.fileId,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      fileHash: fileHash ?? this.fileHash,
      disposition: disposition ?? this.disposition,
      storageType: storageType ?? this.storageType,
      contentId: contentId ?? this.contentId,
      inlineData: inlineData ?? this.inlineData,
      downloadState: downloadState ?? this.downloadState,
      localPath: localPath ?? this.localPath,
    );
  }
}

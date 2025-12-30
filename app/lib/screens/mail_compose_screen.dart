import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../models/email_message.dart';
import '../providers/mail_provider.dart';

/// Screen for composing a new email
class MailComposeScreen extends ConsumerStatefulWidget {
  /// If replying, the original message
  final EmailMessage? replyTo;

  /// If forwarding, the original message
  final EmailMessage? forwardOf;

  /// Pre-filled recipient (for direct compose)
  final String? toNodeId;
  final String? toName;

  const MailComposeScreen({
    super.key,
    this.replyTo,
    this.forwardOf,
    this.toNodeId,
    this.toName,
  });

  @override
  ConsumerState<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends ConsumerState<MailComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  final List<PlatformFile> _attachments = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    // Handle reply
    if (widget.replyTo != null) {
      final original = widget.replyTo!;
      _toController.text = original.from.nodeId;
      _subjectController.text = original.subject?.startsWith('Re:') == true
          ? original.subject!
          : 'Re: ${original.subject ?? ''}';
      _bodyController.text = _buildReplyBody(original);
    }
    // Handle forward
    else if (widget.forwardOf != null) {
      final original = widget.forwardOf!;
      _subjectController.text = original.subject?.startsWith('Fwd:') == true
          ? original.subject!
          : 'Fwd: ${original.subject ?? ''}';
      _bodyController.text = _buildForwardBody(original);
    }
    // Handle direct compose to contact
    else if (widget.toNodeId != null) {
      _toController.text = widget.toNodeId!;
    }
  }

  String _buildReplyBody(EmailMessage original) {
    return '''


On ${original.dateString}, ${original.from.display} wrote:
> ${original.body?.replaceAll('\n', '\n> ') ?? ''}
''';
  }

  String _buildForwardBody(EmailMessage original) {
    return '''


---------- Forwarded message ----------
From: ${original.from.display}
Date: ${original.dateString}
Subject: ${original.subject ?? '(no subject)'}

${original.body ?? ''}
''';
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _addAttachment,
            tooltip: 'Add attachment',
          ),
          IconButton(
            icon: const Icon(Icons.drafts),
            onPressed: _saveDraft,
            tooltip: 'Save draft',
          ),
          IconButton(
            icon: _isSending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            onPressed: _isSending ? null : _send,
            tooltip: 'Send',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // To field
            TextFormField(
              controller: _toController,
              decoration: const InputDecoration(
                labelText: 'To',
                hintText: 'Enter recipient address or .cyx name',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a recipient';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Subject field
            TextFormField(
              controller: _subjectController,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.subject),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a subject';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Attachments
            if (_attachments.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _attachments.map(_buildAttachmentChip).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Body field
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              maxLines: null,
              minLines: 10,
              keyboardType: TextInputType.multiline,
            ),
          ],
        ),
      ),
    );
  }

  String _getTitle() {
    if (widget.replyTo != null) return 'Reply';
    if (widget.forwardOf != null) return 'Forward';
    return 'New Email';
  }

  Widget _buildAttachmentChip(PlatformFile file) {
    return Chip(
      avatar: Icon(_getFileIcon(file.extension)),
      label: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: () => setState(() => _attachments.remove(file)),
    );
  }

  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
        return Icons.folder_zip;
      default:
        return Icons.attach_file;
    }
  }

  Future<void> _addAttachment() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() => _attachments.addAll(result.files));
    }
  }

  Future<void> _saveDraft() async {
    if (_toController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a recipient')),
      );
      return;
    }

    try {
      await ref.read(mailActionsProvider).saveDraft(
            toNodeId: _toController.text.trim(),
            subject: _subjectController.text.trim(),
            body: _bodyController.text,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save draft: $e')),
        );
      }
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      // Prepare attachments
      final attachmentData = <EmailAttachmentData>[];
      for (final file in _attachments) {
        if (file.bytes != null) {
          attachmentData.add(EmailAttachmentData(
            filename: file.name,
            mimeType: _getMimeType(file.extension),
            data: file.bytes!,
          ));
        } else if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          attachmentData.add(EmailAttachmentData(
            filename: file.name,
            mimeType: _getMimeType(file.extension),
            data: bytes,
          ));
        }
      }

      await ref.read(mailActionsProvider).sendEmail(
            toNodeId: _toController.text.trim(),
            subject: _subjectController.text.trim(),
            body: _bodyController.text,
            inReplyTo: widget.replyTo?.mailId,
            attachments: attachmentData.isNotEmpty ? attachmentData : null,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email sent')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _getMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'zip':
        return 'application/zip';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/document_kind.dart';
import 'local_photo.dart';

/// A rectangular photo capture tile shared by the Aadhar and Driving License
/// steps — tap to take a photo of the document with the rear camera; tap
/// again to retake.
///
/// The tile also reports the upload: the photo goes to the backend as soon as
/// it's taken, so it shows progress over the thumbnail and offers a retry when
/// that fails, rather than letting the driver walk away believing it's saved.
class DocumentPhotoPicker extends StatelessWidget {
  const DocumentPhotoPicker({
    super.key,
    required this.photoPath,
    required this.onPhotoTaken,
    this.uploadState = DocumentUploadState.none,
    this.label = 'Take a photo of the document',
  });

  /// The local capture, or null when nothing was taken on this device.
  final String? photoPath;

  final ValueChanged<String> onPhotoTaken;

  /// How the upload of this document is going.
  final DocumentUploadState uploadState;

  final String label;

  /// Whether the backend has the image, even if the local capture is gone —
  /// captures are deleted once onboarding is submitted.
  bool get _isUploaded => uploadState == DocumentUploadState.uploaded;

  Future<void> _pick() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (photo != null) onPhotoTaken(photo.path);
  }

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final path = photoPath;
    final isUploading = uploadState == DocumentUploadState.uploading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            // Blocked mid-upload: replacing the file under an in-flight
            // request would upload one photo and display another.
            onTap: isUploading ? null : _pick,
            borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
            child: Container(
              height: 160,
              width: double.infinity,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: t.raised,
                border: Border.all(
                  color: path == null && !_isUploaded
                      ? t.hairline
                      : t.accentBorder,
                ),
                borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
              ),
              child: _content(t, path, isUploading),
            ),
          ),
        ),
        if (uploadState == DocumentUploadState.failed) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(
            "Upload didn't finish — tap to take the photo again.",
            style: t.body(size: 13, color: Colors.red),
          ),
        ],
      ],
    );
  }

  Widget _content(DeepSignalTokens t, String? path, bool isUploading) {
    if (path == null) {
      // No local file. Either nothing taken yet, or the capture was cleaned up
      // after submission and only the server's copy remains.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isUploaded
                ? Icons.check_circle_outline
                : Icons.camera_alt_outlined,
            color: _isUploaded ? t.accent : t.muted,
            size: 28,
          ),
          const SizedBox(height: DeepSignalTokens.s8),
          Text(
            _isUploaded ? 'Photo uploaded' : label,
            style: t.body(size: 13, color: t.muted),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        LocalPhoto(path: path),
        if (isUploading)
          ColoredBox(
            color: t.invertedSurface.withValues(alpha: 0.5),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.accent,
                ),
              ),
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: t.invertedSurface,
              borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
            ),
            child: Text(switch (uploadState) {
              DocumentUploadState.uploading => 'Uploading…',
              DocumentUploadState.uploaded => 'Uploaded',
              DocumentUploadState.failed => 'Retry',
              DocumentUploadState.none => 'Retake',
            }, style: t.body(size: 12, color: t.invertedFg)),
          ),
        ),
      ],
    );
  }
}

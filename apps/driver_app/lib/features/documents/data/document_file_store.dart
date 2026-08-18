import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../domain/document_kind.dart';

/// Keeps captured KYC images on the device between taking them and the
/// backend confirming it has them.
///
/// `image_picker` writes into the OS cache directory, which Android is free to
/// empty whenever it wants space — a driver who takes a selfie, backgrounds
/// the app and comes back an hour later would find it gone. Each capture is
/// therefore copied into the app's documents directory, and deleted again once
/// the upload succeeds: an Aadhaar photo has no business outliving its upload.
class DocumentFileStore {
  DocumentFileStore({Directory? directory}) : _override = directory;

  final Directory? _override;
  Directory? _resolved;

  /// Subdirectory holding in-flight captures.
  static const String folderName = 'kyc_captures';

  /// Copies the freshly captured file at [sourcePath] into durable storage and
  /// returns the new path. One file per [kind], so a retake replaces the
  /// previous capture instead of accumulating.
  ///
  /// On web there is no filesystem to copy into — the picker's `blob:` URL is
  /// already all the app has — so the path is returned unchanged.
  Future<String> persist(DocumentKind kind, String sourcePath) async {
    if (kIsWeb) return sourcePath;

    final dir = await _directory();
    final destination = File('${dir.path}/${kind.wireName}.jpg');
    await File(sourcePath).copy(destination.path);
    return destination.path;
  }

  /// Deletes the stored capture for [kind], if any. Called once the backend
  /// has the image; failures are swallowed because a leftover file is a
  /// tidiness problem, not a correctness one.
  Future<void> discard(DocumentKind kind) async {
    if (kIsWeb) return;

    try {
      final dir = await _directory();
      final file = File('${dir.path}/${kind.wireName}.jpg');
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Already gone, or not ours to delete.
    }
  }

  /// Returns the stored capture path for [kind], or null when there is none.
  Future<String?> pathFor(DocumentKind kind) async {
    if (kIsWeb) return null;

    final dir = await _directory();
    final file = File('${dir.path}/${kind.wireName}.jpg');
    return file.existsSync() ? file.path : null;
  }

  /// Removes every stored capture — used when onboarding is submitted, so no
  /// identity document is left sitting on the device.
  Future<void> discardAll() async {
    for (final kind in DocumentKind.values) {
      await discard(kind);
    }
  }

  Future<Directory> _directory() async {
    final cached = _resolved;
    if (cached != null) return cached;

    final base = _override ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$folderName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _resolved = dir;
    return dir;
  }
}

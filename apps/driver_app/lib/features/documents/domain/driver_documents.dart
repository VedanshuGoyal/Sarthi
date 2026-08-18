import 'document_kind.dart';

/// The on-device half of the Document View.
///
/// Everything the driver types — name, Aadhaar, licence, bank details — now
/// goes straight to the backend as each step is submitted, so it isn't held
/// here: the server is the draft. What remains local is the two things that
/// can't live there.
///
///  * [capturePaths] — the file for each photo, kept only so the step can show
///    what was taken; the uploaded copy is the real one.
///  * the three permission flags — OS grants, re-read from the system every
///    time the permissions step opens rather than trusted from storage.
class DriverDocuments {
  const DriverDocuments({
    this.capturePaths = const {},
    this.uploadStates = const {},
    this.overlayPermissionGranted = false,
    this.backgroundLocationGranted = false,
    this.batteryUnrestricted = false,
  });

  /// Local file path per captured image.
  final Map<DocumentKind, String> capturePaths;

  /// How each image's upload is going. Absent means [DocumentUploadState.none].
  final Map<DocumentKind, DocumentUploadState> uploadStates;

  final bool overlayPermissionGranted;
  final bool backgroundLocationGranted;
  final bool batteryUnrestricted;

  /// The local file for [kind], or null when nothing was captured this session.
  String? capturePathFor(DocumentKind kind) => capturePaths[kind];

  /// The upload state for [kind].
  DocumentUploadState uploadStateFor(DocumentKind kind) =>
      uploadStates[kind] ?? DocumentUploadState.none;

  /// Whether every OS permission the "Go Online" flow needs has been granted.
  bool get hasAllPermissions =>
      overlayPermissionGranted &&
      backgroundLocationGranted &&
      batteryUnrestricted;

  DriverDocuments copyWith({
    Map<DocumentKind, String>? capturePaths,
    Map<DocumentKind, DocumentUploadState>? uploadStates,
    bool? overlayPermissionGranted,
    bool? backgroundLocationGranted,
    bool? batteryUnrestricted,
  }) {
    return DriverDocuments(
      capturePaths: capturePaths ?? this.capturePaths,
      uploadStates: uploadStates ?? this.uploadStates,
      overlayPermissionGranted:
          overlayPermissionGranted ?? this.overlayPermissionGranted,
      backgroundLocationGranted:
          backgroundLocationGranted ?? this.backgroundLocationGranted,
      batteryUnrestricted: batteryUnrestricted ?? this.batteryUnrestricted,
    );
  }

  /// Returns a copy with [kind]'s capture path replaced.
  DriverDocuments withCapture(DocumentKind kind, String path) =>
      copyWith(capturePaths: {...capturePaths, kind: path});

  /// Returns a copy with [kind]'s upload state replaced.
  DriverDocuments withUploadState(
    DocumentKind kind,
    DocumentUploadState state,
  ) => copyWith(uploadStates: {...uploadStates, kind: state});
}

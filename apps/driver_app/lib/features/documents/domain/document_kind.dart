/// The KYC images a driver uploads, matching the backend's document kinds.
///
/// The [wireName] values are the ones the API expects in
/// `POST /driver/kyc/documents/{kind}` — they must stay in step with
/// `domain.DocumentKind` on the server.
enum DocumentKind {
  selfie('selfie'),
  aadhaar('aadhaar'),
  drivingLicense('driving_license');

  const DocumentKind(this.wireName);

  final String wireName;

  /// Parses a kind from the API, or null for one this build doesn't know
  /// about — a newer server must not crash an older app.
  static DocumentKind? fromWire(String value) {
    for (final kind in DocumentKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// Where one image sits between being taken and being accepted.
enum DocumentUploadState {
  /// Nothing taken for this kind yet.
  none,

  /// Captured on device, upload in flight.
  uploading,

  /// The backend has it.
  uploaded,

  /// The upload failed; the driver can retry.
  failed,
}

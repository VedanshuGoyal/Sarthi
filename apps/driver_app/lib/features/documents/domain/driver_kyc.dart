import 'document_kind.dart';
import 'gender.dart';
import 'vehicle_type.dart';

/// Where the driver's whole Document View stands, as the backend sees it.
///
/// The server owns this — the app reports what it collected, never whether it
/// passed — so a driver can't reach Home by editing local state.
enum KycStatus {
  /// Still filling in the six steps.
  incomplete,

  /// Everything supplied, but something needs a person to look before the
  /// driver can go online — see [DriverKyc.reviewNote].
  submitted,

  /// Every check passed: cleared to drive.
  verified,

  /// Something was refused and needs redoing.
  rejected;

  static KycStatus fromWire(String? value) => switch (value) {
    'submitted' => KycStatus.submitted,
    'verified' => KycStatus.verified,
    'rejected' => KycStatus.rejected,
    _ => KycStatus.incomplete,
  };
}

/// The masked payout details the backend returns. The account number itself is
/// encrypted server-side and never comes back — only the last four digits, so
/// the driver can recognise their own account.
///
/// [verifiedAt] is set once the bank confirmed the account exists (a penny
/// drop), and [verifiedName] is the name the bank holds for it.
class BankAccountSummary {
  const BankAccountSummary({
    required this.accountHolderName,
    required this.accountNumberLast4,
    required this.ifscCode,
    this.verifiedAt,
    this.verifiedName,
  });

  final String accountHolderName;
  final String accountNumberLast4;
  final String ifscCode;
  final DateTime? verifiedAt;
  final String? verifiedName;

  bool get isVerified => verifiedAt != null;

  factory BankAccountSummary.fromJson(Map<String, dynamic> json) {
    return BankAccountSummary(
      accountHolderName: json['accountHolderName'] as String? ?? '',
      accountNumberLast4: json['accountNumberLast4'] as String? ?? '',
      ifscCode: json['ifscCode'] as String? ?? '',
      verifiedAt: DriverKyc._parseDate(json['verifiedAt']),
      verifiedName: DriverKyc._nonEmpty(json['verifiedName']),
    );
  }
}

/// Everything the backend holds for a driver's KYC: the typed fields, which
/// images have landed, and the review status.
///
/// [aadhaarLast4] is all that comes back of the Aadhaar number — the server
/// stores nothing more of it — so the app shows a masked value rather than
/// re-displaying what the driver typed.
///
/// The `…VerifiedAt` fields are the server's checks: Aadhaar through
/// DigiLocker, the licence through the transport department's records. Once
/// the Aadhaar is verified, [fullName], [dateOfBirth] and [gender] are the
/// Aadhaar's and can't be edited.
class DriverKyc {
  const DriverKyc({
    this.status = KycStatus.incomplete,
    this.fullName = '',
    this.dateOfBirth,
    this.gender,
    this.transmission,
    this.aadhaarLast4,
    this.drivingLicenseNumber,
    this.uploadedKinds = const {},
    this.bankAccount,
    this.aadhaarVerifiedAt,
    this.licenseVerifiedAt,
    this.licenseName,
    this.licenseValidUntil,
    this.licenseClasses = const [],
    this.reviewNote,
  });

  final KycStatus status;
  final String fullName;
  final DateTime? dateOfBirth;
  final Gender? gender;
  final VehicleType? transmission;
  final String? aadhaarLast4;
  final String? drivingLicenseNumber;

  /// Which images the backend has. Drives the photo steps' completion, since
  /// a file sitting on the device proves nothing.
  final Set<DocumentKind> uploadedKinds;

  final BankAccountSummary? bankAccount;

  final DateTime? aadhaarVerifiedAt;
  final DateTime? licenseVerifiedAt;

  /// The name on the driving licence, as the transport department has it.
  final String? licenseName;
  final DateTime? licenseValidUntil;

  /// What the licence covers, e.g. `LMV`, `MCWG`.
  final List<String> licenseClasses;

  /// Why the driver is under review or was rejected, safe to show.
  final String? reviewNote;

  bool get isAadhaarVerified => aadhaarVerifiedAt != null;
  bool get isLicenseVerified => licenseVerifiedAt != null;
  bool get isBankVerified => bankAccount?.isVerified ?? false;

  factory DriverKyc.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>? ?? const {};
    final documents = json['documents'] as List<dynamic>? ?? const [];
    final bank = json['bankAccount'] as Map<String, dynamic>?;

    final uploaded = <DocumentKind>{};
    for (final entry in documents) {
      if (entry is! Map<String, dynamic>) continue;
      final kind = DocumentKind.fromWire(entry['kind'] as String? ?? '');
      if (kind != null) uploaded.add(kind);
    }

    return DriverKyc(
      status: KycStatus.fromWire(profile['kycStatus'] as String?),
      fullName: profile['fullName'] as String? ?? '',
      dateOfBirth: _parseDate(profile['dateOfBirth']),
      gender: _parseEnum(Gender.values, profile['gender']),
      transmission: _parseEnum(VehicleType.values, profile['transmission']),
      aadhaarLast4: _nonEmpty(profile['aadhaarLast4']),
      drivingLicenseNumber: _nonEmpty(profile['drivingLicenseNumber']),
      uploadedKinds: uploaded,
      bankAccount: bank == null ? null : BankAccountSummary.fromJson(bank),
      aadhaarVerifiedAt: _parseDate(profile['aadhaarVerifiedAt']),
      licenseVerifiedAt: _parseDate(profile['licenseVerifiedAt']),
      licenseName: _nonEmpty(profile['licenseName']),
      licenseValidUntil: _parseDate(profile['licenseValidUntil']),
      licenseClasses: [
        for (final c in profile['licenseClasses'] as List<dynamic>? ?? const [])
          if (c is String && c.isNotEmpty) c,
      ],
      reviewNote: _nonEmpty(profile['kycReviewNote']),
    );
  }

  /// Whether the backend already has [kind].
  bool hasUploaded(DocumentKind kind) => uploadedKinds.contains(kind);

  static String? _nonEmpty(Object? value) {
    final text = value as String?;
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Parses the server's timestamps (RFC 3339) and plain dates (YYYY-MM-DD).
  static DateTime? _parseDate(Object? value) {
    final text = value as String?;
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  /// Matches a wire string against an enum by name — both [Gender] and
  /// [VehicleType] use identical names on either side of the wire.
  static T? _parseEnum<T extends Enum>(List<T> values, Object? value) {
    final text = value as String?;
    if (text == null || text.isEmpty) return null;
    for (final candidate in values) {
      if (candidate.name == text) return candidate;
    }
    return null;
  }
}

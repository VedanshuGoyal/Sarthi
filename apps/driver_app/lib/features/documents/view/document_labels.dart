import '../../../l10n/l10n.dart';
import '../domain/document_step.dart';
import '../domain/gender.dart';
import '../domain/vehicle_type.dart';

/// The driver-facing words for KYC values, in the app's language. Pass
/// `context.l10n` from a widget, or `L10n.current` from code without a
/// context.

extension VehicleTypeText on VehicleType {
  String labelIn(AppLocalizations l10n) => switch (this) {
    VehicleType.manual => l10n.transmissionManual,
    VehicleType.automatic => l10n.transmissionAutomatic,
    VehicleType.both => l10n.transmissionBoth,
  };
}

extension GenderText on Gender {
  String labelIn(AppLocalizations l10n) => switch (this) {
    Gender.male => l10n.genderMale,
    Gender.female => l10n.genderFemale,
    Gender.other => l10n.genderOther,
  };
}

extension DocumentStepText on DocumentStep {
  String titleIn(AppLocalizations l10n) => switch (this) {
    DocumentStep.vehicleType => l10n.docStepVehicleTypeTitle,
    DocumentStep.photoAndName => l10n.docStepPhotoAndNameTitle,
    DocumentStep.aadhar => l10n.docStepAadhaarTitle,
    DocumentStep.drivingLicense => l10n.docStepLicenseTitle,
    DocumentStep.permissions => l10n.docStepPermissionsTitle,
    DocumentStep.bankDetails => l10n.docStepBankTitle,
  };

  String subtitleIn(AppLocalizations l10n) => switch (this) {
    DocumentStep.vehicleType => l10n.docStepVehicleTypeSubtitle,
    DocumentStep.photoAndName => l10n.docStepPhotoAndNameSubtitle,
    DocumentStep.aadhar => l10n.docStepAadhaarSubtitle,
    DocumentStep.drivingLicense => l10n.docStepLicenseSubtitle,
    DocumentStep.permissions => l10n.docStepPermissionsSubtitle,
    DocumentStep.bankDetails => l10n.docStepBankSubtitle,
  };
}

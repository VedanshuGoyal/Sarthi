// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MOJUD Driver';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Close';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonSave => 'Save';

  @override
  String get commonNotAdded => 'Not added';

  @override
  String get commonNotSet => 'Not set';

  @override
  String get errorNoConnection =>
      'Can\'t reach the server. Check your connection and try again.';

  @override
  String get errorUnexpectedReply =>
      'The server sent an unexpected reply. Please try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get languageTitle => 'Language · भाषा';

  @override
  String get languageFollowsPhone =>
      'Same as your phone. Pick one to change it.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिंदी';

  @override
  String get rideStatusRequested => 'New request';

  @override
  String get rideStatusAccepted => 'Upcoming';

  @override
  String get rideStatusArrived => 'At pickup';

  @override
  String get rideStatusInProgress => 'On trip';

  @override
  String get rideStatusCompleted => 'Completed';

  @override
  String get rideStatusCancelled => 'Cancelled';

  @override
  String get rideStatusUnknown => 'Status unknown';

  @override
  String get tripKindRoundTrip => 'Round trip';

  @override
  String get tripKindOneWay => 'One way';

  @override
  String get tripKindMultiStop => 'Multi-stop';

  @override
  String get tripKindOther => 'Trip';

  @override
  String get ridePaymentDue => 'Awaiting payment';

  @override
  String get ridePaymentPaid => 'Paid';

  @override
  String get ridePaymentPaidOut => 'Paid out';

  @override
  String get rideCancelledAtPickup => 'Customer cancelled at the pickup';

  @override
  String get rideCancelledByCustomer => 'Cancelled by customer';

  @override
  String get rideCancelledNoShow => 'Customer didn\'t come';

  @override
  String get carTypeHatchback => 'Hatchback';

  @override
  String get carTypeSedan => 'Sedan';

  @override
  String get carTypeSuv => 'SUV';

  @override
  String get carTypeLuxury => 'Luxury';

  @override
  String get carTypeUnknown => 'Car';

  @override
  String get transmissionManual => 'Manual';

  @override
  String get transmissionAutomatic => 'Automatic';

  @override
  String get transmissionBoth => 'Manual and Automatic Both';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderOther => 'Other';

  @override
  String get docStepVehicleTypeTitle => 'Type of Vehicle';

  @override
  String get docStepVehicleTypeSubtitle => 'Manual, automatic, or both';

  @override
  String get docStepPhotoAndNameTitle => 'Photo and Name';

  @override
  String get docStepPhotoAndNameSubtitle =>
      'Selfie, full name, date of birth, gender';

  @override
  String get docStepAadhaarTitle => 'Aadhaar Card';

  @override
  String get docStepAadhaarSubtitle => 'Verify with DigiLocker';

  @override
  String get docStepLicenseTitle => 'Driving License';

  @override
  String get docStepLicenseSubtitle => 'License number, checked instantly';

  @override
  String get docStepPermissionsTitle => 'Permissions';

  @override
  String get docStepPermissionsSubtitle =>
      'Display over other apps, background location, battery usage';

  @override
  String get docStepBankTitle => 'Bank Details';

  @override
  String get docStepBankSubtitle =>
      'Where your earnings are paid, verified with your bank';
}

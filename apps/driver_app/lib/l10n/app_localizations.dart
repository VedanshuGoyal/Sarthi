import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// App name in the OS task switcher. Brand name: never translated.
  ///
  /// In en, this message translates to:
  /// **'MOJUD Driver'**
  String get appTitle;

  /// Button that dismisses a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Button that acknowledges a dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Button or tooltip that closes a sheet or screen.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Button that moves on to the next step.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// Button that retries a failed load or action.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Button that saves a form.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Shown in place of a detail (licence, Aadhaar) the driver hasn't given yet.
  ///
  /// In en, this message translates to:
  /// **'Not added'**
  String get commonNotAdded;

  /// Shown in place of a setting the driver hasn't chosen yet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get commonNotSet;

  /// Shown when the phone can't reach the backend (no internet, timeout).
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection and try again.'**
  String get errorNoConnection;

  /// Shown when the backend's reply can't be read.
  ///
  /// In en, this message translates to:
  /// **'The server sent an unexpected reply. Please try again.'**
  String get errorUnexpectedReply;

  /// Fallback error when the backend gives no reason.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// Heading of the app-language setting. Bilingual on purpose, so a driver can find it in either language: put the current language first.
  ///
  /// In en, this message translates to:
  /// **'Language · भाषा'**
  String get languageTitle;

  /// Under the language switch while the app follows the phone language.
  ///
  /// In en, this message translates to:
  /// **'Same as your phone. Pick one to change it.'**
  String get languageFollowsPhone;

  /// Language option. Always shown in English, whatever the app language.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Language option. Always shown in Hindi script, whatever the app language.
  ///
  /// In en, this message translates to:
  /// **'हिंदी'**
  String get languageHindi;

  /// Ride status chip: an open ride the driver can take.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get rideStatusRequested;

  /// Ride status chip: the driver's ride, not started yet.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get rideStatusAccepted;

  /// Ride status chip: the driver is waiting at the pickup.
  ///
  /// In en, this message translates to:
  /// **'At pickup'**
  String get rideStatusArrived;

  /// Ride status chip: the trip is underway.
  ///
  /// In en, this message translates to:
  /// **'On trip'**
  String get rideStatusInProgress;

  /// Ride status chip: the trip is done.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get rideStatusCompleted;

  /// Ride status chip / cancel reason: the ride was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get rideStatusCancelled;

  /// Ride status chip for a status this app version doesn't know.
  ///
  /// In en, this message translates to:
  /// **'Status unknown'**
  String get rideStatusUnknown;

  /// Trip type: driver hired by the hour, ends back at the pickup. Same words as the customer app.
  ///
  /// In en, this message translates to:
  /// **'Round trip'**
  String get tripKindRoundTrip;

  /// Trip type: pickup to a destination.
  ///
  /// In en, this message translates to:
  /// **'One way'**
  String get tripKindOneWay;

  /// Trip type: a trip with several errands/stops.
  ///
  /// In en, this message translates to:
  /// **'Multi-stop'**
  String get tripKindMultiStop;

  /// Trip type this app version doesn't know.
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get tripKindOther;

  /// The customer hasn't paid for the ride yet.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get ridePaymentDue;

  /// The customer paid MOJUD; the driver's share comes in the next payout.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get ridePaymentPaid;

  /// The driver's share has been sent to their bank.
  ///
  /// In en, this message translates to:
  /// **'Paid out'**
  String get ridePaymentPaidOut;

  /// Cancel reason: the customer cancelled after the driver reached the pickup (a fee applies).
  ///
  /// In en, this message translates to:
  /// **'Customer cancelled at the pickup'**
  String get rideCancelledAtPickup;

  /// Cancel reason.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by customer'**
  String get rideCancelledByCustomer;

  /// Cancel reason: the driver closed the ride because the customer never came to the pickup.
  ///
  /// In en, this message translates to:
  /// **'Customer didn\'t come'**
  String get rideCancelledNoShow;

  /// Customer's car type.
  ///
  /// In en, this message translates to:
  /// **'Hatchback'**
  String get carTypeHatchback;

  /// Customer's car type.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get carTypeSedan;

  /// Customer's car type.
  ///
  /// In en, this message translates to:
  /// **'SUV'**
  String get carTypeSuv;

  /// Customer's car type.
  ///
  /// In en, this message translates to:
  /// **'Luxury'**
  String get carTypeLuxury;

  /// Customer's car when its type isn't known.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get carTypeUnknown;

  /// Gearbox: manual (stick shift).
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get transmissionManual;

  /// Gearbox: automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get transmissionAutomatic;

  /// The driver drives both manual and automatic cars.
  ///
  /// In en, this message translates to:
  /// **'Manual and Automatic Both'**
  String get transmissionBoth;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get genderOther;

  /// KYC step title: which gearbox(es) the driver can drive.
  ///
  /// In en, this message translates to:
  /// **'Type of Vehicle'**
  String get docStepVehicleTypeTitle;

  /// KYC step subtitle.
  ///
  /// In en, this message translates to:
  /// **'Manual, automatic, or both'**
  String get docStepVehicleTypeSubtitle;

  /// KYC step title.
  ///
  /// In en, this message translates to:
  /// **'Photo and Name'**
  String get docStepPhotoAndNameTitle;

  /// KYC step subtitle.
  ///
  /// In en, this message translates to:
  /// **'Selfie, full name, date of birth, gender'**
  String get docStepPhotoAndNameSubtitle;

  /// KYC step title.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar Card'**
  String get docStepAadhaarTitle;

  /// KYC step subtitle.
  ///
  /// In en, this message translates to:
  /// **'Verify with DigiLocker'**
  String get docStepAadhaarSubtitle;

  /// KYC step title.
  ///
  /// In en, this message translates to:
  /// **'Driving License'**
  String get docStepLicenseTitle;

  /// KYC step subtitle.
  ///
  /// In en, this message translates to:
  /// **'License number, checked instantly'**
  String get docStepLicenseSubtitle;

  /// KYC step title: phone permissions the app needs.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get docStepPermissionsTitle;

  /// KYC step subtitle.
  ///
  /// In en, this message translates to:
  /// **'Display over other apps, background location, battery usage'**
  String get docStepPermissionsSubtitle;

  /// KYC step title.
  ///
  /// In en, this message translates to:
  /// **'Bank Details'**
  String get docStepBankTitle;

  /// KYC step subtitle.
  ///
  /// In en, this message translates to:
  /// **'Where your earnings are paid, verified with your bank'**
  String get docStepBankSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

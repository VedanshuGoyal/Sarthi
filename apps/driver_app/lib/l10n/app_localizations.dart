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

  /// Account tab: app bar title.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTitle;

  /// Account tab: title of the log-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get accountLogOutConfirmTitle;

  /// Account tab: body of the log-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'You\'ll go off duty and stop getting ride requests on this phone.'**
  String get accountLogOutConfirmBody;

  /// Account tab: log-out button and its confirm action.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get accountLogOut;

  /// Subject line pre-filled in the support email the driver sends.
  ///
  /// In en, this message translates to:
  /// **'Driver app help'**
  String get accountSupportEmailSubject;

  /// Snackbar when no email app could open; shows the support address.
  ///
  /// In en, this message translates to:
  /// **'Write to us at {email}'**
  String accountWriteToUs(String email);

  /// Account tab: section header for driving details.
  ///
  /// In en, this message translates to:
  /// **'Driving'**
  String get accountSectionDriving;

  /// Account tab row: gearbox types the driver drives (manual/automatic).
  ///
  /// In en, this message translates to:
  /// **'Cars you drive'**
  String get accountCarsYouDrive;

  /// Account tab row: the driver's licence number.
  ///
  /// In en, this message translates to:
  /// **'Driving licence'**
  String get accountDrivingLicence;

  /// Account tab row: the driver's Aadhaar (masked).
  ///
  /// In en, this message translates to:
  /// **'Aadhaar'**
  String get accountAadhaar;

  /// Masked Aadhaar number showing only its last four digits.
  ///
  /// In en, this message translates to:
  /// **'XXXX XXXX {last4}'**
  String accountAadhaarMasked(String last4);

  /// Account tab row that opens the KYC documents screen.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get accountDocuments;

  /// Account tab: subtitle of the Documents row.
  ///
  /// In en, this message translates to:
  /// **'View or update what you submitted'**
  String get accountDocumentsSubtitle;

  /// Account tab: section header for the bank account earnings are paid to.
  ///
  /// In en, this message translates to:
  /// **'Payouts'**
  String get accountSectionPayouts;

  /// Account tab: shown when the driver has no bank account on file.
  ///
  /// In en, this message translates to:
  /// **'No bank account added'**
  String get accountNoBankAccount;

  /// Account tab: bank account holder name and the account number's last four digits.
  ///
  /// In en, this message translates to:
  /// **'{holder} · •••• {last4}'**
  String accountBankAccount(String holder, String last4);

  /// Account tab: section header for support.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get accountSectionHelp;

  /// Account tab row that opens an email to MOJUD support.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get accountContactSupport;

  /// Account tab badge: KYC cleared.
  ///
  /// In en, this message translates to:
  /// **'Verified driver'**
  String get accountKycVerified;

  /// Account tab badge: KYC sent, waiting on a reviewer.
  ///
  /// In en, this message translates to:
  /// **'Documents under review'**
  String get accountKycSubmitted;

  /// Account tab badge: a reviewer sent the KYC back.
  ///
  /// In en, this message translates to:
  /// **'Documents need attention'**
  String get accountKycRejected;

  /// Account tab badge: KYC steps not all done.
  ///
  /// In en, this message translates to:
  /// **'Documents incomplete'**
  String get accountKycIncomplete;

  /// Account tab badge: a KYC status this app version doesn't know.
  ///
  /// In en, this message translates to:
  /// **'Documents status unknown'**
  String get accountKycUnknown;

  /// Button that deletes the driver's account, and the dialog's confirm action.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountDelete;

  /// Title of the delete-account confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get accountDeleteConfirmTitle;

  /// Body of the delete-account confirmation dialog: what is deleted, what is kept and why.
  ///
  /// In en, this message translates to:
  /// **'We\'ll delete your selfie, identity and licence checks, bank details and phone number, and sign you out on every device.\n\nRecords of rides you drove and payments are kept, without your details, because the law requires us to keep them.\n\nEarnings not yet paid out are still owed to you: MOJUD pays them out, so contact support before you delete if any are due.\n\nThis can\'t be undone.'**
  String get accountDeleteExplanation;

  /// Snackbar when deleting the account failed for an unexpected reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account. Please try again.'**
  String get accountDeleteFailed;

  /// Start screen: one-line pitch under the app name.
  ///
  /// In en, this message translates to:
  /// **'Drive customers in their own car, on your schedule. Get matched with nearby trips the moment you go online.'**
  String get startTagline;

  /// Start screen: the button that begins sign-up / sign-in.
  ///
  /// In en, this message translates to:
  /// **'Start Driving'**
  String get startDriving;

  /// Ride screen title for an open ride the driver hasn't taken yet.
  ///
  /// In en, this message translates to:
  /// **'Ride request'**
  String get rideDetailTitleRequest;

  /// Ride screen title for one of the driver's own rides.
  ///
  /// In en, this message translates to:
  /// **'Ride details'**
  String get rideDetailTitle;

  /// Under an open request whose places are approximate.
  ///
  /// In en, this message translates to:
  /// **'Places show their area for now. The exact address, the car\'s number plate and the customer\'s name and number appear once you accept.'**
  String get rideDetailApproxNote;

  /// Under an open request.
  ///
  /// In en, this message translates to:
  /// **'The customer\'s name and number appear once you accept.'**
  String get rideDetailCustomerAfterAccept;

  /// Ride header note while the driver waits at the pickup.
  ///
  /// In en, this message translates to:
  /// **'At pickup since {time}'**
  String rideDetailAtPickupSince(String time);

  /// Ride header note while the trip is underway.
  ///
  /// In en, this message translates to:
  /// **'Started {time}'**
  String rideDetailStartedAt(String time);

  /// Ride header note on a completed trip.
  ///
  /// In en, this message translates to:
  /// **'Done {when}'**
  String rideDetailDoneAt(String when);

  /// Ride header note on a cancelled trip.
  ///
  /// In en, this message translates to:
  /// **'Cancelled {when}'**
  String rideDetailCancelledAt(String when);

  /// Under the ride's start time: how long it books the driver for, and roughly when they're free.
  ///
  /// In en, this message translates to:
  /// **'{span} · until ~{time}'**
  String rideDetailSpanUntil(String span, String time);

  /// Small text next to the fare when it was estimated from the trip's length. Lower case in English.
  ///
  /// In en, this message translates to:
  /// **'estimated fare'**
  String get rideDetailFareEstimated;

  /// Small text next to the fare. Lower case in English.
  ///
  /// In en, this message translates to:
  /// **'trip fare'**
  String get rideDetailFareTrip;

  /// Ride progress step: the driver took the ride. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get rideDetailStepAccepted;

  /// Ride progress step: the trip is finished. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get rideDetailStepDone;

  /// Section header over the ride's pickup/stops/drop.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get rideDetailRoute;

  /// How far the pickup is from the driver.
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String rideDetailDistanceAway(String distance);

  /// Button: open Google Maps directions to where the trip ends.
  ///
  /// In en, this message translates to:
  /// **'Navigate to drop'**
  String get rideDetailNavigateDrop;

  /// Button: open Google Maps directions to the pickup.
  ///
  /// In en, this message translates to:
  /// **'Navigate to pickup'**
  String get rideDetailNavigatePickup;

  /// On a multi-stop ride whose car details aren't known.
  ///
  /// In en, this message translates to:
  /// **'The customer will hand over their car at the pickup.'**
  String get rideDetailCarHandover;

  /// Snackbar when no maps app could be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open Maps on this phone.'**
  String get rideDetailMapsFailed;

  /// Why the customer cancelled. The reason is the customer's own words, not translated.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String rideDetailCancelReason(String reason);

  /// The fee the customer owes for cancelling at the pickup.
  ///
  /// In en, this message translates to:
  /// **'{fee} cancellation fee'**
  String rideDetailCancellationFee(String fee);

  /// Notice title on a completed trip charged for extra time.
  ///
  /// In en, this message translates to:
  /// **'Trip ran past the booked time'**
  String get rideDetailRanOverTitle;

  /// Notice title on a completed trip the customer ended before the booked time.
  ///
  /// In en, this message translates to:
  /// **'Customer ended the trip early'**
  String get rideDetailEndedEarlyTitle;

  /// Note on a trip underway that has run past its booked hours.
  ///
  /// In en, this message translates to:
  /// **'Past the booked time — extra time is charged to the customer by the hour.'**
  String get rideDetailPastBookedTime;

  /// Dialog title before closing a ride as a no-show.
  ///
  /// In en, this message translates to:
  /// **'Customer didn\'t come?'**
  String get rideDetailNoShowDialogTitle;

  /// Dialog body before closing a ride as a no-show.
  ///
  /// In en, this message translates to:
  /// **'This closes the ride as a no-show. The customer is told you waited at the pickup, and it isn\'t counted as you cancelling.'**
  String get rideDetailNoShowDialogBody;

  /// Dialog button: don't close the ride, keep waiting for the customer.
  ///
  /// In en, this message translates to:
  /// **'Keep waiting'**
  String get rideDetailKeepWaiting;

  /// Dialog button: close the ride as a no-show.
  ///
  /// In en, this message translates to:
  /// **'Close ride'**
  String get rideDetailCloseRide;

  /// Snackbar after closing a ride as a no-show.
  ///
  /// In en, this message translates to:
  /// **'Ride closed as a no-show.'**
  String get rideDetailNoShowClosed;

  /// Card title while the driver waits at the pickup.
  ///
  /// In en, this message translates to:
  /// **'Customer not here?'**
  String get rideDetailNoShowTitle;

  /// No-show card: the driver may close the ride now.
  ///
  /// In en, this message translates to:
  /// **'You can close the ride as a no-show.'**
  String get rideDetailNoShowOpen;

  /// No-show card: when the driver may close the ride.
  ///
  /// In en, this message translates to:
  /// **'If they still haven\'t come by {time}, you can close the ride as a no-show.'**
  String rideDetailNoShowFrom(String time);

  /// Button that closes the ride because the customer never came.
  ///
  /// In en, this message translates to:
  /// **'No-show'**
  String get rideDetailNoShowButton;

  /// Note on an active ride while the driver's location is sent to the customer.
  ///
  /// In en, this message translates to:
  /// **'Sharing your live location with the customer'**
  String get rideDetailSharingLocation;

  /// In place of the customer's phone number, which is hidden two hours after the ride.
  ///
  /// In en, this message translates to:
  /// **'Number hidden after the ride'**
  String get rideDetailNumberHidden;

  /// Tooltip of the call button on the customer card.
  ///
  /// In en, this message translates to:
  /// **'Call customer'**
  String get rideDetailCallCustomer;

  /// Snackbar when the dialer couldn't be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start a call.'**
  String get rideDetailCallFailed;

  /// Label over the customer's car type (the driver drives the customer's own car).
  ///
  /// In en, this message translates to:
  /// **'Customer\'s car'**
  String get rideDetailCustomerCar;

  /// Card title on a completed ride the driver hasn't rated.
  ///
  /// In en, this message translates to:
  /// **'Rate your customer'**
  String get rideDetailRateTitle;

  /// Hint in the optional note field of the rating card.
  ///
  /// In en, this message translates to:
  /// **'Add a note for your records (optional)'**
  String get rideDetailRateNoteHint;

  /// Button that sends the driver's rating of the customer.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get rideDetailRateSubmit;

  /// The rating the driver gave the customer.
  ///
  /// In en, this message translates to:
  /// **'You rated {stars}★'**
  String rideDetailYouRated(int stars);

  /// Main button on an open request: take the ride.
  ///
  /// In en, this message translates to:
  /// **'Accept ride'**
  String get rideDetailActionAccept;

  /// Main button on an upcoming ride: the driver has reached the pickup.
  ///
  /// In en, this message translates to:
  /// **'I\'ve arrived at pickup'**
  String get rideDetailActionArrive;

  /// Main button at the pickup, and the start-code dialog's confirm button.
  ///
  /// In en, this message translates to:
  /// **'Start trip'**
  String get rideDetailActionStart;

  /// Main button while the trip is underway.
  ///
  /// In en, this message translates to:
  /// **'Complete trip'**
  String get rideDetailActionComplete;

  /// Secondary button on an open request: hide it.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get rideDetailActionDecline;

  /// Secondary button before the trip starts: give the ride back.
  ///
  /// In en, this message translates to:
  /// **'Can\'t make it'**
  String get rideDetailActionRelease;

  /// Snackbar after accepting a ride.
  ///
  /// In en, this message translates to:
  /// **'Ride accepted — it\'s in your upcoming rides.'**
  String get rideDetailAccepted;

  /// Snackbar after declining an open request.
  ///
  /// In en, this message translates to:
  /// **'Request hidden.'**
  String get rideDetailDeclined;

  /// Snackbar after giving a ride back.
  ///
  /// In en, this message translates to:
  /// **'Ride handed back.'**
  String get rideDetailReleased;

  /// Snackbar after starting the trip.
  ///
  /// In en, this message translates to:
  /// **'Trip started. Drive safe!'**
  String get rideDetailStarted;

  /// Snackbar after Complete when the customer had already ended the trip early.
  ///
  /// In en, this message translates to:
  /// **'The customer ended the trip early. They can now pay {amount} by UPI in their app.'**
  String rideDetailCompletedEndedEarly(String amount);

  /// Snackbar after completing a trip that ran past its booked time.
  ///
  /// In en, this message translates to:
  /// **'Trip complete. It ran past the booked time, so the customer can now pay {charge} by UPI in their app.'**
  String rideDetailCompletedRanOver(String charge);

  /// Snackbar after completing a trip.
  ///
  /// In en, this message translates to:
  /// **'Trip complete. The customer can now pay {amount} by UPI in their app.'**
  String rideDetailCompleted(String amount);

  /// Confirm dialog title before completing a trip.
  ///
  /// In en, this message translates to:
  /// **'Complete the trip?'**
  String get rideDetailConfirmCompleteTitle;

  /// Confirm dialog body before completing a trip.
  ///
  /// In en, this message translates to:
  /// **'Confirm the trip is over and the car is back with the customer.'**
  String get rideDetailConfirmCompleteBody;

  /// Confirm dialog button: complete the trip.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get rideDetailConfirmCompleteYes;

  /// Confirm dialog title before giving a ride back.
  ///
  /// In en, this message translates to:
  /// **'Hand this ride back?'**
  String get rideDetailConfirmReleaseTitle;

  /// Confirm dialog body before giving a ride back.
  ///
  /// In en, this message translates to:
  /// **'It goes back to other drivers nearby, and leaves your list.'**
  String get rideDetailConfirmReleaseBody;

  /// Confirm dialog button: give the ride back.
  ///
  /// In en, this message translates to:
  /// **'Hand back'**
  String get rideDetailConfirmReleaseYes;

  /// Confirm dialog button: do nothing.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get rideDetailNotNow;

  /// Dialog title: the 4-digit code the customer reads out to start the trip.
  ///
  /// In en, this message translates to:
  /// **'Enter start code'**
  String get rideDetailStartCodeTitle;

  /// Start-code dialog body. MOJUD is the brand name.
  ///
  /// In en, this message translates to:
  /// **'Ask the customer for the 4-digit code shown in their MOJUD app.'**
  String get rideDetailStartCodeBody;

  /// Section header of the help card on a ride.
  ///
  /// In en, this message translates to:
  /// **'Help & safety'**
  String get helpTitle;

  /// Button: call India's emergency number 112.
  ///
  /// In en, this message translates to:
  /// **'Call 112'**
  String get helpCall112;

  /// Button: share the trip's details on WhatsApp (e.g. with family).
  ///
  /// In en, this message translates to:
  /// **'Share trip'**
  String get helpShareTrip;

  /// Button: message MOJUD support on WhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get helpContactSupport;

  /// Snackbar when the phone dialer couldn't be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the dialer. Dial 112.'**
  String get helpDialerFailed;

  /// Snackbar when WhatsApp is missing and the trip text was copied instead.
  ///
  /// In en, this message translates to:
  /// **'Trip details copied'**
  String get helpTripCopied;

  /// Snackbar when WhatsApp couldn't be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open WhatsApp on this phone.'**
  String get helpWhatsAppFailed;

  /// First line of the trip text the driver shares (e.g. with family) on WhatsApp.
  ///
  /// In en, this message translates to:
  /// **'I\'m driving a MOJUD trip.'**
  String get helpShareIntro;

  /// Line of the shared trip text.
  ///
  /// In en, this message translates to:
  /// **'When: {when}'**
  String helpShareWhen(String when);

  /// Line of the shared trip text. The place is an address, not translated.
  ///
  /// In en, this message translates to:
  /// **'Pickup: {place}'**
  String helpSharePickup(String place);

  /// Line of the shared trip text: the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'Driver: {name}'**
  String helpShareDriver(String name);

  /// Line of the shared trip text: a short booking id.
  ///
  /// In en, this message translates to:
  /// **'Booking: {id}'**
  String helpShareBooking(String id);

  /// Absolute date and time in the shared trip text (read later, maybe on another day). Translate the weekday and month names only.
  ///
  /// In en, this message translates to:
  /// **'{weekday, select, mon{Mon} tue{Tue} wed{Wed} thu{Thu} fri{Fri} sat{Sat} sun{Sun} other{}}, {day} {month, select, jan{Jan} feb{Feb} mar{Mar} apr{Apr} may{May} jun{Jun} jul{Jul} aug{Aug} sep{Sep} oct{Oct} nov{Nov} dec{Dec} other{}} {year}, {time}'**
  String helpShareDateTime(
    String weekday,
    String day,
    String month,
    String year,
    String time,
  );

  /// Rides tab title.
  ///
  /// In en, this message translates to:
  /// **'My rides'**
  String get ridesPanelTitle;

  /// Rides tab: accepted rides not reached yet. Keep short (4 tabs side by side).
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get ridesPanelTabUpcoming;

  /// Rides tab: at the pickup or driving. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get ridesPanelTabOngoing;

  /// Rides tab: finished trips. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get ridesPanelTabCompleted;

  /// Rides tab: rides the customer cancelled. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get ridesPanelTabCancelled;

  /// Empty Upcoming tab.
  ///
  /// In en, this message translates to:
  /// **'No upcoming rides'**
  String get ridesPanelEmptyUpcomingTitle;

  /// Empty Upcoming tab.
  ///
  /// In en, this message translates to:
  /// **'Rides you accept from the Home tab line up here.'**
  String get ridesPanelEmptyUpcomingBody;

  /// Empty Ongoing tab.
  ///
  /// In en, this message translates to:
  /// **'Nothing underway'**
  String get ridesPanelEmptyOngoingTitle;

  /// Empty Ongoing tab. Refers to the ride screen's "I've arrived at pickup" button.
  ///
  /// In en, this message translates to:
  /// **'Tap \"I\'ve arrived\" on an upcoming ride when you reach the pickup.'**
  String get ridesPanelEmptyOngoingBody;

  /// Empty Completed tab.
  ///
  /// In en, this message translates to:
  /// **'No completed rides yet'**
  String get ridesPanelEmptyCompletedTitle;

  /// Empty Completed tab.
  ///
  /// In en, this message translates to:
  /// **'Finished trips and their fares show up here.'**
  String get ridesPanelEmptyCompletedBody;

  /// Empty Cancelled tab.
  ///
  /// In en, this message translates to:
  /// **'No cancelled rides'**
  String get ridesPanelEmptyCancelledTitle;

  /// Empty Cancelled tab.
  ///
  /// In en, this message translates to:
  /// **'Rides a customer cancels after you accept them show up here.'**
  String get ridesPanelEmptyCancelledBody;

  /// Title when the rides list failed to load; the reason follows.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your rides'**
  String get ridesPanelLoadFailed;

  /// Error when the rating sent was out of range.
  ///
  /// In en, this message translates to:
  /// **'Pick 1 to 5 stars for the customer.'**
  String get myRidesInvalidRating;

  /// Error when the ride can't be rated (not completed, or rated already).
  ///
  /// In en, this message translates to:
  /// **'This ride can\'t be rated right now.'**
  String get myRidesCantRate;

  /// Day label for a ride or payout today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get fmtToday;

  /// Day label for a ride tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get fmtTomorrow;

  /// Day label for a ride or payout yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get fmtYesterday;

  /// Short weekday name used in dates like 'Wed, 28 Oct'.
  ///
  /// In en, this message translates to:
  /// **'{weekday, select, mon{Mon} tue{Tue} wed{Wed} thu{Thu} fri{Fri} sat{Sat} sun{Sun} other{}}'**
  String fmtWeekdayShort(String weekday);

  /// Month name used in dates like 'Wed, 28 Oct'.
  ///
  /// In en, this message translates to:
  /// **'{month, select, jan{Jan} feb{Feb} mar{Mar} apr{Apr} may{May} jun{Jun} jul{Jul} aug{Aug} sep{Sep} oct{Oct} nov{Nov} dec{Dec} other{}}'**
  String fmtMonthShort(String month);

  /// A date further than a day away: weekday, day of month, month. weekday and month come from fmtWeekdayShort / fmtMonthShort.
  ///
  /// In en, this message translates to:
  /// **'{weekday}, {day} {month}'**
  String fmtDate(String weekday, int day, String month);

  /// A duration under an hour.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String fmtMinutes(int minutes);

  /// A duration of whole hours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String fmtHours(int hours);

  /// A duration of hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String fmtHoursMinutes(int hours, int minutes);

  /// A distance under a kilometre, rounded to 50 m.
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String fmtMeters(int meters);

  /// A distance in kilometres (already formatted, e.g. 7.7 or 24).
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String fmtKilometers(String km);

  /// Relative time: less than a minute away.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get fmtNow;

  /// Relative time in the past, e.g. '25 min ago'.
  ///
  /// In en, this message translates to:
  /// **'{duration} ago'**
  String fmtTimeAgo(String duration);

  /// Relative time in the future, e.g. 'in 25 min'.
  ///
  /// In en, this message translates to:
  /// **'in {duration}'**
  String fmtTimeIn(String duration);

  /// What a round trip books the driver for: hired by the hour.
  ///
  /// In en, this message translates to:
  /// **'{hours} h hire'**
  String fmtSpanHire(int hours);

  /// What a one-way trip books the driver for: the predicted drive time.
  ///
  /// In en, this message translates to:
  /// **'~{duration} drive'**
  String fmtSpanDrive(String duration);

  /// What a multi-stop trip books the driver for: number of stops and the booked span.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop} other{{count} stops}} · {duration}'**
  String fmtSpanStops(int count, String duration);

  /// The customer paid; the driver's share after MOJUD's commission.
  ///
  /// In en, this message translates to:
  /// **'Paid · your share {share} after commission'**
  String fmtPaidYourShare(String share);

  /// Fee the customer pays for cancelling after the driver reached the pickup.
  ///
  /// In en, this message translates to:
  /// **'{fee} cancellation fee'**
  String fmtCancellationFee(String fee);

  /// The customer ended the trip early and is charged only for the time used.
  ///
  /// In en, this message translates to:
  /// **'Charged {fare} for the time used (booked {booked})'**
  String fmtEndedEarlyCharge(String fare, String booked);

  /// The trip ran past its booked time; the customer pays for the time used.
  ///
  /// In en, this message translates to:
  /// **'{fare} for the time used (booked {booked})'**
  String fmtRanOverCharge(String fare, String booked);

  /// A customer no driver has rated yet.
  ///
  /// In en, this message translates to:
  /// **'New customer'**
  String get fmtNewCustomer;

  /// The customer's average rating from drivers and how many ratings it's from.
  ///
  /// In en, this message translates to:
  /// **'★ {rating} · {count, plural, =1{1 rating} other{{count} ratings}}'**
  String fmtCustomerRating(String rating, int count);

  /// Earnings tab: the driver has no ratings from customers yet.
  ///
  /// In en, this message translates to:
  /// **'No ratings yet'**
  String get fmtNoRatingsYet;

  /// Earnings tab: the driver's average rating from customers.
  ///
  /// In en, this message translates to:
  /// **'Your rating ★ {rating} from {count, plural, =1{1 trip} other{{count} trips}}'**
  String fmtDriverRating(String rating, int count);

  /// Route timeline caption under the pickup place.
  ///
  /// In en, this message translates to:
  /// **'Pickup · {time}'**
  String ridesPickupAt(String time);

  /// Compact route timeline: the final stop of a multi-stop trip.
  ///
  /// In en, this message translates to:
  /// **'Last of {count} stops'**
  String ridesLastOfStops(int count);

  /// Route timeline caption: the stop's position on the route.
  ///
  /// In en, this message translates to:
  /// **'Stop {number}'**
  String ridesStopNumber(int number);

  /// Route timeline: when the driver should leave this stop.
  ///
  /// In en, this message translates to:
  /// **'leave by {time}'**
  String ridesLeaveBy(String time);

  /// Route timeline caption under a one-way trip's destination: the expected arrival time.
  ///
  /// In en, this message translates to:
  /// **'Drop · ~{time}'**
  String ridesDropAt(String time);

  /// Route timeline caption: a round trip ends back at the pickup around this time.
  ///
  /// In en, this message translates to:
  /// **'Back at pickup · ~{time}'**
  String ridesBackAtPickup(String time);

  /// Route timeline: an open request without its address yet.
  ///
  /// In en, this message translates to:
  /// **'Exact place after you accept'**
  String get ridesExactPlaceAfterAccept;

  /// Under a fare the server estimated from the trip's length.
  ///
  /// In en, this message translates to:
  /// **'estimate'**
  String get ridesFareEstimate;

  /// How far the pickup is from the driver.
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String ridesDistanceAway(String distance);

  /// On an open request: the full address, number plate and customer come once the driver takes the ride.
  ///
  /// In en, this message translates to:
  /// **'Exact address after you accept'**
  String get ridesExactAddressAfterAccept;

  /// Ride card note; charge is fmtEndedEarlyCharge.
  ///
  /// In en, this message translates to:
  /// **'Customer ended the trip early · {charge}'**
  String ridesEndedEarlyNote(String charge);

  /// Ride card note; charge is fmtRanOverCharge.
  ///
  /// In en, this message translates to:
  /// **'Trip ran past the booked time · {charge}'**
  String ridesRanOverNote(String charge);

  /// Earnings tab app bar title.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get earningsTitle;

  /// Earnings tab: heading of today's total.
  ///
  /// In en, this message translates to:
  /// **'Today\'s earnings'**
  String get earningsToday;

  /// Earnings tab: trips completed today.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trip completed} other{{count} trips completed}}'**
  String earningsTripsCompleted(int count);

  /// Earnings tab: the driver's share of today's fares after MOJUD's commission.
  ///
  /// In en, this message translates to:
  /// **'{amount} yours after commission'**
  String earningsYoursAfterCommission(String amount);

  /// Earnings tile label.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get earningsThisWeek;

  /// Earnings tile label.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get earningsThisMonth;

  /// Earnings tile label: since the driver joined.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get earningsAllTime;

  /// A number of trips.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trip} other{{count} trips}}'**
  String earningsTrips(int count);

  /// Earnings tile: the driver's share of the window's fares.
  ///
  /// In en, this message translates to:
  /// **'{amount} yours'**
  String earningsYours(String amount);

  /// Money card row: completed trips the customers haven't paid for yet.
  ///
  /// In en, this message translates to:
  /// **'Waiting for customers to pay'**
  String get earningsAwaitingCustomers;

  /// Money card row: customers paid MOJUD; the driver's share isn't in their bank yet.
  ///
  /// In en, this message translates to:
  /// **'Due to you'**
  String get earningsDueToYou;

  /// Money card row detail under 'Due to you'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trip} other{{count} trips}} · paid to your bank weekly'**
  String earningsDueDetail(int count);

  /// Money card row: what MOJUD has transferred to the driver's bank.
  ///
  /// In en, this message translates to:
  /// **'Paid to your bank'**
  String get earningsPaidToBank;

  /// No bank transfer to the driver yet.
  ///
  /// In en, this message translates to:
  /// **'No payouts yet'**
  String get earningsNoPayoutsYet;

  /// Money card: when the last bank transfer was made.
  ///
  /// In en, this message translates to:
  /// **'Last on {when}'**
  String earningsLastPayout(String when);

  /// Section heading: bank transfers MOJUD made to the driver.
  ///
  /// In en, this message translates to:
  /// **'Payouts'**
  String get earningsPayoutsHeader;

  /// Empty payouts list.
  ///
  /// In en, this message translates to:
  /// **'Each transfer MOJUD makes to your bank is listed here with its reference.'**
  String get earningsNoPayoutsBody;

  /// A payout row: how many trips it covers and when it was made.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trip} other{{count} trips}} · {when}'**
  String earningsPayoutTitle(int count, String when);

  /// A payout's bank reference (UTR), to find it on a bank statement.
  ///
  /// In en, this message translates to:
  /// **'Ref {reference}'**
  String earningsPayoutReference(String reference);

  /// Section heading: the driver's completed trips.
  ///
  /// In en, this message translates to:
  /// **'Completed trips'**
  String get earningsCompletedTrips;

  /// Empty completed-trips list title.
  ///
  /// In en, this message translates to:
  /// **'No trips yet'**
  String get earningsNoTripsTitle;

  /// Empty completed-trips list body.
  ///
  /// In en, this message translates to:
  /// **'Each trip you complete is listed here with its fare.'**
  String get earningsNoTripsBody;

  /// Home tab greeting with the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String dutyHello(String name);

  /// Home tab headline while on duty.
  ///
  /// In en, this message translates to:
  /// **'You\'re on duty'**
  String get dutyOnDutyHeadline;

  /// Home tab headline while off duty.
  ///
  /// In en, this message translates to:
  /// **'Ready to drive?'**
  String get dutyReadyHeadline;

  /// Home tab heading over the driver's next accepted ride.
  ///
  /// In en, this message translates to:
  /// **'Your next ride'**
  String get dutyNextRide;

  /// Home tab heading over the ride underway.
  ///
  /// In en, this message translates to:
  /// **'Ride in progress'**
  String get dutyRideInProgress;

  /// Home tab heading over open rides near the driver.
  ///
  /// In en, this message translates to:
  /// **'Ride requests'**
  String get dutyRideRequests;

  /// Number of open ride requests, beside the heading.
  ///
  /// In en, this message translates to:
  /// **'{count} open'**
  String dutyOpenCount(int count);

  /// Home tab: shown instead of requests while off duty.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get dutyOfflineTitle;

  /// Home tab: shown instead of requests while off duty.
  ///
  /// In en, this message translates to:
  /// **'Go on duty to see rides booked near you.'**
  String get dutyOfflineBody;

  /// Home tab: the request feed failed to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load requests'**
  String get dutyRequestsErrorTitle;

  /// Home tab: on duty, no open rides nearby.
  ///
  /// In en, this message translates to:
  /// **'No requests right now'**
  String get dutyNoRequestsTitle;

  /// Home tab: on duty, no open rides nearby.
  ///
  /// In en, this message translates to:
  /// **'New bookings near you show up here. We check every {seconds} seconds while you\'re on duty.'**
  String dutyNoRequestsBody(int seconds);

  /// Home tab: the app doesn't have the driver's position, so requests show without distances.
  ///
  /// In en, this message translates to:
  /// **'Turn on location to see how far each pickup is. Showing all open rides.'**
  String get dutyLocationOffNote;

  /// Snackbar after the driver takes a ride.
  ///
  /// In en, this message translates to:
  /// **'Ride accepted for {when}.'**
  String dutyRideAccepted(String when);

  /// App bar pill: the driver is on duty.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get dutyOnline;

  /// App bar pill: the driver is off duty.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get dutyOffline;

  /// Duty card title while on duty; also the switch's accessibility label.
  ///
  /// In en, this message translates to:
  /// **'On duty'**
  String get dutyOnDuty;

  /// Duty card title while off duty.
  ///
  /// In en, this message translates to:
  /// **'Off duty'**
  String get dutyOffDuty;

  /// Duty card subtitle while on duty.
  ///
  /// In en, this message translates to:
  /// **'Getting ride requests near you'**
  String get dutyGettingRequests;

  /// Duty card subtitle while off duty.
  ///
  /// In en, this message translates to:
  /// **'Tap to start getting ride requests'**
  String get dutyTapToStart;

  /// Home tab strip: today's earnings.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dutyStripToday;

  /// Home tab strip: trips completed today.
  ///
  /// In en, this message translates to:
  /// **'Trips today'**
  String get dutyStripTripsToday;

  /// Home tab strip: rides the driver holds (upcoming and underway).
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get dutyStripBooked;

  /// Button under a ride request: hide it, don't take it.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get dutyDecline;

  /// Button under a ride request: take the ride.
  ///
  /// In en, this message translates to:
  /// **'Accept ride'**
  String get dutyAcceptRide;

  /// Bottom navigation tab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeNavHome;

  /// Bottom navigation tab: the driver's own rides.
  ///
  /// In en, this message translates to:
  /// **'Rides'**
  String get homeNavRides;

  /// Bottom navigation tab.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get homeNavEarnings;

  /// Bottom navigation tab.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get homeNavAccount;

  /// Android ongoing notification while live location is shared with the customer.
  ///
  /// In en, this message translates to:
  /// **'Sharing your location'**
  String get locationSharingTitle;

  /// Android ongoing notification body while live location is shared.
  ///
  /// In en, this message translates to:
  /// **'Your customer can see you on the way.'**
  String get locationSharingText;

  /// Android notification channel name (system settings) for live-location sharing.
  ///
  /// In en, this message translates to:
  /// **'Live location'**
  String get locationChannelName;

  /// Document View (KYC gate): button and dialog action that signs the driver out of this phone.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get docViewLogOut;

  /// Document View: title of the log-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get docViewLogOutTitle;

  /// Document View: body of the log-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'You can sign in again with your phone number. The steps you have finished stay saved.'**
  String get docViewLogOutBody;

  /// Document View: headline when the KYC record could not be loaded at all.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your registration'**
  String get docViewLoadFailedTitle;

  /// Document View headline: the driver's KYC is cleared.
  ///
  /// In en, this message translates to:
  /// **'You\'re verified'**
  String get docViewTitleVerified;

  /// Document View headline: a person is checking the driver's details.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get docViewTitleSubmitted;

  /// Document View headline: a reviewer sent the details back.
  ///
  /// In en, this message translates to:
  /// **'Some details need fixing'**
  String get docViewTitleRejected;

  /// Document View headline: the backend sent a KYC status this app version doesn't know.
  ///
  /// In en, this message translates to:
  /// **'We can\'t show your status'**
  String get docViewTitleUnknown;

  /// Document View headline: KYC steps still to do.
  ///
  /// In en, this message translates to:
  /// **'Complete your registration'**
  String get docViewTitleIncomplete;

  /// Document View subtitle for a verified driver.
  ///
  /// In en, this message translates to:
  /// **'You\'re cleared to take rides. Open any step to see what you sent, or to change it.'**
  String get docViewSubtitleVerified;

  /// Document View subtitle while under review.
  ///
  /// In en, this message translates to:
  /// **'We\'re checking your details. You can go online once they\'re cleared.'**
  String get docViewSubtitleSubmitted;

  /// Document View subtitle after a reviewer sent the details back.
  ///
  /// In en, this message translates to:
  /// **'Fix the details below and submit again.'**
  String get docViewSubtitleRejected;

  /// Document View subtitle for an unknown KYC status.
  ///
  /// In en, this message translates to:
  /// **'Your account has a status this version of the app doesn\'t know, so you can\'t take rides yet.'**
  String get docViewSubtitleUnknown;

  /// Document View subtitle while KYC steps remain. count = number of steps (6).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Finish this step to start accepting rides.} other{Finish these {count} steps to start accepting rides. Each one unlocks once the last is done.}}'**
  String docViewSubtitleIncomplete(int count);

  /// Document View button: re-read the KYC status while waiting on a reviewer.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get docViewCheckAgain;

  /// Document View button while the KYC status is being re-read.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get docViewChecking;

  /// Document View button: send all six finished steps for verification.
  ///
  /// In en, this message translates to:
  /// **'Submit for verification'**
  String get docViewSubmit;

  /// Document View button while the steps are being submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get docViewSubmitting;

  /// KYC status card title once the driver is verified.
  ///
  /// In en, this message translates to:
  /// **'Cleared to drive'**
  String get kycBannerVerifiedTitle;

  /// KYC status card line: the Aadhaar check passed (number not known).
  ///
  /// In en, this message translates to:
  /// **'Aadhaar verified with DigiLocker'**
  String get kycBannerAadhaarVerified;

  /// KYC status card line: the Aadhaar check passed; last4 = last four digits of the Aadhaar number.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar XXXX XXXX {last4} · verified with DigiLocker'**
  String kycBannerAadhaarVerifiedLast4(String last4);

  /// KYC status card line: the driving licence check passed (number not known).
  ///
  /// In en, this message translates to:
  /// **'Driving licence verified'**
  String get kycBannerLicenseVerified;

  /// KYC status card line: the driving licence check passed.
  ///
  /// In en, this message translates to:
  /// **'Driving licence {number} · verified'**
  String kycBannerLicenseVerifiedNumber(String number);

  /// KYC status card line: the bank account check passed; last4 = last four digits of the account.
  ///
  /// In en, this message translates to:
  /// **'Bank account •••• {last4} · verified with your bank'**
  String kycBannerBankVerified(String last4);

  /// KYC status card title while a person reviews the details.
  ///
  /// In en, this message translates to:
  /// **'Waiting on a reviewer'**
  String get kycBannerSubmittedTitle;

  /// KYC status card line: when the details were submitted.
  ///
  /// In en, this message translates to:
  /// **'Sent {date}'**
  String kycBannerSent(String date);

  /// KYC status card title after a reviewer sent the details back.
  ///
  /// In en, this message translates to:
  /// **'Sent back by a reviewer'**
  String get kycBannerRejectedTitle;

  /// KYC status card line when the reviewer left no note.
  ///
  /// In en, this message translates to:
  /// **'Open the steps below to see what to change.'**
  String get kycBannerRejectedHint;

  /// KYC status card title for a status this app version doesn't know.
  ///
  /// In en, this message translates to:
  /// **'Status not recognised'**
  String get kycBannerUnknownTitle;

  /// KYC status card line for an unknown status. Keep the email address as is.
  ///
  /// In en, this message translates to:
  /// **'Update the app, or write to team@mojud.life if this stays.'**
  String get kycBannerUnknownHint;

  /// A date on the verification cards, e.g. 2 Mar 1995. month comes from fmtMonthShort.
  ///
  /// In en, this message translates to:
  /// **'{day} {month} {year}'**
  String docCardDate(String day, String month, String year);

  /// Error: a KYC photo couldn't be stored on the phone.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the photo. Please take it again.'**
  String get docPhotoSaveFailed;

  /// Error: a KYC photo couldn't be read for upload (e.g. the file is gone).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the photo. Please take it again.'**
  String get docPhotoReadFailed;

  /// Permissions KYC step: why the three permissions are needed.
  ///
  /// In en, this message translates to:
  /// **'Turn these on so ride offers reach you even when MOJUD Driver isn\'t the app on screen.'**
  String get permissionsSubtitle;

  /// Permissions step: Android 'display over other apps' permission.
  ///
  /// In en, this message translates to:
  /// **'Display over other apps'**
  String get permissionsOverlayTitle;

  /// Permissions step: what the overlay permission does.
  ///
  /// In en, this message translates to:
  /// **'Shows ride alerts on top of whatever app you\'re using.'**
  String get permissionsOverlaySubtitle;

  /// Permissions step: location access while the app is in the background.
  ///
  /// In en, this message translates to:
  /// **'Background location'**
  String get permissionsLocationTitle;

  /// Permissions step: what background location is used for.
  ///
  /// In en, this message translates to:
  /// **'Streams your GPS to riders and dispatch while online.'**
  String get permissionsLocationSubtitle;

  /// Permissions step: unrestricted battery usage (no battery optimisation).
  ///
  /// In en, this message translates to:
  /// **'Battery usage'**
  String get permissionsBatteryTitle;

  /// Permissions step: why battery usage must be unrestricted.
  ///
  /// In en, this message translates to:
  /// **'Stops the OS from pausing location updates to save power.'**
  String get permissionsBatterySubtitle;

  /// Permissions step: shown for a permission that doesn't exist on this phone (e.g. iPhone).
  ///
  /// In en, this message translates to:
  /// **'Not required on this device'**
  String get permissionsNotRequired;

  /// Permissions step: button that asks the OS for a permission.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get permissionsTurnOn;

  /// Permissions step: button that completes the step.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get permissionsFinish;

  /// Field error: the Aadhaar number is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your Aadhaar number'**
  String get validationAadhaarEmpty;

  /// Field error: the Aadhaar number isn't 12 digits.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 12-digit Aadhaar number'**
  String get validationAadhaarInvalid;

  /// Field error: the driving licence number is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your driving license number'**
  String get validationLicenseEmpty;

  /// Field error: the driving licence number is too short.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid license number'**
  String get validationLicenseInvalid;

  /// Field error: the bank account holder's name is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter the account holder\'s name'**
  String get validationHolderNameEmpty;

  /// Field error: the account holder's name is too short.
  ///
  /// In en, this message translates to:
  /// **'Name is too short'**
  String get validationNameTooShort;

  /// Field error: the bank account number is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your account number'**
  String get validationAccountEmpty;

  /// Field error: the bank account number isn't 9-18 digits.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid account number'**
  String get validationAccountInvalid;

  /// Field error: the confirm-account-number field is empty.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your account number'**
  String get validationAccountConfirmEmpty;

  /// Field error: the two bank account numbers differ.
  ///
  /// In en, this message translates to:
  /// **'Account numbers don\'t match'**
  String get validationAccountMismatch;

  /// Field error: the IFSC code is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter the IFSC code'**
  String get validationIfscEmpty;

  /// Field error: the IFSC code has the wrong format.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid IFSC code'**
  String get validationIfscInvalid;

  /// KYC step 1 screen title: which gearbox(es) the driver can drive.
  ///
  /// In en, this message translates to:
  /// **'Type of vehicle'**
  String get vehicleStepTitle;

  /// KYC step 1 screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'Which gearbox can you drive? This decides which rides you\'re matched with.'**
  String get vehicleStepSubtitle;

  /// Button label while the choice is being saved.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get vehicleStepSaving;

  /// Empty document photo tile: tap to open the camera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of the document'**
  String get photoPickerDefaultLabel;

  /// Under a document photo whose upload failed.
  ///
  /// In en, this message translates to:
  /// **'Upload didn\'t finish — tap to take the photo again.'**
  String get photoPickerUploadFailed;

  /// Document photo tile when the server has the photo but this phone no longer has a copy.
  ///
  /// In en, this message translates to:
  /// **'Photo uploaded'**
  String get photoPickerUploadedNoPreview;

  /// Small badge on a document photo while it uploads.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get photoPickerBadgeUploading;

  /// Small badge on a document photo once uploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get photoPickerBadgeUploaded;

  /// Small badge on a document photo whose upload failed; tapping retakes it.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get photoPickerBadgeRetry;

  /// Small badge on a document photo: tap to take it again.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get photoPickerBadgeRetake;

  /// KYC step 2 screen title.
  ///
  /// In en, this message translates to:
  /// **'Photo and name'**
  String get photoStepTitle;

  /// KYC step 2 screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'A clear selfie and your details, as they appear on your ID.'**
  String get photoStepSubtitle;

  /// Error: the driver tapped Continue without a selfie.
  ///
  /// In en, this message translates to:
  /// **'Take a selfie to continue'**
  String get photoStepSelfieRequired;

  /// Error: no date of birth chosen.
  ///
  /// In en, this message translates to:
  /// **'Select your date of birth'**
  String get photoStepDobRequired;

  /// Error: no gender chosen.
  ///
  /// In en, this message translates to:
  /// **'Select your gender'**
  String get photoStepGenderRequired;

  /// Under the selfie circle while it uploads.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get photoStepSelfieUploading;

  /// Under the selfie circle when its upload failed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed — tap to retry'**
  String get photoStepSelfieUploadFailed;

  /// Under the selfie circle once a selfie is taken.
  ///
  /// In en, this message translates to:
  /// **'Retake selfie'**
  String get photoStepRetakeSelfie;

  /// Under the empty selfie circle.
  ///
  /// In en, this message translates to:
  /// **'Take a selfie'**
  String get photoStepTakeSelfie;

  /// Button under a failed selfie upload: take a fresh selfie instead of retrying.
  ///
  /// In en, this message translates to:
  /// **'Take a new one instead'**
  String get photoStepTakeNewSelfie;

  /// Note under the selfie.
  ///
  /// In en, this message translates to:
  /// **'Customers see this photo when you take their ride.'**
  String get photoStepSelfieShownToCustomers;

  /// Above the name/date of birth/gender once they come from the verified Aadhaar (read-only).
  ///
  /// In en, this message translates to:
  /// **'From your Aadhaar'**
  String get photoStepFromAadhaar;

  /// Label and hint of the full-name field.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get photoStepFullName;

  /// Placeholder of the date-of-birth picker before a date is chosen.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get photoStepDateOfBirth;

  /// Button label while the details are being saved.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get photoStepSaving;

  /// KYC step 3 screen title.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar card'**
  String get aadhaarStepTitle;

  /// KYC step 3 subtitle once verified.
  ///
  /// In en, this message translates to:
  /// **'Your Aadhaar is verified.'**
  String get aadhaarStepVerifiedSubtitle;

  /// KYC step 3 subtitle before verification.
  ///
  /// In en, this message translates to:
  /// **'Enter your Aadhaar number, then sign in to DigiLocker to verify it.'**
  String get aadhaarStepSubtitle;

  /// Error: the DigiLocker page couldn't be opened in the browser.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open DigiLocker. Try again.'**
  String get aadhaarStepOpenFailed;

  /// Error: the driver came back before finishing in DigiLocker.
  ///
  /// In en, this message translates to:
  /// **'Finish the steps in DigiLocker first.'**
  String get aadhaarStepFinishFirst;

  /// Button label while the DigiLocker result is read.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get aadhaarStepChecking;

  /// Button: the driver says they're done in DigiLocker; the app reads the result.
  ///
  /// In en, this message translates to:
  /// **'I\'ve finished in DigiLocker'**
  String get aadhaarStepFinished;

  /// Button label while DigiLocker is being opened.
  ///
  /// In en, this message translates to:
  /// **'Opening DigiLocker…'**
  String get aadhaarStepOpening;

  /// Button that opens DigiLocker to verify the Aadhaar.
  ///
  /// In en, this message translates to:
  /// **'Verify with DigiLocker'**
  String get aadhaarStepVerify;

  /// Heading of the green card showing the verified Aadhaar details.
  ///
  /// In en, this message translates to:
  /// **'Verified with DigiLocker'**
  String get aadhaarStepVerifiedTitle;

  /// Line on the verified Aadhaar card: date of birth.
  ///
  /// In en, this message translates to:
  /// **'Born {date}'**
  String aadhaarStepBorn(String date);

  /// Line on the verified Aadhaar card: the Aadhaar number with all but the last 4 digits hidden. Keep XXXX XXXX as is.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar XXXX XXXX {last4}'**
  String aadhaarStepMasked(String last4);

  /// Label of the Aadhaar number field.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar number'**
  String get aadhaarStepNumberLabel;

  /// Under the Aadhaar field when a number is already saved.
  ///
  /// In en, this message translates to:
  /// **'Saved. Leave this blank unless you need to change it.'**
  String get aadhaarStepSavedHint;

  /// Shown while DigiLocker is open in the browser.
  ///
  /// In en, this message translates to:
  /// **'Finish in DigiLocker, then come back here.'**
  String get aadhaarStepWaiting;

  /// Button that reopens DigiLocker.
  ///
  /// In en, this message translates to:
  /// **'Open DigiLocker again'**
  String get aadhaarStepOpenAgain;

  /// KYC step 4 screen title.
  ///
  /// In en, this message translates to:
  /// **'Driving license'**
  String get licenseStepTitle;

  /// KYC step 4 screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'We check your license number with the transport department.'**
  String get licenseStepSubtitle;

  /// Label of the driving licence number field.
  ///
  /// In en, this message translates to:
  /// **'License number'**
  String get licenseStepNumberLabel;

  /// Hint of the licence number field. Keep the example number as is.
  ///
  /// In en, this message translates to:
  /// **'e.g. MP0920190012345'**
  String get licenseStepNumberHint;

  /// Heading of the green card showing the verified licence details.
  ///
  /// In en, this message translates to:
  /// **'License verified'**
  String get licenseStepVerifiedTitle;

  /// Line on the verified licence card: expiry date.
  ///
  /// In en, this message translates to:
  /// **'Valid till {date}'**
  String licenseStepValidTill(String date);

  /// Line on the verified licence card: the vehicle classes the licence allows (e.g. LMV · MCWG).
  ///
  /// In en, this message translates to:
  /// **'Covers {classes}'**
  String licenseStepCovers(String classes);

  /// Button label while the licence is being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get licenseStepChecking;

  /// Button that checks the licence number.
  ///
  /// In en, this message translates to:
  /// **'Verify license'**
  String get licenseStepVerify;

  /// KYC step 6 screen title.
  ///
  /// In en, this message translates to:
  /// **'Bank details'**
  String get bankStepTitle;

  /// KYC step 6 screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your earnings are paid to this account. We check it with your bank.'**
  String get bankStepSubtitle;

  /// Heading of the green card showing the verified bank account.
  ///
  /// In en, this message translates to:
  /// **'Verified with your bank'**
  String get bankStepVerifiedTitle;

  /// Line on the verified bank card: the account's last 4 digits and IFSC code.
  ///
  /// In en, this message translates to:
  /// **'Account ending {last4} · {ifsc}'**
  String bankStepAccountEnding(String last4, String ifsc);

  /// Label of the account holder name field.
  ///
  /// In en, this message translates to:
  /// **'Account holder name'**
  String get bankStepHolderLabel;

  /// Hint of the account holder name field.
  ///
  /// In en, this message translates to:
  /// **'As it appears on the bank account'**
  String get bankStepHolderHint;

  /// Label and hint of the bank account number field.
  ///
  /// In en, this message translates to:
  /// **'Account number'**
  String get bankStepAccountNumber;

  /// Under the account number field when an account is already saved.
  ///
  /// In en, this message translates to:
  /// **'Currently paying out to the account ending {last4}. Re-enter the number to change it.'**
  String bankStepCurrentAccount(String last4);

  /// Label of the field where the account number is typed a second time.
  ///
  /// In en, this message translates to:
  /// **'Confirm account number'**
  String get bankStepConfirmLabel;

  /// Hint of the confirm-account-number field.
  ///
  /// In en, this message translates to:
  /// **'Re-enter account number'**
  String get bankStepConfirmHint;

  /// Label of the IFSC code field.
  ///
  /// In en, this message translates to:
  /// **'IFSC code'**
  String get bankStepIfscLabel;

  /// Hint of the IFSC field. Keep the example code as is.
  ///
  /// In en, this message translates to:
  /// **'e.g. HDFC0001234'**
  String get bankStepIfscHint;

  /// Button label while the bank checks the account.
  ///
  /// In en, this message translates to:
  /// **'Checking with your bank…'**
  String get bankStepChecking;

  /// Button that saves the bank details (last KYC step).
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get bankStepFinish;

  /// Sign-up step 1 heading: the driver types their mobile number.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get authPhoneTitle;

  /// Sign-up step 1: explains an OTP will be sent by SMS.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text you a one-time code to verify it\'s you.'**
  String get authPhoneSubtitle;

  /// Label above the +91 mobile number field.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get authMobileNumberLabel;

  /// Error under the number field when it's empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get authPhoneRequired;

  /// Error under the number field when it isn't a valid Indian mobile number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit mobile number'**
  String get authPhoneInvalid;

  /// Sign-up step 3 heading.
  ///
  /// In en, this message translates to:
  /// **'What\'s your name?'**
  String get authNameTitle;

  /// Sign-up step 3: customers see this name on their trip.
  ///
  /// In en, this message translates to:
  /// **'This is how riders will see you once you\'re on a trip.'**
  String get authNameSubtitle;

  /// Label and hint of the name field.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullName;

  /// Error under the name field when it's empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get authNameRequired;

  /// Error under the name field when it's one letter.
  ///
  /// In en, this message translates to:
  /// **'Name is too short'**
  String get authNameTooShort;

  /// Button that finishes sign-up.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// Error when the driver tries to sign up without ticking the consent box.
  ///
  /// In en, this message translates to:
  /// **'Agree to the Terms and Privacy Policy to create your account.'**
  String get authConsentRequired;

  /// The server no longer accepts the driver's login; they must sign in again.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Please sign in again.'**
  String get authSessionEnded;

  /// Consent line beside the sign-up checkbox. {terms} and {privacy} become links (consentTerms, consentPrivacy); the rest toggles the box.
  ///
  /// In en, this message translates to:
  /// **'I agree to the {terms} and {privacy}'**
  String consentAgree(String terms, String privacy);

  /// Link text inside consentAgree; opens the Terms page (English).
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get consentTerms;

  /// Link text inside consentAgree; opens the Privacy Policy page (English).
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get consentPrivacy;

  /// Snackbar when no browser could open a legal page.
  ///
  /// In en, this message translates to:
  /// **'Open {address} in a browser'**
  String consentOpenInBrowser(String address);

  /// Sign-up step 2 heading: enter the OTP.
  ///
  /// In en, this message translates to:
  /// **'Verify your number'**
  String get otpTitle;

  /// Sign-up step 2: where the OTP was sent.
  ///
  /// In en, this message translates to:
  /// **'Enter the {length}-digit code sent to {phone}.'**
  String otpSubtitle(int length, String phone);

  /// Label of the OTP field.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get otpFieldLabel;

  /// Button that checks the OTP.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get otpVerify;

  /// Too many wrong codes: this OTP is dead.
  ///
  /// In en, this message translates to:
  /// **'That code is no longer valid. Request a new one to continue.'**
  String get otpInvalidated;

  /// Button that goes back to the number step for a fresh OTP.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get otpStartOver;

  /// Resend cap reached; {time} is a m:ss countdown.
  ///
  /// In en, this message translates to:
  /// **'Too many code requests. Try again in {time}, or start over.'**
  String otpResendLocked(String time);

  /// Before the resend button/countdown.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t get it?'**
  String get otpDidntGetIt;

  /// Button that sends the OTP again.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get otpResend;

  /// Countdown until the OTP can be resent; {time} is m:ss.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {time}'**
  String otpResendIn(String time);

  /// Error under the OTP field when too few digits were typed.
  ///
  /// In en, this message translates to:
  /// **'Enter the {length}-digit code'**
  String otpWrongLength(int length);

  /// Error under the OTP field.
  ///
  /// In en, this message translates to:
  /// **'Code must be digits only'**
  String get otpDigitsOnly;

  /// Full-screen block when this app build is too old. MOJUD Driver is the brand: keep it.
  ///
  /// In en, this message translates to:
  /// **'Update MOJUD Driver'**
  String get updateTitle;

  /// Update screen explanation.
  ///
  /// In en, this message translates to:
  /// **'This version of the app is out of date. Install the latest one to keep getting rides. Your account, documents and earnings are safe.'**
  String get updateBody;

  /// Update screen button: opens the download page.
  ///
  /// In en, this message translates to:
  /// **'Get the latest version'**
  String get updateGetLatest;

  /// Under the update button.
  ///
  /// In en, this message translates to:
  /// **'Download it from {site}'**
  String updateDownloadFrom(String site);

  /// Shown when no browser opened the download page.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open a browser. Copy the link and open it in one: {site}'**
  String updateOpenFailed(String site);

  /// Copies the download link.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get updateCopyLink;

  /// After the download link was copied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get updateLinkCopied;

  /// Android notification channel name, shown in the phone's notification settings.
  ///
  /// In en, this message translates to:
  /// **'Ride requests'**
  String get notifChannelName;

  /// Android notification channel description, shown in the phone's notification settings.
  ///
  /// In en, this message translates to:
  /// **'New rides booked near you while you are on duty.'**
  String get notifChannelDescription;
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

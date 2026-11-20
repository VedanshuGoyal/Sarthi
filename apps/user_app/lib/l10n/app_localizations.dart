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
  /// **'MOJUD'**
  String get appTitle;

  /// Button that dismisses a dialog or sheet without doing anything.
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

  /// Button or tooltip that goes back a step.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Shown when the phone can't reach the backend (no internet, timeout).
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection and try again.'**
  String get errorNoConnection;

  /// Shorter form of errorNoConnection, for a booking or ride action that couldn't reach the backend.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server.'**
  String get errorNoConnectionShort;

  /// Shown when the backend's reply can't be read.
  ///
  /// In en, this message translates to:
  /// **'The server sent an unexpected reply.'**
  String get errorUnexpectedReply;

  /// Fallback error when the backend gives no reason.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// Fallback error for a ride action the backend refused without a reason; status is the HTTP status code.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({status}).'**
  String errorGenericStatus(int status);

  /// Heading of the app-language setting. Bilingual on purpose, so a customer can find it in either language: put the current language first.
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

  /// A date that is today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get fmtToday;

  /// A date that is tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get fmtTomorrow;

  /// A date that was yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get fmtYesterday;

  /// Short weekday name, used inside dates.
  ///
  /// In en, this message translates to:
  /// **'{weekday, select, mon{Mon} tue{Tue} wed{Wed} thu{Thu} fri{Fri} sat{Sat} sun{Sun} other{}}'**
  String fmtWeekdayShort(String weekday);

  /// Short month name, used inside dates.
  ///
  /// In en, this message translates to:
  /// **'{month, select, jan{Jan} feb{Feb} mar{Mar} apr{Apr} may{May} jun{Jun} jul{Jul} aug{Aug} sep{Sep} oct{Oct} nov{Nov} dec{Dec} other{}}'**
  String fmtMonthShort(String month);

  /// A date further than a day away, e.g. Mon, Oct 26. weekday and month come from fmtWeekdayShort / fmtMonthShort.
  ///
  /// In en, this message translates to:
  /// **'{weekday}, {month} {day}'**
  String fmtDate(String weekday, int day, String month);

  /// A date with its year, e.g. a date of birth: 12 Jan 2000. month comes from fmtMonthShort.
  ///
  /// In en, this message translates to:
  /// **'{day} {month} {year}'**
  String fmtDateWithYear(int day, String month, int year);

  /// A day and a time, e.g. Today, 9:30 AM. day is fmtToday/fmtTomorrow/fmtYesterday/fmtDate; time stays like 9:30 AM in every language.
  ///
  /// In en, this message translates to:
  /// **'{day}, {time}'**
  String fmtDayAndTime(String day, String time);

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

  /// On a trip the customer ended early: what they were charged and what they had booked. Amounts are like ₹320.
  ///
  /// In en, this message translates to:
  /// **'Charged {fare} for the time used (booked {booked}).'**
  String fmtEndedEarly(String fare, String booked);

  /// On a trip that ran past its booked hours: what it was charged, for how many hours, and what was booked.
  ///
  /// In en, this message translates to:
  /// **'Ran past the booked time. Charged {fare} for {hours} h (booked {booked}).'**
  String fmtRanOverHours(String fare, int hours, String booked);

  /// As fmtRanOverHours, when the hours used aren't known.
  ///
  /// In en, this message translates to:
  /// **'Ran past the booked time. Charged {fare} (booked {booked}).'**
  String fmtRanOver(String fare, String booked);

  /// Note on the ride screen while a trip is past its booked time.
  ///
  /// In en, this message translates to:
  /// **'You\'re past your booked time. Extra time is charged by the hour.'**
  String get fmtPastBookedTime;

  /// On an upcoming ride while the customer still owes for earlier rides. rides is 'one' when it's all one earlier ride, else 'other'.
  ///
  /// In en, this message translates to:
  /// **'{amount} unpaid from {rides, select, one{an earlier ride} other{earlier rides}} will be added when you pay for this trip.'**
  String fmtCarriedNote(String amount, String rides);

  /// By the Pay button, when the payment also clears what is owed on other rides. rides is 'one' or 'other'.
  ///
  /// In en, this message translates to:
  /// **'Includes {amount} from {rides, select, one{another ride} other{other rides}}.'**
  String fmtCarriedIncluded(String amount, String rides);

  /// On a receipt whose payment also paid other bookings. others is built from fmtOtherRides / fmtRideCount / fmtOtherCancellationFees / fmtCancellationFeeCount, joined with fmtListAnd.
  ///
  /// In en, this message translates to:
  /// **'Paid {amount} together with {others}.'**
  String fmtPaidTogether(String amount, String others);

  /// Part of fmtPaidTogether: other rides paid together with this ride.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 other ride} other{{count} other rides}}'**
  String fmtOtherRides(int count);

  /// Part of fmtPaidTogether: rides paid together with this cancellation fee.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ride} other{{count} rides}}'**
  String fmtRideCount(int count);

  /// Part of fmtPaidTogether: other cancellation fees paid together with this cancellation fee.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 other cancellation fee} other{{count} other cancellation fees}}'**
  String fmtOtherCancellationFees(int count);

  /// Part of fmtPaidTogether: cancellation fees paid together with this ride.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cancellation fee} other{{count} cancellation fees}}'**
  String fmtCancellationFeeCount(int count);

  /// Two items of a list joined by 'and'.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String fmtListAnd(String first, String second);

  /// In place of a driver's rating before anyone has rated them.
  ///
  /// In en, this message translates to:
  /// **'New driver'**
  String get fmtNewDriver;

  /// A driver's average rating and how many ratings it's from. rating is like 4.7.
  ///
  /// In en, this message translates to:
  /// **'★ {rating} · {count, plural, =1{1 rating} other{{count} ratings}}'**
  String fmtDriverRating(String rating, int count);

  /// Trip type: a driver hired by the hour, ending back at the pickup. Same words as the driver app.
  ///
  /// In en, this message translates to:
  /// **'Round Trip'**
  String get tripTypeRoundTrip;

  /// Trip type: pickup to one destination.
  ///
  /// In en, this message translates to:
  /// **'One-Way'**
  String get tripTypeOneWay;

  /// Trip type: a trip with several stops/errands.
  ///
  /// In en, this message translates to:
  /// **'Multi-Stop'**
  String get tripTypeMultiStop;

  /// Ride status pill: booked, no driver has taken it yet.
  ///
  /// In en, this message translates to:
  /// **'Finding a driver'**
  String get bookingStatusRequested;

  /// Ride status pill: a driver has taken the ride.
  ///
  /// In en, this message translates to:
  /// **'Driver assigned'**
  String get bookingStatusAccepted;

  /// Ride status pill: the driver is waiting at the pickup.
  ///
  /// In en, this message translates to:
  /// **'Driver at pickup'**
  String get bookingStatusArrived;

  /// Ride status pill: the trip is underway.
  ///
  /// In en, this message translates to:
  /// **'On trip'**
  String get bookingStatusInProgress;

  /// Ride status pill: the trip is done.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get bookingStatusCompleted;

  /// Ride status pill: the ride was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get bookingStatusCancelled;

  /// Ride status pill: no driver took the ride before it closed.
  ///
  /// In en, this message translates to:
  /// **'No driver found'**
  String get bookingStatusExpired;

  /// Who cancelled: the customer.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by you'**
  String get bookingCancelledByYou;

  /// Who cancelled: the driver.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by your driver'**
  String get bookingCancelledByDriver;

  /// The driver waited at the pickup and the customer never came, so the driver closed the ride.
  ///
  /// In en, this message translates to:
  /// **'Closed as a no-show'**
  String get bookingCancelledNoShow;

  /// Who cancelled and why, on one line. who is bookingCancelledBy…; reason is the reason given (a cancelReason… label, or the customer's own words as typed).
  ///
  /// In en, this message translates to:
  /// **'{who} · {reason}'**
  String bookingCancelledSummary(String who, String reason);

  /// Cancel reason the customer can pick.
  ///
  /// In en, this message translates to:
  /// **'Plans changed'**
  String get cancelReasonPlansChanged;

  /// Cancel reason the customer can pick.
  ///
  /// In en, this message translates to:
  /// **'Booked by mistake'**
  String get cancelReasonBookedByMistake;

  /// Cancel reason the customer can pick.
  ///
  /// In en, this message translates to:
  /// **'Driver asked me to cancel'**
  String get cancelReasonDriverAsked;

  /// Cancel reason the customer can pick.
  ///
  /// In en, this message translates to:
  /// **'Driver is not responding'**
  String get cancelReasonDriverNotResponding;

  /// Cancel reason the customer can pick.
  ///
  /// In en, this message translates to:
  /// **'Found another option'**
  String get cancelReasonFoundAnotherOption;

  /// Cancel reason that lets the customer type their own.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get cancelReasonOther;

  /// Car type.
  ///
  /// In en, this message translates to:
  /// **'Hatchback'**
  String get carTypeHatchback;

  /// Car type.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get carTypeSedan;

  /// Car type.
  ///
  /// In en, this message translates to:
  /// **'SUV'**
  String get carTypeSuv;

  /// Car type: premium/executive car.
  ///
  /// In en, this message translates to:
  /// **'Luxury'**
  String get carTypeLuxury;

  /// Gearbox: automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get transmissionAutomatic;

  /// Gearbox: manual (stick shift).
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get transmissionManual;

  /// Label of the car-type dropdown when adding a car.
  ///
  /// In en, this message translates to:
  /// **'Car type'**
  String get carOptionsCarType;

  /// Hint in the car-type dropdown before one is picked.
  ///
  /// In en, this message translates to:
  /// **'Select car type'**
  String get carOptionsSelectCarType;

  /// Label of the gearbox dropdown when adding a car.
  ///
  /// In en, this message translates to:
  /// **'Transmission'**
  String get carOptionsTransmission;

  /// How a ride was paid: UPI. Keep 'UPI'.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get paymentModeUpi;

  /// How a ride was paid: cash, settled by MOJUD by hand.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentModeCash;

  /// How a ride was paid: MOJUD waived the charge.
  ///
  /// In en, this message translates to:
  /// **'Waived by MOJUD'**
  String get paymentModeWaived;

  /// Receipt line for another ride paid in the same payment, when the server sent no label.
  ///
  /// In en, this message translates to:
  /// **'Ride'**
  String get paymentLineRide;

  /// Receipt line for a cancellation fee paid in the same payment, when the server sent no label.
  ///
  /// In en, this message translates to:
  /// **'Cancellation fee'**
  String get paymentLineCancellationFee;

  /// Sign-in step 1 title.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get authPhoneTitle;

  /// Sign-in step 1 subtitle: an OTP will be sent by SMS.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text you a one-time code to verify it\'s you.'**
  String get authPhoneSubtitle;

  /// Label of the mobile-number field, and of the number on the Account tab.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get authMobileNumberLabel;

  /// Headline of the welcome band on the first sign-in screen: MOJUD sends a driver for the customer's own car.
  ///
  /// In en, this message translates to:
  /// **'Your car, our driver.'**
  String get authBrandTagline;

  /// Line under authBrandTagline.
  ///
  /// In en, this message translates to:
  /// **'Book a driver for your own car, whenever you need one.'**
  String get authBrandBody;

  /// Chip on the welcome band: a driver hired by the hour (round trip).
  ///
  /// In en, this message translates to:
  /// **'By the hour'**
  String get authServiceByTheHour;

  /// Chip on the welcome band: a one-way trip.
  ///
  /// In en, this message translates to:
  /// **'One-way'**
  String get authServiceOneWay;

  /// Chip on the welcome band: a trip with several stops.
  ///
  /// In en, this message translates to:
  /// **'Multi-stop'**
  String get authServiceMultiStop;

  /// Validation: the mobile number is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get authPhoneRequired;

  /// Validation: not a 10-digit Indian mobile number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit mobile number'**
  String get authPhoneInvalid;

  /// Validation: the name is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get authNameRequired;

  /// Validation: the name is one letter.
  ///
  /// In en, this message translates to:
  /// **'Name is too short'**
  String get authNameTooShort;

  /// Validation: the email is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authEmailRequired;

  /// Validation: the email isn't a well-formed address.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get authEmailInvalid;

  /// Title of the date-of-birth calendar, and the validation message when no date is picked.
  ///
  /// In en, this message translates to:
  /// **'Select your date of birth'**
  String get authDobSelect;

  /// Validation: the date of birth is today or later.
  ///
  /// In en, this message translates to:
  /// **'Date of birth can\'t be in the future'**
  String get authDobInFuture;

  /// Validation: the customer is younger than the minimum age.
  ///
  /// In en, this message translates to:
  /// **'You must be at least {age} years old'**
  String authDobTooYoung(int age);

  /// Shown when the customer tries to create an account without ticking the consent box.
  ///
  /// In en, this message translates to:
  /// **'Please agree to the Terms and Privacy Policy to continue.'**
  String get authConsentRequired;

  /// The server no longer accepts the customer's session; they are signed out.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get authSessionExpired;

  /// Sign-in step 3 title, for a new customer.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get authProfileTitle;

  /// Sign-in step 3 subtitle.
  ///
  /// In en, this message translates to:
  /// **'Just a couple of details to finish setting up your account.'**
  String get authProfileSubtitle;

  /// Label and hint of the name field.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullName;

  /// Label and hint of the email field, and of the email on the Account tab.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// Label and hint of the date-of-birth field, and of the date on the Account tab.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get authDateOfBirth;

  /// Button that finishes sign-up.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// Consent line beside the sign-up checkbox. {terms} and {privacy} become links (consentTerms, consentPrivacy).
  ///
  /// In en, this message translates to:
  /// **'I agree to the {terms} and {privacy}'**
  String consentAgree(String terms, String privacy);

  /// Link to the Terms of Service inside consentAgree.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get consentTerms;

  /// Link to the Privacy Policy inside consentAgree.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get consentPrivacy;

  /// Sign-in step 2 title.
  ///
  /// In en, this message translates to:
  /// **'Verify your number'**
  String get otpTitle;

  /// Sign-in step 2: where the OTP was sent.
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

  /// Too many wrong codes: the OTP is dead.
  ///
  /// In en, this message translates to:
  /// **'That code is no longer valid. Request a new one to continue.'**
  String get otpInvalidated;

  /// Button back to the phone step for a fresh code.
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

  /// Resend cooldown; {time} is a m:ss countdown.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {time}'**
  String otpResendIn(String time);

  /// Validation: the OTP has the wrong number of digits.
  ///
  /// In en, this message translates to:
  /// **'Enter the {length}-digit code'**
  String otpWrongLength(int length);

  /// Validation: the OTP has a non-digit.
  ///
  /// In en, this message translates to:
  /// **'Code must be digits only'**
  String get otpDigitsOnly;

  /// Bottom tab: book a driver.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeNavHome;

  /// Bottom tab: the customer's upcoming and past rides.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get homeNavActivity;

  /// Bottom tab: profile, saved cars, language, log out.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get homeNavAccount;

  /// Snack bar after the customer rates a finished trip.
  ///
  /// In en, this message translates to:
  /// **'Thanks for rating your trip.'**
  String get shellThanksForRating;

  /// Title of the Account tab.
  ///
  /// In en, this message translates to:
  /// **'Your profile'**
  String get accountYourProfile;

  /// Button that signs out on this phone.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get accountLogOut;

  /// Button (and the dialog's confirm button) that deletes the customer's account.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountDelete;

  /// The delete button while the request runs.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account…'**
  String get accountDeleting;

  /// Title of the delete-account confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get accountDeleteConfirmTitle;

  /// Body of the delete-account confirmation: what is deleted and what MOJUD must keep.
  ///
  /// In en, this message translates to:
  /// **'We\'ll remove your name, email, phone number, saved cars and recent pickups, and sign you out on every device. Records of past rides and payments are kept, without your details, because the law requires us to keep them. This can\'t be undone.'**
  String get accountDeleteExplanation;

  /// Deleting the account failed without a reason from the server.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account. Please try again.'**
  String get accountDeleteFailed;

  /// Heading of the saved-cars block on the Account tab.
  ///
  /// In en, this message translates to:
  /// **'My cars'**
  String get carsMyCars;

  /// While the saved cars load in a booking step.
  ///
  /// In en, this message translates to:
  /// **'Loading your cars…'**
  String get carsLoading;

  /// The saved cars failed to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your cars.'**
  String get carsLoadFailed;

  /// Button that loads the saved cars again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get carsRetry;

  /// In place of the saved cars when there are none.
  ///
  /// In en, this message translates to:
  /// **'No saved cars yet — add yours once and pick it on every trip.'**
  String get carsNoneYet;

  /// Tooltip of the delete button on a saved car.
  ///
  /// In en, this message translates to:
  /// **'Remove car'**
  String get carsRemove;

  /// Button that opens the add-car sheet, and the sheet's title.
  ///
  /// In en, this message translates to:
  /// **'Add a car'**
  String get carsAdd;

  /// Label of the saved-car dropdown in a booking step.
  ///
  /// In en, this message translates to:
  /// **'Your car'**
  String get carsYourCar;

  /// Hint in the saved-car dropdown before one is picked.
  ///
  /// In en, this message translates to:
  /// **'Select your car'**
  String get carsSelectYourCar;

  /// Under the add-car sheet's title.
  ///
  /// In en, this message translates to:
  /// **'Saved once, offered on every booking.'**
  String get carsAddSubtitle;

  /// Label of the car's number-plate field.
  ///
  /// In en, this message translates to:
  /// **'Registration number'**
  String get carsRegistrationLabel;

  /// Example number plate in the field; keep the plate itself as is.
  ///
  /// In en, this message translates to:
  /// **'e.g. KA 01 AB 1234'**
  String get carsRegistrationHint;

  /// Validation: the number plate is too short or too long.
  ///
  /// In en, this message translates to:
  /// **'Enter the full registration number.'**
  String get carsRegistrationIncomplete;

  /// The save button while the car is being saved.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get carsSaving;

  /// Button that saves the new car.
  ///
  /// In en, this message translates to:
  /// **'Save car'**
  String get carsSave;

  /// Saving the car failed without a reason from the server.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the car. Try again.'**
  String get carsSaveFailed;

  /// The server's reply to saving a car couldn't be read.
  ///
  /// In en, this message translates to:
  /// **'Unexpected response from the server.'**
  String get carsUnexpectedResponse;

  /// A saved-cars request failed without a reason from the server; status is the HTTP status code.
  ///
  /// In en, this message translates to:
  /// **'Saved-cars request failed ({status}).'**
  String carsRequestFailed(int status);

  /// Title of the screen shown when this app version is no longer served.
  ///
  /// In en, this message translates to:
  /// **'Update MOJUD'**
  String get updateTitle;

  /// Body of the update-required screen.
  ///
  /// In en, this message translates to:
  /// **'This version of the app is out of date. Install the latest one to keep booking drivers. Your account and rides are safe.'**
  String get updateBody;

  /// Button that opens the download page.
  ///
  /// In en, this message translates to:
  /// **'Get the latest version'**
  String get updateGetLatest;

  /// Under the button: where the app is downloaded from.
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

  /// The download link was copied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get updateLinkCopied;

  /// Name of the notification channel, shown in the phone's notification settings.
  ///
  /// In en, this message translates to:
  /// **'Ride updates'**
  String get notifChannelName;

  /// Description of the notification channel, shown in the phone's notification settings.
  ///
  /// In en, this message translates to:
  /// **'Your driver is assigned, and other changes to your rides.'**
  String get notifChannelDescription;

  /// Tooltip of the avatar button on Home that opens the Account tab.
  ///
  /// In en, this message translates to:
  /// **'Your profile'**
  String get homeYourProfile;

  /// Greeting on Home. name is the customer's first name.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String homeHello(String name);

  /// Big heading on Home, under the greeting.
  ///
  /// In en, this message translates to:
  /// **'Where should we drive you today?'**
  String get homeWhereTo;

  /// Heading above the trip type cards on Home.
  ///
  /// In en, this message translates to:
  /// **'Book a driver'**
  String get homeBookADriver;

  /// Title of the 'how it works' card on Home: the service promise.
  ///
  /// In en, this message translates to:
  /// **'Your car, our driver'**
  String get homeHowTitle;

  /// Body of the 'how it works' card on Home.
  ///
  /// In en, this message translates to:
  /// **'A driver comes to your pickup and drives your own car.'**
  String get homeHowBody;

  /// Step 1 of 3 in the 'how it works' card, under an icon. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Pick a trip'**
  String get homeHowStepPick;

  /// Step 2 of 3 in the 'how it works' card, under an icon. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Set pickup & time'**
  String get homeHowStepSet;

  /// Step 3 of 3 in the 'how it works' card, under an icon. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Driver drives your car'**
  String get homeHowStepDrive;

  /// Snackbar when the server refuses a booking because a cancellation fee is unpaid. fee is like ₹50.
  ///
  /// In en, this message translates to:
  /// **'Pay the {fee} cancellation fee for your last ride before booking another.'**
  String homePayFeeBeforeBooking(String fee);

  /// Snackbar action that opens the unpaid ride, where its Pay button is.
  ///
  /// In en, this message translates to:
  /// **'Pay now'**
  String get homePayNow;

  /// Snackbar action that sends a booking that failed again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get homeRetry;

  /// Snackbar when a Round Trip booking failed. reason is the server's or the app's explanation, as sent.
  ///
  /// In en, this message translates to:
  /// **'Your Round Trip wasn\'t booked. {reason}'**
  String homeNotBookedRoundTrip(String reason);

  /// Snackbar when a Multi-Stop booking failed. reason is the server's or the app's explanation, as sent.
  ///
  /// In en, this message translates to:
  /// **'Your Multi-Stop trip wasn\'t booked. {reason}'**
  String homeNotBookedMultiStop(String reason);

  /// Snackbar when a One-Way booking failed. reason is the server's or the app's explanation, as sent.
  ///
  /// In en, this message translates to:
  /// **'Your One-Way Trip wasn\'t booked. {reason}'**
  String homeNotBookedOneWay(String reason);

  /// Snackbar once a Round Trip is booked. car is the car's registration number, e.g. DL01AB1234.
  ///
  /// In en, this message translates to:
  /// **'Round Trip booked: {hours, plural, =1{1 hour} other{{hours} hours}}, in your {car}.'**
  String homeBookedRoundTrip(int hours, String car);

  /// Snackbar once a Multi-Stop trip is booked. car is the car's registration number.
  ///
  /// In en, this message translates to:
  /// **'Multi-Stop trip booked: {count, plural, =1{1 stop} other{{count} stops}} planned, in your {car}.'**
  String homeBookedMultiStop(int count, String car);

  /// Snackbar once a One-Way trip is booked: estimated drive time, the car's registration number, and the destination address as the customer picked it.
  ///
  /// In en, this message translates to:
  /// **'One-Way Trip booked: ~{minutes} min, in your {car} to {destination}.'**
  String homeBookedOneWay(int minutes, String car, String destination);

  /// Trip type card on Home: pickup to one destination.
  ///
  /// In en, this message translates to:
  /// **'One-Way Trip'**
  String get tripPickerOneWayTitle;

  /// Under the One-Way Trip card title. Keep short (narrow card).
  ///
  /// In en, this message translates to:
  /// **'Drop at a destination.'**
  String get tripPickerOneWaySubtitle;

  /// Trip type card on Home: a driver hired by the hour, out and back.
  ///
  /// In en, this message translates to:
  /// **'Round Trip'**
  String get tripPickerRoundTripTitle;

  /// Under the Round Trip card title.
  ///
  /// In en, this message translates to:
  /// **'Hire a driver by the hour, out and back.'**
  String get tripPickerRoundTripSubtitle;

  /// Trip type card on Home: one driver for several stops/errands.
  ///
  /// In en, this message translates to:
  /// **'Multi-Stop Trip'**
  String get tripPickerMultiStopTitle;

  /// Under the Multi-Stop Trip card title. Keep short (narrow card).
  ///
  /// In en, this message translates to:
  /// **'Several stops, one driver.'**
  String get tripPickerMultiStopSubtitle;

  /// Placeholder confirmation when the trip chooser is shown without a booking flow (previews). trip is a tripPicker…Title.
  ///
  /// In en, this message translates to:
  /// **'Selected: {trip}'**
  String tripPickerSelected(String trip);

  /// Where a One-Way or Multi-Stop trip starts (where the driver meets the customer). Label of the start row and search field.
  ///
  /// In en, this message translates to:
  /// **'Starting point'**
  String get tripStartStartingPoint;

  /// Title of the screen where the customer picks where a Multi-Stop trip starts.
  ///
  /// In en, this message translates to:
  /// **'Set starting point'**
  String get tripStartSetStartingPoint;

  /// Under the chosen starting point address: what it is, and that tapping changes it.
  ///
  /// In en, this message translates to:
  /// **'Starting point · tap to change'**
  String get tripStartStartingPointTapToChange;

  /// Under the chosen pickup address (Round Trip): what it is, and that tapping changes it.
  ///
  /// In en, this message translates to:
  /// **'Pickup · tap to change'**
  String get tripStartPickupTapToChange;

  /// Under a start/pickup address filled in from the phone's GPS.
  ///
  /// In en, this message translates to:
  /// **'From your current location · tap to change'**
  String get tripStartFromCurrentLocation;

  /// While the phone's GPS position is being found.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get tripStartFindingLocation;

  /// Label of the Round Trip pickup row while the location is being found.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get tripStartPickup;

  /// Start row when GPS couldn't fill it: asks the customer to pick one.
  ///
  /// In en, this message translates to:
  /// **'Choose a starting point'**
  String get tripStartChooseStartingPoint;

  /// Round Trip pickup row when GPS couldn't fill it: asks the customer to pick one.
  ///
  /// In en, this message translates to:
  /// **'Choose a pickup'**
  String get tripStartChoosePickup;

  /// Under tripStartChoose…: the phone's location couldn't be used (no permission, outside the area…).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t use your current location'**
  String get tripStartNoCurrentLocation;

  /// Shown when a picked place (or the phone's location) is outside the area MOJUD serves.
  ///
  /// In en, this message translates to:
  /// **'We\'re only serving Delhi NCR (Delhi, Gurugram, Faridabad, Noida and nearby areas) right now — pick a location within this area.'**
  String get serviceAreaOutside;

  /// Date field placeholder before a date is picked.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get scheduleSelectDate;

  /// Time field placeholder before a time is picked.
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get scheduleSelectTime;

  /// Booking forms, when the chosen start time is too soon for a driver to accept the trip.
  ///
  /// In en, this message translates to:
  /// **'Pick a start at least 45 minutes from now, so a driver can accept it.'**
  String get scheduleTooSoon;

  /// Title of the start-time picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Pick a start time'**
  String get timeSlotTitle;

  /// Under timeSlotTitle: start times are offered on quarter hours only (9:00, 9:15, …).
  ///
  /// In en, this message translates to:
  /// **'Trips start every 15 minutes.'**
  String get timeSlotSubtitle;

  /// Tooltip of the − button of the Round Trip hours stepper.
  ///
  /// In en, this message translates to:
  /// **'Fewer hours'**
  String get hoursFewer;

  /// Tooltip of the + button of the Round Trip hours stepper.
  ///
  /// In en, this message translates to:
  /// **'More hours'**
  String get hoursMore;

  /// The word under the big hours number in the Round Trip stepper.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{hour} other{hours}}'**
  String hoursUnit(int hours);

  /// Quick-pick chip for a Round Trip duration, e.g. 4h.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String hoursChip(int hours);

  /// Above the Round Trip fare before a car is chosen: the fare shown is the lowest it can be.
  ///
  /// In en, this message translates to:
  /// **'Estimated fare from'**
  String get fareSummaryEstimatedFrom;

  /// Above the Round Trip fare once a car is chosen.
  ///
  /// In en, this message translates to:
  /// **'Estimated fare'**
  String get fareSummaryEstimated;

  /// Under fareSummaryEstimated: how many hours the fare covers.
  ///
  /// In en, this message translates to:
  /// **'for {hours, plural, =1{1 hour} other{{hours} hours}}'**
  String fareSummaryForHours(int hours);

  /// App bar title of the Round Trip booking page.
  ///
  /// In en, this message translates to:
  /// **'Trip details'**
  String get roundTripTitle;

  /// Round Trip section heading: how many hours to hire the driver.
  ///
  /// In en, this message translates to:
  /// **'How long?'**
  String get roundTripHowLong;

  /// Under roundTripHowLong.
  ///
  /// In en, this message translates to:
  /// **'Hire a driver by the hour.'**
  String get roundTripHowLongSubtitle;

  /// Round Trip section heading: start date and time.
  ///
  /// In en, this message translates to:
  /// **'When?'**
  String get roundTripWhen;

  /// Under roundTripWhen.
  ///
  /// In en, this message translates to:
  /// **'Pick a start date and time.'**
  String get roundTripWhenSubtitle;

  /// Above the Confirm button while no pickup is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose your pickup to continue.'**
  String get roundTripChoosePickupToContinue;

  /// Round Trip's main button: book it.
  ///
  /// In en, this message translates to:
  /// **'Confirm booking'**
  String get roundTripConfirm;

  /// Title of the dialog explaining why the fare is an estimate (opened from the fare's * marker).
  ///
  /// In en, this message translates to:
  /// **'Estimated fare'**
  String get roundTripFareNoteTitle;

  /// Body of the estimated-fare dialog.
  ///
  /// In en, this message translates to:
  /// **'Prices may vary based on the final pickup or drop location and the time taken. Time past your booked hours is charged by the hour.'**
  String get roundTripFareNoteBody;

  /// Button that closes the estimated-fare dialog.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get roundTripFareNoteOk;

  /// Section heading on the Round Trip and Multi-Stop forms: which of the customer's saved cars the driver drives.
  ///
  /// In en, this message translates to:
  /// **'Which car?'**
  String get bookingDetailsWhichCar;

  /// Under bookingDetailsWhichCar.
  ///
  /// In en, this message translates to:
  /// **'The driver drives your car — pick one.'**
  String get bookingDetailsWhichCarSubtitle;

  /// Above the Confirm button while no car is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose your car to continue.'**
  String get bookingDetailsChooseCarToContinue;

  /// App bar title of the Multi-Stop planner.
  ///
  /// In en, this message translates to:
  /// **'Plan your trip'**
  String get multiStopTitle;

  /// Multi-Stop section heading: when the driver should be at the starting point.
  ///
  /// In en, this message translates to:
  /// **'When do we start?'**
  String get multiStopWhenStart;

  /// Under multiStopWhenStart.
  ///
  /// In en, this message translates to:
  /// **'The driver meets you at the starting point.'**
  String get multiStopWhenStartSubtitle;

  /// Multi-Stop section heading: the list of stops/errands.
  ///
  /// In en, this message translates to:
  /// **'Stops'**
  String get multiStopStops;

  /// Under multiStopStops.
  ///
  /// In en, this message translates to:
  /// **'List each errand in order — where to go, what to do there, and when to move on.'**
  String get multiStopStopsSubtitle;

  /// Button that adds another stop to the plan.
  ///
  /// In en, this message translates to:
  /// **'Add stop'**
  String get multiStopAddStop;

  /// In place of multiStopAddStop (disabled) once the plan has the most stops allowed.
  ///
  /// In en, this message translates to:
  /// **'Up to {max} stops'**
  String multiStopMaxStops(int max);

  /// Multi-Stop's main button: book it.
  ///
  /// In en, this message translates to:
  /// **'Confirm trip'**
  String get multiStopConfirm;

  /// Above the Confirm button once the plan is complete: how many stops, and when the last one is left. date is like Mon, Oct 26; time like 6:30 PM.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop} other{{count} stops}} · wraps up by {date}, {time}'**
  String multiStopSummary(int count, String date, String time);

  /// Above the Confirm button while a stop is missing something.
  ///
  /// In en, this message translates to:
  /// **'Give every stop a location, a task, and a leave-by time to continue.'**
  String get multiStopStopsIncomplete;

  /// Title of the screen where the customer picks where a stop is.
  ///
  /// In en, this message translates to:
  /// **'Set stop location'**
  String get multiStopSetStopLocation;

  /// Search field label on the stop-location screen.
  ///
  /// In en, this message translates to:
  /// **'Stop location'**
  String get multiStopStopLocation;

  /// Error under the first timed stop when its leave-by time isn't after the trip's start.
  ///
  /// In en, this message translates to:
  /// **'Leave-by must be after the start time.'**
  String get multiStopLeaveByAfterStart;

  /// Error under a stop whose leave-by time isn't after the previous timed stop's. stop is that stop's number.
  ///
  /// In en, this message translates to:
  /// **'Leave-by must be after stop {stop}.'**
  String multiStopLeaveByAfterStop(int stop);

  /// Heading of one stop card in the Multi-Stop planner.
  ///
  /// In en, this message translates to:
  /// **'Stop {index}'**
  String stopTitle(int index);

  /// Tooltip of the up-arrow button on a stop card.
  ///
  /// In en, this message translates to:
  /// **'Move stop {index} earlier'**
  String stopMoveEarlier(int index);

  /// Tooltip of the down-arrow button on a stop card.
  ///
  /// In en, this message translates to:
  /// **'Move stop {index} later'**
  String stopMoveLater(int index);

  /// Tooltip of the delete button on a stop card.
  ///
  /// In en, this message translates to:
  /// **'Remove stop {index}'**
  String stopRemove(int index);

  /// Placeholder of a stop's location row before a place is picked.
  ///
  /// In en, this message translates to:
  /// **'Choose location'**
  String get stopChooseLocation;

  /// Label of a stop's task field: the errand, in the customer's words.
  ///
  /// In en, this message translates to:
  /// **'What should the driver do here?'**
  String get stopTaskLabel;

  /// Example inside the empty task field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Pick up the parcel from reception'**
  String get stopTaskHint;

  /// Label above a stop's date/time: when the driver should leave that stop.
  ///
  /// In en, this message translates to:
  /// **'Leave by'**
  String get stopLeaveBy;

  /// Title of the One-Way step where the customer picks the destination.
  ///
  /// In en, this message translates to:
  /// **'Where to?'**
  String get oneWayRouteTitle;

  /// Label of the destination search field on the One-Way route step.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get oneWayRouteField;

  /// One-Way trip details: heading of the start date/time section.
  ///
  /// In en, this message translates to:
  /// **'When?'**
  String get oneWayDetailsWhenTitle;

  /// One-Way trip details: under 'When?'.
  ///
  /// In en, this message translates to:
  /// **'Pick a start date and time.'**
  String get oneWayDetailsWhenSubtitle;

  /// One-Way trip details: heading of the car section (the customer's own car).
  ///
  /// In en, this message translates to:
  /// **'Which car?'**
  String get oneWayDetailsCarTitle;

  /// One-Way trip details: under 'Which car?'. MOJUD drivers drive the customer's own car.
  ///
  /// In en, this message translates to:
  /// **'The driver drives your car — pick one.'**
  String get oneWayDetailsCarSubtitle;

  /// Hint above the disabled Continue button until a car is picked.
  ///
  /// In en, this message translates to:
  /// **'Choose your car to continue.'**
  String get oneWayDetailsChooseCar;

  /// Title of the last One-Way step, before booking.
  ///
  /// In en, this message translates to:
  /// **'Review trip'**
  String get oneWayReviewTitle;

  /// Review step: heading over the chosen start time and car.
  ///
  /// In en, this message translates to:
  /// **'Your plan'**
  String get oneWayReviewPlanTitle;

  /// Review step: under 'Your plan'.
  ///
  /// In en, this message translates to:
  /// **'Go back to change any of these.'**
  String get oneWayReviewPlanSubtitle;

  /// Review step: label of the start date and time line.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get oneWayReviewStarts;

  /// Review step: label of the chosen car line.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get oneWayReviewCar;

  /// Review step: heading of the estimated drive time.
  ///
  /// In en, this message translates to:
  /// **'Trip time'**
  String get oneWayReviewTripTimeTitle;

  /// Review step: under 'Trip time'.
  ///
  /// In en, this message translates to:
  /// **'Estimated for your chosen start time.'**
  String get oneWayReviewTripTimeSubtitle;

  /// Hint above the disabled Confirm button while the drive time loads.
  ///
  /// In en, this message translates to:
  /// **'Checking the trip time…'**
  String get oneWayReviewCheckingTripTime;

  /// Hint above the disabled Confirm button when the drive time couldn't be loaded.
  ///
  /// In en, this message translates to:
  /// **'The trip time is needed to book — retry the estimate above.'**
  String get oneWayReviewTripTimeNeeded;

  /// Shown in the trip-time box while the drive time loads.
  ///
  /// In en, this message translates to:
  /// **'Checking the drive time…'**
  String get oneWayReviewCheckingDriveTime;

  /// The estimated drive time, e.g. About 1 h 30 min. duration comes from fmtMinutes/fmtHours/fmtHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'About {duration}'**
  String oneWayReviewAbout(String duration);

  /// Shown in the trip-time box when the drive time couldn't be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get the trip time.'**
  String get oneWayReviewTripTimeFailed;

  /// Button that asks for the drive time again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get oneWayReviewRetry;

  /// Button that books the One-Way trip.
  ///
  /// In en, this message translates to:
  /// **'Confirm booking'**
  String get oneWayReviewConfirm;

  /// Title of the screen where the customer chooses the pickup place.
  ///
  /// In en, this message translates to:
  /// **'Set pickup'**
  String get pickupTitle;

  /// Label of the pickup search field.
  ///
  /// In en, this message translates to:
  /// **'Pickup location'**
  String get pickupField;

  /// Title of the place picker when choosing where a trip starts.
  ///
  /// In en, this message translates to:
  /// **'Set starting point'**
  String get pickupStartTitle;

  /// Label of the search field when choosing where a trip starts; also the caption on the map pin.
  ///
  /// In en, this message translates to:
  /// **'Starting point'**
  String get pickupStartField;

  /// Hint inside the place search field.
  ///
  /// In en, this message translates to:
  /// **'Search for a place'**
  String get pickupSearchHint;

  /// Row that opens the map to pick a place by moving a pin.
  ///
  /// In en, this message translates to:
  /// **'Select on map'**
  String get pickupSelectOnMap;

  /// Under 'Use my current location': the map opens on the GPS fix so the pin can be nudged.
  ///
  /// In en, this message translates to:
  /// **'Opens the map to adjust the pin'**
  String get pickupMapSubtitle;

  /// Heading over places the customer used before.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get pickupRecent;

  /// Shown on the place picker before anything is typed.
  ///
  /// In en, this message translates to:
  /// **'Search for a place, or use your current location.'**
  String get pickupEmptyWithLocation;

  /// Shown on the destination picker before anything is typed.
  ///
  /// In en, this message translates to:
  /// **'Search for a place, or select it on the map.'**
  String get pickupEmptyWithMap;

  /// A search result came without coordinates, so it can't be used.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t pin that place. Try another result.'**
  String get pickupCantPin;

  /// Row / button that uses the phone's GPS position.
  ///
  /// In en, this message translates to:
  /// **'Use my current location'**
  String get locationUseCurrent;

  /// Title of the map picker while the map isn't showing (loading or failed).
  ///
  /// In en, this message translates to:
  /// **'Pin on map'**
  String get mapPickerTitle;

  /// Caption over the address under the map pin, when picking a pickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup here'**
  String get mapPickerCaption;

  /// Shown on the pin card while the map is being dragged.
  ///
  /// In en, this message translates to:
  /// **'Move the map to place the pin'**
  String get mapPickerMoveHint;

  /// Button that takes the place under the map pin.
  ///
  /// In en, this message translates to:
  /// **'Confirm this location'**
  String get mapPickerConfirm;

  /// Map picker: this build has no Google Maps key.
  ///
  /// In en, this message translates to:
  /// **'The map isn\'t set up yet. Go back and search for your pickup instead.'**
  String get mapPickerNotSetUp;

  /// Map picker on the web: the Google Maps script failed to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the map. Check your connection, or that the Maps API key allows this site.'**
  String get mapPickerLoadFailed;

  /// Route summary: label over the starting address.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get routeFrom;

  /// Route summary: label over the destination address.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get routeTo;

  /// In place of the route map when it can't be shown.
  ///
  /// In en, this message translates to:
  /// **'Map preview unavailable'**
  String get routeMapUnavailable;

  /// Place search / map lookups couldn't reach the server.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the maps service. Check your connection and try again.'**
  String get locationNoConnection;

  /// Place search / map lookups failed on the server.
  ///
  /// In en, this message translates to:
  /// **'The maps service is unavailable right now. Please try again.'**
  String get locationServiceUnavailable;

  /// Place search / map lookups returned something unreadable.
  ///
  /// In en, this message translates to:
  /// **'Unexpected response from the maps service.'**
  String get locationUnexpectedReply;

  /// This build can't estimate drive times for later departures.
  ///
  /// In en, this message translates to:
  /// **'Drive-time estimates are not set up on this build.'**
  String get locationDriveTimeNotSetUp;

  /// The phone's GPS position couldn't be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find your location. Search for your pickup instead.'**
  String get locationNotFound;

  /// The phone's location setting is off.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off. Switch it on to use your current spot.'**
  String get locationTurnedOff;

  /// The customer said no to the location permission prompt.
  ///
  /// In en, this message translates to:
  /// **'Location permission was declined. Search for your pickup instead.'**
  String get locationPermissionDeclined;

  /// Location permission is permanently denied for the app.
  ///
  /// In en, this message translates to:
  /// **'Location is blocked. Enable it in Settings, or search instead.'**
  String get locationBlocked;

  /// Place search refused because the customer's login expired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again to search for places.'**
  String get placesSessionExpired;

  /// Place search isn't configured on the server.
  ///
  /// In en, this message translates to:
  /// **'Map search isn\'t set up yet.'**
  String get placesNotSetUp;

  /// Place search couldn't get access from the server.
  ///
  /// In en, this message translates to:
  /// **'Map search authorization failed. Please try again.'**
  String get placesAuthFailed;

  /// Place search access reply was unreadable.
  ///
  /// In en, this message translates to:
  /// **'Unexpected authorization response.'**
  String get placesAuthUnexpected;

  /// Place search access reply had no access token.
  ///
  /// In en, this message translates to:
  /// **'Authorization response carried no token.'**
  String get placesAuthNoToken;

  /// Stands in for the driver's first name when the server didn't send one; used as the subject of rideIsYourDriver, rideAtYourPickup, rideIsDriving, rideTrackingOnTrip, rideTrackingLocation, rideTrackingAway.
  ///
  /// In en, this message translates to:
  /// **'Your driver'**
  String get rideYourDriver;

  /// Headline once a driver has taken the ride. name is the driver's first name (or rideYourDriver).
  ///
  /// In en, this message translates to:
  /// **'{name} is your driver'**
  String rideIsYourDriver(String name);

  /// The driver has reached the pickup. name is the driver's first name (or rideYourDriver).
  ///
  /// In en, this message translates to:
  /// **'{name} is at your pickup'**
  String rideAtYourPickup(String name);

  /// Under 'On your trip' when the start time isn't known. name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'{name} is driving.'**
  String rideIsDriving(String name);

  /// Title of the ride screen when the ride is no longer in the customer's list.
  ///
  /// In en, this message translates to:
  /// **'Your ride'**
  String get rideDetailsTitleMissing;

  /// Body of the ride screen when the ride is no longer in the customer's list.
  ///
  /// In en, this message translates to:
  /// **'This ride isn\'t in your list any more.'**
  String get rideDetailsNotInList;

  /// Snackbar after cancelling a ride that cost a cancellation fee. fee is like ₹50.
  ///
  /// In en, this message translates to:
  /// **'Your ride is cancelled. Please pay the {fee} fee.'**
  String rideDetailsCancelledPayFee(String fee);

  /// Snackbar after cancelling a ride for free.
  ///
  /// In en, this message translates to:
  /// **'Your ride is cancelled.'**
  String get rideDetailsCancelled;

  /// Snackbar when a cancel failed without a reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cancel the ride.'**
  String get rideDetailsCancelFailed;

  /// Snackbar after the customer ended the trip early.
  ///
  /// In en, this message translates to:
  /// **'Your trip has ended.'**
  String get rideDetailsTripEnded;

  /// Snackbar when ending the trip failed without a reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t end the trip.'**
  String get rideDetailsEndFailed;

  /// Snackbar once a UPI payment is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Payment received. Thank you!'**
  String get rideDetailsPaymentReceived;

  /// Snackbar after the customer rated the driver.
  ///
  /// In en, this message translates to:
  /// **'Thanks for rating your trip.'**
  String get rideDetailsThanksForRating;

  /// Button on the ride screen that opens the cancel sheet.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get rideDetailsCancelRide;

  /// Headline while no driver has taken the ride yet.
  ///
  /// In en, this message translates to:
  /// **'Finding you a driver'**
  String get rideDetailsFindingDriver;

  /// Under rideDetailsFindingDriver.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know as soon as one accepts.'**
  String get rideDetailsFindingDriverDetail;

  /// Under rideIsYourDriver: when the pickup is. when is like 'Today, 9:30 AM'.
  ///
  /// In en, this message translates to:
  /// **'Pickup {when}'**
  String rideDetailsPickupWhen(String when);

  /// Under rideAtYourPickup: tell the driver the start code to begin the trip.
  ///
  /// In en, this message translates to:
  /// **'Share the start code when you meet.'**
  String get rideDetailsShareStartCode;

  /// Headline while the trip is underway.
  ///
  /// In en, this message translates to:
  /// **'On your trip'**
  String get rideDetailsOnYourTrip;

  /// Under rideDetailsOnYourTrip: when the trip started. when is like 'Today, 9:30 AM'.
  ///
  /// In en, this message translates to:
  /// **'Started {when}'**
  String rideDetailsStartedWhen(String when);

  /// Headline of a trip the customer ended before its booked end.
  ///
  /// In en, this message translates to:
  /// **'Trip ended early'**
  String get rideDetailsTripEndedEarly;

  /// Headline of a finished trip.
  ///
  /// In en, this message translates to:
  /// **'Trip completed'**
  String get rideDetailsTripCompleted;

  /// Headline of a cancelled ride.
  ///
  /// In en, this message translates to:
  /// **'Ride cancelled'**
  String get rideDetailsRideCancelled;

  /// Under rideDetailsRideCancelled when the server said neither who cancelled nor why.
  ///
  /// In en, this message translates to:
  /// **'This ride was cancelled.'**
  String get rideDetailsWasCancelled;

  /// Under 'No driver found': the ride closed before any driver took it.
  ///
  /// In en, this message translates to:
  /// **'No driver accepted in time. Please book again.'**
  String get rideDetailsNoDriverDetail;

  /// Heading of the payment card on a ride cancelled after the driver reached the pickup.
  ///
  /// In en, this message translates to:
  /// **'Pay the cancellation fee'**
  String get rideDetailsPayFeeTitle;

  /// Heading of the payment card on a finished trip.
  ///
  /// In en, this message translates to:
  /// **'Pay for your trip'**
  String get rideDetailsPayTripTitle;

  /// Under rideDetailsPayFeeTitle. amount is like ₹50. GPay, PhonePe, Paytm are app names.
  ///
  /// In en, this message translates to:
  /// **'You cancelled after your driver reached the pickup. Pay {amount} with any UPI app: GPay, PhonePe, Paytm or your bank\'s.'**
  String rideDetailsPayFeeSubtitle(String amount);

  /// Under rideDetailsPayTripTitle. amount is like ₹640. GPay, PhonePe, Paytm are app names.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount} with any UPI app: GPay, PhonePe, Paytm or your bank\'s.'**
  String rideDetailsPayTripSubtitle(String amount);

  /// Pay button while the UPI app is open.
  ///
  /// In en, this message translates to:
  /// **'Waiting for UPI…'**
  String get rideDetailsWaitingForUpi;

  /// Pay button. amount is like ₹640.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount} by UPI'**
  String rideDetailsPayByUpi(String amount);

  /// Followed by the stars the customer gave (shown as star icons). Keep the trailing space.
  ///
  /// In en, this message translates to:
  /// **'You rated '**
  String get rideDetailsYouRated;

  /// Heading of the rating card on a finished trip.
  ///
  /// In en, this message translates to:
  /// **'Rate your driver'**
  String get rideDetailsRateDriver;

  /// Under rideDetailsRateDriver when the driver's name isn't known.
  ///
  /// In en, this message translates to:
  /// **'How was your trip?'**
  String get rideDetailsHowWasTrip;

  /// Under rideDetailsRateDriver. name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'How was your trip with {name}?'**
  String rideDetailsHowWasTripWith(String name);

  /// Heading of the card listing pickup, stops and destination.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get rideDetailsRoute;

  /// Under rideDetailsRoute when the stops themselves aren't listed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop planned} other{{count} stops planned}}'**
  String rideDetailsStopsPlanned(int count);

  /// Label of the pickup in the route card.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get rideDetailsRoutePickup;

  /// Label of a stop in the route card.
  ///
  /// In en, this message translates to:
  /// **'Stop {number}'**
  String rideDetailsRouteStop(int number);

  /// Label of the destination (drop) in the route card.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get rideDetailsRouteDestination;

  /// When the driver should move on from a stop. time is like 9:30 AM.
  ///
  /// In en, this message translates to:
  /// **'Leave by {time}'**
  String rideDetailsLeaveBy(String time);

  /// Heading of the card with what was booked.
  ///
  /// In en, this message translates to:
  /// **'Trip details'**
  String get rideDetailsTripDetails;

  /// Row label in Trip details: the kind of trip.
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get rideDetailsInfoTrip;

  /// Row label in Trip details: when the trip starts.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get rideDetailsInfoStarts;

  /// Row label in Trip details: how many hours a round trip is booked for.
  ///
  /// In en, this message translates to:
  /// **'Booked for'**
  String get rideDetailsInfoBookedFor;

  /// Row label in Trip details: about how long the trip will take.
  ///
  /// In en, this message translates to:
  /// **'Est. duration'**
  String get rideDetailsInfoEstDuration;

  /// Row label in Trip details: the customer's car.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get rideDetailsInfoCar;

  /// Row label: the trip's fare (Trip details and the receipt).
  ///
  /// In en, this message translates to:
  /// **'Fare'**
  String get rideFare;

  /// Row label: the fare as booked, on a trip charged for the time actually used.
  ///
  /// In en, this message translates to:
  /// **'Booked fare'**
  String get rideBookedFare;

  /// Row label: the fee for cancelling after the driver reached the pickup.
  ///
  /// In en, this message translates to:
  /// **'Cancellation fee'**
  String get rideCancellationFee;

  /// Heading of the card listing the ride's steps with their times.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get rideDetailsTimeline;

  /// Timeline step: the customer booked the ride.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get rideTimelineBooked;

  /// Timeline step: a driver took the ride.
  ///
  /// In en, this message translates to:
  /// **'Driver assigned'**
  String get rideTimelineDriverAssigned;

  /// Timeline step: the driver reached the pickup.
  ///
  /// In en, this message translates to:
  /// **'Driver arrived'**
  String get rideTimelineDriverArrived;

  /// Timeline step: the trip began.
  ///
  /// In en, this message translates to:
  /// **'Trip started'**
  String get rideTimelineTripStarted;

  /// Timeline step: the customer ended the trip before its booked end.
  ///
  /// In en, this message translates to:
  /// **'Ended early'**
  String get rideTimelineEndedEarly;

  /// Timeline step: the trip finished.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get rideTimelineCompleted;

  /// Under the timeline's last step 'No driver found'.
  ///
  /// In en, this message translates to:
  /// **'No driver accepted in time.'**
  String get rideTimelineNoDriverDetail;

  /// Under the live map when the driver hasn't shared a location lately.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your driver\'s location'**
  String get rideTrackingWaiting;

  /// Under the live map before the first location check.
  ///
  /// In en, this message translates to:
  /// **'Finding your driver\'s location…'**
  String get rideTrackingFinding;

  /// Under the live map while the trip is on. name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'{name} is on your trip'**
  String rideTrackingOnTrip(String name);

  /// Under the live map when the distance to the pickup isn't known. name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s location'**
  String rideTrackingLocation(String name);

  /// Under the live map: how far the driver is from the pickup. distance is rideDistanceMeters / rideDistanceKm.
  ///
  /// In en, this message translates to:
  /// **'{name} is {distance} away'**
  String rideTrackingAway(String name, String distance);

  /// The line under the live map: where the driver is, and how old that is. age is rideAgeJustNow / rideAgeSeconds / rideAgeMinutes / rideAgeHours.
  ///
  /// In en, this message translates to:
  /// **'{where} · updated {age}'**
  String rideTrackingUpdated(String where, String age);

  /// A distance under a kilometre.
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String rideDistanceMeters(int meters);

  /// A distance in kilometres; km is like 2.3 or 14.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String rideDistanceKm(String km);

  /// How old the driver's location is: a few seconds.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get rideAgeJustNow;

  /// How old the driver's location is, in seconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s ago'**
  String rideAgeSeconds(int seconds);

  /// How old the driver's location is, in minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String rideAgeMinutes(int minutes);

  /// How old the driver's location is, in hours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h ago'**
  String rideAgeHours(int hours);

  /// A ride action failed because the server no longer has the ride.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find this ride any more.'**
  String get rideErrorNotFound;

  /// A free cancel was refused because cancelling now costs a fee.
  ///
  /// In en, this message translates to:
  /// **'Cancelling now has a fee. Pull down to refresh, then try again.'**
  String get rideErrorCancelHasFee;

  /// A cancel was refused because the ride moved on.
  ///
  /// In en, this message translates to:
  /// **'This ride has already started or finished, so it can no longer be cancelled.'**
  String get rideErrorCannotCancel;

  /// Ending the trip failed because it isn't on any more.
  ///
  /// In en, this message translates to:
  /// **'This trip isn\'t in progress any more.'**
  String get rideErrorNotInProgress;

  /// A rating was refused because the ride already has one.
  ///
  /// In en, this message translates to:
  /// **'This ride has already been rated.'**
  String get rideErrorAlreadyRated;

  /// A rating was refused as invalid. max is the longest note allowed.
  ///
  /// In en, this message translates to:
  /// **'Pick 1 to 5 stars, and keep the note under {max} characters.'**
  String rideErrorInvalidRating(int max);

  /// Under the Pay button after the UPI app said the payment went through, while the server is checking with the bank.
  ///
  /// In en, this message translates to:
  /// **'We\'re still confirming your payment with the bank. This ride will show as paid in a minute or two.'**
  String get ridePayStillConfirming;

  /// The UPI app said the payment failed.
  ///
  /// In en, this message translates to:
  /// **'The payment didn\'t go through. Please try again.'**
  String get ridePayFailed;

  /// The customer closed the UPI page without paying.
  ///
  /// In en, this message translates to:
  /// **'Payment cancelled.'**
  String get ridePayCancelled;

  /// Payments are switched off on the server.
  ///
  /// In en, this message translates to:
  /// **'Paying in the app isn\'t available yet.'**
  String get ridePayUnavailable;

  /// The ride isn't due for payment.
  ///
  /// In en, this message translates to:
  /// **'This ride can\'t be paid for yet.'**
  String get ridePayNotYet;

  /// Heading of the receipt of a paid ride.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receiptTitle;

  /// Top line of the receipt.
  ///
  /// In en, this message translates to:
  /// **'Paid. Thank you!'**
  String get receiptPaidThanks;

  /// Receipt row: the fare of a trip charged for the time actually used (ended early or ran over).
  ///
  /// In en, this message translates to:
  /// **'Fare for the time used'**
  String get receiptFareForTimeUsed;

  /// Receipt row: the fare before the night surcharge.
  ///
  /// In en, this message translates to:
  /// **'Base fare'**
  String get receiptBaseFare;

  /// Receipt row: the extra charged for driving at night.
  ///
  /// In en, this message translates to:
  /// **'Night surcharge'**
  String get receiptNightSurcharge;

  /// Receipt row: what the whole payment came to, when it also paid other rides.
  ///
  /// In en, this message translates to:
  /// **'Total paid'**
  String get receiptTotalPaid;

  /// Receipt row: how the ride was paid (UPI, Cash, …).
  ///
  /// In en, this message translates to:
  /// **'Paid via'**
  String get receiptPaidVia;

  /// Receipt row: the bank's UTR or the gateway's transaction id, to quote in a dispute.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get receiptReference;

  /// Receipt row: MOJUD's payment order id.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get receiptOrder;

  /// Receipt row: when the payment was made; the value is a day and time.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get receiptPaidAt;

  /// Title of the dialog confirming ending the trip early.
  ///
  /// In en, this message translates to:
  /// **'End trip now?'**
  String get endTripTitle;

  /// End-trip dialog: how ending early is charged.
  ///
  /// In en, this message translates to:
  /// **'You\'ll pay by the hour for the time used. Each started hour counts as a full hour.'**
  String get endTripByTheHour;

  /// End-trip dialog: hours past the booked time are charged after a grace period of minutes.
  ///
  /// In en, this message translates to:
  /// **'If you\'re past your booked time, the extra hours are charged too, after a {minutes}-minute grace.'**
  String endTripOvertime(int minutes);

  /// End-trip dialog: don't end the trip.
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get endTripKeepGoing;

  /// Button that ends the trip early (on the ride screen and in its confirmation dialog).
  ///
  /// In en, this message translates to:
  /// **'End trip now'**
  String get endTripNow;

  /// The code the customer tells the driver at the pickup to start the trip.
  ///
  /// In en, this message translates to:
  /// **'Start code'**
  String get startCodeTitle;

  /// Under startCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Share it with your driver when you meet.'**
  String get startCodeHint;

  /// Screen-reader label: the start code read digit by digit. digits is like '4 8 1 2'.
  ///
  /// In en, this message translates to:
  /// **'Start code {digits}'**
  String startCodeSemantics(String digits);

  /// Tooltip of the button that calls the driver.
  ///
  /// In en, this message translates to:
  /// **'Call driver'**
  String get driverRowCall;

  /// Screen-reader label of the driver's photo.
  ///
  /// In en, this message translates to:
  /// **'Photo of {name}'**
  String driverRowPhotoOf(String name);

  /// Screen-reader label of a read-only star rating.
  ///
  /// In en, this message translates to:
  /// **'{stars} out of 5 stars'**
  String starsOutOfFive(int stars);

  /// Tooltip of each star button when rating.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 star} other{{count} stars}}'**
  String starsCount(int count);

  /// Shown under the stars when 1 star is picked.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get starsWordPoor;

  /// Shown under the stars when 2 stars are picked.
  ///
  /// In en, this message translates to:
  /// **'Not great'**
  String get starsWordNotGreat;

  /// Shown under the stars when 3 stars are picked.
  ///
  /// In en, this message translates to:
  /// **'Okay'**
  String get starsWordOkay;

  /// Shown under the stars when 4 stars are picked.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get starsWordGood;

  /// Shown under the stars when 5 stars are picked.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get starsWordExcellent;

  /// Hint in the rating note field.
  ///
  /// In en, this message translates to:
  /// **'Add a note for your driver (optional)'**
  String get starsNoteHint;

  /// Button that sends the rating.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get starsSubmit;

  /// Map pin title: the pickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get liveMapPickup;

  /// Map pin title: the driver's live position.
  ///
  /// In en, this message translates to:
  /// **'Your driver'**
  String get liveMapYourDriver;

  /// Title of the Activity tab: the customer's upcoming and past rides.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitle;

  /// Activity tab: rides not finished yet.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get activityTabUpcoming;

  /// Activity tab: finished, cancelled or expired rides.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get activityTabCompleted;

  /// Empty Upcoming tab, title.
  ///
  /// In en, this message translates to:
  /// **'No upcoming rides'**
  String get activityNoUpcomingTitle;

  /// Empty Upcoming tab, help line. Home is the app's Home tab.
  ///
  /// In en, this message translates to:
  /// **'Rides you book from Home show up here until they finish.'**
  String get activityNoUpcomingBody;

  /// Empty Completed tab, title.
  ///
  /// In en, this message translates to:
  /// **'No completed rides yet'**
  String get activityNoCompletedTitle;

  /// Empty Completed tab, help line.
  ///
  /// In en, this message translates to:
  /// **'Finished trips and their fares show up here.'**
  String get activityNoCompletedBody;

  /// Title when the rides list couldn't be loaded; the reason is shown under it.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your rides'**
  String get activityLoadFailed;

  /// Rating sheet title when the driver's name isn't known.
  ///
  /// In en, this message translates to:
  /// **'How was your trip?'**
  String get rateTitle;

  /// Rating sheet title; name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'How was your trip with {name}?'**
  String rateTitleWithDriver(String name);

  /// Closes the rating sheet without rating.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get rateNotNow;

  /// On a Multi-Stop ride card: how many stops the trip has.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop} other{{count} stops}}'**
  String rideCardStopCount(int count);

  /// On a completed ride's card when the driver's name isn't known, beside the fare.
  ///
  /// In en, this message translates to:
  /// **'Trip completed'**
  String get rideCardTripCompleted;

  /// On a completed ride's card, beside the fare: who drove.
  ///
  /// In en, this message translates to:
  /// **'Driven by {name}'**
  String rideCardDrivenBy(String name);

  /// On a ride the customer ended early. charge is the sentence fmtEndedEarly (Charged ₹320 for the time used (booked ₹640).).
  ///
  /// In en, this message translates to:
  /// **'Ended early. {charge}'**
  String rideCardEndedEarly(String charge);

  /// On a rated ride's card, followed by the stars given (drawn as stars, not text).
  ///
  /// In en, this message translates to:
  /// **'You rated'**
  String get rideCardYouRated;

  /// Button on an unrated completed ride's card; opens the rating sheet.
  ///
  /// In en, this message translates to:
  /// **'Rate your trip'**
  String get rideCardRateTrip;

  /// On a cancelled ride's card when the server didn't say who cancelled or why.
  ///
  /// In en, this message translates to:
  /// **'This ride was cancelled.'**
  String get rideCardCancelled;

  /// On a ride cancelled at the pickup: the fee's label, beside its amount.
  ///
  /// In en, this message translates to:
  /// **'Cancellation fee'**
  String get rideCardCancellationFee;

  /// On a ride no driver took before it closed.
  ///
  /// In en, this message translates to:
  /// **'No driver accepted in time. Please book again.'**
  String get rideCardNoDriver;

  /// On a ride still looking for a driver.
  ///
  /// In en, this message translates to:
  /// **'We\'ll show your driver here as soon as one accepts.'**
  String get rideCardWaitingForDriver;

  /// Button on a ride (or cancellation fee) still to pay. amount is like ₹640.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount} by UPI'**
  String rideCardPayByUpi(String amount);

  /// Small tag beside the amount of a paid ride. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get rideCardPaid;

  /// Title of the cancel sheet.
  ///
  /// In en, this message translates to:
  /// **'Cancel this ride?'**
  String get cancelSheetTitle;

  /// Cancel sheet, once the driver is at the pickup. name is the driver's first name; fee is like ₹50.
  ///
  /// In en, this message translates to:
  /// **'{name} has reached your pickup, so cancelling now costs {fee}.'**
  String cancelSheetFeeNowNamed(String name, String fee);

  /// As cancelSheetFeeNowNamed when the driver's name isn't known.
  ///
  /// In en, this message translates to:
  /// **'Your driver has reached your pickup, so cancelling now costs {fee}.'**
  String cancelSheetFeeNow(String fee);

  /// Cancel sheet when the driver is at the pickup but no fee applies.
  ///
  /// In en, this message translates to:
  /// **'Cancelling is free.'**
  String get cancelSheetFree;

  /// Cancel sheet before the driver reaches the pickup. fee is like ₹50.
  ///
  /// In en, this message translates to:
  /// **'Cancelling is free until the driver reaches your pickup. After that it costs {fee}.'**
  String cancelSheetFreeUntilPickup(String fee);

  /// Cancel sheet note when cancelling costs a fee. name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'You\'ll pay the fee by UPI, like a ride, before your next booking. {name} will be told you cancelled.'**
  String cancelSheetFeeWarningNamed(String name);

  /// As cancelSheetFeeWarningNamed when the driver's name isn't known.
  ///
  /// In en, this message translates to:
  /// **'You\'ll pay the fee by UPI, like a ride, before your next booking. Your driver will be told you cancelled.'**
  String get cancelSheetFeeWarning;

  /// Cancel sheet note, driver at the pickup, no fee. name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'{name} is already waiting at your pickup. They will be told you cancelled.'**
  String cancelSheetWaitingNamed(String name);

  /// As cancelSheetWaitingNamed when the driver's name isn't known.
  ///
  /// In en, this message translates to:
  /// **'Your driver is already waiting at your pickup. They will be told you cancelled.'**
  String get cancelSheetWaiting;

  /// Cancel sheet note once a driver has taken the ride. name is the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'{name} has accepted this ride and is planning around it. They will be told you cancelled.'**
  String cancelSheetAcceptedNamed(String name);

  /// As cancelSheetAcceptedNamed when the driver's name isn't known.
  ///
  /// In en, this message translates to:
  /// **'Your driver has accepted this ride and is planning around it. They will be told you cancelled.'**
  String get cancelSheetAccepted;

  /// Above the list of cancel reasons.
  ///
  /// In en, this message translates to:
  /// **'Tell us why — it helps us improve.'**
  String get cancelSheetWhy;

  /// Hint in the text field shown for the 'Other' cancel reason.
  ///
  /// In en, this message translates to:
  /// **'Tell us more (optional)'**
  String get cancelSheetTellUsMore;

  /// Confirm button when cancelling costs a fee. fee is like ₹50.
  ///
  /// In en, this message translates to:
  /// **'Cancel and pay {fee}'**
  String cancelSheetCancelAndPay(String fee);

  /// Confirm button when cancelling is free.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get cancelSheetCancelRide;

  /// Closes the cancel sheet without cancelling.
  ///
  /// In en, this message translates to:
  /// **'Keep my ride'**
  String get cancelSheetKeepRide;

  /// Heading of the help & safety buttons on a ride.
  ///
  /// In en, this message translates to:
  /// **'Help & safety'**
  String get helpTitle;

  /// Button: calls 112, India's emergency number.
  ///
  /// In en, this message translates to:
  /// **'Call 112'**
  String get helpCall112;

  /// Button: shares the trip's details with someone (WhatsApp).
  ///
  /// In en, this message translates to:
  /// **'Share trip'**
  String get helpShareTrip;

  /// Button: opens a WhatsApp chat with MOJUD support.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get helpContactSupport;

  /// Snackbar when the phone's dialer couldn't be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the dialer. Dial 112.'**
  String get helpDialerFailed;

  /// Snackbar when WhatsApp isn't there and the trip details were copied instead.
  ///
  /// In en, this message translates to:
  /// **'Trip details copied'**
  String get helpTripCopied;

  /// Snackbar when WhatsApp couldn't be opened to contact support.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open WhatsApp.'**
  String get helpWhatsAppFailed;

  /// First line of the trip details the customer shares with a friend.
  ///
  /// In en, this message translates to:
  /// **'My MOJUD trip'**
  String get helpShareIntro;

  /// Shared trip details: when the trip starts. when is helpShareDateTime.
  ///
  /// In en, this message translates to:
  /// **'When: {when}'**
  String helpShareWhen(String when);

  /// Shared trip details: the pickup address, as entered.
  ///
  /// In en, this message translates to:
  /// **'Pickup: {place}'**
  String helpSharePickup(String place);

  /// Shared trip details: the driver's first name.
  ///
  /// In en, this message translates to:
  /// **'Driver: {name}'**
  String helpShareDriver(String name);

  /// Shared trip details: a short booking id, like 3F2A9C1B.
  ///
  /// In en, this message translates to:
  /// **'Booking: {id}'**
  String helpShareBooking(String id);

  /// When the shared trip starts, absolute (the friend may read it another day), e.g. Wed 18 Nov, 9:30 AM. time stays like 9:30 AM.
  ///
  /// In en, this message translates to:
  /// **'{weekday, select, mon{Mon} tue{Tue} wed{Wed} thu{Thu} fri{Fri} sat{Sat} sun{Sun} other{}} {day} {month, select, jan{Jan} feb{Feb} mar{Mar} apr{Apr} may{May} jun{Jun} jul{Jul} aug{Aug} sep{Sep} oct{Oct} nov{Nov} dec{Dec} other{}}, {time}'**
  String helpShareDateTime(String weekday, int day, String month, String time);

  /// A booking refused because a finished ride is still unpaid.
  ///
  /// In en, this message translates to:
  /// **'Pay for your last ride before booking another.'**
  String get bookingErrorPayLastRide;

  /// The rides list couldn't be loaded; status is the HTTP status code.
  ///
  /// In en, this message translates to:
  /// **'Loading your rides failed ({status}).'**
  String bookingErrorLoadFailed(int status);

  /// A booking the server refused without a reason; status is the HTTP status code.
  ///
  /// In en, this message translates to:
  /// **'Booking request failed ({status}).'**
  String bookingErrorRequestFailed(int status);

  /// The PhonePe payment page couldn't be set up. PhonePe is a brand: keep it.
  ///
  /// In en, this message translates to:
  /// **'PhonePe couldn\'t start.'**
  String get checkoutCouldNotStart;

  /// The PhonePe payment page couldn't be opened.
  ///
  /// In en, this message translates to:
  /// **'PhonePe couldn\'t open.'**
  String get checkoutCouldNotOpen;

  /// Shown on builds (web, desktop) where UPI payment isn't available.
  ///
  /// In en, this message translates to:
  /// **'Paying by UPI works in the Android app.'**
  String get checkoutAndroidOnly;
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

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

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MOJUD';

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
  String get commonBack => 'Back';

  @override
  String get errorNoConnection =>
      'Can\'t reach the server. Check your connection and try again.';

  @override
  String get errorNoConnectionShort => 'Can\'t reach the server.';

  @override
  String get errorUnexpectedReply => 'The server sent an unexpected reply.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String errorGenericStatus(int status) {
    return 'Something went wrong ($status).';
  }

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
  String get fmtToday => 'Today';

  @override
  String get fmtTomorrow => 'Tomorrow';

  @override
  String get fmtYesterday => 'Yesterday';

  @override
  String fmtWeekdayShort(String weekday) {
    String _temp0 = intl.Intl.selectLogic(weekday, {
      'mon': 'Mon',
      'tue': 'Tue',
      'wed': 'Wed',
      'thu': 'Thu',
      'fri': 'Fri',
      'sat': 'Sat',
      'sun': 'Sun',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String fmtMonthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'jan': 'Jan',
      'feb': 'Feb',
      'mar': 'Mar',
      'apr': 'Apr',
      'may': 'May',
      'jun': 'Jun',
      'jul': 'Jul',
      'aug': 'Aug',
      'sep': 'Sep',
      'oct': 'Oct',
      'nov': 'Nov',
      'dec': 'Dec',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String fmtDate(String weekday, int day, String month) {
    return '$weekday, $month $day';
  }

  @override
  String fmtDateWithYear(int day, String month, int year) {
    return '$day $month $year';
  }

  @override
  String fmtDayAndTime(String day, String time) {
    return '$day, $time';
  }

  @override
  String fmtMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String fmtHours(int hours) {
    return '$hours h';
  }

  @override
  String fmtHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String fmtEndedEarly(String fare, String booked) {
    return 'Charged $fare for the time used (booked $booked).';
  }

  @override
  String fmtRanOverHours(String fare, int hours, String booked) {
    return 'Ran past the booked time. Charged $fare for $hours h (booked $booked).';
  }

  @override
  String fmtRanOver(String fare, String booked) {
    return 'Ran past the booked time. Charged $fare (booked $booked).';
  }

  @override
  String get fmtPastBookedTime =>
      'You\'re past your booked time. Extra time is charged by the hour.';

  @override
  String fmtCarriedNote(String amount, String rides) {
    String _temp0 = intl.Intl.selectLogic(rides, {
      'one': 'an earlier ride',
      'other': 'earlier rides',
    });
    return '$amount unpaid from $_temp0 will be added when you pay for this trip.';
  }

  @override
  String fmtCarriedIncluded(String amount, String rides) {
    String _temp0 = intl.Intl.selectLogic(rides, {
      'one': 'another ride',
      'other': 'other rides',
    });
    return 'Includes $amount from $_temp0.';
  }

  @override
  String fmtPaidTogether(String amount, String others) {
    return 'Paid $amount together with $others.';
  }

  @override
  String fmtOtherRides(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count other rides',
      one: '1 other ride',
    );
    return '$_temp0';
  }

  @override
  String fmtRideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rides',
      one: '1 ride',
    );
    return '$_temp0';
  }

  @override
  String fmtOtherCancellationFees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count other cancellation fees',
      one: '1 other cancellation fee',
    );
    return '$_temp0';
  }

  @override
  String fmtCancellationFeeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cancellation fees',
      one: '1 cancellation fee',
    );
    return '$_temp0';
  }

  @override
  String fmtListAnd(String first, String second) {
    return '$first and $second';
  }

  @override
  String get fmtNewDriver => 'New driver';

  @override
  String fmtDriverRating(String rating, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings',
      one: '1 rating',
    );
    return '★ $rating · $_temp0';
  }

  @override
  String get tripTypeRoundTrip => 'Round Trip';

  @override
  String get tripTypeOneWay => 'One-Way';

  @override
  String get tripTypeMultiStop => 'Multi-Stop';

  @override
  String get bookingStatusRequested => 'Finding a driver';

  @override
  String get bookingStatusAccepted => 'Driver assigned';

  @override
  String get bookingStatusArrived => 'Driver at pickup';

  @override
  String get bookingStatusInProgress => 'On trip';

  @override
  String get bookingStatusCompleted => 'Completed';

  @override
  String get bookingStatusCancelled => 'Cancelled';

  @override
  String get bookingStatusExpired => 'No driver found';

  @override
  String get bookingCancelledByYou => 'Cancelled by you';

  @override
  String get bookingCancelledByDriver => 'Cancelled by your driver';

  @override
  String get bookingCancelledNoShow => 'Closed as a no-show';

  @override
  String bookingCancelledSummary(String who, String reason) {
    return '$who · $reason';
  }

  @override
  String get cancelReasonPlansChanged => 'Plans changed';

  @override
  String get cancelReasonBookedByMistake => 'Booked by mistake';

  @override
  String get cancelReasonDriverAsked => 'Driver asked me to cancel';

  @override
  String get cancelReasonDriverNotResponding => 'Driver is not responding';

  @override
  String get cancelReasonFoundAnotherOption => 'Found another option';

  @override
  String get cancelReasonOther => 'Other';

  @override
  String get carTypeHatchback => 'Hatchback';

  @override
  String get carTypeSedan => 'Sedan';

  @override
  String get carTypeSuv => 'SUV';

  @override
  String get carTypeLuxury => 'Luxury';

  @override
  String get transmissionAutomatic => 'Automatic';

  @override
  String get transmissionManual => 'Manual';

  @override
  String get carOptionsCarType => 'Car type';

  @override
  String get carOptionsSelectCarType => 'Select car type';

  @override
  String get carOptionsTransmission => 'Transmission';

  @override
  String get paymentModeUpi => 'UPI';

  @override
  String get paymentModeCash => 'Cash';

  @override
  String get paymentModeWaived => 'Waived by MOJUD';

  @override
  String get paymentLineRide => 'Ride';

  @override
  String get paymentLineCancellationFee => 'Cancellation fee';
}

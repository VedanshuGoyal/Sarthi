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

  @override
  String get authPhoneTitle => 'Enter your mobile number';

  @override
  String get authPhoneSubtitle =>
      'We\'ll text you a one-time code to verify it\'s you.';

  @override
  String get authMobileNumberLabel => 'Mobile number';

  @override
  String get authBrandTagline => 'Your car, our driver.';

  @override
  String get authBrandBody =>
      'Book a driver for your own car, whenever you need one.';

  @override
  String get authServiceByTheHour => 'By the hour';

  @override
  String get authServiceOneWay => 'One-way';

  @override
  String get authServiceMultiStop => 'Multi-stop';

  @override
  String get authPhoneRequired => 'Enter your mobile number';

  @override
  String get authPhoneInvalid => 'Enter a valid 10-digit mobile number';

  @override
  String get authNameRequired => 'Enter your name';

  @override
  String get authNameTooShort => 'Name is too short';

  @override
  String get authEmailRequired => 'Enter your email';

  @override
  String get authEmailInvalid => 'Enter a valid email address';

  @override
  String get authDobSelect => 'Select your date of birth';

  @override
  String get authDobInFuture => 'Date of birth can\'t be in the future';

  @override
  String authDobTooYoung(int age) {
    return 'You must be at least $age years old';
  }

  @override
  String get authConsentRequired =>
      'Please agree to the Terms and Privacy Policy to continue.';

  @override
  String get authSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get authProfileTitle => 'Complete your profile';

  @override
  String get authProfileSubtitle =>
      'Just a couple of details to finish setting up your account.';

  @override
  String get authFullName => 'Full name';

  @override
  String get authEmail => 'Email';

  @override
  String get authDateOfBirth => 'Date of birth';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String consentAgree(String terms, String privacy) {
    return 'I agree to the $terms and $privacy';
  }

  @override
  String get consentTerms => 'Terms';

  @override
  String get consentPrivacy => 'Privacy Policy';

  @override
  String get otpTitle => 'Verify your number';

  @override
  String otpSubtitle(int length, String phone) {
    return 'Enter the $length-digit code sent to $phone.';
  }

  @override
  String get otpFieldLabel => 'Verification code';

  @override
  String get otpVerify => 'Verify';

  @override
  String get otpInvalidated =>
      'That code is no longer valid. Request a new one to continue.';

  @override
  String get otpStartOver => 'Start over';

  @override
  String otpResendLocked(String time) {
    return 'Too many code requests. Try again in $time, or start over.';
  }

  @override
  String get otpDidntGetIt => 'Didn\'t get it?';

  @override
  String get otpResend => 'Resend code';

  @override
  String otpResendIn(String time) {
    return 'Resend code in $time';
  }

  @override
  String otpWrongLength(int length) {
    return 'Enter the $length-digit code';
  }

  @override
  String get otpDigitsOnly => 'Code must be digits only';

  @override
  String get homeNavHome => 'Home';

  @override
  String get homeNavActivity => 'Activity';

  @override
  String get homeNavAccount => 'Account';

  @override
  String get shellThanksForRating => 'Thanks for rating your trip.';

  @override
  String get accountYourProfile => 'Your profile';

  @override
  String get accountLogOut => 'Log out';

  @override
  String get accountDelete => 'Delete account';

  @override
  String get accountDeleting => 'Deleting your account…';

  @override
  String get accountDeleteConfirmTitle => 'Delete your account?';

  @override
  String get accountDeleteExplanation =>
      'We\'ll remove your name, email, phone number, saved cars and recent pickups, and sign you out on every device. Records of past rides and payments are kept, without your details, because the law requires us to keep them. This can\'t be undone.';

  @override
  String get accountDeleteFailed =>
      'Couldn\'t delete your account. Please try again.';

  @override
  String get carsMyCars => 'My cars';

  @override
  String get carsLoading => 'Loading your cars…';

  @override
  String get carsLoadFailed => 'Couldn\'t load your cars.';

  @override
  String get carsRetry => 'Retry';

  @override
  String get carsNoneYet =>
      'No saved cars yet — add yours once and pick it on every trip.';

  @override
  String get carsRemove => 'Remove car';

  @override
  String get carsAdd => 'Add a car';

  @override
  String get carsYourCar => 'Your car';

  @override
  String get carsSelectYourCar => 'Select your car';

  @override
  String get carsAddSubtitle => 'Saved once, offered on every booking.';

  @override
  String get carsRegistrationLabel => 'Registration number';

  @override
  String get carsRegistrationHint => 'e.g. KA 01 AB 1234';

  @override
  String get carsRegistrationIncomplete =>
      'Enter the full registration number.';

  @override
  String get carsSaving => 'Saving…';

  @override
  String get carsSave => 'Save car';

  @override
  String get carsSaveFailed => 'Couldn\'t save the car. Try again.';

  @override
  String get carsUnexpectedResponse => 'Unexpected response from the server.';

  @override
  String carsRequestFailed(int status) {
    return 'Saved-cars request failed ($status).';
  }

  @override
  String get updateTitle => 'Update MOJUD';

  @override
  String get updateBody =>
      'This version of the app is out of date. Install the latest one to keep booking drivers. Your account and rides are safe.';

  @override
  String get updateGetLatest => 'Get the latest version';

  @override
  String updateDownloadFrom(String site) {
    return 'Download it from $site';
  }

  @override
  String updateOpenFailed(String site) {
    return 'Couldn\'t open a browser. Copy the link and open it in one: $site';
  }

  @override
  String get updateCopyLink => 'Copy link';

  @override
  String get updateLinkCopied => 'Link copied';

  @override
  String get notifChannelName => 'Ride updates';

  @override
  String get notifChannelDescription =>
      'Your driver is assigned, and other changes to your rides.';

  @override
  String get homeYourProfile => 'Your profile';

  @override
  String homeHello(String name) {
    return 'Hello, $name';
  }

  @override
  String get homeWhereTo => 'Where should we drive you today?';

  @override
  String get homeBookADriver => 'Book a driver';

  @override
  String get homeHowTitle => 'Your car, our driver';

  @override
  String get homeHowBody =>
      'A driver comes to your pickup and drives your own car.';

  @override
  String get homeHowStepPick => 'Pick a trip';

  @override
  String get homeHowStepSet => 'Set pickup & time';

  @override
  String get homeHowStepDrive => 'Driver drives your car';

  @override
  String homePayFeeBeforeBooking(String fee) {
    return 'Pay the $fee cancellation fee for your last ride before booking another.';
  }

  @override
  String get homePayNow => 'Pay now';

  @override
  String get homeRetry => 'Retry';

  @override
  String homeNotBookedRoundTrip(String reason) {
    return 'Your Round Trip wasn\'t booked. $reason';
  }

  @override
  String homeNotBookedMultiStop(String reason) {
    return 'Your Multi-Stop trip wasn\'t booked. $reason';
  }

  @override
  String homeNotBookedOneWay(String reason) {
    return 'Your One-Way Trip wasn\'t booked. $reason';
  }

  @override
  String homeBookedRoundTrip(int hours, String car) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return 'Round Trip booked: $_temp0, in your $car.';
  }

  @override
  String homeBookedMultiStop(int count, String car) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '1 stop',
    );
    return 'Multi-Stop trip booked: $_temp0 planned, in your $car.';
  }

  @override
  String homeBookedOneWay(int minutes, String car, String destination) {
    return 'One-Way Trip booked: ~$minutes min, in your $car to $destination.';
  }

  @override
  String get tripPickerOneWayTitle => 'One-Way Trip';

  @override
  String get tripPickerOneWaySubtitle => 'Drop at a destination.';

  @override
  String get tripPickerRoundTripTitle => 'Round Trip';

  @override
  String get tripPickerRoundTripSubtitle =>
      'Hire a driver by the hour, out and back.';

  @override
  String get tripPickerMultiStopTitle => 'Multi-Stop Trip';

  @override
  String get tripPickerMultiStopSubtitle => 'Several stops, one driver.';

  @override
  String tripPickerSelected(String trip) {
    return 'Selected: $trip';
  }

  @override
  String get tripStartStartingPoint => 'Starting point';

  @override
  String get tripStartSetStartingPoint => 'Set starting point';

  @override
  String get tripStartStartingPointTapToChange =>
      'Starting point · tap to change';

  @override
  String get tripStartPickupTapToChange => 'Pickup · tap to change';

  @override
  String get tripStartFromCurrentLocation =>
      'From your current location · tap to change';

  @override
  String get tripStartFindingLocation => 'Finding your location…';

  @override
  String get tripStartPickup => 'Pickup';

  @override
  String get tripStartChooseStartingPoint => 'Choose a starting point';

  @override
  String get tripStartChoosePickup => 'Choose a pickup';

  @override
  String get tripStartNoCurrentLocation =>
      'Couldn\'t use your current location';

  @override
  String get serviceAreaOutside =>
      'We\'re only serving Delhi NCR (Delhi, Gurugram, Faridabad, Noida and nearby areas) right now — pick a location within this area.';

  @override
  String get scheduleSelectDate => 'Select date';

  @override
  String get scheduleSelectTime => 'Select time';

  @override
  String get scheduleTooSoon =>
      'Pick a start at least 45 minutes from now, so a driver can accept it.';

  @override
  String get timeSlotTitle => 'Pick a start time';

  @override
  String get timeSlotSubtitle => 'Trips start every 15 minutes.';

  @override
  String get hoursFewer => 'Fewer hours';

  @override
  String get hoursMore => 'More hours';

  @override
  String hoursUnit(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'hours',
      one: 'hour',
    );
    return '$_temp0';
  }

  @override
  String hoursChip(int hours) {
    return '${hours}h';
  }

  @override
  String get fareSummaryEstimatedFrom => 'Estimated fare from';

  @override
  String get fareSummaryEstimated => 'Estimated fare';

  @override
  String fareSummaryForHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return 'for $_temp0';
  }

  @override
  String get roundTripTitle => 'Trip details';

  @override
  String get roundTripHowLong => 'How long?';

  @override
  String get roundTripHowLongSubtitle => 'Hire a driver by the hour.';

  @override
  String get roundTripWhen => 'When?';

  @override
  String get roundTripWhenSubtitle => 'Pick a start date and time.';

  @override
  String get roundTripChoosePickupToContinue =>
      'Choose your pickup to continue.';

  @override
  String get roundTripConfirm => 'Confirm booking';

  @override
  String get roundTripFareNoteTitle => 'Estimated fare';

  @override
  String get roundTripFareNoteBody =>
      'Prices may vary based on the final pickup or drop location and the time taken. Time past your booked hours is charged by the hour.';

  @override
  String get roundTripFareNoteOk => 'Got it';

  @override
  String get bookingDetailsWhichCar => 'Which car?';

  @override
  String get bookingDetailsWhichCarSubtitle =>
      'The driver drives your car — pick one.';

  @override
  String get bookingDetailsChooseCarToContinue =>
      'Choose your car to continue.';

  @override
  String get multiStopTitle => 'Plan your trip';

  @override
  String get multiStopWhenStart => 'When do we start?';

  @override
  String get multiStopWhenStartSubtitle =>
      'The driver meets you at the starting point.';

  @override
  String get multiStopStops => 'Stops';

  @override
  String get multiStopStopsSubtitle =>
      'List each errand in order — where to go, what to do there, and when to move on.';

  @override
  String get multiStopAddStop => 'Add stop';

  @override
  String multiStopMaxStops(int max) {
    return 'Up to $max stops';
  }

  @override
  String get multiStopConfirm => 'Confirm trip';

  @override
  String multiStopSummary(int count, String date, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '1 stop',
    );
    return '$_temp0 · wraps up by $date, $time';
  }

  @override
  String get multiStopStopsIncomplete =>
      'Give every stop a location, a task, and a leave-by time to continue.';

  @override
  String get multiStopSetStopLocation => 'Set stop location';

  @override
  String get multiStopStopLocation => 'Stop location';

  @override
  String get multiStopLeaveByAfterStart =>
      'Leave-by must be after the start time.';

  @override
  String multiStopLeaveByAfterStop(int stop) {
    return 'Leave-by must be after stop $stop.';
  }

  @override
  String stopTitle(int index) {
    return 'Stop $index';
  }

  @override
  String stopMoveEarlier(int index) {
    return 'Move stop $index earlier';
  }

  @override
  String stopMoveLater(int index) {
    return 'Move stop $index later';
  }

  @override
  String stopRemove(int index) {
    return 'Remove stop $index';
  }

  @override
  String get stopChooseLocation => 'Choose location';

  @override
  String get stopTaskLabel => 'What should the driver do here?';

  @override
  String get stopTaskHint => 'e.g. Pick up the parcel from reception';

  @override
  String get stopLeaveBy => 'Leave by';

  @override
  String get oneWayRouteTitle => 'Where to?';

  @override
  String get oneWayRouteField => 'Destination';

  @override
  String get oneWayDetailsWhenTitle => 'When?';

  @override
  String get oneWayDetailsWhenSubtitle => 'Pick a start date and time.';

  @override
  String get oneWayDetailsCarTitle => 'Which car?';

  @override
  String get oneWayDetailsCarSubtitle =>
      'The driver drives your car — pick one.';

  @override
  String get oneWayDetailsChooseCar => 'Choose your car to continue.';

  @override
  String get oneWayReviewTitle => 'Review trip';

  @override
  String get oneWayReviewPlanTitle => 'Your plan';

  @override
  String get oneWayReviewPlanSubtitle => 'Go back to change any of these.';

  @override
  String get oneWayReviewStarts => 'Starts';

  @override
  String get oneWayReviewCar => 'Car';

  @override
  String get oneWayReviewTripTimeTitle => 'Trip time';

  @override
  String get oneWayReviewTripTimeSubtitle =>
      'Estimated for your chosen start time.';

  @override
  String get oneWayReviewCheckingTripTime => 'Checking the trip time…';

  @override
  String get oneWayReviewTripTimeNeeded =>
      'The trip time is needed to book — retry the estimate above.';

  @override
  String get oneWayReviewCheckingDriveTime => 'Checking the drive time…';

  @override
  String oneWayReviewAbout(String duration) {
    return 'About $duration';
  }

  @override
  String get oneWayReviewTripTimeFailed => 'Couldn\'t get the trip time.';

  @override
  String get oneWayReviewRetry => 'Retry';

  @override
  String get oneWayReviewConfirm => 'Confirm booking';

  @override
  String get pickupTitle => 'Set pickup';

  @override
  String get pickupField => 'Pickup location';

  @override
  String get pickupStartTitle => 'Set starting point';

  @override
  String get pickupStartField => 'Starting point';

  @override
  String get pickupSearchHint => 'Search for a place';

  @override
  String get pickupSelectOnMap => 'Select on map';

  @override
  String get pickupMapSubtitle => 'Opens the map to adjust the pin';

  @override
  String get pickupRecent => 'Recent';

  @override
  String get pickupEmptyWithLocation =>
      'Search for a place, or use your current location.';

  @override
  String get pickupEmptyWithMap =>
      'Search for a place, or select it on the map.';

  @override
  String get pickupCantPin => 'Couldn\'t pin that place. Try another result.';

  @override
  String get locationUseCurrent => 'Use my current location';

  @override
  String get mapPickerTitle => 'Pin on map';

  @override
  String get mapPickerCaption => 'Pickup here';

  @override
  String get mapPickerMoveHint => 'Move the map to place the pin';

  @override
  String get mapPickerConfirm => 'Confirm this location';

  @override
  String get mapPickerNotSetUp =>
      'The map isn\'t set up yet. Go back and search for your pickup instead.';

  @override
  String get mapPickerLoadFailed =>
      'Couldn\'t load the map. Check your connection, or that the Maps API key allows this site.';

  @override
  String get routeFrom => 'From';

  @override
  String get routeTo => 'To';

  @override
  String get routeMapUnavailable => 'Map preview unavailable';

  @override
  String get locationNoConnection =>
      'Can\'t reach the maps service. Check your connection and try again.';

  @override
  String get locationServiceUnavailable =>
      'The maps service is unavailable right now. Please try again.';

  @override
  String get locationUnexpectedReply =>
      'Unexpected response from the maps service.';

  @override
  String get locationDriveTimeNotSetUp =>
      'Drive-time estimates are not set up on this build.';

  @override
  String get locationNotFound =>
      'Couldn\'t find your location. Search for your pickup instead.';

  @override
  String get locationTurnedOff =>
      'Location is turned off. Switch it on to use your current spot.';

  @override
  String get locationPermissionDeclined =>
      'Location permission was declined. Search for your pickup instead.';

  @override
  String get locationBlocked =>
      'Location is blocked. Enable it in Settings, or search instead.';

  @override
  String get placesSessionExpired =>
      'Your session has expired. Sign in again to search for places.';

  @override
  String get placesNotSetUp => 'Map search isn\'t set up yet.';

  @override
  String get placesAuthFailed =>
      'Map search authorization failed. Please try again.';

  @override
  String get placesAuthUnexpected => 'Unexpected authorization response.';

  @override
  String get placesAuthNoToken => 'Authorization response carried no token.';

  @override
  String get rideYourDriver => 'Your driver';

  @override
  String rideIsYourDriver(String name) {
    return '$name is your driver';
  }

  @override
  String rideAtYourPickup(String name) {
    return '$name is at your pickup';
  }

  @override
  String rideIsDriving(String name) {
    return '$name is driving.';
  }

  @override
  String get rideDetailsTitleMissing => 'Your ride';

  @override
  String get rideDetailsNotInList => 'This ride isn\'t in your list any more.';

  @override
  String rideDetailsCancelledPayFee(String fee) {
    return 'Your ride is cancelled. Please pay the $fee fee.';
  }

  @override
  String get rideDetailsCancelled => 'Your ride is cancelled.';

  @override
  String get rideDetailsCancelFailed => 'Couldn\'t cancel the ride.';

  @override
  String get rideDetailsTripEnded => 'Your trip has ended.';

  @override
  String get rideDetailsEndFailed => 'Couldn\'t end the trip.';

  @override
  String get rideDetailsPaymentReceived => 'Payment received. Thank you!';

  @override
  String get rideDetailsThanksForRating => 'Thanks for rating your trip.';

  @override
  String get rideDetailsCancelRide => 'Cancel ride';

  @override
  String get rideDetailsFindingDriver => 'Finding you a driver';

  @override
  String get rideDetailsFindingDriverDetail =>
      'We\'ll let you know as soon as one accepts.';

  @override
  String rideDetailsPickupWhen(String when) {
    return 'Pickup $when';
  }

  @override
  String get rideDetailsShareStartCode => 'Share the start code when you meet.';

  @override
  String get rideDetailsOnYourTrip => 'On your trip';

  @override
  String rideDetailsStartedWhen(String when) {
    return 'Started $when';
  }

  @override
  String get rideDetailsTripEndedEarly => 'Trip ended early';

  @override
  String get rideDetailsTripCompleted => 'Trip completed';

  @override
  String get rideDetailsRideCancelled => 'Ride cancelled';

  @override
  String get rideDetailsWasCancelled => 'This ride was cancelled.';

  @override
  String get rideDetailsNoDriverDetail =>
      'No driver accepted in time. Please book again.';

  @override
  String get rideDetailsPayFeeTitle => 'Pay the cancellation fee';

  @override
  String get rideDetailsPayTripTitle => 'Pay for your trip';

  @override
  String rideDetailsPayFeeSubtitle(String amount) {
    return 'You cancelled after your driver reached the pickup. Pay $amount with any UPI app: GPay, PhonePe, Paytm or your bank\'s.';
  }

  @override
  String rideDetailsPayTripSubtitle(String amount) {
    return 'Pay $amount with any UPI app: GPay, PhonePe, Paytm or your bank\'s.';
  }

  @override
  String get rideDetailsWaitingForUpi => 'Waiting for UPI…';

  @override
  String rideDetailsPayByUpi(String amount) {
    return 'Pay $amount by UPI';
  }

  @override
  String get rideDetailsYouRated => 'You rated ';

  @override
  String get rideDetailsRateDriver => 'Rate your driver';

  @override
  String get rideDetailsHowWasTrip => 'How was your trip?';

  @override
  String rideDetailsHowWasTripWith(String name) {
    return 'How was your trip with $name?';
  }

  @override
  String get rideDetailsRoute => 'Route';

  @override
  String rideDetailsStopsPlanned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops planned',
      one: '1 stop planned',
    );
    return '$_temp0';
  }

  @override
  String get rideDetailsRoutePickup => 'Pickup';

  @override
  String rideDetailsRouteStop(int number) {
    return 'Stop $number';
  }

  @override
  String get rideDetailsRouteDestination => 'Destination';

  @override
  String rideDetailsLeaveBy(String time) {
    return 'Leave by $time';
  }

  @override
  String get rideDetailsTripDetails => 'Trip details';

  @override
  String get rideDetailsInfoTrip => 'Trip';

  @override
  String get rideDetailsInfoStarts => 'Starts';

  @override
  String get rideDetailsInfoBookedFor => 'Booked for';

  @override
  String get rideDetailsInfoEstDuration => 'Est. duration';

  @override
  String get rideDetailsInfoCar => 'Car';

  @override
  String get rideFare => 'Fare';

  @override
  String get rideBookedFare => 'Booked fare';

  @override
  String get rideCancellationFee => 'Cancellation fee';

  @override
  String get rideDetailsTimeline => 'Timeline';

  @override
  String get rideTimelineBooked => 'Booked';

  @override
  String get rideTimelineDriverAssigned => 'Driver assigned';

  @override
  String get rideTimelineDriverArrived => 'Driver arrived';

  @override
  String get rideTimelineTripStarted => 'Trip started';

  @override
  String get rideTimelineEndedEarly => 'Ended early';

  @override
  String get rideTimelineCompleted => 'Completed';

  @override
  String get rideTimelineNoDriverDetail => 'No driver accepted in time.';

  @override
  String get rideTrackingWaiting => 'Waiting for your driver\'s location';

  @override
  String get rideTrackingFinding => 'Finding your driver\'s location…';

  @override
  String rideTrackingOnTrip(String name) {
    return '$name is on your trip';
  }

  @override
  String rideTrackingLocation(String name) {
    return '$name\'s location';
  }

  @override
  String rideTrackingAway(String name, String distance) {
    return '$name is $distance away';
  }

  @override
  String rideTrackingUpdated(String where, String age) {
    return '$where · updated $age';
  }

  @override
  String rideDistanceMeters(int meters) {
    return '$meters m';
  }

  @override
  String rideDistanceKm(String km) {
    return '$km km';
  }

  @override
  String get rideAgeJustNow => 'just now';

  @override
  String rideAgeSeconds(int seconds) {
    return '$seconds s ago';
  }

  @override
  String rideAgeMinutes(int minutes) {
    return '$minutes min ago';
  }

  @override
  String rideAgeHours(int hours) {
    return '$hours h ago';
  }

  @override
  String get rideErrorNotFound => 'We couldn\'t find this ride any more.';

  @override
  String get rideErrorCancelHasFee =>
      'Cancelling now has a fee. Pull down to refresh, then try again.';

  @override
  String get rideErrorCannotCancel =>
      'This ride has already started or finished, so it can no longer be cancelled.';

  @override
  String get rideErrorNotInProgress => 'This trip isn\'t in progress any more.';

  @override
  String get rideErrorAlreadyRated => 'This ride has already been rated.';

  @override
  String rideErrorInvalidRating(int max) {
    return 'Pick 1 to 5 stars, and keep the note under $max characters.';
  }

  @override
  String get ridePayStillConfirming =>
      'We\'re still confirming your payment with the bank. This ride will show as paid in a minute or two.';

  @override
  String get ridePayFailed =>
      'The payment didn\'t go through. Please try again.';

  @override
  String get ridePayCancelled => 'Payment cancelled.';

  @override
  String get ridePayUnavailable => 'Paying in the app isn\'t available yet.';

  @override
  String get ridePayNotYet => 'This ride can\'t be paid for yet.';

  @override
  String get receiptTitle => 'Receipt';

  @override
  String get receiptPaidThanks => 'Paid. Thank you!';

  @override
  String get receiptFareForTimeUsed => 'Fare for the time used';

  @override
  String get receiptBaseFare => 'Base fare';

  @override
  String get receiptNightSurcharge => 'Night surcharge';

  @override
  String get receiptTotalPaid => 'Total paid';

  @override
  String get receiptPaidVia => 'Paid via';

  @override
  String get receiptReference => 'Reference';

  @override
  String get receiptOrder => 'Order';

  @override
  String get receiptPaidAt => 'Paid';

  @override
  String get endTripTitle => 'End trip now?';

  @override
  String get endTripByTheHour =>
      'You\'ll pay by the hour for the time used. Each started hour counts as a full hour.';

  @override
  String endTripOvertime(int minutes) {
    return 'If you\'re past your booked time, the extra hours are charged too, after a $minutes-minute grace.';
  }

  @override
  String get endTripKeepGoing => 'Keep going';

  @override
  String get endTripNow => 'End trip now';

  @override
  String get startCodeTitle => 'Start code';

  @override
  String get startCodeHint => 'Share it with your driver when you meet.';

  @override
  String startCodeSemantics(String digits) {
    return 'Start code $digits';
  }

  @override
  String get driverRowCall => 'Call driver';

  @override
  String driverRowPhotoOf(String name) {
    return 'Photo of $name';
  }

  @override
  String starsOutOfFive(int stars) {
    return '$stars out of 5 stars';
  }

  @override
  String starsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get starsWordPoor => 'Poor';

  @override
  String get starsWordNotGreat => 'Not great';

  @override
  String get starsWordOkay => 'Okay';

  @override
  String get starsWordGood => 'Good';

  @override
  String get starsWordExcellent => 'Excellent';

  @override
  String get starsNoteHint => 'Add a note for your driver (optional)';

  @override
  String get starsSubmit => 'Submit rating';

  @override
  String get liveMapPickup => 'Pickup';

  @override
  String get liveMapYourDriver => 'Your driver';

  @override
  String get activityTitle => 'Activity';

  @override
  String get activityTabUpcoming => 'Upcoming';

  @override
  String get activityTabCompleted => 'Completed';

  @override
  String get activityNoUpcomingTitle => 'No upcoming rides';

  @override
  String get activityNoUpcomingBody =>
      'Rides you book from Home show up here until they finish.';

  @override
  String get activityNoCompletedTitle => 'No completed rides yet';

  @override
  String get activityNoCompletedBody =>
      'Finished trips and their fares show up here.';

  @override
  String get activityLoadFailed => 'Couldn\'t load your rides';

  @override
  String get rateTitle => 'How was your trip?';

  @override
  String rateTitleWithDriver(String name) {
    return 'How was your trip with $name?';
  }

  @override
  String get rateNotNow => 'Not now';

  @override
  String rideCardStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '1 stop',
    );
    return '$_temp0';
  }

  @override
  String get rideCardTripCompleted => 'Trip completed';

  @override
  String rideCardDrivenBy(String name) {
    return 'Driven by $name';
  }

  @override
  String rideCardEndedEarly(String charge) {
    return 'Ended early. $charge';
  }

  @override
  String get rideCardYouRated => 'You rated';

  @override
  String get rideCardRateTrip => 'Rate your trip';

  @override
  String get rideCardCancelled => 'This ride was cancelled.';

  @override
  String get rideCardCancellationFee => 'Cancellation fee';

  @override
  String get rideCardNoDriver =>
      'No driver accepted in time. Please book again.';

  @override
  String get rideCardWaitingForDriver =>
      'We\'ll show your driver here as soon as one accepts.';

  @override
  String rideCardPayByUpi(String amount) {
    return 'Pay $amount by UPI';
  }

  @override
  String get rideCardPaid => 'Paid';

  @override
  String get cancelSheetTitle => 'Cancel this ride?';

  @override
  String cancelSheetFeeNowNamed(String name, String fee) {
    return '$name has reached your pickup, so cancelling now costs $fee.';
  }

  @override
  String cancelSheetFeeNow(String fee) {
    return 'Your driver has reached your pickup, so cancelling now costs $fee.';
  }

  @override
  String get cancelSheetFree => 'Cancelling is free.';

  @override
  String cancelSheetFreeUntilPickup(String fee) {
    return 'Cancelling is free until the driver reaches your pickup. After that it costs $fee.';
  }

  @override
  String cancelSheetFeeWarningNamed(String name) {
    return 'You\'ll pay the fee by UPI, like a ride, before your next booking. $name will be told you cancelled.';
  }

  @override
  String get cancelSheetFeeWarning =>
      'You\'ll pay the fee by UPI, like a ride, before your next booking. Your driver will be told you cancelled.';

  @override
  String cancelSheetWaitingNamed(String name) {
    return '$name is already waiting at your pickup. They will be told you cancelled.';
  }

  @override
  String get cancelSheetWaiting =>
      'Your driver is already waiting at your pickup. They will be told you cancelled.';

  @override
  String cancelSheetAcceptedNamed(String name) {
    return '$name has accepted this ride and is planning around it. They will be told you cancelled.';
  }

  @override
  String get cancelSheetAccepted =>
      'Your driver has accepted this ride and is planning around it. They will be told you cancelled.';

  @override
  String get cancelSheetWhy => 'Tell us why — it helps us improve.';

  @override
  String get cancelSheetTellUsMore => 'Tell us more (optional)';

  @override
  String cancelSheetCancelAndPay(String fee) {
    return 'Cancel and pay $fee';
  }

  @override
  String get cancelSheetCancelRide => 'Cancel ride';

  @override
  String get cancelSheetKeepRide => 'Keep my ride';

  @override
  String get helpTitle => 'Help & safety';

  @override
  String get helpCall112 => 'Call 112';

  @override
  String get helpShareTrip => 'Share trip';

  @override
  String get helpContactSupport => 'Contact support';

  @override
  String get helpDialerFailed => 'Couldn\'t open the dialer. Dial 112.';

  @override
  String get helpTripCopied => 'Trip details copied';

  @override
  String get helpWhatsAppFailed => 'Couldn\'t open WhatsApp.';

  @override
  String get helpShareIntro => 'My MOJUD trip';

  @override
  String helpShareWhen(String when) {
    return 'When: $when';
  }

  @override
  String helpSharePickup(String place) {
    return 'Pickup: $place';
  }

  @override
  String helpShareDriver(String name) {
    return 'Driver: $name';
  }

  @override
  String helpShareBooking(String id) {
    return 'Booking: $id';
  }

  @override
  String helpShareDateTime(String weekday, int day, String month, String time) {
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
    String _temp1 = intl.Intl.selectLogic(month, {
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
    return '$_temp0 $day $_temp1, $time';
  }

  @override
  String get bookingErrorPayLastRide =>
      'Pay for your last ride before booking another.';

  @override
  String bookingErrorLoadFailed(int status) {
    return 'Loading your rides failed ($status).';
  }

  @override
  String bookingErrorRequestFailed(int status) {
    return 'Booking request failed ($status).';
  }

  @override
  String get checkoutCouldNotStart => 'PhonePe couldn\'t start.';

  @override
  String get checkoutCouldNotOpen => 'PhonePe couldn\'t open.';

  @override
  String get checkoutAndroidOnly => 'Paying by UPI works in the Android app.';
}

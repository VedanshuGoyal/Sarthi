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

  @override
  String get accountTitle => 'Account';

  @override
  String get accountLogOutConfirmTitle => 'Log out?';

  @override
  String get accountLogOutConfirmBody =>
      'You\'ll go off duty and stop getting ride requests on this phone.';

  @override
  String get accountLogOut => 'Log out';

  @override
  String get accountSupportEmailSubject => 'Driver app help';

  @override
  String accountWriteToUs(String email) {
    return 'Write to us at $email';
  }

  @override
  String get accountSectionDriving => 'Driving';

  @override
  String get accountCarsYouDrive => 'Cars you drive';

  @override
  String get accountDrivingLicence => 'Driving licence';

  @override
  String get accountAadhaar => 'Aadhaar';

  @override
  String accountAadhaarMasked(String last4) {
    return 'XXXX XXXX $last4';
  }

  @override
  String get accountDocuments => 'Documents';

  @override
  String get accountDocumentsSubtitle => 'View or update what you submitted';

  @override
  String get accountSectionPayouts => 'Payouts';

  @override
  String get accountNoBankAccount => 'No bank account added';

  @override
  String accountBankAccount(String holder, String last4) {
    return '$holder · •••• $last4';
  }

  @override
  String get accountSectionHelp => 'Help';

  @override
  String get accountContactSupport => 'Contact support';

  @override
  String get accountKycVerified => 'Verified driver';

  @override
  String get accountKycSubmitted => 'Documents under review';

  @override
  String get accountKycRejected => 'Documents need attention';

  @override
  String get accountKycIncomplete => 'Documents incomplete';

  @override
  String get accountKycUnknown => 'Documents status unknown';

  @override
  String get accountDelete => 'Delete account';

  @override
  String get accountDeleteConfirmTitle => 'Delete your account?';

  @override
  String get accountDeleteExplanation =>
      'We\'ll delete your selfie, identity and licence checks, bank details and phone number, and sign you out on every device.\n\nRecords of rides you drove and payments are kept, without your details, because the law requires us to keep them.\n\nEarnings not yet paid out are still owed to you: MOJUD pays them out, so contact support before you delete if any are due.\n\nThis can\'t be undone.';

  @override
  String get accountDeleteFailed =>
      'Couldn\'t delete your account. Please try again.';

  @override
  String get startTagline =>
      'Drive customers in their own car, on your schedule. Get matched with nearby trips the moment you go online.';

  @override
  String get startDriving => 'Start Driving';

  @override
  String get rideDetailTitleRequest => 'Ride request';

  @override
  String get rideDetailTitle => 'Ride details';

  @override
  String get rideDetailApproxNote =>
      'Places show their area for now. The exact address, the car\'s number plate and the customer\'s name and number appear once you accept.';

  @override
  String get rideDetailCustomerAfterAccept =>
      'The customer\'s name and number appear once you accept.';

  @override
  String rideDetailAtPickupSince(String time) {
    return 'At pickup since $time';
  }

  @override
  String rideDetailStartedAt(String time) {
    return 'Started $time';
  }

  @override
  String rideDetailDoneAt(String when) {
    return 'Done $when';
  }

  @override
  String rideDetailSpanUntil(String span, String time) {
    return '$span · until ~$time';
  }

  @override
  String get rideDetailFareEstimated => 'estimated fare';

  @override
  String get rideDetailFareTrip => 'trip fare';

  @override
  String get rideDetailStepAccepted => 'Accepted';

  @override
  String get rideDetailStepDone => 'Done';

  @override
  String get rideDetailRoute => 'Route';

  @override
  String rideDetailDistanceAway(String distance) {
    return '$distance away';
  }

  @override
  String get rideDetailNavigateDrop => 'Navigate to drop';

  @override
  String get rideDetailNavigatePickup => 'Navigate to pickup';

  @override
  String get rideDetailCarHandover =>
      'The customer will hand over their car at the pickup.';

  @override
  String get rideDetailMapsFailed => 'Couldn\'t open Maps on this phone.';

  @override
  String rideDetailCancelReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String rideDetailCancellationFee(String fee) {
    return '$fee cancellation fee';
  }

  @override
  String get rideDetailRanOverTitle => 'Trip ran past the booked time';

  @override
  String get rideDetailEndedEarlyTitle => 'Customer ended the trip early';

  @override
  String get rideDetailPastBookedTime =>
      'Past the booked time — extra time is charged to the customer by the hour.';

  @override
  String get rideDetailNoShowDialogTitle => 'Customer didn\'t come?';

  @override
  String get rideDetailNoShowDialogBody =>
      'This closes the ride as a no-show. The customer is told you waited at the pickup, and it isn\'t counted as you cancelling.';

  @override
  String get rideDetailKeepWaiting => 'Keep waiting';

  @override
  String get rideDetailCloseRide => 'Close ride';

  @override
  String get rideDetailNoShowClosed => 'Ride closed as a no-show.';

  @override
  String get rideDetailNoShowTitle => 'Customer not here?';

  @override
  String get rideDetailNoShowOpen => 'You can close the ride as a no-show.';

  @override
  String rideDetailNoShowFrom(String time) {
    return 'If they still haven\'t come by $time, you can close the ride as a no-show.';
  }

  @override
  String get rideDetailNoShowButton => 'No-show';

  @override
  String get rideDetailSharingLocation =>
      'Sharing your live location with the customer';

  @override
  String get rideDetailNumberHidden => 'Number hidden after the ride';

  @override
  String get rideDetailCallCustomer => 'Call customer';

  @override
  String get rideDetailCallFailed => 'Couldn\'t start a call.';

  @override
  String get rideDetailCustomerCar => 'Customer\'s car';

  @override
  String get rideDetailRateTitle => 'Rate your customer';

  @override
  String get rideDetailRateNoteHint => 'Add a note for your records (optional)';

  @override
  String get rideDetailRateSubmit => 'Submit rating';

  @override
  String rideDetailYouRated(int stars) {
    return 'You rated $stars★';
  }

  @override
  String get rideDetailActionAccept => 'Accept ride';

  @override
  String get rideDetailActionArrive => 'I\'ve arrived at pickup';

  @override
  String get rideDetailActionStart => 'Start trip';

  @override
  String get rideDetailActionComplete => 'Complete trip';

  @override
  String get rideDetailActionDecline => 'Decline';

  @override
  String get rideDetailActionRelease => 'Can\'t make it';

  @override
  String get rideDetailAccepted =>
      'Ride accepted — it\'s in your upcoming rides.';

  @override
  String get rideDetailDeclined => 'Request hidden.';

  @override
  String get rideDetailReleased => 'Ride handed back.';

  @override
  String get rideDetailStarted => 'Trip started. Drive safe!';

  @override
  String rideDetailCompletedEndedEarly(String amount) {
    return 'The customer ended the trip early. They can now pay $amount by UPI in their app.';
  }

  @override
  String rideDetailCompletedRanOver(String charge) {
    return 'Trip complete. It ran past the booked time, so the customer can now pay $charge by UPI in their app.';
  }

  @override
  String rideDetailCompleted(String amount) {
    return 'Trip complete. The customer can now pay $amount by UPI in their app.';
  }

  @override
  String get rideDetailConfirmCompleteTitle => 'Complete the trip?';

  @override
  String get rideDetailConfirmCompleteBody =>
      'Confirm the trip is over and the car is back with the customer.';

  @override
  String get rideDetailConfirmCompleteYes => 'Complete';

  @override
  String get rideDetailConfirmReleaseTitle => 'Hand this ride back?';

  @override
  String get rideDetailConfirmReleaseBody =>
      'It goes back to other drivers nearby, and leaves your list.';

  @override
  String get rideDetailConfirmReleaseYes => 'Hand back';

  @override
  String get rideDetailNotNow => 'Not now';

  @override
  String get rideDetailStartCodeTitle => 'Enter start code';

  @override
  String get rideDetailStartCodeBody =>
      'Ask the customer for the 4-digit code shown in their MOJUD app.';

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
  String get helpWhatsAppFailed => 'Couldn\'t open WhatsApp on this phone.';

  @override
  String get helpShareIntro => 'I\'m driving a MOJUD trip.';

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
  String helpShareDateTime(
    String weekday,
    String day,
    String month,
    String year,
    String time,
  ) {
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
    return '$_temp0, $day $_temp1 $year, $time';
  }

  @override
  String get ridesPanelTitle => 'My rides';

  @override
  String get ridesPanelTabUpcoming => 'Upcoming';

  @override
  String get ridesPanelTabOngoing => 'Ongoing';

  @override
  String get ridesPanelTabCompleted => 'Completed';

  @override
  String get ridesPanelTabCancelled => 'Cancelled';

  @override
  String get ridesPanelEmptyUpcomingTitle => 'No upcoming rides';

  @override
  String get ridesPanelEmptyUpcomingBody =>
      'Rides you accept from the Home tab line up here.';

  @override
  String get ridesPanelEmptyOngoingTitle => 'Nothing underway';

  @override
  String get ridesPanelEmptyOngoingBody =>
      'Tap \"I\'ve arrived\" on an upcoming ride when you reach the pickup.';

  @override
  String get ridesPanelEmptyCompletedTitle => 'No completed rides yet';

  @override
  String get ridesPanelEmptyCompletedBody =>
      'Finished trips and their fares show up here.';

  @override
  String get ridesPanelEmptyCancelledTitle => 'No cancelled rides';

  @override
  String get ridesPanelEmptyCancelledBody =>
      'Rides a customer cancels after you accept them show up here.';

  @override
  String get ridesPanelLoadFailed => 'Couldn\'t load your rides';

  @override
  String get myRidesInvalidRating => 'Pick 1 to 5 stars for the customer.';

  @override
  String get myRidesCantRate => 'This ride can\'t be rated right now.';

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
    return '$weekday, $day $month';
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
  String fmtMeters(int meters) {
    return '$meters m';
  }

  @override
  String fmtKilometers(String km) {
    return '$km km';
  }

  @override
  String get fmtNow => 'now';

  @override
  String fmtTimeAgo(String duration) {
    return '$duration ago';
  }

  @override
  String fmtTimeIn(String duration) {
    return 'in $duration';
  }

  @override
  String fmtSpanHire(int hours) {
    return '$hours h hire';
  }

  @override
  String fmtSpanDrive(String duration) {
    return '~$duration drive';
  }

  @override
  String fmtSpanStops(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '1 stop',
    );
    return '$_temp0 · $duration';
  }

  @override
  String fmtPaidYourShare(String share) {
    return 'Paid · your share $share after commission';
  }

  @override
  String fmtCancellationFee(String fee) {
    return '$fee cancellation fee';
  }

  @override
  String fmtEndedEarlyCharge(String fare, String booked) {
    return 'Charged $fare for the time used (booked $booked)';
  }

  @override
  String fmtRanOverCharge(String fare, String booked) {
    return '$fare for the time used (booked $booked)';
  }

  @override
  String get fmtNewCustomer => 'New customer';

  @override
  String fmtCustomerRating(String rating, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings',
      one: '1 rating',
    );
    return '★ $rating · $_temp0';
  }

  @override
  String get fmtNoRatingsYet => 'No ratings yet';

  @override
  String fmtDriverRating(String rating, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
    );
    return 'Your rating ★ $rating from $_temp0';
  }

  @override
  String ridesPickupAt(String time) {
    return 'Pickup · $time';
  }

  @override
  String ridesLastOfStops(int count) {
    return 'Last of $count stops';
  }

  @override
  String ridesStopNumber(int number) {
    return 'Stop $number';
  }

  @override
  String ridesLeaveBy(String time) {
    return 'leave by $time';
  }

  @override
  String ridesDropAt(String time) {
    return 'Drop · ~$time';
  }

  @override
  String ridesBackAtPickup(String time) {
    return 'Back at pickup · ~$time';
  }

  @override
  String get ridesExactPlaceAfterAccept => 'Exact place after you accept';

  @override
  String get ridesFareEstimate => 'estimate';

  @override
  String ridesDistanceAway(String distance) {
    return '$distance away';
  }

  @override
  String get ridesExactAddressAfterAccept => 'Exact address after you accept';

  @override
  String ridesEndedEarlyNote(String charge) {
    return 'Customer ended the trip early · $charge';
  }

  @override
  String ridesRanOverNote(String charge) {
    return 'Trip ran past the booked time · $charge';
  }

  @override
  String get earningsTitle => 'Earnings';

  @override
  String get earningsToday => 'Today\'s earnings';

  @override
  String earningsTripsCompleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips completed',
      one: '1 trip completed',
    );
    return '$_temp0';
  }

  @override
  String earningsYoursAfterCommission(String amount) {
    return '$amount yours after commission';
  }

  @override
  String get earningsThisWeek => 'This week';

  @override
  String get earningsThisMonth => 'This month';

  @override
  String get earningsAllTime => 'All time';

  @override
  String earningsTrips(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
    );
    return '$_temp0';
  }

  @override
  String earningsYours(String amount) {
    return '$amount yours';
  }

  @override
  String get earningsAwaitingCustomers => 'Waiting for customers to pay';

  @override
  String get earningsDueToYou => 'Due to you';

  @override
  String earningsDueDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
    );
    return '$_temp0 · paid to your bank weekly';
  }

  @override
  String get earningsPaidToBank => 'Paid to your bank';

  @override
  String get earningsNoPayoutsYet => 'No payouts yet';

  @override
  String earningsLastPayout(String when) {
    return 'Last on $when';
  }

  @override
  String get earningsPayoutsHeader => 'Payouts';

  @override
  String get earningsNoPayoutsBody =>
      'Each transfer MOJUD makes to your bank is listed here with its reference.';

  @override
  String earningsPayoutTitle(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
    );
    return '$_temp0 · $when';
  }

  @override
  String earningsPayoutReference(String reference) {
    return 'Ref $reference';
  }

  @override
  String get earningsCompletedTrips => 'Completed trips';

  @override
  String get earningsNoTripsTitle => 'No trips yet';

  @override
  String get earningsNoTripsBody =>
      'Each trip you complete is listed here with its fare.';

  @override
  String dutyHello(String name) {
    return 'Hello, $name';
  }

  @override
  String get dutyOnDutyHeadline => 'You\'re on duty';

  @override
  String get dutyReadyHeadline => 'Ready to drive?';

  @override
  String get dutyNextRide => 'Your next ride';

  @override
  String get dutyRideInProgress => 'Ride in progress';

  @override
  String get dutyRideRequests => 'Ride requests';

  @override
  String dutyOpenCount(int count) {
    return '$count open';
  }

  @override
  String get dutyOfflineTitle => 'You\'re offline';

  @override
  String get dutyOfflineBody => 'Go on duty to see rides booked near you.';

  @override
  String get dutyRequestsErrorTitle => 'Couldn\'t load requests';

  @override
  String get dutyNoRequestsTitle => 'No requests right now';

  @override
  String dutyNoRequestsBody(int seconds) {
    return 'New bookings near you show up here. We check every $seconds seconds while you\'re on duty.';
  }

  @override
  String get dutyLocationOffNote =>
      'Turn on location to see how far each pickup is. Showing all open rides.';

  @override
  String dutyRideAccepted(String when) {
    return 'Ride accepted for $when.';
  }

  @override
  String get dutyOnline => 'Online';

  @override
  String get dutyOffline => 'Offline';

  @override
  String get dutyOnDuty => 'On duty';

  @override
  String get dutyOffDuty => 'Off duty';

  @override
  String get dutyGettingRequests => 'Getting ride requests near you';

  @override
  String get dutyTapToStart => 'Tap to start getting ride requests';

  @override
  String get dutyStripToday => 'Today';

  @override
  String get dutyStripTripsToday => 'Trips today';

  @override
  String get dutyStripBooked => 'Booked';

  @override
  String get dutyDecline => 'Decline';

  @override
  String get dutyAcceptRide => 'Accept ride';

  @override
  String get homeNavHome => 'Home';

  @override
  String get homeNavRides => 'Rides';

  @override
  String get homeNavEarnings => 'Earnings';

  @override
  String get homeNavAccount => 'Account';

  @override
  String get locationSharingTitle => 'Sharing your location';

  @override
  String get locationSharingText => 'Your customer can see you on the way.';

  @override
  String get locationChannelName => 'Live location';

  @override
  String get docViewLogOut => 'Log out';

  @override
  String get docViewLogOutTitle => 'Log out?';

  @override
  String get docViewLogOutBody =>
      'You can sign in again with your phone number. The steps you have finished stay saved.';

  @override
  String get docViewLoadFailedTitle => 'Couldn\'t load your registration';

  @override
  String get docViewTitleVerified => 'You\'re verified';

  @override
  String get docViewTitleSubmitted => 'Under review';

  @override
  String get docViewTitleRejected => 'Some details need fixing';

  @override
  String get docViewTitleUnknown => 'We can\'t show your status';

  @override
  String get docViewTitleIncomplete => 'Complete your registration';

  @override
  String get docViewSubtitleVerified =>
      'You\'re cleared to take rides. Open any step to see what you sent, or to change it.';

  @override
  String get docViewSubtitleSubmitted =>
      'We\'re checking your details. You can go online once they\'re cleared.';

  @override
  String get docViewSubtitleRejected =>
      'Fix the details below and submit again.';

  @override
  String get docViewSubtitleUnknown =>
      'Your account has a status this version of the app doesn\'t know, so you can\'t take rides yet.';

  @override
  String docViewSubtitleIncomplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Finish these $count steps to start accepting rides. Each one unlocks once the last is done.',
      one: 'Finish this step to start accepting rides.',
    );
    return '$_temp0';
  }

  @override
  String get docViewCheckAgain => 'Check again';

  @override
  String get docViewChecking => 'Checking…';

  @override
  String get docViewSubmit => 'Submit for verification';

  @override
  String get docViewSubmitting => 'Submitting…';

  @override
  String get kycBannerVerifiedTitle => 'Cleared to drive';

  @override
  String get kycBannerAadhaarVerified => 'Aadhaar verified with DigiLocker';

  @override
  String kycBannerAadhaarVerifiedLast4(String last4) {
    return 'Aadhaar XXXX XXXX $last4 · verified with DigiLocker';
  }

  @override
  String get kycBannerLicenseVerified => 'Driving licence verified';

  @override
  String kycBannerLicenseVerifiedNumber(String number) {
    return 'Driving licence $number · verified';
  }

  @override
  String kycBannerBankVerified(String last4) {
    return 'Bank account •••• $last4 · verified with your bank';
  }

  @override
  String get kycBannerSubmittedTitle => 'Waiting on a reviewer';

  @override
  String kycBannerSent(String date) {
    return 'Sent $date';
  }

  @override
  String get kycBannerRejectedTitle => 'Sent back by a reviewer';

  @override
  String get kycBannerRejectedHint =>
      'Open the steps below to see what to change.';

  @override
  String get kycBannerUnknownTitle => 'Status not recognised';

  @override
  String get kycBannerUnknownHint =>
      'Update the app, or write to team@mojud.life if this stays.';

  @override
  String docCardDate(String day, String month, String year) {
    return '$day $month $year';
  }

  @override
  String get docPhotoSaveFailed =>
      'Couldn\'t save the photo. Please take it again.';

  @override
  String get docPhotoReadFailed =>
      'Couldn\'t read the photo. Please take it again.';

  @override
  String get permissionsSubtitle =>
      'Turn these on so ride offers reach you even when MOJUD Driver isn\'t the app on screen.';

  @override
  String get permissionsOverlayTitle => 'Display over other apps';

  @override
  String get permissionsOverlaySubtitle =>
      'Shows ride alerts on top of whatever app you\'re using.';

  @override
  String get permissionsLocationTitle => 'Background location';

  @override
  String get permissionsLocationSubtitle =>
      'Streams your GPS to riders and dispatch while online.';

  @override
  String get permissionsBatteryTitle => 'Battery usage';

  @override
  String get permissionsBatterySubtitle =>
      'Stops the OS from pausing location updates to save power.';

  @override
  String get permissionsNotRequired => 'Not required on this device';

  @override
  String get permissionsTurnOn => 'Turn on';

  @override
  String get permissionsFinish => 'Finish';

  @override
  String get validationAadhaarEmpty => 'Enter your Aadhaar number';

  @override
  String get validationAadhaarInvalid =>
      'Enter a valid 12-digit Aadhaar number';

  @override
  String get validationLicenseEmpty => 'Enter your driving license number';

  @override
  String get validationLicenseInvalid => 'Enter a valid license number';

  @override
  String get validationHolderNameEmpty => 'Enter the account holder\'s name';

  @override
  String get validationNameTooShort => 'Name is too short';

  @override
  String get validationAccountEmpty => 'Enter your account number';

  @override
  String get validationAccountInvalid => 'Enter a valid account number';

  @override
  String get validationAccountConfirmEmpty => 'Re-enter your account number';

  @override
  String get validationAccountMismatch => 'Account numbers don\'t match';

  @override
  String get validationIfscEmpty => 'Enter the IFSC code';

  @override
  String get validationIfscInvalid => 'Enter a valid IFSC code';

  @override
  String get vehicleStepTitle => 'Type of vehicle';

  @override
  String get vehicleStepSubtitle =>
      'Which gearbox can you drive? This decides which rides you\'re matched with.';

  @override
  String get vehicleStepSaving => 'Saving…';

  @override
  String get photoPickerDefaultLabel => 'Take a photo of the document';

  @override
  String get photoPickerUploadFailed =>
      'Upload didn\'t finish — tap to take the photo again.';

  @override
  String get photoPickerUploadedNoPreview => 'Photo uploaded';

  @override
  String get photoPickerBadgeUploading => 'Uploading…';

  @override
  String get photoPickerBadgeUploaded => 'Uploaded';

  @override
  String get photoPickerBadgeRetry => 'Retry';

  @override
  String get photoPickerBadgeRetake => 'Retake';

  @override
  String get photoStepTitle => 'Photo and name';

  @override
  String get photoStepSubtitle =>
      'A clear selfie and your details, as they appear on your ID.';

  @override
  String get photoStepSelfieRequired => 'Take a selfie to continue';

  @override
  String get photoStepDobRequired => 'Select your date of birth';

  @override
  String get photoStepGenderRequired => 'Select your gender';

  @override
  String get photoStepSelfieUploading => 'Uploading…';

  @override
  String get photoStepSelfieUploadFailed => 'Upload failed — tap to retry';

  @override
  String get photoStepRetakeSelfie => 'Retake selfie';

  @override
  String get photoStepTakeSelfie => 'Take a selfie';

  @override
  String get photoStepTakeNewSelfie => 'Take a new one instead';

  @override
  String get photoStepSelfieShownToCustomers =>
      'Customers see this photo when you take their ride.';

  @override
  String get photoStepFromAadhaar => 'From your Aadhaar';

  @override
  String get photoStepFullName => 'Full name';

  @override
  String get photoStepDateOfBirth => 'Date of birth';

  @override
  String get photoStepSaving => 'Saving…';

  @override
  String get aadhaarStepTitle => 'Aadhaar card';

  @override
  String get aadhaarStepVerifiedSubtitle => 'Your Aadhaar is verified.';

  @override
  String get aadhaarStepSubtitle =>
      'Enter your Aadhaar number, then sign in to DigiLocker to verify it.';

  @override
  String get aadhaarStepOpenFailed => 'Couldn\'t open DigiLocker. Try again.';

  @override
  String get aadhaarStepFinishFirst => 'Finish the steps in DigiLocker first.';

  @override
  String get aadhaarStepChecking => 'Checking…';

  @override
  String get aadhaarStepFinished => 'I\'ve finished in DigiLocker';

  @override
  String get aadhaarStepOpening => 'Opening DigiLocker…';

  @override
  String get aadhaarStepVerify => 'Verify with DigiLocker';

  @override
  String get aadhaarStepVerifiedTitle => 'Verified with DigiLocker';

  @override
  String aadhaarStepBorn(String date) {
    return 'Born $date';
  }

  @override
  String aadhaarStepMasked(String last4) {
    return 'Aadhaar XXXX XXXX $last4';
  }

  @override
  String get aadhaarStepNumberLabel => 'Aadhaar number';

  @override
  String get aadhaarStepSavedHint =>
      'Saved. Leave this blank unless you need to change it.';

  @override
  String get aadhaarStepWaiting => 'Finish in DigiLocker, then come back here.';

  @override
  String get aadhaarStepOpenAgain => 'Open DigiLocker again';

  @override
  String get licenseStepTitle => 'Driving license';

  @override
  String get licenseStepSubtitle =>
      'We check your license number with the transport department.';

  @override
  String get licenseStepNumberLabel => 'License number';

  @override
  String get licenseStepNumberHint => 'e.g. MP0920190012345';

  @override
  String get licenseStepVerifiedTitle => 'License verified';

  @override
  String licenseStepValidTill(String date) {
    return 'Valid till $date';
  }

  @override
  String licenseStepCovers(String classes) {
    return 'Covers $classes';
  }

  @override
  String get licenseStepChecking => 'Checking…';

  @override
  String get licenseStepVerify => 'Verify license';

  @override
  String get bankStepTitle => 'Bank details';

  @override
  String get bankStepSubtitle =>
      'Your earnings are paid to this account. We check it with your bank.';

  @override
  String get bankStepVerifiedTitle => 'Verified with your bank';

  @override
  String bankStepAccountEnding(String last4, String ifsc) {
    return 'Account ending $last4 · $ifsc';
  }

  @override
  String get bankStepHolderLabel => 'Account holder name';

  @override
  String get bankStepHolderHint => 'As it appears on the bank account';

  @override
  String get bankStepAccountNumber => 'Account number';

  @override
  String bankStepCurrentAccount(String last4) {
    return 'Currently paying out to the account ending $last4. Re-enter the number to change it.';
  }

  @override
  String get bankStepConfirmLabel => 'Confirm account number';

  @override
  String get bankStepConfirmHint => 'Re-enter account number';

  @override
  String get bankStepIfscLabel => 'IFSC code';

  @override
  String get bankStepIfscHint => 'e.g. HDFC0001234';

  @override
  String get bankStepChecking => 'Checking with your bank…';

  @override
  String get bankStepFinish => 'Finish';

  @override
  String get authPhoneTitle => 'Enter your mobile number';

  @override
  String get authPhoneSubtitle =>
      'We\'ll text you a one-time code to verify it\'s you.';

  @override
  String get authMobileNumberLabel => 'Mobile number';

  @override
  String get authPhoneRequired => 'Enter your mobile number';

  @override
  String get authPhoneInvalid => 'Enter a valid 10-digit mobile number';

  @override
  String get authNameTitle => 'What\'s your name?';

  @override
  String get authNameSubtitle =>
      'This is how riders will see you once you\'re on a trip.';

  @override
  String get authFullName => 'Full name';

  @override
  String get authNameRequired => 'Enter your name';

  @override
  String get authNameTooShort => 'Name is too short';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authConsentRequired =>
      'Agree to the Terms and Privacy Policy to create your account.';

  @override
  String get authSessionEnded =>
      'Your session has ended. Please sign in again.';

  @override
  String consentAgree(String terms, String privacy) {
    return 'I agree to the $terms and $privacy';
  }

  @override
  String get consentTerms => 'Terms';

  @override
  String get consentPrivacy => 'Privacy Policy';

  @override
  String consentOpenInBrowser(String address) {
    return 'Open $address in a browser';
  }

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
  String get updateTitle => 'Update MOJUD Driver';

  @override
  String get updateBody =>
      'This version of the app is out of date. Install the latest one to keep getting rides. Your account, documents and earnings are safe.';

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
  String get notifChannelName => 'Ride requests';

  @override
  String get notifChannelDescription =>
      'New rides booked near you while you are on duty.';
}

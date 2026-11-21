// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'MOJUD';

  @override
  String get commonCancel => 'कैंसल';

  @override
  String get commonOk => 'ठीक है';

  @override
  String get commonClose => 'बंद करें';

  @override
  String get commonContinue => 'आगे बढ़ें';

  @override
  String get commonTryAgain => 'फिर से कोशिश करें';

  @override
  String get commonSave => 'सेव करें';

  @override
  String get commonBack => 'वापस';

  @override
  String get errorNoConnection =>
      'सर्वर से कनेक्ट नहीं हो पा रहा। इंटरनेट चेक करके फिर से कोशिश करें।';

  @override
  String get errorNoConnectionShort => 'सर्वर से कनेक्ट नहीं हो पा रहा।';

  @override
  String get errorUnexpectedReply => 'सर्वर से सही जवाब नहीं आया।';

  @override
  String get errorGeneric => 'कुछ गड़बड़ हो गई। फिर से कोशिश करें।';

  @override
  String errorGenericStatus(int status) {
    return 'कुछ गड़बड़ हो गई ($status)।';
  }

  @override
  String get languageTitle => 'भाषा · Language';

  @override
  String get languageFollowsPhone =>
      'अभी फ़ोन वाली भाषा है। बदलने के लिए एक चुनें।';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिंदी';

  @override
  String get fmtToday => 'आज';

  @override
  String get fmtTomorrow => 'कल';

  @override
  String get fmtYesterday => 'कल';

  @override
  String fmtWeekdayShort(String weekday) {
    String _temp0 = intl.Intl.selectLogic(weekday, {
      'mon': 'सोम',
      'tue': 'मंगल',
      'wed': 'बुध',
      'thu': 'गुरु',
      'fri': 'शुक्र',
      'sat': 'शनि',
      'sun': 'रवि',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String fmtMonthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'jan': 'जनवरी',
      'feb': 'फ़रवरी',
      'mar': 'मार्च',
      'apr': 'अप्रैल',
      'may': 'मई',
      'jun': 'जून',
      'jul': 'जुलाई',
      'aug': 'अगस्त',
      'sep': 'सितंबर',
      'oct': 'अक्टूबर',
      'nov': 'नवंबर',
      'dec': 'दिसंबर',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String fmtDate(String weekday, int day, String month) {
    return '$weekday, $day $month';
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
    return '$minutes मिनट';
  }

  @override
  String fmtHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours घंटे',
      one: '1 घंटा',
    );
    return '$_temp0';
  }

  @override
  String fmtHoursMinutes(int hours, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours घंटे',
      one: '1 घंटा',
    );
    return '$_temp0 $minutes मिनट';
  }

  @override
  String fmtEndedEarly(String fare, String booked) {
    return 'जितना समय लगा उसका $fare लिया गया (बुकिंग $booked की थी)।';
  }

  @override
  String fmtRanOverHours(String fare, int hours, String booked) {
    return 'ट्रिप बुक किए समय से ज़्यादा चली। $hours घंटे का $fare लिया गया (बुकिंग $booked की थी)।';
  }

  @override
  String fmtRanOver(String fare, String booked) {
    return 'ट्रिप बुक किए समय से ज़्यादा चली। $fare लिया गया (बुकिंग $booked की थी)।';
  }

  @override
  String get fmtPastBookedTime =>
      'बुक किया समय पूरा हो गया। ज़्यादा समय का पैसा घंटे के हिसाब से लगेगा।';

  @override
  String fmtCarriedNote(String amount, String rides) {
    String _temp0 = intl.Intl.selectLogic(rides, {
      'one': 'पिछली राइड',
      'other': 'पिछली राइडों',
    });
    return '$_temp0 के बाकी $amount इस ट्रिप का पेमेंट करते समय जुड़ जाएँगे।';
  }

  @override
  String fmtCarriedIncluded(String amount, String rides) {
    String _temp0 = intl.Intl.selectLogic(rides, {
      'one': 'दूसरी राइड',
      'other': 'दूसरी राइडों',
    });
    return 'इसमें $_temp0 के $amount भी शामिल हैं।';
  }

  @override
  String fmtPaidTogether(String amount, String others) {
    return '$amount का पेमेंट $others के साथ हुआ।';
  }

  @override
  String fmtOtherRides(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दूसरी राइडों',
      one: '1 दूसरी राइड',
    );
    return '$_temp0';
  }

  @override
  String fmtRideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count राइडों',
      one: '1 राइड',
    );
    return '$_temp0';
  }

  @override
  String fmtOtherCancellationFees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दूसरे कैंसल चार्ज',
      one: '1 दूसरे कैंसल चार्ज',
    );
    return '$_temp0';
  }

  @override
  String fmtCancellationFeeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count कैंसल चार्ज',
      one: '1 कैंसल चार्ज',
    );
    return '$_temp0';
  }

  @override
  String fmtListAnd(String first, String second) {
    return '$first और $second';
  }

  @override
  String get fmtNewDriver => 'नया ड्राइवर';

  @override
  String fmtDriverRating(String rating, int count) {
    return '★ $rating · $count रेटिंग';
  }

  @override
  String get tripTypeRoundTrip => 'राउंड ट्रिप';

  @override
  String get tripTypeOneWay => 'वन-वे';

  @override
  String get tripTypeMultiStop => 'मल्टी-स्टॉप';

  @override
  String get bookingStatusRequested => 'ड्राइवर ढूँढ रहे हैं';

  @override
  String get bookingStatusAccepted => 'ड्राइवर मिल गया';

  @override
  String get bookingStatusArrived => 'ड्राइवर पिकअप पर है';

  @override
  String get bookingStatusInProgress => 'ट्रिप चालू';

  @override
  String get bookingStatusCompleted => 'पूरी हुई';

  @override
  String get bookingStatusCancelled => 'कैंसल';

  @override
  String get bookingStatusExpired => 'कोई ड्राइवर नहीं मिला';

  @override
  String get bookingCancelledByYou => 'आपने कैंसल किया';

  @override
  String get bookingCancelledByDriver => 'आपके ड्राइवर ने कैंसल किया';

  @override
  String get bookingCancelledNoShow => 'आपके न आने पर बंद हुई';

  @override
  String bookingCancelledSummary(String who, String reason) {
    return '$who · $reason';
  }

  @override
  String get cancelReasonPlansChanged => 'प्लान बदल गया';

  @override
  String get cancelReasonBookedByMistake => 'ग़लती से बुक हो गई';

  @override
  String get cancelReasonDriverAsked => 'ड्राइवर ने कैंसल करने को कहा';

  @override
  String get cancelReasonDriverNotResponding => 'ड्राइवर जवाब नहीं दे रहा';

  @override
  String get cancelReasonFoundAnotherOption => 'कोई दूसरा इंतज़ाम मिल गया';

  @override
  String get cancelReasonOther => 'कुछ और';

  @override
  String get carTypeHatchback => 'हैचबैक';

  @override
  String get carTypeSedan => 'सेडान';

  @override
  String get carTypeSuv => 'SUV';

  @override
  String get carTypeLuxury => 'लग्ज़री';

  @override
  String get transmissionAutomatic => 'ऑटोमैटिक';

  @override
  String get transmissionManual => 'मैनुअल';

  @override
  String get carOptionsCarType => 'कार का टाइप';

  @override
  String get carOptionsSelectCarType => 'कार का टाइप चुनें';

  @override
  String get carOptionsTransmission => 'गियरबॉक्स';

  @override
  String get paymentModeUpi => 'UPI';

  @override
  String get paymentModeCash => 'कैश';

  @override
  String get paymentModeWaived => 'MOJUD ने माफ़ किया';

  @override
  String get paymentLineRide => 'राइड';

  @override
  String get paymentLineCancellationFee => 'कैंसल चार्ज';

  @override
  String get authPhoneTitle => 'अपना मोबाइल नंबर डालें';

  @override
  String get authPhoneSubtitle =>
      'हम आपको SMS पर एक OTP भेजेंगे, ताकि पता चले कि यह आप ही हैं।';

  @override
  String get authMobileNumberLabel => 'मोबाइल नंबर';

  @override
  String get authBrandTagline => 'आपकी कार, हमारा ड्राइवर।';

  @override
  String get authBrandBody =>
      'जब भी ज़रूरत हो, अपनी कार के लिए ड्राइवर बुक करें।';

  @override
  String get authServiceByTheHour => 'घंटे के हिसाब से';

  @override
  String get authServiceOneWay => 'वन-वे';

  @override
  String get authServiceMultiStop => 'मल्टी-स्टॉप';

  @override
  String get authPhoneRequired => 'अपना मोबाइल नंबर डालें';

  @override
  String get authPhoneInvalid => 'सही 10 अंकों का मोबाइल नंबर डालें';

  @override
  String get authNameRequired => 'अपना नाम डालें';

  @override
  String get authNameTooShort => 'नाम बहुत छोटा है';

  @override
  String get authEmailRequired => 'अपना ईमेल डालें';

  @override
  String get authEmailInvalid => 'सही ईमेल पता डालें';

  @override
  String get authDobSelect => 'अपनी जन्म की तारीख चुनें';

  @override
  String get authDobInFuture => 'जन्म की तारीख आज के बाद की नहीं हो सकती';

  @override
  String authDobTooYoung(int age) {
    return 'आपकी उम्र कम से कम $age साल होनी चाहिए';
  }

  @override
  String get authConsentRequired =>
      'आगे बढ़ने के लिए शर्तों और प्राइवेसी पॉलिसी से सहमति दें।';

  @override
  String get authSessionExpired =>
      'आपका लॉग इन ख़त्म हो गया है। फिर से लॉग इन करें।';

  @override
  String get authProfileTitle => 'अपनी प्रोफ़ाइल पूरी करें';

  @override
  String get authProfileSubtitle =>
      'अकाउंट तैयार करने के लिए बस थोड़ी सी जानकारी चाहिए।';

  @override
  String get authFullName => 'पूरा नाम';

  @override
  String get authEmail => 'ईमेल';

  @override
  String get authDateOfBirth => 'जन्म की तारीख';

  @override
  String get authCreateAccount => 'अकाउंट बनाएँ';

  @override
  String consentAgree(String terms, String privacy) {
    return 'मैं $terms और $privacy से सहमत हूँ';
  }

  @override
  String get consentTerms => 'शर्तों';

  @override
  String get consentPrivacy => 'प्राइवेसी पॉलिसी';

  @override
  String get otpTitle => 'अपना नंबर वेरिफ़ाई करें';

  @override
  String otpSubtitle(int length, String phone) {
    return '$phone पर भेजा गया $length अंकों का OTP डालें।';
  }

  @override
  String get otpFieldLabel => 'OTP';

  @override
  String get otpVerify => 'वेरिफ़ाई करें';

  @override
  String get otpInvalidated =>
      'यह OTP अब काम नहीं करेगा। आगे बढ़ने के लिए नया OTP मँगाएँ।';

  @override
  String get otpStartOver => 'फिर से शुरू करें';

  @override
  String otpResendLocked(String time) {
    return 'बहुत बार OTP माँगा गया। $time बाद फिर कोशिश करें, या फिर से शुरू करें।';
  }

  @override
  String get otpDidntGetIt => 'OTP नहीं मिला?';

  @override
  String get otpResend => 'OTP दोबारा भेजें';

  @override
  String otpResendIn(String time) {
    return '$time बाद OTP दोबारा भेजें';
  }

  @override
  String otpWrongLength(int length) {
    return '$length अंकों का OTP डालें';
  }

  @override
  String get otpDigitsOnly => 'OTP में सिर्फ़ अंक होने चाहिए';

  @override
  String get homeNavHome => 'होम';

  @override
  String get homeNavActivity => 'राइड';

  @override
  String get homeNavAccount => 'अकाउंट';

  @override
  String get shellThanksForRating => 'ट्रिप को रेटिंग देने के लिए शुक्रिया।';

  @override
  String get accountYourProfile => 'आपकी प्रोफ़ाइल';

  @override
  String get accountLogOut => 'लॉग आउट';

  @override
  String get accountDelete => 'अकाउंट डिलीट करें';

  @override
  String get accountDeleting => 'अकाउंट डिलीट हो रहा है…';

  @override
  String get accountDeleteConfirmTitle => 'अपना अकाउंट डिलीट करें?';

  @override
  String get accountDeleteExplanation =>
      'हम आपका नाम, ईमेल, फ़ोन नंबर, सेव की हुई कारें और हाल के पिकअप हटा देंगे, और हर फ़ोन से आपको लॉग आउट कर देंगे। पिछली राइड और पेमेंट का रिकॉर्ड रखा जाएगा, पर आपकी डिटेल्स के बिना, क्योंकि कानून के हिसाब से इसे रखना ज़रूरी है। डिलीट करने के बाद अकाउंट वापस नहीं आएगा।';

  @override
  String get accountDeleteFailed =>
      'अकाउंट डिलीट नहीं हो पाया। फिर से कोशिश करें।';

  @override
  String get carsMyCars => 'मेरी कारें';

  @override
  String get carsLoading => 'आपकी कारें लोड हो रही हैं…';

  @override
  String get carsLoadFailed => 'आपकी कारें लोड नहीं हो पाईं।';

  @override
  String get carsRetry => 'फिर कोशिश करें';

  @override
  String get carsNoneYet =>
      'अभी कोई कार सेव नहीं है — एक बार अपनी कार जोड़ें, फिर हर ट्रिप पर उसे चुनें।';

  @override
  String get carsRemove => 'कार हटाएँ';

  @override
  String get carsAdd => 'कार जोड़ें';

  @override
  String get carsYourCar => 'आपकी कार';

  @override
  String get carsSelectYourCar => 'अपनी कार चुनें';

  @override
  String get carsAddSubtitle => 'एक बार सेव करें, हर बुकिंग पर काम आएगी।';

  @override
  String get carsRegistrationLabel => 'कार नंबर';

  @override
  String get carsRegistrationHint => 'जैसे KA 01 AB 1234';

  @override
  String get carsRegistrationIncomplete => 'कार का पूरा नंबर डालें।';

  @override
  String get carsSaving => 'सेव हो रही है…';

  @override
  String get carsSave => 'कार सेव करें';

  @override
  String get carsSaveFailed => 'कार सेव नहीं हो पाई। फिर से कोशिश करें।';

  @override
  String get carsUnexpectedResponse => 'सर्वर से सही जवाब नहीं आया।';

  @override
  String carsRequestFailed(int status) {
    return 'सेव की हुई कारों की रिक्वेस्ट नहीं हो पाई ($status)।';
  }

  @override
  String get updateTitle => 'MOJUD अपडेट करें';

  @override
  String get updateBody =>
      'ऐप का यह वर्ज़न पुराना हो गया है। ड्राइवर बुक करते रहने के लिए नया वर्ज़न इंस्टॉल करें। आपका अकाउंट और राइड सुरक्षित हैं।';

  @override
  String get updateGetLatest => 'नया वर्ज़न डाउनलोड करें';

  @override
  String updateDownloadFrom(String site) {
    return '$site से डाउनलोड करें';
  }

  @override
  String updateOpenFailed(String site) {
    return 'ब्राउज़र नहीं खुला। लिंक कॉपी करके किसी ब्राउज़र में खोलें: $site';
  }

  @override
  String get updateCopyLink => 'लिंक कॉपी करें';

  @override
  String get updateLinkCopied => 'लिंक कॉपी हो गया';

  @override
  String get notifChannelName => 'राइड अपडेट';

  @override
  String get notifChannelDescription =>
      'ड्राइवर तय होने और आपकी राइड में बाकी बदलावों की सूचना।';

  @override
  String get homeYourProfile => 'आपकी प्रोफ़ाइल';

  @override
  String homeHello(String name) {
    return 'नमस्ते, $name';
  }

  @override
  String get homeWhereTo => 'आज आपको कहाँ ले चलें?';

  @override
  String get homeBookADriver => 'ड्राइवर बुक करें';

  @override
  String get homeHowTitle => 'आपकी कार, हमारा ड्राइवर';

  @override
  String get homeHowBody => 'ड्राइवर आपके पिकअप पर आकर आपकी अपनी कार चलाता है।';

  @override
  String get homeHowStepPick => 'ट्रिप चुनें';

  @override
  String get homeHowStepSet => 'पिकअप और समय चुनें';

  @override
  String get homeHowStepDrive => 'ड्राइवर आपकी कार चलाए';

  @override
  String homePayFeeBeforeBooking(String fee) {
    return 'नई बुकिंग से पहले पिछली राइड के $fee कैंसल चार्ज का पेमेंट करें।';
  }

  @override
  String get homePayNow => 'अभी पेमेंट करें';

  @override
  String get homeRetry => 'फिर से भेजें';

  @override
  String homeNotBookedRoundTrip(String reason) {
    return 'आपकी राउंड ट्रिप बुक नहीं हुई। $reason';
  }

  @override
  String homeNotBookedMultiStop(String reason) {
    return 'आपकी मल्टी-स्टॉप ट्रिप बुक नहीं हुई। $reason';
  }

  @override
  String homeNotBookedOneWay(String reason) {
    return 'आपकी वन-वे ट्रिप बुक नहीं हुई। $reason';
  }

  @override
  String homeBookedRoundTrip(int hours, String car) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours घंटे',
      one: '1 घंटा',
    );
    return 'राउंड ट्रिप बुक हो गई: $_temp0, आपकी कार $car में।';
  }

  @override
  String homeBookedMultiStop(int count, String car) {
    return 'मल्टी-स्टॉप ट्रिप बुक हो गई: $count स्टॉप, आपकी कार $car में।';
  }

  @override
  String homeBookedOneWay(int minutes, String car, String destination) {
    return 'वन-वे ट्रिप बुक हो गई: $destination तक लगभग $minutes मिनट, आपकी कार $car में।';
  }

  @override
  String get tripPickerOneWayTitle => 'वन-वे ट्रिप';

  @override
  String get tripPickerOneWaySubtitle => 'एक जगह तक ड्रॉप।';

  @override
  String get tripPickerRoundTripTitle => 'राउंड ट्रिप';

  @override
  String get tripPickerRoundTripSubtitle =>
      'घंटे के हिसाब से ड्राइवर, जाना और वापस आना।';

  @override
  String get tripPickerMultiStopTitle => 'मल्टी-स्टॉप ट्रिप';

  @override
  String get tripPickerMultiStopSubtitle => 'कई स्टॉप, एक ड्राइवर।';

  @override
  String tripPickerSelected(String trip) {
    return 'चुना गया: $trip';
  }

  @override
  String get tripStartStartingPoint => 'पिकअप';

  @override
  String get tripStartSetStartingPoint => 'पिकअप चुनें';

  @override
  String get tripStartStartingPointTapToChange =>
      'पिकअप · बदलने के लिए टैप करें';

  @override
  String get tripStartPickupTapToChange => 'पिकअप · बदलने के लिए टैप करें';

  @override
  String get tripStartFromCurrentLocation =>
      'आपकी अभी की लोकेशन · बदलने के लिए टैप करें';

  @override
  String get tripStartFindingLocation => 'आपकी लोकेशन ढूँढ रहे हैं…';

  @override
  String get tripStartPickup => 'पिकअप';

  @override
  String get tripStartChooseStartingPoint => 'पिकअप चुनें';

  @override
  String get tripStartChoosePickup => 'पिकअप चुनें';

  @override
  String get tripStartNoCurrentLocation => 'आपकी अभी की लोकेशन नहीं ले पाए';

  @override
  String get serviceAreaOutside =>
      'अभी हम सिर्फ़ दिल्ली NCR (दिल्ली, गुरुग्राम, फ़रीदाबाद, नोएडा और आस-पास के इलाके) में सर्विस देते हैं — इसी इलाके में कोई लोकेशन चुनें।';

  @override
  String get scheduleSelectDate => 'तारीख चुनें';

  @override
  String get scheduleSelectTime => 'समय चुनें';

  @override
  String get scheduleTooSoon =>
      'शुरू होने का समय अभी से कम से कम 45 मिनट बाद का चुनें, ताकि कोई ड्राइवर राइड ले सके।';

  @override
  String get timeSlotTitle => 'शुरू होने का समय चुनें';

  @override
  String get timeSlotSubtitle => 'ट्रिप हर 15 मिनट के स्लॉट पर शुरू होती है।';

  @override
  String get hoursFewer => 'घंटे कम करें';

  @override
  String get hoursMore => 'घंटे बढ़ाएँ';

  @override
  String hoursUnit(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'घंटे',
      one: 'घंटा',
    );
    return '$_temp0';
  }

  @override
  String hoursChip(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours घंटे',
      one: '1 घंटा',
    );
    return '$_temp0';
  }

  @override
  String get fareSummaryEstimatedFrom => 'अंदाज़न किराया, कम से कम';

  @override
  String get fareSummaryEstimated => 'अंदाज़न किराया';

  @override
  String fareSummaryForHours(int hours) {
    return '$hours घंटे के लिए';
  }

  @override
  String get roundTripTitle => 'ट्रिप की जानकारी';

  @override
  String get roundTripHowLong => 'कितने घंटे के लिए?';

  @override
  String get roundTripHowLongSubtitle =>
      'ड्राइवर को घंटे के हिसाब से बुक करें।';

  @override
  String get roundTripWhen => 'कब?';

  @override
  String get roundTripWhenSubtitle => 'ट्रिप शुरू होने की तारीख और समय चुनें।';

  @override
  String get roundTripChoosePickupToContinue => 'आगे बढ़ने के लिए पिकअप चुनें।';

  @override
  String get roundTripConfirm => 'बुकिंग कन्फ़र्म करें';

  @override
  String get roundTripFareNoteTitle => 'अंदाज़न किराया';

  @override
  String get roundTripFareNoteBody =>
      'आख़िरी पिकअप या ड्रॉप लोकेशन और लगे समय के हिसाब से किराया बदल सकता है। बुक किए घंटों से ज़्यादा समय का पैसा घंटे के हिसाब से लगेगा।';

  @override
  String get roundTripFareNoteOk => 'ठीक है';

  @override
  String get bookingDetailsWhichCar => 'कौन सी कार?';

  @override
  String get bookingDetailsWhichCarSubtitle =>
      'ड्राइवर आपकी ही कार चलाएगा — एक चुनें।';

  @override
  String get bookingDetailsChooseCarToContinue =>
      'आगे बढ़ने के लिए अपनी कार चुनें।';

  @override
  String get multiStopTitle => 'अपनी ट्रिप प्लान करें';

  @override
  String get multiStopWhenStart => 'कब शुरू करें?';

  @override
  String get multiStopWhenStartSubtitle => 'ड्राइवर आपको पिकअप पर मिलेगा।';

  @override
  String get multiStopStops => 'स्टॉप';

  @override
  String get multiStopStopsSubtitle =>
      'हर काम क्रम से लिखें — कहाँ जाना है, वहाँ क्या करना है और कब निकलना है।';

  @override
  String get multiStopAddStop => 'स्टॉप जोड़ें';

  @override
  String multiStopMaxStops(int max) {
    return 'ज़्यादा से ज़्यादा $max स्टॉप';
  }

  @override
  String get multiStopConfirm => 'ट्रिप कन्फ़र्म करें';

  @override
  String multiStopSummary(int count, String date, String time) {
    return '$count स्टॉप · $date, $time तक ख़त्म';
  }

  @override
  String get multiStopStopsIncomplete =>
      'आगे बढ़ने के लिए हर स्टॉप की लोकेशन, काम और निकलने का समय भरें।';

  @override
  String get multiStopSetStopLocation => 'स्टॉप की लोकेशन चुनें';

  @override
  String get multiStopStopLocation => 'स्टॉप की लोकेशन';

  @override
  String get multiStopLeaveByAfterStart =>
      'निकलने का समय ट्रिप शुरू होने के बाद का होना चाहिए।';

  @override
  String multiStopLeaveByAfterStop(int stop) {
    return 'निकलने का समय स्टॉप $stop के बाद का होना चाहिए।';
  }

  @override
  String stopTitle(int index) {
    return 'स्टॉप $index';
  }

  @override
  String stopMoveEarlier(int index) {
    return 'स्टॉप $index को ऊपर करें';
  }

  @override
  String stopMoveLater(int index) {
    return 'स्टॉप $index को नीचे करें';
  }

  @override
  String stopRemove(int index) {
    return 'स्टॉप $index हटाएँ';
  }

  @override
  String get stopChooseLocation => 'लोकेशन चुनें';

  @override
  String get stopTaskLabel => 'ड्राइवर को यहाँ क्या करना है?';

  @override
  String get stopTaskHint => 'जैसे: रिसेप्शन से पार्सल लेना';

  @override
  String get stopLeaveBy => 'कब निकलना है';

  @override
  String get oneWayRouteTitle => 'कहाँ जाना है?';

  @override
  String get oneWayRouteField => 'ड्रॉप की जगह';

  @override
  String get oneWayDetailsWhenTitle => 'कब?';

  @override
  String get oneWayDetailsWhenSubtitle =>
      'ट्रिप शुरू होने की तारीख और समय चुनें।';

  @override
  String get oneWayDetailsCarTitle => 'कौन सी कार?';

  @override
  String get oneWayDetailsCarSubtitle =>
      'ड्राइवर आपकी ही कार चलाएगा — एक चुनें।';

  @override
  String get oneWayDetailsChooseCar => 'आगे बढ़ने के लिए अपनी कार चुनें।';

  @override
  String get oneWayReviewTitle => 'ट्रिप चेक करें';

  @override
  String get oneWayReviewPlanTitle => 'आपका प्लान';

  @override
  String get oneWayReviewPlanSubtitle => 'कुछ भी बदलना हो तो वापस जाएँ।';

  @override
  String get oneWayReviewStarts => 'शुरू';

  @override
  String get oneWayReviewCar => 'कार';

  @override
  String get oneWayReviewTripTimeTitle => 'ट्रिप का समय';

  @override
  String get oneWayReviewTripTimeSubtitle =>
      'आपके चुने हुए समय के हिसाब से अंदाज़ा।';

  @override
  String get oneWayReviewCheckingTripTime => 'ट्रिप का समय देख रहे हैं…';

  @override
  String get oneWayReviewTripTimeNeeded =>
      'बुक करने के लिए ट्रिप का समय चाहिए — ऊपर फिर से कोशिश करें।';

  @override
  String get oneWayReviewCheckingDriveTime => 'ड्राइव का समय देख रहे हैं…';

  @override
  String oneWayReviewAbout(String duration) {
    return 'लगभग $duration';
  }

  @override
  String get oneWayReviewTripTimeFailed => 'ट्रिप का समय पता नहीं चल पाया।';

  @override
  String get oneWayReviewRetry => 'फिर से देखें';

  @override
  String get oneWayReviewConfirm => 'बुकिंग कन्फ़र्म करें';

  @override
  String get pickupTitle => 'पिकअप चुनें';

  @override
  String get pickupField => 'पिकअप की जगह';

  @override
  String get pickupStartTitle => 'ट्रिप कहाँ से शुरू होगी?';

  @override
  String get pickupStartField => 'पिकअप की जगह';

  @override
  String get pickupSearchHint => 'कोई जगह खोजें';

  @override
  String get pickupSelectOnMap => 'मैप पर चुनें';

  @override
  String get pickupMapSubtitle => 'पिन ठीक करने के लिए मैप खुलेगा';

  @override
  String get pickupRecent => 'हाल की जगहें';

  @override
  String get pickupEmptyWithLocation =>
      'कोई जगह खोजें, या अपनी अभी की लोकेशन लें।';

  @override
  String get pickupEmptyWithMap => 'कोई जगह खोजें, या मैप पर चुनें।';

  @override
  String get pickupCantPin => 'यह जगह मैप पर नहीं मिली। कोई दूसरा नतीजा चुनें।';

  @override
  String get locationUseCurrent => 'मेरी अभी की लोकेशन लें';

  @override
  String get mapPickerTitle => 'मैप पर पिन करें';

  @override
  String get mapPickerCaption => 'पिकअप यहाँ';

  @override
  String get mapPickerMoveHint => 'पिन लगाने के लिए मैप खिसकाएँ';

  @override
  String get mapPickerConfirm => 'यही लोकेशन लें';

  @override
  String get mapPickerNotSetUp =>
      'मैप अभी सेट नहीं है। वापस जाकर अपना पिकअप खोजें।';

  @override
  String get mapPickerLoadFailed =>
      'मैप लोड नहीं हो पाया। इंटरनेट चेक करें, या देखें कि Maps API key इस साइट पर चलती है।';

  @override
  String get routeFrom => 'कहाँ से';

  @override
  String get routeTo => 'कहाँ तक';

  @override
  String get routeMapUnavailable => 'मैप नहीं दिख पा रहा';

  @override
  String get locationNoConnection =>
      'मैप सर्विस से कनेक्ट नहीं हो पा रहा। इंटरनेट चेक करके फिर से कोशिश करें।';

  @override
  String get locationServiceUnavailable =>
      'मैप सर्विस अभी नहीं चल रही। फिर से कोशिश करें।';

  @override
  String get locationUnexpectedReply => 'मैप सर्विस से सही जवाब नहीं आया।';

  @override
  String get locationDriveTimeNotSetUp =>
      'इस वर्ज़न में ड्राइव के समय का अंदाज़ा सेट नहीं है।';

  @override
  String get locationNotFound => 'आपकी लोकेशन नहीं मिली। अपना पिकअप खोजें।';

  @override
  String get locationTurnedOff =>
      'फ़ोन की लोकेशन बंद है। अभी की जगह लेने के लिए इसे चालू करें।';

  @override
  String get locationPermissionDeclined =>
      'लोकेशन की परमिशन नहीं मिली। अपना पिकअप खोजें।';

  @override
  String get locationBlocked =>
      'लोकेशन की परमिशन बंद है। सेटिंग्स में चालू करें, या जगह खोजें।';

  @override
  String get placesSessionExpired =>
      'आपका लॉग इन ख़त्म हो गया है। जगह खोजने के लिए फिर से लॉग इन करें।';

  @override
  String get placesNotSetUp => 'मैप सर्च अभी सेट नहीं है।';

  @override
  String get placesAuthFailed =>
      'मैप सर्च शुरू नहीं हो पाया। फिर से कोशिश करें।';

  @override
  String get placesAuthUnexpected => 'मैप सर्च से सही जवाब नहीं आया।';

  @override
  String get placesAuthNoToken => 'मैप सर्च से सही जवाब नहीं आया।';

  @override
  String get rideYourDriver => 'आपके ड्राइवर';

  @override
  String rideIsYourDriver(String name) {
    return '$name आपके ड्राइवर हैं';
  }

  @override
  String rideAtYourPickup(String name) {
    return '$name आपके पिकअप पर पहुँच गए हैं';
  }

  @override
  String rideIsDriving(String name) {
    return '$name गाड़ी चला रहे हैं।';
  }

  @override
  String get rideDetailsTitleMissing => 'आपकी राइड';

  @override
  String get rideDetailsNotInList => 'यह राइड अब आपकी लिस्ट में नहीं है।';

  @override
  String rideDetailsCancelledPayFee(String fee) {
    return 'आपकी राइड कैंसल हो गई। $fee कैंसल चार्ज का पेमेंट करें।';
  }

  @override
  String get rideDetailsCancelled => 'आपकी राइड कैंसल हो गई।';

  @override
  String get rideDetailsCancelFailed => 'राइड कैंसल नहीं हो पाई।';

  @override
  String get rideDetailsTripEnded => 'आपकी ट्रिप ख़त्म हो गई।';

  @override
  String get rideDetailsEndFailed => 'ट्रिप ख़त्म नहीं हो पाई।';

  @override
  String get rideDetailsPaymentReceived => 'पेमेंट मिल गया। शुक्रिया!';

  @override
  String get rideDetailsThanksForRating =>
      'ट्रिप को रेटिंग देने के लिए शुक्रिया।';

  @override
  String get rideDetailsCancelRide => 'राइड कैंसल करें';

  @override
  String get rideDetailsFindingDriver => 'आपके लिए ड्राइवर ढूँढ रहे हैं';

  @override
  String get rideDetailsFindingDriverDetail =>
      'कोई ड्राइवर राइड लेते ही हम आपको बता देंगे।';

  @override
  String rideDetailsPickupWhen(String when) {
    return 'पिकअप: $when';
  }

  @override
  String get rideDetailsShareStartCode =>
      'मिलने पर ड्राइवर को स्टार्ट कोड बताएँ।';

  @override
  String get rideDetailsOnYourTrip => 'आपकी ट्रिप चल रही है';

  @override
  String rideDetailsStartedWhen(String when) {
    return 'शुरू हुई: $when';
  }

  @override
  String get rideDetailsTripEndedEarly => 'ट्रिप जल्दी ख़त्म हुई';

  @override
  String get rideDetailsTripCompleted => 'ट्रिप पूरी हुई';

  @override
  String get rideDetailsRideCancelled => 'राइड कैंसल हुई';

  @override
  String get rideDetailsWasCancelled => 'यह राइड कैंसल हो गई।';

  @override
  String get rideDetailsNoDriverDetail =>
      'समय पर किसी ड्राइवर ने राइड नहीं ली। फिर से बुक करें।';

  @override
  String get rideDetailsPayFeeTitle => 'कैंसल चार्ज का पेमेंट करें';

  @override
  String get rideDetailsPayTripTitle => 'अपनी ट्रिप का पेमेंट करें';

  @override
  String rideDetailsPayFeeSubtitle(String amount) {
    return 'आपने ड्राइवर के पिकअप पर पहुँचने के बाद कैंसल किया। किसी भी UPI ऐप से $amount का पेमेंट करें: GPay, PhonePe, Paytm या अपने बैंक का ऐप।';
  }

  @override
  String rideDetailsPayTripSubtitle(String amount) {
    return 'किसी भी UPI ऐप से $amount का पेमेंट करें: GPay, PhonePe, Paytm या अपने बैंक का ऐप।';
  }

  @override
  String get rideDetailsWaitingForUpi => 'UPI का इंतज़ार है…';

  @override
  String rideDetailsPayByUpi(String amount) {
    return 'UPI से $amount का पेमेंट करें';
  }

  @override
  String get rideDetailsYouRated => 'आपकी रेटिंग ';

  @override
  String get rideDetailsRateDriver => 'ड्राइवर को रेटिंग दें';

  @override
  String get rideDetailsHowWasTrip => 'आपकी ट्रिप कैसी रही?';

  @override
  String rideDetailsHowWasTripWith(String name) {
    return '$name के साथ आपकी ट्रिप कैसी रही?';
  }

  @override
  String get rideDetailsRoute => 'रास्ता';

  @override
  String rideDetailsStopsPlanned(int count) {
    return '$count स्टॉप तय हैं';
  }

  @override
  String get rideDetailsRoutePickup => 'पिकअप';

  @override
  String rideDetailsRouteStop(int number) {
    return 'स्टॉप $number';
  }

  @override
  String get rideDetailsRouteDestination => 'ड्रॉप';

  @override
  String rideDetailsLeaveBy(String time) {
    return '$time तक निकलें';
  }

  @override
  String get rideDetailsTripDetails => 'ट्रिप की जानकारी';

  @override
  String get rideDetailsInfoTrip => 'ट्रिप';

  @override
  String get rideDetailsInfoStarts => 'शुरू';

  @override
  String get rideDetailsInfoBookedFor => 'बुक किया समय';

  @override
  String get rideDetailsInfoEstDuration => 'अंदाज़न समय';

  @override
  String get rideDetailsInfoCar => 'कार';

  @override
  String get rideFare => 'किराया';

  @override
  String get rideBookedFare => 'बुकिंग का किराया';

  @override
  String get rideCancellationFee => 'कैंसल चार्ज';

  @override
  String get rideDetailsTimeline => 'टाइमलाइन';

  @override
  String get rideTimelineBooked => 'बुक हुई';

  @override
  String get rideTimelineDriverAssigned => 'ड्राइवर मिला';

  @override
  String get rideTimelineDriverArrived => 'ड्राइवर पहुँचे';

  @override
  String get rideTimelineTripStarted => 'ट्रिप शुरू हुई';

  @override
  String get rideTimelineEndedEarly => 'जल्दी ख़त्म हुई';

  @override
  String get rideTimelineCompleted => 'पूरी हुई';

  @override
  String get rideTimelineNoDriverDetail =>
      'समय पर किसी ड्राइवर ने राइड नहीं ली।';

  @override
  String get rideTrackingWaiting => 'ड्राइवर की लोकेशन का इंतज़ार है';

  @override
  String get rideTrackingFinding => 'ड्राइवर की लोकेशन देख रहे हैं…';

  @override
  String rideTrackingOnTrip(String name) {
    return '$name आपकी ट्रिप पर हैं';
  }

  @override
  String rideTrackingLocation(String name) {
    return '$name की लोकेशन';
  }

  @override
  String rideTrackingAway(String name, String distance) {
    return '$name $distance दूर हैं';
  }

  @override
  String rideTrackingUpdated(String where, String age) {
    return '$where · अपडेट: $age';
  }

  @override
  String rideDistanceMeters(int meters) {
    return '$meters मी';
  }

  @override
  String rideDistanceKm(String km) {
    return '$km किमी';
  }

  @override
  String get rideAgeJustNow => 'अभी';

  @override
  String rideAgeSeconds(int seconds) {
    return '$seconds सेकंड पहले';
  }

  @override
  String rideAgeMinutes(int minutes) {
    return '$minutes मिनट पहले';
  }

  @override
  String rideAgeHours(int hours) {
    return '$hours घंटे पहले';
  }

  @override
  String get rideErrorNotFound => 'यह राइड अब नहीं मिल रही।';

  @override
  String get rideErrorCancelHasFee =>
      'अब कैंसल करने पर चार्ज लगेगा। नीचे खींचकर रिफ़्रेश करें, फिर कोशिश करें।';

  @override
  String get rideErrorCannotCancel =>
      'यह राइड शुरू हो चुकी है या ख़त्म हो चुकी है, इसलिए अब कैंसल नहीं हो सकती।';

  @override
  String get rideErrorNotInProgress => 'यह ट्रिप अब चालू नहीं है।';

  @override
  String get rideErrorAlreadyRated =>
      'इस राइड को पहले ही रेटिंग दी जा चुकी है।';

  @override
  String rideErrorInvalidRating(int max) {
    return '1 से 5 स्टार चुनें, और नोट $max अक्षरों से छोटा रखें।';
  }

  @override
  String get ridePayStillConfirming =>
      'बैंक से आपका पेमेंट अभी कन्फ़र्म हो रहा है। एक-दो मिनट में यहाँ पेमेंट हो गया दिखेगा।';

  @override
  String get ridePayFailed => 'पेमेंट नहीं हो पाया। फिर से कोशिश करें।';

  @override
  String get ridePayCancelled => 'पेमेंट कैंसल हुआ।';

  @override
  String get ridePayUnavailable => 'ऐप में पेमेंट अभी शुरू नहीं हुआ है।';

  @override
  String get ridePayUnderway =>
      'आपका पिछला पेमेंट अभी प्रोसेस हो रहा है। अपना UPI ऐप देखें, या कुछ मिनट बाद फिर कोशिश करें।';

  @override
  String get ridePayNotYet => 'इस राइड का पेमेंट अभी नहीं हो सकता।';

  @override
  String get receiptTitle => 'रसीद';

  @override
  String get receiptPaidThanks => 'पेमेंट हो गया। शुक्रिया!';

  @override
  String get receiptFareForTimeUsed => 'जितना समय लगा उसका किराया';

  @override
  String get receiptBaseFare => 'बेस किराया';

  @override
  String get receiptNightSurcharge => 'रात का चार्ज';

  @override
  String get receiptTotalPaid => 'कुल पेमेंट';

  @override
  String get receiptPaidVia => 'पेमेंट का तरीका';

  @override
  String get receiptReference => 'रेफ़रेंस';

  @override
  String get receiptOrder => 'ऑर्डर';

  @override
  String get receiptPaidAt => 'पेमेंट हुआ';

  @override
  String get endTripTitle => 'अभी ट्रिप ख़त्म करें?';

  @override
  String get endTripByTheHour =>
      'जितना समय लगा, उसका पैसा घंटे के हिसाब से लगेगा। शुरू हुआ हर घंटा पूरा गिना जाएगा।';

  @override
  String endTripOvertime(int minutes) {
    return 'अगर बुक किया समय निकल चुका है, तो $minutes मिनट की छूट के बाद ज़्यादा घंटों का पैसा भी लगेगा।';
  }

  @override
  String get endTripKeepGoing => 'ट्रिप जारी रखें';

  @override
  String get endTripNow => 'अभी ट्रिप ख़त्म करें';

  @override
  String get startCodeTitle => 'स्टार्ट कोड';

  @override
  String get startCodeHint => 'मिलने पर यह कोड अपने ड्राइवर को बताएँ।';

  @override
  String startCodeSemantics(String digits) {
    return 'स्टार्ट कोड $digits';
  }

  @override
  String get driverRowCall => 'ड्राइवर को कॉल करें';

  @override
  String driverRowPhotoOf(String name) {
    return '$name की फ़ोटो';
  }

  @override
  String starsOutOfFive(int stars) {
    return '5 में से $stars स्टार';
  }

  @override
  String starsCount(int count) {
    return '$count स्टार';
  }

  @override
  String get starsWordPoor => 'ख़राब';

  @override
  String get starsWordNotGreat => 'कुछ ख़ास नहीं';

  @override
  String get starsWordOkay => 'ठीक-ठाक';

  @override
  String get starsWordGood => 'अच्छा';

  @override
  String get starsWordExcellent => 'बहुत बढ़िया';

  @override
  String get starsNoteHint => 'ड्राइवर के लिए कुछ लिखें (ज़रूरी नहीं)';

  @override
  String get starsSubmit => 'रेटिंग भेजें';

  @override
  String get liveMapPickup => 'पिकअप';

  @override
  String get liveMapYourDriver => 'आपका ड्राइवर';

  @override
  String get activityTitle => 'मेरी राइड';

  @override
  String get activityTabUpcoming => 'आने वाली';

  @override
  String get activityTabCompleted => 'पिछली';

  @override
  String get activityNoUpcomingTitle => 'कोई आने वाली राइड नहीं';

  @override
  String get activityNoUpcomingBody =>
      'होम से बुक की गई राइड पूरी होने तक यहाँ दिखेंगी।';

  @override
  String get activityNoCompletedTitle => 'अभी तक कोई राइड पूरी नहीं हुई';

  @override
  String get activityNoCompletedBody =>
      'पूरी हुई ट्रिप और उनका किराया यहाँ दिखेगा।';

  @override
  String get activityLoadFailed => 'आपकी राइड लोड नहीं हो पाईं';

  @override
  String get rateTitle => 'आपकी ट्रिप कैसी रही?';

  @override
  String rateTitleWithDriver(String name) {
    return '$name के साथ आपकी ट्रिप कैसी रही?';
  }

  @override
  String get rateNotNow => 'अभी नहीं';

  @override
  String rideCardStopCount(int count) {
    return '$count स्टॉप';
  }

  @override
  String get rideCardTripCompleted => 'ट्रिप पूरी हुई';

  @override
  String rideCardDrivenBy(String name) {
    return '$name ने गाड़ी चलाई';
  }

  @override
  String rideCardEndedEarly(String charge) {
    return 'ट्रिप जल्दी ख़त्म हुई। $charge';
  }

  @override
  String get rideCardYouRated => 'आपकी रेटिंग';

  @override
  String get rideCardRateTrip => 'ट्रिप को रेटिंग दें';

  @override
  String get rideCardCancelled => 'यह राइड कैंसल हो गई।';

  @override
  String get rideCardCancellationFee => 'कैंसल चार्ज';

  @override
  String get rideCardNoDriver =>
      'समय पर किसी ड्राइवर ने राइड नहीं ली। फिर से बुक करें।';

  @override
  String get rideCardWaitingForDriver =>
      'जैसे ही कोई ड्राइवर राइड लेगा, वह यहाँ दिखेगा।';

  @override
  String rideCardPayByUpi(String amount) {
    return 'UPI से $amount का पेमेंट करें';
  }

  @override
  String get rideCardPaid => 'पेमेंट हुआ';

  @override
  String get cancelSheetTitle => 'यह राइड कैंसल करें?';

  @override
  String cancelSheetFeeNowNamed(String name, String fee) {
    return '$name आपके पिकअप पर पहुँच गए हैं, इसलिए अब कैंसल करने पर $fee लगेंगे।';
  }

  @override
  String cancelSheetFeeNow(String fee) {
    return 'आपके ड्राइवर पिकअप पर पहुँच गए हैं, इसलिए अब कैंसल करने पर $fee लगेंगे।';
  }

  @override
  String get cancelSheetFree => 'कैंसल करना फ़्री है।';

  @override
  String cancelSheetFreeUntilPickup(String fee) {
    return 'ड्राइवर के पिकअप पर पहुँचने तक कैंसल करना फ़्री है। उसके बाद $fee लगेंगे।';
  }

  @override
  String cancelSheetFeeWarningNamed(String name) {
    return 'यह चार्ज अभी UPI से दें, या यह आपकी अगली राइड के पेमेंट में जुड़ जाएगा। $name को बताया जाएगा कि आपने कैंसल किया।';
  }

  @override
  String get cancelSheetFeeWarning =>
      'यह चार्ज अभी UPI से दें, या यह आपकी अगली राइड के पेमेंट में जुड़ जाएगा। आपके ड्राइवर को बताया जाएगा कि आपने कैंसल किया।';

  @override
  String cancelSheetWaitingNamed(String name) {
    return '$name आपके पिकअप पर इंतज़ार कर रहे हैं। उन्हें बताया जाएगा कि आपने कैंसल किया।';
  }

  @override
  String get cancelSheetWaiting =>
      'आपके ड्राइवर पिकअप पर इंतज़ार कर रहे हैं। उन्हें बताया जाएगा कि आपने कैंसल किया।';

  @override
  String cancelSheetAcceptedNamed(String name) {
    return '$name ने यह राइड ले ली है और उसी हिसाब से प्लान कर रहे हैं। उन्हें बताया जाएगा कि आपने कैंसल किया।';
  }

  @override
  String get cancelSheetAccepted =>
      'आपके ड्राइवर ने यह राइड ले ली है और उसी हिसाब से प्लान कर रहे हैं। उन्हें बताया जाएगा कि आपने कैंसल किया।';

  @override
  String get cancelSheetWhy =>
      'वजह बताएँ — इससे हमें सुधार करने में मदद मिलती है।';

  @override
  String get cancelSheetTellUsMore => 'और बताएँ (ज़रूरी नहीं)';

  @override
  String cancelSheetCancelAndPay(String fee) {
    return 'कैंसल करें और $fee दें';
  }

  @override
  String get cancelSheetCancelRide => 'राइड कैंसल करें';

  @override
  String get cancelSheetKeepRide => 'मेरी राइड रखें';

  @override
  String get helpTitle => 'मदद और सुरक्षा';

  @override
  String get helpCall112 => '112 पर कॉल करें';

  @override
  String get helpShareTrip => 'ट्रिप शेयर करें';

  @override
  String get helpContactSupport => 'सपोर्ट से बात करें';

  @override
  String get helpDialerFailed => 'डायलर नहीं खुल पाया। 112 डायल करें।';

  @override
  String get helpTripCopied => 'ट्रिप की जानकारी कॉपी हो गई';

  @override
  String get helpWhatsAppFailed => 'WhatsApp नहीं खुल पाया।';

  @override
  String get helpShareIntro => 'मेरी MOJUD ट्रिप';

  @override
  String helpShareWhen(String when) {
    return 'कब: $when';
  }

  @override
  String helpSharePickup(String place) {
    return 'पिकअप: $place';
  }

  @override
  String helpShareDriver(String name) {
    return 'ड्राइवर: $name';
  }

  @override
  String helpShareBooking(String id) {
    return 'बुकिंग: $id';
  }

  @override
  String helpShareDateTime(String weekday, int day, String month, String time) {
    String _temp0 = intl.Intl.selectLogic(weekday, {
      'mon': 'सोमवार',
      'tue': 'मंगलवार',
      'wed': 'बुधवार',
      'thu': 'गुरुवार',
      'fri': 'शुक्रवार',
      'sat': 'शनिवार',
      'sun': 'रविवार',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(month, {
      'jan': 'जनवरी',
      'feb': 'फ़रवरी',
      'mar': 'मार्च',
      'apr': 'अप्रैल',
      'may': 'मई',
      'jun': 'जून',
      'jul': 'जुलाई',
      'aug': 'अगस्त',
      'sep': 'सितंबर',
      'oct': 'अक्टूबर',
      'nov': 'नवंबर',
      'dec': 'दिसंबर',
      'other': '',
    });
    return '$_temp0, $day $_temp1, $time';
  }

  @override
  String get bookingErrorPayLastRide =>
      'नई बुकिंग से पहले अपनी पिछली राइड का पेमेंट करें।';

  @override
  String bookingErrorLoadFailed(int status) {
    return 'आपकी राइड लोड नहीं हो पाईं ($status)।';
  }

  @override
  String bookingErrorRequestFailed(int status) {
    return 'बुकिंग नहीं हो पाई ($status)।';
  }

  @override
  String get checkoutCouldNotStart => 'PhonePe शुरू नहीं हो पाया।';

  @override
  String get checkoutCouldNotOpen => 'PhonePe नहीं खुल पाया।';

  @override
  String get checkoutAndroidOnly => 'UPI से पेमेंट Android ऐप में ही होता है।';
}

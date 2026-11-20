// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'MOJUD Driver';

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
  String get commonNotAdded => 'नहीं जोड़ा';

  @override
  String get commonNotSet => 'नहीं चुना';

  @override
  String get errorNoConnection =>
      'सर्वर से कनेक्ट नहीं हो पा रहा। इंटरनेट चेक करके फिर से कोशिश करें।';

  @override
  String get errorUnexpectedReply =>
      'सर्वर से सही जवाब नहीं आया। फिर से कोशिश करें।';

  @override
  String get errorGeneric => 'कुछ गड़बड़ हो गई। फिर से कोशिश करें।';

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
  String get rideStatusRequested => 'नई रिक्वेस्ट';

  @override
  String get rideStatusAccepted => 'आने वाली';

  @override
  String get rideStatusArrived => 'पिकअप पर';

  @override
  String get rideStatusInProgress => 'ट्रिप चालू';

  @override
  String get rideStatusCompleted => 'पूरी हुई';

  @override
  String get rideStatusCancelled => 'कैंसल';

  @override
  String get rideStatusUnknown => 'स्टेटस पता नहीं';

  @override
  String get tripKindRoundTrip => 'राउंड ट्रिप';

  @override
  String get tripKindOneWay => 'वन-वे';

  @override
  String get tripKindMultiStop => 'मल्टी-स्टॉप';

  @override
  String get tripKindOther => 'ट्रिप';

  @override
  String get ridePaymentDue => 'पेमेंट बाकी';

  @override
  String get ridePaymentPaid => 'पेमेंट हो गया';

  @override
  String get ridePaymentPaidOut => 'बैंक में भेजा गया';

  @override
  String get rideCancelledAtPickup => 'कस्टमर ने पिकअप पर कैंसल किया';

  @override
  String get rideCancelledByCustomer => 'कस्टमर ने कैंसल किया';

  @override
  String get rideCancelledNoShow => 'कस्टमर नहीं आया';

  @override
  String get carTypeHatchback => 'हैचबैक';

  @override
  String get carTypeSedan => 'सेडान';

  @override
  String get carTypeSuv => 'SUV';

  @override
  String get carTypeLuxury => 'लग्ज़री';

  @override
  String get carTypeUnknown => 'कार';

  @override
  String get transmissionManual => 'मैनुअल';

  @override
  String get transmissionAutomatic => 'ऑटोमैटिक';

  @override
  String get transmissionBoth => 'मैनुअल और ऑटोमैटिक दोनों';

  @override
  String get genderMale => 'पुरुष';

  @override
  String get genderFemale => 'महिला';

  @override
  String get genderOther => 'अन्य';

  @override
  String get docStepVehicleTypeTitle => 'गाड़ी का टाइप';

  @override
  String get docStepVehicleTypeSubtitle => 'मैनुअल, ऑटोमैटिक या दोनों';

  @override
  String get docStepPhotoAndNameTitle => 'फ़ोटो और नाम';

  @override
  String get docStepPhotoAndNameSubtitle =>
      'सेल्फ़ी, पूरा नाम, जन्म की तारीख, लिंग';

  @override
  String get docStepAadhaarTitle => 'आधार कार्ड';

  @override
  String get docStepAadhaarSubtitle => 'DigiLocker से वेरिफ़ाई करें';

  @override
  String get docStepLicenseTitle => 'ड्राइविंग लाइसेंस';

  @override
  String get docStepLicenseSubtitle => 'लाइसेंस नंबर, तुरंत चेक होगा';

  @override
  String get docStepPermissionsTitle => 'परमिशन';

  @override
  String get docStepPermissionsSubtitle =>
      'दूसरे ऐप्स के ऊपर दिखना, बैकग्राउंड लोकेशन, बैटरी';

  @override
  String get docStepBankTitle => 'बैंक डिटेल्स';

  @override
  String get docStepBankSubtitle =>
      'आपकी कमाई किस खाते में आएगी, बैंक से वेरिफ़ाई';

  @override
  String get accountTitle => 'अकाउंट';

  @override
  String get accountLogOutConfirmTitle => 'लॉग आउट करें?';

  @override
  String get accountLogOutConfirmBody =>
      'आपकी ड्यूटी बंद हो जाएगी और इस फ़ोन पर राइड रिक्वेस्ट आनी बंद हो जाएँगी।';

  @override
  String get accountLogOut => 'लॉग आउट';

  @override
  String get accountSupportEmailSubject => 'ड्राइवर ऐप में मदद चाहिए';

  @override
  String accountWriteToUs(String email) {
    return 'हमें $email पर लिखें';
  }

  @override
  String get accountSectionDriving => 'ड्राइविंग';

  @override
  String get accountCarsYouDrive => 'आप कौन सी गाड़ी चलाते हैं';

  @override
  String get accountDrivingLicence => 'ड्राइविंग लाइसेंस';

  @override
  String get accountAadhaar => 'आधार';

  @override
  String accountAadhaarMasked(String last4) {
    return 'XXXX XXXX $last4';
  }

  @override
  String get accountDocuments => 'डॉक्यूमेंट';

  @override
  String get accountDocumentsSubtitle => 'जो जमा किया है उसे देखें या बदलें';

  @override
  String get accountSectionPayouts => 'पेआउट';

  @override
  String get accountNoBankAccount => 'कोई बैंक खाता नहीं जोड़ा';

  @override
  String accountBankAccount(String holder, String last4) {
    return '$holder · •••• $last4';
  }

  @override
  String get accountSectionHelp => 'मदद';

  @override
  String get accountContactSupport => 'सपोर्ट से बात करें';

  @override
  String get accountKycVerified => 'वेरिफ़ाइड ड्राइवर';

  @override
  String get accountKycSubmitted => 'डॉक्यूमेंट की जाँच चल रही है';

  @override
  String get accountKycRejected => 'डॉक्यूमेंट में कुछ ठीक करना है';

  @override
  String get accountKycIncomplete => 'डॉक्यूमेंट अधूरे हैं';

  @override
  String get accountKycUnknown => 'डॉक्यूमेंट का स्टेटस पता नहीं';

  @override
  String get accountDelete => 'अकाउंट डिलीट करें';

  @override
  String get accountDeleteConfirmTitle => 'अपना अकाउंट डिलीट करें?';

  @override
  String get accountDeleteExplanation =>
      'हम आपकी सेल्फ़ी, पहचान और लाइसेंस की जाँच, बैंक डिटेल्स और फ़ोन नंबर डिलीट कर देंगे, और हर फ़ोन से आपको लॉग आउट कर देंगे।\n\nआपकी चलाई राइड और पेमेंट का रिकॉर्ड रखा जाएगा, पर आपकी डिटेल्स के बिना, क्योंकि कानून के हिसाब से इसे रखना ज़रूरी है।\n\nजो कमाई अभी आपके बैंक में नहीं आई है, वह आपको ही मिलेगी: MOJUD उसे भेजेगा, इसलिए अगर कुछ बाकी है तो डिलीट करने से पहले सपोर्ट से बात कर लें।\n\nडिलीट करने के बाद अकाउंट वापस नहीं आएगा।';

  @override
  String get accountDeleteFailed =>
      'अकाउंट डिलीट नहीं हो पाया। फिर से कोशिश करें।';

  @override
  String get startTagline =>
      'कस्टमर की अपनी कार चलाएँ, अपने टाइम पर। ऑनलाइन होते ही पास की ट्रिप मिलने लगेंगी।';

  @override
  String get startDriving => 'ड्राइविंग शुरू करें';

  @override
  String get rideDetailTitleRequest => 'राइड रिक्वेस्ट';

  @override
  String get rideDetailTitle => 'राइड की जानकारी';

  @override
  String get rideDetailApproxNote =>
      'अभी सिर्फ़ इलाका दिख रहा है। राइड लेने के बाद पूरा पता, कार का नंबर और कस्टमर का नाम व नंबर दिखेगा।';

  @override
  String get rideDetailCustomerAfterAccept =>
      'राइड लेने के बाद कस्टमर का नाम और नंबर दिखेगा।';

  @override
  String rideDetailAtPickupSince(String time) {
    return '$time से पिकअप पर';
  }

  @override
  String rideDetailStartedAt(String time) {
    return '$time पर शुरू हुई';
  }

  @override
  String rideDetailDoneAt(String when) {
    return 'पूरी हुई: $when';
  }

  @override
  String rideDetailSpanUntil(String span, String time) {
    return '$span · ~$time तक';
  }

  @override
  String get rideDetailFareEstimated => 'अंदाज़न किराया';

  @override
  String get rideDetailFareTrip => 'ट्रिप का किराया';

  @override
  String get rideDetailStepAccepted => 'राइड ली';

  @override
  String get rideDetailStepDone => 'पूरी';

  @override
  String get rideDetailRoute => 'रास्ता';

  @override
  String rideDetailDistanceAway(String distance) {
    return '$distance दूर';
  }

  @override
  String get rideDetailNavigateDrop => 'ड्रॉप का रास्ता देखें';

  @override
  String get rideDetailNavigatePickup => 'पिकअप का रास्ता देखें';

  @override
  String get rideDetailCarHandover => 'कस्टमर पिकअप पर अपनी कार आपको दे देंगे।';

  @override
  String get rideDetailMapsFailed => 'इस फ़ोन पर मैप नहीं खुल पाया।';

  @override
  String rideDetailCancelReason(String reason) {
    return 'वजह: $reason';
  }

  @override
  String rideDetailCancellationFee(String fee) {
    return '$fee कैंसल चार्ज';
  }

  @override
  String get rideDetailRanOverTitle => 'ट्रिप बुक किए समय से ज़्यादा चली';

  @override
  String get rideDetailEndedEarlyTitle => 'कस्टमर ने ट्रिप जल्दी ख़त्म की';

  @override
  String get rideDetailPastBookedTime =>
      'बुक किया समय पूरा हो गया — अब ज़्यादा समय का पैसा कस्टमर से घंटे के हिसाब से लिया जाएगा।';

  @override
  String get rideDetailNoShowDialogTitle => 'कस्टमर नहीं आया?';

  @override
  String get rideDetailNoShowDialogBody =>
      'राइड \"कस्टमर नहीं आया\" लिखकर बंद हो जाएगी। कस्टमर को बताया जाएगा कि आपने पिकअप पर इंतज़ार किया, और इसे आपकी तरफ़ से कैंसल नहीं गिना जाएगा।';

  @override
  String get rideDetailKeepWaiting => 'इंतज़ार करें';

  @override
  String get rideDetailCloseRide => 'राइड बंद करें';

  @override
  String get rideDetailNoShowClosed => 'राइड बंद हुई — कस्टमर नहीं आया।';

  @override
  String get rideDetailNoShowTitle => 'कस्टमर अभी तक नहीं आया?';

  @override
  String get rideDetailNoShowOpen =>
      'आप राइड \"कस्टमर नहीं आया\" लिखकर बंद कर सकते हैं।';

  @override
  String rideDetailNoShowFrom(String time) {
    return 'अगर कस्टमर $time तक भी नहीं आता, तो आप राइड \"कस्टमर नहीं आया\" लिखकर बंद कर सकते हैं।';
  }

  @override
  String get rideDetailNoShowButton => 'कस्टमर नहीं आया';

  @override
  String get rideDetailSharingLocation =>
      'आपकी लाइव लोकेशन कस्टमर को दिख रही है';

  @override
  String get rideDetailNumberHidden => 'राइड के बाद नंबर छिपा दिया गया';

  @override
  String get rideDetailCallCustomer => 'कस्टमर को कॉल करें';

  @override
  String get rideDetailCallFailed => 'कॉल नहीं लग पाई।';

  @override
  String get rideDetailCustomerCar => 'कस्टमर की कार';

  @override
  String get rideDetailRateTitle => 'कस्टमर को रेटिंग दें';

  @override
  String get rideDetailRateNoteHint => 'अपने लिए नोट लिखें (ज़रूरी नहीं)';

  @override
  String get rideDetailRateSubmit => 'रेटिंग भेजें';

  @override
  String rideDetailYouRated(int stars) {
    return 'आपने $stars★ दिए';
  }

  @override
  String get rideDetailActionAccept => 'राइड लें';

  @override
  String get rideDetailActionArrive => 'पिकअप पर पहुँच गए';

  @override
  String get rideDetailActionStart => 'ट्रिप शुरू करें';

  @override
  String get rideDetailActionComplete => 'ट्रिप पूरी करें';

  @override
  String get rideDetailActionDecline => 'मना करें';

  @override
  String get rideDetailActionRelease => 'राइड छोड़ें';

  @override
  String get rideDetailAccepted =>
      'राइड आपकी हो गई — आने वाली राइड में दिखेगी।';

  @override
  String get rideDetailDeclined => 'रिक्वेस्ट हटा दी।';

  @override
  String get rideDetailReleased => 'राइड वापस कर दी।';

  @override
  String get rideDetailStarted => 'ट्रिप शुरू हो गई। ध्यान से चलाएँ!';

  @override
  String rideDetailCompletedEndedEarly(String amount) {
    return 'कस्टमर ने ट्रिप जल्दी ख़त्म की। अब वे अपने ऐप में UPI से $amount दे सकते हैं।';
  }

  @override
  String rideDetailCompletedRanOver(String charge) {
    return 'ट्रिप पूरी हुई। ट्रिप बुक किए समय से ज़्यादा चली, इसलिए कस्टमर अब अपने ऐप में UPI से $charge दे सकते हैं।';
  }

  @override
  String rideDetailCompleted(String amount) {
    return 'ट्रिप पूरी हुई। अब कस्टमर अपने ऐप में UPI से $amount दे सकते हैं।';
  }

  @override
  String get rideDetailConfirmCompleteTitle => 'ट्रिप पूरी करें?';

  @override
  String get rideDetailConfirmCompleteBody =>
      'पक्का करें कि ट्रिप ख़त्म हो गई है और कार कस्टमर को वापस मिल गई है।';

  @override
  String get rideDetailConfirmCompleteYes => 'पूरी करें';

  @override
  String get rideDetailConfirmReleaseTitle => 'यह राइड वापस करें?';

  @override
  String get rideDetailConfirmReleaseBody =>
      'यह आस-पास के दूसरे ड्राइवरों के पास चली जाएगी और आपकी लिस्ट से हट जाएगी।';

  @override
  String get rideDetailConfirmReleaseYes => 'वापस करें';

  @override
  String get rideDetailNotNow => 'अभी नहीं';

  @override
  String get rideDetailStartCodeTitle => 'स्टार्ट कोड डालें';

  @override
  String get rideDetailStartCodeBody =>
      'कस्टमर से उनके MOJUD ऐप में दिख रहा 4 अंकों का कोड पूछें।';

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
  String get helpWhatsAppFailed => 'इस फ़ोन पर WhatsApp नहीं खुल पाया।';

  @override
  String get helpShareIntro => 'मेरी MOJUD ट्रिप की जानकारी:';

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
  String helpShareDateTime(
    String weekday,
    String day,
    String month,
    String year,
    String time,
  ) {
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
    return '$_temp0, $day $_temp1 $year, $time';
  }

  @override
  String get ridesPanelTitle => 'मेरी राइड';

  @override
  String get ridesPanelTabUpcoming => 'आने वाली';

  @override
  String get ridesPanelTabOngoing => 'चालू';

  @override
  String get ridesPanelTabCompleted => 'पूरी';

  @override
  String get ridesPanelTabCancelled => 'कैंसल';

  @override
  String get ridesPanelEmptyUpcomingTitle => 'कोई आने वाली राइड नहीं';

  @override
  String get ridesPanelEmptyUpcomingBody =>
      'होम टैब से ली गई राइड यहाँ दिखेंगी।';

  @override
  String get ridesPanelEmptyOngoingTitle => 'अभी कोई ट्रिप नहीं चल रही';

  @override
  String get ridesPanelEmptyOngoingBody =>
      'पिकअप पर पहुँचकर आने वाली राइड में \"पिकअप पर पहुँच गए\" दबाएँ।';

  @override
  String get ridesPanelEmptyCompletedTitle => 'अभी तक कोई राइड पूरी नहीं हुई';

  @override
  String get ridesPanelEmptyCompletedBody =>
      'पूरी हुई ट्रिप और उनका किराया यहाँ दिखेगा।';

  @override
  String get ridesPanelEmptyCancelledTitle => 'कोई कैंसल राइड नहीं';

  @override
  String get ridesPanelEmptyCancelledBody =>
      'राइड लेने के बाद अगर कस्टमर उसे कैंसल करे, तो वह यहाँ दिखेगी।';

  @override
  String get ridesPanelLoadFailed => 'आपकी राइड लोड नहीं हो पाईं';

  @override
  String get myRidesInvalidRating => 'कस्टमर के लिए 1 से 5 स्टार चुनें।';

  @override
  String get myRidesCantRate => 'इस राइड को अभी रेटिंग नहीं दी जा सकती।';

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
  String fmtMeters(int meters) {
    return '$meters मी';
  }

  @override
  String fmtKilometers(String km) {
    return '$km किमी';
  }

  @override
  String get fmtNow => 'अभी';

  @override
  String fmtTimeAgo(String duration) {
    return '$duration पहले';
  }

  @override
  String fmtTimeIn(String duration) {
    return '$duration में';
  }

  @override
  String fmtSpanHire(int hours) {
    return '$hours घंटे की बुकिंग';
  }

  @override
  String fmtSpanDrive(String duration) {
    return 'लगभग $duration की ड्राइव';
  }

  @override
  String fmtSpanStops(int count, String duration) {
    return '$count स्टॉप · $duration';
  }

  @override
  String fmtPaidYourShare(String share) {
    return 'पेमेंट हो गया · कमीशन के बाद आपका हिस्सा $share';
  }

  @override
  String fmtCancellationFee(String fee) {
    return '$fee कैंसल चार्ज';
  }

  @override
  String fmtEndedEarlyCharge(String fare, String booked) {
    return 'जितना समय लगा उसका $fare लिया (बुकिंग $booked की थी)';
  }

  @override
  String fmtRanOverCharge(String fare, String booked) {
    return 'जितना समय लगा उसका $fare (बुकिंग $booked की थी)';
  }

  @override
  String get fmtNewCustomer => 'नया कस्टमर';

  @override
  String fmtCustomerRating(String rating, int count) {
    return '★ $rating · $count रेटिंग';
  }

  @override
  String get fmtNoRatingsYet => 'अभी कोई रेटिंग नहीं';

  @override
  String fmtDriverRating(String rating, int count) {
    return 'आपकी रेटिंग ★ $rating ($count ट्रिप से)';
  }

  @override
  String ridesPickupAt(String time) {
    return 'पिकअप · $time';
  }

  @override
  String ridesLastOfStops(int count) {
    return '$count स्टॉप में आखिरी';
  }

  @override
  String ridesStopNumber(int number) {
    return 'स्टॉप $number';
  }

  @override
  String ridesLeaveBy(String time) {
    return '$time तक निकलें';
  }

  @override
  String ridesDropAt(String time) {
    return 'ड्रॉप · ~$time';
  }

  @override
  String ridesBackAtPickup(String time) {
    return 'वापस पिकअप पर · ~$time';
  }

  @override
  String get ridesExactPlaceAfterAccept => 'राइड लेने के बाद पूरी जगह दिखेगी';

  @override
  String get ridesFareEstimate => 'अंदाज़न';

  @override
  String ridesDistanceAway(String distance) {
    return '$distance दूर';
  }

  @override
  String get ridesExactAddressAfterAccept => 'राइड लेने के बाद पूरा पता दिखेगा';

  @override
  String ridesEndedEarlyNote(String charge) {
    return 'कस्टमर ने ट्रिप जल्दी ख़त्म की · $charge';
  }

  @override
  String ridesRanOverNote(String charge) {
    return 'ट्रिप बुक किए समय से ज़्यादा चली · $charge';
  }

  @override
  String get earningsTitle => 'कमाई';

  @override
  String get earningsToday => 'आज की कमाई';

  @override
  String earningsTripsCompleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ट्रिप पूरी हुईं',
      one: '1 ट्रिप पूरी हुई',
    );
    return '$_temp0';
  }

  @override
  String earningsYoursAfterCommission(String amount) {
    return 'कमीशन के बाद आपके $amount';
  }

  @override
  String get earningsThisWeek => 'इस हफ़्ते';

  @override
  String get earningsThisMonth => 'इस महीने';

  @override
  String get earningsAllTime => 'अब तक';

  @override
  String earningsTrips(int count) {
    return '$count ट्रिप';
  }

  @override
  String earningsYours(String amount) {
    return 'आपके $amount';
  }

  @override
  String get earningsAwaitingCustomers => 'कस्टमर का पेमेंट बाकी';

  @override
  String get earningsDueToYou => 'आपको मिलना है';

  @override
  String earningsDueDetail(int count) {
    return '$count ट्रिप · हर हफ़्ते आपके बैंक में';
  }

  @override
  String get earningsPaidToBank => 'आपके बैंक में भेजा गया';

  @override
  String get earningsNoPayoutsYet => 'अभी कोई पेआउट नहीं';

  @override
  String earningsLastPayout(String when) {
    return 'आखिरी बार $when';
  }

  @override
  String get earningsPayoutsHeader => 'पेआउट';

  @override
  String get earningsNoPayoutsBody =>
      'MOJUD आपके बैंक में जो भी पैसे भेजेगा, वो रेफ़रेंस नंबर के साथ यहाँ दिखेंगे।';

  @override
  String earningsPayoutTitle(int count, String when) {
    return '$count ट्रिप · $when';
  }

  @override
  String earningsPayoutReference(String reference) {
    return 'रेफ़ $reference';
  }

  @override
  String get earningsCompletedTrips => 'पूरी हुई ट्रिप';

  @override
  String get earningsNoTripsTitle => 'अभी कोई ट्रिप नहीं';

  @override
  String get earningsNoTripsBody =>
      'आपकी हर पूरी हुई ट्रिप उसके किराए के साथ यहाँ दिखेगी।';

  @override
  String dutyHello(String name) {
    return 'नमस्ते, $name';
  }

  @override
  String get dutyOnDutyHeadline => 'आप ड्यूटी पर हैं';

  @override
  String get dutyReadyHeadline => 'गाड़ी चलाने के लिए तैयार?';

  @override
  String get dutyNextRide => 'आपकी अगली राइड';

  @override
  String get dutyRideInProgress => 'राइड चल रही है';

  @override
  String get dutyRideRequests => 'राइड रिक्वेस्ट';

  @override
  String dutyOpenCount(int count) {
    return '$count उपलब्ध';
  }

  @override
  String get dutyOfflineTitle => 'आप ऑफ़लाइन हैं';

  @override
  String get dutyOfflineBody =>
      'पास में बुक हुई राइड देखने के लिए ड्यूटी चालू करें।';

  @override
  String get dutyRequestsErrorTitle => 'रिक्वेस्ट लोड नहीं हो पाईं';

  @override
  String get dutyNoRequestsTitle => 'अभी कोई रिक्वेस्ट नहीं';

  @override
  String dutyNoRequestsBody(int seconds) {
    return 'आपके पास की नई बुकिंग यहाँ दिखेंगी। ड्यूटी पर रहते हुए हम हर $seconds सेकंड में चेक करते हैं।';
  }

  @override
  String get dutyLocationOffNote =>
      'हर पिकअप कितनी दूर है, यह देखने के लिए लोकेशन चालू करें। अभी सारी राइड दिख रही हैं।';

  @override
  String dutyRideAccepted(String when) {
    return 'राइड आपकी हो गई: $when।';
  }

  @override
  String get dutyOnline => 'ऑनलाइन';

  @override
  String get dutyOffline => 'ऑफ़लाइन';

  @override
  String get dutyOnDuty => 'ड्यूटी पर';

  @override
  String get dutyOffDuty => 'ड्यूटी बंद';

  @override
  String get dutyGettingRequests => 'आपके पास की राइड रिक्वेस्ट आ रही हैं';

  @override
  String get dutyTapToStart => 'राइड रिक्वेस्ट पाने के लिए टैप करें';

  @override
  String get dutyStripToday => 'आज';

  @override
  String get dutyStripTripsToday => 'आज की ट्रिप';

  @override
  String get dutyStripBooked => 'बुकिंग';

  @override
  String get dutyDecline => 'मना करें';

  @override
  String get dutyAcceptRide => 'राइड लें';

  @override
  String get homeNavHome => 'होम';

  @override
  String get homeNavRides => 'राइड';

  @override
  String get homeNavEarnings => 'कमाई';

  @override
  String get homeNavAccount => 'अकाउंट';

  @override
  String get locationSharingTitle => 'आपकी लोकेशन शेयर हो रही है';

  @override
  String get locationSharingText => 'कस्टमर देख सकता है कि आप रास्ते में हैं।';

  @override
  String get locationChannelName => 'लाइव लोकेशन';

  @override
  String get docViewLogOut => 'लॉग आउट';

  @override
  String get docViewLogOutTitle => 'लॉग आउट करें?';

  @override
  String get docViewLogOutBody =>
      'आप अपने फ़ोन नंबर से फिर से साइन इन कर सकते हैं। जो स्टेप पूरे हो चुके हैं, वे सेव रहेंगे।';

  @override
  String get docViewLoadFailedTitle => 'आपका रजिस्ट्रेशन लोड नहीं हो पाया';

  @override
  String get docViewTitleVerified => 'आप वेरिफ़ाइड हैं';

  @override
  String get docViewTitleSubmitted => 'जाँच चल रही है';

  @override
  String get docViewTitleRejected => 'कुछ जानकारी ठीक करनी है';

  @override
  String get docViewTitleUnknown => 'आपका स्टेटस नहीं दिखा पा रहे';

  @override
  String get docViewTitleIncomplete => 'अपना रजिस्ट्रेशन पूरा करें';

  @override
  String get docViewSubtitleVerified =>
      'आप राइड ले सकते हैं। जो भेजा है उसे देखने या बदलने के लिए कोई भी स्टेप खोलें।';

  @override
  String get docViewSubtitleSubmitted =>
      'हम आपकी जानकारी चेक कर रहे हैं। मंज़ूरी मिलते ही आप ऑनलाइन जा सकते हैं।';

  @override
  String get docViewSubtitleRejected =>
      'नीचे दी गई जानकारी ठीक करें और फिर से जमा करें।';

  @override
  String get docViewSubtitleUnknown =>
      'आपके अकाउंट का स्टेटस ऐप का यह वर्ज़न नहीं पहचानता, इसलिए अभी आप राइड नहीं ले सकते।';

  @override
  String docViewSubtitleIncomplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'राइड लेना शुरू करने के लिए ये $count स्टेप पूरे करें। पिछला स्टेप पूरा होते ही अगला खुलेगा।',
      one: 'राइड लेना शुरू करने के लिए यह स्टेप पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String get docViewCheckAgain => 'फिर से चेक करें';

  @override
  String get docViewChecking => 'चेक हो रहा है…';

  @override
  String get docViewSubmit => 'वेरिफ़िकेशन के लिए जमा करें';

  @override
  String get docViewSubmitting => 'जमा हो रहा है…';

  @override
  String get kycBannerVerifiedTitle => 'गाड़ी चलाने की मंज़ूरी मिल गई';

  @override
  String get kycBannerAadhaarVerified => 'आधार DigiLocker से वेरिफ़ाइड';

  @override
  String kycBannerAadhaarVerifiedLast4(String last4) {
    return 'आधार XXXX XXXX $last4 · DigiLocker से वेरिफ़ाइड';
  }

  @override
  String get kycBannerLicenseVerified => 'ड्राइविंग लाइसेंस वेरिफ़ाइड';

  @override
  String kycBannerLicenseVerifiedNumber(String number) {
    return 'ड्राइविंग लाइसेंस $number · वेरिफ़ाइड';
  }

  @override
  String kycBannerBankVerified(String last4) {
    return 'बैंक खाता •••• $last4 · आपके बैंक से वेरिफ़ाइड';
  }

  @override
  String get kycBannerSubmittedTitle => 'टीम की जाँच बाकी है';

  @override
  String kycBannerSent(String date) {
    return '$date को भेजा';
  }

  @override
  String get kycBannerRejectedTitle => 'टीम ने वापस भेजा';

  @override
  String get kycBannerRejectedHint =>
      'क्या बदलना है, यह देखने के लिए नीचे के स्टेप खोलें।';

  @override
  String get kycBannerUnknownTitle => 'स्टेटस समझ नहीं आया';

  @override
  String get kycBannerUnknownHint =>
      'ऐप अपडेट करें। फिर भी ऐसा ही रहे तो team@mojud.life पर लिखें।';

  @override
  String docCardDate(String day, String month, String year) {
    return '$day $month $year';
  }

  @override
  String get docPhotoSaveFailed => 'फ़ोटो सेव नहीं हो पाई। फिर से फ़ोटो लें।';

  @override
  String get docPhotoReadFailed => 'फ़ोटो खुल नहीं पाई। फिर से फ़ोटो लें।';

  @override
  String get permissionsSubtitle =>
      'इन्हें चालू करें, ताकि MOJUD Driver स्क्रीन पर खुला न हो तब भी राइड के ऑफ़र आप तक पहुँचें।';

  @override
  String get permissionsOverlayTitle => 'दूसरे ऐप्स के ऊपर दिखना';

  @override
  String get permissionsOverlaySubtitle =>
      'आप कोई भी ऐप चला रहे हों, राइड अलर्ट उसके ऊपर दिखेगा।';

  @override
  String get permissionsLocationTitle => 'बैकग्राउंड लोकेशन';

  @override
  String get permissionsLocationSubtitle =>
      'ऑनलाइन रहते हुए आपकी GPS लोकेशन कस्टमर और हमारी टीम तक जाती है।';

  @override
  String get permissionsBatteryTitle => 'बैटरी इस्तेमाल';

  @override
  String get permissionsBatterySubtitle =>
      'बैटरी बचाने के लिए फ़ोन लोकेशन अपडेट नहीं रोकेगा।';

  @override
  String get permissionsNotRequired => 'इस फ़ोन पर ज़रूरी नहीं';

  @override
  String get permissionsTurnOn => 'चालू करें';

  @override
  String get permissionsFinish => 'पूरा करें';

  @override
  String get validationAadhaarEmpty => 'अपना आधार नंबर डालें';

  @override
  String get validationAadhaarInvalid => 'सही 12 अंकों का आधार नंबर डालें';

  @override
  String get validationLicenseEmpty => 'अपना ड्राइविंग लाइसेंस नंबर डालें';

  @override
  String get validationLicenseInvalid => 'सही लाइसेंस नंबर डालें';

  @override
  String get validationHolderNameEmpty => 'खाताधारक का नाम डालें';

  @override
  String get validationNameTooShort => 'नाम बहुत छोटा है';

  @override
  String get validationAccountEmpty => 'अपना खाता नंबर डालें';

  @override
  String get validationAccountInvalid => 'सही खाता नंबर डालें';

  @override
  String get validationAccountConfirmEmpty => 'खाता नंबर दोबारा डालें';

  @override
  String get validationAccountMismatch => 'दोनों खाता नंबर एक जैसे नहीं हैं';

  @override
  String get validationIfscEmpty => 'IFSC कोड डालें';

  @override
  String get validationIfscInvalid => 'सही IFSC कोड डालें';

  @override
  String get vehicleStepTitle => 'गाड़ी का टाइप';

  @override
  String get vehicleStepSubtitle =>
      'आप कौन सी गाड़ी चला लेते हैं — मैनुअल या ऑटोमैटिक? इसी से तय होगा कि आपको कौन सी राइड मिलेंगी।';

  @override
  String get vehicleStepSaving => 'सेव हो रहा है…';

  @override
  String get photoPickerDefaultLabel => 'डॉक्यूमेंट की फ़ोटो लें';

  @override
  String get photoPickerUploadFailed =>
      'अपलोड पूरा नहीं हुआ — फ़ोटो दोबारा लेने के लिए टैप करें।';

  @override
  String get photoPickerUploadedNoPreview => 'फ़ोटो अपलोड हो गई';

  @override
  String get photoPickerBadgeUploading => 'अपलोड हो रही है…';

  @override
  String get photoPickerBadgeUploaded => 'अपलोड हो गई';

  @override
  String get photoPickerBadgeRetry => 'फिर से कोशिश करें';

  @override
  String get photoPickerBadgeRetake => 'दोबारा लें';

  @override
  String get photoStepTitle => 'फ़ोटो और नाम';

  @override
  String get photoStepSubtitle =>
      'एक साफ़ सेल्फ़ी और आपकी डिटेल्स — ठीक वैसी, जैसी आपकी ID पर लिखी हैं।';

  @override
  String get photoStepSelfieRequired => 'आगे बढ़ने के लिए सेल्फ़ी लें';

  @override
  String get photoStepDobRequired => 'अपनी जन्म की तारीख चुनें';

  @override
  String get photoStepGenderRequired => 'अपना लिंग चुनें';

  @override
  String get photoStepSelfieUploading => 'अपलोड हो रही है…';

  @override
  String get photoStepSelfieUploadFailed =>
      'अपलोड नहीं हुई — फिर से भेजने के लिए टैप करें';

  @override
  String get photoStepRetakeSelfie => 'सेल्फ़ी दोबारा लें';

  @override
  String get photoStepTakeSelfie => 'सेल्फ़ी लें';

  @override
  String get photoStepTakeNewSelfie => 'इसकी जगह नई सेल्फ़ी लें';

  @override
  String get photoStepSelfieShownToCustomers =>
      'जब आप किसी की राइड लेंगे, कस्टमर को यही फ़ोटो दिखेगी।';

  @override
  String get photoStepFromAadhaar => 'आपके आधार से';

  @override
  String get photoStepFullName => 'पूरा नाम';

  @override
  String get photoStepDateOfBirth => 'जन्म की तारीख';

  @override
  String get photoStepSaving => 'सेव हो रहा है…';

  @override
  String get aadhaarStepTitle => 'आधार कार्ड';

  @override
  String get aadhaarStepVerifiedSubtitle => 'आपका आधार वेरिफ़ाई हो गया है।';

  @override
  String get aadhaarStepSubtitle =>
      'अपना आधार नंबर डालें, फिर उसे वेरिफ़ाई करने के लिए DigiLocker में साइन इन करें।';

  @override
  String get aadhaarStepOpenFailed =>
      'DigiLocker नहीं खुल पाया। फिर से कोशिश करें।';

  @override
  String get aadhaarStepFinishFirst =>
      'पहले DigiLocker में सारे स्टेप पूरे करें।';

  @override
  String get aadhaarStepChecking => 'चेक हो रहा है…';

  @override
  String get aadhaarStepFinished => 'DigiLocker में पूरा कर लिया';

  @override
  String get aadhaarStepOpening => 'DigiLocker खुल रहा है…';

  @override
  String get aadhaarStepVerify => 'DigiLocker से वेरिफ़ाई करें';

  @override
  String get aadhaarStepVerifiedTitle => 'DigiLocker से वेरिफ़ाई हुआ';

  @override
  String aadhaarStepBorn(String date) {
    return 'जन्म: $date';
  }

  @override
  String aadhaarStepMasked(String last4) {
    return 'आधार XXXX XXXX $last4';
  }

  @override
  String get aadhaarStepNumberLabel => 'आधार नंबर';

  @override
  String get aadhaarStepSavedHint =>
      'नंबर सेव है। बदलना हो तभी भरें, वरना खाली छोड़ दें।';

  @override
  String get aadhaarStepWaiting =>
      'DigiLocker में काम पूरा करें, फिर यहाँ वापस आएँ।';

  @override
  String get aadhaarStepOpenAgain => 'DigiLocker फिर से खोलें';

  @override
  String get licenseStepTitle => 'ड्राइविंग लाइसेंस';

  @override
  String get licenseStepSubtitle =>
      'हम आपका लाइसेंस नंबर ट्रांसपोर्ट विभाग के रिकॉर्ड से चेक करते हैं।';

  @override
  String get licenseStepNumberLabel => 'लाइसेंस नंबर';

  @override
  String get licenseStepNumberHint => 'जैसे MP0920190012345';

  @override
  String get licenseStepVerifiedTitle => 'लाइसेंस वेरिफ़ाई हो गया';

  @override
  String licenseStepValidTill(String date) {
    return '$date तक वैलिड';
  }

  @override
  String licenseStepCovers(String classes) {
    return 'लाइसेंस में: $classes';
  }

  @override
  String get licenseStepChecking => 'चेक हो रहा है…';

  @override
  String get licenseStepVerify => 'लाइसेंस वेरिफ़ाई करें';

  @override
  String get bankStepTitle => 'बैंक डिटेल्स';

  @override
  String get bankStepSubtitle =>
      'आपकी कमाई इसी खाते में आएगी। हम इसे आपके बैंक से चेक करते हैं।';

  @override
  String get bankStepVerifiedTitle => 'आपके बैंक से वेरिफ़ाई हुआ';

  @override
  String bankStepAccountEnding(String last4, String ifsc) {
    return 'खाता नंबर के आखिरी अंक $last4 · $ifsc';
  }

  @override
  String get bankStepHolderLabel => 'खाताधारक का नाम';

  @override
  String get bankStepHolderHint => 'जैसा बैंक खाते में लिखा है';

  @override
  String get bankStepAccountNumber => 'खाता नंबर';

  @override
  String bankStepCurrentAccount(String last4) {
    return 'अभी पेमेंट उस खाते में जा रहा है जिसके आखिरी अंक $last4 हैं। बदलने के लिए नया खाता नंबर डालें।';
  }

  @override
  String get bankStepConfirmLabel => 'खाता नंबर कन्फ़र्म करें';

  @override
  String get bankStepConfirmHint => 'खाता नंबर फिर से डालें';

  @override
  String get bankStepIfscLabel => 'IFSC कोड';

  @override
  String get bankStepIfscHint => 'जैसे HDFC0001234';

  @override
  String get bankStepChecking => 'आपके बैंक से चेक हो रहा है…';

  @override
  String get bankStepFinish => 'पूरा करें';

  @override
  String get authPhoneTitle => 'अपना मोबाइल नंबर डालें';

  @override
  String get authPhoneSubtitle =>
      'हम आपको SMS पर एक OTP भेजेंगे, ताकि पता चले कि यह आप ही हैं।';

  @override
  String get authMobileNumberLabel => 'मोबाइल नंबर';

  @override
  String get authPhoneRequired => 'अपना मोबाइल नंबर डालें';

  @override
  String get authPhoneInvalid => 'सही 10 अंकों का मोबाइल नंबर डालें';

  @override
  String get authNameTitle => 'आपका नाम क्या है?';

  @override
  String get authNameSubtitle => 'ट्रिप पर कस्टमर को आपका यही नाम दिखेगा।';

  @override
  String get authFullName => 'पूरा नाम';

  @override
  String get authNameRequired => 'अपना नाम डालें';

  @override
  String get authNameTooShort => 'नाम बहुत छोटा है';

  @override
  String get authCreateAccount => 'अकाउंट बनाएँ';

  @override
  String get authConsentRequired =>
      'अकाउंट बनाने के लिए शर्तों और प्राइवेसी पॉलिसी से सहमति दें।';

  @override
  String get authSessionEnded =>
      'आपका लॉग इन ख़त्म हो गया है। फिर से लॉग इन करें।';

  @override
  String consentAgree(String terms, String privacy) {
    return 'मैं $terms और $privacy से सहमत हूँ';
  }

  @override
  String get consentTerms => 'शर्तों';

  @override
  String get consentPrivacy => 'प्राइवेसी पॉलिसी';

  @override
  String consentOpenInBrowser(String address) {
    return '$address को ब्राउज़र में खोलें';
  }

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
  String get updateTitle => 'MOJUD Driver अपडेट करें';

  @override
  String get updateBody =>
      'ऐप का यह वर्ज़न पुराना हो गया है। राइड मिलती रहें, इसके लिए नया वर्ज़न इंस्टॉल करें। आपका अकाउंट, डॉक्यूमेंट और कमाई सुरक्षित हैं।';

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
  String get notifChannelName => 'राइड रिक्वेस्ट';

  @override
  String get notifChannelDescription =>
      'ड्यूटी पर रहते हुए आपके पास बुक हुई नई राइड।';
}

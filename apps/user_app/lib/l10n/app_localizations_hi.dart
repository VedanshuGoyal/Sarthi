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
}

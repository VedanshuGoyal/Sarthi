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
}

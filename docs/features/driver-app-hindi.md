# MOJUD Driver in Hindi

| | |
|---|---|
| Slug | `driver-app-hindi` |
| Status | implemented on `feat/driver-app-hindi` — owner to review the Hindi |
| Components | `apps/driver_app`; `shared`: optional `label` on `SarthiPhoneField`, optional `actions` on `SarthiFormScaffold` (user_app unchanged) |
| Risk flags | none — text only; no payment or KYC logic changed |
| Versions | not bumped here (feature → minor on release) |

## What it does

- Every driver-facing string in `apps/driver_app` comes from ARB files: English (template) + Hindi.
- Server-sent text stays as sent (backend errors, review notes, addresses, names, push titles/bodies).
- Money stays `₹` with Indian grouping (`RideFormat.rupees`); digits stay Latin; times stay `9:05 AM`.

## Language switch

- Default: the phone's language — Hindi phone → Hindi; anything else → English.
- In-app: **Account → Language · भाषा** (English / हिंदी). Also a translate icon (English / हिंदी menu) in the app bar of the start screen and the Document View, so a driver can switch before KYC clears (the Account tab only exists after).
- Saved on the phone (`flutter_secure_storage`, key `sarthi.driver.language`), like the app's other local settings; survives log-out; not sent to the server.
- Code: `lib/features/language/` — `LanguageRepository` → `LanguageViewModel` → `MaterialApp.locale` in `main.dart`.

## How to add a string

1. Add the key to `apps/driver_app/lib/l10n/app_en.arb` with an `@key` description (and `placeholders` with types).
2. Add the same key to `app_hi.arb`.
3. `cd apps/driver_app && flutter gen-l10n` (or any `flutter run/test/analyze` — `generate: true`). Generated `app_localizations*.dart` are checked in.
4. Use it:
   - widgets: `context.l10n.myKey` (import `lib/l10n/l10n.dart`)
   - view models / repositories / `RideFormat` (no context): `L10n.current.myKey`
   - enums: the `labelIn(l10n)` extensions in `rides/view/ride_labels.dart` and `documents/view/document_labels.dart`
- Rules: one key per whole sentence (Hindi word order differs — don't glue fragments); counts as ICU plurals; money/dates as `String` placeholders filled from `RideFormat`; no `intl` `DateFormat` (its locale data isn't loaded in unit tests).
- Tests pump `MaterialApp(locale: Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, …)`; Hindi layout checks (no overflow at 320 / 360 dp) are in `test/l10n/hindi_layout_test.dart`; the switch in `test/language/language_test.dart`.

## Hindi style used

- Simple spoken Delhi-NCR Hindi, `आप` + `…करें`; Devanagari; nukta forms (फ़ोन, फ़ीस).
- Loanwords kept: OTP, UPI, KYC, DigiLocker, IFSC, SUV (Latin); राइड, ट्रिप, कस्टमर, पिकअप, ड्रॉप, ड्यूटी, ऑनलाइन, पेमेंट, पेआउट, कमीशन, डॉक्यूमेंट, वेरिफ़ाई, लोकेशन, परमिशन.
- Brand stays MOJUD / MOJUD Driver.

## Left in English (on purpose)

- Server text: backend error messages, KYC review notes, addresses, names, cancel reasons, push titles/bodies, an unknown status word (`On hold`).
- Times `9:05 AM`, `₹` amounts, Latin digits, masks (`XXXX XXXX 1234`, `••••`), example numbers in hints (`MP0920190012345`, `HDFC0001234`), `5/6` step count.
- Brand / proper names: MOJUD, MOJUD Driver, DigiLocker, WhatsApp; abbreviations OTP, UPI, KYC, IFSC, GPS, SUV.
- Support prefill `Booking {id}` (read by the MOJUD team) and the support email address.
- The Terms / Privacy pages themselves (only the link labels are translated).
- Developer-only text: debug logs, `API_BASE_URL` error, push-token errors (never shown).
- Android channel names switch language on the next app start after a change.

## For the owner: terms to check

| Key | English | Hindi used | Question |
|---|---|---|---|
| `fmtTomorrow` / `fmtYesterday` | Tomorrow / Yesterday | कल / कल | Same word (as CLDR); only the tab disambiguates. OK, or "आने वाला कल" / "बीता कल"? |
| `commonCancel` | Cancel | कैंसल | vs "रद्द करें" / "रहने दें" |
| `rideDetailActionAccept`, `dutyAcceptRide` | Accept ride | राइड लें | vs "स्वीकार करें" / "एक्सेप्ट करें" |
| `rideDetailActionDecline` | Decline | मना करें | — |
| `rideDetailActionRelease` | Can't make it | राइड छोड़ें | reworded ("leave the ride") |
| `rideDetailActionArrive` | I've arrived at pickup | पिकअप पर पहुँच गए | masculine-plural; "पहुँच गया/गई" is gendered |
| gendered verbs (several) | — | सकते हैं, चला रहे हों, लेंगे, पहुँच गए | masculine-plural honorific (usual in Hindi apps); fine for women drivers? |
| `locationSharingText` | Your customer can see you on the way. | कस्टमर देख सकता है… | customer as masculine |
| `rideStatusAccepted` / `rideStatusInProgress` | Upcoming / On trip | आने वाली / ट्रिप चालू | — |
| `tripKindOneWay` / `tripKindMultiStop` | One way / Multi-stop | वन-वे / मल्टी-स्टॉप | kept close to the customer app's English |
| `fmtSpanHire` | 3 h hire | 3 घंटे की बुकिंग | "hire" → booking |
| `fmtCancellationFee` | ₹50 cancellation fee | ₹50 कैंसल चार्ज | vs "कैंसलेशन फ़ीस" |
| `fmtEndedEarlyCharge` | Charged ₹200 for the time used (booked ₹340) | जितना समय लगा उसका ₹200 लिया (बुकिंग ₹340 की थी) | add "कस्टमर से"? |
| `ridePaymentPaidOut` | Paid out | बैंक में भेजा गया | — |
| `accountSectionPayouts`, `earningsPayoutsHeader` | Payouts | पेआउट | vs "भुगतान" |
| `earningsPayoutReference` | Ref UTR123 | रेफ़ UTR123 | drivers may know "UTR" |
| `dutyOpenCount` | 3 open | 3 उपलब्ध | slightly formal |
| `dutyStripBooked` | Booked | बुकिंग | counts rides held |
| `fmtMonthShort`, `helpShareDateTime` | Jan… / Mon… | full month names (जनवरी…); short weekdays (सोम…) | CLDR short months (जन॰) felt unfamiliar |
| `docStepVehicleTypeTitle` | Type of Vehicle | गाड़ी का टाइप | — |
| `vehicleStepSubtitle` | Which gearbox can you drive? | आप कौन सी गाड़ी चला लेते हैं — मैनुअल या ऑटोमैटिक? | "gearbox" rephrased |
| `photoStepGenderRequired`, `docStepPhotoAndNameSubtitle` | gender | लिंग | govt-form word; or "जेंडर"? |
| `photoStepSubtitle` | …as on your ID | …जैसी आपकी ID पर लिखी हैं | "ID" vs "पहचान पत्र" |
| `licenseStepSubtitle` | transport department | ट्रांसपोर्ट विभाग | or "RTO"? |
| `licenseStepValidTill` | Valid till | … तक वैलिड | vs "वैध" |
| `licenseStepCovers` | Covers LMV, MCWG | लाइसेंस में: LMV, MCWG | no exact equivalent |
| `validationHolderNameEmpty`, `bankStepHolderLabel` | Account holder name | खाताधारक का नाम | vs "खाते वाले का नाम" |
| `bankStepAccountEnding` | Account ending 2345 | खाता नंबर के आखिरी अंक 2345 | a bit long |
| `kycBannerSubmittedTitle` / `kycBannerRejectedTitle` | Waiting on / Sent back by a reviewer | टीम की जाँच बाकी है / टीम ने वापस भेजा | reviewer → "the team" |
| `kycBannerVerifiedTitle` | Cleared to drive | गाड़ी चलाने की मंज़ूरी मिल गई | could be shorter |
| `permissionsLocationSubtitle` | …to riders and dispatch | …कस्टमर और हमारी टीम तक | dispatch → "our team" |
| `accountKycRejected` | Documents need attention | डॉक्यूमेंट में कुछ ठीक करना है | — |
| `consentTerms` / `consentPrivacy` | Terms / Privacy Policy | शर्तों / प्राइवेसी पॉलिसी | vs "गोपनीयता नीति" |
| `otpFieldLabel` | Verification code | OTP | — |
| `authSessionEnded` | Your session has ended | आपका लॉग इन ख़त्म हो गया है | — |
| `authNameSubtitle` | …how riders will see you | …कस्टमर को आपका यही नाम दिखेगा | — |
| `updateGetLatest` | Get the latest version | नया वर्ज़न डाउनलोड करें | — |
| `notifChannelDescription` | New rides booked near you while you are on duty. | ड्यूटी पर रहते हुए आपके पास बुक हुई नई राइड। | shown in phone settings |

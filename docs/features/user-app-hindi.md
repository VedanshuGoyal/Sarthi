# MOJUD in Hindi

| | |
|---|---|
| Slug | `user-app-hindi` |
| Status | implemented on `feat/user-app-hindi` — owner to review the Hindi |
| Components | `apps/user_app` only (`shared/` and the driver app untouched) |
| Risk flags | **HUMAN REVIEW REQUIRED** — payment screens' text changed (Pay button, receipt, UPI checkout messages in `upi_checkout.dart`, booking errors); text only, no payment logic changed |
| Versions | not bumped here (feature → minor on release) |

## What it does

- Every customer-facing string in `apps/user_app` comes from ARB files: English (template) + Hindi, ~460 keys.
- Same approach, helper names and Hindi style as the driver app (`docs/features/driver-app-hindi.md`).
- Server-sent text stays as sent (backend errors, addresses, place names, names, server receipt-line labels, typed cancel reasons).
- Money stays `₹` as today (no grouping change); digits stay Latin; times stay `9:30 AM`.
- Cancel reasons are shown in the app's language but still sent to the server in English (driver and MOJUD team read them).

## Language switch

- Default: the phone's language — Hindi phone → Hindi; anything else → English.
- In-app: **Account → Language · भाषा** (English / हिंदी), plus a translate icon (English / हिंदी menu) in the app bar of every sign-in step (phone, OTP, profile), so a customer can switch before signing in.
- Saved on the phone (`flutter_secure_storage`, key `sarthi.user.language`); survives log-out; not sent to the server.
- Code: `lib/features/language/` — `LanguageRepository` → `LanguageViewModel` → `MaterialApp.locale` in `main.dart`.
- Android channel name ("Ride updates") switches language on the next app start after a change.

## How to add a string

1. Add the key to `apps/user_app/lib/l10n/app_en.arb` with an `@key` description (and `placeholders` with types).
2. Add the same key to `app_hi.arb`.
3. `cd apps/user_app && flutter gen-l10n` (or any `flutter run/test/analyze` — `generate: true`). Generated `app_localizations*.dart` are checked in.
4. Use it:
   - widgets: `context.l10n.myKey` (import `lib/l10n/l10n.dart`)
   - view models / repositories / `RideFormat` (no context): `L10n.current.myKey`
   - enums and booking words: the `labelIn(l10n)` extensions in `lib/features/ride/ride_labels.dart`
- Rules: one key per whole sentence (Hindi word order differs — don't glue fragments); counts as ICU plurals; money/dates as `String` placeholders filled from `RideFormat` (`rupees`, `date`, `day`, `when`, `clock`); no `intl` `DateFormat`.
- Tests pump `MaterialApp(locale: Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, …)`; Hindi layout checks (no overflow at 320 / 360 dp) are in `test/l10n/` via `test/support/hindi.dart`; the switch in `test/language/language_test.dart`.
- Widget previews get English strings via `@Preview(localizations: previewLocalizations)`.

## Hindi style used

- Simple spoken Delhi-NCR Hindi, `आप` + `…करें`; Devanagari; nukta forms (फ़ोन, ज़्यादा, ग़लती).
- Loanwords kept: OTP, UPI, SUV, GPay/PhonePe/Paytm (Latin); राइड, ट्रिप, बुकिंग, ड्राइवर, पिकअप, ड्रॉप, स्टॉप, पेमेंट, लोकेशन, अकाउंट, कैंसल, सपोर्ट, मैप.
- Same words as the driver app: वन-वे, मल्टी-स्टॉप, राउंड ट्रिप, कैंसल, कैंसल चार्ज, अंदाज़न किराया; sign-in, OTP, consent and update screens reuse the driver app's Hindi.
- A named driver is honorific plural (`{name} आपके ड्राइवर हैं`); "a driver" in general is singular (`ड्राइवर आपकी ही कार चलाएगा`).
- Brand stays MOJUD.

## Left in English (on purpose)

- Server text: backend error messages, addresses and place names (Ola/Google), names, server receipt-line labels ("One way · Fri 25 Oct"), unknown payment modes ("Net Banking"), UTR / order ids, typed cancel reasons, PhonePe SDK errors.
- Times `9:30 AM`, `₹` amounts, Latin digits, `+91`, the example plate `KA 01 AB 1234`, OTP countdown `m:ss`.
- Brand / proper names: MOJUD, GPay, PhonePe, Paytm, WhatsApp; OTP, UPI, SUV.
- Support WhatsApp prefill `Booking {id}` (read by the MOJUD team), as in the driver app.
- Developer-only text: debug logs, `API_BASE_URL` error, push-token and recent-pickups API errors (never shown), Maps web-loader errors.
- Design galleries and previews (`deep_signal/`, `vast_quiet/`, `*previews.dart`) — not shown in the app.
- The Terms / Privacy pages themselves (only the link labels are translated).

## For the owner: terms to check

| Key | English | Hindi used | Question |
|---|---|---|---|
| `fmtTomorrow` / `fmtYesterday` | Tomorrow / Yesterday | कल / कल | Same word, as in the driver app. OK? |
| `homeNavActivity` / `activityTitle` | Activity (tab / screen title) | राइड / मेरी राइड | vs "एक्टिविटी" |
| `activityTabCompleted` | Completed (tab) | पिछली | "Past": the tab also holds cancelled / expired rides |
| `bookingStatusAccepted` | Driver assigned | ड्राइवर मिल गया | vs "ड्राइवर तय हो गया" |
| `bookingCancelledNoShow` | Closed as a no-show | आपके न आने पर बंद हुई | clear enough? |
| `cancelReasonFoundAnotherOption` | Found another option | कोई दूसरा इंतज़ाम मिल गया | — |
| `carOptionsTransmission` | Transmission | गियरबॉक्स | vs "गियर का टाइप" / "ट्रांसमिशन" |
| `carsRegistrationLabel` | Registration number | कार नंबर | vs "रजिस्ट्रेशन नंबर" |
| `paymentModeWaived` | Waived by MOJUD | MOJUD ने माफ़ किया | — |
| `fmtCarriedNote` | ₹50 unpaid from an earlier ride will be added when you pay for this trip. | पिछली राइड के बाकी ₹50 इस ट्रिप का पेमेंट करते समय जुड़ जाएँगे। | — |
| `fmtPaidTogether` + `fmtOtherRides` | Paid ₹690 together with 1 other ride. | ₹690 का पेमेंट 1 दूसरी राइड के साथ हुआ। | — |
| `tripStartStartingPoint`, `pickupStartField` | Starting point | पिकअप / पिकअप की जगह | "Starting point" and "Pickup" both read पिकअप |
| `oneWayRouteField` | Destination | ड्रॉप की जगह | vs "कहाँ जाना है" |
| `routeFrom` / `routeTo` | From / To | कहाँ से / कहाँ तक | — |
| `tripPickerRoundTripSubtitle` | Hire a driver by the hour, out and back. | घंटे के हिसाब से ड्राइवर, जाना और वापस आना। | natural? |
| `authServiceByTheHour` | By the hour | घंटे के हिसाब से | — |
| `fareSummaryEstimatedFrom` | Estimated fare from | अंदाज़न किराया, कम से कम | better word for "from"? |
| `hoursChip` | 4h | 4 घंटे | full word on the hour chips |
| `timeSlotSubtitle` | Trips start every 15 minutes. | ट्रिप हर 15 मिनट के स्लॉट पर शुरू होती है। | — |
| `stopMoveEarlier` / `stopMoveLater` | Move stop 2 earlier / later | स्टॉप 2 को ऊपर / नीचे करें | up/down, matching the arrows |
| `stopLeaveBy`, `rideDetailsLeaveBy` | Leave by / Leave by 9:30 AM | कब निकलना है / 9:30 AM तक निकलें | — |
| `oneWayReviewTitle` | Review trip | ट्रिप चेक करें | — |
| `roundTripConfirm`, `oneWayReviewConfirm` | Confirm booking | बुकिंग कन्फ़र्म करें | vs "बुकिंग पक्की करें" |
| `homeRetry`, `carsRetry`, `oneWayReviewRetry` | Retry | फिर से भेजें / फिर कोशिश करें / फिर से देखें | shortened per place to fit at 320 dp |
| `mapPickerMoveHint` | Move the map to place the pin | पिन लगाने के लिए मैप खिसकाएँ | "खिसकाएँ" OK? |
| `mapPickerConfirm` | Confirm this location | यही लोकेशन लें | — |
| `rideIsYourDriver`, `rideAtYourPickup` | Ravi is your driver / … is at your pickup | {name} आपके ड्राइवर हैं / … पहुँच गए हैं | masculine honorific; fine for women drivers? |
| `rideDetailsInfoBookedFor` | Booked for | बुक किया समय | — |
| `rideDetailsTimeline` | Timeline | टाइमलाइन | or "क्या कब हुआ"? |
| `receiptTitle` | Receipt | रसीद | — |
| `receiptPaidVia` / `receiptPaidAt` | Paid via / Paid (date row) | पेमेंट का तरीका / पेमेंट हुआ | — |
| `receiptNightSurcharge` | Night surcharge | रात का चार्ज | — |
| `ridePayStillConfirming` | We're still confirming your payment with the bank… | बैंक से आपका पेमेंट अभी कन्फ़र्म हो रहा है… | "कन्फ़र्म" vs "पुष्टि" |
| `endTripOvertime` | …after a 15-minute grace. | …15 मिनट की छूट के बाद… | "छूट" for grace? |
| `starsWord*` | Poor … Excellent | ख़राब / कुछ ख़ास नहीं / ठीक-ठाक / अच्छा / बहुत बढ़िया | — |
| `rideCardDrivenBy` | Driven by Ravi | Ravi ने गाड़ी चलाई | or "ड्राइवर: Ravi"? |
| `rideCardPaid` | Paid (tag) | पेमेंट हुआ | shorter than पेमेंट हो गया, to fit the tag |
| `cancelSheetFree` | Cancelling is free. | कैंसल करना फ़्री है। | vs "कोई चार्ज नहीं" |
| `cancelSheetWhy` | Tell us why — it helps us improve. | वजह बताएँ — इससे हमें सुधार करने में मदद मिलती है। | — |
| `checkoutAndroidOnly` | Paying by UPI works in the Android app. | UPI से पेमेंट Android ऐप में ही होता है। | — |
| `notifChannelDescription` | Your driver is assigned, and other changes to your rides. | ड्राइवर तय होने और आपकी राइड में बाकी बदलावों की सूचना। | shown in phone settings |
| `serviceAreaOutside` | We're only serving Delhi NCR … | अभी हम सिर्फ़ दिल्ली NCR (…) में सर्विस देते हैं — … | — |

# Play Store readiness — MOJUD and MOJUD Driver

Draft, 21 Nov 2026. Distribution today is APK sideload from apps.mojud.life.
Sources are linked; "my reading" marks anything that isn't from them.

## What decides the timeline

| Item | What it means for MOJUD |
|---|---|
| Account type | A **personal** account created after 13 Nov 2023 must run a closed test with **12+ testers opted in for 14 days in a row** before it can publish ([Google](https://support.google.com/googleplay/android-developer/answer/14151465)). An **organization** account skips that but needs a D-U-N-S number (third-party guides say up to 30 days). |
| Fee | US$25, one time ([Google](https://support.google.com/googleplay/android-developer/answer/6112435)). |
| Developer verification | From 2027 Google plans to require, worldwide, that apps on certified Android phones come from a verified developer, **sideloaded APKs included**. No India date has been announced ([Google, Mar 2026](https://android-developers.googleblog.com/2026/03/android-developer-verification-rolling-out-to-all-developers.html)). So the APKs on apps.mojud.life will need a registered developer either way. |
| Signing | Enrol in Play App Signing with **your existing key** (`sarthi-release.jks`). Then people who sideloaded the app can update from Play without uninstalling (my reading: Android only accepts an update signed by the same key). |
| Legal pages | Play needs a live privacy policy URL. Terms and Privacy still have blanks (see the checklist). |
| Account deletion | Play wants a way to ask for deletion from the web, not only in the app (my reading of Play's account-deletion rule). Already covered: the privacy page's "Deleting your account" section offers email, so the listing can link to `…/privacy#deletion`. |
| Reviewer login | Sign-in is by SMS OTP, so Google's reviewer needs a test number with a fixed code on prod. **Not built:** a `REVIEW_PHONE` + `REVIEW_OTP` pair in the server env, one for each app. |

## Driver app: location permissions

- The app asks for **background location**. That needs Play's location declaration: a form, a short video, and the in-app prominent disclosure ([Google](https://support.google.com/googleplay/android-developer/answer/9799150)).
- Going on duty is a tap by the driver. A **foreground service of type location**, started by that tap, may be enough without background location. It still has to be declared on the App content page ([Google](https://support.google.com/googleplay/android-developer/answer/13392821)). Google treats it as background location if it works the same way.
- Recommendation (mine): try the foreground-service route first, because the review is simpler, and drop `ACCESS_BACKGROUND_LOCATION` if the duty location still works with the screen off. The driver-app branch from 21 Nov reports what the app does today.

## Listing text (drafts)

**MOJUD** (customer). Category: Travel & Local.

- Title (max 30): `MOJUD: A driver for your car`
- Short (max 80): `Book a trained, verified driver for your own car. By the hour or one way.`
- Full:
  > MOJUD sends a trained driver to drive your car. Use it for a night out, a long day of errands, an airport run or a trip out of town.
  > • Round trip by the hour, one way, or several stops
  > • Every driver's Aadhaar, licence and bank account are verified
  > • See your driver's photo, track them as they come, and share your trip
  > • Fares shown up front, taxes included; pay by UPI after the ride
  > • Call 112 or contact support from any ride
  > Serving Delhi NCR (Delhi, Gurugram, Faridabad, Noida).

**MOJUD Driver**. Category: Business (my pick; Maps & Navigation also fits).

- Title: `MOJUD Driver`
- Short: `Drive for MOJUD: get ride requests near you and get paid to your bank.`
- Full:
  > Drive customers' own cars with MOJUD. Verify once with DigiLocker, your licence and your bank, then go on duty to get trips near you.
  > • See the area first; the full address after you accept
  > • Start each trip with the customer's code
  > • Earnings and payouts in one place
  > Delhi NCR only for now.

## App content answers (drafts, check before submitting)

- **Ads:** none.
- **Target audience:** 18 and over.
- **Payments:** UPI through PhonePe, for a real-world service. My reading: Play Billing isn't required for physical services.
- **Data safety:** collected and why. Shared with the processors listed in the privacy policy (PhonePe, Surepass/DigiLocker, Firebase, Fast2SMS, Ola/Google Maps, Cloudflare R2, Vultr). All data is encrypted in transit, and users can delete their account.

| Data | Customer app | Driver app |
|---|---|---|
| Name, phone, email | ✓ account | ✓ account |
| Date of birth | ✓ | ✓ |
| Precise location | ✓ pickup | ✓ while on duty |
| Photos | — | ✓ selfie |
| Government ID | — | ✓ Aadhaar (last 4 digits and name), driving licence |
| Financial info | Payment status only; PhonePe takes the payment | ✓ bank account for payouts |
| Device ID | ✓ push token | ✓ push token |

## Next steps, in order

1. Choose personal or organization (fee, 14-day test, D-U-N-S).
2. Fill the legal blanks and publish the pages.
3. Build the reviewer login and add the web deletion line.
4. Choose the driver-location route (foreground service, or the background-location declaration).
5. Upload with Play App Signing on the existing key, then run the closed test.

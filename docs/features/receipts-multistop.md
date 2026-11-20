# Receipts for combined payments · multi-stop car

| | |
|---|---|
| Slug | `receipts-multistop` |
| Status | implemented (branch `feat/receipts-multistop`, 21 Nov 2026); approved (owner brief, 2026-11-21) |
| Components | server · user_app |
| Risk flags | PAYMENTS (read-only) — see Risk |
| Versions | user_app `1.6.0+9` → not bumped here; the car rule needs the release to be build **10** or later |

## Goal

- One payment can pay several bookings (carried dues, `payment_order_items`, 0031). The receipt shows the total and every booking paid.
- Fable F16: multi-stop trips never named a car, so any driver was offered them whatever the gearbox. The app now asks for a car on multi-stop too.

## Contract

### Customer booking JSON — `payment` block

`GET /me/bookings` and every `{booking}` reply (cancel, end, rating, payment sync). Old keys are unchanged.

```json
"payment": {
  "mode": "UPI_INTENT",
  "utr": "412345678901",
  "merchantOrderId": "MOJUD_…",
  "paidAt": "2026-11-18T06:00:00Z",
  "totalPaise": 29000,
  "lines": [
    {"bookingId": "…", "kind": "cancellation_fee", "label": "Cancellation fee · Sun 15 Nov", "amountPaise": 5000},
    {"bookingId": "…", "kind": "ride", "label": "Round trip · Tue 17 Nov", "amountPaise": 24000}
  ]
}
```

- `totalPaise`: the order's amount. `lines`: every booking the order paid, this one included, oldest scheduled first.
- `kind`: `ride` | `cancellation_fee`. `label`: trip type and day (IST), made by the server.
- Only the customer's own orders and bookings are listed. No driver data.
- Both fields are set only for app payments (not for `CASH` / `WAIVED`). If the lines can't be read, the receipt is sent without them.

### `POST /me/bookings` — car

| Client | Booking without a car |
|---|---|
| `X-App: user_app`, `X-Build` ≥ 10 | 400 `car_required` ("choose the car the driver will drive") — any trip type |
| 1.6.0 (+9) and older, no build headers, debug (0) | accepted as before; multi-stop is offered to any gearbox |

- "Car" = `details.car` with `registration`, `carType` (hatchback/sedan/suv/luxury), `transmission` (automatic/manual).
- A multi-stop trip with a car is matched on its gearbox. A luxury car is priced on the luxury hourly tariff, as one-way trips already are.

## Migration

- None. Lines are read from `payment_order_items` (0031) joined to `payment_orders` and `bookings`.

## App screens (user_app)

- Receipt card: "Paid ₹690 together with 1 cancellation fee." under the heading, then the other bookings' lines after this one's fare, then "Total paid". A payment for one booking looks as before.
- Multi-stop planner: a "Which car?" section (saved-car dropdown, add a car). Confirm stays off until a car is picked ("Choose your car to continue."). The booked snackbar names the plate.

## Acceptance tests

- Server: `TestBookingService_receiptListsEveryBookingThePaymentPaid`, `…_receiptWithoutLinesWhenTheyCantBeRead`, `…_noReceiptsNoLinesRead`, `TestPaymentLineLabel` (`service/payment_lines_test.go`); `TestListBookings_receiptLinesJSON` (`api/receipt_lines_test.go`).
- Server: `TestBookingService_Record_multiStopWithoutACarFromOlderApps`, `…_carRequiredFromAppsThatAskForIt`, `…_multiStopCarDecidesGearboxAndTariff` (`service/multistop_car_test.go`); `TestSubmitBooking_multiStopCar` (`api/multistop_car_test.go`); `TestAsksCarOnEveryTrip` (`api/app_version_test.go`).
- Repository SQL: `TestBookingRepository_PaymentLines_Integration` (`repository/payment_lines_repository_test.go`).
- App: `test/ride/receipt_card_test.dart`; three new parse tests in `test/ride/my_booking_test.dart`; the receipt in `ride_details_screen_test.dart`; car tests in `multi_stop_planner_view_model_test.dart`, `multi_stop_planner_screen_test.dart` and `booking_repository_test.dart`.

## Risk

| Area | Touched? | Notes |
|---|---|---|
| Payments | read-only | New SELECT on `payment_order_items` / `payment_orders`; no write path, amount or commission changed. HUMAN REVIEW REQUIRED (payments read path) |
| Driver KYC | no | |
| Personal data | no new | Lines carry the customer's own booking ids, trip type, day and amount |
| Auth scope | unchanged | Filtered by `po.user_id` and `b.user_id` |
| Build gate | yes | `firstCarOnEveryTripBuild = 10` assumes the next user app release is build 10 with this change. If another release ships as +10 without it, raise the constant before deploying the server |

## Rollout

- Server: redeploy only (no migration). Safe before the APK: old builds are unaffected.
- App: bump `apps/user_app/pubspec.yaml` to `1.7.0+10` (feature → minor), build, publish.
- Smoke: a paid booking in `GET /me/bookings` shows `payment.totalPaise` and `payment.lines`; a build-10 multi-stop without a car gets 400 `car_required`.

## Out of scope

- Server-side car requirement for builds before 10 (they can't send one for multi-stop).
- Rollout script, version bump, APK release.

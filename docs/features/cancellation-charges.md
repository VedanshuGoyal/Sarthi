# Cancellation charges — 17 Nov 2026

HUMAN REVIEW REQUIRED: payments.

## Rules (owner's decision, 17 Nov)

| When the customer stops the ride | Charge |
|---|---|
| Before the driver reaches the pickup (`requested`, `accepted`) | free |
| Driver at the pickup, trip not started (`arrived`) | **₹50** cancellation fee |
| During the trip (`in_progress`) — "End trip now" | hourly tariff for the time used: each started hour counts as a whole one, at least 1 h, plus the night surcharge for those hours; never more than the booked fare |
| Customer never comes (driver's no-show) | free (no no-show fee) |

- The driver gets the fee (or the partial fare) like a ride: less MOJUD's commission, in the next payout.
- A fee or partial fare is a normal payment: PhonePe checkout, and the customer can't book again until it's paid (`payment_due`).
- Waived by ops (`/admin` → settle `waived`): the customer pays nothing, **MOJUD still pays the driver their share**.
- Prices include GST/TDS. MOJUD isn't liable for damage to the customer's car.

## API

Customer booking JSON (`GET /me/bookings`, `GET /me/bookings/{id}`, cancel/end responses):

| Field | Meaning |
|---|---|
| `cancellationFeePaise` | `arrived`: what cancelling now costs (5000). `cancelled`: the fee charged. Omitted when 0. |
| `paymentStatus` | also `due` / `paid` on a cancelled booking with a fee (amount = `cancellationFeePaise`) |
| `bookedFarePaise` | only when the customer ended the trip early: the fare as booked; `farePaise` is then the charge for the time used |

`POST /me/bookings/{id}/cancel` `{"reason": "…", "acceptFeePaise": 5000}`

- The new app always sends `acceptFeePaise`: the fee it showed (0 if none).
- Cancelling costs more than `acceptFeePaise` (driver reached the pickup after the dialog opened) →
  409 `{"error": "…", "code": "cancellation_fee", "feePaise": 5000}`, nothing changes.
- No `acceptFeePaise` (apps before user build 9) → cancels free.

`POST /me/bookings/{id}/end` (no body) — customer ends an `in_progress` trip.

- 200 → booking `completed`, `farePaise` = charge for the time used, `bookedFarePaise` = booked fare, `paymentStatus: "due"`.
- 409 `{"code": "cannot_end"}` when the trip isn't in progress.
- The driver gets push `ride_ended_early` (`rideId`).

Checkout (`POST /me/bookings/{id}/payment/checkout`) and sync also take a cancelled booking whose `paymentStatus` is `due`; the amount is the fee.
A 409 `payment_due` on a new booking can name such a cancelled booking.

Driver ride JSON: `cancellationFeePaise`, `paymentStatus` (`due`/`paid`/`paid_out`), `sharePaise` on a ride the customer cancelled at the pickup;
`bookedFarePaise` on one they ended early. Earnings: fees count in "awaiting customer", "due to you" and "paid out"; ride counts and fare windows stay completed rides only.

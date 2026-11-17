# Cancellation charges — 17 Nov 2026

HUMAN REVIEW REQUIRED: payments.

## Rules (owner's decision, 17 Nov)

| When the customer stops the ride | Charge |
|---|---|
| Before the driver reaches the pickup (`requested`, `accepted`) | free |
| Driver at the pickup, trip not started (`arrived`) | **₹50** cancellation fee |
| During the trip (`in_progress`) — "End trip now" | hourly tariff for the time used: each started hour counts as a whole one, at least 1 h, plus the night surcharge for those hours; never more than the booked fare unless the trip already ran over |
| Trip runs past its booked hours + 15 min | hourly tariff for the started hours used (overtime), never less than booked |
| Customer never comes (driver's no-show) | free (no no-show fee) |

- The driver gets the fee (or the partial fare) like a ride: less MOJUD's commission, in the next payout.
- A fee or partial fare is a normal payment: PhonePe checkout.
- **Nothing owed blocks booking (owner, 17 Nov).** Unpaid rides and fees are carried into the customer's next payment: paying any booking collects everything they owe in one order (`payment_order_items`, migration 0031), and each booking is marked paid with its own part and commission.
- **Overtime (owner, 17 Nov).** A trip that runs past its booked hours (from `startedAt`) by more than 15 min (my pick) is charged the hourly tariff for the started hours used, never less than booked — whether the driver completes it or the customer ends it.
- Waived by ops (`/admin` → settle `waived`): the customer pays nothing, **MOJUD still pays the driver their share**.
- Prices include GST/TDS. MOJUD isn't liable for damage to the customer's car.

## API

Customer booking JSON (`GET /me/bookings`, `GET /me/bookings/{id}`, cancel/end responses):

| Field | Meaning |
|---|---|
| `cancellationFeePaise` | `arrived`: what cancelling now costs (5000). `cancelled`: the fee charged. Omitted when 0. |
| `paymentStatus` | also `due` / `paid` on a cancelled booking with a fee (amount = `cancellationFeePaise`) |
| `bookedFarePaise` | when the final fare was recalculated: the fare as booked. `farePaise > bookedFarePaise` → ran over time; otherwise the customer ended it early |
| `carriedPaise` | what the customer owes on other bookings, collected with this booking's payment (on bookings due or underway) |

`POST /me/bookings/{id}/cancel` `{"reason": "…", "acceptFeePaise": 5000}`

- The new app always sends `acceptFeePaise`: the fee it showed (0 if none).
- Cancelling costs more than `acceptFeePaise` (driver reached the pickup after the dialog opened) →
  409 `{"error": "…", "code": "cancellation_fee", "feePaise": 5000}`, nothing changes.
- No `acceptFeePaise` (apps before user build 9) → cancels free.

`POST /me/bookings/{id}/end` (no body) — customer ends an `in_progress` trip.

- 200 `{"booking": …}` (same envelope as cancel) → `completed`, `farePaise` = charge for the time used, `bookedFarePaise` = booked fare, `paymentStatus: "due"`.
- 409 `{"code": "cannot_end"}` when the trip isn't in progress.
- The driver gets push `ride_ended_early` (`rideId`).

Checkout (`POST /me/bookings/{id}/payment`) and sync (`…/payment/sync`) also take a cancelled booking whose `paymentStatus` is `due`; the amount is the fee.
New bookings are never refused for money owed (no more 409 `payment_due`); checkout `amountPaise` includes `carriedPaise`.

Driver ride JSON: `cancellationFeePaise`, `paymentStatus` (`due`/`paid`/`paid_out`), `sharePaise` on a ride the customer cancelled at the pickup;
`bookedFarePaise` on one they ended early. Earnings: fees count in "awaiting customer", "due to you" and "paid out"; ride counts and fare windows stay completed rides only.

## Server

- Migration `0030_cancellation_charges` (`cancellation_fee_paise`, `booked_fare_paise`, index); `/readyz` probes it.
- Payouts, earnings, stats: only `cash` settlements are excluded from what MOJUD owes drivers (was: any hand settlement).
- Old app builds (no `acceptFeePaise`) cancel free; raise `MIN_BUILD_USER_APP` to 9 once 1.6.0 is out to close that.
- Tests: service unit tests, DB integration tests, `scripts/e2e/run.sh` steps 6 and 10 (102/102 checks).
- Rollouts: `overnight-hardening-rollout.sh` (0030, done 17 Nov 09:34), `carry-dues-rollout.sh` (0031).

# Overnight hardening — 17 Nov 2026

Branch `overnight/production-ready` (worktree `~/Work/Sarthi-overnight`): about 100 commits, ~330 files. **Not pushed. Prod untouched.** Reviews by Claude Fable 5.2 (API credits: $34.85 for 7 reviews incl. a final
review of the whole diff); fixes by Claude Code.

## What changed

| Area | Change |
|---|---|
| Auth | Register needs a verified OTP (was: anyone could open an account on any number), bound to a one-time `registrationTicket` for builds ≥ user 9 / driver 8. 5 SMS/number/hour, per-IP (/64 for IPv6) limits, 1500 texts/day global budget. Session tokens stored as SHA-256 (migration 0020). |
| Config | Boot fails without real SMS provider / at-rest keys / ≥32-char admin token unless `ALLOW_DEV_DEFAULTS=1`. `cmd/rekey` moves bank numbers off the public dev key. |
| Money | Fare priced and checked on the server (was: client-set). Checkout reuses the open order. Payout stamps exactly the rides summed; holds unless driver + bank verified. Unpaid ride → 409 `payment_due`. Duplicate-booking guard + `Idempotency-Key`. Receipts. Net earnings + payout list + payout push. |
| KYC | Rejection sticks. `KYC_AUTO_CLEAR` (default **off** = a person reviews every submission). One Aadhaar identity per driver (verified name/DOB/last-4). Selfie change after clearance → review. Paid checks: Aadhaar first, per-driver lock, 200/day budget. Aadhaar/licence photo uploads → 410. |
| Rides | Coarse area only before accept (no address/plate/phone). Ride watchdog: re-alerts T-3h/T-1h, "no driver yet" T-60, reminders, ops ERROR lines. Fallback alert to all verified drivers. Durable duty (survives restart, auto-off after 2 h silence). Replay-safe accept/steps. No-show action. Start-code lockout. Phones hidden 2 h after a ride. Live location only for this ride's driver. |
| Ops tools | `/admin`: bookings list/assign/cancel/settle (cash/waived), payments needing attention, audit log (`admin_actions`). Admin wrong-token backoff. |
| Privacy | Consent at sign-up (`consentVersion`). Delete account in both apps (anonymise; money records kept). Daily retention sweep. `docs/privacy/data-map.md`. Draft Terms/Privacy pages (placeholders). |
| Apps | `X-App`/`X-Build` headers, `GET /app/config`, 426 update gate + update screen. Help & safety (112, share trip, support). Timeouts, sign-out on 401, double-submit guards, per-account caches, UTC times, KYC upload/camera recovery, pay-confirming state, release-build guards. |
| Ops/infra | `/readyz` (DB + newest migrations present); redeploy gates on it. Server timeouts, 60 s request deadline, body limits (413), memory caps (`MemoryMax=400M`), never-give-up restarts, DB retry at boot. Nightly backup + off-box R2 copy + restore drill. Telegram watchdog. Security headers, CORS allow-list. |
| Charges (17 Nov, owner) | Cancel free until the driver reaches the pickup, ₹50 after; "End trip now" bills the started hours used; overtime charged by the hour (15-min grace); no no-show fee; waived rides still pay the driver; unpaid dues carried into the next payment, never blocking a booking. See `cancellation-charges.md`. |
| Tests | Go: all packages + `-race`. user_app 453, driver_app 245 (were 294 / 90). `scripts/e2e/run.sh` full-flow API check: 102/102. |

## Owner checklist (in order)

1. Review the ~45 commits marked `HUMAN REVIEW REQUIRED` (payments/KYC/auth):
   `git log --grep='HUMAN REVIEW' e559ec4..overnight/production-ready`.
2. Commit main's pending apps-page work, then merge `overnight/production-ready` into main and push.
3. Decided 17 Nov: cancel ₹50 at the pickup (free before), end early by the hour, no no-show fee,
   no damage cover, prices include GST/TDS, driver paid when the customer doesn't pay, dues carried
   (not blocking), overtime charged. Still open: KYC auto-clear [off], start any time after accept [yes].
4. Fill the `[[placeholders]]` in `scripts/apps-page/legal/*.html` (they won't publish until filled).
5. `bash docs/features/overnight-hardening-rollout.sh`. It generates real at-rest keys + rekeys,
   migrates 0015–0029, installs units/timers, redeploys, runs the first backup and smoke checks.
   Optional env in `/etc/sarthi/sarthi.env`: `SUPPORT_PHONE` (wa.me digits),
   `LATEST_BUILD_USER_APP=9`, `LATEST_BUILD_DRIVER_APP=8`, PhonePe webhook creds.
6. Build APKs (auto mode blocked me):
   `cd ~/Work/Sarthi-overnight && ./scripts/build-user-app-apk.sh release && ./scripts/build-driver-app-apk.sh release`
7. Phone test (below), then `PUBLISH_APPS=1` publish.
8. Box: SSH key-only (root password login is on), external uptime monitor on `/readyz`,
   R2 lifecycle rule on `backups/db/`, Caddy `request_body max_size 13MB` (script prints how).

## Phone test (release APKs, prod)

- [ ] Customer: sign up (real SMS), consent box, add car, book a round trip ≥45 min ahead.
- [ ] Driver: sign in, KYC (DigiLocker, licence, bank) → admin approves on `/admin`.
- [ ] Driver on duty sees the request with **area only**; accept → full address.
- [ ] Push: request, assigned, reminder; arrive → start code → complete.
- [ ] Pay a small ride via PhonePe; receipt shows; driver earnings net; `/admin` payouts due.
- [ ] Help & safety row; Delete account dialog (cancel it); kill app mid-payment → re-check.

## Not done (next)

Done on 21 Nov 2026 (on main, server not deployed, apps not built): the multi-stop car (F16); Driver Document View states; refresh on resume; unknown enums; crash reporting (Crashlytics). The driver ride-location service now keeps a wake lock. See `docs/features/receipts-multistop.md` and `payments-review-rollout.sh`.

Still open:

- Feed SQL filter / large-radius query / bounded fan-out (F17/F25).
- Outbox for pushes; `sarthi_core` shared Dart package + one `ApiClient`; Hindi for the customer app.
- Dedicated VPS (Fable's recommendation: the shared box also runs a trading controller).
- A driver foreground service for location for the whole duty shift (Play policy declaration; battery is the owner's call).

# Personal data map

What MOJUD stores about people, where it is kept, how long it is kept, and
what happens when someone asks for erasure. This is an engineering summary,
not legal advice. Confirm the retention periods and DPDP commencement dates
with counsel.

## Where personal data lives

### Postgres (prod VPS)

| Table / columns | Whose | What | Retention |
|---|---|---|---|
| `users` | customer | name, phone, email, date of birth, consent version and time | until erasure |
| `drivers` | driver | name, phone, date of birth, gender, gearbox, Aadhaar last 4 digits, Aadhaar HMACs, licence number, name, expiry and classes, KYC status and notes, consent | until erasure |
| `sessions`, `driver_sessions` | both | SHA-256 of each bearer token, expiry | 30-day TTL, row deleted 7 days after expiry |
| `push_tokens` | both | FCM device token | until sign-out, uninstall, or erasure |
| `cars` | customer | registration, type, gearbox | until deleted by the customer, or erasure |
| `recent_pickups` | customer | addresses and coordinates | capped per user; deleted on erasure |
| `bookings` | both | trip details (`details` JSONB: pickup, stops, car), times, fare, ratings and notes, start code | kept: money record |
| `payment_orders` | customer | PhonePe order ids, UTR, payment mode | kept: money record |
| `driver_payouts` | driver | amount, bank reference | kept: money record |
| `driver_bank_accounts` | driver | holder name, account number (AES-256-GCM), last 4 digits, IFSC, name the bank confirmed | until erasure |
| `driver_documents` | driver | bucket key, hash, review status | until replaced, or erasure |
| `driver_kyc_checks` | driver | log of Surepass calls: kind, outcome, licence number or bank last 4 digits, detail | 180 days |
| `booking_declines` | driver | rides a driver swiped away | until erasure |

### Elsewhere

- **R2 bucket `drivers/<id>/…`**: selfie (older apps also uploaded Aadhaar and licence photos). Kept until replaced or erased.
- **R2 bucket `backups/db/`**: nightly `pg_dump` of everything above. The VPS keeps 14 local dumps (`deploy/backup.sh`, `KEEP=14`). The R2 lifecycle rule is suggested at 30 days in `deploy/README.md`; check it is actually set.
- **Memory only (memstore)**: live driver positions, presence, OTP attempt counters and the session cache. Lost on restart, never written to disk.
- **Logs**:
  - journald: app logs, with ids only, no names or phones by design. Rotation is the OS default; check `journalctl --disk-usage`.
  - Caddy: `/var/log/caddy/sarthi.log`, 10 MiB × 5 files. Holds IPs, paths, and `lat`/`lng` query strings.
- **Devices**:
  - Customer app: session token and recent pickups.
  - Driver app: session token and KYC captures in the app's documents directory.
  - Both apps clear these on sign-out.
- **Processors**:
  - Surepass: Aadhaar through DigiLocker, licence, bank penny-drop.
  - PhonePe: payments.
  - Google FCM: push.
  - Firebase Crashlytics (both apps, release builds only): crash stack traces, app build, device model, a Firebase installation ID. No user id, phone, name or email is set (`lib/core/services/crash_reporting.dart`).
  - Fast2SMS: OTP SMS, so phone numbers.
  - Ola and Google: map searches and coordinates.

## Consent

- Both apps show a required "I agree to the Terms and Privacy Policy" checkbox at sign-up.
  - Terms: `https://apps.mojud.life/terms`
  - Privacy Policy: `https://apps.mojud.life/privacy`
- Both apps send `consentVersion` (currently `2026-11`) to `POST /auth/register` and `POST /driver/auth/register`.
- The server stores `consent_version` and `consented_at`. Accounts made before this, or from builds that don't send a version, read NULL, meaning no consent was recorded.
- When the policy text changes, bump the version in both apps' `lib/core/config/legal.dart`.

## Erasure

- **Routes**:
  - `DELETE /me/account`: customer app, Profile.
  - `DELETE /driver/account`: driver app, Account.
  - `POST /admin/accounts/{customer|driver}/{id}/erase`: requests that arrive by email or phone.
- **Refused with 409 `account_busy`** while the account has:
  - a ride that is accepted, arrived or in progress, or
  - a completed ride with a fare that hasn't been paid.
- **Accounts are anonymised, not deleted**, because `bookings` and `payment_orders` reference them with RESTRICT (migration 0018). Both kinds:
  - Name becomes "Deleted user".
  - Phone becomes `deleted-<id>` and email `deleted-<id>@deleted.invalid`, so the same number can sign up again.
  - Date of birth becomes 1900-01-01 for customers and NULL for drivers.
  - `erased_at` is set.
  - Every session is deleted from Postgres and from the memstore cache, so old tokens get 401 at once.
  - Push tokens are deleted.
- **Customer**:
  - Saved cars and recent pickups are deleted.
  - Requests that no driver has taken are cancelled with the reason "account deleted".
- **Driver**:
  - Bank account, declines and every KYC field (DigiLocker, licence, selfie hash, notes) are cleared. KYC status goes back to `incomplete`.
  - The driver is taken off the online index.
  - The licence number and Aadhaar digits are removed from `driver_kyc_checks`. The rows stay for the cost audit until the 180-day sweep.
  - Each KYC image is deleted from the bucket first, then its row. If a bucket delete fails, the row is kept and the daily sweep retries it.
- **Kept**:
  - Bookings, payment orders, payouts, ratings and trip details. These are money records and need confirming with counsel.
  - Earnings already paid but not yet paid out stay on the books. `GET /admin/payouts/due` lists them "on hold: no bank account on file", and ops pays them by contacting the driver.
  - The Aadhaar HMAC fingerprints, but only for a driver a reviewer rejected, so that identity can't come back on a fresh account.
- **Backups** still hold erased data until they age out (14 days locally, plus the R2 rule). After restoring a dump, erase again every account erased since the dump was taken. Erasures are logged as `erasure: account erased` lines with the account ids.

## Retention sweep

- `service/retention_service.go` runs at boot and then every 24 h.
- It deletes:
  - sessions expired more than 7 days ago
  - `driver_kyc_checks` older than 180 days
  - leftover KYC images of erased drivers
- OTPs are never stored, because Fast2SMS holds the code and memstore holds the counters. No other logs are kept in Postgres.

## Open decisions

- **Booking addresses**: `bookings.details` keeps pickup and stop addresses, coordinates and the car registration forever. Decide with counsel on a cap, e.g. scrub them after the tax-record period.
- **Ops dashboard**: `/admin/stats` still counts erased accounts as customers or drivers.
- **Backups**: confirm the R2 lifecycle rule exists on `backups/db/`.

## Breach runbook (outline)

1. **Contain**:
   - Rotate `ADMIN_TOKEN`, the database password, the R2 keys and the Surepass, PhonePe and FCM credentials.
   - Revoke sessions with `DELETE FROM sessions; DELETE FROM driver_sessions;` and restart.
   - Block the source in Caddy or the firewall.
2. **Preserve**:
   - Copy journald, Caddy logs and `pg_stat_activity` before rotation or restart.
   - Snapshot the VPS.
3. **Assess**:
   - Which tables, buckets or logs were reachable, and over what window.
   - How many people are affected, by kind.
   - Whether bank numbers were exposed: they are encrypted, but check whether `DOCUMENT_ENCRYPTION_KEY` leaked too.
4. **Notify**. Confirm the timelines with counsel:
   - Data Protection Board and each affected person, without delay (DPDP Act 2023 s.8(6)). The DPDP Rules 2025 ask for a detailed report to the Board within 72 hours.
   - CERT-In within 6 hours of noticing the incident (CERT-In Directions of 28 Apr 2022).
   - Processors whose data was involved: Surepass, PhonePe.
5. **Recover**:
   - Patch the cause.
   - Restore from backup if needed, then re-apply the erasures made since the dump.
   - Watch for misuse.
6. **Review**: write up the timeline and the fix in `docs/`, and update this map.

"""End-to-end run of the Sarthi server on :8097. Prints PASS/FAIL per check and a step table."""
import json, random, subprocess, sys, uuid, datetime as dt
import urllib.request, urllib.error

BASE = "http://127.0.0.1:8097"
ADMIN = "dev-admin-token-0123456789abcdef0123"
IST = dt.timezone(dt.timedelta(hours=5, minutes=30))
results = {}  # step -> list of (name, ok, detail)


def req(method, path, body=None, token=None, headers=None, raw=None):
    h = {"Content-Type": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    h.update(headers or {})
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    r = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            txt = resp.read().decode()
            return resp.status, (json.loads(txt) if txt.strip().startswith(("{", "[")) else txt), dict(resp.headers)
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        try:
            j = json.loads(txt)
        except Exception:
            j = txt
        return e.code, j, dict(e.headers)


def check(step, name, ok, detail=""):
    results.setdefault(step, []).append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + f"[{step}] {name}" + ("" if ok else f"  -> {str(detail)[:600]}"))
    return ok


def psql(sql):
    out = subprocess.run(["docker", "exec", "-i", "server-db-1", "psql", "-U", "sarthi", "-d", "sarthi",
                          "-tA", "-c", sql], capture_output=True, text=True)
    if out.returncode != 0:
        print("psql error:", out.stderr)
    return out.stdout.strip()


def phone():
    return "+91" + random.choice("6789") + "".join(random.choice("0123456789") for _ in range(9))


def customer_signup(step, name, verify=True):
    p = phone()
    s, j, _ = req("POST", "/auth/otp", {"phoneE164": p})
    check(step, f"{name}: /auth/otp", s in (200, 202), (s, j))
    if verify:
        s, j, _ = req("POST", "/auth/otp/verify", {"phoneE164": p, "code": "123456"})
        check(step, f"{name}: verify -> registered=false", s == 200 and j.get("registered") is False, (s, j))
    s, j, _ = req("POST", "/auth/register", {"phoneE164": p, "name": name, "email": f"{name.lower()}@example.com",
                                             "dateOfBirth": "1990-01-01", "consentVersion": "2026-11"})
    return p, s, j


def tariff(hours, luxury=False):
    first, second, extra = (196, 330, 110) if luxury else (139, 240, 100)
    return first if hours <= 1 else second if hours == 2 else second + (hours - 2) * extra


def night(start_ist, hours):
    finish = start_ist + dt.timedelta(hours=hours)
    ns = start_ist.replace(hour=22, minute=0, second=0, microsecond=0)
    if start_ist > ns:
        ns = start_ist
    if finish <= ns:
        return 0
    mins = int((finish - ns).total_seconds() // 60)
    nh = (mins + 59) // 60
    return 0 if nh == 0 else 50 + 24 * nh


PICKUP = {"address": "Flat 12B, 4th Cross, Indiranagar, Bengaluru 560038",
          "point": {"latitude": 12.97194, "longitude": 77.64115}}


def round_trip(start_ist, hours, car, fare=None):
    return {"tripType": "roundTrip", "details": {
        "scheduledAt": start_ist.strftime("%Y-%m-%dT%H:%M:%S.000"),
        "pickup": PICKUP, "hours": hours,
        "fare": fare if fare is not None else tariff(hours) + night(start_ist, hours),
        "car": car}}


def main():
    # ---- 1. customer auth
    S = "1"
    p_unverified = phone()
    req("POST", "/auth/otp", {"phoneE164": p_unverified})
    s, j, _ = req("POST", "/auth/register", {"phoneE164": p_unverified, "name": "Sneaky", "email": "sneaky@example.com",
                                             "dateOfBirth": "1990-01-01", "consentVersion": "2026-11"})
    check(S, "register without verify -> 401 otp_not_verified", s == 401 and j.get("code") == "otp_not_verified", (s, j))
    pa, s, j = customer_signup(S, "Asha")
    check(S, "register with consentVersion -> 201 + token", s in (200, 201) and j.get("token"), (s, j))
    ta = j.get("token")
    if not ta:
        return
    cid = j["user"]["id"]
    cons = psql(f"SELECT coalesce(consent_version,'') FROM users WHERE id='{cid}'")
    check(S, "consent_version stored", cons == "2026-11", cons)
    s, j, _ = req("GET", "/auth/me", token=ta)
    check(S, "GET /auth/me", s == 200, (s, j))
    # The registration ticket: builds that send it (user_app 9+, driver_app
    # 8+) must, and nobody else can spend their pass by phone alone.
    for app, build, prefix, body in (
            ("user_app", "9", "/auth", {"name": "Tara", "email": "tara@example.com",
                                        "dateOfBirth": "1990-01-01", "consentVersion": "2026-11"}),
            ("driver_app", "8", "/driver/auth", {"name": "Tara Singh", "consentVersion": "2026-11"})):
        hdr = {"X-App": app, "X-Build": build}
        pt = phone()
        req("POST", prefix + "/otp", {"phoneE164": pt}, headers=hdr)
        s, j, _ = req("POST", prefix + "/otp/verify", {"phoneE164": pt, "code": "123456"}, headers=hdr)
        ticket = j.get("registrationTicket") if isinstance(j, dict) else None
        check(S, f"{app} {build}: verify returns a registrationTicket", s == 200 and ticket, (s, j))
        s, j, _ = req("POST", prefix + "/register", dict(body, phoneE164=pt))
        check(S, f"{app}: someone else registering by phone alone -> 401",
              s == 401 and j.get("code") == "otp_not_verified", (s, j))
        s, j, _ = req("POST", prefix + "/register", dict(body, phoneE164=pt), headers=hdr)
        check(S, f"{app} {build}: register without the ticket -> 401", s == 401, (s, j))
        s, j, _ = req("POST", prefix + "/register", dict(body, phoneE164=pt, registrationTicket=ticket), headers=hdr)
        check(S, f"{app} {build}: register with the ticket -> 201", s == 201 and j.get("token"), (s, j))

    # ---- 2. car + app config
    S = "2"
    s, j, _ = req("POST", "/me/cars", {"registration": "KA 01 AB 1234", "carType": "sedan", "transmission": "manual"},
                  token=ta)
    check(S, "add car", s in (200, 201), (s, j))
    car = j.get("car", {}) if isinstance(j, dict) else {}
    car_payload = {"registration": car.get("registration", "KA01AB1234"), "carType": "sedan", "transmission": "manual"}
    s, j, _ = req("GET", "/app/config")
    check(S, "GET /app/config", s == 200 and isinstance(j, dict), (s, j))
    print("   app/config:", json.dumps(j)[:300])
    s, j, _ = req("GET", "/me/cars", token=ta, headers={"X-App": "user_app", "X-Build": "9"})
    check(S, "X-App/X-Build with min=0 -> 200", s == 200, (s, j))

    # ---- 3. booking
    S = "3"
    start1 = (dt.datetime.now(IST) + dt.timedelta(minutes=47)).replace(second=0, microsecond=0)
    body = round_trip(start1, 2, car_payload)
    s, j, _ = req("POST", "/me/bookings", round_trip(start1, 2, car_payload, fare=body["details"]["fare"] - 1),
                  token=ta, headers={"Idempotency-Key": str(uuid.uuid4())})
    check(S, "tampered fare -> 400 fare_mismatch", s == 400 and j.get("code") == "fare_mismatch", (s, j))
    too_soon = round_trip(dt.datetime.now(IST) + dt.timedelta(minutes=20), 2, car_payload)
    s, j, _ = req("POST", "/me/bookings", too_soon, token=ta, headers={"Idempotency-Key": str(uuid.uuid4())})
    check(S, "booking 20 min ahead -> 400", s == 400, (s, j))
    key = str(uuid.uuid4())
    s, j, _ = req("POST", "/me/bookings", body, token=ta, headers={"Idempotency-Key": key})
    check(S, "book round trip +47min -> 202", s == 202 and j.get("id"), (s, j, body))
    b1 = j.get("id")
    if not b1:
        return
    s, j, _ = req("POST", "/me/bookings", body, token=ta, headers={"Idempotency-Key": key})
    check(S, "retry same key -> 200 duplicate same id", s == 200 and j.get("id") == b1 and j.get("duplicate"), (s, j))
    fare_db = psql(f"SELECT fare_paise FROM bookings WHERE id='{b1}'")
    check(S, "stored fare = tariff", fare_db == str(body["details"]["fare"] * 100), fare_db)

    # ---- 4. driver
    S = "4"
    pd = phone()
    s, j, _ = req("POST", "/driver/auth/otp", {"phoneE164": pd})
    check(S, "driver otp", s in (200, 202), (s, j))
    s, j, _ = req("POST", "/driver/auth/otp/verify", {"phoneE164": pd, "code": "123456"})
    check(S, "driver verify", s == 200, (s, j))
    s, j, _ = req("POST", "/driver/auth/register", {"phoneE164": pd, "name": "Ravi Kumar", "consentVersion": "2026-11"})
    check(S, "driver register", s in (200, 201) and j.get("token"), (s, j))
    td, did = j.get("token"), (j.get("driver") or {}).get("id")
    s, j, _ = req("GET", "/driver/rides/requests", token=td)
    check(S, "unverified driver can't see requests (403)", s == 403, (s, j))
    psql(f"""UPDATE drivers SET kyc_status='verified', kyc_submitted_at=now(), transmission='both',
             date_of_birth='1988-05-05', gender='male', aadhaar_last4='1234', aadhaar_verified_at=now(),
             driving_license_number='KA0120100001234', license_verified_at=now(), license_name='RAVI KUMAR',
             license_valid_until=(now() + interval '5 years')::date, license_vehicle_classes='{{LMV}}'
             WHERE id='{did}'""")
    # sign in again via OTP as the now-verified driver
    s, j, _ = req("POST", "/driver/auth/otp", {"phoneE164": pd})
    s, j, _ = req("POST", "/driver/auth/otp/verify", {"phoneE164": pd, "code": "123456"})
    check(S, "verified driver signs in via OTP", s == 200 and j.get("registered") and j.get("token"), (s, j))
    td = j.get("token") or td
    near = {"lat": 12.9725, "lng": 77.6420}
    s, j, _ = req("PUT", "/driver/duty", {"online": True, **near}, token=td)
    check(S, "PUT /driver/duty online", s in (200, 204), (s, j))
    s, j, _ = req("GET", f"/driver/rides/requests?lat={near['lat']}&lng={near['lng']}", token=td)
    rides = j.get("rides", []) if isinstance(j, dict) else []
    mine = [r for r in rides if r["id"] == b1]
    check(S, "request visible in feed", s == 200 and len(mine) == 1, (s, [r["id"] for r in rides]))
    if mine:
        r = mine[0]
        txt = json.dumps(r)
        check(S, "coarse: approximate=true", r.get("approximate") is True, r)
        check(S, "coarse: no exact address", "Flat 12B" not in txt and "4th Cross" not in txt, r.get("pickup"))
        check(S, "coarse: no plate", "KA01AB1234" not in txt and not (r.get("car") or {}).get("registration"), r.get("car"))
        check(S, "coarse: no customer/phone", "customer" not in r and pa not in txt, r.get("customer"))
        check(S, "coarse: exact coords hidden", abs(r["pickup"]["lat"] - 12.97194) > 1e-6 or abs(r["pickup"]["lng"] - 77.64115) > 1e-6, r["pickup"])
        print("   coarse ride:", txt[:400])
    s, j, _ = req("POST", f"/driver/rides/{b1}/accept", token=td)
    check(S, "accept -> 200", s == 200 and j.get("ride", {}).get("id") == b1, (s, j))
    first_accept = j.get("ride", {})
    s, j, _ = req("POST", f"/driver/rides/{b1}/accept", token=td)
    check(S, "accept again -> 200 same ride", s == 200 and j.get("ride", {}).get("id") == b1
          and j["ride"].get("status") == first_accept.get("status"), (s, j))
    full = j.get("ride", {})
    ftxt = json.dumps(full)
    check(S, "after accept: exact address", "Flat 12B" in full.get("pickup", {}).get("address", ""), full.get("pickup"))
    check(S, "after accept: plate", (full.get("car") or {}).get("registration") == "KA01AB1234", full.get("car"))
    check(S, "after accept: customer phone", (full.get("customer") or {}).get("phoneE164") == pa, full.get("customer"))
    check(S, "after accept: not approximate", not full.get("approximate"), ftxt[:300])

    # ---- 5. customer sees driver + code; arrive / start / complete
    S = "5"
    s, j, _ = req("GET", "/me/bookings", token=ta)
    bk = next((b for b in j.get("bookings", []) if b["id"] == b1), {})
    check(S, "customer sees assigned driver", (bk.get("driver") or {}).get("name") == "Ravi Kumar", bk.get("driver"))
    check(S, "customer sees driver phone", (bk.get("driver") or {}).get("phoneE164") == pd, bk.get("driver"))
    code = bk.get("startOtp")
    check(S, "customer sees start code", bool(code) and len(code) == 4, bk.get("startOtp"))
    s, j, _ = req("POST", f"/driver/rides/{b1}/start", {"otp": code}, token=td)
    check(S, "start before arrive -> 409", s == 409, (s, j))
    s, j, _ = req("POST", f"/driver/rides/{b1}/arrive", token=td)
    check(S, "arrive", s == 200 and j.get("ride", {}).get("status") == "arrived", (s, j))
    s, j, _ = req("POST", f"/driver/rides/{b1}/start", {"otp": "0000" if code != "0000" else "1111"}, token=td)
    check(S, "wrong code -> 4xx", 400 <= s < 500, (s, j))
    s, j, _ = req("POST", f"/driver/rides/{b1}/start", {"otp": code}, token=td)
    check(S, "start with code (ride ~47 min ahead)", s == 200 and j.get("ride", {}).get("status") == "in_progress", (s, j))
    s, j, _ = req("POST", f"/driver/rides/{b1}/complete", token=td)
    check(S, "complete", s == 200 and j.get("ride", {}).get("status") == "completed", (s, j))

    # ---- 6. payment due, pay, receipt, earnings, payouts
    S = "6"
    s, j, _ = req("GET", "/me/bookings", token=ta)
    bk = next((b for b in j.get("bookings", []) if b["id"] == b1), {})
    check(S, "booking paymentStatus=due", bk.get("paymentStatus") == "due", bk.get("paymentStatus"))
    start2 = (dt.datetime.now(IST) + dt.timedelta(hours=3)).replace(second=0, microsecond=0)
    s, j, _ = req("POST", "/me/bookings", round_trip(start2, 1, car_payload), token=ta,
                  headers={"Idempotency-Key": str(uuid.uuid4())})
    check(S, "new booking -> 409 payment_due", s == 409 and j.get("code") == "payment_due" and j.get("bookingId") == b1, (s, j))
    # erasure while unpaid (step 8 check)
    s, j, _ = req("DELETE", "/me/account", token=ta)
    check("8", "erase customer with unpaid ride -> 409", s == 409 and j.get("code") == "account_busy", (s, j))
    s, j, _ = req("POST", f"/me/bookings/{b1}/payment", token=ta)
    check(S, "checkout via fake PhonePe", s == 200 and j.get("checkout", {}).get("token"), (s, j))
    s, j, _ = req("POST", f"/me/bookings/{b1}/payment/sync", token=ta)
    check(S, "sync -> paid", s == 200 and j.get("booking", {}).get("paymentStatus") == "paid", (s, j))
    s, j, _ = req("GET", "/me/bookings", token=ta)
    bk = next((b for b in j.get("bookings", []) if b["id"] == b1), {})
    check(S, "receipt block on booking", isinstance(bk.get("payment"), dict) and bk["payment"], bk.get("payment"))
    print("   receipt:", json.dumps(bk.get("payment")), "breakdown:", json.dumps(bk.get("fareBreakdown")))
    fare = bk.get("farePaise", 0)
    s, j, _ = req("GET", "/driver/earnings", token=td)
    print("   earnings:", json.dumps(j)[:700])
    net = fare - (fare * 1300 + 5000) // 10000  # 13% commission, rounded
    pay = j.get("payments", {}) if isinstance(j, dict) else {}
    check(S, "driver earnings show net share", net in [v for v in pay.values() if isinstance(v, int)]
          or net in [v for p in j.values() if isinstance(p, dict) for v in p.values() if isinstance(v, int)], (net, j))
    s, j, _ = req("GET", "/admin/payouts/due", token=ADMIN)
    drv = [d for d in j.get("drivers", [])] if isinstance(j, dict) else []
    me = [d for d in drv if d.get("driverId") == did]
    check(S, "admin payouts/due lists driver", s == 200 and len(me) == 1, (s, j))
    if me:
        check(S, "payout amount = net share", me[0].get("amountPaise") == net, (me[0], net))
    s, j, _ = req("POST", "/me/bookings", round_trip(start2, 1, car_payload), token=ta,
                  headers={"Idempotency-Key": str(uuid.uuid4())})
    check(S, "booking after paying -> 202", s == 202, (s, j))
    b2 = j.get("id")

    # ---- 7. ops
    S = "7"
    s, j, _ = req("GET", "/admin/bookings", token=ADMIN)
    ids = [b.get("id") for b in j.get("bookings", [])] if isinstance(j, dict) else []
    check(S, "GET /admin/bookings has both", s == 200 and b1 in ids and b2 in ids, (s, str(j)[:300]))
    s, j, _ = req("POST", f"/admin/bookings/{b2}/assign", {"driverId": did}, token=ADMIN)
    check(S, "admin assign", s == 200, (s, j))
    s, j, _ = req("GET", "/me/bookings", token=ta)
    bk2 = next((b for b in j.get("bookings", []) if b["id"] == b2), {})
    check(S, "customer sees assigned driver on b2", bk2.get("status") == "accepted" and bk2.get("driver"), bk2)
    s, j, _ = req("DELETE", "/me/account", token=ta)
    check("8", "erase customer with active ride -> 409", s == 409 and j.get("code") == "account_busy", (s, j))
    s, j, _ = req("POST", f"/admin/bookings/{b2}/cancel", {"reason": "e2e test"}, token=ADMIN)
    check(S, "admin cancel", s == 200, (s, j))
    s, j, _ = req("GET", "/admin/actions", token=ADMIN)
    acts = j.get("actions", []) if isinstance(j, dict) else []
    kinds = [a.get("action") for a in acts if b2 in json.dumps(a)]
    check(S, "audit rows for assign+cancel", "booking.assign" in kinds and "booking.cancel" in kinds, (kinds, str(acts[:3])[:400]))
    s, j, _ = req("GET", "/admin/bookings", token="wrong-token")
    check(S, "admin with bad token -> 401", s == 401, (s, j))

    # ---- 8. erasure
    S = "8"
    pb, s, j = customer_signup(S, "Bina")
    tb = j.get("token")
    check(S, "throwaway customer registered", bool(tb), (s, j))
    s, j, _ = req("DELETE", "/me/account", token=tb)
    check(S, "DELETE /me/account -> 200", s == 200, (s, j))
    s, j, _ = req("GET", "/auth/me", token=tb)
    check(S, "old token -> 401", s == 401, (s, j))
    s, j, _ = req("GET", "/me/bookings", token=tb)
    check(S, "old token on /me/bookings -> 401", s == 401, (s, j))

    # ---- 9. readiness + hardening
    S = "9"
    s, j, h = req("GET", "/readyz")
    check(S, "/readyz 200", s == 200, (s, j))
    for hdr in ("Strict-Transport-Security", "X-Content-Type-Options", "Referrer-Policy", "X-Frame-Options"):
        check(S, f"header {hdr}", hdr in h, list(h))
    big = json.dumps({"tripType": "roundTrip", "details": {"pad": "x" * (300 << 10)}}).encode()
    s, j, _ = req("POST", "/me/bookings", token=ta, raw=big)
    check(S, "oversized JSON -> 413", s == 413, (s, j))
    s, j, _ = req("POST", "/auth/otp", raw=json.dumps({"phoneE164": "+91" + "9" * 10, "pad": "x" * (300 << 10)}).encode())
    check(S, "oversized JSON on public route -> 413", s == 413, (s, j))
    pc = phone()
    codes = [req("POST", "/auth/otp", {"phoneE164": pc})[0] for _ in range(7)]
    check(S, "OTP send past cap -> 429", codes[-1] == 429 and 429 in codes, codes)
    s, j, h = req("POST", "/auth/otp", {"phoneE164": pc})
    check(S, "429 carries Retry-After", s == 429 and "Retry-After" in h, (s, j, h.get("Retry-After")))

    # ---- 10. cancellation charges (docs/features/cancellation-charges.md)
    S = "10"

    def at_pickup(hours, lead):
        start = (dt.datetime.now(IST) + dt.timedelta(minutes=lead)).replace(second=0, microsecond=0)
        s, j, _ = req("POST", "/me/bookings", round_trip(start, hours, car_payload), token=ta,
                      headers={"Idempotency-Key": str(uuid.uuid4())})
        bid = j.get("id")
        a = req("POST", f"/driver/rides/{bid}/accept", token=td)[0]
        r = req("POST", f"/driver/rides/{bid}/arrive", token=td)[0]
        check(S, f"{hours} h ride booked, accepted, driver at pickup", s == 202 and a == 200 and r == 200, (s, j, a, r))
        return bid

    def mine(bid):
        return next((b for b in req("GET", "/me/bookings", token=ta)[1].get("bookings", []) if b["id"] == bid), {})

    c1 = at_pickup(2, 52)  # a start of its own, or the duplicate guard returns b1
    check(S, "at pickup: cancellationFeePaise 5000 shown", mine(c1).get("cancellationFeePaise") == 5000, mine(c1))
    s, j, _ = req("POST", f"/me/bookings/{c1}/cancel", {"reason": "e2e", "acceptFeePaise": 0}, token=ta)
    check(S, "cancel at pickup having seen no fee -> 409 cancellation_fee",
          s == 409 and j.get("code") == "cancellation_fee" and j.get("feePaise") == 5000, (s, j))
    check(S, "refused cancel left the ride arrived", mine(c1).get("status") == "arrived", mine(c1).get("status"))
    s, j, _ = req("POST", f"/me/bookings/{c1}/cancel", {"reason": "e2e", "acceptFeePaise": 5000}, token=ta)
    cb = j.get("booking", {}) if isinstance(j, dict) else {}
    check(S, "cancel accepting the fee -> cancelled, fee due",
          s == 200 and cb.get("status") == "cancelled" and cb.get("cancellationFeePaise") == 5000
          and cb.get("paymentStatus") == "due", (s, j))
    start3 = (dt.datetime.now(IST) + dt.timedelta(hours=5)).replace(second=0, microsecond=0)
    s, j, _ = req("POST", "/me/bookings", round_trip(start3, 1, car_payload), token=ta,
                  headers={"Idempotency-Key": str(uuid.uuid4())})
    check(S, "unpaid fee blocks the next booking -> 409 payment_due",
          s == 409 and j.get("code") == "payment_due" and j.get("bookingId") == c1, (s, j))
    s, j, _ = req("POST", f"/me/bookings/{c1}/payment", token=ta)
    check(S, "fee checkout is for 5000", s == 200 and j.get("checkout", {}).get("amountPaise") == 5000, (s, j))
    s, j, _ = req("POST", f"/me/bookings/{c1}/payment/sync", token=ta)
    check(S, "fee sync -> paid", s == 200 and j.get("booking", {}).get("paymentStatus") == "paid", (s, j))
    s, j, _ = req("GET", f"/driver/rides", token=td)
    dr = next((r for r in (j.get("rides", []) if isinstance(j, dict) else []) if r.get("id") == c1), {})
    check(S, "driver sees the fee and their share", dr.get("cancellationFeePaise") == 5000
          and dr.get("paymentStatus") == "paid" and dr.get("sharePaise") == 4350, dr)

    e1 = at_pickup(3, 58)
    booked = mine(e1).get("farePaise")
    code = mine(e1).get("startOtp")
    s, j, _ = req("POST", f"/me/bookings/{e1}/end", token=ta)
    check(S, "end before the trip starts -> 409 cannot_end", s == 409 and j.get("code") == "cannot_end", (s, j))
    s, j, _ = req("POST", f"/driver/rides/{e1}/start", {"otp": code}, token=td)
    started = dt.datetime.now(IST)
    check(S, "3 h trip started", s == 200, (s, j))
    s, j, _ = req("POST", f"/me/bookings/{e1}/end", token=ta)
    eb = j.get("booking", {}) if isinstance(j, dict) else {}
    want = min(booked, (tariff(1) + night(started, 1)) * 100)
    check(S, "end early -> completed, charged one started hour, booked fare kept",
          s == 200 and eb.get("status") == "completed" and eb.get("farePaise") == want
          and eb.get("bookedFarePaise") == booked and eb.get("paymentStatus") == "due", (s, j, want, booked))
    s, j, _ = req("POST", f"/me/bookings/{e1}/payment", token=ta)
    check(S, "ended trip checkout is the charge", s == 200 and j.get("checkout", {}).get("amountPaise") == want, (s, j))
    s, j, _ = req("POST", f"/me/bookings/{e1}/payment/sync", token=ta)
    check(S, "ended trip paid", s == 200 and j.get("booking", {}).get("paymentStatus") == "paid", (s, j))


if __name__ == "__main__":
    random.seed()
    try:
        main()
    finally:
        print("\n==== step summary ====")
        for step in sorted(results):
            fails = [n for n, ok, _ in results[step] if not ok]
            print(f"step {step}: {'PASS' if not fails else 'FAIL'} ({len(results[step]) - len(fails)}/{len(results[step])})"
                  + (f"  failed: {fails}" if fails else ""))

"""Extra probes. phase=pre (server with min build 0) or phase=post (restarted with MIN_BUILD_USER_APP=100)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from e2e import req, check, phone, customer_signup, results, ADMIN  # noqa: E402

STATE = os.path.join(os.environ.get("E2E_TMP", "/tmp"), "sarthi_e2e_extras_state.json")
phase = sys.argv[1]
if phase == "pre":
    S = "x"
    p, s, j = customer_signup(S, "Chitra")
    tok = j.get("token")
    s, j, _ = req("DELETE", "/me/account", token=tok)
    check(S, "erase Chitra", s == 200, (s, j))
    # Same phone signs up again after deletion.
    s, j, _ = req("POST", "/auth/otp", {"phoneE164": p})
    s, j, _ = req("POST", "/auth/otp/verify", {"phoneE164": p, "code": "123456"})
    check(S, "erased phone verifies as new (registered=false)", s == 200 and j.get("registered") is False, (s, j))
    s, j, _ = req("POST", "/auth/register", {"phoneE164": p, "name": "Chitra", "email": "c@example.com",
                                             "dateOfBirth": "1990-01-01", "consentVersion": "2026-11"})
    check(S, "erased phone can register again", s == 201 and j.get("token"), (s, j))
    json.dump({"token": j.get("token")}, open(STATE, "w"))
    s, j, _ = req("POST", "/payments/phonepe/webhook", {"event": "checkout.order.completed"},
                  headers={"Authorization": "x"})
    check(S, "webhook without configured creds refused", s in (401, 404), (s, j))
    s, j, _ = req("GET", "/admin/stats", token=ADMIN)
    check(S, "/admin/stats 200", s == 200, (s, str(j)[:200]))
    print("   stats:", json.dumps(j)[:500])
else:
    S = "2b"
    tok = json.load(open(STATE))["token"]
    s, j, _ = req("GET", "/app/config")
    check(S, "/app/config shows minBuild 100", s == 200 and j["apps"]["user_app"]["minBuild"] == 100, (s, j))
    s, j, _ = req("GET", "/auth/me", token=tok, headers={"X-App": "user_app", "X-Build": "9"})
    check(S, "old build -> 426 update_required", s == 426 and j.get("code") == "update_required"
          and j.get("downloadUrl"), (s, j))
    s, j, _ = req("GET", "/auth/me", token=tok, headers={"X-App": "user_app", "X-Build": "100"})
    check(S, "current build -> 200 (and session survived restart)", s == 200, (s, j))
    s, j, _ = req("GET", "/auth/me", token=tok)
    check(S, "no X-App headers (legacy) -> passes", s == 200, (s, j))
    s, j, _ = req("POST", "/auth/otp", {"phoneE164": phone()}, headers={"X-App": "user_app", "X-Build": "9"})
    check(S, "old build blocked on /auth/otp too", s == 426, (s, j))
    s, j, _ = req("GET", "/readyz", headers={"X-App": "user_app", "X-Build": "9"})
    check(S, "/readyz exempt", s == 200, (s, j))
    s, j, _ = req("GET", "/admin/bookings", token=ADMIN, headers={"X-App": "user_app", "X-Build": "9"})
    check(S, "/admin exempt", s == 200, (s, str(j)[:100]))
    s, j, _ = req("GET", "/driver/auth/me", headers={"X-App": "driver_app", "X-Build": "9"})
    check(S, "driver app (min 0) not blocked -> 401 without token", s == 401, (s, j))

for step in sorted(results):
    fails = [n for n, ok, _ in results[step] if not ok]
    print(f"step {step}: {'PASS' if not fails else 'FAIL'} ({len(results[step]) - len(fails)}/{len(results[step])})")

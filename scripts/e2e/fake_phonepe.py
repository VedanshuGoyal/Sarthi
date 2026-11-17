# Tiny fake of the PhonePe PG endpoints the server calls: token, create order, order status.
import json, time, sys, threading
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

orders = {}
lock = threading.Lock()


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n)
        if self.path.endswith("/oauth/token"):
            return self._send(200, {"access_token": "fake-token", "expires_at": int(time.time()) + 3600})
        if self.path.endswith("/checkout/v2/sdk/order"):
            if "fake-token" not in self.headers.get("Authorization", ""):
                return self._send(401, {"code": "UNAUTHORIZED"})
            d = json.loads(body)
            oid = "OMO" + d["merchantOrderId"][-12:]
            with lock:
                orders[d["merchantOrderId"]] = d["amount"]
            return self._send(200, {"orderId": oid, "state": "PENDING", "token": "sdk-tok-" + oid,
                                    "expireAt": int(time.time() * 1000) + d["expireAfter"] * 1000})
        self._send(404, {"code": "NOT_FOUND"})

    def do_GET(self):
        if "/checkout/v2/order/" in self.path and "/status" in self.path:
            mid = self.path.split("/checkout/v2/order/")[1].split("/status")[0]
            with lock:
                amt = orders.get(mid)
            if amt is None:
                return self._send(404, {"code": "ORDER_NOT_FOUND"})
            return self._send(200, {
                "orderId": "OMO" + mid[-12:], "state": "COMPLETED", "amount": amt,
                "paymentDetails": [{"transactionId": "TXN" + mid[-8:], "paymentMode": "UPI_INTENT",
                                    "state": "COMPLETED",
                                    "splitInstruments": [{"rail": {"utr": "UTR123456"}}]}]})
        self._send(404, {"code": "NOT_FOUND"})

    def log_message(self, fmt, *a):
        sys.stderr.write("fake-phonepe: " + (fmt % a) + "\n")


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8098), H).serve_forever()

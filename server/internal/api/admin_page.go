package api

import (
	_ "embed"
	"net/http"
)

// adminPage is the back office: the KYC review queue and driver payouts. It
// holds no data itself; it calls the /admin/* routes with the token the
// person using it pastes in, kept only for that browser tab.
//
//go:embed admin_page.html
var adminPage []byte

// AdminPage handles GET /admin.
func AdminPage(w http.ResponseWriter, _ *http.Request) {
	h := w.Header()
	h.Set("Content-Type", "text/html; charset=utf-8")
	h.Set("Cache-Control", "no-store")
	h.Set("X-Frame-Options", "DENY")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("X-Robots-Tag", "noindex, nofollow")
	h.Set("Content-Security-Policy",
		"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "+
			"img-src blob:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
	w.Write(adminPage)
}

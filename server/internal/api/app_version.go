package api

import (
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The client compatibility contract. APKs are side-loaded, so old builds stay
// in the field for good and the server can't make anyone update; instead every
// build of the apps says who it is on every request:
//
//	X-App:   user_app | driver_app
//	X-Build: the build number, the +N of the app's pubspec version (0 for a
//	         debug or unversioned build)
//
// A build below its app's minimum gets 426 update_required, and the app shows
// its update screen. Requests without the headers ("legacy": every APK
// shipped before them, plus browsers and webhooks) are never blocked.
// GET /app/config tells an app the minimum and latest builds at startup.

// App identifiers, as sent in X-App.
const (
	AppUser   = "user_app"
	AppDriver = "driver_app"
)

// AppBuilds is one app's place in the contract.
type AppBuilds struct {
	// MinBuild is the oldest build still served; older ones get 426. 0 turns
	// the gate off (observe only).
	MinBuild int
	// LatestBuild is the newest published build.
	LatestBuild int
}

// AppPolicy is the contract for both apps.
type AppPolicy struct {
	// DownloadURL is where the current APKs are published.
	DownloadURL string
	// SupportPhone is the ops WhatsApp number the apps' "Contact support"
	// opens (digits with country code). Empty hides that button.
	SupportPhone string
	UserApp      AppBuilds
	DriverApp    AppBuilds
}

func (p AppPolicy) builds(app string) AppBuilds {
	if app == AppDriver {
		return p.DriverApp
	}
	return p.UserApp
}

// appClient is the app build behind a request.
type appClient struct {
	app   string
	build int
}

// identifyClient reads X-App and X-Build. ok is false when the request doesn't
// name one of our apps and a build number: a legacy APK, a browser, a webhook,
// or headers we can't read — none of which is ever blocked.
func identifyClient(r *http.Request) (c appClient, ok bool) {
	app := r.Header.Get("X-App")
	if app != AppUser && app != AppDriver {
		return appClient{}, false
	}
	build, err := strconv.Atoi(strings.TrimSpace(r.Header.Get("X-Build")))
	if err != nil || build < 0 {
		return appClient{}, false
	}
	return appClient{app: app, build: build}, true
}

// firstTicketBuild is each app's first build that sends the registration
// ticket from OTP verify back at sign-up (service.AuthService.Register).
var firstTicketBuild = map[string]int{AppUser: 9, AppDriver: 8}

// sendsRegistrationTicket reports whether r comes from a build of app that
// sends the registration ticket. Older builds, and requests that don't say
// which build they are, sign up with the phone-only pass.
func sendsRegistrationTicket(r *http.Request, app string) bool {
	c, ok := identifyClient(r)
	return ok && c.app == app && c.build >= firstTicketBuild[app]
}

// firstCarOnEveryTripBuild is the user app's first build that asks for the
// customer's car on every trip type, multi-stop too (Fable F16). Builds
// before it — 1.6.0 (+9) and older — never send a car with a multi-stop
// booking, so theirs are still taken without one.
const firstCarOnEveryTripBuild = 10

// asksCarOnEveryTrip reports whether r comes from a user app build that
// asks for the customer's car on every trip type, so its bookings must name
// one. Older builds, debug runs (build 0) and requests that don't say which
// build they are book as before.
func asksCarOnEveryTrip(r *http.Request) bool {
	c, ok := identifyClient(r)
	return ok && c.app == AppUser && c.build >= firstCarOnEveryTripBuild
}

// exemptFromBuildGate lists the routes no app build is turned away from:
// probes, the contract itself, the back office, and the URLs third parties
// call (PhonePe's webhook, DigiLocker's redirect).
func exemptFromBuildGate(path string) bool {
	switch path {
	case "/healthz", "/readyz", "/app/config", "/users",
		"/payments/phonepe/webhook", "/kyc/digilocker/done":
		return true
	}
	return strings.HasPrefix(path, "/admin")
}

// requireMinBuild answers 426 update_required to an app build older than its
// app's minimum. Build 0 (a debug run) is never blocked, and nor is a request
// that doesn't identify itself; those are only counted (see legacyCounter).
func requireMinBuild(next http.Handler, policy AppPolicy) http.Handler {
	legacy := newLegacyCounter(time.Hour)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if exemptFromBuildGate(r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}
		c, ok := identifyClient(r)
		if !ok {
			legacy.add(strings.HasPrefix(r.URL.Path, "/driver/"))
			next.ServeHTTP(w, r)
			return
		}
		if c.build > 0 && c.build < policy.builds(c.app).MinBuild {
			writeUpdateRequired(w, c.app, policy.DownloadURL)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// updateRequiredResponse is the error envelope plus where to get the update.
type updateRequiredResponse struct {
	errorResponse
	DownloadURL string `json:"downloadUrl"`
}

// writeUpdateRequired sends 426. The error is a full sentence because builds
// that predate the update screen show it as it is.
func writeUpdateRequired(w http.ResponseWriter, app, downloadURL string) {
	name := "MOJUD"
	if app == AppDriver {
		name = "MOJUD Driver"
	}
	where := strings.TrimSuffix(strings.TrimPrefix(downloadURL, "https://"), "/")
	writeJSON(w, http.StatusUpgradeRequired, updateRequiredResponse{
		errorResponse: errorResponse{
			Error: fmt.Sprintf("This version of %s is out of date. "+
				"Please install the latest version from %s to continue.", name, where),
			Code: "update_required",
		},
		DownloadURL: downloadURL,
	})
}

// legacyCounter counts requests that carry no X-App/X-Build, guessing the app
// from the path, and logs the tally at most once per interval rather than a
// line per request. It's how the owner can tell when the last pre-contract
// APKs have gone quiet, so it logs at info: the server runs slog's default
// handler, which drops debug lines.
type legacyCounter struct {
	mu           sync.Mutex
	every        time.Duration
	now          func() time.Time
	since        time.Time
	user, driver int
}

func newLegacyCounter(every time.Duration) *legacyCounter {
	return &legacyCounter{every: every, now: time.Now}
}

// add counts one request; driver says it was for a /driver/ route.
func (c *legacyCounter) add(driver bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if driver {
		c.driver++
	} else {
		c.user++
	}
	now := c.now()
	if c.since.IsZero() {
		c.since = now
		return
	}
	if now.Sub(c.since) < c.every {
		return
	}
	slog.Info("app version: requests without X-App/X-Build",
		"userApp", c.user, "driverApp", c.driver,
		"window", now.Sub(c.since).Round(time.Second).String())
	c.user, c.driver, c.since = 0, 0, now
}

// counts reports the tally since the last report.
func (c *legacyCounter) counts() (user, driver int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.user, c.driver
}

// appBuildsJSON is one app's entry in GET /app/config.
type appBuildsJSON struct {
	MinBuild    int    `json:"minBuild"`
	LatestBuild int    `json:"latestBuild"`
	DownloadURL string `json:"downloadUrl"`
}

// appConfigResponse is GET /app/config, keyed by the X-App values. Fields
// are only ever added.
type appConfigResponse struct {
	SupportPhone string `json:"supportPhone,omitempty"`
	Apps         struct {
		UserApp   appBuildsJSON `json:"user_app"`
		DriverApp appBuildsJSON `json:"driver_app"`
	} `json:"apps"`
}

// appConfig serves GET /app/config: public, read by both apps at startup.
func appConfig(policy AppPolicy) http.HandlerFunc {
	entry := func(b AppBuilds) appBuildsJSON {
		return appBuildsJSON{
			MinBuild: b.MinBuild,
			// A latest build below the minimum would read as "no update";
			// the minimum is at least as new as anything served.
			LatestBuild: max(b.LatestBuild, b.MinBuild),
			DownloadURL: policy.DownloadURL,
		}
	}
	var body appConfigResponse
	body.SupportPhone = policy.SupportPhone
	body.Apps.UserApp = entry(policy.UserApp)
	body.Apps.DriverApp = entry(policy.DriverApp)
	return func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, body)
	}
}

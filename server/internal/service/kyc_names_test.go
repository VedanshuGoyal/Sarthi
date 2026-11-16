package service

import (
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

func TestReviewIssues(t *testing.T) {
	now := time.Now()
	cleared := func() domain.DriverKYC {
		return domain.DriverKYC{
			Profile: domain.DriverProfile{
				FullName:          "Asha Singh",
				LicenseName:       "ASHA SINGH",
				LicenseValidUntil: &domain.Date{Time: now.AddDate(5, 0, 0)},
				LicenseClasses:    []string{"LMV"},
			},
			BankAccount: &domain.DriverBankAccount{VerifiedAt: &now, VerifiedName: "MRS ASHA SINGH"},
		}
	}
	cases := []struct {
		name  string
		edit  func(*domain.DriverKYC)
		issue string // "" means none
	}{
		{"everything agrees", func(*domain.DriverKYC) {}, ""},
		{"licence name missing", func(k *domain.DriverKYC) { k.Profile.LicenseName = "" }, "licence holder's name not on record"},
		{"licence in another name", func(k *domain.DriverKYC) { k.Profile.LicenseName = "RAVI SINGH" }, "licence name"},
		{"bank name missing", func(k *domain.DriverKYC) { k.BankAccount.VerifiedName = "" }, "account holder's name"},
		{"bank in a one-word lookalike", func(k *domain.DriverKYC) {
			k.Profile.FullName, k.Profile.LicenseName = "Asha Kumari", "ASHA KUMARI"
			k.BankAccount.VerifiedName = "ASHA DEVI"
		}, "bank account name"},
	}
	for _, c := range cases {
		k := cleared()
		c.edit(&k)
		issues := strings.Join(reviewIssues(k), "; ")
		if c.issue == "" && issues != "" {
			t.Errorf("%s: issues = %q, want none", c.name, issues)
		}
		if c.issue != "" && !strings.Contains(issues, c.issue) {
			t.Errorf("%s: issues = %q, want one about %q", c.name, issues, c.issue)
		}
	}
}

func TestNamesMatch(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"Asha Kumari", "ASHA KUMARI", true},
		{"Asha Kumari Singh", "ASHA SINGH", true},
		{"Asha Kumari Singh", "Asha K Singh", true},
		{"Asha Singh", "SINGH ASHA", true},
		{"Asha Singh", "MRS ASHA SINGH", true},
		{"Vedanshu Goyal", "VEDANSHUGOYAL", true},
		{"A. Yadav", "Anil Yadav", true},
		{"Asha Singh", "Ravi Singh", false},
		{"Asha Singh", "A S", false}, // initials alone prove nothing
		{"Asha Singh", "", false},
		// "Kumari" is dropped as an honorific, so "Asha Kumari" is the one
		// word ASHA, which on its own would match any Asha.
		{"Asha Kumari", "Asha Kumari Ravi Singh", false},
		{"Asha Kumari", "Asha Devi", false},
		{"Ramesh", "Ramesh K", false},
		{"Ramesh", "RAMESH", true},
		{"Asha Kumari Singh", "Asha Devi", false},
	}
	for _, tc := range cases {
		if got := namesMatch(tc.a, tc.b); got != tc.want {
			t.Errorf("namesMatch(%q, %q) = %v, want %v", tc.a, tc.b, got, tc.want)
		}
		if got := namesMatch(tc.b, tc.a); got != tc.want {
			t.Errorf("namesMatch(%q, %q) = %v, want %v (reversed)", tc.b, tc.a, got, tc.want)
		}
	}
}

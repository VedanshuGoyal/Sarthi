package service

import "testing"

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
		{"Asha Kumari", "Asha Kumari Ravi Singh", true},
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

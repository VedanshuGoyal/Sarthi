package config

import "testing"

// KYC_AUTO_CLEAR defaults to off — at launch a person reviews every driver —
// and a typo fails the boot rather than silently picking a side.
func TestLoadKYCAutoClear(t *testing.T) {
	for _, tc := range []struct {
		env     string
		want    bool
		wantErr bool
	}{
		{"", false, false},
		{"false", false, false},
		{"true", true, false},
		{"1", true, false},
		{"yes", false, true},
	} {
		t.Run(tc.env, func(t *testing.T) {
			t.Setenv("DATABASE_URL", "postgres://localhost/test")
			t.Setenv("ALLOW_DEV_DEFAULTS", "1")
			t.Setenv("KYC_AUTO_CLEAR", tc.env)
			cfg, err := Load()
			if (err != nil) != tc.wantErr {
				t.Fatalf("Load: err = %v, want error %v", err, tc.wantErr)
			}
			if err == nil && cfg.KYCAutoClear != tc.want {
				t.Errorf("KYCAutoClear = %v, want %v", cfg.KYCAutoClear, tc.want)
			}
		})
	}
}

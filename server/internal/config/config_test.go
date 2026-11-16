package config

import (
	"strings"
	"testing"
)

func TestLoadCommission(t *testing.T) {
	for _, tc := range []struct {
		env     string
		want    int64
		wantErr bool
	}{
		{"", 1300, false}, // MOJUD's 13% when unset
		{"13", 1300, false},
		{"12.5", 1250, false},
		{"0", 0, false},
		{"101", 0, true},
		{"ten", 0, true},
	} {
		t.Setenv("COMMISSION_PERCENT", tc.env)
		got, err := loadCommission()
		if (err != nil) != tc.wantErr || got != tc.want {
			t.Errorf("COMMISSION_PERCENT=%q: got %d, %v; want %d, err=%v", tc.env, got, err, tc.want, tc.wantErr)
		}
	}
}

func TestLoadSecretsRequiresKeysOutsideDev(t *testing.T) {
	const key = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=" // 32 bytes, base64
	for _, tc := range []struct {
		name         string
		key, pepper  string
		allowDev     bool
		wantErr, dev bool
	}{
		{name: "neither, dev allowed", allowDev: true, dev: true},
		{name: "neither, production", wantErr: true},
		{name: "only the key", key: key, allowDev: true, wantErr: true},
		{name: "only the pepper", pepper: "p", allowDev: true, wantErr: true},
		{name: "both", key: key, pepper: "p"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("DOCUMENT_ENCRYPTION_KEY", tc.key)
			t.Setenv("DOCUMENT_HASH_PEPPER", tc.pepper)
			got, err := loadSecrets(tc.allowDev)
			if (err != nil) != tc.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tc.wantErr)
			}
			if err == nil && got.Development != tc.dev {
				t.Fatalf("Development = %v, want %v", got.Development, tc.dev)
			}
		})
	}
}

func TestLoadFailsClosedWithoutDevFlag(t *testing.T) {
	base := func(t *testing.T) {
		t.Setenv("DATABASE_URL", "postgres://localhost/test")
		t.Setenv("DOCUMENT_ENCRYPTION_KEY", "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=")
		t.Setenv("DOCUMENT_HASH_PEPPER", "pepper")
		t.Setenv("FAST2SMS_API_KEY", "k")
		t.Setenv("FAST2SMS_OTP_ID", "id")
		t.Setenv("ADMIN_TOKEN", strings.Repeat("a", MinAdminTokenLength))
		t.Setenv("ALLOW_DEV_DEFAULTS", "")
	}

	t.Run("fully configured boots", func(t *testing.T) {
		base(t)
		if _, err := Load(); err != nil {
			t.Fatalf("Load: %v", err)
		}
	})
	t.Run("missing SMS provider fails", func(t *testing.T) {
		base(t)
		t.Setenv("FAST2SMS_API_KEY", "")
		if _, err := Load(); err == nil {
			t.Fatal("want an error: the dev OTP would accept every account")
		}
	})
	t.Run("short admin token fails", func(t *testing.T) {
		base(t)
		t.Setenv("ADMIN_TOKEN", "short")
		if _, err := Load(); err == nil {
			t.Fatal("want an error for a short admin token")
		}
	})
	t.Run("dev flag allows the fallbacks", func(t *testing.T) {
		base(t)
		t.Setenv("FAST2SMS_API_KEY", "")
		t.Setenv("DOCUMENT_ENCRYPTION_KEY", "")
		t.Setenv("DOCUMENT_HASH_PEPPER", "")
		t.Setenv("ADMIN_TOKEN", "dev-admin")
		t.Setenv("ALLOW_DEV_DEFAULTS", "1")
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if !cfg.AllowDevDefaults || !cfg.Secrets.Development {
			t.Fatal("dev defaults should be in use")
		}
	})
}

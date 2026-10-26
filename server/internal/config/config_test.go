package config

import "testing"

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

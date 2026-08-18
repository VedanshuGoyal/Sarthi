package secret

import (
	"bytes"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
)

// testKey is a fixed 32-byte key; these tests never touch production material.
func testKey(t *testing.T) []byte {
	t.Helper()
	key := bytes.Repeat([]byte{0x2a}, KeyLength)
	return key
}

func TestCipherRoundTrip(t *testing.T) {
	c, err := NewCipher(testKey(t))
	if err != nil {
		t.Fatalf("NewCipher: %v", err)
	}

	const accountNumber = "123456789012345"
	sealed, err := c.Seal([]byte(accountNumber))
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}
	if bytes.Contains(sealed, []byte(accountNumber)) {
		t.Fatal("sealed value still contains the plaintext account number")
	}

	opened, err := c.Open(sealed)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if string(opened) != accountNumber {
		t.Errorf("Open = %q, want %q", opened, accountNumber)
	}
}

// Sealing the same value twice must produce different bytes, otherwise the
// column would leak which drivers share an account number.
func TestSealIsNotDeterministic(t *testing.T) {
	c, err := NewCipher(testKey(t))
	if err != nil {
		t.Fatalf("NewCipher: %v", err)
	}

	first, err := c.Seal([]byte("123456789"))
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}
	second, err := c.Seal([]byte("123456789"))
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}
	if bytes.Equal(first, second) {
		t.Error("sealing the same value twice produced identical ciphertext")
	}
}

func TestOpenRejectsTamperedAndForeignCiphertext(t *testing.T) {
	c, err := NewCipher(testKey(t))
	if err != nil {
		t.Fatalf("NewCipher: %v", err)
	}
	sealed, err := c.Seal([]byte("123456789"))
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}

	tests := map[string]struct {
		cipher *Cipher
		input  []byte
	}{
		"flipped bit": {cipher: c, input: flipLastBit(sealed)},
		"truncated":   {cipher: c, input: sealed[:4]},
		"empty":       {cipher: c, input: nil},
		"wrong key": {
			cipher: mustCipher(t, bytes.Repeat([]byte{0x3b}, KeyLength)),
			input:  sealed,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := tc.cipher.Open(tc.input); !errors.Is(err, ErrDecrypt) {
				t.Errorf("Open error = %v, want ErrDecrypt", err)
			}
		})
	}
}

func TestNewCipherRejectsWrongKeyLength(t *testing.T) {
	for _, length := range []int{0, 16, 31, 33} {
		if _, err := NewCipher(make([]byte, length)); err == nil {
			t.Errorf("NewCipher accepted a %d-byte key", length)
		}
	}
}

func TestParseKey(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString(testKey(t))
	key, err := ParseKey(encoded)
	if err != nil {
		t.Fatalf("ParseKey: %v", err)
	}
	if !bytes.Equal(key, testKey(t)) {
		t.Error("ParseKey did not round-trip the key")
	}

	for name, encoded := range map[string]string{
		"not base64": "not base64!!",
		"too short":  base64.StdEncoding.EncodeToString([]byte("short")),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseKey(encoded); err == nil {
				t.Error("ParseKey accepted an invalid key")
			}
		})
	}
}

func TestFingerprint(t *testing.T) {
	pepper := []byte("pepper")
	const aadhaar = "123456789012"

	got := Fingerprint(pepper, aadhaar)

	// Stable, so the duplicate-Aadhaar index works across restarts.
	if again := Fingerprint(pepper, aadhaar); got != again {
		t.Error("Fingerprint is not stable for the same input")
	}
	// Distinct per value, or the unique index would reject unrelated drivers.
	if other := Fingerprint(pepper, "123456789013"); got == other {
		t.Error("different Aadhaar numbers produced the same fingerprint")
	}
	// Keyed, so a leaked table can't be brute-forced without the pepper.
	if unpeppered := Fingerprint([]byte("other"), aadhaar); got == unpeppered {
		t.Error("fingerprint does not depend on the pepper")
	}
	// The number itself must not be recoverable from the output.
	if strings.Contains(got, aadhaar) {
		t.Error("fingerprint contains the Aadhaar number")
	}
}

func mustCipher(t *testing.T, key []byte) *Cipher {
	t.Helper()
	c, err := NewCipher(key)
	if err != nil {
		t.Fatalf("NewCipher: %v", err)
	}
	return c
}

func flipLastBit(b []byte) []byte {
	out := bytes.Clone(b)
	out[len(out)-1] ^= 0x01
	return out
}

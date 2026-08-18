// Package secret handles the two things Sarthi does with sensitive personal
// numbers: encrypt what it must be able to read back, fingerprint what it
// only needs to compare.
//
//   - Bank account numbers are encrypted ([Cipher]). Payouts need the real
//     number, so a one-way hash is not an option; AES-256-GCM with a key held
//     outside the database means a stolen dump alone is useless.
//   - Aadhaar numbers are fingerprinted ([Fingerprint]) and never stored. The
//     only question the server asks of an Aadhaar number is "have I seen this
//     one before?", which a keyed hash answers without retaining it. The key
//     (pepper) matters: plain SHA-256 over a 12-digit space is trivially
//     brute-forced, HMAC with a secret pepper is not.
package secret

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
)

// KeyLength is the required encryption key size, in bytes (AES-256).
const KeyLength = 32

// ErrDecrypt is returned when sealed data can't be opened — wrong key, or
// tampered ciphertext. Deliberately opaque: callers must not be able to tell
// the two apart.
var ErrDecrypt = errors.New("could not decrypt value")

// Cipher seals and opens values with AES-256-GCM.
type Cipher struct {
	aead cipher.AEAD
}

// NewCipher builds a Cipher from a 32-byte key.
func NewCipher(key []byte) (*Cipher, error) {
	if len(key) != KeyLength {
		return nil, fmt.Errorf("encryption key must be %d bytes, got %d", KeyLength, len(key))
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("building cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("building GCM: %w", err)
	}
	return &Cipher{aead: aead}, nil
}

// ParseKey decodes a base64 (standard, padded) 32-byte key, as read from the
// environment.
func ParseKey(encoded string) ([]byte, error) {
	key, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("decoding key: %w", err)
	}
	if len(key) != KeyLength {
		return nil, fmt.Errorf("key must decode to %d bytes, got %d", KeyLength, len(key))
	}
	return key, nil
}

// Seal encrypts plaintext, returning nonce||ciphertext. Each call uses a fresh
// random nonce, so sealing the same value twice gives different bytes and the
// stored column leaks no equality information.
func (c *Cipher) Seal(plaintext []byte) ([]byte, error) {
	nonce := make([]byte, c.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("generating nonce: %w", err)
	}
	// Append the ciphertext onto the nonce so the result carries its own nonce.
	return c.aead.Seal(nonce, nonce, plaintext, nil), nil
}

// Open reverses [Cipher.Seal].
func (c *Cipher) Open(sealed []byte) ([]byte, error) {
	n := c.aead.NonceSize()
	if len(sealed) < n {
		return nil, ErrDecrypt
	}
	plaintext, err := c.aead.Open(nil, sealed[:n], sealed[n:], nil)
	if err != nil {
		return nil, ErrDecrypt
	}
	return plaintext, nil
}

// Fingerprint returns a stable hex HMAC-SHA256 of value under pepper. Equal
// values fingerprint equally (that's the point — it powers the "this Aadhaar
// is already registered" check), but the value cannot be recovered and cannot
// be guessed without the pepper.
func Fingerprint(pepper []byte, value string) string {
	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte(value))
	return hex.EncodeToString(mac.Sum(nil))
}

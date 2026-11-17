package main

import (
	"bytes"
	"testing"

	"github.com/sarthi/server/internal/config"
	"github.com/sarthi/server/internal/secret"
)

func TestReseal(t *testing.T) {
	oldC, _ := secret.NewCipher(config.DevEncryptionKey())
	newC, _ := secret.NewCipher(bytes.Repeat([]byte{7}, secret.KeyLength))
	otherC, _ := secret.NewCipher(bytes.Repeat([]byte{9}, secret.KeyLength))

	sealed, _ := oldC.Seal([]byte("123456789012"))
	moved, changed, err := reseal(oldC, newC, sealed)
	if err != nil || !changed {
		t.Fatalf("first pass: changed=%v err=%v", changed, err)
	}
	if plain, err := newC.Open(moved); err != nil || string(plain) != "123456789012" {
		t.Fatalf("resealed value should open under the new key: %q %v", plain, err)
	}

	// Rerun: already on the new key, left alone.
	again, changed, err := reseal(oldC, newC, moved)
	if err != nil || changed || !bytes.Equal(again, moved) {
		t.Fatalf("rerun should be a no-op: changed=%v err=%v", changed, err)
	}

	// Sealed under some third key: refuse rather than corrupt.
	foreign, _ := otherC.Seal([]byte("x"))
	if _, _, err := reseal(oldC, newC, foreign); err == nil {
		t.Fatal("want an error for a value under neither key")
	}
}

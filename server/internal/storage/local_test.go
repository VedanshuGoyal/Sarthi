package storage

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLocalPutGetDelete(t *testing.T) {
	ctx := context.Background()
	store := newLocal(t)
	const key = "drivers/abc/selfie/1234.jpg"
	want := []byte("pretend this is a JPEG")

	if err := store.Put(ctx, key, want, "image/jpeg"); err != nil {
		t.Fatalf("Put: %v", err)
	}

	body, err := store.Get(ctx, key)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	got, err := io.ReadAll(body)
	if err != nil {
		t.Fatalf("reading object: %v", err)
	}
	if err := body.Close(); err != nil {
		t.Fatalf("closing object: %v", err)
	}
	if string(got) != string(want) {
		t.Errorf("Get = %q, want %q", got, want)
	}

	if err := store.Delete(ctx, key); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := store.Get(ctx, key); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get after Delete = %v, want ErrNotFound", err)
	}
}

// Cleanup paths call Delete without checking whether anything is there, so a
// missing key must not be an error.
func TestLocalDeleteMissingKeyIsNotAnError(t *testing.T) {
	if err := newLocal(t).Delete(context.Background(), "drivers/x/selfie/none.jpg"); err != nil {
		t.Errorf("Delete of a missing key = %v, want nil", err)
	}
}

func TestLocalPutOverwrites(t *testing.T) {
	ctx := context.Background()
	store := newLocal(t)
	const key = "drivers/abc/aadhaar/1.jpg"

	if err := store.Put(ctx, key, []byte("first"), "image/jpeg"); err != nil {
		t.Fatalf("first Put: %v", err)
	}
	if err := store.Put(ctx, key, []byte("second"), "image/jpeg"); err != nil {
		t.Fatalf("second Put: %v", err)
	}

	got := readAll(t, store, key)
	if got != "second" {
		t.Errorf("object = %q, want %q", got, "second")
	}
}

// A traversal here would let a key write anywhere the process can reach. Keys
// are server-generated today, so this is defence in depth — which is exactly
// why it needs a test rather than an assumption.
func TestLocalRejectsKeysEscapingTheRoot(t *testing.T) {
	ctx := context.Background()
	store := newLocal(t)

	keys := map[string]string{
		"parent traversal":  "../escaped.jpg",
		"nested traversal":  "drivers/../../escaped.jpg",
		"absolute path":     "/etc/passwd",
		"backslash":         `drivers\..\escaped.jpg`,
		"empty":             "",
		"traversal to root": "..",
	}

	for name, key := range keys {
		t.Run(name, func(t *testing.T) {
			if err := store.Put(ctx, key, []byte("payload"), "image/jpeg"); err == nil {
				t.Errorf("Put(%q) succeeded, want an error", key)
			}
			if _, err := store.Get(ctx, key); err == nil {
				t.Errorf("Get(%q) succeeded, want an error", key)
			}
			if err := store.Delete(ctx, key); err == nil {
				t.Errorf("Delete(%q) succeeded, want an error", key)
			}
		})
	}
}

// Anyone reading a KYC image off the disk should need the server's own
// account, not merely a login on the box.
func TestLocalWritesRestrictivePermissions(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	store, err := NewLocal(dir)
	if err != nil {
		t.Fatalf("NewLocal: %v", err)
	}

	const key = "drivers/abc/selfie/1.jpg"
	if err := store.Put(ctx, key, []byte("bytes"), "image/jpeg"); err != nil {
		t.Fatalf("Put: %v", err)
	}

	info, err := os.Stat(filepath.Join(dir, filepath.FromSlash(key)))
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Errorf("object mode = %v, want 0600", perm)
	}
}

// Put must not leave the temp file it writes through lying around.
func TestLocalLeavesNoTempFiles(t *testing.T) {
	dir := t.TempDir()
	store, err := NewLocal(dir)
	if err != nil {
		t.Fatalf("NewLocal: %v", err)
	}
	if err := store.Put(context.Background(), "a/b.jpg", []byte("bytes"), "image/jpeg"); err != nil {
		t.Fatalf("Put: %v", err)
	}

	entries, err := os.ReadDir(filepath.Join(dir, "a"))
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 1 || entries[0].Name() != "b.jpg" {
		t.Errorf("directory contents = %v, want just b.jpg", entries)
	}
}

func TestLocalCannotSignURLs(t *testing.T) {
	_, err := newLocal(t).SignedGetURL(context.Background(), "a/b.jpg", time.Minute)
	if !errors.Is(err, ErrNoSignedURL) {
		t.Errorf("SignedGetURL = %v, want ErrNoSignedURL", err)
	}
}

func newLocal(t *testing.T) *Local {
	t.Helper()
	store, err := NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("NewLocal: %v", err)
	}
	return store
}

func readAll(t *testing.T, store *Local, key string) string {
	t.Helper()
	body, err := store.Get(context.Background(), key)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	defer func() {
		if err := body.Close(); err != nil {
			t.Errorf("closing object: %v", err)
		}
	}()
	got, err := io.ReadAll(body)
	if err != nil {
		t.Fatalf("reading object: %v", err)
	}
	return string(got)
}

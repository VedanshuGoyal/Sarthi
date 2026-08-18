package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Local stores objects as files under a root directory. Development only: it
// ties the bytes to one machine's disk, which is exactly what production must
// not do (a VPS rebuild would lose every driver's KYC).
type Local struct {
	root string
}

// NewLocal returns a disk-backed Blob rooted at dir, creating it if needed.
func NewLocal(dir string) (*Local, error) {
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, fmt.Errorf("resolving storage dir: %w", err)
	}
	// 0700: KYC images are readable only by the account running the server.
	if err := os.MkdirAll(abs, 0o700); err != nil {
		return nil, fmt.Errorf("creating storage dir: %w", err)
	}
	return &Local{root: abs}, nil
}

// Put writes body atomically: a temp file in the destination directory,
// renamed into place, so a crash mid-write can't leave a truncated image that
// later reads would treat as valid.
func (l *Local) Put(_ context.Context, key string, body []byte, _ string) error {
	path, err := l.path(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("creating object dir: %w", err)
	}

	tmp, err := os.CreateTemp(filepath.Dir(path), ".upload-*")
	if err != nil {
		return fmt.Errorf("creating temp object: %w", err)
	}
	tmpName := tmp.Name()
	// Best-effort cleanup: a no-op once the rename below has succeeded.
	defer func() {
		_ = os.Remove(tmpName)
	}()

	if _, err := tmp.Write(body); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("writing object: %w", err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("securing object: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("closing object: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("publishing object: %w", err)
	}
	return nil
}

// Get opens the object file.
func (l *Local) Get(_ context.Context, key string) (io.ReadCloser, error) {
	path, err := l.path(key)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("opening object: %w", err)
	}
	return f, nil
}

// Delete removes the object file; a missing file is not an error.
func (l *Local) Delete(_ context.Context, key string) error {
	path, err := l.path(key)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("deleting object: %w", err)
	}
	return nil
}

// SignedGetURL always fails: there is nothing in front of the local directory
// to honour a signature. Callers stream via Get instead.
func (l *Local) SignedGetURL(context.Context, string, time.Duration) (string, error) {
	return "", ErrNoSignedURL
}

// path maps an object key to a file path under the root, rejecting anything
// that would escape it. Keys are server-generated today, but a traversal bug
// here would be catastrophic, so it is checked rather than assumed.
func (l *Local) path(key string) (string, error) {
	if key == "" || strings.HasPrefix(key, "/") || strings.Contains(key, "\\") {
		return "", fmt.Errorf("invalid object key %q", key)
	}
	path := filepath.Join(l.root, filepath.FromSlash(key))
	// filepath.Join cleans "..", so compare the result against the root.
	if path != l.root && !strings.HasPrefix(path, l.root+string(os.PathSeparator)) {
		return "", fmt.Errorf("invalid object key %q", key)
	}
	return path, nil
}

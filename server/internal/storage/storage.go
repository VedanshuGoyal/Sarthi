// Package storage stores opaque binary objects (today: driver KYC images)
// outside PostgreSQL.
//
// Images are deliberately not kept in the database. They are write-once,
// read-rarely, and roughly half a megabyte each — putting them in a column
// would bloat every pg_dump and every WAL segment with bytes no query ever
// filters on. The database keeps the key; this package keeps the bytes.
//
// Two backends implement [Blob]: [NewS3] for production (any S3-compatible
// service — Cloudflare R2, Backblaze B2, AWS S3, MinIO) and [NewLocal] for
// development, so a local run needs no cloud credentials.
package storage

import (
	"context"
	"errors"
	"io"
	"time"
)

// ErrNotFound is returned by Get and Delete when no object has that key.
var ErrNotFound = errors.New("object not found")

// ErrNoSignedURL is returned by SignedGetURL on backends that cannot hand out
// a direct time-limited link — the local-disk backend. Callers fall back to
// streaming the object through [Blob.Get].
var ErrNoSignedURL = errors.New("backend does not support signed URLs")

// Blob is a keyed object store. Keys are slash-separated paths
// ("drivers/<id>/selfie/<uuid>.jpg"); implementations treat them as opaque.
//
// Defined here rather than consumer-side because both the service that writes
// documents and any future reader share exactly this view of it.
type Blob interface {
	// Put stores body under key, overwriting any existing object.
	Put(ctx context.Context, key string, body []byte, contentType string) error

	// Get opens the object for reading. The caller closes the reader.
	Get(ctx context.Context, key string) (io.ReadCloser, error)

	// Delete removes the object. Deleting a missing key is not an error —
	// cleanup paths should be idempotent.
	Delete(ctx context.Context, key string) error

	// SignedGetURL returns a URL that grants read access to key for ttl,
	// or [ErrNoSignedURL] if the backend cannot issue one.
	SignedGetURL(ctx context.Context, key string, ttl time.Duration) (string, error)
}

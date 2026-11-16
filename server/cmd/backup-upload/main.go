// Command backup-upload copies one database dump to the S3-compatible bucket
// (Cloudflare R2 in production) under backups/db/, so a lost or rebuilt VPS
// does not take the only copies with it. deploy/backup.sh runs it nightly.
//
//	backup-upload /var/backups/sarthi/sarthi-20261117-0330.sql.gz
//
// It reads the same S3_* variables as the server (from /etc/sarthi/sarthi.env).
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/sarthi/server/internal/storage"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		slog.Error("backup upload failed", "error", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: backup-upload <dump file>")
	}
	path := args[0]
	body, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	opts := storage.S3Options{
		Bucket:          os.Getenv("S3_BUCKET"),
		Region:          os.Getenv("S3_REGION"),
		Endpoint:        os.Getenv("S3_ENDPOINT"),
		AccessKeyID:     os.Getenv("S3_ACCESS_KEY_ID"),
		SecretAccessKey: os.Getenv("S3_SECRET_ACCESS_KEY"),
		UsePathStyle:    os.Getenv("S3_USE_PATH_STYLE") == "true",
	}
	if opts.Bucket == "" || opts.AccessKeyID == "" || opts.SecretAccessKey == "" {
		return fmt.Errorf("S3_BUCKET, S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY are required")
	}
	if opts.Region == "" {
		opts.Region = "auto"
	}
	blob, err := storage.NewS3(opts)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	key := "backups/db/" + filepath.Base(path)
	if err := blob.Put(ctx, key, body, "application/gzip"); err != nil {
		return fmt.Errorf("uploading %s: %w", key, err)
	}
	slog.Info("backup uploaded", "key", key, "bytes", len(body))
	return nil
}

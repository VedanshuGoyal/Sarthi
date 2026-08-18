package storage

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/aws/smithy-go"
)

// S3 stores objects in any S3-compatible service. Production uses Cloudflare
// R2 (no egress fees, S3 API), but the same code covers AWS S3, Backblaze B2
// and MinIO — only the endpoint and region differ.
type S3 struct {
	client  *s3.Client
	presign *s3.PresignClient
	bucket  string
}

// S3Options configures [NewS3].
type S3Options struct {
	Bucket string
	// Region is "auto" for R2; a real region for AWS S3.
	Region string
	// Endpoint is the service URL, e.g.
	// https://<account-id>.r2.cloudflarestorage.com. Empty means AWS S3.
	Endpoint string
	// AccessKeyID and SecretAccessKey authenticate every request.
	AccessKeyID     string
	SecretAccessKey string
	// UsePathStyle addresses buckets as <endpoint>/<bucket>/<key> instead of
	// <bucket>.<endpoint>/<key>. Needed by MinIO; harmless on R2.
	UsePathStyle bool
}

// NewS3 builds an S3-compatible Blob from static credentials.
func NewS3(opts S3Options) (*S3, error) {
	if opts.Bucket == "" {
		return nil, errors.New("storage: S3 bucket is required")
	}
	if opts.AccessKeyID == "" || opts.SecretAccessKey == "" {
		return nil, errors.New("storage: S3 credentials are required")
	}
	region := opts.Region
	if region == "" {
		region = "auto"
	}

	cfg := aws.Config{
		Region: region,
		Credentials: credentials.NewStaticCredentialsProvider(
			opts.AccessKeyID, opts.SecretAccessKey, "",
		),
		// Recent SDK versions add a CRC32 checksum header to every upload and
		// expect one back. Non-AWS implementations are inconsistent about
		// both, so ask for checksums only where the operation requires them.
		RequestChecksumCalculation: aws.RequestChecksumCalculationWhenRequired,
		ResponseChecksumValidation: aws.ResponseChecksumValidationWhenRequired,
	}

	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if opts.Endpoint != "" {
			o.BaseEndpoint = aws.String(opts.Endpoint)
		}
		o.UsePathStyle = opts.UsePathStyle
	})

	return &S3{
		client:  client,
		presign: s3.NewPresignClient(client),
		bucket:  opts.Bucket,
	}, nil
}

// Put uploads body under key.
func (s *S3) Put(ctx context.Context, key string, body []byte, contentType string) error {
	_, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		Body:          bytes.NewReader(body),
		ContentType:   aws.String(contentType),
		ContentLength: aws.Int64(int64(len(body))),
	})
	if err != nil {
		return fmt.Errorf("uploading object: %w", err)
	}
	return nil
}

// Get opens the object for reading; the caller closes the reader.
func (s *S3) Get(ctx context.Context, key string) (io.ReadCloser, error) {
	out, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if isNotFound(err) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("downloading object: %w", err)
	}
	return out.Body, nil
}

// Delete removes the object. S3 treats deleting a missing key as success, so
// this is idempotent without extra handling.
func (s *S3) Delete(ctx context.Context, key string) error {
	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil && !isNotFound(err) {
		return fmt.Errorf("deleting object: %w", err)
	}
	return nil
}

// SignedGetURL returns a pre-signed GET valid for ttl, so a reviewer's browser
// fetches the image straight from object storage without the bytes passing
// through this server — and without the object ever being public.
func (s *S3) SignedGetURL(ctx context.Context, key string, ttl time.Duration) (string, error) {
	req, err := s.presign.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(ttl))
	if err != nil {
		return "", fmt.Errorf("signing object URL: %w", err)
	}
	return req.URL, nil
}

// isNotFound reports whether err is S3's "no such key". The typed error only
// comes back from GetObject; HeadObject-style calls and some S3-compatible
// services return a bare API error instead, so both are checked.
func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	if _, ok := errors.AsType[*types.NoSuchKey](err); ok {
		return true
	}
	if apiErr, ok := errors.AsType[smithy.APIError](err); ok {
		switch apiErr.ErrorCode() {
		case "NoSuchKey", "NotFound":
			return true
		}
	}
	return false
}

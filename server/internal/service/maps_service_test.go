package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

type fakeMapsSource struct {
	token domain.MapsToken
	err   error
}

func (f fakeMapsSource) Token(context.Context) (domain.MapsToken, error) {
	return f.token, f.err
}

func TestMapsService_NotConfigured(t *testing.T) {
	_, err := NewMapsService(nil).Token(context.Background())
	if !errors.Is(err, ErrMapsNotConfigured) {
		t.Fatalf("err = %v, want ErrMapsNotConfigured", err)
	}
}

func TestMapsService_ReturnsSourceToken(t *testing.T) {
	want := domain.MapsToken{AccessToken: "t", ExpiresAt: time.Now().Add(time.Hour)}
	got, err := NewMapsService(fakeMapsSource{token: want}).Token(context.Background())
	if err != nil || got != want {
		t.Fatalf("got %+v, %v; want %+v", got, err, want)
	}
}

func TestMapsService_PropagatesSourceError(t *testing.T) {
	boom := errors.New("provider down")
	_, err := NewMapsService(fakeMapsSource{err: boom}).Token(context.Background())
	if !errors.Is(err, boom) {
		t.Fatalf("err = %v, want %v", err, boom)
	}
}

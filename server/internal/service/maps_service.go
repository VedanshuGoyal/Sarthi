package service

import (
	"context"
	"errors"

	"github.com/sarthi/server/internal/domain"
)

// ErrMapsNotConfigured is returned when the server has no Ola Maps credentials.
var ErrMapsNotConfigured = errors.New("maps: no Ola Maps credentials configured")

// MapsTokenSource mints Ola Maps bearer tokens. Implemented by olamaps.Client;
// defined consumer-side so the service stays testable with a fake.
type MapsTokenSource interface {
	Token(ctx context.Context) (domain.MapsToken, error)
}

// MapsService hands the apps short-lived Ola Maps tokens, so the OAuth client
// secret never leaves the server.
type MapsService struct {
	src MapsTokenSource
}

// NewMapsService wires the service to its token source. A nil source means
// maps are not configured: Token then returns [ErrMapsNotConfigured].
func NewMapsService(src MapsTokenSource) *MapsService {
	return &MapsService{src: src}
}

// Token returns a valid Ola Maps bearer token.
func (s *MapsService) Token(ctx context.Context) (domain.MapsToken, error) {
	if s.src == nil {
		return domain.MapsToken{}, ErrMapsNotConfigured
	}
	return s.src.Token(ctx)
}

package service

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// ErrInvalidPayout is returned when a payout names no driver or no bank
// reference.
var ErrInvalidPayout = errors.New("a payout needs the driverId and the bank's transfer reference")

// PayoutStore lists what drivers are owed and records transfers
// (repository.PaymentRepository).
type PayoutStore interface {
	DuePayouts(ctx context.Context, asOf time.Time) ([]domain.PayoutDue, error)
	RecordPayout(ctx context.Context, driverID, reference string, asOf, at time.Time) (domain.DriverPayout, error)
}

// SealOpener decrypts a sealed bank account number (secret.Cipher).
type SealOpener interface {
	Open(sealed []byte) ([]byte, error)
}

// PayoutService is MOJUD's side of paying drivers: what each is owed — their
// share of every ride customers have paid for, less commission — and a
// record of each bank transfer once it's made. The transfer itself is done
// at the bank; this only keeps the books.
type PayoutService struct {
	store  PayoutStore
	cipher SealOpener
	now    func() time.Time
}

// NewPayoutService wires the service.
func NewPayoutService(store PayoutStore, cipher SealOpener) *PayoutService {
	return &PayoutService{store: store, cipher: cipher, now: time.Now}
}

// Due lists what each driver is owed for rides paid by asOf (zero means
// now), with their bank account number decrypted for the transfer. A
// driver whose number can't be opened is listed without it.
func (s *PayoutService) Due(ctx context.Context, asOf time.Time) ([]domain.PayoutDue, time.Time, error) {
	if asOf.IsZero() {
		asOf = s.now()
	}
	due, err := s.store.DuePayouts(ctx, asOf)
	if err != nil {
		return nil, asOf, err
	}
	for i := range due {
		sealed := due[i].AccountNumberEncrypted
		due[i].AccountNumberEncrypted = nil
		if len(sealed) == 0 {
			continue
		}
		number, err := s.cipher.Open(sealed)
		if err != nil {
			slog.WarnContext(ctx, "payouts: could not open a bank account number",
				"driverId", due[i].DriverID, "error", err)
			continue
		}
		due[i].AccountNumber = string(number)
	}
	return due, asOf, nil
}

// Record notes a transfer made to driverID — reference is the bank's UTR —
// covering every ride of theirs paid by asOf (zero means now) and not yet
// paid out. Pass the asOf the Due list was read at, so a ride paid after it
// isn't swept into a transfer that didn't include it.
func (s *PayoutService) Record(ctx context.Context, driverID, reference string, asOf time.Time) (domain.DriverPayout, error) {
	driverID, reference = strings.TrimSpace(driverID), strings.TrimSpace(reference)
	if driverID == "" || reference == "" {
		return domain.DriverPayout{}, ErrInvalidPayout
	}
	now := s.now()
	if asOf.IsZero() || asOf.After(now) {
		asOf = now
	}
	p, err := s.store.RecordPayout(ctx, driverID, reference, asOf, now)
	if err != nil {
		return domain.DriverPayout{}, err
	}
	slog.InfoContext(ctx, "payout recorded",
		"payoutId", p.ID, "driverId", driverID, "amountPaise", p.AmountPaise, "rides", p.Rides)
	return p, nil
}

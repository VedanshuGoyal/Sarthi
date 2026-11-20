package service

import (
	"context"
	"log/slog"

	"github.com/sarthi/server/internal/domain"
)

// withPaymentLines completes the receipt of each booking in cbs that was
// paid in the app with every booking that payment paid — one checkout
// collects all the customer owes (see [PaymentService.Checkout]) — each
// labelled for the customer. Only userID's own bookings are listed.
//
// A failed read leaves the receipts as they were: the lines explain a
// payment, the customer doesn't need them to see it was made.
func (s *BookingService) withPaymentLines(ctx context.Context, userID string, cbs []domain.CustomerBooking) []domain.CustomerBooking {
	var orders []string
	seen := map[string]bool{}
	for _, cb := range cbs {
		if p := cb.Payment; p != nil && p.MerchantOrderID != "" && !seen[p.MerchantOrderID] {
			seen[p.MerchantOrderID] = true
			orders = append(orders, p.MerchantOrderID)
		}
	}
	if len(orders) == 0 {
		return cbs
	}
	lines, err := s.store.PaymentLines(ctx, userID, orders)
	if err != nil {
		slog.WarnContext(ctx, "bookings: receipt lines unavailable", "userId", userID, "error", err)
		return cbs
	}
	for i, cb := range cbs {
		p := cb.Payment
		if p == nil || len(lines[p.MerchantOrderID]) == 0 {
			continue
		}
		receipt := *p
		receipt.Lines = labelledLines(lines[p.MerchantOrderID])
		cbs[i].Payment = &receipt
	}
	return cbs
}

// labelledLines is a copy of lines with each one's Label set.
func labelledLines(lines []domain.PaymentLine) []domain.PaymentLine {
	out := make([]domain.PaymentLine, len(lines))
	for i, l := range lines {
		l.Label = paymentLineLabel(l)
		out[i] = l
	}
	return out
}

// paymentLineLabel names a receipt line in a few words: what it paid for and
// the day that booking was for, in IST — "Round trip · Mon 17 Nov",
// "Cancellation fee · Sat 15 Nov".
func paymentLineLabel(l domain.PaymentLine) string {
	what := tripLabel(l.TripType, tripPlan{})
	if l.Kind == domain.PaymentLineCancellationFee {
		what = "Cancellation fee"
	}
	if l.ScheduledAt == nil {
		return what
	}
	return what + " · " + l.ScheduledAt.In(ist).Format("Mon 2 Jan")
}

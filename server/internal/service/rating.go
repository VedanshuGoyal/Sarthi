package service

import (
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/sarthi/server/internal/domain"
)

// ErrInvalidRating is returned for stars outside 1–5 or an over-long note.
var ErrInvalidRating = errors.New("rate from 1 to 5 stars, with a note of at most 500 characters")

// maxRatingNote caps the optional note left with a rating, in characters.
const maxRatingNote = 500

// newRating validates a rating one side of a completed ride gives the other.
func newRating(stars int, note string) (domain.RideRating, error) {
	note = strings.TrimSpace(note)
	if stars < 1 || stars > 5 || utf8.RuneCountInString(note) > maxRatingNote {
		return domain.RideRating{}, ErrInvalidRating
	}
	return domain.RideRating{Stars: stars, Note: note}, nil
}

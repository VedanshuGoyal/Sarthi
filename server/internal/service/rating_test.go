package service

import "testing"

func TestNewRating(t *testing.T) {
	if r, err := newRating(5, "  Great  "); err != nil || r.Stars != 5 || r.Note != "Great" {
		t.Errorf("newRating(5) = %+v, %v", r, err)
	}
	for _, stars := range []int{0, 6} {
		if _, err := newRating(stars, ""); err != ErrInvalidRating {
			t.Errorf("newRating(%d) err = %v, want ErrInvalidRating", stars, err)
		}
	}
}

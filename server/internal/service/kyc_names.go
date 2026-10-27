package service

import (
	"strings"
	"unicode"
)

// honorifics are dropped before names are compared; banks often prefix them.
var honorifics = map[string]bool{
	"MR": true, "MRS": true, "MS": true, "MISS": true, "SHRI": true, "SRI": true,
	"SMT": true, "KUMARI": true, "KM": true, "DR": true, "MASTER": true,
}

// namesMatch reports whether two records plausibly name the same person:
// "ASHA KUMARI SINGH", "Asha K Singh" and "SINGH ASHA" all match, while
// "ASHA SINGH" and "RAVI SINGH" don't. Case, punctuation, word order and
// honorifics are ignored; every word of the shorter name must appear in the
// longer one, either whole or as an initial, and at least one whole word must.
func namesMatch(a, b string) bool {
	ta, tb := nameTokens(a), nameTokens(b)
	if len(ta) == 0 || len(tb) == 0 {
		return false
	}
	if strings.Join(ta, "") == strings.Join(tb, "") {
		return true
	}
	short, long := ta, tb
	if len(short) > len(long) {
		short, long = long, short
	}

	used := make([]bool, len(long))
	whole := false
	for _, s := range short {
		matched := false
		// Whole words first, so "A" can't use up the word an exact match needs.
		for i, l := range long {
			if !used[i] && s == l && len(s) > 1 {
				used[i], matched, whole = true, true, true
				break
			}
		}
		if !matched {
			for i, l := range long {
				if !used[i] && (len(s) == 1 || len(l) == 1) && s[0] == l[0] {
					used[i], matched = true, true
					break
				}
			}
		}
		if !matched {
			return false
		}
	}
	return whole
}

// nameTokens upper-cases a name into its words, without honorifics.
func nameTokens(name string) []string {
	words := strings.FieldsFunc(strings.ToUpper(name), func(r rune) bool {
		return !unicode.IsLetter(r)
	})
	out := words[:0]
	for _, w := range words {
		if !honorifics[w] {
			out = append(out, w)
		}
	}
	return out
}

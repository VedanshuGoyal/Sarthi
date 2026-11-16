package service

import "sync"

// keyedLocks hands out one mutex per key — a driver, or a driver and a kind
// of check — so work for one key runs one at a time while different keys
// run in parallel. A key's mutex exists only while someone holds or waits
// for it. The zero value is ready to use.
//
// It serialises within this process, which is the whole deployment: like
// memstore, it assumes a single server instance.
type keyedLocks struct {
	mu    sync.Mutex
	locks map[string]*keyedLock
}

type keyedLock struct {
	mu   sync.Mutex
	refs int // holders and waiters; guarded by keyedLocks.mu
}

// lock blocks until key is free, takes it, and returns the func that frees
// it.
func (k *keyedLocks) lock(key string) (unlock func()) {
	k.mu.Lock()
	if k.locks == nil {
		k.locks = make(map[string]*keyedLock)
	}
	l := k.locks[key]
	if l == nil {
		l = &keyedLock{}
		k.locks[key] = l
	}
	l.refs++
	k.mu.Unlock()

	l.mu.Lock()
	return func() {
		l.mu.Unlock()
		k.mu.Lock()
		l.refs--
		if l.refs == 0 {
			delete(k.locks, key)
		}
		k.mu.Unlock()
	}
}

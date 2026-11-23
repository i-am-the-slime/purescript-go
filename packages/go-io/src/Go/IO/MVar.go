package ffi

import "sync"

// MVar is a box that is empty or holds one value.
type MVar[A any] = *mvar[A]

type mvar[A any] struct {
	lock    sync.Mutex
	changed sync.Cond
	full    bool
	value   A
}

func NewEmptyMVarImpl[A any]() *mvar[A] {
	box := &mvar[A]{}
	box.changed.L = &box.lock
	return box
}

func TakeMVarImpl[A any](box *mvar[A]) A {
	box.lock.Lock()
	defer box.lock.Unlock()
	for !box.full {
		box.changed.Wait()
	}
	return box.take()
}

func PutMVarImpl[A any](box *mvar[A], value A) {
	box.lock.Lock()
	defer box.lock.Unlock()
	for box.full {
		box.changed.Wait()
	}
	box.put(value)
}

func ReadMVarImpl[A any](box *mvar[A]) A {
	box.lock.Lock()
	defer box.lock.Unlock()
	for !box.full {
		box.changed.Wait()
	}
	return box.value
}

func TryTakeMVarImpl[A, R any](empty R, found func(A) R, box *mvar[A]) R {
	box.lock.Lock()
	defer box.lock.Unlock()
	if !box.full {
		return empty
	}
	return found(box.take())
}

func TryPutMVarImpl[A any](box *mvar[A], value A) bool {
	box.lock.Lock()
	defer box.lock.Unlock()
	if box.full {
		return false
	}
	box.put(value)
	return true
}

func TryReadMVarImpl[A, R any](empty R, found func(A) R, box *mvar[A]) R {
	box.lock.Lock()
	defer box.lock.Unlock()
	if !box.full {
		return empty
	}
	return found(box.value)
}

func IsEmptyMVarImpl[A any](box *mvar[A]) bool {
	box.lock.Lock()
	defer box.lock.Unlock()
	return !box.full
}

func (box *mvar[A]) take() A {
	value := box.value
	var zero A
	box.value, box.full = zero, false
	box.changed.Broadcast()
	return value
}

func (box *mvar[A]) put(value A) {
	box.value, box.full = value, true
	box.changed.Broadcast()
}

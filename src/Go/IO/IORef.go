package ffi

import "sync/atomic"

// IORef is a cell whose value every goroutine sees whole: reads and writes swap a pointer.
type IORef[A any] = *ioref[A]

type ioref[A any] struct {
	value atomic.Pointer[A]
}

func NewIORefImpl[A any](value A) *ioref[A] {
	ref := &ioref[A]{}
	ref.value.Store(&value)
	return ref
}

func ReadIORefImpl[A any](ref *ioref[A]) A { return *ref.value.Load() }

func WriteIORefImpl[A any](ref *ioref[A], value A) { ref.value.Store(&value) }

// AtomicModifyIORefImpl applies f to the current value and stores the first of its results, unless
// another goroutine stored one first, in which case it tries again with that one.
func AtomicModifyIORefImpl[A, B, T any](first func(T) A, second func(T) B, f func(A) T, ref *ioref[A]) B {
	for {
		old := ref.value.Load()
		result := f(*old)
		updated := first(result)
		if ref.value.CompareAndSwap(old, &updated) {
			return second(result)
		}
	}
}

package ffi

import "sync"

// Chan is an unbounded first-in, first-out queue.
type Chan[A any] = *channel[A]

type channel[A any] struct {
	lock    sync.Mutex
	written sync.Cond
	queue   []A
}

func NewChanImpl[A any]() *channel[A] {
	queue := &channel[A]{}
	queue.written.L = &queue.lock
	return queue
}

func WriteChanImpl[A any](queue *channel[A], value A) {
	queue.lock.Lock()
	queue.queue = append(queue.queue, value)
	queue.lock.Unlock()
	queue.written.Signal()
}

func ReadChanImpl[A any](queue *channel[A]) A {
	queue.lock.Lock()
	defer queue.lock.Unlock()
	for len(queue.queue) == 0 {
		queue.written.Wait()
	}
	value := queue.queue[0]
	var zero A
	queue.queue[0] = zero
	queue.queue = queue.queue[1:]
	return value
}

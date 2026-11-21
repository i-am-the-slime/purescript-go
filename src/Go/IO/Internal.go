package ffi

import (
	"fmt"

	"github.com/i-am-the-slime/iris-go/aff"
	"github.com/i-am-the-slime/iris-go/exception"
)

// RunEffectImpl runs the effect on the event loop and waits for it; an exception it throws is
// rethrown on this goroutine.
func RunEffectImpl[A any](effect func() A) A {
	var value A
	var failure exception.Error
	var failed bool
	aff.Exclusive(func() { value, failure, failed = attempt(effect) })
	if failed {
		panic(failure)
	}
	return value
}

// CatchImpl runs the action and hands whatever it panics with to the handler as an Error.
func CatchImpl[A any](handler func(exception.Error) A, action func() A) A {
	result, failure, failed := attempt(action)
	if failed {
		return handler(failure)
	}
	return result
}

func attempt[A any](action func() A) (result A, failure exception.Error, failed bool) {
	defer func() {
		if recovered := recover(); recovered != nil {
			failure, failed = asError(recovered), true
		}
	}()
	return action(), exception.Error{}, false
}

func asError(recovered any) exception.Error {
	if failure, ok := exception.AsError(recovered); ok {
		return failure
	}
	if err, ok := recovered.(error); ok {
		return exception.NewError(err.Error())
	}
	return exception.NewError(fmt.Sprint(recovered))
}

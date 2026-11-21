package ffi

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync/atomic"
	"time"

	"github.com/i-am-the-slime/iris-go/aff"
	"github.com/i-am-the-slime/iris-go/exception"
)

var threads atomic.Int32

// ForkIOImpl runs the action on a new goroutine. An exception it doesn't catch goes to standard
// error, as GHC reports one, and ends only that goroutine.
func ForkIOImpl(action func()) int32 {
	id := threads.Add(1)
	go func() {
		_, failure, failed := attempt(func() struct{} {
			action()
			return struct{}{}
		})
		if failed {
			fmt.Fprintf(os.Stderr, "%s: thread %d: %s\n", filepath.Base(os.Args[0]), id, exception.Stack(failure))
		}
	}()
	return id
}

func ThreadDelayImpl(milliseconds float64) {
	time.Sleep(time.Duration(milliseconds * float64(time.Millisecond)))
}

func YieldImpl() { runtime.Gosched() }

func NumCapabilitiesImpl() int32 { return int32(runtime.GOMAXPROCS(0)) }

// ToAffImpl runs the action on a goroutine of its own and hands its outcome to succeeded or failed
// on the event loop. Until then it keeps the program running. An exception either throws ends the
// program, as an uncaught one does in JavaScript.
func ToAffImpl[A any](action func() A, succeeded func(A), failed func(exception.Error)) {
	retire := aff.Hold()
	go func() {
		defer exception.ReportUncaught()
		value, failure, didFail := attempt(action)
		aff.Exclusive(func() {
			if didFail {
				failed(failure)
			} else {
				succeeded(value)
			}
		})
		retire()
	}()
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

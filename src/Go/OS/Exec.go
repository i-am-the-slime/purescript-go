package ffi

import (
	"bytes"
	"errors"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"

	"github.com/i-am-the-slime/iris-go/aff"
)

type Output struct {
	Stdout   string
	Stderr   string
	ExitCode int32
	Signal   string
}

type Prepared struct {
	Program      string
	Args         []string
	Dir          string
	Inherit      bool
	EnvNames     []string
	EnvValues    []string
	StdinText    string
	StdinParent  bool
	StdoutParent bool
	StderrParent bool
}

// Process is a started program. Its output is collected on a goroutine of its own, so that waiting
// for it in Aff does not hold the event loop.
type Process = *running

type running struct {
	command *exec.Cmd
	stdout  bytes.Buffer
	stderr  bytes.Buffer
	done    chan struct{}
	code    int32
	err     error
}

func RunImpl[R any](
	notFound func(string) R,
	failed func(error) R,
	finished func(Output) R,
	prepared Prepared,
) R {
	process, err := launch(prepared)
	switch {
	case errors.Is(err, exec.ErrNotFound):
		return notFound(prepared.Program)
	case err != nil:
		return failed(err)
	}
	<-process.done
	if process.err != nil {
		return failed(process.err)
	}
	return finished(process.output())
}

func StartImpl[R any](
	notFound func(string) R,
	failed func(error) R,
	started func(Process) R,
	prepared Prepared,
) R {
	process, err := launch(prepared)
	switch {
	case errors.Is(err, exec.ErrNotFound):
		return notFound(prepared.Program)
	case err != nil:
		return failed(err)
	}
	return started(process)
}

// WaitImpl waits for the program on a goroutine of its own and hands the result to finished on the
// event loop, so other fibers keep running meanwhile.
func WaitImpl[R any](failed func(error) R, ended func(Output) R, process Process, finished func(R)) {
	retire := aff.Hold()
	go func() {
		<-process.done
		aff.Exclusive(func() {
			if process.err != nil {
				finished(failed(process.err))
			} else {
				finished(ended(process.output()))
			}
		})
		retire()
	}()
}

func KillImpl[R any](failed func(error) R, done R, process Process) R {
	select {
	case <-process.done:
		return done
	default:
	}
	if err := process.command.Process.Signal(syscall.SIGKILL); err != nil && !errors.Is(err, os.ErrProcessDone) {
		return failed(err)
	}
	return done
}

// launch starts the program and collects its exit on a goroutine, which closes done.
func launch(prepared Prepared) (*running, error) {
	process := &running{command: start(prepared), done: make(chan struct{})}
	command := process.command
	if prepared.StdinParent {
		command.Stdin = os.Stdin
	} else {
		command.Stdin = strings.NewReader(prepared.StdinText)
	}
	command.Stdout = sink(prepared.StdoutParent, os.Stdout, &process.stdout)
	command.Stderr = sink(prepared.StderrParent, os.Stderr, &process.stderr)
	if err := command.Start(); err != nil {
		return nil, err
	}
	go func() {
		process.code, process.err = exitCode(command.Wait())
		close(process.done)
	}()
	return process, nil
}

func sink(parent bool, own *os.File, captured *bytes.Buffer) io.Writer {
	if parent {
		return own
	}
	return captured
}

func (process *running) output() Output {
	return Output{
		Stdout:   process.stdout.String(),
		Stderr:   process.stderr.String(),
		ExitCode: process.code,
		Signal:   signalName(process.command.ProcessState),
	}
}

func RunInteractiveImpl[R any](
	notFound func(string) R,
	failed func(error) R,
	finished func(int32) R,
	prepared Prepared,
) R {
	command := start(prepared)
	command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
	code, err := exitCode(command.Run())
	switch {
	case errors.Is(err, exec.ErrNotFound):
		return notFound(prepared.Program)
	case err != nil:
		return failed(err)
	}
	return finished(code)
}

func start(prepared Prepared) *exec.Cmd {
	command := exec.Command(prepared.Program, prepared.Args...)
	command.Dir = prepared.Dir
	environment := []string{}
	if prepared.Inherit {
		environment = os.Environ()
	}
	for index, name := range prepared.EnvNames {
		environment = append(environment, name+"="+prepared.EnvValues[index])
	}
	command.Env = environment
	return command
}

// exitCode is the exit code of a program that ran to its end, and the error of one that did not.
// A Unix exit code fits a byte. A Windows one above 2^31-1, such as an NTSTATUS crash code, reads
// as the negative Int with the same 32 bits.
func exitCode(err error) (int32, error) {
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return int32(exitError.ExitCode()), nil
	}
	return 0, err
}

// signalName names the signal that ended the program, or is empty if it exited by itself.
func signalName(state *os.ProcessState) string {
	if state == nil {
		return ""
	}
	status, ok := state.Sys().(syscall.WaitStatus)
	if !ok || !status.Signaled() {
		return ""
	}
	if name, known := signalNames[status.Signal()]; known {
		return name
	}
	return "SIG" + strconv.Itoa(int(status.Signal()))
}

var signalNames = map[syscall.Signal]string{
	syscall.SIGHUP:  "SIGHUP",
	syscall.SIGINT:  "SIGINT",
	syscall.SIGQUIT: "SIGQUIT",
	syscall.SIGABRT: "SIGABRT",
	syscall.SIGKILL: "SIGKILL",
	syscall.SIGSEGV: "SIGSEGV",
	syscall.SIGPIPE: "SIGPIPE",
	syscall.SIGALRM: "SIGALRM",
	syscall.SIGTERM: "SIGTERM",
	syscall.SIGUSR1: "SIGUSR1",
	syscall.SIGUSR2: "SIGUSR2",
}

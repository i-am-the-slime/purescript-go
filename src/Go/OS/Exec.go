package ffi

import (
	"bytes"
	"errors"
	"os/exec"
	"strings"
)

type Output struct {
	Stdout   string
	Stderr   string
	ExitCode int32
}

func RunImpl[R any](
	notFound func(string) R,
	failed func(error) R,
	finished func(Output) R,
	program string,
	args []string,
	dir string,
	stdin string,
) R {
	command := exec.Command(program, args...)
	command.Dir = dir
	command.Stdin = strings.NewReader(stdin)
	var stdout, stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	err := command.Run()
	var exitError *exec.ExitError
	switch {
	case errors.Is(err, exec.ErrNotFound):
		return notFound(program)
	case errors.As(err, &exitError):
		// A Unix exit code fits a byte. A Windows one above 2^31-1, such as an NTSTATUS crash
		// code, reads as the negative Int with the same 32 bits.
		return finished(Output{Stdout: stdout.String(), Stderr: stderr.String(), ExitCode: int32(exitError.ExitCode())})
	case err != nil:
		return failed(err)
	}
	return finished(Output{Stdout: stdout.String(), Stderr: stderr.String()})
}

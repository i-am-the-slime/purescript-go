package ffi

import (
	"bytes"
	"errors"
	"os/exec"
	"strings"
)

func RunImpl[R any](
	notFound func(string) R,
	failed func(error) R,
	finished func(string) func(string) func(int) R,
	program string,
	args []string,
	dir string,
	stdin string,
) func() R {
	return func() R {
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
			return finished(stdout.String())(stderr.String())(exitError.ExitCode())
		case err != nil:
			return failed(err)
		}
		return finished(stdout.String())(stderr.String())(0)
	}
}

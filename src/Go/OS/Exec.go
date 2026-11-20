package ffi

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"strings"
)

type Output struct {
	Stdout   string
	Stderr   string
	ExitCode int32
}

type Prepared struct {
	Program   string
	Args      []string
	Dir       string
	Inherit   bool
	EnvNames  []string
	EnvValues []string
}

func RunImpl[R any](
	notFound func(string) R,
	failed func(error) R,
	finished func(Output) R,
	prepared Prepared,
	stdin string,
) R {
	command := start(prepared)
	command.Stdin = strings.NewReader(stdin)
	var stdout, stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	code, err := exitCode(command.Run())
	switch {
	case errors.Is(err, exec.ErrNotFound):
		return notFound(prepared.Program)
	case err != nil:
		return failed(err)
	}
	return finished(Output{Stdout: stdout.String(), Stderr: stderr.String(), ExitCode: code})
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

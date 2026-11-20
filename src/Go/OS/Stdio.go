package ffi

import (
	"bufio"
	"errors"
	"io"
	"os"
	"strings"
)

func ReadAllImpl[R any](failed func(error) R, read func(string) R) R {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		return failed(err)
	}
	return read(string(data))
}

func ReadAllBytesImpl[R any](failed func(error) R, read func([]byte) R) R {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		return failed(err)
	}
	return read(data)
}

// ForEachLineImpl reads with ReadString rather than a bufio.Scanner, whose tokens are limited to
// 64 KiB, so that a line can be any length.
func ForEachLineImpl[R any](failed func(error) R, done R, handle func(string)) R {
	reader := bufio.NewReader(os.Stdin)
	for {
		line, err := reader.ReadString('\n')
		if len(line) > 0 {
			handle(strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r"))
		}
		if errors.Is(err, io.EOF) {
			return done
		}
		if err != nil {
			return failed(err)
		}
	}
}

func WriteStdoutImpl[R any](failed func(error) R, done R, text string) R {
	return written(failed, done, os.Stdout, []byte(text))
}

func WriteStdoutBytesImpl[R any](failed func(error) R, done R, data []byte) R {
	return written(failed, done, os.Stdout, data)
}

func WriteStderrImpl[R any](failed func(error) R, done R, text string) R {
	return written(failed, done, os.Stderr, []byte(text))
}

func WriteStderrBytesImpl[R any](failed func(error) R, done R, data []byte) R {
	return written(failed, done, os.Stderr, data)
}

func StdinIsTerminalImpl() bool { return isTerminal(os.Stdin) }

func StdoutIsTerminalImpl() bool { return isTerminal(os.Stdout) }

func written[R any](failed func(error) R, done R, file *os.File, data []byte) R {
	if _, err := file.Write(data); err != nil {
		return failed(err)
	}
	return done
}

// isTerminal tells a terminal by its file being a character device, as the standard library
// alone can.
func isTerminal(file *os.File) bool {
	info, err := file.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

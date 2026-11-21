package ffi

import (
	"bufio"
	"errors"
	"io"
	"os"
	"strings"
	"unicode/utf8"

	"github.com/i-am-the-slime/iris-go/eventloop"
)

// stdin is shared by forEachLine and readChunk, so that neither loses what the other buffered.
var stdin = bufio.NewReader(os.Stdin)

// pending holds the start of a character that a read split, until the next read completes it.
var pending []byte

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
	for {
		line, err := stdin.ReadString('\n')
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

// ReadChunkImpl reads on a goroutine of its own and resumes the fiber with the text.
func ReadChunkImpl[R any](failed func(error) R, ended R, read func(string) R, finished func(R)) {
	retire := eventloop.Hold()
	go func() {
		text, err := nextChunk()
		switch {
		case text != "":
			finished(read(text))
		case errors.Is(err, io.EOF):
			finished(ended)
		default:
			finished(failed(err))
		}
		retire()
	}()
}

// nextChunk returns the next complete characters of standard input, keeping a split one for later.
func nextChunk() (string, error) {
	buffer := make([]byte, 4096)
	for {
		count, err := stdin.Read(buffer)
		data := append(pending, buffer[:count]...)
		complete := len(data)
		if err == nil {
			complete = completeLength(data)
		}
		pending = append([]byte(nil), data[complete:]...)
		if complete > 0 || err != nil {
			return string(data[:complete]), err
		}
	}
}

// completeLength is the length of the longest prefix of data that does not end inside a character.
func completeLength(data []byte) int {
	for back := 1; back <= utf8.UTFMax && back <= len(data); back++ {
		start := len(data) - back
		if utf8.RuneStart(data[start]) {
			if utf8.FullRune(data[start:]) {
				return len(data)
			}
			return start
		}
	}
	return len(data)
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

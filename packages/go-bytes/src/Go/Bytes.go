package ffi

import (
	"bytes"
	"math"
	"slices"
	"strings"
	"unicode/utf8"
)

type Bytes = []byte

func EqImpl(left []byte, right []byte) bool { return bytes.Equal(left, right) }

// AppendImpl copies both, so that the result never shares memory another Bytes can see.
func AppendImpl(left []byte, right []byte) []byte { return slices.Concat(left, right) }

var EmptyImpl = []byte{}

func SizeImpl(data []byte) float64 { return float64(len(data)) }

func SliceImpl(start float64, end float64, data []byte) []byte {
	from, to := clamp(start, len(data)), clamp(end, len(data))
	if to < from {
		return []byte{}
	}
	return slices.Clone(data[from:to])
}

// FromStringImpl encodes a PureScript string, which Iris keeps as WTF-8, as UTF-8: the
// three-byte encoding of a lone surrogate (ED A0-BF 80-BF) becomes U+FFFD.
func FromStringImpl(text string) []byte {
	if utf8.ValidString(text) {
		return []byte(text)
	}
	var encoded bytes.Buffer
	for index := 0; index < len(text); {
		if index+2 < len(text) && text[index] == 0xED && text[index+1] >= 0xA0 {
			encoded.WriteRune(utf8.RuneError)
			index += 3
			continue
		}
		encoded.WriteByte(text[index])
		index++
	}
	return encoded.Bytes()
}

// ToStringImpl decodes UTF-8, replacing each byte that is not part of a valid encoding with U+FFFD.
func ToStringImpl(data []byte) string {
	if utf8.Valid(data) {
		return string(data)
	}
	var decoded strings.Builder
	for len(data) > 0 {
		character, width := utf8.DecodeRune(data)
		decoded.WriteRune(character)
		data = data[width:]
	}
	return decoded.String()
}

func FromArrayImpl(numbers []int32) []byte {
	data := make([]byte, len(numbers))
	for index, number := range numbers {
		data[index] = byte(number)
	}
	return data
}

func ToArrayImpl(data []byte) []int32 {
	numbers := make([]int32, len(data))
	for index, value := range data {
		numbers[index] = int32(value)
	}
	return numbers
}

func clamp(offset float64, length int) int {
	if math.IsNaN(offset) || offset <= 0 {
		return 0
	}
	if offset >= float64(length) {
		return length
	}
	return int(offset)
}

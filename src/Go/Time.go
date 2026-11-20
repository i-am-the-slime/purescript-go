package ffi

import "time"

func FormatImpl(layout string, milliseconds float64) string {
	return time.UnixMilli(int64(milliseconds)).UTC().Format(layout)
}

func ParseImpl[R any](failed func(error) R, parsed func(float64) R, layout string, text string) R {
	moment, err := time.Parse(layout, text)
	if err != nil {
		return failed(err)
	}
	return parsed(float64(moment.UnixMilli()))
}

func SleepImpl(milliseconds float64) {
	time.Sleep(time.Duration(milliseconds * float64(time.Millisecond)))
}

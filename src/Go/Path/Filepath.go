package ffi

import "path/filepath"

func JoinImpl(paths []string) string { return filepath.Join(paths...) }

func BaseImpl(path string) string { return filepath.Base(path) }

func DirImpl(path string) string { return filepath.Dir(path) }

func ExtImpl(path string) string { return filepath.Ext(path) }

func CleanImpl(path string) string { return filepath.Clean(path) }

func IsAbsImpl(path string) bool { return filepath.IsAbs(path) }

func RelImpl[R any](failed func(error) R, found func(string) R, from string, target string) R {
	path, err := filepath.Rel(from, target)
	if err != nil {
		return failed(err)
	}
	return found(path)
}

func AbsImpl[R any](failed func(error) R, found func(string) R, path string) func() R {
	return func() R {
		absolute, err := filepath.Abs(path)
		if err != nil {
			return failed(err)
		}
		return found(absolute)
	}
}

func GlobImpl[R any](failed func(error) R, found func([]string) R, pattern string) func() R {
	return func() R {
		matches, err := filepath.Glob(pattern)
		if err != nil {
			return failed(err)
		}
		if matches == nil {
			matches = []string{}
		}
		return found(matches)
	}
}

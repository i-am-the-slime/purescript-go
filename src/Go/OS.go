package ffi

import (
	"errors"
	"io/fs"
	"os"
)

type FileInfo = fs.FileInfo

type DirEntry = fs.DirEntry

func ClassifyImpl[R any](notExist, exist, permission func(string) R, other func(error) R, err error) R {
	path := ""
	var pathError *fs.PathError
	if errors.As(err, &pathError) {
		path = pathError.Path
	}
	var linkError *os.LinkError
	if errors.As(err, &linkError) {
		path = linkError.Old
	}
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return notExist(path)
	case errors.Is(err, fs.ErrExist):
		return exist(path)
	case errors.Is(err, fs.ErrPermission):
		return permission(path)
	default:
		return other(err)
	}
}

func ReadFileImpl[R any](failed func(error) R, read func(string) R, path string) R {
	data, err := os.ReadFile(path)
	if err != nil {
		return failed(err)
	}
	return read(string(data))
}

func ReadFileBytesImpl[R any](failed func(error) R, read func([]byte) R, path string) R {
	data, err := os.ReadFile(path)
	if err != nil {
		return failed(err)
	}
	return read(data)
}

func WriteFileBytesImpl[R any](failed func(error) R, done R, path string, mode int32, contents []byte) R {
	return result(failed, done, os.WriteFile(path, contents, fs.FileMode(mode)))
}

func AppendFileBytesImpl[R any](failed func(error) R, done R, path string, contents []byte) R {
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return failed(err)
	}
	_, err = file.Write(contents)
	return result(failed, done, errors.Join(err, file.Close()))
}

func ExecutableImpl[R any](failed func(error) R, found func(string) R) R {
	path, err := os.Executable()
	if err != nil {
		return failed(err)
	}
	return found(path)
}

func WriteFileImpl[R any](failed func(error) R, done R, path string, mode int32, contents string) R {
	return result(failed, done, os.WriteFile(path, []byte(contents), fs.FileMode(mode)))
}

func AppendFileImpl[R any](failed func(error) R, done R, path string, contents string) R {
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return failed(err)
	}
	_, err = file.WriteString(contents)
	return result(failed, done, errors.Join(err, file.Close()))
}

func ReadDirImpl[R any](failed func(error) R, read func([]fs.DirEntry) R, path string) R {
	entries, err := os.ReadDir(path)
	if err != nil {
		return failed(err)
	}
	return read(entries)
}

func MkdirImpl[R any](failed func(error) R, done R, path string) R {
	return result(failed, done, os.Mkdir(path, 0o755))
}

func MkdirAllImpl[R any](failed func(error) R, done R, path string) R {
	return result(failed, done, os.MkdirAll(path, 0o755))
}

func RemoveImpl[R any](failed func(error) R, done R, path string) R {
	return result(failed, done, os.Remove(path))
}

func RemoveAllImpl[R any](failed func(error) R, done R, path string) R {
	return result(failed, done, os.RemoveAll(path))
}

func RenameImpl[R any](failed func(error) R, done R, from string, to string) R {
	return result(failed, done, os.Rename(from, to))
}

func StatImpl[R any](failed func(error) R, found func(fs.FileInfo) R, path string) R {
	info, err := os.Stat(path)
	if err != nil {
		return failed(err)
	}
	return found(info)
}

func MkdirTempImpl[R any](failed func(error) R, created func(string) R, parent string, prefix string) R {
	path, err := os.MkdirTemp(parent, prefix)
	if err != nil {
		return failed(err)
	}
	return created(path)
}

func TempDirImpl() string { return os.TempDir() }

func GetwdImpl[R any](failed func(error) R, found func(string) R) R {
	path, err := os.Getwd()
	if err != nil {
		return failed(err)
	}
	return found(path)
}

func ChdirImpl[R any](failed func(error) R, done R, path string) R {
	return result(failed, done, os.Chdir(path))
}

func ArgsImpl() []string { return append([]string(nil), os.Args[1:]...) }

func LookupEnvImpl[R any](missing R, found func(string) R, name string) R {
	value, ok := os.LookupEnv(name)
	if !ok {
		return missing
	}
	return found(value)
}

func SetenvImpl(name string, value string) { os.Setenv(name, value) }

func UnsetenvImpl(name string) { os.Unsetenv(name) }

func ExitImpl(code int32) { os.Exit(int(code)) }

func NameImpl(info fs.FileInfo) string { return info.Name() }

func SizeImpl(info fs.FileInfo) float64 { return float64(info.Size()) }

func IsDirImpl(info fs.FileInfo) bool { return info.IsDir() }

// Permission bits are nine bits wide, so they fit an Int.
func ModeImpl(info fs.FileInfo) int32 { return int32(info.Mode().Perm()) }

func ModTimeImpl(info fs.FileInfo) float64 { return float64(info.ModTime().UnixMilli()) }

func EntryNameImpl(entry fs.DirEntry) string { return entry.Name() }

func EntryIsDirImpl(entry fs.DirEntry) bool { return entry.IsDir() }

func result[R any](failed func(error) R, done R, err error) R {
	if err != nil {
		return failed(err)
	}
	return done
}

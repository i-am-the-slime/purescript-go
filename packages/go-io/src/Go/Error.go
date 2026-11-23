package ffi

type GoError = error

func MessageImpl(err error) string { return err.Error() }

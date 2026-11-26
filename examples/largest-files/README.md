# largest-files

The ten largest files under a directory, found in parallel, with a 2 second deadline.

Every directory gets its own goroutine, through `mapConcurrently_`. A buffered channel keeps it to 64
open directories at a time, so a deep tree doesn't run out of file handles. Files go over a typed
`Chan SizedFile` to a collector that keeps the top ten. Once the deadline hits, `select2` with
`onDone` lets every walker and the collector stop where they are, and you get the largest so far.

What it uses from `go-io`:

- `mapConcurrently_` to fan out over subdirectories, and `forkIO` with `finally` to close the channel
  once the walk is done
- `withTimeout`, `isCancelled`, `err` and `cancel` from `Go.IO.Context`
- `select2` with `onSend`, `onReceive` and `onDone`, so nobody waits on a channel past the deadline
- `newBufferedChan` twice: once for the files, once as a limit on open directories, with `bracket_`
  to hand the slot back even if reading throws
- `log` from `Go.IO.Console`, which prints whole lines, whichever thread it's on

## Running it

You need [googoo](https://github.com/i-am-the-slime/iris-go-backend) 0.1.18-go.5 or later and Go
1.27. The `spago.yaml` uses the Go package set, so there's nothing else to set up:

```bash
cd examples/largest-files
googoo run --go -- /usr
```

Without an argument it looks at the current directory.

## Sample output

A tree it can walk in time (0.23 seconds, on 18 cores):

```
$ googoo run --go -- /usr
The largest of 31480 files under /usr:
  421.2 MB  /usr/local/bin/vault
   71.8 MB  /usr/share/tokenizer/ja/matrix.bin
   60.9 MB  /usr/libexec/searchpartyd
   55.8 MB  /usr/libexec/searchpartyuseragent
   41.5 MB  /usr/share/tokenizer/ja/sys.dic
   37.7 MB  /usr/sbin/bluetoothd
   36.1 MB  /usr/share/icu/icudt78l.dat
   34.2 MB  /usr/libexec/remindd
   34.0 MB  /usr/libexec/nearbyd
   32.1 MB  /usr/standalone/firmware/DP865/X2232_LGD_BUNDLE_LC8.bin
That's the whole tree.
```

And one it can't:

```
$ googoo run --go -- /Applications
The largest of 215820 files under /Applications:
    1.3 GB  /Applications/Affinity.app/Contents/Frameworks/liblibpersona.dylib
  731.9 MB  /Applications/godotjs/godot.macos.template_release.arm64.dSYM/Contents/Resources/DWARF/godot.macos.template_release.arm64
  625.6 MB  /Applications/Affinity.app/Contents/Frameworks/liblibrastertools.dylib
  537.7 MB  /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/158.0.8127.36/Google Chrome Framework
  537.7 MB  /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/158.0.8127.37/Google Chrome Framework
  448.6 MB  /Applications/Goodnotes.app/Contents/MacOS/Goodnotes
  426.2 MB  /Applications/Warp.app/Contents/MacOS/stable
  425.1 MB  /Applications/OrbStack.app/Contents/Resources/assets/release/arm64/rootfs.img
  398.7 MB  /Applications/Discord.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Electron Framework
  392.0 MB  /Applications/WhatsApp.app/Contents/MacOS/WhatsApp
Stopped at the 2 second deadline, so that's the largest so far.
```

That one returns after 2.02 seconds.

## The same in Go

[`go/main.go`](go/main.go) is the same program written by hand, with the standard library: a
`sync.WaitGroup`, a semaphore channel, `context.WithTimeout` and a labelled `for`/`select` loop. It
prints the same thing:

```bash
cd go && go run . /usr
```

| | PureScript | Go |
| --- | --- | --- |
| lines, without blank ones | 82 | 95 |
| of those, imports | 27 | 10 |
| the program itself | 55 | 85 |

Fewer lines is nice, the part that matters is which lines you don't write. In Go the walk is this:

```go
var walk func(dir string)
walk = func(dir string) {
	defer wg.Done()
	if ctx.Err() != nil {
		return
	}
	openDirectories <- struct{}{}
	entries, _ := os.ReadDir(dir)
	<-openDirectories
	for _, entry := range entries {
		path := filepath.Join(dir, entry.Name())
		if entry.IsDir() {
			wg.Add(1)
			go walk(path)
			continue
		}
		// …Lstat, then select on found <- file and <-ctx.Done()
	}
}

wg.Add(1)
go walk(root)
go func() {
	wg.Wait()
	close(found)
}()
```

Forget one `wg.Add(1)` and it closes the channel early, forget `<-openDirectories` and it hangs at
the 65th directory, and if `ReadDir` panicked the slot would be gone for good. In PureScript the
walk is this:

```purescript
walk scan directory = unlessM (isCancelled scan.context) do
  entries <- readDirectory scan.openDirectories directory
  for_ (Array.filter (not OS.entryIsDir) entries) (sizeOf >=> maybe (pure unit) (sendUnlessCancelled scan))
  mapConcurrently_ (walk scan) (Array.filter OS.entryIsDir entries <#> pathOf)
```

`mapConcurrently_` waits for the subdirectories itself, so there's no counter to keep right, and
`bracket_` gives the slot back whatever happens.

## The Go googoo writes

`googoo go out` puts the Go for this program in `out/`. With 0.1.18-go.5 that's 288 lines in `main.go`,
plus a few small files for `Maybe`, `Tuple` and the `Go.OS` types. Function names are 13 characters
on average and the longest is `RightEitherArrayDirEntry`. The file count is a plain Go `int` now, so
printing it is just `strconv.Itoa`. There are 2 `switch either`s, this program hardly
fails.

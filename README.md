# purescript-go

Go's standard library for PureScript. Compile with [Iris](https://github.com/i-am-the-slime/purescript-analyzer/tree/iris-go)
and you get a single native binary that reads files, runs programs, serves HTTP and uses every core
you've got.

```purescript
module Main where

import Prelude

import Data.Maybe (fromMaybe)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class.Console (log)
import Go.Error (message)
import Go.Net.HTTP (Address(..), QueryName(..))
import Go.Net.HTTP as HTTP

main :: Effect Unit
main = launchAff_ do
  log "listening on :8080"
  failure <- HTTP.listenAndServe (Address ":8080") \request ->
    pure (HTTP.ok ("hello " <> fromMaybe "stranger" (HTTP.query (QueryName "name") request)))
  log (show (message failure))
```

```
$ iris run --go
listening on :8080
$ curl 'localhost:8080/?name=Mark'
hello Mark
```

## Packages

| Package | Modules | |
| --- | --- | --- |
| `go-io` | `Go.IO`, `Go.IO.IORef`, `Go.IO.MVar`, `Go.IO.Chan`, `Go.IO.Async`, `Go.IO.Internal`, `Go.Error` | Haskell's `IO` on goroutines, and Go's `error` |
| `go-os` | `Go.OS`, `Go.OS.Stdio`, `Go.FilePath`, `Go.Path.Filepath` | files, directories, environment, arguments, exit, standard input and output, paths |
| `go-exec` | `Go.OS.Exec` | run programs, collect their output or hand them the terminal |
| `go-http` | `Go.Net.HTTP` | a server and a client |
| `go-time` | `Go.Time` | Go's time layouts, sleep |
| `go-bytes` | `Go.Bytes` | `[]byte`, for files and bodies that aren't text |

Take what you need, each one brings along the ones it builds on.

## Installing

You need Iris with the Go backend, and Go 1.27 or later:

```bash
brew install i-am-the-slime/tap/iris
```

The packages aren't in the registry yet, so add them to your `spago.yaml` straight from GitHub. Pick a
commit and list every package you use, and the ones they use:

```yaml
package:
  dependencies:
    - go-exec
    - go-io
    - go-os
workspace:
  extraPackages:
    go-io:
      git: https://github.com/i-am-the-slime/purescript-go.git
      ref: <commit>
      subdir: packages/go-io
    go-bytes:
      git: https://github.com/i-am-the-slime/purescript-go.git
      ref: <commit>
      subdir: packages/go-bytes
    go-os:
      git: https://github.com/i-am-the-slime/purescript-go.git
      ref: <commit>
      subdir: packages/go-os
    go-exec:
      git: https://github.com/i-am-the-slime/purescript-go.git
      ref: <commit>
      subdir: packages/go-exec
```

`go-os` and `go-http` need `go-bytes`, everything needs `go-io`.

Then run your program with `iris run --go`, or build it with `iris go`, which prints where it put the
binary.

There are no `.js` files: this only works with Iris's Go backend. `spago build` will complain about
missing foreign modules.

## go-io

If you know Haskell's `IO`, this is that. `IO` actions run on goroutines, off the event loop, so
they really run at the same time, on every core:

```purescript
module Main where

import Prelude

import Data.Array as Array
import Data.Foldable (sum)
import Effect (Effect)
import Effect.Class.Console (log)
import Go.IO (IO, getNumCapabilities, launchIO_)
import Go.IO.Async (mapConcurrently)

main :: Effect Unit
main = launchIO_ do
  cores <- getNumCapabilities
  counts <- mapConcurrently primesBetween chunks
  log (show (sum counts) <> " primes below 8000000, counted on " <> show cores <> " cores")
  where
  chunks = map (\i -> { from: i * 1_000_000, to: (i + 1) * 1_000_000 }) (Array.range 0 7)

primesBetween :: { from :: Int, to :: Int } -> IO Int
primesBetween { from, to } = pure (Array.length (Array.filter isPrime (Array.range from (to - 1))))

isPrime :: Int -> Boolean
isPrime n = n > 1 && noDivisorFrom 2
  where
  noDivisorFrom d = d * d > n || (n `mod` d /= 0 && noDivisorFrom (d + 1))
```

```
539777 primes below 8000000, counted on 18 cores
```

That takes 1.2 seconds here, and 5.8 with `GOMAXPROCS=1`. `mapConcurrently` calls
`primesBetween` on each chunk's own thread, so the counting happens there, even though `pure`
gets its argument worked out first. `concurrently` and `race` take actions that are already
built, so for pure work hand the inputs to `mapConcurrently` or `forConcurrently`.

The names are Haskell's: `forkIO`, `forkFinally`, `threadDelay`, `newIORef`, `atomicModifyIORef'`,
`newMVar`, `takeMVar`, `putMVar`, `modifyMVar_`, `newChan`, `readChan`, `writeChan`, and from
`Go.IO.Async`, `async`, `wait`, `concurrently`, `race` and `mapConcurrently`. `throwIO`, `catch`,
`try`, `bracket` and `finally` work as you'd expect, and `catch` even catches a panic in Go code.

### Sharing state between threads

An `Effect.Ref` isn't safe between parallel `IO` threads. Two threads that `modify` the same `Ref`
at once can lose an update. Use an `MVar` (`modifyMVar_`, `withMVar`) or an `IORef` with
`atomicModifyIORef'` instead: those are atomic, however many threads hit them.

### ParIO

`ParIO` is to `IO` what `ParAff` is to `Aff`: its `<*>` runs both sides at the same time, so
everything in `Control.Parallel` works on `IO`:

```purescript
pages :: Array URL -> IO (Array String)
pages = parTraverse fetch

fastest :: IO String
fastest = parOneOf [ fromCache, fromNetwork ]
```

`parTraverse` keeps the order, and `parOneOf` returns whichever finishes first. If one side throws,
the whole throws right away, without waiting for the rest.

### IO and the rest of your program

`IO` and the rest of the program meet in three places:

- `toAff` runs an `IO` action from `Aff`. The fiber waits, the event loop doesn't: other fibers and
  HTTP handlers keep going.
- `liftEffect` runs an `Effect` from inside `IO`: it waits for the program's main event loop and
  runs it there. That's how an `IO` thread gets at `log` or anything else that lives there, so
  `Effect.Class.Console.log` just works in `IO`. Keep these short, no fiber runs while one does.
  Each trip to the event loop and back costs about 80 ns, so a hot loop keeps its state in an
  `IORef`, which never leaves the thread's goroutine.
- `launchIO_` starts an `IO` action from `Effect`, like `launchAff_` does for `Aff`, and returns
  right away. `launchIO action callback` hands the callback an `Either Error a` on the event loop
  once the action is done.

### Different from GHC

- `threadDelay` takes `Milliseconds`, not microseconds.
- There's no `killThread`, and `race` doesn't cancel the loser. Go can't stop a goroutine from
  outside, so the loser runs to its end and its result is dropped.
- The program doesn't wait for its threads. Wait for them with an `MVar` or `Async`.
- `unsafePerformEffect` inside `IO` is as unsupported as `unsafePerformIO` is risky in Haskell: the
  `Effect` runs on whatever goroutine evaluates it, off the event loop.
- No STM.

### Errors are values

Go returns errors, so these bindings do too. Things that can fail return an `Either`, and `Go.Error`
has Go's `error` as `GoError`, with `message` to get at its text.

## go-os

```purescript
module Main where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (maybe)
import Data.Newtype (un)
import Effect (Effect)
import Effect.Class.Console (log)
import Go.FilePath (FilePath(..))
import Go.OS (EnvName(..), EnvValue(..), FSError(..))
import Go.OS as OS
import Go.Path.Filepath as Filepath

main :: Effect Unit
main = do
  home <- OS.lookupEnv (EnvName "HOME")
  let notes = Filepath.join [ maybe (FilePath ".") (FilePath <<< un EnvValue) home, FilePath "notes.txt" ]
  OS.readFile notes >>= case _ of
    Right text -> log text
    Left (NotExist _) -> log ("nothing in " <> un FilePath notes <> " yet")
    Left other -> log (show other)
```

`Go.OS` sorts file system errors the way Go's `errors.Is` does: `NotExist`, `Exist`, `Permission`, or
`OtherError` with the original `GoError`. `Go.Path.Filepath` joins, splits, cleans and globs paths.

### Standard input and output

`Go.OS.Stdio`'s `forEachLine` reads standard input a line at a time, as it arrives, so this is
`cat -n`:

```purescript
main :: Effect Unit
main = do
  count <- Ref.new 0
  result <- Stdio.forEachLine \line -> do
    number <- Ref.modify (_ + 1) count
    void (Stdio.writeStdout (show number <> " " <> line <> "\n"))
  either (log <<< show) pure result
```

Writes aren't buffered, so there's nothing to flush, and they come out in the order you make them,
mixed with `log` too. `readChunk` waits in `Aff` for the next piece of standard input.

### Text and bytes

Files come as `String` or as `Bytes`. A `String` is UTF-8 text: bytes that aren't valid UTF-8 turn
into U+FFFD, the replacement character. Want the bytes as they are? Use the `Bytes` version:
`readFileBytes`, `writeFileBytes`, `readAllBytes`.

## go-exec

A program that exits with a non-zero code isn't an error, it's output:

```purescript
module Main where

import Prelude

import Data.Either (Either(..))
import Effect (Effect)
import Effect.Class.Console (log)
import Go.OS (Arg(..), ExitCode(..))
import Go.OS.Exec (ExecError(..), Program(..), command)
import Go.OS.Exec as Exec

main :: Effect Unit
main = Exec.run (command (Program "git") [ Arg "status", Arg "--short" ]) >>= case _ of
  Right { exitCode: ExitCode 0, stdout } -> log stdout
  Right { stderr } -> log ("git failed: " <> stderr)
  Left (ProgramNotFound _) -> log "no git"
  Left (StartFailed error) -> log (show error)
```

`Arg`, `ExitCode` and the environment types come from `Go.OS`, so you'll want `go-os` too.

A command inherits your environment. Add variables with `Inherited`, or start from nothing with
`Only`:

```purescript
Exec.run ((command (Program "sh") [ Arg "-c", Arg "echo $GREETING" ])
  { environment = Inherited [ { name: EnvName "GREETING", value: EnvValue "moin" } ] })
```

`run` holds up the whole program until the command ends. `runAff` waits in `Aff` instead, so a
spinner or a server in the same program keeps going:

```purescript
Exec.runAff (command (Program "sleep") [ Arg "2" ])
```

Pick where each stream goes with `stdin`, `stdout` and `stderr`. `Parent` passes a stream through to
your own, `Capture` collects it in the result:

```purescript
Exec.runAff ((command (Program "gum") [ Arg "choose", Arg "red", Arg "blue" ])
  { stdin = ParentStdin, stderr = Parent })
```

`start` gives you the running `Process` to `wait` for or `kill`.

For programs that talk to the user, like an editor or `git commit`, `runInteractive` hands them your
terminal and gives you back their exit code:

```purescript
Exec.runInteractive (command (Program "vim") [ Arg "notes.md" ])
```

## go-http

The example at the top is a whole server. A handler is `Request -> Aff Response`, and so is the
client: `get` and `send` wait in `Aff`. Bodies come as `String` or, with `bodyBytes` and
`responseBodyBytes`, as `Bytes`.

### Handlers take turns

PureScript in `Aff` runs one piece at a time, just like on JavaScript's event loop, so while one
handler waits for a database, another server or a `delay`, the next request gets going. A `Ref` is
safe between two waits:

```purescript
count <- Ref.new 0
HTTP.start (Address ":8080") \_ -> do
  visits <- liftEffect (Ref.modify (_ + 1) count)
  pure (HTTP.ok ("visitor " <> show visits))
```

A handler can call another server, even one in the same program, without anything getting stuck.
Got work for every core? `toAff` it into `IO`.

## go-time

```purescript
module Main where

import Prelude

import Data.Either (Either(..))
import Effect (Effect)
import Effect.Class.Console (log)
import Go.Error (message)
import Go.Time (Layout(..), dateOnly, rfc3339)
import Go.Time as Time

main :: Effect Unit
main = case Time.parse rfc3339 "2026-11-23T09:30:00Z" of
  Right instant -> do
    log (Time.format dateOnly instant)
    log (Time.format (Layout "Mon, 02 Jan 2006 15:04") instant)
  Left error -> log (show (message error))
```

```
2026-11-23
Mon, 23 Nov 2026 09:30
```

Layouts are Go's: write how Go's reference time, Monday 2 January 2006 at 15:04:05, would look.
Times are `Instant`s, formatted in UTC.

## go-bytes

```purescript
module Main where

import Prelude

import Effect (Effect)
import Effect.Class.Console (log)
import Go.Bytes (ByteCount(..))
import Go.Bytes as Bytes

main :: Effect Unit
main = do
  let greeting = Bytes.fromString "moin, Welt 👋"
  log (show (Bytes.size greeting) <> " bytes")
  log (Bytes.toString (Bytes.slice (ByteCount 6.0) (ByteCount 10.0) greeting))
  log (show (Bytes.toArray (Bytes.fromString "hi")))
```

```
15.0 bytes
Welt
[104,105]
```

Sizes are `ByteCount`s, a `Number`, since files can be bigger than an `Int`. `Bytes` never change:
everything that makes bytes makes new ones.

## Testing

```bash
./test.sh
```

compiles the specs of every package with Iris and runs them. Set `IRIS_GO` to a local iris-go
checkout to build against that.

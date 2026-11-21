# purescript-golang

Go's standard library for PureScript. Compile with [Iris](https://github.com/i-am-the-slime/purescript-analyzer/tree/iris-go)
and you get a single native binary that reads files, runs programs and serves HTTP.

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

```bash
iris go --entry Main.main out
cd out && go build -o hello . && ./hello
```

## What's in it

| Module | Go package | |
| --- | --- | --- |
| `Go.OS` | `os` | files, directories, environment, arguments, exit |
| `Go.OS.Stdio` | `os`, `bufio` | standard input, output and error |
| `Go.OS.Exec` | `os/exec` | run programs, collect their output or hand them the terminal |
| `Go.Bytes` | `bytes` | `[]byte`, for files and bodies that aren't text |
| `Go.Path.Filepath` | `path/filepath` | join, split, clean, glob |
| `Go.Time` | `time` | Go's time layouts, sleep |
| `Go.Net.HTTP` | `net/http` | a server and a client |
| `Go.Error` | | Go's `error` |
| `Go.IO` | goroutines | Haskell's `IO`: threads, `IORef`, `MVar`, `Chan`, `Async` |

## Errors are values

Go returns errors, so these bindings do too. Things that can fail return an `Either`:

```purescript
OS.readFile (FilePath "config.toml") >>= case _ of
  Right text -> parse text
  Left (NotExist _) -> pure defaults
  Left other -> throw (show other)
```

`Go.OS` sorts file system errors the way Go's `errors.Is` does: `NotExist`, `Exist`, `Permission`, or
`OtherError` with the original `GoError`.

A program that exits with a non-zero code isn't an error either, it's output:

```purescript
Exec.run (command (Program "git") [ Arg "status" ]) >>= case _ of
  Right { exitCode: ExitCode 0, stdout } -> log stdout
  Right { stderr } -> log ("git failed: " <> stderr)
  Left (ProgramNotFound _) -> log "no git"
  Left (StartFailed error) -> log (show error)
```

## Standard input and output

`forEachLine` reads standard input a line at a time, as it arrives, so this is `cat -n`:

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
mixed with `log` too.

## Running programs

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

## Text and bytes

Files and HTTP bodies come as `String` or as `Bytes`. A `String` is UTF-8 text: bytes that aren't valid
UTF-8 turn into U+FFFD, the replacement character. Want the bytes as they are? Use the `Bytes`
version: `readFileBytes`, `bodyBytes`, `responseBodyBytes`.

## HTTP handlers take turns

A handler is `Request -> Aff Response`, and so is the client: `get` and `send` wait in `Aff`.
PureScript runs one piece at a time, just like on JavaScript's event loop, so while one handler
waits for a database, another server or a `delay`, the next request gets going. A `Ref` is safe
between two waits:

```purescript
count <- Ref.new 0
HTTP.start (Address ":8080") \_ -> do
  visits <- liftEffect (Ref.modify (_ + 1) count)
  pure (HTTP.ok ("visitor " <> show visits))
```

A handler can call another server, even one in the same program, without anything getting stuck.

## Parallel IO

If you know Haskell's `IO`, this is that. `IO` actions run on goroutines, off the event loop,
so they really run at the same time, on every core:

```purescript
main :: Effect Unit
main = launchAff_ do
  cores <- toAff getNumCapabilities
  counts <- toAff (mapConcurrently primesBetween chunks)
  log (show (sum counts) <> " primes below 8000000, counted on " <> show cores <> " cores")
  where
  chunks = map (\i -> { from: i * 1_000_000, to: (i + 1) * 1_000_000 }) (Array.range 0 7)

primesBetween :: { from :: Int, to :: Int } -> IO Int
primesBetween { from, to } = pure (Array.length (Array.filter isPrime (Array.range from (to - 1))))
```

```
539777 primes below 8000000, counted on 18 cores
```

That takes 0.47 seconds here, and 0.87 with `GOMAXPROCS=1`. `mapConcurrently` calls
`primesBetween` on each chunk's own thread, so the counting happens there, even though `pure`
gets its argument worked out first. `concurrently` and `race` take actions that are already
built, so for pure work hand the inputs to `mapConcurrently` or `forConcurrently`.

The names are Haskell's: `forkIO`, `forkFinally`, `threadDelay`, `newIORef`, `atomicModifyIORef'`,
`newMVar`, `takeMVar`, `putMVar`, `modifyMVar_`, `newChan`, `readChan`, `writeChan`, and from
`Go.IO.Async`, `async`, `wait`, `concurrently`, `race` and `mapConcurrently`. `throwIO`, `catch`,
`try`, `bracket` and `finally` work as you'd expect, and `catch` even catches a panic in Go code.

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

`IO` and the rest of the program meet in three places:

- `toAff` runs an `IO` action from `Aff`. The fiber waits, the event loop doesn't: other fibers and
  HTTP handlers keep going.
- `runEffect`, or `liftEffect`, runs an `Effect` from inside `IO`: it runs it on the program's main
  event loop and waits for it. That's how an `IO` thread gets at a `Ref`, `log` or anything else
  that lives there, so `Effect.Class.Console.log` just works in `IO`. Keep these short, no fiber
  runs while one does. Each trip to the event loop and back costs about 80 ns, so a hot loop
  keeps its state in an `IORef`, which never leaves the thread's goroutine.
- `launchIO_` starts an `IO` action from `Effect`, like `launchAff_` does for `Aff`, and returns
  right away. `launchIO action callback` hands the callback an `Either Error a` on the event loop
  once the action is done.

A few things are different from GHC:

- `threadDelay` takes `Milliseconds`, not microseconds.
- There's no `killThread`, and `race` doesn't cancel the loser. Go can't stop a goroutine from
  outside, so the loser runs to its end and its result is dropped.
- The program doesn't wait for its threads. Wait for them with an `MVar` or `Async`.
- `unsafePerformEffect` inside `IO` is as unsupported as `unsafePerformIO` is risky in Haskell: the
  `Effect` runs on whatever goroutine evaluates it, off the event loop.
- No STM.

## Go only

There are no `.js` files: this package only works with Iris's Go backend. `spago build` will complain
about missing foreign modules, so use `iris go` to compile.

## Testing

```bash
./test.sh
```

compiles the specs with Iris and runs them.

# purescript-golang

Go's standard library for PureScript. Compile with [Iris](https://github.com/i-am-the-slime/purescript-analyzer/tree/iris-go)
and you get a single native binary that reads files, runs programs and serves HTTP.

```purescript
module Main where

import Prelude

import Data.Maybe (fromMaybe)
import Effect (Effect)
import Effect.Console (log)
import Go.Error (message)
import Go.Net.HTTP (Address(..), QueryName(..))
import Go.Net.HTTP as HTTP

main :: Effect Unit
main = do
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

For programs that talk to the user, like an editor or `git commit`, `runInteractive` hands them your
terminal and gives you back their exit code:

```purescript
Exec.runInteractive (command (Program "vim") [ Arg "notes.md" ])
```

## Text and bytes

Files and HTTP bodies come as `String` or as `Bytes`. A `String` is UTF-8 text: bytes that aren't valid
UTF-8 turn into U+FFFD, the replacement character. Want the bytes as they are? Use the `Bytes`
version: `readFileBytes`, `bodyBytes`, `responseBodyBytes`.

## HTTP handlers run at the same time

Go serves every request on its own goroutine, and so do your handlers. If they share a `Ref`, they share
it the way Go handlers share a variable.

## Go only

There are no `.js` files: this package only works with Iris's Go backend. `spago build` will complain
about missing foreign modules, so use `iris go` to compile.

## Testing

```bash
./test.sh
```

compiles the specs with Iris and runs them.

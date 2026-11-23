module Go.OS.Stdio
  ( readAll
  , readAllBytes
  , forEachLine
  , readChunk
  , writeStdout
  , writeStdoutBytes
  , writeStderr
  , writeStderrBytes
  , stdinIsTerminal
  , stdoutIsTerminal
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Go.Bytes (Bytes)
import Go.Error (GoError)

-- | Reads standard input to its end, as UTF-8 text.
readAll :: Effect (Either GoError String)
readAll = readAllImpl Left Right

readAllBytes :: Effect (Either GoError Bytes)
readAllBytes = readAllBytesImpl Left Right

-- | Reads standard input a line at a time, as it arrives, and hands each line to the callback
-- | without its line ending (`\n` or `\r\n`). A last line without a line ending counts too. Lines
-- | can be any length.
forEachLine :: (String -> Effect Unit) -> Effect (Either GoError Unit)
forEachLine handle = forEachLineImpl Left (Right unit) handle

-- | Waits for the next piece of standard input and returns what arrived, such as a single key
-- | press when the terminal is in raw mode. `Nothing` means the input has ended. The fiber waits,
-- | the program doesn't. A character split between two reads comes whole with the second.
readChunk :: Aff (Either GoError (Maybe String))
readChunk = makeAff \resolve -> readChunkImpl Left (Right Nothing) (Right <<< Just) (resolve <<< Right) $> nonCanceler

-- | Writes the text to standard output as it is, without adding a newline. Writes aren't
-- | buffered, so there is nothing to flush, and they interleave with `Effect.Console.log` in
-- | program order.
writeStdout :: String -> Effect (Either GoError Unit)
writeStdout = writeStdoutImpl Left (Right unit)

writeStdoutBytes :: Bytes -> Effect (Either GoError Unit)
writeStdoutBytes = writeStdoutBytesImpl Left (Right unit)

-- | Like `writeStdout`, for standard error.
writeStderr :: String -> Effect (Either GoError Unit)
writeStderr = writeStderrImpl Left (Right unit)

writeStderrBytes :: Bytes -> Effect (Either GoError Unit)
writeStderrBytes = writeStderrBytesImpl Left (Right unit)

-- | Whether standard input is a terminal rather than a file or a pipe. It checks for a character
-- | device, so `/dev/null` counts as a terminal too.
stdinIsTerminal :: Effect Boolean
stdinIsTerminal = stdinIsTerminalImpl

-- | Whether standard output is a terminal rather than a file or a pipe, as `stdinIsTerminal`
-- | checks.
stdoutIsTerminal :: Effect Boolean
stdoutIsTerminal = stdoutIsTerminalImpl

foreign import readAllImpl :: forall r. (GoError -> r) -> (String -> r) -> Effect r
foreign import readAllBytesImpl :: forall r. (GoError -> r) -> (Bytes -> r) -> Effect r
foreign import forEachLineImpl :: forall r. (GoError -> r) -> r -> (String -> Effect Unit) -> Effect r
foreign import readChunkImpl
  :: forall r. (GoError -> r) -> r -> (String -> r) -> (r -> Effect Unit) -> Effect Unit
foreign import writeStdoutImpl :: forall r. (GoError -> r) -> r -> String -> Effect r
foreign import writeStdoutBytesImpl :: forall r. (GoError -> r) -> r -> Bytes -> Effect r
foreign import writeStderrImpl :: forall r. (GoError -> r) -> r -> String -> Effect r
foreign import writeStderrBytesImpl :: forall r. (GoError -> r) -> r -> Bytes -> Effect r
foreign import stdinIsTerminalImpl :: Effect Boolean
foreign import stdoutIsTerminalImpl :: Effect Boolean

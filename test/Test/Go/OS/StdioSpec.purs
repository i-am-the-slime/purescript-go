module Test.Go.OS.StdioSpec
  ( spec
  , child
  ) where

import Prelude

import Data.Either (Either(..), either)
import Data.Maybe (Maybe(..))
import Data.Newtype (un)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (throw)
import Go.Bytes as Bytes
import Go.FilePath (FilePath(..))
import Go.OS (EnvName(..), EnvValue(..), ExitCode(..))
import Go.OS as OS
import Go.OS.Exec (Environment(..), Output, Program(..), Stdin(..), command)
import Go.OS.Exec as Exec
import Go.OS.Stdio as Stdio
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- | The variable that makes the spec binary run as the child these specs pipe into.
childMode :: EnvName
childMode = EnvName "GO_SPEC_CHILD"

spec :: Spec Unit
spec = describe "Go.OS.Stdio" do
  it "reads standard input line by line, with or without a last line ending" do
    output <- asChild "lines" "one\r\ntwo\n\nthree"
    output.stdout `shouldEqual` "[one][two][][three]"

  it "reads all of standard input as bytes and writes them unchanged" do
    output <- asChild "bytes" "h\xFFFDi\n"
    output.stdout `shouldEqual` "h\xFFFDi\n"

  it "reads all of standard input as text and writes to standard error" do
    output <- asChild "text" "to stderr"
    output.stderr `shouldEqual` "to stderr"
    output.stdout `shouldEqual` ""

  it "sees a pipe, not a terminal" do
    output <- asChild "terminal" ""
    output.stdout `shouldEqual` "stdin false, stdout false"

  it "keeps writes in program order" do
    output <- asChild "order" ""
    output.stdout `shouldEqual` "a\nb\nc"

-- | Runs the spec binary itself as a child in the mode, with the input piped to it.
asChild :: String -> String -> Aff Output
asChild mode input = liftEffect do
  binary <- OS.executable >>= either (throw <<< show) pure
  let
    runChild = (command (Program (un FilePath binary)) [])
      { environment = Inherited [ { name: childMode, value: EnvValue mode } ], stdin = Text input }
  output <- Exec.run runChild >>= either (throw <<< show) pure
  unless (output.exitCode == ExitCode 0) (throw ("child failed: " <> output.stderr))
  pure output

-- | What the child does in each mode, if this binary runs as one.
child :: Effect Boolean
child = OS.lookupEnv childMode >>= case _ of
  Just (EnvValue "lines") -> ran (Stdio.forEachLine \line -> void (Stdio.writeStdout ("[" <> line <> "]")))
  Just (EnvValue "bytes") -> ran (Stdio.readAllBytes >>= either (pure <<< Left) Stdio.writeStdoutBytes)
  Just (EnvValue "text") -> ran (Stdio.readAll >>= either (pure <<< Left) Stdio.writeStderr)
  Just (EnvValue "terminal") -> do
    stdin <- Stdio.stdinIsTerminal
    stdout <- Stdio.stdoutIsTerminal
    ran (Stdio.writeStdout ("stdin " <> show stdin <> ", stdout " <> show stdout))
  Just (EnvValue "order") -> do
    log "a"
    _ <- Stdio.writeStdout "b\n"
    ran (Stdio.writeStdoutBytes (Bytes.fromString "c"))
  _ -> pure false
  where
  ran action = action >>= either (throw <<< show) (const (pure true))

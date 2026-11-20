module Test.Go.OS.ExecSpec where

import Prelude

import Data.Either (Either(..), either)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Go.FilePath (FilePath(..))
import Go.OS (Arg(..), ExitCode(..))
import Go.OS.Exec (ExecError(..), Output, Program(..), command)
import Go.OS.Exec as Exec
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = describe "Go.OS.Exec" do
  it "collects standard output" do
    output <- ran (command (Program "echo") [ Arg "hello", Arg "go" ])
    output.stdout `shouldEqual` "hello go\n"
    output.exitCode `shouldEqual` ExitCode 0

  it "feeds standard input" do
    output <- ran ((command (Program "tr") [ Arg "a-z", Arg "A-Z" ]) { stdin = "shout\n" })
    output.stdout `shouldEqual` "SHOUT\n"

  it "runs in the given directory" do
    output <- ran ((command (Program "pwd") []) { dir = Just (FilePath "/") })
    output.stdout `shouldEqual` "/\n"

  it "returns a non-zero exit code and standard error as output" do
    output <- ran (command (Program "sh") [ Arg "-c", Arg "echo oops >&2; exit 3" ])
    output.stderr `shouldEqual` "oops\n"
    output.exitCode `shouldEqual` ExitCode 3

  it "reports a program that is not on the PATH" do
    liftEffect (Exec.run (command (Program "no-such-program-anywhere") [])) >>= case _ of
      Left (ProgramNotFound program) -> program `shouldEqual` Program "no-such-program-anywhere"
      other -> fail ("expected ProgramNotFound, got " <> either show (_.stdout) other)

ran :: Exec.Command -> Aff Output
ran cmd = liftEffect (Exec.run cmd) >>= either (liftEffect <<< throw <<< show) pure

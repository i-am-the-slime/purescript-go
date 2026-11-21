module Test.Go.OS.ExecSpec where

import Prelude

import Data.Either (Either(..), either)
import Data.Maybe (Maybe(..))
import Control.Monad.Rec.Class (forever)
import Effect.Aff (Aff, Milliseconds(..), delay, forkAff, killFiber)
import Effect.Exception (error)
import Effect.Ref as Ref
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Go.FilePath (FilePath(..))
import Go.OS (Arg(..), EnvName(..), EnvValue(..), ExitCode(..))
import Go.OS.Exec (Environment(..), ExecError(..), Output, Program(..), Sink(..), Stdin(..), command)
import Go.OS.Exec as Exec
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = describe "Go.OS.Exec" do
  it "collects standard output" do
    output <- ran (command (Program "echo") [ Arg "hello", Arg "go" ])
    output.stdout `shouldEqual` "hello go\n"
    output.exitCode `shouldEqual` ExitCode 0
    output.signal `shouldEqual` ""

  it "feeds standard input" do
    output <- ran ((command (Program "tr") [ Arg "a-z", Arg "A-Z" ]) { stdin = Text "shout\n" })
    output.stdout `shouldEqual` "SHOUT\n"

  it "runs in the given directory" do
    output <- ran ((command (Program "pwd") []) { dir = Just (FilePath "/") })
    output.stdout `shouldEqual` "/\n"

  it "returns a non-zero exit code and standard error as output" do
    output <- ran (command (Program "sh") [ Arg "-c", Arg "echo oops >&2; exit 3" ])
    output.stderr `shouldEqual` "oops\n"
    output.exitCode `shouldEqual` ExitCode 3

  it "adds variables to the inherited environment" do
    let variable = { name: EnvName "GO_EXEC_SPEC", value: EnvValue "added" }
    output <- ran ((command (Program "sh") [ Arg "-c", Arg "echo $GO_EXEC_SPEC ${PATH:+has-path}" ]) { environment = Inherited [ variable ] })
    output.stdout `shouldEqual` "added has-path\n"

  it "runs with only the given environment" do
    let variable = { name: EnvName "GO_EXEC_SPEC", value: EnvValue "alone" }
    output <- ran ((command (Program "sh") [ Arg "-c", Arg "echo $GO_EXEC_SPEC ${HOME:-no-home}" ]) { environment = Only [ variable ] })
    output.stdout `shouldEqual` "alone no-home\n"

  it "runs an interactive program and returns its exit code" do
    liftEffect (Exec.runInteractive (command (Program "sh") [ Arg "-c", Arg "exit 4" ])) >>= case _ of
      Right code -> code `shouldEqual` ExitCode 4
      Left error -> fail (show error)

  it "lets other fibers run while runAff waits" do
    ticks <- Ref.new 0 # liftEffect
    ticker <- forkAff $ forever do
      delay (Milliseconds 10.0)
      Ref.modify_ (_ + 1) ticks # liftEffect
    output <- ranAff (command (Program "sleep") [ Arg "0.2" ])
    killFiber (error "done") ticker
    counted <- Ref.read ticks # liftEffect
    output.exitCode `shouldEqual` ExitCode 0
    (counted > 5) `shouldEqual` true

  it "sends standard error to this program's own when asked" do
    output <- ranAff ((command (Program "sh") [ Arg "-c", Arg "echo out; echo err >&2" ]) { stderr = Parent })
    output.stdout `shouldEqual` "out\n"
    output.stderr `shouldEqual` ""

  it "starts a program, kills it, and waits for it" do
    process <- liftEffect (Exec.start (command (Program "sleep") [ Arg "10" ])) >>= either (liftEffect <<< throw <<< show) pure
    killed <- Exec.kill process # liftEffect
    output <- Exec.wait process >>= either (liftEffect <<< throw <<< show) pure
    either show (const "killed") killed `shouldEqual` "killed"
    output.exitCode `shouldEqual` ExitCode (-1)
    output.signal `shouldEqual` "SIGKILL"

  it "reports a program that is not on the PATH from runAff" do
    Exec.runAff (command (Program "no-such-program-anywhere") []) >>= case _ of
      Left (ProgramNotFound program) -> program `shouldEqual` Program "no-such-program-anywhere"
      other -> fail ("expected ProgramNotFound, got " <> either show (_.stdout) other)

  it "reports a program that is not on the PATH" do
    liftEffect (Exec.run (command (Program "no-such-program-anywhere") [])) >>= case _ of
      Left (ProgramNotFound program) -> program `shouldEqual` Program "no-such-program-anywhere"
      other -> fail ("expected ProgramNotFound, got " <> either show (_.stdout) other)

ranAff :: Exec.Command -> Aff Output
ranAff cmd = Exec.runAff cmd >>= either (liftEffect <<< throw <<< show) pure

ran :: Exec.Command -> Aff Output
ran cmd = liftEffect (Exec.run cmd) >>= either (liftEffect <<< throw <<< show) pure

module Test.Spec.Runner.GoSpec
  ( spec
  , child
  ) where

import Prelude

import Data.Either (either)
import Data.Maybe (Maybe(..))
import Data.Newtype (un)
import Data.String (Pattern(..))
import Data.String as String
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Go.FilePath (FilePath(..))
import Go.OS (EnvName(..), EnvValue(..), ExitCode(..))
import Go.OS as OS
import Go.OS.Exec (Environment(..), Output, Program(..), command)
import Go.OS.Exec as Exec
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (defaultConfig)
import Test.Spec.Runner.Go (runSpecAndExitProcess, runSpecAndExitProcess')

spec :: Spec Unit
spec = describe "Test.Spec.Runner.Go" do
  it "exits with 0 when every spec passes, after the reporter printed them" do
    output <- asChild "passing"
    output.exitCode `shouldEqual` ExitCode 0
    output.stdout `shouldMention` "one and one are two"

  it "exits with 1 when a spec fails" do
    output <- asChild "failing"
    output.exitCode `shouldEqual` ExitCode 1
    output.stdout `shouldMention` "one and one are three"

  it "never prints spec's warning about Node.js" do
    passing <- asChild "passing"
    failing <- asChild "failing"
    passing.stdout `shouldNotMention` "WARNING"
    failing.stdout `shouldNotMention` "WARNING"

  it "takes a config, and exits itself even when the config says exit" do
    output <- asChild "config"
    output.exitCode `shouldEqual` ExitCode 1
    output.stdout `shouldNotMention` "WARNING"
  where
  shouldMention text part = String.contains (Pattern part) text `shouldEqual` true
  shouldNotMention text part = String.contains (Pattern part) text `shouldEqual` false

-- | The variable that makes the spec binary run a small spec of its own and exit.
childMode :: EnvName
childMode = EnvName "GO_SPEC_RUNNER_CHILD"

-- | Runs the spec binary itself as a child in the mode.
asChild :: String -> Aff Output
asChild mode = liftEffect do
  binary <- OS.executable >>= either (throw <<< show) pure
  let runChild = (command (Program (un FilePath binary)) []) { environment = Inherited [ { name: childMode, value: EnvValue mode } ] }
  Exec.run runChild >>= either (throw <<< show) pure

-- | Runs the child's spec and exits, if this binary runs as one.
child :: Effect Boolean
child = OS.lookupEnv childMode >>= case _ of
  Just (EnvValue "passing") -> ran (runSpecAndExitProcess [ consoleReporter ] passing)
  Just (EnvValue "failing") -> ran (runSpecAndExitProcess [ consoleReporter ] (passing *> failing))
  Just (EnvValue "config") -> ran (runSpecAndExitProcess' (defaultConfig { exit = true, failFast = true }) [ consoleReporter ] (failing *> passing))
  _ -> pure false
  where
  ran run = run $> true
  passing = it "one and one are two" ((1 + 1) `shouldEqual` 2)
  failing = it "one and one are three" ((1 + 1) `shouldEqual` 3)

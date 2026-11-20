module Test.Main where

import Prelude

import Data.Identity (Identity(..))
import Data.Newtype (un)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Go.OS (ExitCode(..))
import Go.OS as OS
import Test.Go.BytesSpec as BytesSpec
import Test.Go.Net.HTTPSpec as HTTPSpec
import Test.Go.OS.ExecSpec as ExecSpec
import Test.Go.OS.StdioSpec as StdioSpec
import Test.Go.OSSpec as OSSpec
import Test.Go.Path.FilepathSpec as FilepathSpec
import Test.Go.TimeSpec as TimeSpec
import Test.Spec (Spec)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (defaultConfig, evalSpecT)
import Test.Spec.Summary (successful)

-- | Runs the specs, unless the specs started this binary as a child to pipe into.
main :: Effect Unit
main = do
  isChild <- StdioSpec.child
  unless isChild do
    launchAff_ do
      results <- un Identity (evalSpecT (defaultConfig { exit = false }) [ consoleReporter ] specs)
      unless (successful results) (liftEffect (OS.exit (ExitCode 1)))

specs :: Spec Unit
specs = do
  OSSpec.spec
  ExecSpec.spec
  StdioSpec.spec
  BytesSpec.spec
  FilepathSpec.spec
  TimeSpec.spec
  HTTPSpec.spec

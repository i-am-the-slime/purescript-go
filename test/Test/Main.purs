module Test.Main where

import Prelude

import Data.Identity (Identity(..))
import Data.Newtype (un)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Go.OS (ExitCode(..))
import Go.OS as OS
import Test.Go.OSSpec as OSSpec
import Test.Go.Path.FilepathSpec as FilepathSpec
import Test.Spec (Spec)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (defaultConfig, evalSpecT)
import Test.Spec.Summary (successful)

main :: Effect Unit
main = launchAff_ do
  results <- un Identity (evalSpecT (defaultConfig { exit = false }) [ consoleReporter ] specs)
  unless (successful results) (liftEffect (OS.exit (ExitCode 1)))

specs :: Spec Unit
specs = do
  OSSpec.spec
  FilepathSpec.spec

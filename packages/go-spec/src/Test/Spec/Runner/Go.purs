-- | spec-node's `runSpecAndExitProcess` for programs compiled to Go: runs the specs, then exits
-- | the process with 0 when they all passed and 1 when one failed or the run itself threw.
module Test.Spec.Runner.Go
  ( runSpecAndExitProcess
  , runSpecAndExitProcess'
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Identity (Identity(..))
import Data.Newtype (un)
import Effect (Effect)
import Effect.Aff (launchAff_, try)
import Effect.Class (liftEffect)
import Effect.Console as Console
import Go.OS (ExitCode(..))
import Go.OS as OS
import Test.Spec (Spec)
import Test.Spec.Runner (Config, Reporter, defaultConfig, evalSpecT)
import Test.Spec.Summary (successful)

-- | Runs the specs with spec's `defaultConfig`, reporting to the reporters, and exits.
runSpecAndExitProcess :: Array Reporter -> Spec Unit -> Effect Unit
runSpecAndExitProcess = runSpecAndExitProcess' defaultConfig

-- | Runs the specs with the config, reporting to the reporters, and exits. The config's `exit` is
-- | ignored: this always exits, and spec's own exit, which warns about Node.js, never runs.
runSpecAndExitProcess' :: Config -> Array Reporter -> Spec Unit -> Effect Unit
runSpecAndExitProcess' config reporters spec = launchAff_ do
  outcome <- try runTheSpecs
  exitCode <- exitCodeFor outcome # liftEffect
  OS.exit exitCode # liftEffect
  where
  runTheSpecs = un Identity (evalSpecT (config { exit = false }) reporters spec)

  exitCodeFor = case _ of
    Right results | successful results -> pure (ExitCode 0)
    Right _ -> pure (ExitCode 1)
    Left failure -> do
      Console.error (show failure)
      pure (ExitCode 1)

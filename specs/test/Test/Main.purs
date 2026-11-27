module Test.Main where

import Prelude

import Effect (Effect)
import Test.Go.BytesSpec as BytesSpec
import Test.Go.IO.ChannelSpec as ChannelSpec
import Test.Go.IOSpec as IOSpec
import Test.Go.Net.HTTPSpec as HTTPSpec
import Test.Go.OS.ExecSpec as ExecSpec
import Test.Go.OS.StdioSpec as StdioSpec
import Test.Go.MapSpec as MapSpec
import Test.Go.OSSpec as OSSpec
import Test.Go.Path.FilepathSpec as FilepathSpec
import Test.Go.TimeSpec as TimeSpec
import Test.Spec (Spec)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Go (runSpecAndExitProcess)
import Test.Spec.Runner.GoSpec as RunnerSpec

-- | Runs the specs, unless the specs started this binary as a child to pipe into.
main :: Effect Unit
main = do
  isChild <- StdioSpec.child `orElse` IOSpec.child `orElse` RunnerSpec.child
  unless isChild (runSpecAndExitProcess [ consoleReporter ] specs)
  where
  orElse first second = first >>= if _ then pure true else second

specs :: Spec Unit
specs = do
  OSSpec.spec
  ExecSpec.spec
  StdioSpec.spec
  BytesSpec.spec
  FilepathSpec.spec
  TimeSpec.spec
  HTTPSpec.spec
  IOSpec.spec
  ChannelSpec.spec
  MapSpec.spec
  RunnerSpec.spec

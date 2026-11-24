module Test.Parallel.Main where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Class (liftEffect)
import Go.IO.Console (log)
import Effect.Exception (error)
import Go.IO (IO, launchIO_, threadDelay, throwIO)
import Go.IO.Async (concurrently_, forConcurrently_, race)
import Go.IO.Internal (IO(..))
import Go.IO.MVar (modifyMVar_, newEmptyMVar, newMVar, putMVar, readMVar, takeMVar)

main :: Effect Unit
main = launchIO_ do
  meetInsideLiftEffect
  log "two liftEffects ran at the same time"
  counted <- modifyFromThreads
  log ("32 threads counted " <> show counted.count <> " and " <> show counted.hits <> " hits")
  unless (counted == { count: 32_000, hits: 32_000 }) (throwIO (error "lost a modify"))
  forConcurrently_ (Array.range 1 4) \thread -> log ("thread " <> show thread <> " logged on its own")

meetInsideLiftEffect :: IO Unit
meetInsideLiftEffect = race (threadDelay (Milliseconds 5_000.0)) handshake >>= case _ of
  Left _ -> throwIO (error "each liftEffect waited for the other")
  Right _ -> pure unit
  where
  handshake = do
    left <- newEmptyMVar
    right <- newEmptyMVar
    concurrently_
      (insideLiftEffect (putMVar left unit *> takeMVar right))
      (insideLiftEffect (putMVar right unit *> takeMVar left))
  insideLiftEffect (IO effect) = liftEffect effect

modifyFromThreads :: IO { count :: Int, hits :: Int }
modifyFromThreads = do
  count <- newMVar 0
  stats <- newMVar { hits: 0, lastThread: 0 }
  forConcurrently_ (Array.range 1 32) \thread ->
    repeat 1_000 do
      modifyMVar_ count (pure <<< (_ + 1))
      modifyMVar_ stats \seen -> pure { hits: seen.hits + 1, lastThread: thread }
      liftEffect (pure unit)
  total <- readMVar count
  seen <- readMVar stats
  pure { count: total, hits: seen.hits }
  where
  repeat times action = when (times > 0) (action *> repeat (times - 1) action)

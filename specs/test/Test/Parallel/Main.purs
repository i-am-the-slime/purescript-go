module Test.Parallel.Main where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Class (liftEffect)
import Go.IO.Console (log)
import Effect.Exception (error)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Go.IO (IO, forkIO, launchIO_, threadDelay, threadDelayWith, throwIO)
import Go.IO.Async (concurrently_, forConcurrently_, race)
import Go.IO.Chan (newBufferedChan, newChan, sendAll)
import Go.IO.Context (background, cancel, withCancel)
import Go.IO.Internal (IO(..))
import Go.IO.MVar (MVar, modifyMVar_, newEmptyMVar, newMVar, putMVar, readMVar, takeMVar, takeMVarWith)
import Go.IO.Select (onDone, onReceive, select2)

main :: Effect Unit
main = launchIO_ do
  meetInsideLiftEffect
  log "two liftEffects ran at the same time"
  counted <- modifyFromThreads
  log ("32 threads counted " <> show counted.count <> " and " <> show counted.hits <> " hits")
  unless (counted == { count: 32_000, hits: 32_000 }) (throwIO (error "lost a modify"))
  forConcurrently_ (Array.range 1 4) \thread -> log ("thread " <> show thread <> " logged on its own")
  merged <- mergeFromThreads
  log ("select merged " <> show merged.received <> " records from 8 threads, then saw the context cancelled")
  unless (merged == { received: 8_000, cancelled: true }) (throwIO (error "select lost a record"))
  interrupted <- interruptWaits
  log ("a cancel woke " <> show interrupted <> " waiting threads")
  unless (interrupted == 3) (throwIO (error "a wait missed its cancel"))

-- | Eight threads send records on one buffered channel; the reader selects between it and a
-- | context that a ninth thread cancels once everything is read.
mergeFromThreads :: IO { received :: Int, cancelled :: Boolean }
mergeFromThreads = do
  readings <- newBufferedChan 16
  allRead <- newEmptyMVar
  context /\ cancelContext <- withCancel background
  forConcurrently_ (Array.range 1 8) \thread -> void (forkIO (sendFrom readings thread))
  _ <- forkIO (takeMVar allRead *> cancel cancelContext)
  receiveUntilCancelled readings allRead context 0
  where
  sendFrom readings thread = sendAll readings (Array.range 1 1_000 <#> \index -> { thread, index })
  receiveUntilCancelled readings allRead context received = do
    next <- select2
      (onReceive readings \_ -> pure (Just (received + 1)))
      (onDone context (pure Nothing))
    case next of
      Just count -> do
        when (count == 8_000) (putMVar allRead unit)
        receiveUntilCancelled readings allRead context count
      Nothing -> pure { received, cancelled: true }

-- | A thread each waits in threadDelayWith, takeMVarWith and a select on an empty channel; one
-- | cancel wakes all three.
interruptWaits :: IO Int
interruptWaits = do
  context /\ cancelContext <- withCancel background
  woken <- newMVar 0
  nothingComes <- newChan
  emptyBox <- newEmptyMVar
  let wake = modifyMVar_ woken (pure <<< (_ + 1))
  waiting <- newEmptyMVar
  _ <- forkIO (threadDelayWith context (Milliseconds 60_000.0) *> wake *> putMVar waiting unit)
  _ <- forkIO (takeMVarWith context (emptyBox :: MVar Int) *> wake *> putMVar waiting unit)
  _ <- forkIO (select2 (onReceive nothingComes \(_ :: Maybe Int) -> pure unit) (onDone context (pure unit)) *> wake *> putMVar waiting unit)
  threadDelay (Milliseconds 20.0)
  cancel cancelContext
  forConcurrently_ (Array.range 1 3) \_ -> takeMVar waiting
  readMVar woken

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

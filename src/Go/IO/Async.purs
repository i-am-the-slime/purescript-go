-- | Haskell's `Control.Concurrent.Async`: run `IO` actions at the same time and wait for their
-- | results.
-- |
-- | One difference: Go can't stop a goroutine from outside, so nothing here cancels a thread.
-- | When `race` has a winner, or `concurrently` a failure, the other threads keep running until
-- | they finish on their own; their results are dropped.
module Go.IO.Async
  ( Async
  , async
  , wait
  , waitCatch
  , poll
  , concurrently
  , concurrently_
  , race
  , race_
  , mapConcurrently
  , mapConcurrently_
  , forConcurrently
  , forConcurrently_
  , replicateConcurrently
  , replicateConcurrently_
  ) where

import Prelude

import Control.Monad.Rec.Class (Step(..), tailRecM)
import Data.Array as Array
import Data.Either (Either(..), blush, either)
import Data.Foldable (class Foldable, length, traverse_)
import Data.Maybe (Maybe(..))
import Data.Traversable (class Traversable, traverse)
import Data.Tuple.Nested (type (/\), (/\))
import Effect.Exception (Error)
import Go.IO (IO, forkFinally, throwIO)
import Go.IO.Chan (Chan, newChan, readChan, writeChan)
import Go.IO.MVar (MVar, newEmptyMVar, putMVar, readMVar, tryReadMVar)

-- | An action running on a thread of its own, and its result once it has one.
newtype Async a = Async (MVar (Either Error a))

-- | Starts the action on a new thread.
async :: forall a. IO a -> IO (Async a)
async action = do
  outcome <- newEmptyMVar
  _ <- forkFinally action (putMVar outcome)
  pure (Async outcome)

-- | The result, waiting for it. If the action threw, this throws the same.
wait :: forall a. Async a -> IO a
wait running = waitCatch running >>= either throwIO pure

waitCatch :: forall a. Async a -> IO (Either Error a)
waitCatch (Async outcome) = readMVar outcome

-- | The outcome, if the action has finished.
poll :: forall a. Async a -> IO (Maybe (Either Error a))
poll (Async outcome) = tryReadMVar outcome

-- | Runs both at the same time and returns both results. If either throws, this throws the
-- | first exception as soon as it happens.
concurrently :: forall a b. IO a -> IO b -> IO (a /\ b)
concurrently left right = do
  finished <- newChan
  leftOutcome <- reporting finished left
  rightOutcome <- reporting finished right
  awaitAll 2 finished
  (/\) <$> outcomeOf leftOutcome <*> outcomeOf rightOutcome

concurrently_ :: forall a b. IO a -> IO b -> IO Unit
concurrently_ left right = void (concurrently left right)

-- | Runs both at the same time and returns the result of the first to finish. If that one threw,
-- | this throws the same.
race :: forall a b. IO a -> IO b -> IO (Either a b)
race left right = do
  first <- newChan
  _ <- forkFinally (Left <$> left) (writeChan first)
  _ <- forkFinally (Right <$> right) (writeChan first)
  readChan first >>= either throwIO pure

race_ :: forall a b. IO a -> IO b -> IO Unit
race_ left right = void (race left right)

-- | Runs the action for every element at the same time and returns the results in order. If any
-- | throws, this throws the first exception as soon as it happens.
mapConcurrently :: forall t a b. Traversable t => (a -> IO b) -> t a -> IO (t b)
mapConcurrently f elements = do
  finished <- newChan
  outcomes <- traverse (reporting finished <<< f) elements
  awaitAll (length elements) finished
  traverse outcomeOf outcomes

mapConcurrently_ :: forall f a b. Foldable f => (a -> IO b) -> f a -> IO Unit
mapConcurrently_ f elements = do
  finished <- newChan
  traverse_ (void <<< reporting finished <<< f) elements
  awaitAll (length elements) finished

forConcurrently :: forall t a b. Traversable t => t a -> (a -> IO b) -> IO (t b)
forConcurrently = flip mapConcurrently

forConcurrently_ :: forall f a b. Foldable f => f a -> (a -> IO b) -> IO Unit
forConcurrently_ = flip mapConcurrently_

-- | Runs the action that many times at the same time.
replicateConcurrently :: forall a. Int -> IO a -> IO (Array a)
replicateConcurrently count action = mapConcurrently (const action) (Array.replicate count unit)

replicateConcurrently_ :: forall a. Int -> IO a -> IO Unit
replicateConcurrently_ count action = mapConcurrently_ (const action) (Array.replicate count unit)

-- | Starts the action, keeps its outcome, and reports on `finished` whether it threw.
reporting :: forall a. Chan (Maybe Error) -> IO a -> IO (MVar (Either Error a))
reporting finished action = do
  outcome <- newEmptyMVar
  _ <- forkFinally action \result -> do
    putMVar outcome result
    writeChan finished (blush result)
  pure outcome

-- | Waits until that many threads reported success, or throws the first failure reported.
awaitAll :: Int -> Chan (Maybe Error) -> IO Unit
awaitAll count finished = tailRecM next count
  where
  next remaining
    | remaining <= 0 = pure (Done unit)
    | otherwise = readChan finished >>= case _ of
        Just error -> throwIO error
        Nothing -> pure (Loop (remaining - 1))

outcomeOf :: forall a. MVar (Either Error a) -> IO a
outcomeOf outcome = readMVar outcome >>= either throwIO pure

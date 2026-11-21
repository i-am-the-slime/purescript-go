-- | Haskell's `Control.Concurrent.Async`: run `IO` actions at the same time and wait for their
-- | results.
-- |
-- | One difference: Go can't stop a goroutine from outside, so nothing here cancels a thread.
-- | When `race` has a winner, or `concurrently` a failure, the other threads keep running until
-- | they finish on their own; their results are dropped.
-- |
-- | The work of `f x` happens on the thread. `mapConcurrently (\n -> pure (sum (1 .. n))) xs`
-- | works out every sum at the same time, though PureScript is strict and `pure` gets its
-- | argument computed: `mapConcurrently`, `forConcurrently` and their `_` versions apply `f` to
-- | each element on that element's thread, not while they build the actions. `concurrently`,
-- | `race` and `replicateConcurrently` take actions their caller has already built, so
-- | `concurrently (pure (sum xs)) (pure (sum ys))` adds up both before any thread starts. For pure
-- | work, hand the inputs to `mapConcurrently` or `forConcurrently` instead.
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

import Control.Alt ((<|>))
import Control.Parallel (parTraverse, parTraverse_, parallel, sequential)
import Data.Array as Array
import Data.Either (Either(..), either)
import Data.Foldable (class Foldable)
import Data.Maybe (Maybe)
import Data.Traversable (class Traversable)
import Data.Tuple.Nested (type (/\), (/\))
import Effect.Exception (Error)
import Go.IO (IO, forkFinally, throwIO)
import Go.IO.Internal (deferIO)
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
concurrently left right = sequential ((/\) <$> parallel left <*> parallel right)

concurrently_ :: forall a b. IO a -> IO b -> IO Unit
concurrently_ left right = void (concurrently left right)

-- | Runs both at the same time and returns the result of the first to finish. If that one threw,
-- | this throws the same.
race :: forall a b. IO a -> IO b -> IO (Either a b)
race left right = sequential (parallel (Left <$> left) <|> parallel (Right <$> right))

race_ :: forall a b. IO a -> IO b -> IO Unit
race_ left right = void (race left right)

-- | Runs the action for every element at the same time and returns the results in order. If any
-- | throws, this throws the first exception as soon as it happens.
mapConcurrently :: forall t a b. Traversable t => (a -> IO b) -> t a -> IO (t b)
mapConcurrently f = parTraverse (onItsThread f)

mapConcurrently_ :: forall f a b. Foldable f => (a -> IO b) -> f a -> IO Unit
mapConcurrently_ f = parTraverse_ (onItsThread f)

forConcurrently :: forall t a b. Traversable t => t a -> (a -> IO b) -> IO (t b)
forConcurrently = flip mapConcurrently

forConcurrently_ :: forall f a b. Foldable f => f a -> (a -> IO b) -> IO Unit
forConcurrently_ = flip mapConcurrently_

-- | `f x` as an action that applies `f` once it runs, on its thread, rather than while the
-- | actions are being built.
onItsThread :: forall a b. (a -> IO b) -> a -> IO b
onItsThread f x = deferIO \_ -> f x

-- | Runs the action that many times at the same time.
replicateConcurrently :: forall a. Int -> IO a -> IO (Array a)
replicateConcurrently count action = mapConcurrently (const action) (Array.replicate count unit)

replicateConcurrently_ :: forall a. Int -> IO a -> IO Unit
replicateConcurrently_ count action = mapConcurrently_ (const action) (Array.replicate count unit)

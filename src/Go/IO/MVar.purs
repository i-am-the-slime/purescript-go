-- | Haskell's `Control.Concurrent.MVar`: a box that is empty or holds one value. Taking from an
-- | empty box waits until a thread puts one in; putting into a full box waits until one is taken.
module Go.IO.MVar
  ( MVar
  , newEmptyMVar
  , newMVar
  , takeMVar
  , putMVar
  , readMVar
  , tryTakeMVar
  , tryPutMVar
  , tryReadMVar
  , isEmptyMVar
  , swapMVar
  , withMVar
  , modifyMVar_
  , modifyMVar
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Tuple.Nested (type (/\), (/\))
import Effect (Effect)
import Go.IO (onException)
import Go.IO.Internal (IO(..))

foreign import data MVar :: Type -> Type

newEmptyMVar :: forall a. IO (MVar a)
newEmptyMVar = IO newEmptyMVarImpl

newMVar :: forall a. a -> IO (MVar a)
newMVar value = do
  box <- newEmptyMVar
  putMVar box value
  pure box

-- | Takes the value out, waiting while the box is empty.
takeMVar :: forall a. MVar a -> IO a
takeMVar box = IO (takeMVarImpl box)

-- | Puts the value in, waiting while the box is full.
putMVar :: forall a. MVar a -> a -> IO Unit
putMVar box value = IO (putMVarImpl box value)

-- | The value, without taking it out, waiting while the box is empty. Atomic: no other thread can
-- | take in between.
readMVar :: forall a. MVar a -> IO a
readMVar box = IO (readMVarImpl box)

tryTakeMVar :: forall a. MVar a -> IO (Maybe a)
tryTakeMVar box = IO (tryTakeMVarImpl Nothing Just box)

-- | Puts the value in if the box is empty, and says whether it did.
tryPutMVar :: forall a. MVar a -> a -> IO Boolean
tryPutMVar box value = IO (tryPutMVarImpl box value)

tryReadMVar :: forall a. MVar a -> IO (Maybe a)
tryReadMVar box = IO (tryReadMVarImpl Nothing Just box)

isEmptyMVar :: forall a. MVar a -> IO Boolean
isEmptyMVar box = IO (isEmptyMVarImpl box)

-- | Replaces the value and returns the old one.
swapMVar :: forall a. MVar a -> a -> IO a
swapMVar box value = modifyMVar box \old -> pure (value /\ old)

-- | Runs the action with the value, which stays taken meanwhile, so the box works as a lock.
withMVar :: forall a b. MVar a -> (a -> IO b) -> IO b
withMVar box f = modifyMVar box \value -> (value /\ _) <$> f value

-- | Replaces the value by what the function makes of it. If the function throws, the old value
-- | goes back in.
modifyMVar_ :: forall a. MVar a -> (a -> IO a) -> IO Unit
modifyMVar_ box f = modifyMVar box \value -> (_ /\ unit) <$> f value

modifyMVar :: forall a b. MVar a -> (a -> IO (a /\ b)) -> IO b
modifyMVar box f = do
  value <- takeMVar box
  updated /\ result <- f value `onException` putMVar box value
  putMVar box updated
  pure result

foreign import newEmptyMVarImpl :: forall a. Effect (MVar a)
foreign import takeMVarImpl :: forall a. MVar a -> Effect a
foreign import putMVarImpl :: forall a. MVar a -> a -> Effect Unit
foreign import readMVarImpl :: forall a. MVar a -> Effect a
foreign import tryTakeMVarImpl :: forall a r. r -> (a -> r) -> MVar a -> Effect r
foreign import tryPutMVarImpl :: forall a. MVar a -> a -> Effect Boolean
foreign import tryReadMVarImpl :: forall a r. r -> (a -> r) -> MVar a -> Effect r
foreign import isEmptyMVarImpl :: forall a. MVar a -> Effect Boolean

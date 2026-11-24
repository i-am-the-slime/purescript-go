-- | Haskell's `Data.IORef`: a mutable cell that `IO` threads share.
module Go.IO.IORef
  ( IORef
  , newIORef
  , readIORef
  , writeIORef
  , modifyIORef
  , modifyIORef'
  , atomicModifyIORef
  , atomicModifyIORef'
  , atomicWriteIORef
  ) where

import Prelude

import Data.Tuple (fst, snd)
import Data.Tuple.Nested (type (/\))
import Effect (Effect)
import Go.IO.Internal (IO(..))

foreign import data IORef :: Type -> Type

newIORef :: forall a. a -> IO (IORef a)
newIORef value = IO (newIORefImpl value)

readIORef :: forall a. IORef a -> IO a
readIORef ref = IO (readIORefImpl ref)

writeIORef :: forall a. IORef a -> a -> IO Unit
writeIORef ref value = IO (writeIORefImpl ref value)

-- | Reads, applies and writes. Not atomic: another thread can write in between. PureScript
-- | evaluates eagerly, so this is `modifyIORef'`.
modifyIORef :: forall a. IORef a -> (a -> a) -> IO Unit
modifyIORef = modifyIORef'

modifyIORef' :: forall a. IORef a -> (a -> a) -> IO Unit
modifyIORef' ref f = readIORef ref >>= writeIORef ref <<< f

-- | Replaces the value by the first of the function's results and returns the second, atomically:
-- | if another thread writes in between, it applies the function again to the new value. The
-- | function should be cheap and do nothing else.
atomicModifyIORef' :: forall a b. IORef a -> (a -> a /\ b) -> IO b
atomicModifyIORef' ref f = IO (atomicModifyIORefImpl fst snd f ref)

-- | PureScript evaluates eagerly, so this is `atomicModifyIORef'`.
atomicModifyIORef :: forall a b. IORef a -> (a -> a /\ b) -> IO b
atomicModifyIORef = atomicModifyIORef'

-- | Writes the value so that every thread sees it at once.
atomicWriteIORef :: forall a. IORef a -> a -> IO Unit
atomicWriteIORef = writeIORef

foreign import newIORefImpl :: forall a. a -> Effect (IORef a)
foreign import readIORefImpl :: forall a. IORef a -> Effect a
foreign import writeIORefImpl :: forall a. IORef a -> a -> Effect Unit
foreign import atomicModifyIORefImpl
  :: forall a b t. (t -> a) -> (t -> b) -> (a -> t) -> IORef a -> Effect b

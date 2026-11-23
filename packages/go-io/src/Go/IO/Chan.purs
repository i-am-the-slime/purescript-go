-- | Haskell's `Control.Concurrent.Chan`: an unbounded queue between `IO` threads. Writing never
-- | waits; reading waits until there is something to read.
module Go.IO.Chan
  ( Chan
  , newChan
  , writeChan
  , readChan
  , writeList2Chan
  ) where

import Prelude

import Data.Foldable (traverse_)
import Effect (Effect)
import Go.IO.Internal (IO(..))

foreign import data Chan :: Type -> Type

newChan :: forall a. IO (Chan a)
newChan = IO newChanImpl

writeChan :: forall a. Chan a -> a -> IO Unit
writeChan channel value = IO (writeChanImpl channel value)

-- | The oldest value written, waiting until there is one.
readChan :: forall a. Chan a -> IO a
readChan channel = IO (readChanImpl channel)

-- | Writes the values in order.
writeList2Chan :: forall a. Chan a -> Array a -> IO Unit
writeList2Chan channel = traverse_ (writeChan channel)

foreign import newChanImpl :: forall a. Effect (Chan a)
foreign import writeChanImpl :: forall a. Chan a -> a -> Effect Unit
foreign import readChanImpl :: forall a. Chan a -> Effect a

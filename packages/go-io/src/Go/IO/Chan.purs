-- | Go's channels, typed: a `Chan Int` is a `chan int32` in Go. Without room, a send waits until
-- | another thread receives it; with room for some, a send waits only while it's full. To wait on
-- | several channels at once, or on a channel and a `Context`, use `Go.IO.Select`.
module Go.IO.Chan
  ( Chan
  , ReceiveChan
  , class Receivable
  , receiveEnd
  , Polled(..)
  , newChan
  , newBufferedChan
  , send
  , sendAll
  , receive
  , close
  , trySend
  , tryReceive
  , capacity
  , length
  ) where

import Prelude

import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Go.IO.Internal (IO(..))

-- | Go's `chan A`.
foreign import data Chan :: Type -> Type

-- | Go's `<-chan A`: a channel to receive from only, such as `Go.IO.Context.done`.
foreign import data ReceiveChan :: Type -> Type

-- | What can be received from: a `Chan` and a `ReceiveChan`.
class Receivable :: (Type -> Type) -> Constraint
class Receivable channel where
  receiveEnd :: forall a. channel a -> ReceiveChan a

instance Receivable Chan where
  receiveEnd channel = receiveEndImpl channel

instance Receivable ReceiveChan where
  receiveEnd channel = channel

foreign import receiveEndImpl :: forall a. Chan a -> ReceiveChan a

-- | What `tryReceive` found.
data Polled a
  = Received a
  -- | Nothing to receive right now.
  | Empty
  -- | Closed, and every value sent before taken.
  | Closed

derive instance Eq a => Eq (Polled a)

instance Show a => Show (Polled a) where
  show = case _ of
    Received value -> "(Received " <> show value <> ")"
    Empty -> "Empty"
    Closed -> "Closed"

-- | A channel without room: each send waits until a thread receives it.
newChan :: forall a. IO (Chan a)
newChan = IO newChanImpl

foreign import newChanImpl :: forall a. Effect (Chan a)

-- | A channel with room for `room` values nobody has received yet.
newBufferedChan :: forall a. Int -> IO (Chan a)
newBufferedChan room = IO (newBufferedChanImpl room)

foreign import newBufferedChanImpl :: forall a. Int -> Effect (Chan a)

-- | Sends the value, waiting while there's no room. Throws if the channel is closed.
send :: forall a. Chan a -> a -> IO Unit
send channel value = IO (sendImpl channel value)

foreign import sendImpl :: forall a. Chan a -> a -> Effect Unit

-- | Sends the values in order.
sendAll :: forall a. Chan a -> Array a -> IO Unit
sendAll channel = traverse_ (send channel)

-- | The next value, waiting until there is one. `Nothing` once the channel is closed and every
-- | value sent before is taken.
receive :: forall channel a. Receivable channel => channel a -> IO (Maybe a)
receive channel = IO (receiveImpl Nothing Just (receiveEnd channel))

foreign import receiveImpl :: forall a r. r -> (a -> r) -> ReceiveChan a -> Effect r

-- | No more sends: receivers get what is left, then `Nothing`. Throws if it's closed already.
close :: forall a. Chan a -> IO Unit
close channel = IO (closeImpl channel)

foreign import closeImpl :: forall a. Chan a -> Effect Unit

-- | Sends the value if a receiver is waiting or there's room, and says whether it did.
trySend :: forall a. Chan a -> a -> IO Boolean
trySend channel value = IO (trySendImpl channel value)

foreign import trySendImpl :: forall a. Chan a -> a -> Effect Boolean

-- | Receives a value if one is ready, without waiting.
tryReceive :: forall channel a. Receivable channel => channel a -> IO (Polled a)
tryReceive channel = IO (tryReceiveImpl Empty Closed Received (receiveEnd channel))

foreign import tryReceiveImpl :: forall a r. r -> r -> (a -> r) -> ReceiveChan a -> Effect r

-- | How many values fit in without a receiver: 0 for `newChan`.
capacity :: forall channel a. Receivable channel => channel a -> Int
capacity channel = capacityImpl (receiveEnd channel)

foreign import capacityImpl :: forall a. ReceiveChan a -> Int

-- | How many values were sent and are not yet received.
length :: forall channel a. Receivable channel => channel a -> IO Int
length channel = IO (lengthImpl (receiveEnd channel))

foreign import lengthImpl :: forall a. ReceiveChan a -> Effect Int

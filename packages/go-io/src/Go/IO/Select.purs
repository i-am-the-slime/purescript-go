-- | Go's `select`: waits on several channel operations at once, does whichever can go first and
-- | runs its handler. If several can, it picks one at random.
-- |
-- | ```purescript
-- | received <- select2
-- |   (onReceive jobs \job -> pure job)
-- |   (onDone context (pure Nothing))
-- | ```
-- |
-- | `select2` and `select3` are Go `select` statements over that many cases, typed, without
-- | reflection; `trySelect1` and `trySelect2` add a `default`, which runs when no case can go
-- | right away.
module Go.IO.Select
  ( Case
  , onReceive
  , onSend
  , onDone
  , select2
  , select3
  , trySelect1
  , trySelect2
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Newtype (un)
import Effect (Effect)
import Effect.Uncurried (EffectFn2, mkEffectFn2)
import Go.IO.Chan (class Receivable, Chan, ReceiveChan, receiveEnd)
import Go.IO.Context (Context, done)
import Go.IO.Internal (IO(..))

-- | A channel operation that a select may do, with a value of type `a`, and what to do once it's
-- | done.
foreign import data Case :: Type -> Type -> Type

-- | Receives from the channel, and hands the handler the value, or `Nothing` if the channel is
-- | closed.
onReceive :: forall channel a r. Receivable channel => channel a -> (Maybe a -> IO r) -> Case a r
onReceive channel handler = onReceiveImpl (receiveEnd channel) (mkEffectFn2 receivedOrClosed)
  where
  receivedOrClosed value open = un IO (handler (if open then Just value else Nothing))

foreign import onReceiveImpl :: forall a r. ReceiveChan a -> EffectFn2 a Boolean r -> Case a r

-- | Sends the value, then runs the handler.
onSend :: forall a r. Chan a -> a -> IO r -> Case a r
onSend channel value handler = onSendImpl channel value (un IO handler)

foreign import onSendImpl :: forall a r. Chan a -> a -> Effect r -> Case a r

-- | Runs the handler once the context is done.
onDone :: forall r. Context -> IO r -> Case Unit r
onDone context handler = onReceive (done context) \_ -> handler

select2 :: forall a b r. Case a r -> Case b r -> IO r
select2 first second = IO (select2Impl first second)

foreign import select2Impl :: forall a b r. Case a r -> Case b r -> Effect r

select3 :: forall a b c r. Case a r -> Case b r -> Case c r -> IO r
select3 first second third = IO (select3Impl first second third)

foreign import select3Impl :: forall a b c r. Case a r -> Case b r -> Case c r -> Effect r

-- | Does the case if it can go right away, and runs `otherwise` if not.
trySelect1 :: forall a r. Case a r -> IO r -> IO r
trySelect1 first otherwise = IO (trySelect1Impl first (un IO otherwise))

foreign import trySelect1Impl :: forall a r. Case a r -> Effect r -> Effect r

trySelect2 :: forall a b r. Case a r -> Case b r -> IO r -> IO r
trySelect2 first second otherwise = IO (trySelect2Impl first second (un IO otherwise))

foreign import trySelect2Impl :: forall a b r. Case a r -> Case b r -> Effect r -> Effect r

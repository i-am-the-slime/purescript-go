-- | Go's `context.Context`: how a thread learns that it should stop waiting, because whoever it
-- | works for is done, a deadline passed or a client hung up. Every wait in `Go.IO.Select`, and
-- | `threadDelayWith` and the `…With` waits of `Go.IO.MVar`, stop once their context is cancelled.
module Go.IO.Context
  ( Context
  , CancelContext
  , Cancellation(..)
  , background
  , withCancel
  , withTimeout
  , withDeadline
  , cancel
  , done
  , err
  , isCancelled
  ) where

import Prelude

import Data.DateTime.Instant (Instant, unInstant)
import Data.Maybe (Maybe(..))
import Data.Newtype (un)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested (type (/\), (/\))
import Effect (Effect)
import Go.IO.Chan (ReceiveChan)
import Go.IO.Internal (IO(..))

-- | Go's `context.Context`.
foreign import data Context :: Type

-- | Go's `context.CancelFunc`.
foreign import data CancelContext :: Type

-- | Why a context is done: Go's `context.Canceled` and `context.DeadlineExceeded`.
data Cancellation
  = Cancelled
  | DeadlineExceeded

derive instance Eq Cancellation

instance Show Cancellation where
  show = case _ of
    Cancelled -> "Cancelled"
    DeadlineExceeded -> "DeadlineExceeded"

-- | The context that is never done.
foreign import background :: Context

-- | A context that is done once `cancel` is called on it, or once its parent is.
withCancel :: Context -> IO (Context /\ CancelContext)
withCancel parent = IO (withCancelImpl (/\) parent)

foreign import withCancelImpl :: (Context -> CancelContext -> Context /\ CancelContext) -> Context -> Effect (Context /\ CancelContext)

-- | `withCancel`, and done by itself once the duration has passed.
withTimeout :: Milliseconds -> Context -> IO (Context /\ CancelContext)
withTimeout (Milliseconds duration) parent = IO (withTimeoutImpl (/\) duration parent)

foreign import withTimeoutImpl :: (Context -> CancelContext -> Context /\ CancelContext) -> Number -> Context -> Effect (Context /\ CancelContext)

-- | `withCancel`, and done by itself at the instant.
withDeadline :: Instant -> Context -> IO (Context /\ CancelContext)
withDeadline deadline parent = IO (withDeadlineImpl (/\) millisecondsSinceEpoch parent)
  where
  millisecondsSinceEpoch = un Milliseconds (unInstant deadline)

foreign import withDeadlineImpl :: (Context -> CancelContext -> Context /\ CancelContext) -> Number -> Context -> Effect (Context /\ CancelContext)

-- | Cancels the context and its children. Cancelling again does nothing.
cancel :: CancelContext -> IO Unit
cancel cancelling = IO (cancelImpl cancelling)

foreign import cancelImpl :: CancelContext -> Effect Unit

-- | Closed once the context is done, so receiving from it waits until then. `background`'s never
-- | closes.
done :: Context -> ReceiveChan Unit
done context = doneImpl context

foreign import doneImpl :: Context -> ReceiveChan Unit

-- | Why the context is done, or `Nothing` while it isn't.
err :: Context -> IO (Maybe Cancellation)
err context = IO (errImpl Nothing (Just Cancelled) (Just DeadlineExceeded) context)

foreign import errImpl :: forall r. r -> r -> r -> Context -> Effect r

isCancelled :: Context -> IO Boolean
isCancelled context = IO (isCancelledImpl context)

foreign import isCancelledImpl :: Context -> Effect Boolean

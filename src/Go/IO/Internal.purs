-- | The representation of `Go.IO`'s `IO`, for the modules that build `IO` actions out of Go
-- | foreign functions. Wrapping an arbitrary `Effect` this way runs it off the event loop, which
-- | is only safe for code that touches no Aff, `Ref` or console state; programs use `Go.IO`.
module Go.IO.Internal
  ( IO(..)
  , Boxed(..)
  , unbox
  , runEffect
  ) where

import Prelude

import Control.Monad.Error.Class (class MonadError, class MonadThrow)
import Control.Monad.Rec.Class (class MonadRec)
import Effect (Effect)
import Effect.Class (class MonadEffect)
import Effect.Exception (Error, throwException)

-- | A value on its way through a generic Go function. Go has no type for nothing, so a `Unit`
-- | can't be the type argument of one; a `Boxed Unit` can.
data Boxed a = Boxed a

unbox :: forall a. Boxed a -> a
unbox (Boxed value) = value

-- | An action that runs on a goroutine of its own, off the event loop, in parallel with other
-- | `IO` threads.
newtype IO a = IO (Effect a)

derive newtype instance Functor IO
derive newtype instance Apply IO
derive newtype instance Applicative IO
derive newtype instance Bind IO
derive newtype instance Monad IO
derive newtype instance MonadRec IO

-- | `liftEffect` is `runEffect`, so `log` and `Ref`s work inside `IO` as they do in `Aff`.
instance MonadEffect IO where
  liftEffect = runEffect

-- | Runs the `Effect` on the program's main event loop, where `Ref`s, `log` and `Aff` live, and
-- | waits for it. Keep it short: while it runs, no fiber does. An exception it throws is thrown in
-- | the `IO` action.
runEffect :: forall a. Effect a -> IO a
runEffect action = IO (unbox <$> runEffectImpl (Boxed <$> action))

instance MonadThrow Error IO where
  throwError error = IO (throwException error)

-- | Catches anything the action throws: a PureScript `Error`, or a panic in Go foreign code, which
-- | arrives as an `Error` with the panic's message.
instance MonadError Error IO where
  catchError (IO action) handler = IO (catchImpl (effect <<< handler) action)
    where
    effect (IO recovered) = recovered

foreign import runEffectImpl :: forall a. Effect a -> Effect a

foreign import catchImpl :: forall a. (Error -> Effect a) -> Effect a -> Effect a

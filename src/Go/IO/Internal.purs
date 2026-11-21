-- | The representation of `Go.IO`'s `IO`, for the modules that build `IO` actions out of Go
-- | foreign functions. Wrapping an arbitrary `Effect` this way runs it off the event loop, which
-- | is only safe for code that touches no Aff, `Ref` or console state; programs use `Go.IO`.
module Go.IO.Internal
  ( IO(..)
  , ParIO(..)
  , Boxed(..)
  , unbox
  , runEffect
  ) where

import Prelude

import Control.Alt (class Alt)
import Control.Alternative (class Alternative)
import Control.Monad.Error.Class (class MonadError, class MonadThrow)
import Control.Parallel.Class (class Parallel)
import Control.Plus (class Plus)
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

-- | `liftEffect` is `runEffect`, so `log` and `Ref`s work inside `IO` as they do in `Aff`. Each
-- | `liftEffect` runs on the program's event loop and costs about 80 ns, so hot loops keep their
-- | state in an `IORef` instead.
instance MonadEffect IO where
  liftEffect = runEffect

-- | Runs the `Effect` on the program's main event loop, where `Ref`s, `log` and `Aff` live, and
-- | waits for it. Keep it short: while it runs, no fiber does. An exception it throws is thrown in
-- | the `IO` action.
-- |
-- | Each call, and so each `liftEffect`, is a trip to the event loop and back, about 80 ns. That's
-- | nothing next to a `log`, but a lot inside a hot loop: keep state a loop updates in an `IORef`,
-- | which an `IO` thread changes without leaving its goroutine.
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

-- | `IO` whose `<*>` runs both sides at the same time, as `ParAff` is for `Aff`. With it,
-- | `parTraverse`, `parSequence_`, `parOneOf` and the rest of `Control.Parallel` work on `IO`.
newtype ParIO a = ParIO (IO a)

instance Functor ParIO where
  map f (ParIO action) = ParIO (map f action)

-- | Runs both sides on threads of their own and waits for both. If one throws, so does the
-- | whole, as soon as it happens. Go can't stop the other thread: it runs to its end and its
-- | result is dropped.
instance Apply ParIO where
  apply (ParIO (IO functions)) (ParIO (IO values)) =
    ParIO (IO (unbox <$> bothImpl applyBoxed (Boxed <$> functions) (Boxed <$> values)))
    where
    applyBoxed (Boxed f) (Boxed value) = Boxed (f value)

instance Applicative ParIO where
  pure value = ParIO (pure value)

-- | Runs both sides on threads of their own and returns the first to finish. If that one threw,
-- | this throws the same. The other keeps running, and its result is dropped.
instance Alt ParIO where
  alt (ParIO (IO left)) (ParIO (IO right)) =
    ParIO (IO (unbox <$> firstImpl (Boxed <$> left) (Boxed <$> right)))

-- | `empty` never finishes, so it never wins a race.
instance Plus ParIO where
  empty = ParIO (IO (unbox <$> neverImpl))

instance Alternative ParIO

instance Parallel ParIO IO where
  parallel = ParIO
  sequential (ParIO action) = action

foreign import bothImpl :: forall a b c. (a -> b -> c) -> Effect a -> Effect b -> Effect c
foreign import firstImpl :: forall a. Effect a -> Effect a -> Effect a
foreign import neverImpl :: forall a. Effect a

foreign import runEffectImpl :: forall a. Effect a -> Effect a

foreign import catchImpl :: forall a. (Error -> Effect a) -> Effect a -> Effect a

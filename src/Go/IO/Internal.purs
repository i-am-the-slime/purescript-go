-- | The representation of `Go.IO`'s `IO`, for the modules that build `IO` actions out of Go
-- | foreign functions. Wrapping an arbitrary `Effect` this way runs it off the event loop, which
-- | is only safe for code that touches no Aff, `Ref` or console state; programs use `Go.IO`.
-- |
-- | `IO` is also the type of a callback that Go calls on a goroutine of its own, such as an HTTP
-- | handler: it gets at the event loop with `liftEffect`. A callback typed `Effect` is only ever
-- | called right away, on the goroutine that called the foreign.
module Go.IO.Internal
  ( IO(..)
  , ParIO(..)
  , Boxed(..)
  , unbox
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

-- | `liftEffect` waits for the program's event loop, where `Ref`s, `log` and `Aff` live, runs the
-- | `Effect` there and comes back with its result. So `log` and `Ref`s work inside `IO` as they do
-- | in `Aff`. Keep it short: while it runs, no fiber does. An exception it throws is thrown in the
-- | `IO` action.
-- |
-- | Each `liftEffect` is a trip to the event loop and back, about 80 ns. That's nothing next to a
-- | `log`, but a lot inside a hot loop: keep state a loop updates in an `IORef`, which an `IO`
-- | thread changes without leaving its goroutine.
instance MonadEffect IO where
  liftEffect action = IO (unbox <$> liftEffectImpl (Boxed <$> action))

foreign import liftEffectImpl :: forall a. Effect a -> Effect a

instance MonadThrow Error IO where
  throwError error = IO (throwException error)

-- | Catches anything the action throws: a PureScript `Error`, or a panic in Go foreign code, which
-- | arrives as an `Error` with the panic's message.
instance MonadError Error IO where
  catchError action handler = IO (unbox <$> catchImpl (map Boxed <<< handler) (Boxed <$> action))

foreign import catchImpl :: forall a. (Error -> IO a) -> IO a -> Effect a

-- | `IO` whose `<*>` runs both sides at the same time, as `ParAff` is for `Aff`. With it,
-- | `parTraverse`, `parSequence_`, `parOneOf` and the rest of `Control.Parallel` work on `IO`.
-- | `parTraverse f` applies `f` to every element before it starts a thread, so the pure work of
-- | `f x` happens up front, one element after another; `Go.IO.Async.mapConcurrently` does it on
-- | the threads.
newtype ParIO a = ParIO (IO a)

instance Functor ParIO where
  map f (ParIO action) = ParIO (map f action)

-- | Runs both sides on threads of their own and waits for both. If one throws, so does the
-- | whole, as soon as it happens. Go can't stop the other thread: it runs to its end and its
-- | result is dropped.
instance Apply ParIO where
  apply (ParIO functions) (ParIO values) =
    ParIO (IO (unbox <$> bothImpl applyBoxed (Boxed <$> functions) (Boxed <$> values)))
    where
    applyBoxed (Boxed f) (Boxed value) = Boxed (f value)

foreign import bothImpl :: forall a b c. (a -> b -> c) -> IO a -> IO b -> Effect c

instance Applicative ParIO where
  pure value = ParIO (pure value)

-- | Runs both sides on threads of their own and returns the first to finish. If that one threw,
-- | this throws the same. The other keeps running, and its result is dropped.
instance Alt ParIO where
  alt (ParIO left) (ParIO right) =
    ParIO (IO (unbox <$> firstImpl (Boxed <$> left) (Boxed <$> right)))

foreign import firstImpl :: forall a. IO a -> IO a -> Effect a

-- | `empty` never finishes, so it never wins a race.
instance Plus ParIO where
  empty = ParIO (IO (unbox <$> neverImpl))

foreign import neverImpl :: forall a. Effect a

instance Alternative ParIO

instance Parallel ParIO IO where
  parallel = ParIO
  sequential (ParIO action) = action

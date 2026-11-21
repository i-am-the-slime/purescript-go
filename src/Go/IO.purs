-- | Haskell's `IO` for Go: actions that run on goroutines, off the event loop, truly in
-- | parallel. `toAff` runs one from `Aff`, `launchIO` starts one from `Effect`, and `liftEffect`
-- | runs an `Effect` from inside one.
module Go.IO
  ( module Go.IO.Internal
  , ThreadId
  , forkIO
  , forkFinally
  , threadDelay
  , yield
  , getNumCapabilities
  , toAff
  , launchIO
  , launchIO_
  , throwIO
  , catch
  , try
  , evaluate
  , bracket
  , bracket_
  , finally
  , onException
  ) where

import Prelude

import Control.Monad.Error.Class (catchError, throwError)
import Data.Either (Either(..), either)
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Effect.Exception (Error, throwException)
import Go.IO.Internal (Boxed(..), IO, ParIO, unbox)
import Go.IO.Internal as Internal

-- | A thread `forkIO` started.
newtype ThreadId = ThreadId Int

derive instance Eq ThreadId
derive instance Ord ThreadId

instance Show ThreadId where
  show (ThreadId id) = "ThreadId " <> show id

-- | Runs the action on a new thread. An exception the action doesn't catch is reported on
-- | standard error, as GHC does, and ends only that thread. The program doesn't wait for its
-- | threads: wait for them yourself, with an `MVar` or `Go.IO.Async`.
forkIO :: IO Unit -> IO ThreadId
forkIO action = Internal.IO (ThreadId <$> forkIOImpl action)

foreign import forkIOImpl :: IO Unit -> Effect Int

-- | Runs the action on a new thread and hands its outcome to the finalizer, on that thread.
forkFinally :: forall a. IO a -> (Either Error a -> IO Unit) -> IO ThreadId
forkFinally action finalizer = forkIO (try action >>= finalizer)

-- | Waits at least the duration. Haskell's `threadDelay` counts microseconds; this one counts
-- | `Milliseconds`.
threadDelay :: Milliseconds -> IO Unit
threadDelay (Milliseconds duration) = Internal.IO (threadDelayImpl duration)

foreign import threadDelayImpl :: Number -> Effect Unit

-- | Lets other threads run, like `runtime.Gosched`.
yield :: IO Unit
yield = Internal.IO yieldImpl

foreign import yieldImpl :: Effect Unit

-- | How many threads can run at the same time: Go's `GOMAXPROCS`, the number of CPU cores by
-- | default.
getNumCapabilities :: IO Int
getNumCapabilities = Internal.IO numCapabilitiesImpl

foreign import numCapabilitiesImpl :: Effect Int

-- | Runs the action on a thread of its own and resumes the fiber with its result. Other fibers,
-- | and the handlers of a server in the same program, run meanwhile. An exception the action
-- | throws becomes the fiber's error.
toAff :: forall a. IO a -> Aff a
toAff action = makeAff \resolve -> toAffImpl (Boxed <$> action) (resuming resolve <<< Right <<< unbox) (resuming resolve <<< Left) $> nonCanceler
  where
  resuming resolve outcome = Internal.IO (resolve outcome)

-- | Starts the action on a thread of its own and returns right away, as `launchAff` does. The
-- | callback gets its outcome on the event loop once it's done, and until then the program keeps
-- | running.
launchIO :: forall a. IO a -> (Either Error a -> Effect Unit) -> Effect Unit
launchIO action handle = toAffImpl (Boxed <$> action) (handling <<< Right <<< unbox) (handling <<< Left)
  where
  handling outcome = handle outcome # liftEffect

foreign import toAffImpl :: forall a. IO a -> (a -> IO Unit) -> (Error -> IO Unit) -> Effect Unit

-- | Starts the action on a thread of its own and returns right away, as `launchAff_` does. An
-- | exception the action doesn't catch is rethrown on the event loop and ends the program.
launchIO_ :: IO Unit -> Effect Unit
launchIO_ action = launchIO action (either throwException pure)

throwIO :: forall a. Error -> IO a
throwIO = throwError

-- | Catches what the action throws, including a panic in Go foreign code.
catch :: forall a. IO a -> (Error -> IO a) -> IO a
catch = catchError

try :: forall a. IO a -> IO (Either Error a)
try action = catch (Right <$> action) (pure <<< Left)

-- | The value, as an action. PureScript evaluates eagerly, so this is `pure`.
evaluate :: forall a. a -> IO a
evaluate = pure

-- | Acquires, uses, and releases even when the use throws.
bracket :: forall a b c. IO a -> (a -> IO b) -> (a -> IO c) -> IO c
bracket acquire release use = do
  resource <- acquire
  use resource `finally` release resource

bracket_ :: forall a b c. IO a -> IO b -> IO c -> IO c
bracket_ acquire release use = bracket acquire (const release) (const use)

-- | Runs the finalizer after the action, whether it succeeds or throws.
finally :: forall a b. IO a -> IO b -> IO a
finally action finalizer = do
  result <- action `onException` finalizer
  _ <- finalizer
  pure result

-- | Runs the handler when the action throws, and rethrows.
onException :: forall a b. IO a -> IO b -> IO a
onException action handler = catch action \error -> handler *> throwIO error

-- | `Effect.Console` for `IO`: prints right from the thread, without a trip to the event loop.
-- | Iris's console locks its state, so threads printing at the same time each print whole lines.
-- | `Effect.Class.Console` works in `IO` too, through `liftEffect`, and waits for the event loop.
module Go.IO.Console
  ( log
  , logShow
  , warn
  , warnShow
  , error
  , errorShow
  , info
  , infoShow
  , debug
  , debugShow
  ) where

import Prelude

import Effect.Console as Console
import Go.IO.Internal (IO(..))

log :: String -> IO Unit
log message = IO (Console.log message)

logShow :: forall a. Show a => a -> IO Unit
logShow value = log (show value)

warn :: String -> IO Unit
warn message = IO (Console.warn message)

warnShow :: forall a. Show a => a -> IO Unit
warnShow value = warn (show value)

error :: String -> IO Unit
error message = IO (Console.error message)

errorShow :: forall a. Show a => a -> IO Unit
errorShow value = error (show value)

info :: String -> IO Unit
info message = IO (Console.info message)

infoShow :: forall a. Show a => a -> IO Unit
infoShow value = info (show value)

debug :: String -> IO Unit
debug message = IO (Console.debug message)

debugShow :: forall a. Show a => a -> IO Unit
debugShow value = debug (show value)

module Main where

import Prelude

import Control.Monad (unlessM)
import Data.Array as Array
import Data.Either (either)
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), maybe)
import Data.Newtype (un)
import Data.Number.Format (fixed, toStringWith)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Effect.Class (liftEffect)
import Go.Bytes (ByteCount(..))
import Go.FilePath (FilePath(..))
import Go.IO (IO, bracket_, finally, forkIO, launchIO_)
import Go.IO.Async (mapConcurrently_)
import Go.IO.Chan (Chan, close, newBufferedChan, receive, send)
import Go.IO.Console (log)
import Go.IO.Context (Cancellation(..), Context, background, cancel, err, isCancelled, withTimeout)
import Go.IO.Select (onDone, onReceive, onSend, select2)
import Go.OS (Arg(..), DirEntry)
import Go.OS as OS
import Go.Path.Filepath as Filepath

type SizedFile = { path :: FilePath, size :: ByteCount }

type Summary = { filesSeen :: Int, largest :: Array SizedFile }

-- | Every directory is read on its own goroutine, but never more than this many at once.
newtype OpenDirectoryLimit = OpenDirectoryLimit (Chan Unit)

type Scan = { context :: Context, foundFiles :: Chan SizedFile, openDirectories :: OpenDirectoryLimit }

main :: Effect Unit
main = launchIO_ do
  root <- directoryFromArguments # liftEffect
  context /\ stopTheClock <- withTimeout (Milliseconds 2000.0) background
  foundFiles <- newBufferedChan 256
  openDirectories <- newBufferedChan 64 <#> OpenDirectoryLimit
  _ <- forkIO (walk { context, foundFiles, openDirectories } root `finally` close foundFiles)
  summary <- keepTheLargest context foundFiles { filesSeen: 0, largest: [] }
  stoppedBecause <- err context
  cancel stopTheClock
  report root summary stoppedBecause
  where
  directoryFromArguments = OS.args <#> Array.head >>> maybe (FilePath ".") (un Arg >>> FilePath)

walk :: Scan -> FilePath -> IO Unit
walk scan directory = unlessM (isCancelled scan.context) do
  entries <- readDirectory scan.openDirectories directory
  for_ (Array.filter (not OS.entryIsDir) entries) (sizeOf >=> maybe (pure unit) (sendUnlessCancelled scan))
  mapConcurrently_ (walk scan) (Array.filter OS.entryIsDir entries <#> pathOf)
  where
  pathOf entry = Filepath.join [ directory, OS.entryName entry ]
  sizeOf entry = OS.lstat (pathOf entry) # liftEffect <#> either (const Nothing) (regularFileOf (pathOf entry))
  regularFileOf path info = if OS.isRegular info then Just { path, size: OS.size info } else Nothing

readDirectory :: OpenDirectoryLimit -> FilePath -> IO (Array DirEntry)
readDirectory (OpenDirectoryLimit slots) directory =
  bracket_ (send slots unit) (receive slots) (OS.readDir directory # liftEffect <#> either (const []) identity)

sendUnlessCancelled :: Scan -> SizedFile -> IO Unit
sendUnlessCancelled scan file = select2
  (onSend scan.foundFiles file (pure unit))
  (onDone scan.context (pure unit))

keepTheLargest :: Context -> Chan SizedFile -> Summary -> IO Summary
keepTheLargest context foundFiles summary = do
  next <- select2 (onReceive foundFiles pure) (onDone context (pure Nothing))
  case next of
    Just file -> keepTheLargest context foundFiles (remember file)
    Nothing -> pure summary
  where
  remember file = { filesSeen: summary.filesSeen + 1, largest: topTen (Array.insertBy largestFirst file summary.largest) }
  topTen = Array.take 10
  largestFirst a b = compare b.size a.size

report :: FilePath -> Summary -> Maybe Cancellation -> IO Unit
report root { filesSeen, largest } stoppedBecause = do
  log ("The largest of " <> show filesSeen <> " files under " <> un FilePath root <> ":")
  for_ largest \file -> log (readable file.size <> "  " <> un FilePath file.path)
  log case stoppedBecause of
    Just DeadlineExceeded -> "Stopped at the 2 second deadline, so that's the largest so far."
    _ -> "That's the whole tree."
  where
  readable (ByteCount bytes)
    | bytes >= 1.0e9 = padLeft 7 (oneDecimal (bytes / 1.0e9)) <> " GB"
    | otherwise = padLeft 7 (oneDecimal (bytes / 1.0e6)) <> " MB"
  oneDecimal = toStringWith (fixed 1)
  padLeft width text = String.joinWith "" (Array.replicate (width - String.length text) " ") <> text

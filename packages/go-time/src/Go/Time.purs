module Go.Time
  ( Layout(..)
  , rfc3339
  , dateOnly
  , timeOnly
  , format
  , parse
  , sleep
  ) where

import Prelude

import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Either (Either(..))
import Data.Maybe (fromJust)
import Data.Newtype (class Newtype, un)
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Go.Error (GoError)
import Partial.Unsafe (unsafePartial)

-- | A layout in Go's reference-time notation: how `Mon Jan 2 15:04:05 MST 2006` would look.
newtype Layout = Layout String

derive instance Newtype Layout _
derive newtype instance Eq Layout
derive newtype instance Show Layout

-- | `2006-01-02T15:04:05Z07:00`
rfc3339 :: Layout
rfc3339 = Layout "2006-01-02T15:04:05Z07:00"

-- | `2006-01-02`
dateOnly :: Layout
dateOnly = Layout "2006-01-02"

-- | `15:04:05`
timeOnly :: Layout
timeOnly = Layout "15:04:05"

-- | Formats the instant in UTC.
format :: Layout -> Instant -> String
format layout moment = formatImpl (un Layout layout) (un Milliseconds (unInstant moment))

-- | Parses a time written in the layout. Without a zone in the text, it is UTC.
parse :: Layout -> String -> Either GoError Instant
parse layout text = parseImpl Left (Right <<< toInstant) (un Layout layout) text
  where
  toInstant milliseconds = unsafePartial (fromJust (instant (Milliseconds milliseconds)))

-- | Blocks the program for the duration.
sleep :: Milliseconds -> Effect Unit
sleep duration = sleepImpl (un Milliseconds duration)

foreign import formatImpl :: String -> Number -> String
foreign import parseImpl :: forall r. (GoError -> r) -> (Number -> r) -> String -> String -> r
foreign import sleepImpl :: Number -> Effect Unit

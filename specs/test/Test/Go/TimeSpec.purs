module Test.Go.TimeSpec where

import Prelude

import Data.DateTime.Instant (diff, instant)
import Data.Either (hush, isLeft)
import Data.Maybe (Maybe(..))
import Data.Time.Duration (Milliseconds(..))
import Effect.Class (liftEffect)
import Effect.Now (now)
import Go.Time (Layout(..), dateOnly, rfc3339, timeOnly)
import Go.Time as Time
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

spec :: Spec Unit
spec = describe "Go.Time" do
  it "formats an instant in UTC" do
    let moment = instant (Milliseconds 1700000000123.0)
    (Time.format rfc3339 <$> moment) `shouldEqual` Just "2023-11-14T22:13:20Z"
    (Time.format dateOnly <$> moment) `shouldEqual` Just "2023-11-14"
    (Time.format timeOnly <$> moment) `shouldEqual` Just "22:13:20"
    (Time.format (Layout "Jan 2, 2006 at 3:04pm") <$> moment) `shouldEqual` Just "Nov 14, 2023 at 10:13pm"

  it "parses what it formats" do
    hush (Time.parse rfc3339 "2023-11-14T22:13:20Z") `shouldEqual` instant (Milliseconds 1700000000000.0)
    hush (Time.parse rfc3339 "2023-11-14T23:13:20+01:00") `shouldEqual` instant (Milliseconds 1700000000000.0)
    Time.parse dateOnly "14.11.2023" `shouldSatisfy` isLeft

  it "sleeps" do
    before <- liftEffect now
    liftEffect (Time.sleep (Milliseconds 20.0))
    after <- liftEffect now
    (diff after before :: Milliseconds) `shouldSatisfy` (_ >= Milliseconds 20.0)

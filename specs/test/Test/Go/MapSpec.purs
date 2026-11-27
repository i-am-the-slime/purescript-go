module Test.Go.MapSpec where

import Prelude

import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Effect.Class (liftEffect)
import Go.Map (GoMap)
import Go.Map as GoMap
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Go.Map" do
  it "finds what was inserted and forgets what was deleted" do
    squares <- GoMap.new # liftEffect
    for_ [ 1, 2, 3 ] (\n -> GoMap.insert n (n * n) squares) # liftEffect
    GoMap.delete 2 squares # liftEffect
    two <- GoMap.lookup 2 squares # liftEffect
    three <- GoMap.lookup 3 squares # liftEffect
    hasOne <- GoMap.member 1 squares # liftEffect
    count <- GoMap.size squares # liftEffect
    { two, three, hasOne, count } `shouldEqual` { two: Nothing, three: Just 9, hasOne: true, count: 2 }

  it "overwrites a key's value" do
    names <- GoMap.new # liftEffect
    GoMap.insert "a" "first" names # liftEffect
    GoMap.insert "a" "second" names # liftEffect
    found <- GoMap.lookup "a" names # liftEffect
    found `shouldEqual` Just "second"

  it "alters a key, adding, changing and removing it" do
    tallies <- GoMap.newWithCapacity 4 # liftEffect
    for_ [ "b", "a", "b", "c", "b" ] (\word -> GoMap.alter countOneMore word tallies) # liftEffect
    GoMap.alter (const Nothing) "c" tallies # liftEffect
    counted <- GoMap.entries tallies # liftEffect
    counted `shouldEqual` [ "a" /\ 1, "b" /\ 3 ]

  it "lists keys and values sorted by key, whatever order Go keeps them in" do
    letters <- GoMap.new # liftEffect
    for_ [ 'z', 'a', 'm', 'q', 'b' ] (\letter -> GoMap.insert letter (show letter) letters) # liftEffect
    keys <- GoMap.keys letters # liftEffect
    values <- GoMap.values letters # liftEffect
    keys `shouldEqual` [ 'a', 'b', 'm', 'q', 'z' ]
    values `shouldEqual` [ "'a'", "'b'", "'m'", "'q'", "'z'" ]

  it "takes Number keys" do
    prices <- (GoMap.new :: _ (GoMap Number String)) # liftEffect
    GoMap.insert 2.5 "cheap" prices # liftEffect
    found <- GoMap.lookup 2.5 prices # liftEffect
    found `shouldEqual` Just "cheap"
  where
  countOneMore = case _ of
    Nothing -> Just 1
    Just count -> Just (count + 1)

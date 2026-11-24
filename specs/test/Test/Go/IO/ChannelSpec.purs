module Test.Go.IO.ChannelSpec (spec) where

import Prelude

import Control.Monad.Rec.Class (Step(..), tailRecM)
import Data.Array as Array
import Data.DateTime.Instant (diff, instant, unInstant)
import Data.Either (isLeft)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))
import Effect.Class (liftEffect)
import Effect.Now (now)
import Go.IO (IO, forkIO, threadDelay, threadDelayWith, toAff, try)
import Go.IO.Async (concurrently)
import Go.IO.Chan (Chan, Polled(..), capacity, close, length, newBufferedChan, newChan, receive, send, sendAll, tryReceive, trySend)
import Go.IO.Context (Cancellation(..), Context, background, cancel, done, err, isCancelled, withCancel, withDeadline, withTimeout)
import Go.IO.MVar (newEmptyMVar, newMVar, putMVarWith, readMVarWith, takeMVarWith)
import Go.IO.Select (onDone, onReceive, onSend, select2, select3, trySelect1, trySelect2)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

spec :: Spec Unit
spec = describe "Go.IO channels" do
  describe "Chan" do
    it "has no room without a receiver, unbuffered" do
      sent <- toAff do
        channel <- newChan
        trySend channel 1
      sent `shouldEqual` false

    it "takes as many values as it has room for, buffered" do
      found <- toAff do
        channel <- newBufferedChan 2
        first <- trySend channel "one"
        second <- trySend channel "two"
        third <- trySend channel "three"
        waiting <- length channel
        pure { sent: [ first, second, third ], waiting, room: capacity channel }
      found `shouldEqual` { sent: [ true, true, false ], waiting: 2, room: 2 }

    it "hands out what was sent before it was closed, then Nothing" do
      received <- toAff do
        channel <- newBufferedChan 2
        sendAll channel [ 1, 2 ]
        close channel
        traverseIO [ 1, 2, 3 ] \_ -> receive channel
      received `shouldEqual` [ Just 1, Just 2, Nothing ]

    it "polls without waiting" do
      polled <- toAff do
        channel <- newBufferedChan 1
        empty <- tryReceive channel
        send channel { name: "ada" }
        full <- tryReceive channel
        close channel
        closed <- tryReceive channel
        pure [ empty, full, closed ]
      polled `shouldEqual` [ Empty, Received { name: "ada" }, Closed ]

    it "throws on a send to a closed channel" do
      outcome <- toAff do
        channel <- newBufferedChan 1
        close channel
        try (send channel 'x')
      isLeft outcome `shouldEqual` true

  describe "Context" do
    it "never cancels the background" do
      state <- toAff (contextState background)
      state `shouldEqual` { cancelled: false, why: Nothing }

    it "is cancelled once cancel is called, with its children" do
      states <- toAff do
        parent /\ cancelParent <- withCancel background
        child /\ _ <- withCancel parent
        before <- contextState child
        cancel cancelParent
        after <- contextState child
        pure [ before, after ]
      states `shouldEqual` [ { cancelled: false, why: Nothing }, { cancelled: true, why: Just Cancelled } ]

    it "times out" do
      state <- toAff do
        context /\ _ <- withTimeout (Milliseconds 10.0) background
        threadDelay (Milliseconds 50.0)
        contextState context
      state `shouldEqual` { cancelled: true, why: Just DeadlineExceeded }

    it "is done at its deadline" do
      current <- liftEffect now
      let deadline = fromMaybe current (instant (unInstant current <> Milliseconds 10.0))
      states <- toAff do
        context /\ _ <- withDeadline deadline background
        before <- contextState context
        threadDelay (Milliseconds 50.0)
        after <- contextState context
        pure [ before, after ]
      states `shouldEqual` [ { cancelled: false, why: Nothing }, { cancelled: true, why: Just DeadlineExceeded } ]

    it "closes done once cancelled" do
      received <- toAff do
        context /\ cancelContext <- withCancel background
        _ <- forkIO (threadDelay (Milliseconds 10.0) *> cancel cancelContext)
        receive (done context)
      received `shouldEqual` Nothing

  describe "select" do
    it "takes from whichever channel has a value" do
      chosen <- toAff do
        quiet <- newChan
        busy <- newBufferedChan 1
        send busy "busy"
        select2
          (onReceive quiet \value -> pure ("quiet " <> show (value :: Maybe String)))
          (onReceive busy \value -> pure ("busy " <> show value))
      chosen `shouldEqual` "busy (Just \"busy\")"

    it "sends once a receiver is there, then runs the send's handler" do
      outcome <- toAff do
        jobs <- newChan
        context /\ _ <- withCancel background
        concurrently
          (select2 (onSend jobs 42 (pure "sent")) (onDone context (pure "cancelled")))
          (receive jobs)
      outcome `shouldEqual` ("sent" /\ Just 42)

    it "stops waiting once the context is done" do
      started <- liftEffect now
      outcome <- toAff do
        nothingComes <- newChan
        context /\ cancelContext <- withCancel background
        _ <- forkIO (threadDelay (Milliseconds 20.0) *> cancel cancelContext)
        select2
          (onReceive nothingComes \(_ :: Maybe Int) -> pure "received")
          (onDone context (pure "cancelled"))
      finished <- liftEffect now
      outcome `shouldEqual` "cancelled"
      (diff finished started :: Milliseconds) `shouldSatisfy` (_ < Milliseconds 1000.0)

    it "hands Nothing to the handler of a closed channel" do
      outcome <- toAff do
        closing <- newChan
        close closing
        nothingComes <- newChan
        select2 (onReceive closing pure) (onReceive nothingComes \(_ :: Maybe Unit) -> pure (Just "never"))
      outcome `shouldEqual` (Nothing :: Maybe String)

    it "chooses among three cases, of different types" do
      chosen <- toAff do
        numbers <- newChan
        names <- newChan
        flags <- newBufferedChan 1
        send flags true
        fromReceives <- select3
          (onReceive numbers \(n :: Maybe Int) -> pure ("number " <> show n))
          (onReceive names \(name :: Maybe String) -> pure ("name " <> show name))
          (onReceive flags \flag -> pure ("flag " <> show flag))
        cancelled /\ cancelContext <- withCancel background
        cancel cancelContext
        fromMixed <- select3
          (onSend numbers 1 (pure "sent"))
          (onReceive names \name -> pure ("name " <> show name))
          (onDone cancelled (pure "done"))
        room <- newBufferedChan 1
        fromSends <- select3 (onSend numbers 1 (pure "number")) (onSend names "ada" (pure "name")) (onSend room unit (pure "room"))
        pure [ fromReceives, fromMixed, fromSends ]
      chosen `shouldEqual` [ "flag (Just true)", "done", "room" ]

    it "takes the default when no case can go" do
      chosen <- toAff do
        empty <- newChan
        full <- newChan
        one <- trySelect1 (onReceive empty \(_ :: Maybe Int) -> pure "received") (pure "default")
        sending <- trySelect1 (onSend full 'x' (pure "sent")) (pure "default")
        two <- trySelect2 (onReceive empty \(_ :: Maybe Int) -> pure "received") (onSend full 'x' (pure "sent")) (pure "default")
        both <- trySelect2 (onSend full 'y' (pure "sent")) (onDone background (pure "done")) (pure "default")
        pure [ one, sending, two, both ]
      chosen `shouldEqual` [ "default", "default", "default", "default" ]

    it "takes a case that can go rather than the default" do
      chosen <- toAff do
        room <- newBufferedChan 1
        trySelect1 (onSend room unit (pure "sent")) (pure "default")
      chosen `shouldEqual` "sent"

    it "merges two producers into one sum" do
      total <- toAff do
        left <- newChan
        right <- newChan
        _ <- forkIO (sendAll left (map Just (oneTo 1_000)) *> close left)
        _ <- forkIO (sendAll right (map Just (oneTo 1_000)) *> close right)
        sumBoth left right
      total `shouldEqual` 1_001_000

  describe "threadDelayWith" do
    it "waits the whole duration while the context is running" do
      slept <- toAff (threadDelayWith background (Milliseconds 10.0))
      slept `shouldEqual` true

    it "wakes once the context is done" do
      started <- liftEffect now
      slept <- toAff do
        context /\ cancelContext <- withCancel background
        _ <- forkIO (threadDelay (Milliseconds 20.0) *> cancel cancelContext)
        threadDelayWith context (Milliseconds 5_000.0)
      finished <- liftEffect now
      slept `shouldEqual` false
      (diff finished started :: Milliseconds) `shouldSatisfy` (_ < Milliseconds 1000.0)

  describe "MVar waits with a context" do
    it "take and read what is there" do
      found <- toAff do
        box <- newMVar "here"
        read <- readMVarWith background box
        taken <- takeMVarWith background box
        pure [ read, taken ]
      found `shouldEqual` [ Just "here", Just "here" ]

    it "give up on an empty box once the context is done" do
      found <- toAff do
        box <- newEmptyMVar
        context /\ cancelContext <- withCancel background
        _ <- forkIO (threadDelay (Milliseconds 20.0) *> cancel cancelContext)
        taken <- takeMVarWith context box
        read <- readMVarWith context box
        pure [ taken, read ]
      found `shouldEqual` ([ Nothing, Nothing ] :: Array (Maybe Int))

    it "give up on a full box once the context is done" do
      put <- toAff do
        box <- newMVar 1
        context /\ cancelContext <- withCancel background
        _ <- forkIO (threadDelay (Milliseconds 20.0) *> cancel cancelContext)
        putMVarWith context box 2
      put `shouldEqual` false

contextState :: Context -> IO { cancelled :: Boolean, why :: Maybe Cancellation }
contextState context = do
  cancelled <- isCancelled context
  why <- err context
  pure { cancelled, why }

-- | Receives from both until both are closed.
sumBoth :: Chan (Maybe Int) -> Chan (Maybe Int) -> IO Int
sumBoth left right = tailRecM step { leftOpen: true, rightOpen: true, total: 0 }
  where
  step state@{ leftOpen, rightOpen }
    | leftOpen && rightOpen = select2 (onReceive left (fromLeft state)) (onReceive right (fromRight state))
    | leftOpen = receive left >>= fromLeft state
    | rightOpen = receive right >>= fromRight state
    | otherwise = pure (Done state.total)
  fromLeft state = case _ of
    Just (Just value) -> pure (Loop state { total = state.total + value })
    _ -> pure (Loop state { leftOpen = false })
  fromRight state = case _ of
    Just (Just value) -> pure (Loop state { total = state.total + value })
    _ -> pure (Loop state { rightOpen = false })

oneTo :: Int -> Array Int
oneTo count = Array.range 1 count

traverseIO :: forall a b. Array a -> (a -> IO b) -> IO (Array b)
traverseIO elements f = tailRecM step (0 /\ [])
  where
  step (index /\ acc) = case Array.index elements index of
    Nothing -> pure (Done acc)
    Just element -> f element <#> \value -> Loop ((index + 1) /\ Array.snoc acc value)

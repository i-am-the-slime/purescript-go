module Test.Go.IOSpec
  ( spec
  , child
  ) where

import Prelude

import Control.Parallel (parOneOf, parSequence_, parTraverse, parallel, sequential)
import Control.Plus (empty)
import Control.Monad.Rec.Class (Step(..), tailRec, tailRecM)
import Data.Array as Array
import Data.Array.Partial as ArrayPartial
import Data.DateTime.Instant (diff)
import Data.Either (Either(..), either, isLeft)
import Data.Foldable (for_, sum)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (un)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Effect.Exception (error, message, throw)
import Effect.Now (now)
import Effect.Ref as Ref
import Go.FilePath (FilePath(..))
import Go.IO (IO, catch, evaluate, forkIO, getNumCapabilities, launchIO, launchIO_, threadDelay, throwIO, toAff, try)
import Go.IO.Async (concurrently, forConcurrently, forConcurrently_, mapConcurrently, mapConcurrently_, race, replicateConcurrently)
import Go.IO.Chan (newChan, readChan, writeList2Chan)
import Go.IO.IORef (atomicModifyIORef', newIORef, readIORef, writeIORef)
import Go.IO.MVar (modifyMVar_, newEmptyMVar, newMVar, putMVar, readMVar, takeMVar, withMVar)
import Go.Net.HTTP (Address(..), Status(..), URL(..))
import Go.Net.HTTP as HTTP
import Go.OS (EnvName(..), EnvValue(..), ExitCode(..))
import Go.OS as OS
import Go.OS.Exec (Environment(..), Program(..), command)
import Go.OS.Exec as Exec
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldNotEqual, shouldSatisfy)

spec :: Spec Unit
spec = describe "Go.IO" do
  describe "threads" do
    it "runs pure work on several cores at once" do
      capabilities <- toAff getNumCapabilities
      let workers = min 4 capabilities
      if workers < 2 then log "  (one core: nothing to compare)"
      else do
        work <- calibrate 1_000_000
        alone <- timed (toAff (spinning work))
        together <- timed (toAff (mapConcurrently spinning (Array.replicate workers work)))
        log ("  " <> show capabilities <> " cores; one worker " <> show (Int.round alone) <> " ms, " <> show workers <> " workers " <> show (Int.round together) <> " ms")
        together `shouldSatisfy` (_ < alone * Int.toNumber workers * 0.6)

    it "reports an exception a forked thread doesn't catch on standard error" do
      output <- asChild "fork-crash"
      output.stderr `shouldSatisfy` String.contains (String.Pattern "Error: boom")
      output.stderr `shouldSatisfy` String.contains (String.Pattern "thread")

    it "loops without growing the stack" do
      total <- toAff (tailRecM (\(i /\ acc) -> pure if i == 0 then Done acc else Loop ((i - 1) /\ (acc + 1))) (1_000_000 /\ 0))
      total `shouldEqual` 1_000_000

  describe "IORef" do
    it "counts exactly with atomicModifyIORef' from 8 threads" do
      count <- toAff do
        counter <- newIORef 0
        forConcurrently_ (Array.range 1 8) \_ ->
          repeatIO 10_000 (atomicModifyIORef' counter \n -> (n + 1) /\ unit)
        readIORef counter
      count `shouldEqual` 80_000

  describe "MVar" do
    it "works as a lock around a read and a write" do
      count <- toAff do
        lock <- newMVar unit
        counter <- newIORef 0
        forConcurrently_ (Array.range 1 8) \_ ->
          repeatIO 1_000 (withMVar lock \_ -> readIORef counter >>= writeIORef counter <<< (_ + 1))
        readIORef counter
      count `shouldEqual` 8_000

    it "keeps every modify and read of 32 threads, on an Int and on a record" do
      totals <- toAff do
        count <- newMVar 0
        stats <- newMVar { hits: 0, lastThread: 0 }
        forConcurrently_ (Array.range 1 32) \thread ->
          repeatIO 1_000 do
            modifyMVar_ count (pure <<< (_ + 1))
            modifyMVar_ stats \seen -> pure { hits: seen.hits + 1, lastThread: thread }
            seen <- readMVar stats
            unless (seen.lastThread >= 1 && seen.lastThread <= 32) (throwIO (error "torn read"))
        counted <- readMVar count
        seen <- readMVar stats
        pure { counted, hits: seen.hits }
      totals `shouldEqual` { counted: 32_000, hits: 32_000 }

    it "works as a channel between two threads" do
      received <- toAff do
        box <- newEmptyMVar
        _ <- forkIO (forEachIO (Array.range 1 100) (putMVar box))
        traverseIO (Array.range 1 100) (\_ -> takeMVar box)
      received `shouldEqual` Array.range 1 100

  describe "Chan" do
    it "delivers in the order written" do
      received <- toAff do
        queue <- newChan
        _ <- forkIO (writeList2Chan queue (Array.range 1 1_000))
        traverseIO (Array.range 1 1_000) (\_ -> readChan queue)
      received `shouldEqual` Array.range 1 1_000

  describe "Async" do
    it "returns every result, in order" do
      results <- toAff do
        both <- concurrently (threadDelay (Milliseconds 20.0) $> "left") (pure "right")
        squares <- mapConcurrently (\n -> threadDelay (Milliseconds (Int.toNumber (10 - n))) $> n * n) (Array.range 1 9)
        copies <- replicateConcurrently 3 (pure 'x')
        pure { both, squares, copies }
      results.both `shouldEqual` ("left" /\ "right")
      results.squares `shouldEqual` map (\n -> n * n) (Array.range 1 9)
      results.copies `shouldEqual` [ 'x', 'x', 'x' ]

    it "works out f x on the threads of mapConcurrently and forConcurrently" do
      inParallel \items -> do
        mapped <- toAff (timedIO (mapConcurrently (\n -> pure (spin n)) items))
        forked <- toAff (timedIO (forConcurrently items \n -> pure (spin n)))
        pure [ mapped, forked ]

    it "works out f x on the threads of mapConcurrently_ and forConcurrently_" do
      inParallel \items -> do
        mapped <- toAff (timedIO (mapConcurrently_ (\n -> pure (spin n)) items))
        forked <- toAff (timedIO (forConcurrently_ items \n -> pure (spin n)))
        pure [ mapped, forked ]

    it "throws the first exception of its threads" do
      outcome <- toAff (try (mapConcurrently (\n -> if n == 3 then throwIO (error "three") else threadDelay (Milliseconds 500.0) $> n) (Array.range 1 5)))
      either message show outcome `shouldEqual` "three"

    it "races, and returns the first to finish" do
      winner <- toAff (race (threadDelay (Milliseconds 300.0) $> 1) (pure "fast"))
      winner `shouldEqual` Right "fast"

  describe "ParIO" do
    it "runs both sides of <*> at the same time" do
      handshake <- toAff do
        leftReady <- newEmptyMVar
        rightReady <- newEmptyMVar
        let left = putMVar leftReady "left" *> takeMVar rightReady
        let right = putMVar rightReady "right" *> takeMVar leftReady
        sequential ((/\) <$> parallel left <*> parallel right)
      handshake `shouldEqual` ("right" /\ "left")

    it "traverses in parallel and keeps the order" do
      started <- liftEffect now
      squares <- toAff (parTraverse (\n -> threadDelay (Milliseconds 100.0) $> n * n) (Array.range 1 8))
      finished <- liftEffect now
      squares `shouldEqual` map (\n -> n * n) (Array.range 1 8)
      (diff finished started :: Milliseconds) `shouldSatisfy` (_ < Milliseconds 400.0)

    it "runs every action of parSequence_" do
      count <- toAff do
        counter <- newIORef 0
        parSequence_ (Array.replicate 50 (atomicModifyIORef' counter \n -> (n + 1) /\ unit))
        readIORef counter
      count `shouldEqual` 50

    it "returns the first to finish from parOneOf, and empty never wins" do
      winner <- toAff (parOneOf [ threadDelay (Milliseconds 300.0) $> "slow", pure "fast", sequential empty ])
      winner `shouldEqual` "fast"

    it "throws as soon as one side throws, without waiting for the other" do
      started <- liftEffect now
      outcome <- toAffAttempt (sequential (parallel (threadDelay (Milliseconds 2000.0)) *> parallel (throwIO (error "early") :: IO Unit)))
      finished <- liftEffect now
      outcome `shouldEqual` Left "early"
      (diff finished started :: Milliseconds) `shouldSatisfy` (_ < Milliseconds 1000.0)

  describe "exceptions" do
    it "catches what IO throws" do
      caught <- toAff (throwIO (error "thrown") `catch` (pure <<< message))
      caught `shouldEqual` "thrown"

    it "catches what an IO Unit throws" do
      caught <- toAff do
        seen <- newIORef ""
        throwIO (error "thrown") `catch` (writeIORef seen <<< message)
        readIORef seen
      caught `shouldEqual` "thrown"

    it "catches a panic in Go code" do
      outcome <- toAff (try (pure unit >>= \_ -> evaluate (unsafePartial (ArrayPartial.head ([] :: Array Int)))))
      isLeft outcome `shouldEqual` true

    it "turns an exception into the fiber's error in toAff" do
      outcome <- toAffAttempt (throwIO (error "in IO") :: IO Unit)
      outcome `shouldEqual` Left "in IO"

  describe "launchIO" do
    it "hands the result to the callback" do
      outcome <- launched (sum <$> mapConcurrently (pure <<< (_ * 2)) (Array.range 1 10))
      outcome `shouldEqual` Right 110

    it "hands an exception to the callback" do
      outcome <- launched (throwIO (error "launched") :: IO Unit)
      outcome `shouldEqual` Left "launched"

    it "returns before the action finishes" do
      order <- liftEffect do
        events <- Ref.new []
        launchIO_ (threadDelay (Milliseconds 50.0) *> liftEffect (Ref.modify_ (_ <> [ "action" ]) events))
        Ref.modify_ (_ <> [ "returned" ]) events
        pure events
      toAff (threadDelay (Milliseconds 200.0))
      liftEffect (Ref.read order) >>= (_ `shouldEqual` [ "returned", "action" ])

    it "ends the program with an exception launchIO_'s action doesn't catch" do
      output <- asChild "launch-crash"
      output.stderr `shouldSatisfy` String.contains (String.Pattern "panic: launch boom")
      output.exitCode `shouldNotEqual` ExitCode 0

  describe "the event loop" do
    it "lets 32 IO threads modify a Ref 1000 times each through liftEffect" do
      ref <- liftEffect (Ref.new 0)
      toAff (forConcurrently_ (Array.range 1 32) \_ -> for_ (Array.range 1 1000) \_ -> Ref.modify_ (_ + 1) ref # liftEffect)
      liftEffect (Ref.read ref) >>= (_ `shouldEqual` 32000)

    it "lifts an Effect into IO with liftEffect" do
      ref <- liftEffect (Ref.new 0)
      toAff (forConcurrently_ (Array.range 1 10) \n -> liftEffect (Ref.modify_ (_ + n) ref))
      liftEffect (Ref.read ref) >>= (_ `shouldEqual` 55)

    it "rethrows an exception of the Effect in IO" do
      outcome <- toAff (try (throw "from the Effect" # liftEffect))
      either message (const "no exception") outcome `shouldEqual` "from the Effect"

    it "runs IO from inside an HTTP handler" do
      server <- liftEffect (HTTP.start (Address "127.0.0.1:0") \_ -> HTTP.ok <<< show <$> toAff (sum <$> mapConcurrently (pure <<< (_ * 2)) (Array.range 1 10)))
        >>= either (liftEffect <<< throw <<< show) pure
      answer <- HTTP.get (URL ("http://" <> un Address (HTTP.serverAddress server) <> "/")) >>= either (liftEffect <<< throw <<< show) pure
      HTTP.shutdown server
      HTTP.status answer `shouldEqual` Status 200
      HTTP.responseBody answer `shouldEqual` "110"

-- | A pure loop that keeps one core busy.
spin :: Int -> Int
spin count = tailRec step (count /\ 0)
  where
  step (remaining /\ acc)
    | remaining <= 0 = Done acc
    | otherwise = Loop ((remaining - 1) /\ ((acc + remaining * remaining) `mod` 1_000_003))

-- | The loop, run when the action runs rather than when it is built.
spinning :: Int -> IO Int
spinning count = pure unit >>= \_ -> evaluate (spin count)

-- | Hands as many loop lengths as there are cores (up to 4) to the measurement, and checks that
-- | each of the times it returns is well below what doing them one after the other would take.
inParallel :: (Array Int -> Aff (Array Number)) -> Aff Unit
inParallel measure = do
  capabilities <- toAff getNumCapabilities
  let workers = min 4 capabilities
  if workers < 2 then log "  (one core: nothing to compare)"
  else do
    work <- calibrate 1_000_000
    alone <- timed (toAff (spinning work))
    times <- measure (Array.replicate workers work)
    times `shouldSatisfy` Array.all (_ < alone * Int.toNumber workers * 0.6)

-- | How long the action takes, in milliseconds.
timedIO :: forall a. IO a -> IO Number
timedIO action = do
  started <- liftEffect now
  _ <- action
  finished <- liftEffect now
  pure (un Milliseconds (diff finished started))

-- | A loop length that keeps one core busy for at least 150 milliseconds.
calibrate :: Int -> Aff Int
calibrate count = do
  elapsed <- timed (toAff (spinning count))
  if elapsed >= 150.0 then pure count else calibrate (count * 2)

timed :: forall a. Aff a -> Aff Number
timed action = do
  started <- liftEffect now
  _ <- action
  finished <- liftEffect now
  pure (un Milliseconds (diff finished started))

repeatIO :: Int -> IO Unit -> IO Unit
repeatIO count action = tailRecM (\n -> if n <= 0 then pure (Done unit) else action $> Loop (n - 1)) count

forEachIO :: forall a. Array a -> (a -> IO Unit) -> IO Unit
forEachIO elements f = tailRecM step 0
  where
  step index = case Array.index elements index of
    Nothing -> pure (Done unit)
    Just element -> f element $> Loop (index + 1)

traverseIO :: forall a b. Array a -> (a -> IO b) -> IO (Array b)
traverseIO elements f = tailRecM step (0 /\ [])
  where
  step (index /\ acc) = case Array.index elements index of
    Nothing -> pure (Done acc)
    Just element -> f element <#> \value -> Loop ((index + 1) /\ Array.snoc acc value)

launched :: forall a. IO a -> Aff (Either String a)
launched action = makeAff \resolve -> launchIO action (resolve <<< Right <<< either (Left <<< message) Right) $> nonCanceler

toAffAttempt :: forall a. IO a -> Aff (Either String a)
toAffAttempt action = toAff (try action) <#> either (Left <<< message) Right

childMode :: EnvName
childMode = EnvName "GO_IO_SPEC_CHILD"

asChild :: String -> Aff Exec.Output
asChild mode = liftEffect do
  binary <- OS.executable >>= either (throw <<< show) pure
  let runChild = (command (Program (un FilePath binary)) []) { environment = Inherited [ { name: childMode, value: EnvValue mode } ] }
  Exec.run runChild >>= either (throw <<< show) pure

-- | What the child does in each mode, if this binary runs as one.
child :: Effect Boolean
child = OS.lookupEnv childMode >>= case _ of
  Just (EnvValue "fork-crash") -> do
    launchAff_ (toAff (forkIO (throwIO (error "boom")) *> threadDelay (Milliseconds 100.0)))
    pure true
  Just (EnvValue "launch-crash") -> do
    launchIO_ (throwIO (error "launch boom"))
    pure true
  _ -> pure false

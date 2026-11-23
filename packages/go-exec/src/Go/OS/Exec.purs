module Go.OS.Exec
  ( Program(..)
  , Command
  , EnvVar
  , Environment(..)
  , Stdin(..)
  , Sink(..)
  , Output
  , ExecError(..)
  , Process
  , command
  , run
  , runAff
  , runInteractive
  , start
  , wait
  , kill
  ) where

import Prelude

import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Data.Newtype (class Newtype, un)
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Go.Error (GoError)
import Go.FilePath (FilePath(..))
import Go.OS (Arg(..), EnvName(..), EnvValue(..), ExitCode(..))

-- | A program to run: a name looked up on the `PATH`, such as `git`, or a path to one.
newtype Program = Program String

derive instance Newtype Program _
derive newtype instance Eq Program
derive newtype instance Show Program

type Command =
  { program :: Program
  , args :: Array Arg
  , dir :: Maybe FilePath
  , environment :: Environment
  , stdin :: Stdin
  , stdout :: Sink
  , stderr :: Sink
  }

-- | Where a program's standard input comes from.
data Stdin
  -- | This text, and then the end of the input.
  = Text String
  -- | This program's own standard input, such as the terminal.
  | ParentStdin

-- | Where a program's standard output or error goes.
data Sink
  -- | Into the `Output`.
  = Capture
  -- | To this program's own standard output or error, as it comes. The `Output` has `""` for it.
  | Parent

type EnvVar = { name :: EnvName, value :: EnvValue }

-- | The environment a program runs with.
data Environment
  -- | This program's own environment, with these variables added or replaced.
  = Inherited (Array EnvVar)
  -- | Exactly these variables, and nothing else.
  | Only (Array EnvVar)

-- | A program that ran to its end. A non-zero `exitCode` is an ordinary result, not an error. A
-- | program that a signal ended has `exitCode` `ExitCode (-1)` and the signal's name, such as
-- | `SIGKILL`, in `signal`, which is `""` otherwise.
type Output =
  { stdout :: String
  , stderr :: String
  , exitCode :: ExitCode
  , signal :: String
  }

data ExecError
  = ProgramNotFound Program
  | StartFailed GoError

instance Show ExecError where
  show = case _ of
    ProgramNotFound program -> "(ProgramNotFound " <> show program <> ")"
    StartFailed error -> "(StartFailed " <> show error <> ")"

-- | A program that was started and may still be running.
foreign import data Process :: Type

-- | A command that runs the program with the arguments in the working directory, with this
-- | program's environment and empty standard input, and captures its output. Change the rest with
-- | a record update: `(command git []) { dir = Just repo, stderr = Parent }`.
command :: Program -> Array Arg -> Command
command program arguments =
  { program
  , args: arguments
  , dir: Nothing
  , environment: Inherited []
  , stdin: Text ""
  , stdout: Capture
  , stderr: Capture
  }

-- | Runs the command to its end and collects its output. The whole program waits meanwhile; use
-- | `runAff` to let other fibers run.
run :: Command -> Effect (Either ExecError Output)
run cmd = runImpl notFound (Left <<< StartFailed) Right (prepared cmd)

-- | Runs the command to its end and collects its output. The fiber waits, the program doesn't:
-- | other fibers, such as a spinner, keep going.
runAff :: Command -> Aff (Either ExecError Output)
runAff cmd = do
  started <- start cmd # liftEffect
  case started of
    Left error -> pure (Left error)
    Right process -> lmap StartFailed <$> wait process

-- | Starts the command without waiting for it.
start :: Command -> Effect (Either ExecError Process)
start cmd = startImpl notFound (Left <<< StartFailed) Right (prepared cmd)

-- | Waits for a started program to end and collects its output. The fiber waits, the program
-- | doesn't. Waiting again gives the same output.
wait :: Process -> Aff (Either GoError Output)
wait process = makeAff \resolve -> waitImpl Left Right process (resolve <<< Right) $> nonCanceler

-- | Ends a started program with `SIGKILL`. Its `wait` then has `exitCode` `ExitCode (-1)`.
kill :: Process -> Effect (Either GoError Unit)
kill = killImpl Left (Right unit)

-- | Runs the command with this program's standard input, output and error, for programs that
-- | talk to the user: an editor, a pager, `git commit`. The command's `stdin` is not used.
runInteractive :: Command -> Effect (Either ExecError ExitCode)
runInteractive cmd = runInteractiveImpl notFound (Left <<< StartFailed) (Right <<< ExitCode) (prepared cmd)

notFound :: forall a. String -> Either ExecError a
notFound = Left <<< ProgramNotFound <<< Program

prepared :: Command -> Prepared
prepared { program, args, dir, environment, stdin, stdout, stderr } =
  { program: un Program program
  , args: map (un Arg) args
  , dir: maybe "" (un FilePath) dir
  , inherit: inherits
  , envNames: map (un EnvName <<< _.name) variables
  , envValues: map (un EnvValue <<< _.value) variables
  , stdinText: stdinText
  , stdinParent: stdinParent
  , stdoutParent: isParent stdout
  , stderrParent: isParent stderr
  }
  where
  inherits /\ variables = case environment of
    Inherited extra -> true /\ extra
    Only exact -> false /\ exact
  stdinText /\ stdinParent = case stdin of
    Text text -> text /\ false
    ParentStdin -> "" /\ true
  isParent = case _ of
    Capture -> false
    Parent -> true

-- | A command as Go starts it. The variables go as names and values: an `EnvVar` has the fields of
-- | `Go.Net.HTTP`'s `Header`, and a record can have one Go struct.
type Prepared =
  { program :: String
  , args :: Array String
  , dir :: String
  , inherit :: Boolean
  , envNames :: Array String
  , envValues :: Array String
  , stdinText :: String
  , stdinParent :: Boolean
  , stdoutParent :: Boolean
  , stderrParent :: Boolean
  }

foreign import runImpl
  :: forall r. (String -> r) -> (GoError -> r) -> (Output -> r) -> Prepared -> Effect r

foreign import startImpl
  :: forall r. (String -> r) -> (GoError -> r) -> (Process -> r) -> Prepared -> Effect r

foreign import waitImpl
  :: forall r. (GoError -> r) -> (Output -> r) -> Process -> (r -> Effect Unit) -> Effect Unit

foreign import killImpl :: forall r. (GoError -> r) -> r -> Process -> Effect r

foreign import runInteractiveImpl
  :: forall r. (String -> r) -> (GoError -> r) -> (Int -> r) -> Prepared -> Effect r

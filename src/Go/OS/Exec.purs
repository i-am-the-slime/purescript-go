module Go.OS.Exec
  ( Program(..)
  , Command
  , EnvVar
  , Environment(..)
  , Output
  , ExecError(..)
  , command
  , run
  , runInteractive
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Data.Newtype (class Newtype, un)
import Data.Tuple.Nested ((/\))
import Effect (Effect)
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
  , stdin :: String
  }

type EnvVar = { name :: EnvName, value :: EnvValue }

-- | The environment a program runs with.
data Environment
  -- | This program's own environment, with these variables added or replaced.
  = Inherited (Array EnvVar)
  -- | Exactly these variables, and nothing else.
  | Only (Array EnvVar)

-- | A program that ran to its end. A non-zero `exitCode` is an ordinary result, not an error.
type Output =
  { stdout :: String
  , stderr :: String
  , exitCode :: ExitCode
  }

data ExecError
  = ProgramNotFound Program
  | StartFailed GoError

instance Show ExecError where
  show = case _ of
    ProgramNotFound program -> "(ProgramNotFound " <> show program <> ")"
    StartFailed error -> "(StartFailed " <> show error <> ")"

-- | A command that runs the program with the arguments in the working directory, with this
-- | program's environment and empty standard input. Change the rest with a record update:
-- | `(command git []) { dir = Just repo }`.
command :: Program -> Array Arg -> Command
command program arguments =
  { program, args: arguments, dir: Nothing, environment: Inherited [], stdin: "" }

-- | Runs the command to its end and collects its output.
run :: Command -> Effect (Either ExecError Output)
run cmd = runImpl notFound (Left <<< StartFailed) Right (prepared cmd) cmd.stdin

-- | Runs the command with this program's standard input, output and error, for programs that
-- | talk to the user: an editor, a pager, `git commit`. The command's `stdin` is not used.
runInteractive :: Command -> Effect (Either ExecError ExitCode)
runInteractive cmd = runInteractiveImpl notFound (Left <<< StartFailed) (Right <<< ExitCode) (prepared cmd)

notFound :: forall a. String -> Either ExecError a
notFound = Left <<< ProgramNotFound <<< Program

prepared :: Command -> Prepared
prepared { program, args, dir, environment } =
  { program: un Program program
  , args: map (un Arg) args
  , dir: maybe "" (un FilePath) dir
  , inherit: inherits
  , envNames: map (un EnvName <<< _.name) variables
  , envValues: map (un EnvValue <<< _.value) variables
  }
  where
  inherits /\ variables = case environment of
    Inherited extra -> true /\ extra
    Only exact -> false /\ exact

-- | A command as Go starts it. The variables go as names and values: an `EnvVar` has the fields of
-- | `Go.Net.HTTP`'s `Header`, and a record can have one Go struct.
type Prepared =
  { program :: String
  , args :: Array String
  , dir :: String
  , inherit :: Boolean
  , envNames :: Array String
  , envValues :: Array String
  }

foreign import runImpl
  :: forall r. (String -> r) -> (GoError -> r) -> (Output -> r) -> Prepared -> String -> Effect r

foreign import runInteractiveImpl
  :: forall r. (String -> r) -> (GoError -> r) -> (Int -> r) -> Prepared -> Effect r

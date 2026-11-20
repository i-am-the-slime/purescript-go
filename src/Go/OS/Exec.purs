module Go.OS.Exec
  ( Program(..)
  , Command
  , Output
  , ExecError(..)
  , command
  , run
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Data.Newtype (class Newtype, un)
import Effect (Effect)
import Go.Error (GoError)
import Go.FilePath (FilePath(..))
import Go.OS (Arg(..), ExitCode)

-- | A program to run: a name looked up on the `PATH`, such as `git`, or a path to one.
newtype Program = Program String

derive instance Newtype Program _
derive newtype instance Eq Program
derive newtype instance Show Program

type Command =
  { program :: Program
  , args :: Array Arg
  , dir :: Maybe FilePath
  , stdin :: String
  }

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

-- | A command that runs the program with the arguments in the working directory, with empty
-- | standard input. Change the rest with a record update: `(command git []) { dir = Just repo }`.
command :: Program -> Array Arg -> Command
command program arguments = { program, args: arguments, dir: Nothing, stdin: "" }

-- | Runs the command to its end and collects its output.
run :: Command -> Effect (Either ExecError Output)
run { program, args, dir, stdin } =
  runImpl
    (Left <<< ProgramNotFound <<< Program)
    (Left <<< StartFailed)
    Right
    (un Program program)
    (map (un Arg) args)
    (maybe "" (un FilePath) dir)
    stdin

foreign import runImpl
  :: forall r
   . (String -> r)
  -> (GoError -> r)
  -> (Output -> r)
  -> String
  -> Array String
  -> String
  -> String
  -> Effect r

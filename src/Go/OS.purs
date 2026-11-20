module Go.OS
  ( FSError(..)
  , FileMode(..)
  , FileInfo
  , DirEntry
  , ByteCount(..)
  , EnvName(..)
  , EnvValue(..)
  , Arg(..)
  , ExitCode(..)
  , readFile
  , writeFile
  , writeFileWithMode
  , appendFile
  , readDir
  , mkdir
  , mkdirAll
  , remove
  , removeAll
  , rename
  , stat
  , exists
  , mkdirTemp
  , tempDir
  , getwd
  , chdir
  , args
  , lookupEnv
  , setenv
  , unsetenv
  , exit
  , name
  , size
  , isDir
  , mode
  , modTime
  , entryName
  , entryIsDir
  ) where

import Prelude

import Data.DateTime.Instant (Instant, instant)
import Data.Either (Either(..), isRight)
import Data.Maybe (Maybe(..), fromJust)
import Data.Newtype (class Newtype, un)
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Exception (throw)
import Go.Error (GoError)
import Go.FilePath (FilePath(..))
import Partial.Unsafe (unsafePartial)

-- | A failed file system operation, by the checks Go's `errors.Is` makes.
data FSError
  = NotExist FilePath
  | Exist FilePath
  | Permission FilePath
  | OtherError GoError

instance Show FSError where
  show = case _ of
    NotExist path -> "(NotExist " <> show path <> ")"
    Exist path -> "(Exist " <> show path <> ")"
    Permission path -> "(Permission " <> show path <> ")"
    OtherError error -> "(OtherError " <> show error <> ")"

-- | Permission bits, as in `os.FileMode`: `FileMode 0o644` is written `FileMode 420`.
newtype FileMode = FileMode Int

derive instance Newtype FileMode _
derive newtype instance Eq FileMode
derive newtype instance Ord FileMode
derive newtype instance Show FileMode

newtype ByteCount = ByteCount Number

derive instance Newtype ByteCount _
derive newtype instance Eq ByteCount
derive newtype instance Ord ByteCount
derive newtype instance Show ByteCount

newtype EnvName = EnvName String

derive instance Newtype EnvName _
derive newtype instance Eq EnvName
derive newtype instance Ord EnvName
derive newtype instance Show EnvName

newtype EnvValue = EnvValue String

derive instance Newtype EnvValue _
derive newtype instance Eq EnvValue
derive newtype instance Show EnvValue

newtype Arg = Arg String

derive instance Newtype Arg _
derive newtype instance Eq Arg
derive newtype instance Show Arg

newtype ExitCode = ExitCode Int

derive instance Newtype ExitCode _
derive newtype instance Eq ExitCode
derive newtype instance Show ExitCode

-- | What `os.Stat` describes: a file's name, size, mode and modification time.
foreign import data FileInfo :: Type

-- | An entry of a directory, as `os.ReadDir` lists them.
foreign import data DirEntry :: Type

readFile :: FilePath -> Effect (Either FSError String)
readFile path = readFileImpl failed Right (un FilePath path)

-- | Creates or truncates the file, with mode 0644 for a new one.
writeFile :: FilePath -> String -> Effect (Either FSError Unit)
writeFile path = writeFileWithMode path (FileMode 420)

writeFileWithMode :: FilePath -> FileMode -> String -> Effect (Either FSError Unit)
writeFileWithMode path fileMode contents =
  writeFileImpl failed (Right unit) (un FilePath path) (un FileMode fileMode) contents

-- | Appends to the file, creating it with mode 0644 if it does not exist.
appendFile :: FilePath -> String -> Effect (Either FSError Unit)
appendFile path contents = appendFileImpl failed (Right unit) (un FilePath path) contents

-- | The directory's entries, sorted by name.
readDir :: FilePath -> Effect (Either FSError (Array DirEntry))
readDir path = readDirImpl failed Right (un FilePath path)

-- | Creates the directory with mode 0755.
mkdir :: FilePath -> Effect (Either FSError Unit)
mkdir path = mkdirImpl failed (Right unit) (un FilePath path)

-- | Creates the directory and any missing parents with mode 0755. Succeeds if it already exists.
mkdirAll :: FilePath -> Effect (Either FSError Unit)
mkdirAll path = mkdirAllImpl failed (Right unit) (un FilePath path)

-- | Removes a file or an empty directory.
remove :: FilePath -> Effect (Either FSError Unit)
remove path = removeImpl failed (Right unit) (un FilePath path)

-- | Removes the path and everything it contains. Succeeds if it does not exist.
removeAll :: FilePath -> Effect (Either FSError Unit)
removeAll path = removeAllImpl failed (Right unit) (un FilePath path)

rename :: FilePath -> FilePath -> Effect (Either FSError Unit)
rename from to = renameImpl failed (Right unit) (un FilePath from) (un FilePath to)

stat :: FilePath -> Effect (Either FSError FileInfo)
stat path = statImpl failed Right (un FilePath path)

exists :: FilePath -> Effect Boolean
exists path = isRight <$> stat path

-- | Creates a new directory inside `parent` whose name starts with `prefix`.
mkdirTemp :: FilePath -> String -> Effect (Either FSError FilePath)
mkdirTemp parent prefix = mkdirTempImpl failed (Right <<< FilePath) (un FilePath parent) prefix

-- | The directory for temporary files, such as `$TMPDIR`.
tempDir :: Effect FilePath
tempDir = FilePath <$> tempDirImpl

getwd :: Effect (Either FSError FilePath)
getwd = getwdImpl failed (Right <<< FilePath)

chdir :: FilePath -> Effect (Either FSError Unit)
chdir path = chdirImpl failed (Right unit) (un FilePath path)

-- | The program's arguments, without the program itself.
args :: Effect (Array Arg)
args = map Arg <$> argsImpl

lookupEnv :: EnvName -> Effect (Maybe EnvValue)
lookupEnv variable = lookupEnvImpl Nothing (Just <<< EnvValue) (un EnvName variable)

setenv :: EnvName -> EnvValue -> Effect Unit
setenv variable value = setenvImpl (un EnvName variable) (un EnvValue value)

unsetenv :: EnvName -> Effect Unit
unsetenv variable = unsetenvImpl (un EnvName variable)

-- | Exits right away, without running deferred work.
exit :: forall a. ExitCode -> Effect a
exit code = exitImpl (un ExitCode code) *> throw "os.Exit returned"

name :: FileInfo -> FilePath
name = FilePath <<< nameImpl

size :: FileInfo -> ByteCount
size = ByteCount <<< sizeImpl

isDir :: FileInfo -> Boolean
isDir = isDirImpl

mode :: FileInfo -> FileMode
mode = FileMode <<< modeImpl

modTime :: FileInfo -> Instant
modTime info = unsafePartial (fromJust (instant (Milliseconds (modTimeImpl info))))

entryName :: DirEntry -> FilePath
entryName = FilePath <<< entryNameImpl

entryIsDir :: DirEntry -> Boolean
entryIsDir = entryIsDirImpl

failed :: forall a. GoError -> Either FSError a
failed = Left <<< classifyImpl (NotExist <<< FilePath) (Exist <<< FilePath) (Permission <<< FilePath) OtherError

foreign import classifyImpl
  :: forall r. (String -> r) -> (String -> r) -> (String -> r) -> (GoError -> r) -> GoError -> r

foreign import readFileImpl :: forall r. (GoError -> r) -> (String -> r) -> String -> Effect r
foreign import writeFileImpl :: forall r. (GoError -> r) -> r -> String -> Int -> String -> Effect r
foreign import appendFileImpl :: forall r. (GoError -> r) -> r -> String -> String -> Effect r
foreign import readDirImpl :: forall r. (GoError -> r) -> (Array DirEntry -> r) -> String -> Effect r
foreign import mkdirImpl :: forall r. (GoError -> r) -> r -> String -> Effect r
foreign import mkdirAllImpl :: forall r. (GoError -> r) -> r -> String -> Effect r
foreign import removeImpl :: forall r. (GoError -> r) -> r -> String -> Effect r
foreign import removeAllImpl :: forall r. (GoError -> r) -> r -> String -> Effect r
foreign import renameImpl :: forall r. (GoError -> r) -> r -> String -> String -> Effect r
foreign import statImpl :: forall r. (GoError -> r) -> (FileInfo -> r) -> String -> Effect r
foreign import mkdirTempImpl :: forall r. (GoError -> r) -> (String -> r) -> String -> String -> Effect r
foreign import tempDirImpl :: Effect String
foreign import getwdImpl :: forall r. (GoError -> r) -> (String -> r) -> Effect r
foreign import chdirImpl :: forall r. (GoError -> r) -> r -> String -> Effect r
foreign import argsImpl :: Effect (Array String)
foreign import lookupEnvImpl :: forall r. r -> (String -> r) -> String -> Effect r
foreign import setenvImpl :: String -> String -> Effect Unit
foreign import unsetenvImpl :: String -> Effect Unit
foreign import exitImpl :: Int -> Effect Unit
foreign import nameImpl :: FileInfo -> String
foreign import sizeImpl :: FileInfo -> Number
foreign import isDirImpl :: FileInfo -> Boolean
foreign import modeImpl :: FileInfo -> Int
foreign import modTimeImpl :: FileInfo -> Number
foreign import entryNameImpl :: DirEntry -> String
foreign import entryIsDirImpl :: DirEntry -> Boolean

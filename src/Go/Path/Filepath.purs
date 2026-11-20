module Go.Path.Filepath
  ( Pattern(..)
  , Extension(..)
  , join
  , base
  , dir
  , ext
  , clean
  , isAbs
  , rel
  , abs
  , glob
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Newtype (class Newtype, un)
import Effect (Effect)
import Go.Error (GoError)
import Go.FilePath (FilePath(..))

-- | A pattern for `glob`, in the syntax of Go's `filepath.Match`: `*.purs`, `src/*/Main.go`.
newtype Pattern = Pattern String

derive instance Newtype Pattern _
derive newtype instance Eq Pattern
derive newtype instance Show Pattern

-- | A file name extension including its dot, such as `.go`, or empty.
newtype Extension = Extension String

derive instance Newtype Extension _
derive newtype instance Eq Extension
derive newtype instance Ord Extension
derive newtype instance Show Extension

join :: Array FilePath -> FilePath
join paths = FilePath (joinImpl (map (un FilePath) paths))

base :: FilePath -> FilePath
base = lift baseImpl

dir :: FilePath -> FilePath
dir = lift dirImpl

ext :: FilePath -> Extension
ext path = Extension (extImpl (un FilePath path))

clean :: FilePath -> FilePath
clean = lift cleanImpl

isAbs :: FilePath -> Boolean
isAbs path = isAbsImpl (un FilePath path)

-- | The path of `target` relative to `from`.
rel :: FilePath -> FilePath -> Either GoError FilePath
rel from target = relImpl Left (Right <<< FilePath) (un FilePath from) (un FilePath target)

-- | The absolute path, resolved against the working directory.
abs :: FilePath -> Effect (Either GoError FilePath)
abs path = absImpl Left (Right <<< FilePath) (un FilePath path)

-- | The files matching the pattern, sorted.
glob :: Pattern -> Effect (Either GoError (Array FilePath))
glob pattern = globImpl Left (Right <<< map FilePath) (un Pattern pattern)

lift :: (String -> String) -> FilePath -> FilePath
lift f path = FilePath (f (un FilePath path))

foreign import joinImpl :: Array String -> String
foreign import baseImpl :: String -> String
foreign import dirImpl :: String -> String
foreign import extImpl :: String -> String
foreign import cleanImpl :: String -> String
foreign import isAbsImpl :: String -> Boolean
foreign import relImpl :: forall r. (GoError -> r) -> (String -> r) -> String -> String -> r
foreign import absImpl :: forall r. (GoError -> r) -> (String -> r) -> String -> Effect r
foreign import globImpl :: forall r. (GoError -> r) -> (Array String -> r) -> String -> Effect r

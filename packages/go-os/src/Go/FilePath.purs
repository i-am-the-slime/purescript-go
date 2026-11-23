module Go.FilePath
  ( FilePath(..)
  ) where

import Prelude

import Data.Newtype (class Newtype)

newtype FilePath = FilePath String

derive instance Newtype FilePath _
derive newtype instance Eq FilePath
derive newtype instance Ord FilePath
derive newtype instance Show FilePath

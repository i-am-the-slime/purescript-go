module Go.Error
  ( GoError
  , ErrorMessage(..)
  , message
  ) where

import Prelude

import Data.Newtype (class Newtype)

-- | A Go `error`.
foreign import data GoError :: Type

newtype ErrorMessage = ErrorMessage String

derive instance Newtype ErrorMessage _
derive newtype instance Eq ErrorMessage
derive newtype instance Show ErrorMessage

message :: GoError -> ErrorMessage
message = ErrorMessage <<< messageImpl

instance Show GoError where
  show error = "(GoError " <> show (messageImpl error) <> ")"

foreign import messageImpl :: GoError -> String

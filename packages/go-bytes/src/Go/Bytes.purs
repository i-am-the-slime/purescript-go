module Go.Bytes
  ( Bytes
  , ByteCount(..)
  , size
  , slice
  , fromString
  , toString
  , fromArray
  , toArray
  ) where

import Prelude

import Data.Newtype (class Newtype, un)

-- | A Go `[]byte`. Bytes never change: every operation that makes bytes makes new ones.
foreign import data Bytes :: Type

-- | A number of bytes. A `Number`, not an `Int`, since Go slices and files can be larger than
-- | 2^31-1 bytes.
newtype ByteCount = ByteCount Number

derive instance Newtype ByteCount _
derive newtype instance Eq ByteCount
derive newtype instance Ord ByteCount
derive newtype instance Show ByteCount

instance Eq Bytes where
  eq = eqImpl

instance Semigroup Bytes where
  append = appendImpl

instance Monoid Bytes where
  mempty = emptyImpl

instance Show Bytes where
  show bytes = "(fromArray " <> show (toArray bytes) <> ")"

size :: Bytes -> ByteCount
size bytes = ByteCount (sizeImpl bytes)

-- | The bytes from `start` up to, not including, `end`. Like JavaScript's `slice`, offsets are
-- | clamped to the bytes there are, so `slice` never fails.
slice :: ByteCount -> ByteCount -> Bytes -> Bytes
slice start end bytes = sliceImpl (un ByteCount start) (un ByteCount end) bytes

-- | The string's UTF-8 encoding. A lone surrogate, which a PureScript string can hold, becomes
-- | U+FFFD, as JavaScript's `TextEncoder` does.
fromString :: String -> Bytes
fromString = fromStringImpl

-- | The string the UTF-8 bytes encode. Each byte that is not part of valid UTF-8 becomes U+FFFD.
toString :: Bytes -> String
toString = toStringImpl

-- | Bytes from numbers between 0 and 255. Other numbers keep their lowest 8 bits.
fromArray :: Array Int -> Bytes
fromArray = fromArrayImpl

toArray :: Bytes -> Array Int
toArray = toArrayImpl

foreign import eqImpl :: Bytes -> Bytes -> Boolean
foreign import appendImpl :: Bytes -> Bytes -> Bytes
foreign import emptyImpl :: Bytes
foreign import sizeImpl :: Bytes -> Number
foreign import sliceImpl :: Number -> Number -> Bytes -> Bytes
foreign import fromStringImpl :: String -> Bytes
foreign import toStringImpl :: Bytes -> String
foreign import fromArrayImpl :: Array Int -> Bytes
foreign import toArrayImpl :: Bytes -> Array Int

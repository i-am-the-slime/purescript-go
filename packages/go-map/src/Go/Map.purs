-- | Go's built-in `map[K]V`: a mutable hash map that you read and write in `Effect`, like a
-- | `Ref`. Inserts, lookups and deletes are Go's own, so a map that a loop fills costs what it
-- | costs in Go.
-- |
-- | Keys are the types Go can hash and order: `Int`, `String`, `Char` and `Number`. Go visits a
-- | map in random order, so `entries`, `keys` and `values` sort by key to stay deterministic.
module Go.Map
  ( GoMap
  , class Key
  , new
  , newWithCapacity
  , lookup
  , member
  , insert
  , delete
  , alter
  , size
  , entries
  , keys
  , values
  ) where

import Prelude

import Effect (Effect)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested (type (/\), (/\))

foreign import data GoMap :: Type -> Type -> Type

type role GoMap nominal representational

-- | The key types Go can hash and order.
class Key :: Type -> Constraint
class Key k

instance Key Int
instance Key String
instance Key Char
instance Key Number

new :: forall k v. Key k => Effect (GoMap k v)
new = newImpl 0

-- | A map with room for this many entries before it grows.
newWithCapacity :: forall k v. Key k => Int -> Effect (GoMap k v)
newWithCapacity = newImpl

foreign import newImpl :: forall k v. Int -> Effect (GoMap k v)

lookup :: forall k v. Key k => k -> GoMap k v -> Effect (Maybe v)
lookup = lookupImpl Just Nothing

foreign import lookupImpl :: forall k v. (v -> Maybe v) -> Maybe v -> k -> GoMap k v -> Effect (Maybe v)

member :: forall k v. Key k => k -> GoMap k v -> Effect Boolean
member = memberImpl

foreign import memberImpl :: forall k v. k -> GoMap k v -> Effect Boolean

insert :: forall k v. Key k => k -> v -> GoMap k v -> Effect Unit
insert = insertImpl

foreign import insertImpl :: forall k v. k -> v -> GoMap k v -> Effect Unit

delete :: forall k v. Key k => k -> GoMap k v -> Effect Unit
delete = deleteImpl

foreign import deleteImpl :: forall k v. k -> GoMap k v -> Effect Unit

-- | Writes or deletes the key with the function's answer for what's there now.
alter :: forall k v. Key k => (Maybe v -> Maybe v) -> k -> GoMap k v -> Effect Unit
alter change key map = do
  current <- lookup key map
  case change current of
    Just value -> insert key value map
    Nothing -> delete key map

size :: forall k v. GoMap k v -> Effect Int
size = sizeImpl

foreign import sizeImpl :: forall k v. GoMap k v -> Effect Int

-- | Every key and value, sorted by key.
entries :: forall k v. Key k => GoMap k v -> Effect (Array (k /\ v))
entries = entriesImpl (/\)

foreign import entriesImpl :: forall k v. (k -> v -> k /\ v) -> GoMap k v -> Effect (Array (k /\ v))

-- | Every key, sorted.
keys :: forall k v. Key k => GoMap k v -> Effect (Array k)
keys = keysImpl

foreign import keysImpl :: forall k v. GoMap k v -> Effect (Array k)

-- | Every value, sorted by its key.
values :: forall k v. Key k => GoMap k v -> Effect (Array v)
values = valuesImpl

foreign import valuesImpl :: forall k v. GoMap k v -> Effect (Array v)

module Test.Go.BytesSpec where

import Prelude

import Go.Bytes (ByteCount(..))
import Go.Bytes as Bytes
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Go.Bytes" do
  it "encodes and decodes UTF-8" do
    let encoded = Bytes.fromString "héllo"
    Bytes.toArray encoded `shouldEqual` [ 104, 195, 169, 108, 108, 111 ]
    Bytes.size encoded `shouldEqual` ByteCount 6.0
    Bytes.toString encoded `shouldEqual` "héllo"

  it "decodes each invalid byte as U+FFFD" do
    Bytes.toString (Bytes.fromArray [ 104, 255, 105 ]) `shouldEqual` "h\xFFFDi"
    Bytes.toString (Bytes.fromArray [ 237, 160, 128 ]) `shouldEqual` "\xFFFD\xFFFD\xFFFD"

  it "encodes a lone surrogate as U+FFFD" do
    Bytes.toArray (Bytes.fromString "a\xD800z") `shouldEqual` [ 97, 239, 191, 189, 122 ]

  it "slices with clamped offsets" do
    let digits = Bytes.fromString "0123456789"
    Bytes.toString (Bytes.slice (ByteCount 2.0) (ByteCount 5.0) digits) `shouldEqual` "234"
    Bytes.toString (Bytes.slice (ByteCount (-3.0)) (ByteCount 2.0) digits) `shouldEqual` "01"
    Bytes.toString (Bytes.slice (ByteCount 8.0) (ByteCount 99.0) digits) `shouldEqual` "89"
    Bytes.size (Bytes.slice (ByteCount 5.0) (ByteCount 2.0) digits) `shouldEqual` ByteCount 0.0

  it "appends and compares" do
    (Bytes.fromString "ab" <> Bytes.fromString "cd") `shouldEqual` Bytes.fromString "abcd"
    (Bytes.fromString "ab" <> mempty) `shouldEqual` Bytes.fromString "ab"
    (Bytes.fromString "ab" == Bytes.fromString "ba") `shouldEqual` false
    show (Bytes.fromArray [ 1, 2 ]) `shouldEqual` "(fromArray [1,2])"

  it "keeps the lowest 8 bits of a number" do
    Bytes.toArray (Bytes.fromArray [ 256, 257, -1 ]) `shouldEqual` [ 0, 1, 255 ]

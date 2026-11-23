module Test.Go.Path.FilepathSpec where

import Prelude

import Data.Either (hush, isLeft)
import Data.Maybe (Maybe(..))
import Effect.Class (liftEffect)
import Go.FilePath (FilePath(..))
import Go.Path.Filepath (Extension(..), Pattern(..))
import Go.Path.Filepath as Filepath
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

spec :: Spec Unit
spec = describe "Go.Path.Filepath" do
  it "joins and cleans paths" do
    Filepath.join [ FilePath "a", FilePath "b/../c", FilePath "d.go" ] `shouldEqual` FilePath "a/c/d.go"
    Filepath.clean (FilePath "a//b/./c/..") `shouldEqual` FilePath "a/b"

  it "takes paths apart" do
    let path = FilePath "/src/Go/OS.purs"
    Filepath.base path `shouldEqual` FilePath "OS.purs"
    Filepath.dir path `shouldEqual` FilePath "/src/Go"
    Filepath.ext path `shouldEqual` Extension ".purs"
    Filepath.ext (FilePath "Makefile") `shouldEqual` Extension ""
    Filepath.isAbs path `shouldEqual` true
    Filepath.isAbs (FilePath "src") `shouldEqual` false

  it "relates paths" do
    hush (Filepath.rel (FilePath "/a/b") (FilePath "/a/c/d")) `shouldEqual` Just (FilePath "../c/d")
    Filepath.rel (FilePath "/a") (FilePath "b") `shouldSatisfy` isLeft

  it "resolves against the working directory" do
    absolute <- liftEffect (Filepath.abs (FilePath "src"))
    (Filepath.isAbs <$> hush absolute) `shouldEqual` Just true

  it "rejects a malformed glob pattern" do
    matches <- liftEffect (Filepath.glob (Pattern "[unclosed"))
    matches `shouldSatisfy` isLeft

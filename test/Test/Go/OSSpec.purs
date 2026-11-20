module Test.Go.OSSpec where

import Prelude

import Data.Array (sort)
import Data.Either (Either(..), either, isLeft)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Go.Bytes (ByteCount(..))
import Go.Bytes as Bytes
import Go.FilePath (FilePath(..))
import Go.OS (EnvName(..), EnvValue(..), FSError(..))
import Go.OS as OS
import Go.Path.Filepath as Filepath
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = describe "Go.OS" do
  it "writes, appends and reads text files" do
    directory <- scratch
    let file = Filepath.join [ directory, FilePath "hello.txt" ]
    expectRight =<< liftEffect (OS.writeFile file "hello\n")
    expectRight =<< liftEffect (OS.appendFile file "wörld\n")
    liftEffect (OS.readFile file) >>= shouldEqual' "hello\nwörld\n"

  it "writes, appends and reads bytes" do
    directory <- scratch
    let file = Filepath.join [ directory, FilePath "data.bin" ]
    expectRight =<< liftEffect (OS.writeFileBytes file (Bytes.fromArray [ 0, 255 ]))
    expectRight =<< liftEffect (OS.appendFileBytes file (Bytes.fromArray [ 7 ]))
    contents <- expectRight =<< liftEffect (OS.readFileBytes file)
    Bytes.toArray contents `shouldEqual` [ 0, 255, 7 ]

  it "knows its own binary" do
    binary <- expectRight =<< liftEffect OS.executable
    liftEffect (OS.exists binary) >>= shouldEqual true

  it "reports a missing file as NotExist with its path" do
    directory <- scratch
    let missing = Filepath.join [ directory, FilePath "missing.txt" ]
    liftEffect (OS.readFile missing) >>= case _ of
      Left (NotExist path) -> path `shouldEqual` missing
      other -> fail ("expected NotExist, got " <> either show show other)

  it "reports an existing directory as Exist" do
    directory <- scratch
    liftEffect (OS.mkdir directory) >>= case _ of
      Left (Exist path) -> path `shouldEqual` directory
      other -> fail ("expected Exist, got " <> either show show other)

  it "creates, lists, renames and removes directories" do
    directory <- scratch
    let nested = Filepath.join [ directory, FilePath "a", FilePath "b" ]
    expectRight =<< liftEffect (OS.mkdirAll nested)
    expectRight =<< liftEffect (OS.writeFile (Filepath.join [ directory, FilePath "z.txt" ]) "z")
    entries <- expectRight =<< liftEffect (OS.readDir directory)
    sort (map OS.entryName entries) `shouldEqual` [ FilePath "a", FilePath "z.txt" ]
    map OS.entryIsDir entries `shouldEqual` [ true, false ]
    let renamed = Filepath.join [ directory, FilePath "c" ]
    expectRight =<< liftEffect (OS.rename (Filepath.join [ directory, FilePath "a" ]) renamed)
    liftEffect (OS.exists nested) >>= shouldEqual false
    expectRight =<< liftEffect (OS.removeAll renamed)
    liftEffect (OS.exists renamed) >>= shouldEqual false

  it "describes a file" do
    directory <- scratch
    let file = Filepath.join [ directory, FilePath "five.txt" ]
    expectRight =<< liftEffect (OS.writeFile file "12345")
    info <- expectRight =<< liftEffect (OS.stat file)
    OS.name info `shouldEqual` FilePath "five.txt"
    OS.size info `shouldEqual` ByteCount 5.0
    OS.isDir info `shouldEqual` false

  it "reads and changes environment variables" do
    let variable = EnvName "GO_OS_SPEC_VARIABLE"
    liftEffect (OS.lookupEnv variable) >>= shouldEqual Nothing
    liftEffect (OS.setenv variable (EnvValue "set"))
    liftEffect (OS.lookupEnv variable) >>= shouldEqual (Just (EnvValue "set"))
    liftEffect (OS.unsetenv variable)
    liftEffect (OS.lookupEnv variable) >>= shouldEqual Nothing

  it "changes the working directory" do
    directory <- scratch
    before <- expectRight =<< liftEffect OS.getwd
    expectRight =<< liftEffect (OS.chdir directory)
    inside <- expectRight =<< liftEffect OS.getwd
    Filepath.base inside `shouldEqual` Filepath.base directory
    expectRight =<< liftEffect (OS.chdir before)
    missing <- liftEffect (OS.chdir (Filepath.join [ directory, FilePath "missing" ]))
    isLeft missing `shouldEqual` true
  where
  shouldEqual' :: forall a. Show a => Eq a => a -> Either FSError a -> Aff Unit
  shouldEqual' expected actual = expectRight actual >>= shouldEqual expected

expectRight :: forall a. Either FSError a -> Aff a
expectRight = either (liftEffect <<< throw <<< show) pure

-- | A new, empty directory under the system's temporary directory.
scratch :: Aff FilePath
scratch = liftEffect do
  temporary <- OS.tempDir
  created <- OS.mkdirTemp temporary "go-os-spec-"
  either (throw <<< show) pure created

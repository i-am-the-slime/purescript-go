module Test.Go.Net.HTTPSpec where

import Prelude

import Data.Either (Either, either, isLeft)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Newtype (un)
import Effect (Effect)
import Effect.Aff (Aff, bracket)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Go.Error (GoError)
import Go.Net.HTTP (Address(..), ClientResponse, Handler, HeaderName(..), HeaderValue(..), Method(..), Path(..), QueryName(..), Request, Response, Status(..), URL(..))
import Go.Net.HTTP as HTTP
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Go.Net.HTTP" do
  it "serves a handler and answers a GET" do
    withServer (pure <<< greet) \url -> do
      answer <- fetched (HTTP.get (url "/hello?name=gopher"))
      HTTP.status answer `shouldEqual` Status 200
      HTTP.responseBody answer `shouldEqual` "hello gopher"
      HTTP.responseHeader (HeaderName "content-type") answer `shouldEqual` Just (HeaderValue "text/plain")

  it "passes the method, headers and body" do
    withServer echo \url -> do
      let
        request = (HTTP.clientRequest (Method "POST") (url "/echo"))
          { headers = [ { name: HeaderName "X-Token", value: HeaderValue "secret" } ]
          , body = "payload"
          }
      answer <- fetched (HTTP.send request)
      HTTP.responseBody answer `shouldEqual` "POST /echo secret payload"

  it "answers an error status as a response" do
    withServer (pure <<< greet) \url -> do
      answer <- fetched (HTTP.get (url "/missing"))
      HTTP.status answer `shouldEqual` Status 404

  it "fails to reach a server that is not there" do
    unreachable <- liftEffect (HTTP.get (URL "http://127.0.0.1:1/"))
    isLeft unreachable `shouldEqual` true

greet :: Request -> Response
greet request = case HTTP.path request of
  Path "/hello" ->
    HTTP.withHeader (HeaderName "Content-Type") (HeaderValue "text/plain")
      (HTTP.ok ("hello " <> fromMaybe "stranger" (HTTP.query (QueryName "name") request)))
  _ -> HTTP.notFound

echo :: Request -> Effect Response
echo request = do
  text <- HTTP.body request >>= either (throw <<< show) pure
  pure (HTTP.ok (words [ un Method (HTTP.method request), un Path (HTTP.path request), token, text ]))
  where
  token = maybe "" (un HeaderValue) (HTTP.header (HeaderName "x-token") request)
  words = case _ of
    [ a, b, c, d ] -> a <> " " <> b <> " " <> c <> " " <> d
    _ -> ""

-- | Runs the test against a server on a free port, given a way to build its URLs.
withServer :: Handler -> ((String -> URL) -> Aff Unit) -> Aff Unit
withServer handler test = bracket started (liftEffect <<< HTTP.shutdown) \server ->
  test \route -> URL ("http://" <> un Address (HTTP.serverAddress server) <> route)
  where
  started = fetched (HTTP.start (Address "127.0.0.1:0") handler)

fetched :: forall a. Effect (Either GoError a) -> Aff a
fetched request = liftEffect request >>= either (liftEffect <<< throw <<< show) pure

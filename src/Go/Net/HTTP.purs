module Go.Net.HTTP
  ( Address(..)
  , Method(..)
  , Path(..)
  , URL(..)
  , Status(..)
  , HeaderName(..)
  , HeaderValue(..)
  , QueryName(..)
  , Request
  , Response
  , Handler
  , Server
  , Header
  , ClientRequest
  , ClientResponse
  , listenAndServe
  , start
  , serverAddress
  , shutdown
  , method
  , path
  , query
  , header
  , body
  , bodyBytes
  , response
  , responseBytes
  , withHeader
  , ok
  , notFound
  , get
  , clientRequest
  , send
  , status
  , responseHeader
  , responseHeaders
  , responseURL
  , responseBody
  , responseBodyBytes
  ) where

import Prelude

import Data.Either (Either(..), either)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, un)
import Effect (Effect)
import Effect.Aff (Aff, attempt, launchAff_, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Go.Bytes (Bytes)
import Go.Error (GoError)

-- | Where a server listens: `:8080`, or `localhost:0` for any free port.
newtype Address = Address String

derive instance Newtype Address _
derive newtype instance Eq Address
derive newtype instance Show Address

newtype Method = Method String

derive instance Newtype Method _
derive newtype instance Eq Method
derive newtype instance Show Method

newtype Path = Path String

derive instance Newtype Path _
derive newtype instance Eq Path
derive newtype instance Show Path

newtype URL = URL String

derive instance Newtype URL _
derive newtype instance Eq URL
derive newtype instance Show URL

newtype Status = Status Int

derive instance Newtype Status _
derive newtype instance Eq Status
derive newtype instance Ord Status
derive newtype instance Show Status

-- | A header name. Lookups ignore its case.
newtype HeaderName = HeaderName String

derive instance Newtype HeaderName _
derive newtype instance Eq HeaderName
derive newtype instance Show HeaderName

newtype HeaderValue = HeaderValue String

derive instance Newtype HeaderValue _
derive newtype instance Eq HeaderValue
derive newtype instance Show HeaderValue

newtype QueryName = QueryName String

derive instance Newtype QueryName _
derive newtype instance Show QueryName

-- | A request a server received.
foreign import data Request :: Type

-- | What a handler answers with.
foreign import data Response :: Type

-- | Answers a request. Handlers of different requests take turns: while one waits, say on
-- | `send` or `delay`, the others run.
type Handler = Request -> Aff Response

-- | A server listening in the background.
foreign import data Server :: Type

type Header = { name :: HeaderName, value :: HeaderValue }

-- | What `send` sends.
type ClientRequest =
  { method :: Method
  , url :: URL
  , headers :: Array Header
  , body :: String
  }

-- | What a server answered `send`.
foreign import data ClientResponse :: Type

-- | Serves requests until the server fails, and returns why.
listenAndServe :: Address -> Handler -> Aff GoError
listenAndServe address handler =
  makeAff \stopped -> listenAndServeImpl (un Address address) (answer handler) (stopped <<< Right) $> nonCanceler

-- | Starts listening, and serves requests in the background until `shutdown`. Until then, the
-- | server keeps the program running.
start :: Address -> Handler -> Effect (Either GoError Server)
start address handler = startImpl Left Right (un Address address) (answer handler)

-- | The address the server listens on, with the port it was given for `:0`.
serverAddress :: Server -> Address
serverAddress server = Address (serverAddressImpl server)

-- | Stops listening and waits for the requests in flight.
shutdown :: Server -> Aff Unit
shutdown server = makeAff \finished -> shutdownImpl server (finished (Right unit)) $> nonCanceler

-- | Runs the handler and hands its response over. A handler that fails answers 500.
answer :: Handler -> Request -> (Response -> Effect Unit) -> Effect Unit
answer handler request respond = launchAff_ do
  result <- attempt (handler request)
  liftEffect (respond (either (const internalServerError) identity result))
  where
  internalServerError = response (Status 500) "500 internal server error\n"

method :: Request -> Method
method request = Method (methodImpl request)

path :: Request -> Path
path request = Path (pathImpl request)

-- | The first value of the query parameter.
query :: QueryName -> Request -> Maybe String
query name request = queryImpl Nothing Just (un QueryName name) request

-- | The first value of the header.
header :: HeaderName -> Request -> Maybe HeaderValue
header name request = headerImpl Nothing (Just <<< HeaderValue) (un HeaderName name) request

-- | Reads the whole request body.
body :: Request -> Effect (Either GoError String)
body request = bodyImpl Left Right request

-- | Reads the whole request body.
bodyBytes :: Request -> Effect (Either GoError Bytes)
bodyBytes request = bodyBytesImpl Left Right request

response :: Status -> String -> Response
response code text = responseImpl (un Status code) text

responseBytes :: Status -> Bytes -> Response
responseBytes code data_ = responseBytesImpl (un Status code) data_

withHeader :: HeaderName -> HeaderValue -> Response -> Response
withHeader name value answer = withHeaderImpl (un HeaderName name) (un HeaderValue value) answer

ok :: String -> Response
ok = response (Status 200)

notFound :: Response
notFound = response (Status 404) "404 page not found\n"

-- | A GET request without headers or body.
clientRequest :: Method -> URL -> ClientRequest
clientRequest requestMethod url = { method: requestMethod, url, headers: [], body: "" }

get :: URL -> Aff (Either GoError ClientResponse)
get url = send (clientRequest (Method "GET") url)

-- | Sends the request and reads the whole response. An error status is a response, not an error.
-- | The fiber waits for the answer without blocking the program: other fibers, and the handlers
-- | of a server in the same program, run meanwhile.
send :: ClientRequest -> Aff (Either GoError ClientResponse)
send request = makeAff \resolve -> sendImpl Left Right request (resolve <<< Right) $> nonCanceler

status :: ClientResponse -> Status
status answer = Status (statusImpl answer)

responseHeader :: HeaderName -> ClientResponse -> Maybe HeaderValue
responseHeader name answer =
  responseHeaderImpl Nothing (Just <<< HeaderValue) (un HeaderName name) answer

-- | Every header of the response, in the order Go sorts them, one entry per value. Names are in
-- | Go's canonical form, such as `Content-Type`.
responseHeaders :: ClientResponse -> Array Header
responseHeaders = responseHeadersImpl

-- | Where the response came from, after following redirects.
responseURL :: ClientResponse -> URL
responseURL answer = URL (responseURLImpl answer)

-- | The body as UTF-8 text. Each byte that is not part of valid UTF-8 becomes U+FFFD.
responseBody :: ClientResponse -> String
responseBody = responseBodyImpl

responseBodyBytes :: ClientResponse -> Bytes
responseBodyBytes = responseBodyBytesImpl

foreign import listenAndServeImpl
  :: String -> (Request -> (Response -> Effect Unit) -> Effect Unit) -> (GoError -> Effect Unit) -> Effect Unit
foreign import startImpl
  :: forall r
   . (GoError -> r)
  -> (Server -> r)
  -> String
  -> (Request -> (Response -> Effect Unit) -> Effect Unit)
  -> Effect r
foreign import serverAddressImpl :: Server -> String
foreign import shutdownImpl :: Server -> Effect Unit -> Effect Unit
foreign import methodImpl :: Request -> String
foreign import pathImpl :: Request -> String
foreign import queryImpl :: forall r. r -> (String -> r) -> String -> Request -> r
foreign import headerImpl :: forall r. r -> (String -> r) -> String -> Request -> r
foreign import bodyImpl :: forall r. (GoError -> r) -> (String -> r) -> Request -> Effect r
foreign import bodyBytesImpl :: forall r. (GoError -> r) -> (Bytes -> r) -> Request -> Effect r
foreign import responseImpl :: Int -> String -> Response
foreign import responseBytesImpl :: Int -> Bytes -> Response
foreign import withHeaderImpl :: String -> String -> Response -> Response
foreign import sendImpl
  :: forall r. (GoError -> r) -> (ClientResponse -> r) -> ClientRequest -> (r -> Effect Unit) -> Effect Unit
foreign import statusImpl :: ClientResponse -> Int
foreign import responseHeaderImpl :: forall r. r -> (String -> r) -> String -> ClientResponse -> r
foreign import responseHeadersImpl :: ClientResponse -> Array Header
foreign import responseURLImpl :: ClientResponse -> String
foreign import responseBodyImpl :: ClientResponse -> String
foreign import responseBodyBytesImpl :: ClientResponse -> Bytes

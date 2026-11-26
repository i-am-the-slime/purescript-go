package ffi

import (
	"context"
	"io"
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"unicode/utf8"

	"github.com/i-am-the-slime/iris-go/eventloop"
)

type Request = *http.Request

// ResponseType is what a handler answers with. Adding a header copies it.
type ResponseType struct {
	status int
	header http.Header
	body   []byte
}

type Server struct {
	server   *http.Server
	listener net.Listener
	retire   func()
	stopped  *sync.Once
}

type ClientResponse struct {
	status int
	header http.Header
	body   []byte
	url    string
}

// ListenAndServeImpl serves in the background and resumes the fiber with the reason once the
// server stops. Until then it keeps the program running.
func ListenAndServeImpl(address string, handler func(*http.Request) func(func(ResponseType)), stopped func(error)) {
	retire := eventloop.Hold()
	go func() {
		stopped(http.ListenAndServe(address, serve(handler)))
		retire()
	}()
}

// StartImpl listens and serves in the background, keeping the program running until
// ShutdownImpl.
func StartImpl[R any](failed func(error) R, started func(Server) R, address string, handler func(*http.Request) func(func(ResponseType))) R {
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return failed(err)
	}
	server := &http.Server{Handler: serve(handler)}
	running := Server{server: server, listener: listener, retire: eventloop.Hold(), stopped: &sync.Once{}}
	go server.Serve(listener)
	return started(running)
}

func ServerAddressImpl(server Server) string { return server.listener.Addr().String() }

// ShutdownImpl stops listening, waits for the requests in flight off the event loop, and then
// resumes the fiber.
func ShutdownImpl(server Server, finished func()) {
	retire := eventloop.Hold()
	go func() {
		server.server.Shutdown(context.Background())
		finished()
		server.stopped.Do(server.retire)
		retire()
	}()
}

func MethodImpl(request *http.Request) string { return request.Method }

func PathImpl(request *http.Request) string { return request.URL.Path }

func QueryImpl[R any](missing R, found func(string) R, name string, request *http.Request) R {
	values, ok := request.URL.Query()[name]
	if !ok || len(values) == 0 {
		return missing
	}
	return found(values[0])
}

func HeaderImpl[R any](missing R, found func(string) R, name string, request *http.Request) R {
	values := request.Header.Values(name)
	if len(values) == 0 {
		return missing
	}
	return found(values[0])
}

func BodyImpl[R any](failed func(error) R, read func(string) R, request *http.Request) R {
	data, err := io.ReadAll(request.Body)
	if err != nil {
		return failed(err)
	}
	return read(text(data))
}

func BodyBytesImpl[R any](failed func(error) R, read func([]byte) R, request *http.Request) R {
	data, err := io.ReadAll(request.Body)
	if err != nil {
		return failed(err)
	}
	return read(data)
}

func ResponseImpl(status int, body string) ResponseType {
	return ResponseType{status: status, header: http.Header{}, body: []byte(body)}
}

func ResponseBytesImpl(status int, body []byte) ResponseType {
	return ResponseType{status: status, header: http.Header{}, body: body}
}

func WithHeaderImpl(name string, value string, response ResponseType) ResponseType {
	header := response.header.Clone()
	header.Add(name, value)
	return ResponseType{status: response.status, header: header, body: response.body}
}

type Header struct {
	Name  string
	Value string
}

type ClientRequest struct {
	Method  string
	Url     string
	Headers []Header
	Body    string
}

// SendImpl sends the request on a goroutine of its own and resumes the fiber with the result, so
// other fibers, and the handlers of a server in the same program, keep running meanwhile.
func SendImpl[R any](failed func(error) R, received func(ClientResponse) R, outgoing ClientRequest, finished func(R)) {
	retire := eventloop.Hold()
	go func() {
		answer, err := exchange(outgoing)
		if err != nil {
			finished(failed(err))
		} else {
			finished(received(answer))
		}
		retire()
	}()
}

func exchange(outgoing ClientRequest) (ClientResponse, error) {
	request, err := http.NewRequest(outgoing.Method, outgoing.Url, strings.NewReader(outgoing.Body))
	if err != nil {
		return ClientResponse{}, err
	}
	for _, header := range outgoing.Headers {
		request.Header.Add(header.Name, header.Value)
	}
	answer, err := http.DefaultClient.Do(request)
	if err != nil {
		return ClientResponse{}, err
	}
	defer answer.Body.Close()
	data, err := io.ReadAll(answer.Body)
	if err != nil {
		return ClientResponse{}, err
	}
	return ClientResponse{status: answer.StatusCode, header: answer.Header, body: data, url: answer.Request.URL.String()}, nil
}

func StatusImpl(response ClientResponse) int { return response.status }

func ResponseHeaderImpl[R any](missing R, found func(string) R, name string, response ClientResponse) R {
	values := response.header.Values(name)
	if len(values) == 0 {
		return missing
	}
	return found(values[0])
}

func ResponseHeadersImpl(response ClientResponse) []Header {
	names := make([]string, 0, len(response.header))
	for name := range response.header {
		names = append(names, name)
	}
	sort.Strings(names)
	headers := []Header{}
	for _, name := range names {
		for _, value := range response.header[name] {
			headers = append(headers, Header{Name: name, Value: value})
		}
	}
	return headers
}

func ResponseURLImpl(response ClientResponse) string { return response.url }

func ResponseBodyImpl(response ClientResponse) string { return text(response.body) }

func ResponseBodyBytesImpl(response ClientResponse) []byte { return response.body }

// serve calls the handler, an IO action, on each request's goroutine and waits there for the
// response.
func serve(handler func(*http.Request) func(func(ResponseType))) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		answered := make(chan ResponseType, 1)
		handler(request)(func(response ResponseType) { answered <- response })
		response := <-answered
		for name, values := range response.header {
			for _, value := range values {
				writer.Header().Add(name, value)
			}
		}
		writer.WriteHeader(response.status)
		writer.Write(response.body)
	})
}

// text decodes UTF-8, replacing each byte that is not part of a valid encoding with U+FFFD, as
// Go.Bytes.toString does.
func text(data []byte) string {
	if utf8.Valid(data) {
		return string(data)
	}
	var decoded strings.Builder
	for len(data) > 0 {
		character, width := utf8.DecodeRune(data)
		decoded.WriteRune(character)
		data = data[width:]
	}
	return decoded.String()
}

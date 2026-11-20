package ffi

import (
	"context"
	"io"
	"net"
	"net/http"
	"strings"
)

type Request = *http.Request

// ResponseType is what a handler answers with. Adding a header copies it.
type ResponseType struct {
	status int32
	header http.Header
	body   string
}

type Server struct {
	server   *http.Server
	listener net.Listener
}

type ClientResponse struct {
	status int32
	header http.Header
	body   string
}

func ListenAndServeImpl(address string, handler func(*http.Request) ResponseType) error {
	return http.ListenAndServe(address, serve(handler))
}

func StartImpl[R any](failed func(error) R, started func(Server) R, address string, handler func(*http.Request) ResponseType) R {
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return failed(err)
	}
	server := &http.Server{Handler: serve(handler)}
	go server.Serve(listener)
	return started(Server{server: server, listener: listener})
}

func ServerAddressImpl(server Server) string { return server.listener.Addr().String() }

func ShutdownImpl(server Server) { server.server.Shutdown(context.Background()) }

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
	return read(string(data))
}

func ResponseImpl(status int32, body string) ResponseType {
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

func SendImpl[R any](failed func(error) R, received func(ClientResponse) R, outgoing ClientRequest) R {
	request, err := http.NewRequest(outgoing.Method, outgoing.Url, strings.NewReader(outgoing.Body))
	if err != nil {
		return failed(err)
	}
	for _, header := range outgoing.Headers {
		request.Header.Add(header.Name, header.Value)
	}
	answer, err := http.DefaultClient.Do(request)
	if err != nil {
		return failed(err)
	}
	defer answer.Body.Close()
	data, err := io.ReadAll(answer.Body)
	if err != nil {
		return failed(err)
	}
	return received(ClientResponse{status: int32(answer.StatusCode), header: answer.Header, body: string(data)})
}

func StatusImpl(response ClientResponse) int32 { return response.status }

func ResponseHeaderImpl[R any](missing R, found func(string) R, name string, response ClientResponse) R {
	values := response.header.Values(name)
	if len(values) == 0 {
		return missing
	}
	return found(values[0])
}

func ResponseBodyImpl(response ClientResponse) string { return response.body }

func serve(handler func(*http.Request) ResponseType) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		response := handler(request)
		for name, values := range response.header {
			for _, value := range values {
				writer.Header().Add(name, value)
			}
		}
		writer.WriteHeader(int(response.status))
		io.WriteString(writer, response.body)
	})
}

# typed_openapi_transport_tests

The conformance suite of typed_openapi transports (not published). Every
`ClientTransport` runs the same cases against a loopback HTTP server that
the suite starts in a hybrid isolate, so the cases also run in a browser:

```dart
void main() {
  TransportConformance(
    (baseUrl) => DioTransport(Dio(BaseOptions(baseUrl: '$baseUrl'))),
    skips: {'<case name>': '<why this transport cannot meet it>'},
  ).register();
}
```

A skip must name a case (a test checks it) and say why. The `createWithTimeout`
factory is optional: without it the timeout case is skipped.

The cases cover:

- requests: method, target and headers, a header given twice, PUT, PATCH and
  DELETE, JSON, form and streamed bodies, send progress;
- multipart: the exact bytes of a body with a fixed boundary, a typed part, a
  text part after it and a file from a stream;
- responses: error and undocumented statuses, headers, binary bodies, receive
  progress;
- statuses: 201, 204, an empty 200, 422, 500, 503 and `HEAD`;
- redirects: a 301 and a 302 are followed (the policy is the transport's; the
  cases document a transport that follows them);
- streaming: a 4 MiB chunked body, a cancel while a body is coming;
- failures: a refused connection, a server that closes the socket, a timeout,
  a cancel before a call (nothing is sent) and in flight;
- event streams: events that reconnect with `Last-Event-ID`, pieces that split
  a line and a character, `retry:`, a 204, an error status with a body and a
  listener cancel (the server sees the connection close).

Not covered yet: upload and download progress beyond the counts above,
`Transfer-Encoding` of requests, and cookies.

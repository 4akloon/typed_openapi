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

A skip must name a case (a test checks it) and say why. The cases cover the
method, target and headers, JSON, form, multipart and streamed bodies, send
and receive progress, error and undocumented statuses, binary bodies, a
refused connection, a cancel before and during a call, and an event stream
that reconnects with `Last-Event-ID` and ends on cancel.

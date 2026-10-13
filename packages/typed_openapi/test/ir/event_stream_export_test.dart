import 'package:test/test.dart';
import 'package:typed_openapi/typed_openapi.dart';

void main() {
  test('the IR types of an event stream are part of the public API', () {
    expect(
      [EventStreamIr, EventUnionIr, EventVariantIr, StreamReconnection],
      hasLength(4),
    );
    expect(StreamReconnection.values, contains(StreamReconnection.onRequest));
  });
}

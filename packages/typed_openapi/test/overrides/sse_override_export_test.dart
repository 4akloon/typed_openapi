import 'package:test/test.dart';
import 'package:typed_openapi/typed_openapi.dart';

void main() {
  test('the sse override is part of the public overrides API', () {
    final operation = OverrideLoader(DiagnosticBag())
        .parse('''
operations:
  feed: {sse: {method: only}}
''', 'o.yaml')!
        .operations
        .single;
    final SseOverride? sse = operation.sse;
    expect(sse?.method, SseMethod.only);
  });
}

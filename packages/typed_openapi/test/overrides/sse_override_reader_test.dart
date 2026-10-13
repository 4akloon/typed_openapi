import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/sse_override.dart';

/// The `sse` field of operation `chat` in an overrides file whose `sse` is
/// [sse] (YAML), with the diagnostics in [bag].
SseOverride? _read(String sse, DiagnosticBag bag) {
  final set = OverrideLoader(
    bag,
  ).parse('operations:\n  chat:\n    sse: $sse\n', 'o.yaml')!;
  return set.operations.single.sse;
}

void main() {
  test('reads every key; a name is a reference to a component', () {
    final bag = DiagnosticBag();
    final sse = _read(
      '{data: ChatChunk, unknown: ignore, reconnect: true, method: only}',
      bag,
    )!;
    expect(bag.all, isEmpty);
    expect(sse.data, {r'$ref': '#/components/schemas/ChatChunk'});
    expect(sse.events, isNull);
    expect(sse.keepUnknown, isFalse);
    expect(sse.reconnect, isTrue);
    expect(sse.method, SseMethod.only);
    expect(sse.pointer.value, '#/operations/chat/sse');
  });

  test('events keep their order; null is an event without data', () {
    final bag = DiagnosticBag();
    final sse = _read(
      '{events: {delta: Delta, done: null, note: {type: string}}}',
      bag,
    )!;
    expect(bag.all, isEmpty);
    expect(sse.events, {
      'delta': {r'$ref': '#/components/schemas/Delta'},
      'done': null,
      'note': {'type': 'string'},
    });
  });

  test('a component key is escaped as a pointer and a URI', () {
    final bag = DiagnosticBag();
    final sse = _read("{data: 'a/b~c d%'}", bag)!;
    expect(sse.data, {r'$ref': '#/components/schemas/a~1b~0c%20d%25'});
  });

  test('data with events is an error and neither is kept', () {
    final bag = DiagnosticBag();
    final sse = _read('{data: A, events: {a: A}}', bag)!;
    expect(sse.data, isNull);
    expect(sse.events, isNull);
    expect(
      [for (final d in bag.all) (d.code, d.pointer?.value)],
      [(DiagnosticCode.invalidOverride, '#/operations/chat/sse')],
    );
  });

  test('bad values are TOA802, unknown keys TOA803 with a suggestion', () {
    final bag = DiagnosticBag();
    final sse = _read(
      '{recconect: true, method: all, unknown: drop, events: {}, data: 3}',
      bag,
    )!;
    expect(sse.method, isNull);
    expect(sse.keepUnknown, isNull);
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.unknownOverrideKey, '#/operations/chat/sse/recconect'),
        (DiagnosticCode.invalidOverride, '#/operations/chat/sse/method'),
        (DiagnosticCode.invalidOverride, '#/operations/chat/sse/unknown'),
        (DiagnosticCode.invalidOverride, '#/operations/chat/sse/events'),
        (DiagnosticCode.invalidOverride, '#/operations/chat/sse/data'),
      ],
    );
    expect(bag.all.first.fix, contains('Did you mean "reconnect"?'));
  });
}

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/config_loader.dart';
import 'package:typed_openapi_core/src/config/project_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  List<ClientConfig> load(String text, DiagnosticBag bag) =>
      ConfigLoader(bag).load(TempDir().write('c.yaml', text))!.clients;

  test('event streams: suffix Stream and no reconnection by default', () {
    final bag = DiagnosticBag();
    final config = load('''
clients:
  a: {input: a.json, output: lib/a}
''', bag).single.generation;
    expect(bag.all, isEmpty);
    expect(config.streamSuffix, 'Stream');
    expect(config.streamReconnect, isFalse);
  });

  test('a client overrides the stream settings of defaults', () {
    final bag = DiagnosticBag();
    final clients = load('''
defaults:
  naming: {stream_suffix: Events}
  sse: {reconnect: true}
clients:
  a: {input: a.json, output: lib/a}
  b:
    input: b.json
    output: lib/b
    naming: {stream_suffix: Live2}
    sse: {reconnect: false}
''', bag);
    expect(bag.all, isEmpty);
    expect(clients[0].generation.streamSuffix, 'Events');
    expect(clients[0].generation.streamReconnect, isTrue);
    expect(clients[1].generation.streamSuffix, 'Live2');
    expect(clients[1].generation.streamReconnect, isFalse);
    expect(
      clients[0].generation.key,
      isNot(clients[1].generation.key),
    );
  });

  test('bad stream settings are TOA902 and the defaults are used', () {
    final bag = DiagnosticBag();
    final config = load('''
clients:
  a:
    input: a.json
    output: lib/a
    naming: {stream_suffix: _live}
    sse: {reconnect: 'yes', retry: 3}
''', bag).single.generation;
    expect(config.streamSuffix, 'Stream');
    expect(config.streamReconnect, isFalse);
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.configInvalid, '#/clients/a/naming/stream_suffix'),
        (DiagnosticCode.configInvalid, '#/clients/a/sse/reconnect'),
        (DiagnosticCode.configUnknownKey, '#/clients/a/sse/retry'),
      ],
    );
  });

  group('naming.stream_suffix', () {
    String suffixOf(String value, DiagnosticBag bag) => load('''
clients:
  a:
    input: a.json
    output: lib/a
    naming: {stream_suffix: "$value"}
''', bag).single.generation.streamSuffix;

    for (final bad in [
      'live',
      'Live_x',
      'Live x',
      r'Live$',
      'Évé',
      'Li-ve',
      '',
      '_',
    ]) {
      test('"$bad" is TOA902 and Stream is used', () {
        final bag = DiagnosticBag();
        expect(suffixOf(bad, bag), 'Stream');
        expect(
          [for (final d in bag.all) d.code],
          [DiagnosticCode.configInvalid],
        );
      });
    }

    for (final good in ['1x', 'Live', 'LIVE2', '9']) {
      test('"$good" is kept', () {
        final bag = DiagnosticBag();
        expect(suffixOf(good, bag), good);
        expect(bag.all, isEmpty);
      });
    }
  });
}

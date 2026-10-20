import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:yaml/yaml.dart';

import '../helpers/compose_fixture.dart';

void main() {
  const limit = Timeout(Duration(seconds: 60));
  const fixture = ComposeFixture();
  final compose = fixture.compose;

  test('the composed tree matches package:yaml on random block and flow '
      'documents (fixed seed)', () {
    final random = Random(7);
    const tokens = [
      'k: ',
      'j: ',
      '- ',
      '[',
      ']',
      '{',
      '}',
      ', ',
      'v',
      '1',
      '"q"',
      "'s'",
      '~',
      'true',
      '2.5',
      '&b ',
      '*a',
      ': ',
      '? ',
      '|',
      '#c',
      ' ',
    ];
    var compared = 0;
    for (var i = 0; i < 20000; i++) {
      final lines = List.generate(1 + random.nextInt(4), (_) {
        final line = StringBuffer(' ' * (2 + random.nextInt(3)));
        for (var t = 1 + random.nextInt(5); t > 0; t--) {
          line.write(tokens[random.nextInt(tokens.length)]);
        }
        return '$line';
      });
      final text = 'x-a: &a [1, 2]\nx-z:\n${lines.join('\n')}\n';
      final YamlNode node;
      try {
        node = loadYamlNode(text);
        // package:yaml's own scanner asserts on some invalid documents; the
        // comparison skips them (the copy reports a syntax error).
        // ignore: avoid_catching_errors
      } on AssertionError {
        continue;
      } on YamlException {
        continue;
      }
      final expected = _failsafeKeys(node);
      if (expected == _skip) continue;
      final (result, bag) = compose(text);
      expect(
        bag.all.where((d) => d.code != DiagnosticCode.nullKey),
        isEmpty,
        reason: text,
      );
      expect(result!.root, expected, reason: text);
      compared++;
    }
    expect(compared, greaterThan(1000));
  }, timeout: limit);
}

const _skip = Object();

/// An anchor or a tag in front of a scalar's text.
final _properties = RegExp(r'^(?:[&!]\S*(?:\s+|$))+');

/// The plain value of [node] with keys as their Failsafe text, or [_skip]
/// when a key is a collection or two keys are one JSON key.
Object? _failsafeKeys(YamlNode node) {
  switch (node) {
    case YamlMap():
      final map = <String, Object?>{};
      for (final MapEntry(:key, value: entry) in node.nodes.entries) {
        final keyNode = key as YamlNode;
        if (keyNode is! YamlScalar) return _skip;
        final value = keyNode.value;
        final name = value is String
            ? value
            : keyNode.span.text.replaceFirst(_properties, '').trim();
        if (map.containsKey(name)) return _skip;
        final converted = _failsafeKeys(entry);
        if (converted == _skip) return _skip;
        map[name] = converted;
      }
      return map;
    case YamlList():
      final list = <Object?>[];
      for (final item in node.nodes) {
        final converted = _failsafeKeys(item);
        if (converted == _skip) return _skip;
        list.add(converted);
      }
      return list;
    default:
      return node.value;
  }
}

import 'dart:collection';
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_openapi/src/load/yaml_event_guard.dart';
import 'package:yaml/yaml.dart';

void main() {
  /// Whether an alias is inside a mapping key of [root], read from the tree
  /// `loadYamlNode` builds (aliases share the node of their anchor): walk the
  /// tree in document order, and a node reached a second time while inside a
  /// key is an alias in that key. Empty scalars are ignored: the loader
  /// shares one node for them.
  bool aliasInKey(YamlNode root) {
    final seen = HashSet<YamlNode>.identity();
    bool walk(YamlNode node, {required bool inKey}) {
      if (node is YamlScalar && node.value == null) return false;
      if (!seen.add(node)) return inKey;
      return switch (node) {
        YamlMap() => node.nodes.entries.any(
          (e) =>
              walk(e.key as YamlNode, inKey: true) ||
              walk(e.value, inKey: inKey),
        ),
        YamlList() => node.nodes.any((e) => walk(e, inKey: inKey)),
        _ => false,
      };
    }

    return walk(root, inKey: false);
  }

  test('the guard reports exactly the documents where an alias is inside a '
      'key (fixed-seed fuzz against the loaded tree)', () {
    final random = Random(11);
    const tokens = [
      '- ',
      '? ',
      ': ',
      'k: ',
      'j: ',
      '&b ',
      '*a',
      '*a ',
      '*b',
      '[',
      ']',
      '{',
      '}',
      ', ',
      'v',
      'k',
      '|',
      '>',
      '"q"',
      "'s'",
      '"',
      "'",
      '#c',
      '!!str ',
      '!!seq ',
      ' ',
      '*a : ',
      '? *a',
      '[*a]',
      '{*a: 1}',
      '[*a]: ',
      '{a: *a}: ',
      ':',
      '?',
      '-',
      '&c ',
      'x y',
      '] : ',
      ':#',
      '?"',
      ":'",
      '?#',
      ' --- ',
      '---',
      '\t',
    ];
    const indents = ['', ' ', '  ', '   ', '    '];
    var rejected = 0;
    var accepted = 0;
    for (var i = 0; i < 300000; i++) {
      final lines = List.generate(2 + random.nextInt(5), (_) {
        final line = StringBuffer(indents[random.nextInt(indents.length)]);
        for (var t = 1 + random.nextInt(5); t > 0; t--) {
          line.write(tokens[random.nextInt(tokens.length)]);
        }
        return '  $line';
      });
      final text = 'x-a: &a [1, 2]\nx-z:\n${lines.join('\n')}\n';
      final YamlNode root;
      try {
        root = loadYamlNode(text);
        // The parser's own assertions fire on some invalid documents.
        // ignore: avoid_catching_errors
      } on AssertionError {
        continue;
      } on YamlException {
        continue;
      }
      final found = const YamlEventGuard().check(text);
      expect(
        found?.problem,
        aliasInKey(root) ? GuardProblem.aliasInKey : isNull,
        reason: text,
      );
      found == null ? accepted++ : rejected++;
    }
    expect(rejected, greaterThan(100));
    expect(accepted, greaterThan(1000));
  }, timeout: const Timeout(Duration(seconds: 120)));
}

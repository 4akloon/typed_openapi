import 'dart:collection';
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';
import 'package:yaml/yaml.dart';

void main() {
  // Oracle: what package:yaml makes of the text. A key is dangerous when it
  // is, or contains, a collection that occurs more than once in the document
  // (an alias the parser has to hash as a tree).
  Iterable<YamlNode> children(YamlNode node) => switch (node) {
    YamlMap() => node.nodes.entries.expand((e) => [e.key as YamlNode, e.value]),
    YamlList() => node.nodes,
    _ => const [],
  };

  test('the scan reports every document where package:yaml hashes an alias '
      'inside a key (fixed-seed fuzz)', () {
    final random = Random(7);
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
    ];
    const indents = ['', ' ', '  ', '   ', '    ', '     '];
    var dangerous = 0;
    for (var i = 0; i < 400000; i++) {
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
      final counts = HashMap<YamlNode, int>.identity();
      void count(YamlNode node) {
        counts[node] = (counts[node] ?? 0) + 1;
        children(node).forEach(count);
      }

      bool shared(YamlNode n) => n is! YamlScalar && (counts[n] ?? 0) > 1;
      bool containsShared(YamlNode n) =>
          shared(n) || children(n).any(containsShared);
      bool dangerousKey(YamlNode n) => switch (n) {
        YamlMap() => n.nodes.entries.any(
          (e) => containsShared(e.key as YamlNode) || dangerousKey(e.value),
        ),
        YamlList() => n.nodes.any(dangerousKey),
        _ => false,
      };
      count(root);
      if (!dangerousKey(root)) continue;
      dangerous++;
      expect(const NestingScanner().scan(text), isNotNull, reason: text);
    }
    expect(dangerous, greaterThan(500));
  }, timeout: const Timeout(Duration(seconds: 120)));
}

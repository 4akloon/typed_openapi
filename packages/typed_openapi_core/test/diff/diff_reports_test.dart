import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diff/api_change.dart';
import 'package:typed_openapi_core/src/diff/json_diff_report.dart';
import 'package:typed_openapi_core/src/diff/markdown_diff_report.dart';
import 'package:typed_openapi_core/src/diff/text_diff_report.dart';

const _removed = ApiChange(
  ChangeCategory.breaking,
  'Model Pet was removed.',
  type: '#/components/schemas/Pet',
  fix: 'schemas:\n  Animal:\n    name: Pet',
);

const _hostile = ApiChange(
  ChangeCategory.wire,
  'Field Pet.a: json changed from "<img src=x>" to "\u001b[2J[x](y)".',
  type: '#/components/schemas/Pet',
  member: 'a',
);

void main() {
  test('text lists each change and the lines of its fix', () {
    expect(
      const TextDiffReport().format({
        'b': [_removed],
        'a': [],
      }),
      'a: no changes.\n'
      'b: 1 breaking, 0 switch-breaking, 0 wire, 0 additive, 0 docs.\n'
      '  breaking: Model Pet was removed.\n'
      '    Keep the old name with this override:\n'
      '      schemas:\n'
      '        Animal:\n'
      '          name: Pet\n',
    );
  });

  test('text neutralises the controls of spec text', () {
    final text = const TextDiffReport().format({
      'a': [_hostile],
    });
    expect(text, contains(r'\u{1b}[2J'));
    expect(text, isNot(contains('\u001b')));
  });

  test('text neutralises bidirectional controls in a fix', () {
    final text = const TextDiffReport().format({
      'a': [
        const ApiChange(
          ChangeCategory.breaking,
          'Model \u202eX was removed.',
          type: 't',
          fix: 'schemas:\n  \u202eY:\n    name: X',
        ),
      ],
    });
    expect(text, isNot(contains('\u202e')));
    expect(text, contains(r'\u{202e}'));
  });

  test('markdown neutralises bidirectional controls', () {
    final text = const MarkdownDiffReport().format({
      'a': [
        const ApiChange(
          ChangeCategory.breaking,
          'Model \u202eX was removed.',
          type: 't',
          fix: 'schemas:\n  \u202eY:\n    name: X',
        ),
      ],
    });
    expect(text, isNot(contains('\u202e')));
    expect(text, contains(r'\u{202e}'));
  });

  test('markdown escapes what would mark up the comment', () {
    final text = const MarkdownDiffReport().format({
      'a': [_hostile],
    });
    expect(text, contains(r'"\<img src=x\>"'));
    expect(text, contains(r'\u{1b}\[2J\[x\](y)'));
  });

  test('markdown escapes @ so a name mentions nobody', () {
    final text = const MarkdownDiffReport().format({
      'a': [
        const ApiChange(
          ChangeCategory.wire,
          'Field Pet.a: renamed to @octocat.',
          type: '#/components/schemas/Pet',
        ),
      ],
    });
    expect(text, contains(r'renamed to \@octocat'));
  });

  test('markdown fences a fix with more backticks than it holds', () {
    final text = const MarkdownDiffReport().format({
      'a': [
        const ApiChange(
          ChangeCategory.breaking,
          'Model X was removed.',
          type: 't',
          fix: "schemas:\n  '````':\n    name: X",
        ),
      ],
    });
    expect(text, contains('  `````yaml\n'));
    expect(text, contains("  '````':\n"));
  });

  test('json counts every category and lists the changes', () {
    final json =
        jsonDecode(
              const JsonDiffReport().format({
                'a': [_removed],
              }),
            )
            as Map<String, Object?>;
    expect(json, {
      'clients': {
        'a': {
          'counts': {
            'breaking': 1,
            'switch-breaking': 0,
            'wire': 0,
            'additive': 0,
            'docs': 0,
          },
          'changes': [_removed.toJson()],
        },
      },
    });
  });
}

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/leak_check.dart';

void main() {
  const check = LeakCheck();

  test('a line that starts with smuggled code is a leak', () {
    expect(check.code('c', {'a.dart': '/// doc */\ninjected();\n'}), [
      'c/a.dart: spec text left its sink: injected();',
    ]);
  });

  test('a raw bidi control or line separator in code is a leak', () {
    expect(check.code('c', {'a.dart': "const a = '\u202E';\n"}), [
      'c/a.dart: a raw U+202E in the code.',
    ]);
    expect(check.code('c', {'a.dart': '/// a\u2028b\n'}), [
      'c/a.dart: a raw U+2028 in the code.',
    ]);
  });

  test('smuggled code in the middle of a line is a leak', () {
    expect(check.code('c', {'a.dart': "const a = 'x'; injected();\n"}), [
      "c/a.dart: spec text left its sink: const a = 'x'; injected();",
    ]);
  });

  test('the text injected inside a comment or a literal is not a leak', () {
    const source =
        "/// a */ injected();\n// injected();\nconst a = '*/ injected();';\n"
        "const b = '''\ninjected();\n''';\n";
    expect(check.code('c', {'a.dart': source}), isEmpty);
  });

  test('a raw lone surrogate in code or in the report is a leak', () {
    expect(check.code('c', {'a.dart': "const a = '\uD800';\n"}), [
      'c/a.dart: a raw U+D800 in the code.',
    ]);
    expect(check.code('c', {'a.dart': "const a = 'x\uDC00';\n"}), [
      'c/a.dart: a raw U+DC00 in the code.',
    ]);
    expect(check.report('error - a\uD800b'), [
      'The report holds a raw U+D800.',
    ]);
  });

  test('a surrogate pair is not a lone surrogate', () {
    expect(check.code('c', {'a.dart': "const a = '\u{1F600}';\n"}), isEmpty);
    expect(check.report('error - \u{1F600}'), isEmpty);
  });

  test('a tab in a doc comment is allowed', () {
    expect(check.code('c', {'a.dart': '/// `tab\there`\n'}), isEmpty);
  });

  test('a raw control character in the report is a leak', () {
    expect(check.report('error - a\x1bb'), [
      'The report holds a raw U+001B.',
    ]);
    expect(check.report('error - a\nb\n'), isEmpty);
  });

  test('a report line that starts like a workflow command is a leak', () {
    expect(check.report('error - x\n::error::boom\n'), [
      'The report holds a line that starts like a workflow command.',
    ]);
    expect(check.report('error - ::error::inside a line'), isEmpty);
  });
}

import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/github_actions_reporter.dart';
import 'package:typed_openapi/src/diagnostics/reporters.dart';
import 'package:typed_openapi/src/diagnostics/sarif_reporter.dart';

void main() {
  const snippet = 'Override:\n  schemas:\n    Pet:\n      nullable: true';
  const hint = 'In NestJS, set nullable: true.';

  Diagnostic make(String fix) => Diagnostic(
    code: .parseError,
    severity: .error,
    message: 'Broken.',
    file: 'a.json',
    fix: fix,
    hints: const [('nestjs', hint)],
  );

  DiagnosticBag multiLine() => DiagnosticBag()..add(make(snippet));

  test('a hint after a multi-line fix starts a line of its own', () {
    expect(make(snippet).fix, '$snippet\n$hint');
  });

  test('a hint after a one-line fix follows on the same line', () {
    expect(make('Fix it.').fix, 'Fix it. $hint');
  });

  test('TextReporter indents the hint line like the snippet', () {
    final text = const TextReporter().format(multiLine());
    expect(
      text,
      contains(
        '  fix: Override:\n      schemas:\n        Pet:\n          nullable: true\n'
        '    $hint\n',
      ),
    );
  });

  test('GitHubActionsReporter puts the hint after a %0A line break', () {
    expect(
      const GitHubActionsReporter().format(multiLine()),
      contains('nullable: true%0A$hint'),
    );
  });

  test('JsonReporter and SarifReporter keep the hint on its own line', () {
    final json =
        jsonDecode(const JsonReporter().format(multiLine()))
            as Map<String, Object?>;
    final fix =
        ((json['diagnostics']! as List<Object?>).single
            as Map<String, Object?>)['fix'];
    expect(fix, '$snippet\n$hint');
    expect(
      const SarifReporter().format(multiLine()),
      contains('nullable: true\\n$hint'),
    );
  });
}

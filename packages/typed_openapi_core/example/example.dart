import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi_core/typed_openapi_core.dart';

/// Lints `openapi.yaml` next to this file and prints what the engine found.
void main() {
  final spec = p.join(
    p.dirname(Platform.script.toFilePath()),
    'openapi.yaml',
  );
  final result = const SpecLinter().lint(spec);
  final findings = result.diagnostics.sorted;
  stdout.writeln('${findings.length} finding(s) in $spec');
  for (final finding in findings) {
    stdout.writeln('${finding.severity.name} ${finding.message}');
  }
}

/// The size limits of `CLAUDE.md` ("Code quality rules") for the tool
/// package: a file in `lib/` has at most 300 lines, a test file 500, a
/// method 40. The package starts within them, so nothing is allowlisted.
library;

import 'package:test/test.dart';

import '../helpers/size_limits.dart';

void main() {
  final limits = SizeLimits('.');

  test('no file is over its size limit', () {
    final failures = limits.fileFailures(
      allowlist: const {},
      permanent: const {},
    );
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });

  test('no method is over 40 lines', () {
    final failures = limits.methodFailures(allowlist: const {});
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });
}

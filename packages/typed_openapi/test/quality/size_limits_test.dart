/// The size limits of `CLAUDE.md` ("Code quality rules") as a ratchet.
///
/// A file in `lib/` has at most 300 lines, a test file 500, a method 40. A
/// unit over its limit may only be here if it is in an allowlist below, with
/// the size it had when it was listed, and it may only shrink: the test fails
/// when a listed unit grows or a new one goes over its limit. A listed unit
/// that shrank or is within its limit again is a stale entry; it does not
/// fail, delete it. Never add a new entry, split the unit instead. The
/// reasoning and the legacy list are in `docs/code-quality-review.md`.
library;

import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// Files over their limit, with the number of lines (`wc -l`) they had when
/// they were listed. Keep the entries sorted.
const Map<String, int> _fileAllowlist = {
  'lib/src/emit/union_emitter.dart': 333,
  // M9: event streams in the empty-client report; webhooks checked.
  'test/cli/generate_command_test.dart': 771,
  'test/emit/model_library_test.dart': 887,
};

/// Files that are exempt for good and are not to be split: a flat catalog
/// with no logic.
const Set<String> _permanent = {};

/// Methods over 40 lines (`path#Type.name`, `new` for a constructor), with
/// the lines they had when they were listed. Keep the entries sorted.
const Map<String, int> _methodAllowlist = {
  'lib/src/emit/enum_emitter.dart#EnumEmitter.write': 94,
  'lib/src/emit/imports.dart#Imports.write': 48,
  'lib/src/emit/model_emitter.dart#ModelEmitter.write': 46,
  'lib/src/emit/union_emitter.dart#UnionEmitter._byStructure': 41,
  'lib/src/emit/union_emitter.dart#UnionEmitter._variant': 78,
};

void main() {
  final limits = SizeLimits('.');

  test('no file is over its size limit unless it is allowlisted', () {
    final failures = limits.fileFailures(
      allowlist: _fileAllowlist,
      permanent: _permanent,
    );
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });

  test('no method is over 40 lines unless it is allowlisted', () {
    final failures = limits.methodFailures(allowlist: _methodAllowlist);
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });
}

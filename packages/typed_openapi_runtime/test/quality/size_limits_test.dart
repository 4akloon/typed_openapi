/// The size limits of `CLAUDE.md` ("Code quality rules") as a ratchet.
///
/// A file in `lib/` has at most 300 lines, a test file 500, a method 40. A
/// unit over its limit may only be here if it is in an allowlist below, with
/// the size it had when it was listed, and it may only shrink: the test fails
/// when a listed unit grows or a new one goes over its limit. A listed unit
/// that shrank or is within its limit again is a stale entry; it does not
/// fail, delete it. Never add a new entry, split the unit instead. The
/// reasoning and the legacy list are in `docs/code-quality-review.md`.
///
/// It reads the source files, so it runs on the VM only.
@TestOn('vm')
library;

import 'package:test/test.dart';

import '../helpers/size_limits.dart';

/// Files over their limit, with the number of lines (`wc -l`) they had when
/// they were listed. Keep the entries sorted.
const Map<String, int> _fileAllowlist = {
  'lib/src/dio/dio_request_sender.dart': 378,
  'lib/src/json/json_reader.dart': 422,
  'test/dio/dio_request_sender_test.dart': 537,
  'test/json/json_reader_test.dart': 531,
};

/// Files that are exempt for good, not to be split. None in this package.
const Set<String> _permanent = {};

/// Methods over 40 lines (`path#Type.name`), with the lines they had when
/// they were listed. Keep the entries sorted.
const Map<String, int> _methodAllowlist = {
  'lib/src/dio/dio_request_sender.dart#DioRequestSender._request': 42,
  'lib/src/dio/dio_request_sender.dart#DioRequestSender.openEvents': 67,
  'lib/src/json/json_reader.dart#JsonReader.listOf': 48,
  'lib/src/sse/sse_item_decoder.dart#SseItemDecoder.bind': 52,
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

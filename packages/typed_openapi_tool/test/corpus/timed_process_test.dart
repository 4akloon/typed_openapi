@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/timed_process.dart';

import '../helpers/temp_dir.dart';

void main() {
  late String script;
  setUp(() {
    script = TempDir().write('wait.dart', '''
import 'dart:io';
Future<void> main(List<String> args) async {
  stdout.writeln('started');
  await Future<void>.delayed(Duration(seconds: int.parse(args.single)));
  stdout.writeln('done');
}
''');
  });

  test('returns the output of a process that finishes', () async {
    final result = await const TimedProcess().run(
      Platform.resolvedExecutable,
      [script, '0'],
    );
    expect(result.exitCode, 0);
    expect(result.stdout, 'started\ndone\n');
  });

  test('kills a process that outlives the limit', () async {
    final run = const TimedProcess(
      timeout: Duration(milliseconds: 500),
    ).run(Platform.resolvedExecutable, [script, '60']);
    await expectLater(
      run,
      throwsA(
        isA<CorpusException>().having(
          (e) => e.message,
          'message',
          contains('was killed'),
        ),
      ),
    );
  });

  test('quotes at most a bounded excerpt of a long output', () {
    final text = TimedProcess.excerpt('x' * 10000);
    expect(text.length, lessThan(TimedProcess.maxQuoted + 100));
    expect(text, endsWith('... 6000 more characters.'));
    expect(TimedProcess.excerpt(' short \n'), 'short');
  });
}

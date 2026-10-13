import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_cli.dart';

void main() {
  for (final args in const [
    ['--sample-every', '0'],
    ['--seeds', 'many'],
    ['--from', '-1'],
  ]) {
    test('${args.join(' ')} is a usage error', () async {
      final err = StringBuffer();
      final code = await FuzzCli(out: StringBuffer(), err: err).run(args);
      expect(code, 64);
      expect('$err', contains(args.first));
    });
  }
}

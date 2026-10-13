import 'package:typed_openapi/typed_openapi.dart';

import 'temp_dir.dart';

/// The IR of the spec [spec] (YAML), checked as the client `api` of a config
/// in a temp directory, as `generate` would build it.
ClientIr clientIr(String spec) {
  final temp = TempDir();
  temp.write('spec.yaml', spec);
  final config = temp.write(
    'typed_openapi.yaml',
    'clients:\n  api: {input: spec.yaml, output: out}\n',
  );
  final bag = DiagnosticBag();
  final project = ConfigLoader(bag).load(config);
  if (project == null) throw StateError('config: ${bag.all}');
  final ir = SpecChecker(bag).check(project).single.ir;
  if (ir == null) throw StateError('spec: ${bag.all}');
  return ir;
}

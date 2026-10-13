import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/emit_fixture.dart';

void main() {
  late String model;
  late String marker;
  setUpAll(() {
    final files = emitFixture(
      'optional_constant.yaml',
      generation: const GenerationConfig(union: UnionMode.structural),
    );
    model = files['models/value_facet.dart']!;
    marker = files['models/marker.dart']!;
  });

  test('a model made in code writes its optional constants', () {
    expect(
      model,
      contains('const ValueFacet({required this.field}) : _absent = const [];'),
    );
    expect(model, contains("if (!_absent.contains('type')) 'type': 'value'"));
    expect(model, contains("if (!_absent.contains('version')) 'version': 2"));
  });

  test('fromJson remembers the optional constants that were absent', () {
    expect(
      model,
      contains('const ValueFacet._(this._absent, {required this.field});'),
    );
    expect(
      model,
      contains(
        "if (!r.constant('type', 'value', required: false)) 'type',",
      ),
    );
    expect(model, contains('return ValueFacet._('));
    expect(model, contains('final List<String> _absent;'));
  });

  test('a model of only an optional constant has both constructors', () {
    expect(marker, contains('const Marker() : _absent = const [];'));
    expect(marker, contains('const Marker._(this._absent);'));
    expect(marker, contains('return Marker._('));
  });

  test('the absent constants are part of equality', () {
    expect(
      model,
      contains('const DeepEquality().equals(other._absent, _absent)'),
    );
    expect(model, contains('hash([field, _absent])'));
  });
}

import 'dart:convert';
import 'dart:math';

import 'fuzz_operations.dart';
import 'fuzz_schemas.dart';
import 'hostile.dart';

/// The spec and the overrides file the fuzz builds from one seed.
typedef FuzzInput = ({String spec, String overrides});

/// Builds a random spec from a seed: the same seed gives the same spec.
final class FuzzSpec {
  /// Creates the builder.
  const FuzzSpec();

  static const _stems = ['Pet', 'Cat', 'Status', 'Kind', 'Id', 'Get0'];
  static const _suffixes = [
    '',
    'Response',
    'Error',
    'Request',
    'Unknown',
    'Dio',
  ];
  static const _methods = ['get', 'post', 'patch', 'put', 'delete'];
  static const _id = {
    'name': 'id',
    'in': 'path',
    'required': true,
    'schema': {'type': 'string'},
  };

  /// The spec (JSON) and the overrides file (JSON) of [seed].
  FuzzInput of(int seed) {
    final random = Random(seed);
    final schemas = FuzzSchemas(random, _names(random));
    final operations = FuzzOperations(random, schemas);
    final overrides = <String, Object?>{};
    final paths = <String, Object?>{
      for (var i = 0; i < 1 + random.nextInt(3); i++)
        '/p$i/{id}': _pathItem(i, random, operations, overrides),
    };
    return (
      spec: jsonEncode({
        'openapi': schemas.pick(['3.0.3', '3.1.0', '3.2.0']),
        'info': {'title': schemas.pick(Hostile.texts), 'version': '1'},
        'paths': paths,
        'components': {
          'schemas': {
            for (final name in schemas.names) name: schemas.component(),
          },
        },
      }),
      overrides: jsonEncode({'operations': overrides}),
    );
  }

  static List<String> _names(Random random) {
    final names = <String>{};
    final count = 3 + random.nextInt(8);
    while (names.length < count) {
      names.add(
        '${_stems[random.nextInt(_stems.length)]}'
        '${_suffixes[random.nextInt(_suffixes.length)]}',
      );
    }
    return names.toList()..sort();
  }

  /// The path item `/p<i>/{id}`; an operation's `sse` override goes into
  /// [overrides].
  static Map<String, Object?> _pathItem(
    int i,
    Random random,
    FuzzOperations operations,
    Map<String, Object?> overrides,
  ) {
    final schemas = operations.schemas;
    final item = <String, Object?>{};
    for (final method in _methods) {
      if (random.nextBool()) continue;
      final id = schemas.pick(['$method$i', '$method$i', ...Hostile.names]);
      item[method] = {
        'operationId': id,
        'description': schemas.pick(Hostile.texts),
        if (schemas.coin())
          'tags': [
            schemas.pick(['t', 'Pet', ...Hostile.names]),
          ],
        'parameters': [
          for (var k = 0; k < random.nextInt(4); k++) operations.parameter(k),
        ],
        if (method != 'get' && schemas.coin())
          'requestBody': {'content': operations.content()},
        'responses': operations.responses(),
      };
      if (random.nextInt(3) == 0) {
        overrides[id] = {'sse': operations.sseOverride()};
      }
    }
    return {
      ...item,
      'parameters': [_id],
    };
  }
}

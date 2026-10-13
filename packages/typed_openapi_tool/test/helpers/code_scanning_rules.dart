/// The properties GitHub code scanning requires of an uploaded SARIF file
/// beyond its schema ("SARIF support for code scanning", the tables of
/// required properties): a driver name, a rule's descriptions and help, a
/// result's message, partial fingerprints and a physical location with a
/// region. An empty string does not count. Tests only.
final class CodeScanningRules {
  /// Creates the checker.
  const CodeScanningRules();

  /// The properties [log] lacks, each with its path; empty when it has all.
  List<String> problems(Map<String, Object?> log) => [
    ..._need(log, r'$schema', ''),
    ..._need(log, 'version', ''),
    for (final (i, run) in _list(log['runs']).indexed) ...[
      ..._need(run, 'tool.driver.name', '/runs/$i'),
      for (final (j, rule) in _list(_at(run, 'tool.driver.rules')).indexed)
        for (final path in [
          'id',
          'shortDescription.text',
          'fullDescription.text',
          'help.text',
        ])
          ..._need(rule, path, '/runs/$i/rules/$j'),
      for (final (j, result) in _list(run['results']).indexed)
        ..._result(result, '/runs/$i/results/$j'),
    ],
  ];

  List<String> _result(Map<String, Object?> result, String at) {
    final locations = _list(result['locations']);
    final prints = result['partialFingerprints'];
    return [
      ..._need(result, 'message.text', at),
      if (locations.isEmpty) '$at: no locations',
      if (prints is! Map || prints.isEmpty) '$at: no partialFingerprints',
      for (final (k, location) in locations.indexed)
        for (final path in [
          'physicalLocation.artifactLocation.uri',
          'physicalLocation.region.startLine',
          'physicalLocation.region.startColumn',
          'physicalLocation.region.endLine',
          'physicalLocation.region.endColumn',
        ])
          ..._need(location, path, '$at/locations/$k'),
    ];
  }

  static List<String> _need(Map<String, Object?> node, String path, String at) {
    final value = _at(node, path);
    return value == null || value == '' ? ['$at: $path is required'] : const [];
  }

  static Object? _at(Map<String, Object?> node, String path) {
    Object? current = node;
    for (final key in path.split('.')) {
      current = current is Map ? current[key] : null;
    }
    return current;
  }

  static List<Map<String, Object?>> _list(Object? value) => value is List
      ? value.whereType<Map<String, Object?>>().toList()
      : const [];
}

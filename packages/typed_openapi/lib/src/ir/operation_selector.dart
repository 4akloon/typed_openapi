import '../config/generation_config.dart';
import 'ir_context.dart';
import 'operation_builder.dart';

/// Chooses the operations a client generates (R4.1): the config's
/// `include` and `exclude` filters and the overrides' `exclude`.
///
/// With `include`, only operations that match one of its patterns are
/// kept; `exclude` then removes the operations it matches, so it refines
/// `include` (`include: {tags: [pets]}`, `exclude: {paths: [/pets/admin/**]}`).
/// A pattern that matches no operation of the spec is reported, and so is a
/// pattern both filters list: the config contradicts itself there.
final class OperationSelector {
  /// Creates a selector for the client of [_context].
  const OperationSelector(this._context);

  final IrContext _context;

  /// The operations of [all] to generate, in the same order.
  List<SpecOperation> select(List<SpecOperation> all) {
    final config = _context.config;
    final include = _Matcher(config.include);
    final exclude = _Matcher(config.exclude);
    final selected = <SpecOperation>[];
    for (final entry in all) {
      final included = config.include.isEmpty || include.matches(entry);
      final excluded = exclude.matches(entry);
      final override = _context.overrides.operationAt(entry.operation.location);
      if (!included || excluded || (override?.exclude ?? false)) continue;
      selected.add(entry);
    }
    for (final (included, excluded) in [
      (config.include.tags, config.exclude.tags),
      (config.include.operations, config.exclude.operations),
      (config.include.paths, config.exclude.paths),
    ]) {
      final values = {for (final p in included) p.value};
      for (final pattern in excluded) {
        if (!values.contains(pattern.value)) continue;
        _context.diagnostics.report(
          .filterConflict,
          '"${pattern.value}" is in both include and exclude; exclude wins.',
          file: config.file,
          pointer: pattern.pointer,
          span: pattern.span,
          fix: 'Remove it from one of the filters.',
        );
      }
    }
    for (final pattern in [...include.unused, ...exclude.unused]) {
      _context.diagnostics.report(
        .filterMatchesNothing,
        'Filter "${pattern.value}" matches no operation of the spec.',
        file: config.file,
        pointer: pattern.pointer,
        span: pattern.span,
        fix: 'Fix the pattern, or remove it from the config.',
      );
    }
    return selected;
  }
}

/// The patterns of one filter, and which of them matched.
final class _Matcher {
  _Matcher(this._filter)
    : _paths = [for (final p in _filter.paths) (p, _glob(p.value))];

  final OperationFilter _filter;
  final List<(FilterPattern, RegExp)> _paths;
  final Set<FilterPattern> _used = {};

  /// The patterns that matched no operation so far, in config order.
  List<FilterPattern> get unused => [
    for (final p in [..._filter.tags, ..._filter.operations, ..._filter.paths])
      if (!_used.contains(p)) p,
  ];

  /// Whether a pattern matches [entry]; every matching pattern counts as
  /// used.
  bool matches(SpecOperation entry) {
    final operation = entry.operation;
    final matched = [
      for (final pattern in _filter.tags)
        if (operation.tags.contains(pattern.value)) pattern,
      for (final pattern in _filter.operations)
        if (operation.operationId == pattern.value) pattern,
      for (final (pattern, glob) in _paths)
        if (glob.hasMatch(entry.path)) pattern,
    ];
    _used.addAll(matched);
    return matched.isNotEmpty;
  }

  /// A path glob as a regular expression: `**` matches any characters,
  /// `*` any characters but `/`, `?` one character but `/`.
  static RegExp _glob(String pattern) {
    final buffer = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '*' && i + 1 < pattern.length && pattern[i + 1] == '*') {
        buffer.write('.*');
        i++;
      } else if (char == '*') {
        buffer.write('[^/]*');
      } else if (char == '?') {
        buffer.write('[^/]');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }
}

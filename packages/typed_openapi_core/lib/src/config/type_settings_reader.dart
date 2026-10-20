import '../diagnostics/json_pointer.dart';
import 'config_reading.dart';
import 'config_sources.dart';

/// Reads the settings of how a client's types are generated: `types.number`
/// and `exhaustive`, each from the last source that has it (`defaults`
/// first). A bad value is reported through the `invalid` function (TOA902)
/// and the next source is tried.
final class TypeSettingsReader {
  /// Creates a reader of [_sources] that reports through [_invalid].
  const TypeSettingsReader(this._sources, this._invalid);

  /// The maps to read, `defaults` first, with their pointers.
  final ConfigSources _sources;

  final void Function(String message, JsonPointer at) _invalid;

  /// `types.number`: the Dart type of a `number` without a format, `double`
  /// or `int`; null for `num`, the default.
  String? numberType() => _sources
      .resolve<String?>(
        'number',
        section: 'types',
        builtIn: null,
        show: (type) => type ?? 'num',
        report: _invalid,
        read: (value) {
          if (value is! String || value.isEmpty) {
            return const InvalidValue('"number" must be a non-empty string.');
          }
          return switch (value) {
            'num' => const ValidValue(null),
            'double' || 'int' => ValidValue(value),
            _ => const InvalidValue('"number" must be num, double or int.'),
          };
        },
      )
      .value;

  /// `exhaustive` (R14.2): whether the bases of enums, unions, status types
  /// and event unions are `sealed`, so a `switch` names every case; `true`
  /// unless set.
  bool exhaustive() => _sources
      .resolve<bool>(
        'exhaustive',
        builtIn: true,
        report: _invalid,
        read: (value) => value is bool
            ? ValidValue(value)
            : const InvalidValue('"exhaustive" must be true or false.'),
      )
      .value;
}

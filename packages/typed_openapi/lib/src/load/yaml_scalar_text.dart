/// The text of a YAML scalar, read as a value of the JSON Schema ruleset.
///
/// The rules are those of package:yaml's loader. They run for every scalar of
/// a spec, so this is an extension type: no object is made for the text.
extension type const YamlScalarText(String text) {
  /// A plain scalar resolved as package:yaml's loader does: null, bool, int,
  /// float, else the string.
  Object? resolvePlain() {
    if (text.isEmpty) return null;
    final resolved = switch (text.codeUnitAt(0)) {
      0x2E || 0x2B || 0x2D => asNumber(),
      0x6E || 0x4E => text.length == 4 ? asNull() : null,
      0x74 || 0x54 => text.length == 4 ? asBool() : null,
      0x66 || 0x46 => text.length == 5 ? asBool() : null,
      0x7E => text.length == 1 ? (null,) : null,
      final c when c >= 0x30 && c <= 0x39 => asNumber(),
      _ => null,
    };
    return resolved == null ? text : resolved.$1;
  }

  /// The null value in a one-element record, or null when the text is not
  /// null (a record tells a null value from a text that is not one).
  (Object?,)? asNull() => switch (text) {
    '' || 'null' || 'Null' || 'NULL' || '~' => (null,),
    _ => null,
  };

  /// The bool value in a one-element record, or null when the text is not a
  /// bool.
  (Object?,)? asBool() => switch (text) {
    'true' || 'True' || 'TRUE' => (true,),
    'false' || 'False' || 'FALSE' => (false,),
    _ => null,
  };

  /// The number in a one-element record, or null when the text is not one;
  /// [allowInt] and [allowFloat] limit what counts (`!!int`, `!!float`).
  (Object?,)? asNumber({bool allowInt = true, bool allowFloat = true}) {
    final value = _numberValue(allowInt: allowInt, allowFloat: allowFloat);
    return value == null ? null : (value,);
  }

  num? _numberValue({required bool allowInt, required bool allowFloat}) {
    if (text.isEmpty) return null;
    final first = text.codeUnitAt(0);
    if (text.length == 1) {
      final digit = first - 0x30;
      if (digit < 0 || digit > 9) return null;
      return allowInt ? digit : digit.toDouble();
    }
    final second = text.codeUnitAt(1);
    if (allowInt && first == 0x30) {
      if (second == 0x78) return int.tryParse(text);
      if (second == 0x6F) return int.tryParse(text.substring(2), radix: 8);
    }
    if (_isDigit(first) ||
        ((first == 0x2B || first == 0x2D) && _isDigit(second))) {
      return _decimal(allowInt: allowInt, allowFloat: allowFloat);
    }
    return allowFloat ? _dotted(first, second) : null;
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  num? _decimal({required bool allowInt, required bool allowFloat}) {
    num? result;
    if (allowInt) result = int.tryParse(text, radix: 10);
    if (allowFloat) result ??= double.tryParse(text);
    return result;
  }

  /// A float that starts with a dot or a signed dot: `.5`, `-.5`, `.inf`,
  /// `-.inf`, `.nan`.
  num? _dotted(int first, int second) {
    if ((first == 0x2E && _isDigit(second)) ||
        ((first == 0x2D || first == 0x2B) && second == 0x2E)) {
      if (text.length == 5) {
        switch (text) {
          case '+.inf' || '+.Inf' || '+.INF':
            return double.infinity;
          case '-.inf' || '-.Inf' || '-.INF':
            return -double.infinity;
        }
      }
      return double.tryParse(text);
    }
    if (text.length == 4 && first == 0x2E) {
      switch (text) {
        case '.inf' || '.Inf' || '.INF':
          return double.infinity;
        case '.nan' || '.NaN' || '.NAN':
          return double.nan;
      }
    }
    return null;
  }
}

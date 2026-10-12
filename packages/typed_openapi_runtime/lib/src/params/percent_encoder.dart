import 'dart:convert';

/// Percent-encoding of parameter names and values (RFC 3986), by the set of
/// characters left as is. Text is encoded as UTF-8; hex digits are upper
/// case.
enum PercentEncoder {
  /// Keeps only unreserved characters (`A-Z a-z 0-9 - . _ ~`), as RFC 6570
  /// simple expansion does.
  unreserved,

  /// `allowReserved: true`: also keeps the reserved characters that are safe
  /// in a query value (`: / ? @ ! $ ' ( ) * , ;`) and valid `%XX` triplets.
  /// `[ ] #` and `& = +` stay encoded, as OAS 3.2 requires for the query.
  reserved,

  /// Header values: keeps printable ASCII (space to `~`); control
  /// characters and non-ASCII are encoded, so a value cannot break the
  /// header line.
  header;

  /// Encodes [text].
  String encode(String text) {
    final bytes = utf8.encode(text);
    final out = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      final byte = bytes[i];
      if (_keeps(byte) || _isTriplet(bytes, i)) {
        out.writeCharCode(byte);
      } else {
        out
          ..write('%')
          ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return out.toString();
  }

  bool _keeps(int byte) => switch (this) {
    unreserved => _isUnreserved(byte),
    reserved => _isUnreserved(byte) || _safeReserved.contains(byte),
    header => byte >= 0x20 && byte <= 0x7E,
  };

  bool _isTriplet(List<int> bytes, int i) =>
      this == reserved &&
      bytes[i] == 0x25 &&
      i + 2 < bytes.length &&
      _isHex(bytes[i + 1]) &&
      _isHex(bytes[i + 2]);

  static bool _isUnreserved(int byte) =>
      (byte >= 0x41 && byte <= 0x5A) ||
      (byte >= 0x61 && byte <= 0x7A) ||
      (byte >= 0x30 && byte <= 0x39) ||
      byte == 0x2D ||
      byte == 0x2E ||
      byte == 0x5F ||
      byte == 0x7E;

  static bool _isHex(int byte) =>
      (byte >= 0x30 && byte <= 0x39) ||
      (byte >= 0x41 && byte <= 0x46) ||
      (byte >= 0x61 && byte <= 0x66);

  static final Set<int> _safeReserved = r":/?@!$'()*,;".codeUnits.toSet();
}

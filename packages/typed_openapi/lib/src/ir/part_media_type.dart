import '../model/media_type_name.dart';
import '../model/spec_node.dart';
import 'ir_context.dart';

/// What a part carries, which decides the media type it can be sent as.
enum PartPayload {
  /// A file: the file's own media type wins at run time.
  file,

  /// Text, or a scalar.
  text,

  /// An object, which the client writes as JSON.
  object,
}

/// Chooses the one concrete media type a multipart part is sent as from the
/// `contentType` of its `encoding` entry.
///
/// OpenAPI allows a comma-separated list (`image/png, image/jpeg`) and a
/// wildcard (`image/*`) there; the runtime parses one media type, so the
/// choice is made here and reported.
final class PartMediaType {
  /// Creates a chooser that reports through [_context].
  const PartMediaType(this._context);

  final IrContext _context;

  static const _fileFallback = 'application/octet-stream';
  static const _json = 'application/json';

  /// A token as RFC 9110 writes it, which never holds `*`.
  static const _token = r"[0-9A-Za-z!#$%&'+.^_`|~-]+";
  static final _concrete = RegExp(
    '^$_token/$_token'
    '(\\s*;\\s*$_token=(?:$_token|"(?:[^"\\\\]|\\\\.)*"))*\\s*\$',
  );
  static final _comma = RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)');

  /// The media type a [payload] part [wire] is sent as, for the [declared]
  /// `contentType` found at [at]; null when none is sent.
  ///
  /// A single concrete type is kept. Another value is reported (TOA661); an
  /// object part that cannot be JSON is reported as TOA662 and its type is
  /// not JSON, which the caller reads as text the caller supplies.
  String? choose(
    String? declared,
    PartPayload payload, {
    required String wire,
    required SpecLocation at,
  }) {
    if (declared == null) return null;
    final candidates = [
      for (final piece in declared.split(_comma))
        if (piece.trim().isNotEmpty) piece.trim(),
    ];
    final concrete = [
      for (final candidate in candidates)
        if (_concrete.hasMatch(candidate)) candidate,
    ];
    final chosen = switch (payload) {
      _ when candidates.length == 1 && concrete.length == 1 => concrete.single,
      .file => concrete.firstOrNull ?? _fileFallback,
      .text => concrete.firstOrNull,
      .object => _objectType(candidates, concrete),
    };
    if (payload == .object && chosen != null && !MediaTypeName(chosen).isJson) {
      _reportNotJson(declared, chosen, wire, at);
    } else if (chosen != declared.trim()) {
      _reportChosen(declared, chosen, payload, wire, at);
    }
    return chosen;
  }

  static String _objectType(List<String> candidates, List<String> concrete) {
    for (final type in concrete) {
      if (MediaTypeName(type).isJson) return type;
    }
    final isJsonWildcard = candidates.any(
      (candidate) => const {'*/*', 'application/*'}.contains(candidate),
    );
    if (isJsonWildcard) return _json;
    return concrete.firstOrNull ?? _fileFallback;
  }

  void _reportChosen(
    String declared,
    String? chosen,
    PartPayload payload,
    String wire,
    SpecLocation at,
  ) {
    final sent = chosen == null
        ? 'without a media type'
        : 'as "$chosen"${payload == .file ? ' unless the file has its own' : ''}';
    _context.report(
      .partMediaTypeChosen,
      'The media type "$declared" of part "$wire" is not one concrete type; '
      'the part is sent $sent.',
      at,
      fix: 'Name one concrete media type in the encoding at the source.',
    );
  }

  void _reportNotJson(
    String declared,
    String chosen,
    String wire,
    SpecLocation at,
  ) {
    _context.report(
      .partMediaTypeNotJson,
      'Part "$wire" is an object that the spec sends as "$declared", which is '
      'not JSON; the client writes JSON only, so the part is a String the '
      'caller supplies, sent as "$chosen".',
      at,
      fix:
          'Write the value in that format yourself and pass the text, or '
          'describe the part as a string at the source.',
    );
  }
}

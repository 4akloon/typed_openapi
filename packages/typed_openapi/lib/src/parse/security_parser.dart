import '../diagnostics/json_pointer.dart';
import '../model/security_requirement.dart';
import 'object_reader.dart';
import 'parse_context.dart';

/// Reads the `security` field of a document or an operation and the Security
/// Requirement Objects in it.
final class SecurityParser {
  /// Creates a parser that reads from [_context].
  const SecurityParser(this._context);

  final ParseContext _context;

  /// The `security` field of [reader], or null when it has none.
  ///
  /// A field that is not a list is reported (TOA111) and kept as one
  /// requirement that stands for it, so the metadata never reads as open.
  List<SecurityRequirement>? requirements(ObjectReader reader) {
    final listed = reader.list('security', requirement);
    if (listed != null) return listed;
    final raw = reader.value('security');
    if (raw == null) return null;
    final (field,) = raw;
    return [
      _malformed(field, reader.pointer.child('security'), isNotList: true),
    ];
  }

  /// Reads the security requirement [raw] at [pointer]; an entry that is not
  /// an object is reported and kept as a malformed requirement.
  SecurityRequirement requirement(Object? raw, JsonPointer pointer) =>
      _context.node(raw, pointer, 'A security requirement', _requirement) ??
      _malformed(raw, pointer, isNotList: false);

  SecurityRequirement _requirement(ObjectReader r) => _context.register(
    SecurityRequirement(
      location: r.location,
      schemes: Map.unmodifiable({
        for (final name in r.keys.toList()) name: r.strings(name) ?? const [],
      }),
    ),
  );

  SecurityRequirement _malformed(
    Object? raw,
    JsonPointer pointer, {
    required bool isNotList,
  }) => _context.register(
    SecurityRequirement(
      location: _context.locate(pointer),
      schemes: {if (raw is String) raw: const []},
      isMalformed: true,
      isNotList: isNotList,
    ),
  );
}

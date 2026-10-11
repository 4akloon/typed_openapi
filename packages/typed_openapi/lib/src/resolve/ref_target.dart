import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';

/// What a `$ref` value points to, or why it cannot be followed.
sealed class RefTarget {
  const RefTarget();

  /// Reads [ref], written in the document at [base].
  ///
  /// The part before `#` is a URI relative to [base]; the fragment is a JSON
  /// pointer, percent-decoded. Remote URIs, plain-name fragments (`#foo`)
  /// and pointers that stop at a components section or end with `/` cannot
  /// be followed.
  factory RefTarget.parse(String ref, Uri base) {
    if (ref.isEmpty) {
      return const BrokenRef(.invalidRef, r'The "$ref" is empty.');
    }
    final hash = ref.indexOf('#');
    final address = hash < 0 ? ref : ref.substring(0, hash);
    final fragment = hash < 0 ? '' : ref.substring(hash + 1);
    final Uri document;
    if (address.isEmpty) {
      document = base;
    } else {
      final Uri parsed;
      try {
        parsed = Uri.parse(address);
      } on FormatException {
        return BrokenRef(.invalidRef, '"$ref" is not a valid URI.');
      }
      if (parsed.hasScheme && parsed.scheme != 'file') {
        return BrokenRef(
          .remoteRef,
          '"$ref" points to a remote document; only local files are read.',
          fix:
              'Save the document next to the spec and refer to it by a '
              'relative path.',
        );
      }
      document = base.resolveUri(parsed).removeFragment();
      if (document.hasAuthority && document.authority.isNotEmpty) {
        return BrokenRef(
          .remoteRef,
          '"$ref" names another host; only local files are read.',
          fix:
              'Save the document next to the spec and refer to it by a '
              'relative path.',
        );
      }
      if (document.hasQuery) {
        return BrokenRef(
          .invalidRef,
          '"$ref" has a query string, which a local file cannot have.',
        );
      }
    }
    final read = _pointer(ref, fragment);
    final pointer = read.pointer;
    if (pointer == null) return read.broken!;
    final tokens = pointer.tokens;
    if (tokens.isNotEmpty && tokens.last.isEmpty) {
      return BrokenRef(
        .invalidRef,
        '"$ref" ends with "/", so the name of the target is missing.',
        fix:
            'Fix the code that writes the spec; in NestJS this usually '
            'means a circular import made a DTO type undefined.',
      );
    }
    if (tokens.length <= 2 && tokens.firstOrNull == 'components') {
      return BrokenRef(
        .invalidRef,
        '"$ref" points at a whole components section, not at one entry.',
      );
    }
    return ResolvableRef(SpecLocation(document, pointer));
  }

  static final _badPercent = RegExp('%(?![0-9A-Fa-f]{2})');
  static final _badTilde = RegExp('~(?![01])');

  static ({JsonPointer? pointer, BrokenRef? broken}) _pointer(
    String ref,
    String fragment,
  ) {
    if (fragment.isEmpty) return (pointer: JsonPointer.root, broken: null);
    if (!fragment.startsWith('/')) {
      return (
        pointer: null,
        broken: BrokenRef(
          .invalidRef,
          '"$ref" does not end with a JSON pointer such as '
          '"#/components/schemas/Name".',
          fix: r'Plain-name fragments ($anchor) are not supported.',
        ),
      );
    }
    final String? decoded = _decode(fragment);
    if (decoded == null) {
      return (
        pointer: null,
        broken: BrokenRef(
          .invalidRef,
          '"$ref" has an invalid percent-escape in the fragment.',
        ),
      );
    }
    if (_badTilde.hasMatch(decoded)) {
      return (
        pointer: null,
        broken: BrokenRef(
          .invalidRef,
          '"$ref" has a "~" that is not followed by 0 or 1.',
        ),
      );
    }
    return (pointer: JsonPointer.parse('#$decoded'), broken: null);
  }

  static String? _decode(String fragment) {
    if (_badPercent.hasMatch(fragment)) return null;
    if (!fragment.contains('%')) return fragment;
    try {
      return Uri.decodeComponent(fragment);
    } on FormatException {
      return null;
    }
  }
}

/// A `$ref` to a node in a local file.
final class ResolvableRef extends RefTarget {
  /// Creates a target at [location].
  const ResolvableRef(this.location);

  /// The file and pointer the `$ref` names.
  final SpecLocation location;
}

/// A `$ref` that cannot be followed.
final class BrokenRef extends RefTarget {
  /// Creates a broken target; [reason] becomes the diagnostic message.
  const BrokenRef(this.code, this.reason, {this.fix});

  /// The diagnostic code to report.
  final DiagnosticCode code;

  /// Why the `$ref` cannot be followed.
  final String reason;

  /// How to fix the `$ref`.
  final String? fix;
}

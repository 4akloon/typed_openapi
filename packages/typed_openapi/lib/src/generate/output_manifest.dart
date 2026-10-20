import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// The manifest of a generated tree: which files the generator wrote and
/// their hashes.
final class OutputManifest {
  /// Creates a manifest that lists [hashes].
  const OutputManifest(this.hashes);

  /// The name of the manifest in the output directory.
  static const fileName = '.typed_openapi.json';

  /// The generator and its version, as the manifest names them.
  static const generator = 'typed_openapi 0.3.0';

  /// The format of the manifest, which it records as `format`: 2 lists every
  /// file with its hash, and `generate` deletes only files whose hash it
  /// still finds. A manifest without a format has no hash to rely on for a
  /// file where one is missing.
  static const format = 2;

  /// What a manifest's `generator` starts with, whatever the version.
  static const generatorName = 'typed_openapi';

  /// A SHA-256 in hex.
  static final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  /// The files by relative path; a hash is null where the manifest has none
  /// (a format before 2).
  final Map<String, String?> hashes;

  /// The SHA-256 of [content], a `String` (as UTF-8) or bytes, in hex.
  static String hashOf(Object content) => sha256
      .convert(content is String ? utf8.encode(content) : content as List<int>)
      .toString();

  /// The text of a manifest that lists [hashes] (files in sorted order)
  /// generated from [inputs]: JSON with sorted keys, the same for the same
  /// files.
  static String render(Map<String, String> hashes, {required String inputs}) =>
      '${const JsonEncoder.withIndent('  ').convert({
        'generator': generator,
        'format': format,
        'inputs': inputs,
        'files': hashes,
      })}\n';

  /// The manifest in [file], or null when it is missing, does not parse or
  /// does not name this generator, in any version.
  static OutputManifest? read(File file) {
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?> ||
          json['generator'] is! String ||
          !(json['generator']! as String).startsWith('$generatorName ')) {
        return null;
      }
      return OutputManifest(switch (json['files']) {
        final Map<String, Object?> files => {
          for (final MapEntry(:key, :value) in files.entries)
            key: value is String && _sha256Hex.hasMatch(value) ? value : null,
        },
        final List<Object?> names => {
          for (final name in names)
            if (name is String) name: null,
        },
        _ => const {},
      });
    } on FormatException {
      return null;
    }
  }

  /// Why the file [path] with [hash] is not the generator's to replace
  /// according to [written], or null when it is.
  static String? strayReason(
    OutputManifest? written,
    String path,
    String hash,
  ) {
    if (written == null || !written.hashes.containsKey(path)) {
      return 'not written by $generatorName';
    }
    final listed = written.hashes[path];
    if (listed == null) {
      return 'no hash in the manifest of an older $generatorName';
    }
    return listed == hash ? null : 'changed since $generatorName wrote it';
  }
}

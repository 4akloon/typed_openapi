import 'dart_code.dart';
import 'dart_writer.dart';

/// The imports of one generated file, written in sections (`dart:`,
/// `package:`, relative), each sorted, with a sorted `show` list for every
/// library but the relative ones.
final class Imports {
  /// Creates the imports of the file [self], which is not imported.
  Imports(this.self);

  /// The runtime library generated code imports.
  static const runtime =
      'package:typed_openapi_runtime/typed_openapi_runtime.dart';

  static const _code = DartCode();

  /// The path of the file, relative to its directory.
  final String self;

  final Map<String, Set<String>> _shown = {};
  final Set<String> _files = {};

  /// Imports [name] from the library [uri].
  void show(String uri, String name) => (_shown[uri] ??= {}).add(name);

  /// Imports [name] from the runtime library.
  void fromRuntime(String name) => show(runtime, name);

  /// Imports the generated file [path], next to this one.
  void file(String path) {
    if (path != self) _files.add(path);
  }

  /// Writes the import directives, with an empty line after each section.
  void write(DartWriter out) {
    final libraries = _shown.keys.toList()..sort();
    final sections = [
      [
        for (final uri in libraries)
          if (uri.startsWith('dart:')) uri,
      ],
      [
        for (final uri in libraries)
          if (!uri.startsWith('dart:')) uri,
      ],
    ];
    for (final section in sections) {
      if (section.isEmpty) continue;
      for (final uri in section) {
        final names = _shown[uri]!.toList()..sort();
        final flat = 'import ${_code.string(uri)} show ${names.join(', ')};';
        if (flat.length <= out.width) {
          out.line(flat);
        } else {
          out
            ..line('import ${_code.string(uri)}')
            ..indented(
              () => out.indented(() => out.line('show ${names.join(', ')};')),
            );
        }
      }
      out.line();
    }
    if (_files.isEmpty) return;
    for (final path in _files.toList()..sort()) {
      out.line('import ${_code.string(path)};');
    }
    out.line();
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds relative Markdown links that lead to a missing file or heading.
final class DocLinks {
  /// Creates a checker that names files relative to [root].
  const DocLinks(this.root);

  /// The directory the reported file names are relative to.
  final String root;

  static final RegExp _link = RegExp(
    r'!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)',
  );
  static final RegExp _scheme = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:');
  static final RegExp _fence = RegExp(r'^\s*(```|~~~)');
  static final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$');

  /// One `file:line: target (reason)` per broken relative link of [files].
  List<String> problems(Iterable<File> files) {
    final found = <String>[];
    for (final file in files) {
      final lines = file.readAsStringSync().split('\n');
      final prose = _proseLines(lines);
      for (var i = 0; i < lines.length; i++) {
        final line = prose[i];
        if (line == null) continue;
        for (final match in _link.allMatches(line)) {
          final target = match.group(1)!;
          final reason = _reasonOf(file, target);
          if (reason == null) continue;
          final name = p.relative(file.path, from: root);
          found.add('$name:${i + 1}: $target ($reason)');
        }
      }
    }
    return found;
  }

  String? _reasonOf(File from, String target) {
    if (_scheme.hasMatch(target)) return null;
    final hash = target.indexOf('#');
    final path = hash < 0 ? target : target.substring(0, hash);
    final anchor = hash < 0 ? null : target.substring(hash + 1);
    final destination = path.isEmpty
        ? from.path
        : p.normalize(p.join(from.parent.path, Uri.decodeFull(path)));
    final isFile = File(destination).existsSync();
    if (!isFile && !Directory(destination).existsSync()) return 'no such file';
    if (anchor == null || anchor.isEmpty) return null;
    if (!isFile || !destination.endsWith('.md')) return null;
    return anchors(File(destination)).contains(anchor)
        ? null
        : 'no such heading';
  }

  /// The GitHub anchors of the headings of [file].
  Set<String> anchors(File file) {
    final lines = file.readAsStringSync().split('\n');
    final prose = _proseLines(lines, blankSpans: false);
    final seen = <String, int>{};
    final result = <String>{};
    for (final line in prose) {
      final text = line == null ? null : _heading.firstMatch(line)?.group(1);
      if (text == null) continue;
      final slug = _slug(text);
      final count = seen[slug] ?? 0;
      seen[slug] = count + 1;
      result.add(count == 0 ? slug : '$slug-$count');
    }
    return result;
  }

  static String _slug(String heading) => heading
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp('[`*~]'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}_ -]', unicode: true), '')
      .replaceAll(' ', '-');

  /// The lines outside fenced blocks, code spans blanked; null inside a fence.
  static List<String?> _proseLines(
    List<String> lines, {
    bool blankSpans = true,
  }) {
    var inFence = false;
    final result = <String?>[];
    for (final line in lines) {
      if (_fence.hasMatch(line)) {
        inFence = !inFence;
        result.add(null);
      } else if (inFence) {
        result.add(null);
      } else {
        result.add(blankSpans ? line.replaceAll(RegExp('`[^`]*`'), '') : line);
      }
    }
    return result;
  }
}

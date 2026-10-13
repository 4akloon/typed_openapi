import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One entry of a [TarArchive].
final class TarEntry {
  /// A regular file [name] with [content].
  const TarEntry.file(this.name, [this.content = ''])
    : type = '0',
      linkName = '';

  /// A directory [name].
  const TarEntry.directory(this.name) : type = '5', content = '', linkName = '';

  /// A symbolic link [name] to [linkName].
  const TarEntry.symlink(this.name, this.linkName) : type = '2', content = '';

  /// A hard link [name] to [linkName].
  const TarEntry.hardlink(this.name, this.linkName) : type = '1', content = '';

  /// The name exactly as written in the header, so `../x` and `/x` are
  /// possible, which the system `tar` would never create.
  final String name;

  /// The tar type flag: `0` file, `1` hard link, `2` symbolic link, `5`
  /// directory.
  final String type;

  /// The text of a regular file.
  final String content;

  /// What a link points to.
  final String linkName;
}

/// Builds the bytes of a `.tar.gz` by hand (ustar headers), so a test can
/// craft entries that the system `tar` refuses to write.
final class TarArchive {
  /// Creates the archive of [entries].
  const TarArchive(this.entries);

  /// The entries, in order.
  final List<TarEntry> entries;

  /// The gzip-compressed archive.
  List<int> toTarGz() {
    final tar = BytesBuilder();
    for (final entry in entries) {
      final body = utf8.encode(entry.content);
      tar
        ..add(_header(entry, body.length))
        ..add(body)
        ..add(Uint8List((512 - body.length % 512) % 512));
    }
    tar.add(Uint8List(1024));
    return gzip.encode(tar.takeBytes());
  }

  static Uint8List _header(TarEntry entry, int size) {
    final header = Uint8List(512);
    void put(int offset, int length, String text) =>
        header.setRange(offset, offset + text.length, ascii.encode(text));
    put(0, 100, entry.name);
    put(100, 8, entry.type == '5' ? '0000755\u0000' : '0000644\u0000');
    put(108, 8, '0000000\u0000');
    put(116, 8, '0000000\u0000');
    put(124, 12, '${size.toRadixString(8).padLeft(11, '0')}\u0000');
    put(136, 12, '${'0'.padLeft(11, '0')}\u0000');
    put(148, 8, '        ');
    put(156, 1, entry.type);
    put(157, 100, entry.linkName);
    put(257, 6, 'ustar\u0000');
    put(263, 2, '00');
    final checksum = header.fold(0, (sum, byte) => sum + byte);
    put(148, 8, '${checksum.toRadixString(8).padLeft(6, '0')}\u0000 ');
    return header;
  }
}

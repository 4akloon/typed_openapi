import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:typed_openapi_core/typed_openapi_core.dart';
import '../generate/output_writer.dart';

/// The hash a manifest records as `inputs`: what the emitters read.
///
/// The emitters read the IR, the line width and the client's name (it names
/// the root file); everything else the run reads (comments, components no
/// operation reaches, operations a filter leaves out, the config's text,
/// the preset and the rules) acts before the IR, so it counts only through
/// its effect on it. Locations in the IR are relative to the working
/// directory, never absolute, so the hash is the same on any machine.
final class GenerationInputs {
  const GenerationInputs._();

  /// The hash of what the code of [client] is generated from: its [ir],
  /// written by [irJson].
  static String of(ClientConfig client, ClientIr ir, IrJson irJson) {
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'generator': OutputWriter.generator,
              'client': client.name,
              'line_width': client.lineWidth,
              'ir': irJson.toJson(ir),
            }),
          ),
        )
        .toString();
  }
}

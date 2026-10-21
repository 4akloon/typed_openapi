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
/// its effect on it. The IR is written without locations, which no emitter
/// reads, so the hash does not depend on where the spec is or on the
/// working directory of the run.
final class GenerationInputs {
  const GenerationInputs._();

  static const _irJson = IrJson.withoutLocations();

  /// The hash of what the code of [client] is generated from: its [ir].
  static String of(ClientConfig client, ClientIr ir) {
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'generator': OutputWriter.generator,
              'client': client.name,
              'line_width': client.lineWidth,
              'ir': _irJson.toJson(ir),
            }),
          ),
        )
        .toString();
  }
}

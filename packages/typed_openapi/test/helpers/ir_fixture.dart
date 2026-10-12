import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir_context.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';

/// A spec read from text, normalized, with an [IrContext] for a client
/// configured by [generation] and [overrides].
final class IrFixture {
  /// Loads [text] as `api.yaml` and normalizes it with [overrides] (the
  /// text of `o.yaml`); the texts must load.
  IrFixture(
    String text, {
    GenerationConfig generation = const GenerationConfig(),
    String? overrides,
    Preset? preset,
  }) {
    final document = SpecLoader(diagnostics).parse(text, 'api.yaml')!;
    final version = OpenApiVersionDetector(diagnostics).detect(document)!;
    final set = overrides == null
        ? null
        : OverrideLoader(diagnostics).parse(overrides, 'o.yaml');
    final spec = Normalizer(
      diagnostics,
      preset: preset,
    ).normalize(document, version, overrides: set);
    before = diagnostics.all.length;
    context = IrContext(
      diagnostics,
      spec,
      ClientConfig(
        name: 'api',
        input: 'api.yaml',
        output: 'lib/api',
        lineWidth: 80,
        preset: preset,
        generation: generation,
      ),
    );
  }

  /// Every diagnostic.
  final DiagnosticBag diagnostics = DiagnosticBag();

  /// How many diagnostics loading and normalizing reported.
  late final int before;

  /// The context for building the IR.
  late final IrContext context;

  /// The diagnostics reported after normalizing, in report order.
  List<Diagnostic> get reported => diagnostics.all.skip(before).toList();

  /// The codes and pointers of [reported].
  List<(DiagnosticCode, String?)> get codes => [
    for (final d in reported) (d.code, d.pointer?.value),
  ];
}

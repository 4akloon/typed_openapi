import 'package:typed_openapi_core/typed_openapi_core.dart';

/// A spec read from text and normalized, ready to build the IR of a client
/// configured by [generation] and [overrides].
class NormalizedFixture {
  /// Loads [text] as `api.yaml` and normalizes it with [overrides] (the
  /// text of `o.yaml`) and [preset]; the texts must load.
  NormalizedFixture(
    String text, {
    GenerationConfig generation = const GenerationConfig(),
    String? overrides,
    Preset? preset,
    String clientName = 'api',
  }) {
    final document = SpecLoader(diagnostics).parse(text, 'api.yaml')!;
    final version = OpenApiVersionDetector(diagnostics).detect(document)!;
    final set = overrides == null
        ? null
        : OverrideLoader(diagnostics).parse(overrides, 'o.yaml');
    // Assigned here, not in the initializer list: they depend on the
    // diagnostics that loading fills.
    spec = Normalizer(
      diagnostics,
      preset: preset,
    ).normalize(document, version, overrides: set);
    before = diagnostics.all.length;
    client = ClientConfig(
      name: clientName,
      input: 'api.yaml',
      output: 'lib/api',
      lineWidth: 80,
      preset: preset,
      generation: generation,
    );
  }

  /// Every diagnostic.
  final DiagnosticBag diagnostics = DiagnosticBag();

  /// How many diagnostics loading and normalizing reported.
  late final int before;

  /// The normalized spec.
  late final NormalizedSpec spec;

  /// The client the IR is built for.
  late final ClientConfig client;

  /// The diagnostics reported after normalizing, in report order.
  List<Diagnostic> get reported => diagnostics.all.skip(before).toList();

  /// The IR of the client, with the names of [names] kept.
  ClientIr build({NameLock names = NameLock.none}) =>
      IrBuilder(diagnostics, names: names).build(spec, client);

  /// The diagnostics of [reported] with [code].
  List<Diagnostic> reportedOf(DiagnosticCode code) => [
    for (final d in reported)
      if (d.code == code) d,
  ];

  /// The codes and pointers of [reported].
  List<(DiagnosticCode, String?)> get codes => [
    for (final d in reported) (d.code, d.pointer?.value),
  ];
}

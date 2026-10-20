import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'generated_notice.dart';

/// The fixed prose around the entries of the diagnostics reference.
final class DiagnosticsIntro {
  /// Creates the prose for a reference of [count] codes.
  DiagnosticsIntro(this.count);

  /// The number of codes in the reference.
  final int count;

  /// The notice, the title, the sample report and the severity section.
  String get opening => '${GeneratedNotice.markdown}$_title$_severity';

  String get _title =>
      '''
# Diagnostics reference

Every problem `typed_openapi` finds in a spec, an overrides file, a baseline or a config has a stable code such as `TOA501`. This guide is the single reference for all $count codes: what each one means and how to fix it. It is generated from the doc comments of the `DiagnosticCode` enum, so it cannot drift from the tool. Other guides link here instead of repeating the table.

```text
warning TOA501 missing-path-parameter: The path /products/{id} has {id}, but this operation declares no path parameter "id"; it is added as a required string path parameter.
  --> specs/shop.yaml:30:7
  at #/paths/~1products~1{id}/get
  fix: Declare each at the source as {name: <name>, in: path, required: true, schema: {type: string}}.
```

A code never changes meaning once released. The slug (`missing-path-parameter`) is its readable name; both work wherever a code is accepted.

''';

  String get _severity =>
      '''
## Severity and levels

Every code has a default severity: `error`, `warning` or `info`. Errors make `check` and `generate` exit with `1`; warnings and infos do not (see [CLI](cli.md#exit-codes)). A client changes the level of a code in `severity:` of the config, by id or by slug, and `off` removes the code from the report (see [Configuration](configuration.md#severity)).

```yaml
clients:
  shop:
    input: specs/shop.yaml
    output: lib/src/api/shop
    severity:
      TOA201: info
      duplicate-operation-id: error
      TOA553: off
```

Three groups of codes are limited:

| Group | Codes | Rule |
| --- | --- | --- |
| Config codes | $_configCodes | The level cannot be changed at all, because the config is read before levels apply. Setting one is TOA902. Marked `config` below. |
| Fixed codes | Marked `fixed` below | The level can be raised but not lowered, and they cannot be turned off. |
| Everything else | All other codes | Any of `error`, `warning`, `info`, `off`. |

> **Note:** A baseline accepts only errors and warnings of codes that are not fixed. Infos are never accepted. See [Baseline](baseline.md).

The "Default" column is the severity before `severity:` applies.

> **Gotcha:** Two diagnostics that are equal (same code, severity, message, file, pointer and start position) are reported once, so a region of the spec that is read twice does not repeat its problems.

''';

  /// The ids of the config codes, such as `TOA901, TOA902`.
  String get _configCodes {
    final ids = [for (final code in DiagnosticCode.configCodes) code.id]
      ..sort();
    return ids.join(', ');
  }

  /// Codes with a number from [from] to [to], as `TOA001-TOA022`.
  static String _span(int from, int to) {
    final ids = [
      for (final code in DiagnosticCode.values)
        if (int.parse(code.id.substring(3)) case final n
            when n >= from && n <= to)
          code.id,
    ]..sort();
    return ids.length == 1 ? ids.single : '${ids.first}-${ids.last}';
  }

  /// The sections after the last area.
  String get closing =>
      '''
## Where codes are reported

| Stage | Codes | Reported by |
| --- | --- | --- |
| Reading files | ${_span(0, 99)} | `check`, `generate`, `baseline` |
| Normalizer rules | TOA106, TOA201-TOA208, TOA211, TOA301, TOA303, TOA401, TOA402, TOA501-TOA504, TOA601 | one of the normalizer rules, see [Presets and rules](presets_and_rules.md) |
| Mapping to Dart | the other TOA2xx-TOA6xx | the IR builder while it names and types the client |
| Overrides | ${_span(560, 560)}, ${_span(800, 819)} | the overrides file, see [Overrides](overrides.md) |
| Baseline | ${_span(820, 829)} | see [Baseline](baseline.md) |
| Generate | ${_span(830, 839)} | see [Generated output](generate_output.md) and [the API lock](cli.md#the-api-lock) |
| Config | ${_span(900, 999)} | see [Configuration](configuration.md) |

## See also

- [CLI](cli.md): formats and exit codes.
- [Configuration](configuration.md): the `severity` key.
- [Baseline](baseline.md): accept diagnostics you cannot fix yet.
- [Presets and rules](presets_and_rules.md): the normalizer rules behind TOA2xx to TOA5xx.
- [Extensions](extensions.md): the `x-` keys of a spec.
''';
}

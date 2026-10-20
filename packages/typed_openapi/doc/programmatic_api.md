# Programmatic API

The pipeline the command line uses lives in two libraries: `package:typed_openapi_core/typed_openapi_core.dart` (the engine: config, checks, diagnostics, the IR) and `package:typed_openapi/typed_openapi.dart` (the generator: the command line, the emitters and the output writer). Together they cover: load a config, check the specs, build the semantic model of each client, write files. It is meant for tools that wrap the generator (a build script, an editor plugin, a test). Everything the CLI reports is also available as data.

> **Note:** The API may change before 1.0 (the current version is 0.1.0). `ApiLibrary` writes the whole client that [`typed_openapi generate`](cli.md#generate) writes; `ModelLibrary` writes only its model files.

## Entry points

| Class | Library | What it does |
| --- | --- | --- |
| `TypedOpenApiCli` | generator | The command line as a class. `run(args)` returns the exit code; it never calls `exit()`. Reports go to `out`, usage errors to `err`, relative paths resolve against `workingDirectory`. |
| `DiagnosticBag` | core | Where every stage reports problems. Pass one to each component below. |
| `ConfigLoader` | core | `load(path)` reads `typed_openapi.yaml` into a `ProjectConfig` (its `clients` are `ClientConfig`s). It returns `null` when the file is missing or unusable, with the reason in the bag (TOA901, TOA902). |
| `SpecChecker` | core | `check(config, {only, strictBaseline})` checks every client and applies its levels and baseline; `checkClients` does the same without baselines. Both return one `ClientCheck` per client. |
| `ClientCheck` | core | The result for one client: `client`, `diagnostics`, `errors` (errors left after levels and baseline), `ir` (`null` when the spec could not be read), `irJson`, and `sources` (the files that were read). |
| `ApiLibrary` | generator | `files(ir, client: name)` returns every file of the client, as `generate` writes them: the models, a file per group in `api/` with the barrel `api.dart`, and the root client `<client>.dart`, as a map from path to text sorted by path. `ApiLibrary(width: 80)` sets the line width (`ClientConfig.lineWidth`). |
| `ModelLibrary` | generator | `files(ir)` returns the model files (`models/<name>.dart` and the barrel `models.dart`) as a map from path to text, sorted by path. |
| `OutputWriter` | generator | `write(client, files, inputs: ...)` writes a map of files into the client's output directory with the [atomic, ownership-checked procedure](generate_output.md) and returns an `OutputChanges` (`written`, `unchanged`, `deleted`, `forced`), or `null` after reporting why nothing was written. |
| `SpecLinter` | core | `lint(input, {preset})` checks one spec file with no config, as [`typed_openapi lint`](cli.md#lint) does, and returns a `LintResult`: `diagnostics` (a `DiagnosticBag` whose fixes are for the backend team), `detection` (the preset and why), `isChosen` (whether the caller named the preset) and `isRead` (whether the spec could be read far enough to check). It builds no IR. |
| `TextReporter`, `JsonReporter`, `SarifReporter`, `GitHubActionsReporter` | core | Turn a bag into the [report formats](cli.md#formats). |

The core also exports the loader (`SpecLoader`, `SpecDocument`), the typed model of the spec (`OpenApiDocument` and the other OpenAPI objects), the normalizer (`Normalizer`, `NormalizerRule`, `Finding`, `SpecEdit`), the overrides reader (`OverrideLoader`, `OverrideSet`), the baseline classes (`Baseline`, `BaselineLoader`) and the IR (`IrBuilder`, `ClientIr`, `DartType`, ...). Each has a doc comment in the source; this guide covers the path from config to files.

## Check a config and write the client

`pets.yaml` has one client, and `specs/pets.yaml` is a spec with a `Pet` schema and one `GET /pets` operation:

```yaml
clients:
  pets:
    input: specs/pets.yaml
    output: lib/pets
```

```dart
import 'package:typed_openapi/typed_openapi.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

void main() {
  final diagnostics = DiagnosticBag();
  final config = ConfigLoader(diagnostics).load('pets.yaml');
  if (config == null) return;

  final checker = SpecChecker(diagnostics);
  final checks = checker.check(config);
  print(const TextReporter().format(diagnostics));

  for (final check in checks) {
    final ir = check.ir;
    if (ir == null || check.errors > 0) continue;
    final files = ApiLibrary(width: check.client.lineWidth)
        .files(ir, client: check.client.name);
    final changes = OutputWriter(diagnostics)
        .write(check.client, files, inputs: 'my-run');
    if (changes == null) continue;
    print(
      '${check.client.name}: ${files.keys.join(', ')}; '
      '${changes.written} written, ${changes.unchanged} unchanged',
    );
  }
}
```

Running it twice prints (the spec has no tags, hence the info TOA554; the output was analysed with `dart analyze` and has no issues):

```text
info TOA554 operation-untagged: No operation of the spec has a tag, so all operations are in DefaultApi.
  --> specs/pets.yaml:4:3
  at #/paths
  fix: Tag the operations at the source, or set group_by to path or single in the config.
errors: 0, warnings: 0, infos: 1
pets: api.dart, api/default_api.dart, models.dart, models/pet.dart, models/pet_status.dart, pets.dart; 6 written, 0 unchanged
(the same report again)
pets: api.dart, api/default_api.dart, models.dart, models/pet.dart, models/pet_status.dart, pets.dart; 0 written, 6 unchanged
```

Notes on the example:

- `errors > 0` is the same test `generate` uses to skip a client. Without it you would write models from a spec that has errors.
- `inputs` is the hash recorded in the manifest `.typed_openapi.json`; the CLI computes it from the files that were read and the client's settings. Pass the same string for the same inputs.
- Problems from the writer (TOA830 to TOA833) go to the same bag, so print it after `write` too if you want to see them.
- An error in the user's input is never thrown. The bag collects it; check `diagnostics.hasErrors` or `ClientCheck.errors`.

## Run the command line from code

```dart
import 'dart:io';

import 'package:typed_openapi/typed_openapi.dart';

Future<void> main() async {
  final cli = TypedOpenApiCli(workingDirectory: Directory.current.path);
  exitCode = await cli.run(['check', '-c', 'pets.yaml']);
}
```

This prints `errors: 0, warnings: 0, infos: 0` and exits `0` for the config above. Pass `out:` a `StringBuffer` to capture the report in a test. The exit codes are the ones in [Command line](cli.md#exit-codes).

## See also

- [Command line](cli.md): what the commands do and their exit codes.
- [Configuration](configuration.md): the keys of `ProjectConfig`.
- [Generated output](generate_output.md): what `OutputWriter` guarantees.
- [Diagnostics](diagnostics.md): the codes in the bag.

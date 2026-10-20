# Release checklist

How to release `0.1.0` (and, with the version changed, any later lockstep
release) of the four published packages: `typed_openapi_core`,
`typed_openapi_client`, `typed_openapi` and `typed_openapi_dio`. They share
one version and are published in that order. The other three packages
(`typed_openapi_tool`, `typed_openapi_test_support`,
`typed_openapi_transport_tests`) are `publish_to: none` and are never
released.

Nothing in the repository publishes, tags or pushes by itself. Every step
below is done by a maintainer.

The names `typed_openapi_core`, `typed_openapi_client`, `typed_openapi` and
`typed_openapi_dio` were checked free on pub.dev on 2026-10-20
(`https://pub.dev/api/packages/<name>` answered 404 for each). Check again
right before the first publish: a name taken in between ends the plan.

In the commands below `<version>` is the release, such as `0.1.0`.

## Before the tag

1. **Run the gates** at the repository root and in each package, on a clean
   tree: `dart pub get`, `dart analyze packages` (prints `No issues found!`),
   `dart format` twice (the second run changes 0 files), `dart test` in the
   core, the generator, the client, the Dio transport and the tool,
   `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm` in the
   client and the Dio transport, and in `packages/typed_openapi_tool`
   `dart run bin/corpus.dart check` (ends with `0 differences from the lock.`)
   and `dart run bin/fuzz.dart --seeds 200`.
2. **Choose the version and set it everywhere.** It is set in four
   `pubspec.yaml` files (`version:`), in every sibling constraint
   (`^<version>`, in `dependencies` and `dev_dependencies`, also in the two
   unpublished packages that depend on a sibling, so the workspace
   resolves) and in `OutputManifest.generator`
   (`packages/typed_openapi/lib/src/generate/output_manifest.dart`,
   `typed_openapi <version>`). The manifest is not part of the `corpus.lock`
   hashes, so the generator string changes no lock or golden file (checked
   at 0.1.0: 0 differences).
   `lockstep_versions_test` and `release_readiness_test` in the tool package
   fail when the pubspecs disagree.
3. **Drop ` - Unreleased`** from the top heading of each of the four
   `CHANGELOG.md` files (`## <version>`). `release_readiness_test` needs the
   heading to start with `## <version>`.
4. **Fix the install text.** Find every place that says the packages are not
   on pub.dev:

   ```sh
   grep -rn "not on pub.dev\|not published\|Nothing is published\|pre-release" README.md packages/*/README.md packages/*/doc
   ```

   The root README and the READMEs of the four packages say "pre-release" or
   "not published yet" in their status lines; the install sections of
   `packages/typed_openapi/doc/getting_started.md`, `cli.md`, `ci.md`,
   `client_for_grund.md`, and `packages/typed_openapi_client/doc/getting_started.md`
   tell the reader to use a path or git dependency. After the release they
   say: install with `dart pub add typed_openapi_client typed_openapi_dio`
   and `dart pub add --dev typed_openapi` (or `dart pub global activate
   typed_openapi`), with the git and path forms kept only as the way to
   follow `main`. Also check `packages/typed_openapi_transport_tests/README.md`
   (it says "not published" and stays true) and `README.ua.md` (see the open
   items).
5. **Pin the schema URLs to the tag.** The editor lines point at `main`.
   Change `.../typed_openapi/main/packages/typed_openapi/schema/...` to
   `.../typed_openapi/typed_openapi-v<version>/packages/typed_openapi/schema/...`
   in `packages/typed_openapi/doc/configuration.md`, `doc/overrides.md` and
   `packages/typed_openapi/example/typed_openapi.yaml`, and drop the "pin it
   to a release tag once one exists" sentences next to them. The tag does
   not exist yet when the pull request is merged, so the URL answers 404
   until the tag is pushed; push the tag soon after the merge.
6. **Dry-run each package in publish order**, from its own directory, on the
   PR branch, and again on the merge commit before the first
   `dart pub publish` (a dirty tree adds a warning that is not a defect):

   ```sh
   cd packages/typed_openapi_core   && dart pub publish --dry-run
   cd packages/typed_openapi_client && dart pub publish --dry-run
   cd packages/typed_openapi        && dart pub publish --dry-run
   cd packages/typed_openapi_dio    && dart pub publish --dry-run
   ```

   Each must end with `Package has 0 warnings.` The archives were about
   455 KB (core), 120 KB (client), 252 KB (typed_openapi) and 11 KB (Dio) at
   0.1.0. A dependent package resolves its sibling through the workspace in a
   dry run, so a dry run before the first publish does not prove that the
   sibling exists on pub.dev; that is proved by publishing in order.
7. **Open one pull request** with steps 2 to 5, wait for CI, merge it. Tag
   and publish from the merge commit on `main`, never from a branch.

## First publish (by hand)

pub.dev allows automated publishing only for a package that exists, so the
first version of each package is published from a maintainer's machine, from
the merge commit, in this order, each from its own directory:

```sh
cd packages/typed_openapi_core   && dart pub publish
cd packages/typed_openapi_client && dart pub publish
cd packages/typed_openapi        && dart pub publish
cd packages/typed_openapi_dio    && dart pub publish
```

`dart pub publish` asks for confirmation and, if the machine is not signed
in, opens a browser for the Google sign-in; this is done by the maintainer,
not by a script. Wait until a package shows on pub.dev before publishing the
one that depends on it: `typed_openapi` needs `typed_openapi_core` and
`typed_openapi_dio` needs `typed_openapi_client`.

Then, for each of the four packages on pub.dev (Admin, Automated
publishing), enable publishing from GitHub Actions: repository
`4akloon/typed_openapi`, tag pattern `<package>-v{{version}}` (for example
`typed_openapi_core-v{{version}}`), and require the GitHub environment
`pub.dev` (the environment must exist in the repository settings).
`.github/workflows/publish.yml` publishes with the OIDC credential on a tag
`<package>-v<version>` and checks that the tag's version equals the
package's `pubspec.yaml`.

## Tags and binaries

Tag the merge commit, one tag per package, in publish order:

```sh
git tag typed_openapi_core-v<version>
git tag typed_openapi_client-v<version>
git tag typed_openapi-v<version>
git tag typed_openapi_dio-v<version>
git push origin typed_openapi_core-v<version>
# wait until typed_openapi_core <version> shows on pub.dev, then:
git push origin typed_openapi_client-v<version>
# and so on, one tag at a time, in this order
```

For the first release (published by hand) only `typed_openapi-v<version>` is
needed: it starts `release.yml`, which builds the binaries. Its
`publish.yml` run fails because the version already exists on pub.dev; that
failure is expected and ignored. Pushing the other three tags is optional
for the first release. From the second release on, push the tags one at a
time, in publish order, each only after the previous package shows on
pub.dev. `publish.yml` does not order the runs (one parallel run per tag), so
a dependent package's run started early can fail because its dependency is
not on pub.dev yet. GitHub may also not start every run when several tags
are pushed at once.

`release.yml` (tag `typed_openapi-v*`) checks the tag against
`packages/typed_openapi/pubspec.yaml`, compiles `typed_openapi` with
`dart compile exe` on five runners (linux-x64, linux-arm64 cross-compiled,
macos-x64, macos-arm64, windows-x64), smoke-tests the native ones, packs each
with the licence through `release/package.sh`
(`typed_openapi-<version>-<target>.tar.gz` and its `.sha256`) and creates a
GitHub release with the five archives and `SHA256SUMS`.

Check the release:

1. The release lists five `.tar.gz` archives and `SHA256SUMS`.
2. On a machine: download an archive and `SHA256SUMS` into one empty
   directory, run `sha256sum --check --ignore-missing SHA256SUMS`, unpack the
   archive and run `./typed_openapi --help`.
3. In a scratch repository, a workflow that uses the action
   (`4akloon/typed_openapi/action@typed_openapi-v<version>` with
   `version: <version>` and a `spec:` file) runs `lint` and reports.

If a build fails: fix the cause on `main` through a pull request, then move
the tag only if no archive was published and nobody has downloaded the
release; otherwise release the next patch version. A release created
partially (some archives missing) is deleted in the GitHub UI before the
tag is moved. Never edit the archives by hand: `SHA256SUMS` is written from
what the build produced.

## After the release

1. Set the status lines of the READMEs to the released version if the
   release changed them (step 4 of "Before the tag" removed the
   "pre-release" wording).
2. Update the roadmap (`docs/roadmap.md`): mark the 0.1.0 release done.
3. When the first change after the release needs it, add a heading
   `## <next version> - Unreleased` at the top of the CHANGELOG of the
   package it changes (a package without changes keeps its last heading;
   lockstep means the version still moves for all four at the next release).
4. Decide on SchemaStore (below) and on moving `helpUri` (open items).

## SchemaStore

Decision 6 of the M13 plan: the schemas are not submitted to SchemaStore by
the work of M13; this section is the text for a maintainer who does it after
the tag exists. The two catalog entries of `src/api/json/catalog.json`:

```json
{
  "name": "typed_openapi",
  "description": "Configuration of the typed_openapi Dart client generator",
  "fileMatch": ["typed_openapi.yaml", "typed_openapi.yml"],
  "url": "https://raw.githubusercontent.com/4akloon/typed_openapi/typed_openapi-v<version>/packages/typed_openapi/schema/typed_openapi.schema.json"
}
```

```json
{
  "name": "typed_openapi overrides",
  "description": "Overrides file of the typed_openapi Dart client generator",
  "fileMatch": [],
  "url": "https://raw.githubusercontent.com/4akloon/typed_openapi/typed_openapi-v<version>/packages/typed_openapi/schema/typed_openapi.overrides.schema.json"
}
```

The overrides file can have any name (it is named in the config), so its
`fileMatch` is empty. Both URLs are pinned to the tag so the schema a
catalog serves does not change under it.

SchemaStore's contribution guide describes the checks for a catalog entry;
it was not read for this checklist, so confirm the current procedure before
submitting. The check command named in the M13 plan, run in a checkout of
the SchemaStore repository, is `node ./cli.js check --schema-name=<name>.json`
(for a schema added under `src/schemas/json/`). A schema referenced by URL
from the catalog may need a different check; verify.

Text for the pull request: "Add typed_openapi, the configuration file of an
OpenAPI to Dart client generator (https://github.com/4akloon/typed_openapi).
The schema is generated from the key catalog the tool reads and a test in
the repository checks that the tool accepts what the schema accepts and
rejects what it rejects. The URLs are pinned to the release tag. The
overrides file has no fixed name, so its entry has an empty fileMatch."

## Open items

These could not be verified while preparing 0.1.0 and are decided or checked
by the maintainer at release.

- **`helpUri` is not pinned to a tag.** `DiagnosticCode.helpUri` (core)
  hard-codes
  `https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/diagnostics.md#...`,
  so SARIF logs written by any version link to the guide on `main`. Decide
  at release whether to pin it to the tag (the URL would then need the
  version at build time) or accept that old logs follow `main`.
- **Framework hints cite facts read once.** The hint for ASP.NET TOA401
  (dotnet/aspnetcore#60469) and the one for NestJS TOA303 (`@nestjs/swagger`
  12) cite facts re-read on 2026-10-20. Re-read both sources before the
  release and fix the hints if they moved.
- **Release automation has never run on GitHub.** The macOS and Windows
  binaries, the composite action (`action/action.yml`) and `release.yml`
  have not run on GitHub; the first release is the real test. Consider a
  dry-run tag in a fork first (a tag `typed_openapi-v<version>` in a fork
  runs `release.yml` there; `publish.yml` fails in the fork for lack of the
  pub.dev setup, which is harmless).
- **`install.sh` on macOS.** The `curl` flags and the bsdtar member
  extraction in `action/install.sh` are unexercised on macOS.
- **`README.ua.md` lacks the new guides.** `packages/typed_openapi/README.ua.md` and
  `packages/typed_openapi_client/README.ua.md` do not link
  the guides added in M13; update them or leave them marked as older.
- **The git-dependency install path is untested** until the first
  publication: the install text that tells users to depend on the
  repository by git has been written, not run, against a published
  `typed_openapi_core`/`typed_openapi_client` split.
- **The vendored YAML scanner.** `packages/typed_openapi_core/lib/src/load/yaml/`
  carries a local fix (linear cost on long flow lines) proposed upstream as
  dart-lang/tools#2658. When it is merged and released, update the vendored
  copy and the note in
  `packages/typed_openapi_core/lib/src/load/yaml/analysis_options.yaml`.
- **The exact pub.dev flow.** Steps that sign in to pub.dev, enable
  automated publishing and read pub.dev's current limits (for example
  whether it allows several tags in one push, or the topics rules) follow
  pub.dev's documentation as of writing and were not run here. Read
  https://dart.dev/tools/pub/publishing and
  https://dart.dev/tools/pub/automated-publishing before the first publish.
- **Upload size.** The dry runs include each package's `test/` directory in
  the archive (about 455 KB for the core). Decide whether a `.pubignore`
  should leave tests out; it changes nothing the user sees.

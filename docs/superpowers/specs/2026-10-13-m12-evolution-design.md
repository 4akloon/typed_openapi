# M12: evolution — API snapshot, change report, name lock — design

**Date:** 2026-10-13.

**Requirements:**
- R14.1 [MUST]: a report of changes between regenerations, with breaking changes of the Dart API reported separately.
- R14.2 [SHOULD]: a new enum value, union variant or optional field does not break the consumer's compiled code.

See [requirements.md](../../requirements.md).

**Roadmap:** row M12 ("`diff` between regenerations with change categories (including source-breaking for an exhaustive `switch`), lock file").

**Earlier stages:**
- [M6 design](2026-10-12-m6-ir-design.md): the IR and naming with `NameScope`.
- [M8 design](2026-10-12-m8-models-design.md): sealed unions and enums, the `exhaustive` override, the manifest.
- [M9](2026-10-13-m9-operations-design.md) and [M10](2026-10-13-m10-sse-design.md): operations, status types and event unions.
- [M11](2026-10-13-m11-corpus-design.md): `corpus.lock` detects that output changed. M12 says what changed and how it affects users.

The user took these decisions in a grilling session.

## Decisions

1. **The diff compares an API snapshot built from the IR.**
   - The snapshot is the client's public surface:
     - types, with their kind: model, enum, union, status type, event union, group, root;
     - fields and constructors, with types and required-ness;
     - union variants;
     - enum values;
     - methods, with their parameters, return types and status variants;
     - wire facts: the JSON key of each field, the path, method, style and media types of each operation, and its statuses.
   - Every entry carries a stable identity: the spec location of a schema, or the operation's `operationId` / `METHOD /path`.
   - The snapshot is deterministic and is built without `package:analyzer`, which the generator core may not depend on.

2. **Five categories of change:**
   1. **breaking.** The change breaks the compilation of any code that uses the client:
      - a type, member or method was removed or renamed;
      - a type changed;
      - a parameter or field became required, or a new required one appeared.
   2. **switch-breaking.** A new union variant, enum value or status variant appeared. It breaks only an exhaustive `switch` over a sealed type.
   3. **additive.** New types, methods, or optional fields and parameters.
   4. **wire.** The Dart API is the same, but the behaviour on the wire changed: a JSON key, a path, a parameter style, a media type, or the set of statuses.
   5. **docs.** Only doc comments or `@Deprecated` changed.

3. **R14.2 through the new config key `exhaustive: true|false`.**
   - The key is set per client or in `defaults`. The default is `true`, which keeps today's sealed types.
   - With `false`, every enum, union, status type and event union base is `abstract interface`, so a `switch` needs a default case.
   - A schema override `exhaustive` still wins over the config key.
   - The diff knows the mode: for a non-exhaustive type, a new variant is **additive**.

4. **The command.**
   - `typed_openapi diff [clients]` compares the locked snapshot (decision 6) with the snapshot the current spec and config would give. It writes nothing.
   - The report formats are `text`, `json` and `markdown`. Markdown is for a PR comment.
   - `--fail-on breaking|switch-breaking|wire|any` sets the exit code for CI. By default the command only reports.
   - The command can also compare two snapshot files directly.
   - `generate` prints one line per client with the count of changes per category.

5. **The snapshot is the name lock.**
   - On regeneration, a name the lock assigned to an identity stays with that identity. The identity is the same spec location or the same operation.
   - New identities take free names. Adding something to a spec therefore never renames an existing type: the `2`, `3` collision suffixes and the inline names stay put.
   - A locked name that cannot be kept is a diagnostic. For example, an override now claims it, or its identity is gone.
   - `--fresh-names` names everything from scratch and ignores the lock.

6. **Where the lock lives.**
   - It is one file, `typed_openapi.lock`, next to `typed_openapi.yaml`, with a section per client.
   - It is committed even when the generated output is git-ignored, like `pubspec.lock`.
   - `generate` updates it, and `diff` compares against it.
   - `generate --locked` for CI checks against the lock and does not rewrite it. A difference is an error.

7. **A schema renamed in the spec is not guessed.**
   - For example, `Pet` becomes `Animal` with the same structure. That has a new spec location, so it is a new identity.
   - The diff reports it as removed plus added, a **breaking** change. The report includes a ready override `name: Pet` that keeps the old Dart name (R2.5: nothing is guessed silently).

## Out of scope

- Detecting renames by structure.
- Migrating user code, for example codemods.
- Changes of the client packages' own API (`typed_openapi_client`, `typed_openapi_dio`). Those are covered by their semver and CHANGELOGs.

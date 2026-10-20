# Generated output

`typed_openapi generate` owns the output directory of a client: it writes the whole tree, replaces it atomically, and refuses to delete anything it did not write. This guide explains what it checks, what the manifest and the lock file are, and what to commit.

```text
$ typed_openapi generate
Generated shop in lib/src/api/shop: 7 files, 7 written, 0 deleted.
$ ls -A lib/src/api/shop
.typed_openapi.json  api  api.dart  models  models.dart  shop.dart
```

The summary counts the generated files (without the manifest). `written` is the files whose content is new or changed, `deleted` the ones of an earlier run that the new tree no longer has.

## Ownership and the manifest

Every output directory holds `.typed_openapi.json`, written last in the same swap:

```json
{
  "generator": "typed_openapi 0.2.0",
  "format": 2,
  "inputs": "a92d74a3cb72...",
  "files": {
    "api.dart": "74271ac03f4789ce...",
    "models/category.dart": "fc1787242daccf6..."
  }
}
```

| Key | Meaning |
| --- | --- |
| `generator` | `typed_openapi` and its version. A manifest whose generator does not start with `typed_openapi ` is not ours. |
| `format` | `2`: every file is listed with the SHA-256 of its content. A manifest from before hashes existed (no hash for a file) is read, but cannot prove a file is untouched. |
| `inputs` | A hash of what the code was generated from, see [Determinism](#determinism). |
| `files` | Every generated file by relative path (sorted) with its SHA-256. |

Before replacing a directory, `generate` hashes every file in it and compares with the manifest. A file is a **stray** when:

- the manifest does not list it (or there is no manifest of this generator), or
- its hash differs from the manifest's (you edited it), or
- the manifest has no hash for it (written by an older format).

A file that already holds exactly what this run would write is never a stray. With any stray, the client is refused with TOA830 and nothing is changed:

```text
$ echo "// mine" > lib/src/api/shop/notes.dart
$ typed_openapi generate
error TOA830 output-not-owned: Client "shop" is not generated: its output directory lib/src/api/shop holds files that the generator did not write or that changed since it wrote them, and it would delete them: notes.dart (not written by typed_openapi).
  --> lib/src/api/shop
  fix: Move them out of the directory, or run generate --force to replace them.
...
Skipped shop: see the error above.
```

The message names up to 8 files, each with its reason (`not written by typed_openapi`, `changed since typed_openapi wrote it`, `no hash in the manifest of an older typed_openapi`). Without a manifest at all the text is `holds files but no .typed_openapi.json, so they were not written by it`.

### --force

`generate --force` replaces the strays instead of refusing. Each file it overwrites or deletes is reported as TOA833 (info) after the swap works, and the summary says how many:

```text
$ typed_openapi generate --force
info TOA833 output-file-replaced: Deleted notes.dart (not written by typed_openapi) in lib/src/api/shop because of --force.
  --> lib/src/api/shop/notes.dart
...
Generated shop in lib/src/api/shop: 7 files, 0 written, 1 deleted. --force replaced 1 foreign or modified file.
```

`--force` does not lift these refusals, because replacing the directory would destroy more than generated code. They are TOA830 whatever the flags:

| The output directory | Message ends with |
| --- | --- |
| holds a `pubspec.yaml` | `holds a pubspec.yaml` |
| is the `lib` directory of a package (its parent has a `pubspec.yaml`) | `is the lib directory of a package` |
| is a symbolic link, or is not a directory | `is a symbolic link, which the generator does not follow` / `is not a directory` |
| holds a symbolic link anywhere inside | `holds a symbolic link, <path>, which the generator does not follow` |
| holds an input of the run: the spec, the overrides, the baseline, a `$ref`'d file, or the config itself | `holds <path>, an input of the run` |

```text
error TOA830 output-not-owned: Client "p" is not generated: its output directory pk/lib is the lib directory of a package.
  --> pk/lib
  fix: Point output to a directory of its own, such as lib/src/<client>.
```

The inputs of **every client in the config** are protected, also those of a client you did not select, and a file is recognised by identity as well as by path, so a hard link or a different spelling of the path cannot get an input deleted.

> **Note:** Point `output` at a directory that holds only generated code, such as `lib/src/api/<client>`. Put hand-written code beside it, not inside it.

## Atomic replacement

A run never leaves a half-written output.

1. It builds the whole new tree, with the manifest, in a staging directory next to the output (`.<output>.typed_openapi-<8 letters or digits>`), so the swap is a rename on one file system.
2. The staging directory gets the mode of the old output (with `chmod`, only when the modes differ, after the files are written). A read-only output (`0555`) keeps its mode. When `chmod` is missing or fails, the run fails with TOA831 rather than change your permissions. Windows copies no mode. Ownership, ACLs and extended attributes are not copied.
3. The old directory is renamed to `<staging>-old`, the staging directory is renamed to the output, and the backup is removed.
4. When a step fails, the old directory is put back. If that fails too, TOA831 names the backup that holds the old tree, so you can move it back by hand. A failed first run leaves nothing.

A run that changes nothing does not swap at all: when no file is written or deleted and the manifest is the same, the directory is not touched. A run whose spec changed only in comments still updates the manifest (its `inputs` differ), while `written` stays `0`.

## Locks

Two runs on the same output would race, so a run takes a lock first: the file `.<output>.typed_openapi.lock` next to the output directory (`lib/src/api/.shop.typed_openapi.lock`), created exclusively before anything else is read, and removed at the end only if it still holds this run's text. It is JSON with the process id, the host name and a random id. On a file system that ignores case, the name is lower-cased.

A held lock is TOA831, and nothing is touched:

```text
error TOA831 output-not-written: Client "shop" is not generated: another typed_openapi run holds the lock lib/src/api/.shop.typed_openapi.lock of its output lib/src/api/shop (process 3285963 on myhost, which is running). Nothing was changed.
  --> lib/src/api/shop
  fix: Wait for it to finish. If you are sure no run is going, delete lib/src/api/.shop.typed_openapi.lock.
```

| The lock belongs to | What happens |
| --- | --- |
| a process on this host that is running | Held, whatever the flags. `--force` and `--break-lock` do not take it. |
| a process on this host that is gone (`kill -0` says so) | Taken over; reported as TOA832 (info). |
| another host, an unreadable or foreign file, a system without `kill`, Windows | Held (TOA831), unless you pass `--break-lock`. |

```text
$ typed_openapi generate --break-lock
info TOA832 output-recovered: Took over the lock lib/src/api/.shop.typed_openapi.lock of client "shop", which process 1 on elsewhere held: --break-lock takes it over.
```

`--break-lock` replaces no file. `--force` never touches a lock. A CI job that was killed on a shared workspace is the usual case for `--break-lock`; on an ephemeral runner you never need it.

## Interrupted runs

A run killed between the renames leaves directories named `.<output>.typed_openapi-<8 characters>` (a half-built tree) and `...-old` (the previous output) next to the output. The next `generate`, under the lock:

- skips any such directory that holds an input of the run (the name may be yours),
- checks the output (or the newest backup, when the output is missing) with the rules above,
- restores that backup as the output and removes the other leftovers. A backup is removed only once the output holds a manifest, since until then it is the only copy of the old tree.

```text
info TOA832 output-recovered: An earlier run for client "shop" was interrupted while it replaced lib/src/api/shop. The previous output was restored from lib/src/api/.shop.typed_openapi-AbCd1234-old. Removed 1 temporary directory it left.
```

## Overlapping outputs

Two clients may not write to the same directory or one inside the other, also through symbolic links or a different case. The config reports TOA904 and `generate` skips both clients:

```text
error TOA904 output-overlap: Clients "a" and "b" write to overlapping directories.
  --> ov.yaml:3:39
  at #/clients/b/output
  fix: Give each client its own output directory.
...
Skipped a: its output overlaps the output of another client (TOA904).
Skipped b: its output overlaps the output of another client (TOA904).
```

## Determinism

The same spec and the same config give byte-identical files, on any machine: no timestamps, no absolute paths, sorted output. The `inputs` hash in the manifest is the SHA-256 of:

- the content of every file the run read (spec, `$ref`'d files, overrides),
- the client's settings that change the code (`naming`, `types`, `tri_state`, `union`, `errors`, `sse`, `group_by`, the filters, `line_width`, `preset`, the disabled `rules`),
- the generator and its version.

Paths are not part of it, so a checkout in another directory gives the same hash. Diagnostics levels (`severity`) and the baseline do not change the code and are not in it. Upgrading `typed_openapi` can change the generated code: treat that as a change of the generator and review the diff.

## What to commit

| Path | Commit? |
| --- | --- |
| The output directory, with `.typed_openapi.json` | Yes. The diff of a spec change then shows exactly what the client change is, and CI can [check that it is up to date](ci.md#checking-that-generated-code-is-up-to-date). |
| `typed_openapi.yaml`, the overrides and the baseline files | Yes. |
| `.<output>.typed_openapi.lock` | No. It exists only while a run goes. |
| `.<output>.typed_openapi-*` | No. They exist only after a killed run. |

```text
# .gitignore
.*.typed_openapi.lock
.*.typed_openapi-*/
```

> **Note:** The generated code imports only `package:typed_openapi_client`. Add it and a transport (`typed_openapi_dio` with `dio`) to the app's `dependencies`; see the [runtime package](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).

## See also

- [Command line](cli.md): the options of `generate`.
- [CI](ci.md): checking that the committed output is current.
- [Diagnostics](diagnostics.md): TOA830-TOA833 and TOA904.
- [Configuration](configuration.md): `output` and the other client keys.

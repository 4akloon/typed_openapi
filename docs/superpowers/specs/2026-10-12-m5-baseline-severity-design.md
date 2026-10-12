# M5: baseline, levels and report formats — design

Date: 2026-10-12. Requirements: R2.2 (levels in the config, formats), R2.3 (baseline / ratchet) ([requirements.md](../../requirements.md)). Research: [research/README](../../research/README.md), rows R2.2 and R2.3 (fingerprint as in oasdiff, stale entries as in ESLint bulk suppressions, formats of Redocly / Spectral). Carried over to M5: the roadmap, the sections "Carried over from M1/M2/M3/M4".

## Decisions

1. **Baseline per client.** The path is `clients.<name>.baseline` in the config (the field already exists). A YAML file, created by `typed_openapi baseline create [clients]` and cleaned by `typed_openapi baseline prune [clients]`. An entry holds the fingerprint and fields for a human: the code, the anchor, the message text at the time of writing (the text is not part of the fingerprint).
2. **Fingerprint without text and without indexes, where possible.** `sha256(code | anchor | arguments)[:12]`. The anchor is the logical address from M4 (reverse addressing: operation, schema, property, parameter), if the place is addressable; otherwise — the file (relative to the baseline file) and a JSON pointer. Identical fingerprints are stored with a counter.
3. **Recorded violations are hidden.** The report shows only new and stale entries, with a counter at the bottom "N recorded in baseline". The `--show-baselined` flag shows everything with a mark. Only unrecorded errors affect the exit code.
4. **A stale entry is a warning** with a hint to run `baseline prune` (R2.3: "suggests removing it"). The `--strict-baseline` flag makes it an error.
5. **Levels in the config.** `severity: {<code or slug>: error|warning|info|off}` in `defaults` and in the client; the client overrides `defaults` name by name. `off` is allowed, except for codes without which the document cannot be read (read and load errors, the config codes, the overrides file and baseline codes): an attempt to lower or turn off these is a config diagnostic. The level applies to the report and to the exit code; it does not affect the fingerprint.
6. **Report formats:** `text`, `json` (as now), `sarif` (2.1.0) and `github-actions` (annotations `::error file=…,line=…,col=…::`).
7. **Paths — relative to the working directory** for all formats and all files, including files reached through `$ref`; a file outside it — an absolute path. This replaces the current mix (the config as entered, specs relative to the config, files through `$ref` as absolute URIs).
8. **Carried-over findings:**
   - a problem that an override introduced gets a second location — the override itself ("introduced by an override in …"; in SARIF — `relatedLocations`);
   - deduplication of diagnostics no longer drops the preset hint of a second client on a shared file.

## Out of scope

- The `junit` format — later, if needed.
- Baseline for `generate` — together with M9 (the same mechanism).
- Overriding levels for a single place (not a code) — through baseline or override.

# 08. Test corpus of specifications

Date: **2026-10-11**. Goal: select public OpenAPI specifications on which to run `typed_openapi check` now and generation later. Related to [06](06-spec-versions-and-defects.md) (versions and defects) and [../requirements.md](../requirements.md).

The specification files were **not saved** either in the repository or to disk. They were only read as a stream (`curl | script`) to count operations, schemas and features. All figures below were measured on 2026-10-11 at the stated commits. If a figure is taken from a description rather than measured, this is stated.

## Criteria

- ~12 specifications, different domains, without repeats where they can be avoided.
- Versions: 3.0.x, 3.1.x, 3.2. Formats: JSON and YAML. There are multi-file ones with cross-file `$ref`s.
- At least 4 generated from code (FastAPI, NestJS, springdoc, Swashbuckle), the rest written by hand.
- Features for load: `oneOf`/`anyOf` with `discriminator`, `allOf`, `nullable` versus `type: [x, "null"]`, non-string enums, `additionalProperties`, multipart and binary bodies, SSE, PATCH, envelopes and pagination, many tags, security schemes, very large and very small size.
- Known defects are a plus: the generator is for exactly such specifications.
- The source is the API owner (its repository or official site). Links are pinned to a commit SHA or version where possible.

The license in the table is the license of the **repository or specification**, not a legal conclusion. The column "Copy in repo" answers the question of whether the file can be put into a public repository as a fixture.

## Summary table

| # | Name | Domain | OAS | Format | Size | Origin | Key features | License / copy in repo |
|---|---|---|---|---|---|---|---|---|
| 1 | Stripe API | payments | 3.0.0 | JSON | 8.3 MB, 612 ops, 1538 schemas | owner, internal generator | `nullable` 2795, `anyOf` 2124, form-urlencoded + `deepObject`, custom `format`s, no tags | MIT, yes |
| 2 | OpenAI API | AI/LLM | 3.1.0 | YAML | 4.1 MB, 359 ops, 2048 schemas | owner | SSE, multipart, 176 `oneOf`+`discriminator`, `type: [x,"null"]`, `webhooks` | MIT, yes |
| 3 | Discord HTTP API | messenger | 3.1.0 | JSON | 1.2 MB, 246 ops, 538 schemas | owner | `oneOf`+`const` without `discriminator`, integer enums, PATCH, multipart | MIT, yes |
| 4 | DigitalOcean API | infrastructure | 3.0.0 | YAML | 3340 files, 3.3 MB, 791 ops | by hand | **multi-file**, `$ref` at the operation level, paths with `:` | Apache-2.0, yes |
| 5 | Medusa Store API | e-commerce | 3.0.0 | YAML | 692 files, 3.1 MB, 78 ops | from code (annotations) | **multi-file**, `{id}` in file names, `$ref` in `x-` pointing to `.js`/`.sh` | MIT (except Enterprise), yes |
| 6 | Grace Server API | dev tools (VCS) | **3.2.0** | YAML | 38 files, 133 ops, 351 schemas | by hand | **multi-file** `$ref` with `~1` escaping, a bundle alongside | MIT, yes |
| 7 | Apache Airflow REST v2 | data/orchestration | 3.1.0 | YAML | 544 KB, 134 ops, 198 schemas | **FastAPI** | `anyOf`+`null` 803, PATCH 21 with `update_mask`, OAuth2 | Apache-2.0, yes |
| 8 | Artemis | education | 3.1.0 | YAML (flow) | 112 KB, 67 ops, 127 schemas | **springdoc** | flow-style YAML, 8 `oneOf`+`discriminator`, `required` defects | MIT, yes |
| 9 | Tambo API | AI platform | 3.0.0 | JSON | 131 KB, 45 ops, 65 schemas | **NestJS** | SSE, multipart, `discriminator`, apiKey + bearer | MIT, yes |
| 10 | Jellyfin API | media | 3.0.4 | JSON | 1.9 MB, 364 ops, 357 schemas | **Swashbuckle** (ASP.NET) | `nullable`+`allOf` wrapper 1038, 46 tags, duplicate content types | GPL-2.0 (repository), **no** |
| 11 | Eclipse Ditto HTTP API | IoT | 3.0.0 | YAML | 519 KB bundle + 234 source files, 131 ops | by hand | **all 131 ops without `operationId`**, `merge-patch+json`, `openIdConnect` | EPL-2.0, with conditions |
| 12 | Google Maps Platform | maps/geo | 3.0.3 | JSON | 2.7 MB, 17 ops, 75 schemas | owner (from documentation) | huge `examples`, apiKey in query, `pipeDelimited` | Apache-2.0, yes (repo archived) |
| 13 | EFGS Federation Gateway | health/government | 3.0.1 | JSON | 16 KB, 7 ops | **springdoc** | minimal; protobuf, `OPTIONS`, `Accept`/`Content-Type` as parameters | Apache-2.0, yes |

Generated from code: No. 5, 7, 8, 9, 10, 13 (six). Multi-file: No. 4, 5, 6 (and the sources of No. 11).

Tiers for CI:
- **Small (milliseconds):** №13, №9, №8. Run on every commit.
- **Medium:** №7, №11, №6, №5, №4, №2/3 (bundle). The regular set.
- **Load:** №1 (8.3 MB), №2 (4.1 MB), №12 (2.7 MB), №10 (1.9 MB), №3 (1.2 MB). For checking the limits (see TOA007/TOA008 in CLAUDE.md) and timing.

## Specifications

### 1. Stripe API (payments)

- **Owner:** Stripe. Repository [stripe/openapi](https://github.com/stripe/openapi).
- **URL:** `https://raw.githubusercontent.com/stripe/openapi/7a1f5c21117298a85995746eeeedb6207969dc4e/openapi/spec3.json`. API version: `2026-09-30.endive`.
- **OAS / format:** 3.0.0, JSON. YAML is also available (`spec3.yaml`, 6.6 MB).
- **Size:** 8,317,513 bytes; 431 paths, 612 operations (273 GET, 307 POST, 32 DELETE), 1538 schemas.
- **One or several files:** one. A smaller `fixtures3.json` (193 KB) sits alongside it, convenient for quick runs.
- **Origin:** the owner, with a tool; `info.x-stripeSpecFilename` points to an internal export. Not a code-first framework.
- **Features:** `anyOf` 2124, `oneOf` 322, `nullable: true` 2795, enum 4399 (24 with boolean `true`), `additionalProperties` 958. Request bodies in `application/x-www-form-urlencoded` (611) with `style: deepObject` (366 parameters). Pagination: `has_more`, `starting_after`, `ending_before`, `limit`. Security: `basic` and `bearer`. One multipart (file upload).
- **Defects and peculiarities:** custom `format`s: `unix-time` (528), `currency` (182), `decimal` (116) — this is the R6.8 check. There are no `tags` and no `PATCH`. 77 schema names with a dot (`billing.alert`). All 4062 `$ref`s are internal and resolve.
- **License:** [MIT](https://github.com/stripe/openapi/blob/master/LICENSE). A copy in the repo is permitted, but at 8.3 MB it is better to take `fixtures3.json` or download by SHA in CI.

### 2. OpenAI API (AI/LLM)

- **Owner:** OpenAI. Repository [openai/openai-openapi](https://github.com/openai/openai-openapi).
- **URL:** `https://raw.githubusercontent.com/openai/openai-openapi/e95c0fe615f45a19e8878af923a729948445a6bd/openapi.yaml`. `info.version`: 2.3.0.
- **OAS / format:** 3.1.0, YAML (there is also `openapi.json`, 4.8 MB).
- **Size:** 4,058,614 bytes; 230 paths, 359 operations (159 GET, 149 POST, 51 DELETE), 2048 schemas, 40 tags, 30 `webhooks`.
- **Files:** one.
- **Origin:** maintained by the owner; the framework is not stated. Extensions `x-oaiMeta`, `x-openai-structured-output-limits`.
- **Traits:**
  - SSE: `text/event-stream` in 12 places.
  - Multipart (18) and binary bodies (`format: binary` 35, `application/octet-stream`, `audio/wav`, `application/sdp`).
  - `oneOf` with `discriminator` 176 (124 without `mapping`), `type: [x, "null"]` 304, `anyOf` with `null` 1115, `allOf` 165.
  - Enums with `null` (7) and integer enums (5).
  - Pagination: `after`/`before`/`limit` + `has_more`/`first_id`/`last_id`.
  - Security: two `bearer` schemes (regular and admin key).
- **Defects:** 117 `operationId` values are not identifiers (`create-live`, `accept-live-session`); 10 schemas with a `-2` suffix (`Error-2`, `ConversationParam-2` — a result of merging); 18 objects where `required` lists fields that are missing from `properties`; there is no `PATCH` (changes go through `POST`).
- **License:** [MIT](https://github.com/openai/openai-openapi/blob/main/LICENSE), `info.license` is MIT too. Copying is allowed; at 4.1 MB it is better to download it in CI.

### 3. Discord HTTP API (messenger/social network)

- **Owner:** Discord. Repository [discord/discord-api-spec](https://github.com/discord/discord-api-spec).
- **URL:** `https://raw.githubusercontent.com/discord/discord-api-spec/1ff2dee3677fabef7b49f942bbae93d06c0c9f2c/specs/openapi.json`. Title: "Discord HTTP API (Preview)", version `10`.
- **OAS / format:** 3.1.0, JSON.
- **Size:** 1,192,427 bytes; 153 paths, 246 operations (103 GET, 45 POST, 40 DELETE, 33 PATCH, 25 PUT), 538 schemas.
- **Files:** one.
- **Origin:** the owner; not declared. The style (`const`, `snake_case` identifiers, consistency) looks generated, but this is an assumption.
- **Traits:** `oneOf` 497 together with `const` 659 and **without any `discriminator`** — the type is told apart by the `const` value. `type: [x, "null"]` 909. Integer enums 165. Custom `format`s: `snowflake`, `nonce`. `multipart/form-data` 15, `x-www-form-urlencoded` 12; PATCH 33 (3 of them not JSON). 12 operations with several 2xx responses. Security: `apiKey` in a header (BotToken) + OAuth2. No tags.
- **Defects:** none — the specification is clean. Useful as a "reference for complex but correct 3.1".
- **License:** [MIT](https://github.com/discord/discord-api-spec/blob/main/LICENSE). Copying is allowed (1.2 MB).

### 4. DigitalOcean API (cloud/infrastructure)

- **Owner:** DigitalOcean. Repository [digitalocean/openapi](https://github.com/digitalocean/openapi).
- **Entry URL:** `https://raw.githubusercontent.com/digitalocean/openapi/6fda13183a6046c669b591e057b9d7b3a6344829/specification/DigitalOcean-public.v2.yaml`. For a cross-file test the whole `specification/` directory at the same SHA is needed ([tree](https://github.com/digitalocean/openapi/tree/6fda13183a6046c669b591e057b9d7b3a6344829/specification)).
- **OAS / format:** 3.0.0, YAML.
- **Size:** entry file 129,461 bytes; 3340 YAML files in total, 3.3 MB. 538 paths, 791 operations (412 GET, 178 POST, 110 DELETE, 72 PUT, 19 PATCH).
- **Files:** many. The entry contains `info`, `security`, `components.securitySchemes`, `x-tagGroups`; it has no schemas or operations.
- **Origin:** hand-written (YAML sources in `resources/<group>/`, shared parts in `shared/`).
- **Traits and defects (all useful for testing `$ref`):**
  - **`$ref` sits at the operation level** (`get: { $ref: "resources/.../x.yml" }`), not at the Path Item level. The specification does not allow this; it is a direct check for TOA10x.
  - References to whole files without a fragment (`models/droplet.yml`), to fragments (`examples.yml#/droplet_create_request`), and relative upward (`../../shared/responses/unauthorized.yml`).
  - A reference to `description.yml#/introduction` — to an arbitrary YAML node.
  - Paths with a colon: `/v2/action-gateway/actors/{actor_id}/limits:clear`.
  - `operationId` only in the operation files (`droplets_create`); the entry file has none.
  - `oneOf` in a request body (one or several droplets). `x-tagGroups`.
- **License:** [Apache-2.0](https://github.com/digitalocean/openapi/blob/main/LICENSE). Copying is allowed, but with 3340 files it is better to fetch them by SHA.

### 5. Medusa Store API (e-commerce)

- **Owner:** Medusa. Repository [medusajs/medusa](https://github.com/medusajs/medusa).
- **Entry URL:** `https://raw.githubusercontent.com/medusajs/medusa/146c46b0ad1146b40595c8ef586c4d5890982603/www/apps/api-reference/specs/store/openapi.yaml`. Tree: [specs/store](https://github.com/medusajs/medusa/tree/146c46b0ad1146b40595c8ef586c4d5890982603/www/apps/api-reference/specs/store). There is also `specs/admin` (273 paths, 897 files, 7.2 MB).
- **OAS / format:** 3.0.0, YAML. `info.version`: 2.21.2.
- **Size:** entry 15,858 bytes; 692 files (excluding code samples), 3,136,987 bytes: 68 path files (78 operations: 39 POST, 33 GET, 6 DELETE) and 607 schema files.
- **Files:** many (paths, schemas, responses, parameters as separate files).
- **Origin:** from code. The operation extensions `x-workflow: createCartWorkflow`, `x-events`, `x-allowed` lead to the server code. The generation tool itself has not been verified.
- **Traits:** `allOf` in bodies; `securitySchemes`: `jwt_token` (bearer), `cookie_auth` (apiKey in a cookie), `reset_password`. `operationId` like `PostActor_typeAuth_providerVerificationConfirm` — pseudo-PascalCase built from path parameter names.
- **Defects:** file names contain curly braces (`store_carts_{id}.yaml`) — they are not escaped in `$ref` (not RFC 3986). `x-associatedSchema` in tags contains a `$ref` inside an extension. `x-codeSamples[].source` is a `$ref` to `.js` and `.sh`, not to YAML/JSON. The entry has 88 external `$ref`s and no internal ones.
- **License:** the repository is under [MIT, except Enterprise](https://github.com/medusajs/medusa/blob/develop/LICENSE); `info.license` in the specification is MIT. Copying is allowed for `specs/store` (it has no Enterprise material).

### 6. Grace Server API (dev tools: version control)

- **Owner:** Scott Arbeit. Repository [ScottArbeit/Grace](https://github.com/ScottArbeit/Grace), server in F#.
- **Entry URL (source):** `https://raw.githubusercontent.com/ScottArbeit/Grace/f746b688e0d20fdfdc46eedb42bd8d301be61a34/src/OpenAPI/Main.OpenAPI.yaml`. Bundle: `.../src/OpenAPI/Grace.OpenAPI.yaml` at the same SHA. Directory: [src/OpenAPI](https://github.com/ScottArbeit/Grace/tree/f746b688e0d20fdfdc46eedb42bd8d301be61a34/src/OpenAPI).
- **OAS / format:** **3.2.0**, YAML. API version `2023-10-01`.
- **Size:** bundle 338,021 bytes; 133 operations (129 POST, 4 GET), 351 schemas, 11 tags. The directory holds 38 files, 1.1 MB (together with the bundle and the projection).
- **Files:** both a multi-file source and a ready bundle. This gives a test "the source and the bundle produce the same model".
- **Origin:** hand-written; the description of the `GetOpenApi` operation states directly that the specification is assembled from the `src/OpenAPI` files. The directory also has `Grace.OpenAPI.3.1.2.yaml` — an automatic version shift 3.2.0 → 3.1.2 (`@redocly/cli`), with `loss-report.json`.
- **Traits:** `$ref`s with fragments where path keys are escaped as `~1`: `./Approval.Paths.OpenAPI.yaml#/~1approval~1policy~1create`. Component references to the root of a file: `Approval.Components.OpenAPI.yaml#/ApprovalPolicy`. `allOf` 170, `nullable: true` 73 (!), `const` 6, integer enums 5, `application/octet-stream`. Security: `apiKey` + `bearer`.
- **Defects:** the document is marked 3.2.0 but uses `nullable: true`, which is a 3.0 keyword and does not exist in 3.1+. One object has a `required` entry without a matching field. Of the 3.2 constructs, only the version string is used.
- **License:** [MIT](https://github.com/ScottArbeit/Grace/blob/main/LICENSE.md). Copying is allowed.

### 7. Apache Airflow REST API v2 (data/orchestration, FastAPI)

- **Owner:** Apache Airflow. Repository [apache/airflow](https://github.com/apache/airflow).
- **URL:** `https://raw.githubusercontent.com/apache/airflow/4ca1f6693bb380ae1f148a6187001adbcadbfa22/airflow-core/src/airflow/api_fastapi/core_api/openapi/v2-rest-api-generated.yaml`.
- **OAS / format:** 3.1.0, YAML.
- **Size:** 543,538 bytes; 94 paths, 134 operations (73 GET, 21 PATCH, 20 POST, 14 DELETE, 6 PUT), 198 schemas, 29 tags.
- **Files:** one. Next to it is `_private_ui.yaml` (166 KB, internal).
- **Origin: FastAPI.** Evidence: the file name `...-generated.yaml`, 131 mentions of `ValidationError`/`HTTPValidationError`, `operationId` in `snake_case` taken from function names (`get_assets`), `title: Update Mask` (Pydantic auto-titles).
- **Traits:** this is a sample of FastAPI + Pydantic v2 output: `anyOf: [X, {type: "null"}]` 803 times (instead of `nullable`), `const` 22, `prefixItems` 2, `oneOf` 10, `additionalProperties` 90. **PATCH 21** with `update_mask` in the query (`anyOf` array/null) and an `application/json` body — a direct check of `Patch<T>`. `*CollectionResponse` envelopes with `total_entries` (78 mentions). Pagination `limit`/`offset`. `application/x-ndjson` (2) — streaming responses. Security: `OAuth2PasswordBearer` + `HTTPBearer`.
- **Defects:** `discriminator` is not used although `oneOf` is present. Otherwise the specification is clean.
- **License:** [Apache-2.0](https://github.com/apache/airflow/blob/main/LICENSE). Copying is allowed (544 KB).

### 8. Artemis (education, springdoc)

- **Owner:** TUM (ls1intum). Repository [ls1intum/Artemis](https://github.com/ls1intum/Artemis).
- **URL:** `https://raw.githubusercontent.com/ls1intum/Artemis/e92f350e7892b514b976b05c4f83cfcec12ec54c/config/openapi/openapi.yaml`. Version `10.3`.
- **OAS / format:** 3.1.0, YAML **in flow style** (`schema: {type: integer, format: int64}`, `servers: - {url: ..., description: ...}`).
- **Size:** 112,129 bytes; 58 paths, 67 operations (30 POST, 21 GET, 9 PUT, 5 DELETE, 2 PATCH), 127 schemas, 16 tags.
- **Files:** one.
- **Origin: springdoc.** Evidence: in `build.gradle` the plugin `org.springdoc.openapi-gradle-plugin`; `servers[0].description: "Generated server url"` (springdoc's signature mark).
- **Traits:** `oneOf` with `discriminator` 8 (1 without `mapping`), `type: [x, "null"]` 6, enums 79, `additionalProperties` 4, `text/csv`, `text/calendar`, `format: binary`.
- **Defects:** 2 objects with `required` without a matching field in `properties`; among the `operationId`s there are overly generic ones (`update`) — a check for name collisions in the client.
- **License:** [MIT](https://github.com/ls1intum/Artemis/blob/develop/LICENSE). Copying is allowed.

### 9. Tambo API (AI platform, NestJS)

- **Owner:** tambo-ai. Repository [tambo-ai/tambo](https://github.com/tambo-ai/tambo).
- **URL:** `https://raw.githubusercontent.com/tambo-ai/tambo/6e2c1bff3b68a00c094b6d876788cc8f33f7bb02/stainless/openapi.json`.
- **OAS / format:** 3.0.0, JSON.
- **Size:** 130,999 bytes; 36 paths, 45 operations (19 POST, 16 GET, 7 DELETE, 2 PUT, 1 PATCH), 65 schemas, 9 tags.
- **Files:** one.
- **Origin: NestJS (`@nestjs/swagger`).** Evidence: `@nestjs/swagger` in `apps/api/package.json`; `operationId`s of the form `V1Controller_createRun`, `AppController_getHello`; `info.contact: {}`; empty `servers`.
- **Traits:** SSE in `POST /v1/threads/runs` and `POST /v1/threads/{threadId}/runs`; multipart in `POST /audio/transcribe`; `discriminator` in 5 schemas (`Message`, `InputMessage`, `ToolResultContent`), `oneOf` 7, `allOf` 16; `nullable: true` 3; enums 33; `additionalProperties` 38; pagination `limit`/`cursor` + `hasMore`. Security: `apiKey` (header) + `bearer`.
- **Defects:** `operationId`s with `Controller_` are typical NestJS noise; a check of naming rules (R5.1). `servers` is empty.
- **Domain:** overlaps with No. 2 (AI). If strict domain variety is needed, replace it with Immich (see runner-up).
- **License:** [MIT](https://github.com/tambo-ai/tambo/blob/main/LICENSE). Copying is allowed.

### 10. Jellyfin API (media, ASP.NET Swashbuckle)

- **Owner:** Jellyfin. Published at `repo.jellyfin.org`; server: [jellyfin/jellyfin](https://github.com/jellyfin/jellyfin).
- **URL (versioned):** `https://repo.jellyfin.org/files/openapi/stable/jellyfin-openapi-12.2.json`. Verified: 1,896,214 bytes, SHA-256 starts with `bd31bb194443d1c5`, `Last-Modified: 2026-10-05`. Moving alias: `https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json`.
- **OAS / format:** **3.0.4**, JSON (a rare patch-level string). `info.x-jellyfin-version: 12.2.0`.
- **Size:** 1,896,214 bytes; 294 paths, 364 operations (186 GET, 130 POST, 30 DELETE, 18 HEAD), 357 schemas, 46 tags.
- **Files:** one.
- **Origin: Swashbuckle.** Evidence: `Swashbuckle` in `Jellyfin.Api/Jellyfin.Api.csproj` and `Directory.Packages.props`; `operationId` taken from action names (`GetLogEntries`, `CreateKey`).
- **Traits:** `nullable: true` 1038 + `allOf` 530 — the typical Swashbuckle wrapper `allOf: [{$ref}]` + `nullable`; `discriminator` 3; `additionalProperties` 316; 68 `deprecated`. Three or four duplicate content types for each response: `application/json`, `application/json; profile="CamelCase"`, `application/json; profile="PascalCase"`, `text/json`, `application/*+json`. `format: binary` 64, `image/*`, `video/*` (streaming). `HEAD` operations. `style: deepObject` 8.
- **Defects:** `format: text` (364) — a non-standard format; many duplicated response schemas; one `securityScheme` (`apiKey` in a header) with a custom name.
- **License:** the server repository is [GPL-2.0](https://github.com/jellyfin/jellyfin/blob/master/LICENSE); the license of the specification file itself is not stated. **Do not put a copy** in the public repo; take it by URL in CI.

### 11. Eclipse Ditto HTTP API (IoT)

- **Owner:** Eclipse Ditto. Repository [eclipse-ditto/ditto](https://github.com/eclipse-ditto/ditto).
- **Bundle URL:** `https://raw.githubusercontent.com/eclipse-ditto/ditto/952e3c270e7845666ee40e1ae945872fba520430/documentation/src/main/resources/openapi/ditto-api-2.yml`. Sources: [openapi/sources](https://github.com/eclipse-ditto/ditto/tree/952e3c270e7845666ee40e1ae945872fba520430/documentation/src/main/resources/openapi/sources) (`api-2-index.yml` + `paths/`, `schemas/`, `parameters/`, `responses/`, `requests/`, `security/`).
- **OAS / format:** 3.0.0, YAML. (The README says "version 2" — this is the API version, not the OAS version.)
- **Size:** bundle 519,051 bytes; 61 paths, 131 operations (45 GET, 32 PUT, 21 DELETE, 20 POST, 12 PATCH, 1 HEAD), 82 schemas, 47 parameters, 12 responses, 10 requestBodies, 9 tags. Sources: 234 files.
- **Files:** both a multi-file source (assembled with `swagger-cli bundle`) and a bundle.
- **Origin:** hand-written.
- **Traits:** PATCH with **`application/merge-patch+json`** (9 of 12) — the closest to a real JSON Merge Patch (R7). Other types: `application/td+json`, `application/vnd.eclipse.ditto+json`. 21 operations with several 2xx responses. Security: five schemes, including `openIdConnect` and two `basic`. `links` 1. 1656 `$ref`s.
- **Defects:** **`operationId` is missing in all 131 operations** — a direct test of name generation from `method + path`. `iri-reference` as a `format`.
- **License:** [EPL-2.0](https://github.com/eclipse-ditto/ditto/blob/master/LICENSE) (file-level copyleft). A copy is permitted if the header and notice are kept; for convenience one may skip keeping them and take it by SHA instead.

### 12. Google Maps Platform (maps/geo)

- **Owner:** Google. Repository [googlemaps/openapi-specification](https://github.com/googlemaps/openapi-specification) — **archived/deprecated** (the README points to Postman).
- **URL (release):** `https://github.com/googlemaps/openapi-specification/releases/download/v1.22.3/google-maps-platform-openapi3.json`. Release 2023-01-25, tag `v1.22.3` → commit `21659934ef78dd9e24982fadb843f83b2c15609f`. A `.yml` variant exists (2.3 MB).
- **OAS / format:** 3.0.3, JSON.
- **Size:** 2,727,068 bytes, but only 17 operations (16 GET, 1 POST), 75 schemas, 74 parameters, 9 tags. The size comes from the embedded examples.
- **Files:** one.
- **Origin:** the owner; assembled from Google's documentation (not from code).
- **Traits:** `securitySchemes`: `apiKey` in the **query** (`key`); `style: pipeDelimited` (9); enums 31, of which integer (10); pagination `next_page_token`; `format: binary` for images (`image/*`). A stress test: "a small API — a large document".
- **Defects:** the file is from 2023 and is no longer updated. Useful as a regression test for large `examples`.
- **License:** [Apache-2.0](https://github.com/googlemaps/openapi-specification/blob/main/LICENSE) (GitHub shows NOASSERTION because of the file format). Copying is permitted, but at 2.7 MB it is better to use the URL in CI.

### 13. EFGS Federation Gateway (health/government, springdoc)

- **Owner:** EU Federation Gateway Service (coronavirus apps). Repository [efgs-federation-gateway](https://github.com/eu-federation-gateway-service/efgs-federation-gateway).
- **URL:** `https://raw.githubusercontent.com/eu-federation-gateway-service/efgs-federation-gateway/cba7be6756b089a7775e2354b367b9830d979105/docs/openapi.json`. Latest commit 2025-01-24.
- **OAS / format:** 3.0.1, JSON.
- **Size:** 15,766 bytes; 6 paths, 7 operations (3 GET, PUT, DELETE, OPTIONS, POST), 1 schema, 5 tags.
- **Files:** one.
- **Origin: springdoc.** Evidence: `servers[0].description: "Generated server url"` (`http://localhost:8090`), OAS 3.0.1, `title: efgs-federation-gateway`, `version: 1.0.0-SNAPSHOT`.
- **Traits and defects:**
  - The `Accept` and `Content-Type` headers are described as **parameters** (the specification says they are ignored).
  - The request body is `application/protobuf; version=1.0` and `application/json; version=1.0`; the response is `application/json+v1.0`.
  - An `OPTIONS` operation; 207 and 410 among the responses; responses without `content`.
- **License:** [Apache-2.0](https://github.com/eu-federation-gateway-service/efgs-federation-gateway/blob/master/LICENSE). Copying is allowed.

## Runner-up

They did not make it into the main set for the reasons given. Suitable as a replacement or addition.

1. **GitHub REST API** — [github/rest-api-description](https://github.com/github/rest-api-description), MIT. `descriptions/api.github.com/api.github.com.2022-11-28.json` at SHA `58b1e0c00b39b9e46c24dc4a0ba6a2669c90e9c1`: 3.0.3, 12.9 MB, 1232 operations, 994 schemas, 44 tags. There is a 3.0/3.1 pair (`descriptions-next/`). `operationId`s like `meta/root` (slash, hyphen) and 893 schema names in kebab-case — the strongest test of name normalization. Not taken, because three stress specifications already exist (No. 1, 2, 10), and the dev tools domain is covered by No. 6.
2. **Immich** — [immich-app/immich](https://github.com/immich-app/immich), `open-api/immich-openapi-specs.json`, SHA `2685234ed390746413203a2cf0b18bc36dba53d1`: 3.0.0, 955 KB, 279 operations, 438 schemas, NestJS. Multipart (3), `application/octet-stream` (11), three security schemes (bearer, cookie, `api_key`), `nullable` 252. **AGPL-3.0**, do not put a copy. The "photo/media" domain overlaps with No. 10.
3. **weather.gov API (NWS)** — `https://api.weather.gov/openapi.json`, a live URL (ETag `d35176a8...`, version 3.12.2), **OAS 3.1.2**, JSON, 123 KB, 69 GET. Types `application/ld+json`, `application/geo+json`, XML. Public domain in the US; the URL is not pinned (an older copy is in [weather-gov/api](https://github.com/weather-gov/api) — 3.0.3, v1.9.0).
4. **traefik/whoami** — [traefik/whoami](https://github.com/traefik/whoami), SHA `1ce75d01b6978863647da42557a707a479da3a51`, `openapi.yaml`: **3.2.0**, 8 KB, 6 operations, Apache-2.0. The smallest real 3.2 specification. Not taken, because No. 13 already covers "small", and 3.2 is covered by No. 6.
5. **Train Travel API** — [bump-sh-examples/train-travel-api](https://github.com/bump-sh-examples/train-travel-api), `openapi.yaml`: 3.2.0, 57 KB, `QUERY` method, `webhooks`, OAuth2, `allOf` 24. License **CC-BY-NC-SA-4.0** (non-commercial) — we would not put it in a public repo under MIT.

Also for 3.2 constructs: the official OAI examples [learn.openapis.org/examples/v3.2](https://github.com/OAI/learn.openapis.org/tree/82b82f372aa185a07ea11bc158619895ab21f741/examples/v3.2) (`3.2-query-example.yaml`, `3.2-tags-example.yaml`, 3 KB and 2 KB, [CC-BY-4.0](https://github.com/OAI/learn.openapis.org)). They show the `query` method in its pure form. I recommend adding them as small fixtures.

We also looked at and rejected: ClinicalTrials.gov (`https://clinicaltrials.gov/api/oas/v2`, 3.0.3, YAML, 81 KB, 9 operations, a live URL without a version, looks like Java generation, but not proven); Supabase Management API (`apps/docs/spec/transforms/api_v1_openapi_deparsed.json`, 3.0.0, 644 KB, `nullable` 519, but this is a file converted for documentation and NestJS is not proven); MITRE Vulcan (3.2.0, multi-file, 223 files, but the security/Rails domain and the license of the files are not determined).

## Coverage matrix

Legend: ✅ present · ⚠️ present, but weak or partial · ❌ absent. Numbers as in the summary table. Measured with a script over the specifications; for the multi-file No. 4 and 5 — by a full pass (No. 5 over the path files) or by the description where it is stated directly.

| Trait | 1 Stripe | 2 OpenAI | 3 Discord | 4 DO | 5 Medusa | 6 Grace | 7 Airflow | 8 Artemis | 9 Tambo | 10 Jellyfin | 11 Ditto | 12 Maps | 13 EFGS |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| OAS 3.0.x | ✅ | | | ✅ | ✅ | | | | ✅ | ✅ (3.0.4) | ✅ | ✅ | ✅ (3.0.1) |
| OAS 3.1.x | | ✅ | ✅ | | | | ✅ | ✅ | | | | | |
| OAS 3.2 | | | | | | ✅ (version string only) | | | | | | | |
| JSON | ✅ | | ✅ | | | | | | ✅ | ✅ | | ✅ | ✅ |
| YAML | | ✅ | | ✅ | ✅ | ✅ | ✅ | ✅ (flow) | | | ✅ | | |
| Multi-file `$ref` | | | | ✅ | ✅ | ✅ | | | | | ✅ (sources) | | |
| Generated from code | ⚠️ | ❌ | ⚠️ | ❌ | ✅ | ❌ | ✅ FastAPI | ✅ springdoc | ✅ NestJS | ✅ Swashbuckle | ❌ | ❌ | ✅ springdoc |
| `oneOf` + `discriminator` | ❌ | ✅ | ❌ (`const`) | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ⚠️ (3) | ❌ | ❌ | ❌ |
| `oneOf`/`anyOf` without `discriminator` | ✅ | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ❌ | ❌ |
| `allOf` (inheritance) | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| `nullable: true` | ✅ | ⚠️ | ❌ | ❌ | ? | ✅ | ❌ | ❌ | ⚠️ | ✅ | ❌ | ❌ | ❌ |
| `type: [x, "null"]` | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `anyOf` with `{type: "null"}` | ❌ | ✅ | ❌ | ❌ | ❌ | ⚠️ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Non-string enums | ✅ (bool) | ✅ | ✅ (int) | ? | ? | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (int) | ❌ |
| `additionalProperties` | ✅ | ✅ | ✅ | ? | ? | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| multipart / binary body | ⚠️ | ✅ | ✅ | ❌ | ❌ | ⚠️ | ❌ | ⚠️ | ✅ | ⚠️ (responses) | ⚠️ | ⚠️ | ✅ (protobuf) |
| SSE / `text/event-stream` | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ⚠️ (ndjson) | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| PATCH | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ⚠️ | ❌ | ✅ (merge-patch) | ❌ | ❌ |
| Envelope / pagination | ✅ | ✅ | ⚠️ | ✅ | ✅ | ❌ | ✅ | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ | ❌ |
| Many tags (≥15) | ❌ | ✅ | ❌ | ✅ | ⚠️ | ⚠️ (11) | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| apiKey | | | ✅ | | ✅ (cookie) | ✅ | | | ✅ | ✅ | | ✅ (query) | |
| bearer / http | ✅ | ✅ | | ✅ | ✅ | ✅ | ✅ | | ✅ | | ✅ | | |
| OAuth2 / OIDC | | | ✅ | | | | ✅ | | | | ✅ (OIDC) | | |
| Very large (>1 MB) | ✅ | ✅ | ✅ | ✅ (sum) | ✅ (sum) | | | | | ✅ | | ✅ | |
| Very small (<20 KB) | | | | | ⚠️ (entry 16 KB) | | | | | | | | ✅ |
| No `operationId` | ❌ | ❌ | ❌ | ⚠️ (in files) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Non-identifiers in names | ✅ (schemas with `.`) | ✅ | ❌ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ |
| `required` outside `properties` | ❌ | ✅ (18) | ❌ | ? | ? | ✅ (1) | ❌ | ✅ (2) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Non-standard `format` | ✅ | ✅ | ✅ | ? | ? | ⚠️ | ❌ | ❌ | ❌ | ✅ (`text`) | ⚠️ | ❌ | ❌ |
| `$ref` not on a schema (file/extension) | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ❌ |

`?` in multi-file No. 4 and No. 5 — not measured across all schema files (the script reads only one root structure).

## Coverage gaps

Could not be closed:

1. **3.2 constructs beyond the version string.** Grace and whoami use only `openapi: 3.2.0`. The `QUERY` method, `tags` with `parent`/`kind`, `itemSchema` (for SSE in 3.2), `$self`, `mediaTypes` appear only in the official OAI examples (CC-BY-4.0, 3 KB) and in Train Travel (NC-SA). Recommendation: take the OAI examples as small fixtures.
2. **Path parameter styles `matrix`/`label`.** I found no public specification with them. The only explicit path style is `simple` in Stripe (450). `form`/`deepObject`/`pipeDelimited` are covered by Stripe, OpenAI, Jellyfin, Maps. A synthetic fixture is needed.
3. **Real SSE with an event schema.** There is only `text/event-stream` in the responses of OpenAI and Tambo. SSE on `itemSchema` (3.2) and with a `discriminator` by event type was not found. A synthetic fixture is needed.
4. **The combination of `nullable: true` + `type: [x, "null"]` in one document in 3.1+.** Grace nearly does (3.2 with `nullable`), but on a small scale. For 3.1 this is a common generator defect; search for it separately or write it by hand.
5. **A multi-file specification with `$ref` over HTTP.** All that were found have only local relative references. The R-requirements forbid the network, so this is not needed, but there is no real specification with `http(s)://` references in the corpus.
6. **Code-first frameworks with no separate example:** NSwag (only a tiny [RicoSuter example](https://github.com/RicoSuter/NSwag/tree/master/src/NSwag.Sample.NET90Minimal), MIT) and a clean springfox/OAS 2→3 migration. This is partly covered: Swashbuckle (No. 10) gives the same class of errors.
7. **Domains.** No. 2 and No. 9 (AI) overlap; No. 10 and the runner-up Immich (media) overlap too. The "health" domain is covered by the smallest specification (No. 13); there is no real medical system (FHIR/HL7) in the corpus. The key "live" government APIs (weather.gov, ClinicalTrials.gov) are not pinned to a version, so they were not taken into the main set.
8. **HTTP-level errors**: specifications where the `default` response has a different schema in different operations (R11.4) were not searched for separately. Check on Stripe and Airflow (`HTTPValidationError`).

## Sources

- The research was done through the GitHub API (`gh api`), the owners' official raw URLs, and direct requests to `repo.jellyfin.org`, `api.jellyfin.org`, `api.weather.gov`, `clinicaltrials.gov`. Counts were computed with our own script (Ruby, read-only stream processing).
- OpenAPI specification versions: [3.2.0](https://spec.openapis.org/oas/v3.2). 3.2 examples: [OAI/learn.openapis.org](https://github.com/OAI/learn.openapis.org/tree/main/examples/v3.2).
- Defects and normalization: [06-spec-versions-and-defects.md](06-spec-versions-and-defects.md).

## First `check` run (2026-10-11, branch M2, commit 9e590a8)

A compiled `check`, all 13 specifications at the pinned SHAs. Grace twice: the source with 38 files and the bundle.

| Specification | Exit | Time | Memory | Diagnostics |
|---|---|---|---|---|
| Stripe | 0 | 1.04 s | 185 MB | — |
| OpenAI | 0 | 0.29 s | 119 MB | TOA021 ×1 (7 places), TOA110 ×1 |
| Discord | 0 | 0.11 s | 85 MB | — |
| DigitalOcean | 0 | 0.02 s | 27 MB | TOA110 ×791, TOA111 ×2 |
| Medusa Store | 0 | 0.10 s | 58 MB | — |
| Grace (source) | 0 | 0.05 s | 54 MB | TOA111 ×16, TOA110 ×2, TOA021 ×1 |
| Grace (bundle) | 0 | 0.04 s | 46 MB | same as the source |
| Airflow | 0 | 0.06 s | 63 MB | — |
| Artemis | **1** | 0.01 s | 20 MB | TOA001 ×1 |
| Tambo | 0 | 0.01 s | 26 MB | — |
| Jellyfin | 0 | 0.14 s | 92 MB | — |
| Ditto | 0 | 0.04 s | 48 MB | — |
| Google Maps | 0 | 0.11 s | 87 MB | — |
| EFGS | 0 | 0.01 s | 16 MB | — |

What was found:

1. **Artemis is not read at all.** springdoc writes `example: !!timestamp '2025-07-27T07:17:05.500Z'` in the examples. `package:yaml` does not know the YAML 1.1 tag `!!timestamp` and fails with TOA001. Needed: read the standard YAML 1.1 tags (`!!timestamp`, `!!binary`, `!!set`, `!!omap`) as a string or a value with a warning diagnostic, instead of rejecting the document.
2. **DigitalOcean is effectively empty.** The multi-file specification in the Redocly style puts `$ref` where OAS does not allow it: at the operation level (`get: {$ref: resources/....yml}`) and in place of a string (`description: {$ref: "description.yml#/introduction"}`). Bundlers (Redocly, swagger-cli) resolve `$ref` anywhere, as a JSON Reference. We ignore such keys (TOA110), so all 791 operations drop out. Needed: a "`$ref` anywhere" mode (substitution before parsing, as the bundlers do) with a diagnostic at each non-standard place.
3. **Grace: real defects, the diagnostics are correct.**
   - `$ref: #/DifferenceType` without quotes: in YAML `#` starts a comment, so the value becomes `null`. It is worth adding a hint "put the `$ref` in quotes".
   - `oneOf: [[{$ref}]]` — a list inside a list.
   - An empty `description:`.
   - `nullable` in a 3.2 document.

The rest (Stripe, Discord, Medusa, Airflow, Tambo, Jellyfin, Ditto, Google Maps, EFGS) are read without M2 diagnostics. The defects from the catalog above (non-standard `operationId`s, missing `operationId`s, `required` without a property) belong to the normalizer level (M3); the M2 `check` does not look for them yet.

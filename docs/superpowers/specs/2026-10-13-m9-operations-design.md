# M9: operation emitter and `generate` — design

**Date:** 2026-10-13.

**Requirements:** R5.3, R10.1–R10.9, R11.1–R11.7 ([requirements.md](../../requirements.md)).

**Previous stages:**
- [M6 design](2026-10-12-m6-ir-design.md) — the IR of operations: groups, parameters, bodies, responses, `ErrorsIr`;
- [M7 design](2026-10-12-m7-runtime-design.md) — `Result`, `CallOptions`, `OperationRequest`, `DioRequestSender`, parameter codecs;
- [M8 design](2026-10-12-m8-models-design.md) — the model emitter, `DartWriter`, `generate`, the manifest.

**Carried over:** [roadmap](../../roadmap.md), the sections "Carried over from M2–M8" marked M9.

## Decisions

1. **Only `Result`, no exceptions** (decision 4 of the research, M7).
   - Each method returns `Future<Result<T, E>>`.
   - `E = Never` when no errors are documented.
   - `T = void` when a successful response has no body.
2. **Method signature (user decision).**
   - All parameters are named; the required ones are `required`. The body is a separate named `body:`. The last one is `CallOptions? call`.
   - Example: `Future<Result<Pet, UpdatePetError>> updatePet({required String petId, String? traceId, required PetInput body, CallOptions? call})`.
   - A new parameter in the spec does not shift positions.
   - Argument names are taken from the IR (M6). Collisions are already resolved there.
3. **Groups and the root client (user decision).**
   - A class per group `{Tag}Api` (M6, R5.3). It is an ordinary class without modifiers, because it is mocked through `implements` (R10.7).
   - The group's constructor — `PetsApi(Dio dio)`.
   - The root class is named after the client's name in the config: `clients.petstore` → `PetstoreClient(Dio dio)`. It can be overridden through `naming.client`. The groups in it are fields: `client.pets.getPet(...)`.
   - The generator does not change the user's `Dio` (R10.1): neither `baseUrl` nor interceptors.
4. **Files (decision of M8, a note of the M8 review for M9).**
   - The API is written to `<output>/api/` (`pets_api.dart`, barrel `api.dart`), the root — to `<output>/<client>.dart`.
   - The names of the files and of the operation types are allocated after the models, in their own namespace, so the models never move.
   - The manifest and the M8 safeguards apply to the whole directory.
5. **Responses (R10.6).**
   - One successful response gives `T`. Several different 2xx give a sealed type with variants named after the status: `CreatePetResponse` → `CreatePetResponseOk` / `…Created` (decision 18 of M8).
   - 204 and a response without a body give `void`.
   - The status and headers are available in `Success` (M7).
   - Non-JSON responses:
     - `text/*` → `String`;
     - binary → `Uint8List`;
     - SSE — M10.
   - A binary or text successful response with JSON errors has a direct way to decode. This closes the item "Carried over from M7".
6. **Errors (R11.1, R11.3–R11.5).**
   - `ErrorsIr` from M6:
     - `NoErrors` → `Never`;
     - `SingleError` → the schema's type;
     - `ErrorsByStatus` → sealed `CreatePetError` with variants named after the status (decision 18 of M8).
   - An undocumented status gives `UndocumentedStatus`, transport — `TransportError`, cancellation — `Cancelled` (M7).
   - An empty `statuses` in `SingleError` means "all 4xx/5xx" (M6, carried over).
   - An operation whose only response is a `default` with a body gets an explicit rule: a diagnostic and the success type `void` or `JsonValue`. The plan defines the concrete rule.
7. **Request bodies (R10.4).**
   - JSON — a model.
   - `application/x-www-form-urlencoded` — a model, encoded by the runtime with `encoding` (`style` and `explode` for each property). Here the media type's `encoding`, carried over from M6 into the IR, goes.
   - `multipart/form-data` — a model of the parts.
   - A binary body.
8. **Files — one's own type in the runtime (user decision).**
   - The type: `FileUpload.bytes(Uint8List, {filename, contentType})` and `FileUpload.stream(Stream<List<int>>, {length, filename, contentType})`.
   - The runtime converts it to a `MultipartFile` or a Dio body. Dio types do not get into the signatures of the generated methods.
   - Works on the web (bytes).
9. **Parameters (R10.3)** are encoded by the runtime (M7).
   - `querystring` (OAS 3.2) goes into the runtime as a separate parameter "the whole query", if it fits the plan. Otherwise TOA564 remains.
   - The path template variable has one definition for the generator and the runtime (carried over from M6).
10. **Security and servers (R10.8, R10.9).**
    - The operation's `securitySchemes` and `security` go into `OperationInfo.security` as metadata for interceptors. The generator does not insert the keys themselves.
    - `servers` are generated as constants of the root client: URL templates and variables with type-safe substitution. Setting them in Dio is the user's job (R10.1).
11. **The envelope `{data: T}`** is only unwrapped (decision of M6). The generic mode (`ApiData<T>`) is not done in M9 (user decision). In the roadmap — "when needed".
12. **Imports.**
    - The generated API imports `package:dio` and the runtime through `show`.
    - The names they export that may collide with schemas (`Response`, `Options`, `Headers`) are resolved in one way: either a `show` without the conflicting names, or reservation in the IR. The plan fixes the choice (carried over from M6).
13. **`generate` writes the whole client**: the models, the API and the root. Skipping clients with errors, the manifest, `--force` and the lock work as in M8.
14. **Diagnostics.**
    - TOA561 (bytes against discarded alternatives) is split into two codes.
    - The numbering of media types and errors is aligned with 6xx, until the codes are published (carried over from M6).

## Out of scope

- SSE methods — M10.
- `callbacks`, `links`, webhooks — later. The plan decides whether a diagnostic "not generated" is needed.
- The generic envelope.
- An HTTP abstraction beyond Dio — before 1.0.

# typed_openapi: roadmap for the grund platform

Date: 2026-10-15, updated 2026-10-20 for M12b. typed_openapi stays a client generator for any code-first
spec. grund, a Dart backend platform whose contract is HTTP plus OpenAPI 3.1,
is one more spec source and the main consumer. The main roadmap stays
`docs/roadmap.md` (M1–M13). The stages below add to it and do not cancel
M12–M13. The cross-repository plan lives in the grund repository: `docs/superpowers/PLATFORM-PLAN.md`.

State on 2026-10-20: M1–M11b and M12b are implemented (OAS 3.0, 3.1 and 3.2,
normalization with diagnostics, `Result<T, E>`, SSE through `openEvents`
returning `Stream<SseItem<T>>` with reconnection, the corpus and the fuzz).
Since M11b the runtime is split: `typed_openapi_client` builds requests and
reads responses and hands bytes to a `ClientTransport`, `typed_openapi_dio`
is the Dio transport, and `typed_openapi_transport_tests` is the conformance
suite for any transport. Security is metadata only, in
`TransportRequest.operation` (`OperationInfo`; the Dio transport also puts it
in `RequestOptions.extra`). `ProblemDetail` exists only as a Spring recipe.
Since M12b the engine (read, normalize, check, the IR) is the package `typed_openapi_core`, and `typed_openapi` is the generator and CLI on top of it.
Nothing is published. M12 (diff and lock file) is implemented.

## Stages

| # | Stage | Needed by | Done when |
|---|---|---|---|
| T1 | **grund as a reference source** | grund G2 | The spec of the grund example (`tasks_api`) is in the corpus and `check` reports no diagnostics. The JSON Schema 2020-12 that grund emits is covered: `type` arrays for nullable, `const`, `$defs`, `oneOf` with `discriminator` (sealed classes), `default`, and constraints (`minLength`, `maximum`, `pattern`). A test in grund's CI runs `check` through the programmatic API (`SpecChecker`). |
| T2 | **RFC 9457 and RFC 8288 in the client core** | grund G2 | A built-in `ProblemDetails` (`type`, `title`, `status`, `detail`, `instance`, extensions) is the typed error for `application/problem+json`, without a recipe. A cursor pagination helper reads `Link` (`rel="next"`) and offers a stream or iterator of pages. |
| T3 | **Applying security schemes** | grund G4 | The generated client applies `securitySchemes` from the operation metadata: `bearer` through a `TokenProvider` interface, and `apiKey` in a header, query or cookie. Applying them in `typed_openapi_client` keeps it the same through every transport; where it sits is decided when T3 is planned. A recipe and an end-to-end test with `token_manager_dio` through `DioTransport` cover refresh after a 401 and the replay. Operations without security never get a token. |
| T4 | **Move to `typed_sse`** | grund G5 | `typed_openapi_client` depends on the new `typed_sse` library instead of its own decoder. The public `SseMessage` and `SseItem` are re-exported for compatibility. Reconnection and `Last-Event-ID` behave as before. |
| T5 | **Release 0.1.0** | grund 1.0 (wanted by grund 0.2.0) | At least the documentation part of M13: the support matrix and a "client for grund" recipe. `publish --dry-run` has no warnings. |

## Order

T1 and T2 land before G2. T3 lands before G4. T4 lands after `typed_sse`
releases S1 and before G5. T5 lands before grund 1.0, ideally next to grund 0.2.0 so that "generate a client" works from pub.dev (`typed_openapi_client` is published before `typed_openapi_dio`). grund's own releases do not wait for it, because its packages never depend on typed_openapi: only contract tests in its unpublished example do, and those (T1: `SpecChecker`) depend on `typed_openapi_core`, not on the generator. M12 (diff and lock file)
proceeds independently on the main roadmap.

## Out of scope

A `package:http` client (still an open decision in `docs/requirements.md`;
grund does not need it), server stub generation, and an AsyncAPI client for
WebSocket.

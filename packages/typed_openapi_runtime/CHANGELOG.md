## 0.0.1 - Unreleased

### Added
- `Patch<T>` for three-state request fields.
- `JsonReader`, `JsonDecodeException` and `JsonValue`: strict JSON decoding
  that reports the JSON pointer of the first mismatch.
- `Date` for `format: date`, with `JsonReader.asDate`.
- `Result<T, E>` with `Success`, `HttpError`, `UndocumentedStatus`,
  `DecodeError`, `TransportError` and `Cancelled`.
- Encoders for OpenAPI path, query, header and cookie parameter styles.
- `OperationInfo`, `OperationRequest` and `RawResponse`.
- `DioRequestSender` and `CallOptions`: requests through the user's Dio.
- `SseDecoder` (WHATWG event stream format), `SseItemDecoder` and the
  `SseItem` stream items; `DioRequestSender.openEvents`.
- For generated models: `DeepEquality` (deep `==` and `hashCode` of lists,
  maps and patches), `JsonReader.constant`, `JsonReader.additional`,
  `JsonReader.asBytes`, and `immutable` re-exported from `package:meta`.

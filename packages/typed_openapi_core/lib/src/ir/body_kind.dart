/// How a body is encoded.
enum BodyKind {
  /// JSON (`application/json` or `+json`).
  json,

  /// `application/x-www-form-urlencoded`.
  form,

  /// `multipart/form-data`.
  multipart,

  /// Text (`text/*` except `text/event-stream`).
  text,

  /// Server-sent events (`text/event-stream`).
  eventStream,

  /// Any other media type: raw bytes.
  bytes,

  /// No content.
  none,
}

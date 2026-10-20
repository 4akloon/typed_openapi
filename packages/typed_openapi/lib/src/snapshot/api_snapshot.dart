/// What a [SnapshotType] is in the generated library.
enum TypeKind {
  /// A model class.
  model,

  /// An enum: a sealed or interface class with a known-values enum.
  enumeration,

  /// A union of variants.
  union,

  /// The sealed type of the successes or errors of an operation.
  statusType,

  /// The sealed type of the events of a stream.
  eventUnion,

  /// The class of the parts of a multipart body.
  parts,

  /// An API class of operations.
  group,

  /// The root client.
  root,
}

/// What a [SnapshotMember] is in its type.
enum MemberKind {
  /// A field of a model or of a parts class.
  field,

  /// A value of an enum.
  value,

  /// A variant of a union.
  variant,

  /// A variant of a status type: one status.
  statusCase,

  /// A variant of an event union: one event name.
  event,

  /// A method of a group.
  method,

  /// A named argument of a method that sends a parameter.
  parameter,

  /// The `body` argument of a method.
  body,

  /// A field of the root client that holds a group.
  groupField,

  /// A server of the root client.
  server,
}

/// A member of a type in an [ApiSnapshot]: what code that uses the client
/// can name, with the facts that decide whether a change breaks it.
final class SnapshotMember {
  /// Creates the member [name] of [kind].
  const SnapshotMember(
    this.name,
    this.kind, {
    this.owner,
    this.facts = const {},
  });

  /// The Dart name.
  final String name;

  /// What the member is.
  final MemberKind kind;

  /// The identity of the member this one belongs to: the method of a
  /// parameter or a body; null for a member of the type itself.
  final String? owner;

  /// The facts by key (`type`, `required`, `json`, `doc`, ...), as text.
  final Map<String, String> facts;
}

/// A type of an [ApiSnapshot].
final class SnapshotType {
  /// Creates the type [name] of [kind].
  const SnapshotType(
    this.name,
    this.kind, {
    this.exhaustive = true,
    this.facts = const {},
    this.members = const {},
  });

  /// The Dart name.
  final String name;

  /// What the type is.
  final TypeKind kind;

  /// Whether a `switch` must name every variant (a `sealed` base); only an
  /// enum, a union, a status type or an event union can be false.
  final bool exhaustive;

  /// The facts of the type itself by key, as text.
  final Map<String, String> facts;

  /// The members by identity.
  final Map<String, SnapshotMember> members;
}

/// The public surface of a generated client (M12, decision 1): its types by
/// a stable identity, a spec location or an operation, never a Dart name.
final class ApiSnapshot {
  /// Creates a snapshot of [types] by identity.
  const ApiSnapshot(this.types);

  /// The types by identity.
  final Map<String, SnapshotType> types;
}

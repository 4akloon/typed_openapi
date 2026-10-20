import 'dart_type.dart';
import 'response_ir.dart';

/// The documented errors of an operation (R11.4).
sealed class ErrorsIr {
  /// Creates the errors.
  const ErrorsIr();
}

/// No documented error: `E` is `Never`.
final class NoErrors extends ErrorsIr {
  /// Creates the value.
  const NoErrors();
}

/// Every documented error has the same body type, which is `E`.
final class SingleError extends ErrorsIr {
  /// Creates the errors.
  const SingleError(this.type, this.statuses);

  /// The body type of every error.
  final DartType type;

  /// The documented error statuses; empty means every 4xx and 5xx one.
  final List<String> statuses;
}

/// Errors with different body types: `E` is a sealed type by status.
final class ErrorsByStatus extends ErrorsIr {
  /// Creates the errors.
  const ErrorsByStatus(this.cases, {this.sensitive = const {}});

  /// The body type of each status; null for a body-less status.
  final List<(String, DartType?)> cases;

  /// The statuses of [cases] whose body is a secret (see
  /// [ResponseIr.sensitive]).
  final Set<String> sensitive;
}

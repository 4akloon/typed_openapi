import 'declaration_names.dart';
import 'direction_index.dart';
import 'ir_context.dart';
import 'mapping_state.dart';
import 'model_notices.dart';
import 'override_notices.dart';
import 'schema_queries.dart';

/// What every part of the schema mapper reads: the client's context, the
/// directions schemas are used in, and the collaborators that answer
/// questions or give names.
final class MappingTools {
  /// Tools for the client of [context].
  MappingTools(this.context, this.directions);

  /// The client's context: the spec, the config, the overrides, the report.
  final IrContext context;

  /// Where each schema is used.
  final DirectionIndex directions;

  /// What the mapping has created so far.
  final MappingState state = MappingState();

  /// Questions about schemas that follow their `$ref`s.
  late final SchemaQueries queries = SchemaQueries(context);

  /// Names of declarations, helper types and members.
  late final DeclarationNames names = DeclarationNames(context);

  /// Reports of overrides that change nothing.
  late final OverrideNotices notices = OverrideNotices(context);

  /// Reports of what a model leaves out of its schema.
  late final ModelNotices modelNotices = ModelNotices(context);
}

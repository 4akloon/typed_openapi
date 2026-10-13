import '../diagnostics/json_pointer.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'declaration_names.dart';
import 'mapping_tools.dart';
import 'schema_shapes.dart';
import 'union_notices.dart';
import 'union_state.dart';

/// Finds the discriminator values that select the variants of a union: the
/// ones its `mapping` gives, the `const` of an inline variant's property,
/// and the component key of a `$ref` variant (R9.1).
final class DiscriminatorReader {
  /// A reader for the spec of [_tools].
  DiscriminatorReader(this._tools) : _notices = _tools.unionNotices;

  final MappingTools _tools;
  final UnionNotices _notices;

  /// The values that select [variants] of the union at [site], and the
  /// variant the default mapping names; none for a union without a
  /// discriminator.
  DiscriminatorValues read(UnionSite site, List<VariantDraft> variants) {
    final discriminator = site.schema.discriminator;
    final property = discriminator?.propertyName;
    if (discriminator == null || property == null) {
      return const DiscriminatorValues.none();
    }
    final values = <SpecLocation, List<String>>{};
    _fromMapping(site, discriminator, variants, values);
    _fromVariants(property, variants, values);
    _reportDuplicates(variants, values);
    return DiscriminatorValues(
      values,
      _defaultVariant(site, discriminator, variants),
    );
  }

  /// Adds the values of the `mapping` that name a variant to [values].
  void _fromMapping(
    UnionSite site,
    Discriminator discriminator,
    List<VariantDraft> variants,
    Map<SpecLocation, List<String>> values,
  ) {
    final targets = {for (final v in variants) ?v.target};
    final document = site.schema.location.document;
    for (final MapEntry(key: value, value: ref)
        in discriminator.mapping.entries) {
      final target = _mappingTarget(ref, document);
      if (target == null) continue;
      if (site.isSubtypes && target == site.schema.location) {
        _notices.mappingToBase(discriminator, value);
      } else if (!targets.contains(target)) {
        _notices.mappingNotVariant(discriminator, value);
      } else {
        (values[target] ??= []).add(value);
      }
    }
  }

  /// Adds the value of each variant the `mapping` does not name: the
  /// `const` of an inline variant's property, or the key of a component.
  void _fromVariants(
    String property,
    List<VariantDraft> variants,
    Map<SpecLocation, List<String>> values,
  ) {
    for (final variant in variants) {
      final target = variant.target;
      if (target == null) {
        // The value an inline variant's own discriminator property holds
        // selects it: the schema allows no other.
        if (_constantProperty(variant.branch, property, {})
            case final String v) {
          values[variant.branch.location] = [v];
        } else {
          _notices.valueMissing(variant.branch);
        }
        continue;
      }
      final key = DeclarationNames.componentKey(target);
      if (key != null && !values.containsKey(target)) values[target] = [key];
    }
  }

  /// Reports the values that select an earlier variant too.
  void _reportDuplicates(
    List<VariantDraft> variants,
    Map<SpecLocation, List<String>> values,
  ) {
    final owners = <String, VariantDraft>{};
    for (final variant in variants) {
      final key = variant.target ?? variant.branch.location;
      for (final value in values[key] ?? const <String>[]) {
        if (owners.putIfAbsent(value, () => variant) == variant) continue;
        _notices.valueDuplicate(value, variant.branch);
      }
    }
  }

  /// The type of the variant that the default mapping of [discriminator]
  /// names, if it has one.
  DartType? _defaultVariant(
    UnionSite site,
    Discriminator discriminator,
    List<VariantDraft> variants,
  ) {
    final ref = discriminator.defaultMapping;
    if (ref == null) return null;
    final target = _mappingTarget(ref, site.schema.location.document);
    DartType? fallback;
    for (final variant in variants) {
      if (variant.target != null && variant.target == target) {
        fallback = variant.type;
      }
    }
    if (fallback == null) _notices.defaultNotVariant(discriminator, ref);
    return fallback;
  }

  /// The one value the property [name] of [schema] can hold, when it is a
  /// `const` or a one-value enum, in the schema or one of its `allOf` parts;
  /// [seen] stops a cycle.
  Object? _constantProperty(
    Schema schema,
    String name,
    Set<SpecLocation> seen,
  ) {
    final queries = _tools.queries;
    final object = queries.resolved(schema);
    if (object == null || !seen.add(object.location)) return null;
    if (object.properties[name] case final property?) {
      final resolved = queries.resolved(property);
      final values = resolved == null
          ? null
          : SchemaShapes.enumValues(resolved);
      return values != null && values.length == 1 ? values.single : null;
    }
    for (final part in object.allOf) {
      if (_constantProperty(part, name, seen) case final value?) return value;
    }
    return null;
  }

  /// The schema a discriminator `mapping` value names: a
  /// `components.schemas` key or a `$ref` in the document of the union.
  SpecLocation? _mappingTarget(String ref, Uri document) {
    final model = _tools.context.model;
    final Schema? written;
    if (ref.startsWith('#/')) {
      final node = model.nodeAt(SpecLocation(document, JsonPointer.parse(ref)));
      written = node is Schema ? node : null;
    } else if (!ref.contains('#') && !ref.contains('/')) {
      written = model.document.components?.schemas[ref];
    } else {
      written = null;
    }
    return written == null ? null : model.resolveSchema(written)?.location;
  }
}

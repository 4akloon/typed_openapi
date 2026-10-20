import '../model/spec_node.dart';
import 'ir_context.dart';
import 'names.dart';
import 'spec_operation.dart';

/// The group an operation is in before the class name template; [untagged]
/// when it has no group of its own (no tag), so it is in the default group.
final class GroupChoice {
  /// The group [name]; `''` is the default group.
  const GroupChoice(this.name, {this.untagged = false});

  /// The group's word: a tag or a path segment in UpperCamelCase, or an
  /// override's group; `''` for the default group.
  final String name;

  /// Whether the operation is in the default group for want of a tag.
  final bool untagged;
}

/// Puts operations into groups (R5.3) and names the group classes in the
/// library scope.
final class GroupNames {
  /// Creates the namer for the client of [_context].
  const GroupNames(this._context);

  static const _names = DartNames();

  final IrContext _context;

  /// The group of [entry] before the class name template: an override's
  /// `group`, else by `group_by`; [tagOfGroup] remembers the tag or path
  /// segment each group was made from.
  GroupChoice choose(SpecOperation entry, Map<String, String> tagOfGroup) {
    if (_overridden(entry) case final name?) return GroupChoice(name);
    return switch (_context.config.groupBy) {
      .single => const GroupChoice(''),
      .path => _byPath(entry, tagOfGroup),
      .tag => _byTag(entry, tagOfGroup),
    };
  }

  /// The group an override names for [entry], if it names a valid one.
  String? _overridden(SpecOperation entry) {
    final override = _context.overrides.operationAt(entry.operation.location);
    final written = override?.group;
    if (override == null || written == null) return null;
    // A group is a word list like a tag: a value that differs from its
    // UpperCamelCase form only by case or separators is that form.
    final words = _names.pascal(written);
    if (_names.isValid(written, .type)) return written;
    if (words != null && !_names.dropsLetters(written)) return words;
    return _context.checkedOverrideName(
      override,
      'group',
      written,
      .type,
      what: 'group',
    );
  }

  GroupChoice _byPath(SpecOperation entry, Map<String, String> tagOfGroup) {
    final segment = entry.path
        .split('/')
        .firstWhere(
          (s) => s.isNotEmpty && !s.startsWith('{'),
          orElse: () => '',
        );
    final group = _names.pascal(segment) ?? '';
    if (group.isNotEmpty && !tagOfGroup.containsKey(group)) {
      tagOfGroup[group] = segment;
      _context.checkLossyName(
        segment,
        group,
        entry.operation.location,
        what: 'Path segment',
        override: _context.overrideAt(
          ['operations', entry.overrideKey],
          {'group': group},
        ),
      );
    }
    return GroupChoice(group);
  }

  GroupChoice _byTag(SpecOperation entry, Map<String, String> tagOfGroup) {
    final operation = entry.operation;
    if (operation.tags.isEmpty) return const GroupChoice('', untagged: true);
    final tag = operation.tags.first;
    final tagAt = operation.location.child('tags').child(0);
    if (operation.tags.length > 1) _reportTags(entry, tag);
    final group = _names.pascal(tag);
    if (group == null) {
      _context.report(
        .nameUnrepresentable,
        'Tag "$tag" has no ASCII letter or digit, so the operation is in '
        '${_context.config.defaultGroup}.',
        tagAt,
        fix: 'Name the group of the operation.',
        override: _context.overrideAt(
          ['operations', entry.overrideKey],
          {'group': 'MyGroup'},
        ),
      );
      return const GroupChoice('');
    }
    _remember(entry, tag, group, tagOfGroup);
    return GroupChoice(group);
  }

  /// Reports that [entry] has several tags and is in the group of [tag].
  void _reportTags(SpecOperation entry, String tag) {
    final operation = entry.operation;
    _context.report(
      .operationMultipleTags,
      'This operation has tags ${operation.tags.join(', ')}; it is '
      'generated once, in the group of "$tag".',
      operation.location.child('tags'),
      fix: 'Keep one tag at the source, or name the group.',
      override: _context.overrideAt(
        ['operations', entry.overrideKey],
        {'group': _names.pascal(tag) ?? 'MyGroup'},
      ),
    );
  }

  /// Remembers that [tag] made [group], or reports that another tag made it
  /// already (TOA555).
  void _remember(
    SpecOperation entry,
    String tag,
    String group,
    Map<String, String> tagOfGroup,
  ) {
    final tagAt = entry.operation.location.child('tags').child(0);
    final earlier = tagOfGroup[group];
    if (earlier == null) {
      tagOfGroup[group] = tag;
      _context.checkLossyName(
        tag,
        group,
        tagAt,
        what: 'Tag',
        override: _context.overrideAt(
          ['operations', entry.overrideKey],
          {'group': group},
        ),
      );
    } else if (earlier != tag) {
      _context.report(
        .tagsMerged,
        'Tags "$earlier" and "$tag" give the same group name, so their '
        'operations are in one class.',
        tagAt,
        fix: 'Write the tag the same way everywhere at the source.',
      );
    }
  }

  /// The class name of [group] in the library scope [types]; [groupClasses]
  /// are the class names the groups got already.
  String className(
    NameScope types,
    String group,
    SpecLocation site,
    Set<String> groupClasses,
  ) {
    final config = _context.config;
    final candidate = group.isEmpty
        ? config.defaultGroup
        : config.groupTemplate.replaceAll('{Tag}', group);
    final (name, change) = types.claim(candidate);
    groupClasses.add(name);
    if (change != null) {
      final ofGroup = change == .collision && groupClasses.contains(candidate);
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Group class "$candidate" would be a name Dart already has; it '
                  'is named "$name".'
            : ofGroup
            ? 'The group class "$candidate" is the class of another group '
                  'already; this group\'s class is named "$name".'
            : 'A type is named "$candidate" already; the group class is '
                  'named "$name".',
        site,
        fix: ofGroup
            ? 'Name the group with the group override of its operations, or '
                  'change naming.group or naming.default_group in the config.'
            : 'Change naming.group in the config, or rename the schema.',
      );
    }
    return name;
  }
}

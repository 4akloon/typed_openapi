/// The rule of R15.4 (spec decision 7): a change of generated output for the
/// same input is a breaking change of the generator, so a change that
/// changes output must say so in the CHANGELOG and raise the version.
///
/// While the base's CHANGELOG top section is titled `Unreleased` for the
/// version in the base pubspec, that version has never been published, so the
/// output change needs the CHANGELOG entry but no raise of the version.
///
/// A change may also waive the raise for its own release: a line
/// `Semver exemption: <reason>` in the top CHANGELOG section that the base's
/// top section does not have. The reason is read in review, and the waiver is
/// gone from the next release because the base then has the line.
final class SemverRule {
  /// Creates the rule.
  const SemverRule();

  /// The heading of the CHANGELOG section that names changed output.
  static const String heading = '### Output changes';

  static final _version = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)',
    multiLine: true,
  );
  static final _section = RegExp('^## ', multiLine: true);
  static final _exemption = RegExp(
    r'^Semver exemption:[ \t]*(\S.*)$',
    multiLine: true,
  );
  static final _entries = RegExp(
    r'^###[ \t]+Output changes[ \t]*\n\s*([-*] [\s\S]*?)'
    r'(?=^### |^## |(?![\s\S]))',
    multiLine: true,
  );

  /// What the change must still add, one sentence each; empty when it
  /// complies. [outputChanged] says whether `corpus.lock` or a fixture's
  /// golden files changed; the pubspecs and CHANGELOGs are the generator's
  /// at the base and in the change.
  List<String> problems({
    required bool outputChanged,
    required String basePubspec,
    required String pubspec,
    required String baseChangelog,
    required String changelog,
  }) {
    if (!outputChanged) return const [];
    final base = _parse(basePubspec);
    final next = _parse(pubspec);
    final entries = _outputEntries(changelog);
    return [
      if (entries == null || entries == _outputEntries(baseChangelog))
        'The generated output changed (corpus.lock or a golden file): add '
            'an entry under "$heading" in the top section of '
            'packages/typed_openapi/CHANGELOG.md that names the clients and '
            'files affected.',
      if (base == null || next == null)
        'The version of packages/typed_openapi/pubspec.yaml cannot be read.'
      else if (!_isUnreleased(baseChangelog, base) &&
          !_raised(base, next) &&
          !_isExempt(baseChangelog, changelog))
        'The generated output changed: raise the version of '
            'packages/typed_openapi/pubspec.yaml from ${base.join('.')} to '
            '${_required(base)} or later (${base.first == 0 ? 'minor before '
                      '1.0' : 'major after 1.0'}).',
    ];
  }

  static List<int>? _parse(String pubspec) => switch (_version.firstMatch(
    pubspec,
  )) {
    final m? => [for (var i = 1; i <= 3; i++) int.parse(m[i] ?? '0')],
    null => null,
  };

  /// Whether the top section of [changelog] is the `Unreleased` one of
  /// [version].
  static bool _isUnreleased(String changelog, List<int> version) {
    final heading = _topSection(changelog).split('\n').first.trim();
    return RegExp(
      '^## ${RegExp.escape(version.join('.'))}\\s+-\\s+Unreleased\\s*\$',
      caseSensitive: false,
    ).hasMatch(heading);
  }

  /// Whether the top section of [changelog] gives a reason for the waiver and
  /// the top section of [baseChangelog] does not already.
  static bool _isExempt(String baseChangelog, String changelog) =>
      _exemption.hasMatch(_topSection(changelog)) &&
      !_exemption.hasMatch(_topSection(baseChangelog));

  static bool _raised(List<int> base, List<int> next) => base.first == 0
      ? next.first > 0 || next[1] > base[1]
      : next.first > base.first;

  static String _required(List<int> base) =>
      base.first == 0 ? '0.${base[1] + 1}.0' : '${base.first + 1}.0.0';

  /// The bullets under the heading in the top section, or null.
  static String? _outputEntries(String changelog) =>
      _entries.firstMatch(_topSection(changelog))?[1]?.trim();

  /// The text of the first `## ` section of [changelog], line ends as `\n`.
  static String _topSection(String changelog) {
    final text = changelog.replaceAll('\r\n', '\n');
    final starts = _section.allMatches(text).map((m) => m.start).toList();
    if (starts.isEmpty) return '';
    return text.substring(starts.first, starts.length > 1 ? starts[1] : null);
  }
}

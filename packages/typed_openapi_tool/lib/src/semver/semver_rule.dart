/// The rule of R15.4 (spec decision 7): a change of generated output for the
/// same input is a breaking change of the generator, so a change that
/// changes output must say so in the CHANGELOG and raise the version.
final class SemverRule {
  /// Creates the rule.
  const SemverRule();

  /// The heading of the CHANGELOG section that names changed output.
  static const String heading = '### Output changes';

  static final _version = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)',
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
    final top = _topSection(changelog);
    return [
      if (changelog == baseChangelog || !top.contains('$heading\n- '))
        'The generated output changed (corpus.lock or a golden file): add '
            'an entry under "$heading" in the top section of '
            'packages/typed_openapi/CHANGELOG.md that names the clients and '
            'files affected.',
      if (base == null || next == null)
        'The version of packages/typed_openapi/pubspec.yaml cannot be read.'
      else if (!_raised(base, next))
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

  static bool _raised(List<int> base, List<int> next) => base.first == 0
      ? next.first > 0 || next[1] > base[1]
      : next.first > base.first;

  static String _required(List<int> base) =>
      base.first == 0 ? '0.${base[1] + 1}.0' : '${base.first + 1}.0.0';

  /// The text of the first `## ` section of [changelog].
  static String _topSection(String changelog) {
    final start = changelog.indexOf('## ');
    if (start < 0) return '';
    final end = changelog.indexOf('\n## ', start + 3);
    return changelog.substring(start, end < 0 ? changelog.length : end);
  }
}

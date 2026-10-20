import '../config/project_config.dart';

/// The preset [PresetDetector] chose for a spec and why.
final class PresetDetection {
  /// A framework [preset] found because of [reason].
  const PresetDetection(this.preset, this.reason);

  /// No single framework: [Preset.generic], for [reason].
  const PresetDetection.generic(this.reason) : preset = Preset.generic;

  /// The detected preset.
  final Preset preset;

  /// The mark that led to [preset], or why none was chosen.
  final String reason;

  /// Whether [preset] is a framework preset rather than [Preset.generic].
  bool get isFramework => preset != Preset.generic;
}

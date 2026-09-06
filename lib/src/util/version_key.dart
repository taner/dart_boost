import 'package:pub_semver/pub_semver.dart';

/// The fragment-directory key for a package version.
///
/// For `1.0.0` and above the major is the breaking axis, so the key is the
/// major alone. Below `1.0.0` pub treats the *minor* as breaking (`^0.3.1`
/// allows `<0.4.0`), so `0.3` and `0.4` must not collide.
///
/// ```
/// riverpod 2.6.1   -> "2"
/// foo      0.4.2   -> "0.4"
/// bar      3.0.0-dev.1 -> "3"
/// ```
String versionKey(Version version) =>
    version.major > 0 ? '${version.major}' : '0.${version.minor}';

/// The fragment-directory key for a Flutter SDK version.
///
/// Flutter has no meaningful major axis (everything is `3.x`), so SDK
/// fragments are keyed on `<major>.<minor>` -- `3.47.2` -> `3.47`.
String sdkVersionKey(Version version) => '${version.major}.${version.minor}';

/// Renders a version key so it is safe inside a renderer flag identifier.
///
/// `2` stays `2`; `0.4` becomes `0_4`, so `usesFoo0_4` is a single token.
String versionKeyForFlag(String key) => key.replaceAll('.', '_');

/// Parses a version string, tolerating the loose forms pub and Flutter emit
/// (`3.47.2`, `1.0.0+1`, `3.7.7-0.0.pre`). Returns `null` when unparseable.
Version? tryParseVersion(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    return Version.parse(trimmed);
  } on FormatException {
    // Flutter occasionally reports `3.47` or `3.47.2 (channel stable)`.
    final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(trimmed);
    if (match == null) return null;
    return Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3) ?? '0'),
    );
  }
}

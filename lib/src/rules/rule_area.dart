import 'package:path/path.dart' as p;

/// Segments of a glob that name a real directory: no wildcards, no dots.
///
/// `lib/models/**` -> `[lib, models]`. This is what decides which rules belong
/// together, so it deliberately ignores the wildcard tail: a rule about
/// `lib/models/**` and one about `lib/models/*.dart` are about the same place.
List<String> meaningfulSegments(String glob) =>
    glob
        .split('/')
        .where((s) => s.isNotEmpty && !s.contains('*') && !s.contains('.'))
        .toList();

/// Two globs with the same area key are filed together.
String areaKey(String glob) => meaningfulSegments(glob).join('/');

/// Slug candidates for a new rule file, shortest first.
///
/// `lib/src/widgets/**` offers `widgets`, then `src-widgets`, then
/// `lib-src-widgets`. The caller takes the first that is not already in use,
/// so a file gets the shortest name that stays unambiguous.
List<String> filenameCandidates(String glob) {
  final segments = meaningfulSegments(glob);
  if (segments.isEmpty) return <String>['general'];

  final candidates = <String>[
    for (var take = 1; take <= segments.length; take++)
      _slug(segments.sublist(segments.length - take)),
  ];

  // Filter out empty slugs and fall back to general if all were empty.
  final nonEmpty = candidates.where((s) => s.isNotEmpty).toList();
  return nonEmpty.isNotEmpty ? nonEmpty : <String>['general'];
}

String _slug(List<String> segments) => segments
    .join('-')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Project-relative, forward-slashed, and inside the project.
///
/// Returns `null` for a glob that escapes the root: rules describe *this*
/// project, and a rule filed against `../` would be unreachable from the index.
String? normalizeGlob(String glob, {required String projectRoot}) {
  var value = glob.trim().replaceAll(r'\', '/');
  if (value.isEmpty) return null;

  // Strip root prefix if present.
  final root = '${projectRoot.replaceAll(r'\', '/')}/';
  if (value.startsWith(root)) {
    value = value.substring(root.length);
  } else {
    // Not under root prefix. Reject any absolute path form (POSIX, Windows, UNC).
    // Do not strip leading slashes from paths not shown to be inside the root.
    if (p.posix.isAbsolute(value) ||
        RegExp(r'^[a-zA-Z]:').hasMatch(value) ||
        value.startsWith('//')) {
      return null;
    }
  }

  if (value.isEmpty) return null;

  // Normalize the path to resolve .. and //.
  final normalized = p.posix.normalize(value);

  // Reject if it tries to escape the root.
  if (normalized.startsWith('..')) return null;

  return normalized;
}

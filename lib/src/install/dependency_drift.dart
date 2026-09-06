import '../project/package_ref.dart';
import '../project/project.dart';
import '../util/version_key.dart';

/// One dependency that is not where the last run left it.
class DependencyChange {
  const DependencyChange({
    required this.name,
    required this.kind,
    this.before,
    this.after,
  });

  final String name;
  final DependencyChangeKind kind;

  /// Version strings as recorded/resolved, or `null` when the dependency was
  /// absent (or had no resolved version) on that side.
  final String? before;
  final String? after;

  /// Whether the fragment directory this package would select has moved.
  ///
  /// Fragments are keyed on the version key, not the full version, so
  /// `3.0.1 -> 3.0.2` changes nothing that dart_boost composes and does not
  /// deserve a line of output; `2.6.1 -> 3.0.0` changes everything.
  bool get rekeys =>
      kind == DependencyChangeKind.upgraded && _key(before) != _key(after);

  static String? _key(String? version) {
    if (version == null) return null;
    final parsed = tryParseVersion(version);
    return parsed == null ? version : versionKey(parsed);
  }

  String describe() => switch (kind) {
    DependencyChangeKind.added => '+ $name ${after ?? ''}'.trimRight(),
    DependencyChangeKind.removed => '- $name ${before ?? ''}'.trimRight(),
    DependencyChangeKind.upgraded => '  $name $before -> $after',
  };
}

enum DependencyChangeKind { added, removed, upgraded }

/// What moved between two runs: dependencies, and the guidance that followed.
class DependencyDrift {
  const DependencyDrift({
    required this.changes,
    required this.recorded,
    this.gainedFragments = const <String>[],
    this.lostFragments = const <String>[],
  });

  /// Nothing to compare against -- a first install, or a state file written
  /// before dart_boost recorded dependencies.
  static const unknown = DependencyDrift(
    changes: <DependencyChange>[],
    recorded: false,
  );

  final List<DependencyChange> changes;

  /// Whether the previous run actually recorded a dependency set. When false
  /// every list here is empty because the comparison could not be made, not
  /// because nothing changed -- the two must not be reported the same way.
  final bool recorded;

  final List<String> gainedFragments;
  final List<String> lostFragments;

  Iterable<DependencyChange> get added =>
      changes.where((c) => c.kind == DependencyChangeKind.added);

  Iterable<DependencyChange> get removed =>
      changes.where((c) => c.kind == DependencyChangeKind.removed);

  /// Upgrades worth mentioning: the ones that move the fragment key.
  Iterable<DependencyChange> get rekeyed => changes.where((c) => c.rekeys);

  bool get isEmpty => added.isEmpty && removed.isEmpty && rekeyed.isEmpty;
}

/// Compares the direct dependencies of [project] against the map the last run
/// wrote into `dart_boost.json`.
///
/// Direct dependencies only, matching what is recorded: a transitive bump is
/// pub's business, not something the user did between two `update` runs.
DependencyDrift diffDependencies(
  Project project,
  Map<String, String>? previous,
) {
  if (previous == null) return DependencyDrift.unknown;

  final current = snapshotDependencies(project);
  final names = <String>{...previous.keys, ...current.keys}.toList()..sort();

  final changes = <DependencyChange>[];
  for (final name in names) {
    final before = previous[name];
    final after = current[name];
    if (before == null) {
      changes.add(
        DependencyChange(
          name: name,
          kind: DependencyChangeKind.added,
          after: _display(after),
        ),
      );
    } else if (after == null) {
      changes.add(
        DependencyChange(
          name: name,
          kind: DependencyChangeKind.removed,
          before: _display(before),
        ),
      );
    } else if (before != after) {
      changes.add(
        DependencyChange(
          name: name,
          kind: DependencyChangeKind.upgraded,
          before: _display(before),
          after: _display(after),
        ),
      );
    }
  }

  return DependencyDrift(changes: changes, recorded: true);
}

/// The direct dependencies of [project] as `dart_boost.json` records them.
Map<String, String> snapshotDependencies(Project project) {
  final entries =
      project.directPackages.toList()..sort((a, b) => a.name.compareTo(b.name));
  return <String, String>{
    for (final package in entries) package.name: _record(package),
  };
}

/// Which fragment keys appeared and disappeared between two composes.
DependencyDrift withFragmentDrift(
  DependencyDrift drift,
  List<String>? previous,
  List<String> current,
) {
  if (!drift.recorded || previous == null) return drift;
  final before = previous.toSet();
  final after = current.toSet();
  return DependencyDrift(
    changes: drift.changes,
    recorded: true,
    gainedFragments: current.where((key) => !before.contains(key)).toList(),
    lostFragments: previous.where((key) => !after.contains(key)).toList(),
  );
}

/// SDK-sourced and path/git deps resolve to no usable version; `-` keeps them
/// in the map so adding and removing one is still observable.
String _record(PackageRef package) => package.version?.toString() ?? '-';

String? _display(String? recorded) => recorded == '-' ? null : recorded;

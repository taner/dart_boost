import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// What the last run *observed*, as opposed to what the user *chose*.
///
/// Lives under `.dart_tool/`, which every Dart project already gitignores,
/// because these values differ per machine. Committing them made every
/// teammate on a different SDK rewrite the file, and made `update` diff your
/// project against whoever last committed rather than against your own last
/// run.
class MachineState {
  const MachineState({this.dependencies, this.fragments, this.lastRun});

  static const currentSchemaVersion = 2;

  /// The direct dependencies the last run resolved, name -> version.
  ///
  /// This is what makes `update` able to say "you added go_router since the
  /// last run" rather than silently re-composing. Direct only: recording the
  /// full transitive closure would put a hundred lines of churn into a file
  /// that gets rewritten every run, and a transitive bump the user never
  /// asked for is not news. `-` stands in for a dependency with no resolved
  /// version (an SDK, path or git dep), so its presence still round-trips.
  ///
  /// `null` -- not the empty map -- means the last run predates this field.
  /// An empty map means "a project with no dependencies", and conflating the
  /// two makes `update` announce every existing dependency as newly added.
  final Map<String, String>? dependencies;

  /// The fragment keys the last run composed, so `update` can report the
  /// guidance that actually appeared or disappeared -- the user-visible
  /// consequence of a dependency change, which a version diff alone does not
  /// show (most packages have no fragment, and some share one). `null` has
  /// the same "not recorded" meaning as on [dependencies].
  final List<String>? fragments;

  final LastRun? lastRun;

  MachineState copyWith({
    Map<String, String>? dependencies,
    List<String>? fragments,
    LastRun? lastRun,
  }) => MachineState(
    dependencies: dependencies ?? this.dependencies,
    fragments: fragments ?? this.fragments,
    lastRun: lastRun ?? this.lastRun,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentSchemaVersion,
    if (dependencies != null) 'dependencies': dependencies,
    if (fragments != null) 'fragments': fragments,
    if (lastRun != null) 'lastRun': lastRun!.toJson(),
  };

  static MachineState fromJson(Map<String, Object?> json) => MachineState(
    dependencies:
        json.containsKey('dependencies')
            ? _stringMap(json['dependencies'])
            : null,
    fragments:
        json.containsKey('fragments') ? _strings(json['fragments']) : null,
    lastRun:
        json['lastRun'] is Map<String, Object?>
            ? LastRun.fromJson(json['lastRun']! as Map<String, Object?>)
            : null,
  );

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : <String>[];

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return <String, String>{};
    return <String, String>{
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }
}

/// Lets `update` say "Flutter 3.44 -> 3.47, re-composing" and spot a stale
/// `pub get` by comparing against `.dart_tool/version`.
class LastRun {
  const LastRun({this.flutter, this.dart, this.boostVersion});

  final String? flutter;
  final String? dart;
  final String? boostVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    if (flutter != null) 'flutter': flutter,
    if (dart != null) 'dart': dart,
    if (boostVersion != null) 'boostVersion': boostVersion,
  };

  static LastRun fromJson(Map<String, Object?> json) => LastRun(
    flutter: json['flutter'] as String?,
    dart: json['dart'] as String?,
    boostVersion: json['boostVersion'] as String?,
  );
}

/// `.dart_tool/dart_boost/state.json` -- per-machine observations, gitignored
/// by Dart convention since they live under `.dart_tool/`.
class MachineStateStore {
  const MachineStateStore(this.fileSystem, this.projectRoot);

  static const relativePath = '.dart_tool/dart_boost/state.json';

  final FileSystem fileSystem;
  final Directory projectRoot;

  File get file => fileSystem.file(
    p.join(projectRoot.path, p.joinAll(relativePath.split('/'))),
  );

  bool get exists => file.existsSync();

  /// Returns `null` when there is no state file; throws nothing when the file
  /// is corrupt -- a broken state file must not block a re-install.
  MachineState? read({void Function(String)? onWarning}) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      return MachineState.fromJson(decoded);
    } on Object catch (error) {
      onWarning?.call('Ignoring unreadable ${file.path}: $error');
      return null;
    }
  }

  void write(MachineState state) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(state.toJson())}\n',
    );
  }
}

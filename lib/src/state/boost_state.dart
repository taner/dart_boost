import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// `dart_boost.json` at the project root -- what `install` chose, so `update`
/// can repeat it without re-asking.
class BoostState {
  BoostState({
    this.schemaVersion = currentSchemaVersion,
    List<String>? agents,
    this.guidelines = true,
    this.mcp = true,
    List<String>? thirdPartyPackages,
    this.delegateSkills = false,
    this.dependencies,
    this.fragments,
    this.lastRun,
  }) : agents = agents ?? <String>[],
       thirdPartyPackages = thirdPartyPackages ?? <String>[];

  static const currentSchemaVersion = 1;
  static const fileName = 'dart_boost.json';

  final int schemaVersion;

  /// Agent keys, in registry order.
  final List<String> agents;

  final bool guidelines;
  final bool mcp;

  /// Explicit trust allowlist. Third-party fragments are text from arbitrary
  /// pub packages injected into an agent's system prompt, so nothing is read
  /// from a package that is not listed here.
  final List<String> thirdPartyPackages;

  final bool delegateSkills;

  /// The direct dependencies the last run resolved, name -> version.
  ///
  /// This is what makes `update` able to say "you added go_router since the
  /// last run" rather than silently re-composing. Direct only: recording the
  /// full transitive closure would put a hundred lines of churn into a file
  /// the user commits, and a transitive bump the user never asked for is not
  /// news. `-` stands in for a dependency with no resolved version (an SDK,
  /// path or git dep), so its presence still round-trips.
  ///
  /// `null` -- not the empty map -- means the last run predates this field.
  /// The two must stay distinguishable: an empty map is "a project with no
  /// dependencies", and treating a state file written by an older dart_boost
  /// as that would announce every existing dependency as newly added.
  final Map<String, String>? dependencies;

  /// The fragment keys the last run composed, so `update` can report the
  /// guidance that actually appeared or disappeared -- the user-visible
  /// consequence of a dependency change, which a version diff alone does not
  /// show (most packages have no fragment, and some share one). `null` has
  /// the same "not recorded" meaning as on [dependencies].
  final List<String>? fragments;

  final LastRun? lastRun;

  bool trusts(String packageName) => thirdPartyPackages.contains(packageName);

  BoostState copyWith({
    List<String>? agents,
    bool? guidelines,
    bool? mcp,
    List<String>? thirdPartyPackages,
    bool? delegateSkills,
    Map<String, String>? dependencies,
    List<String>? fragments,
    LastRun? lastRun,
  }) => BoostState(
    schemaVersion: schemaVersion,
    agents: agents ?? this.agents,
    guidelines: guidelines ?? this.guidelines,
    mcp: mcp ?? this.mcp,
    thirdPartyPackages: thirdPartyPackages ?? this.thirdPartyPackages,
    delegateSkills: delegateSkills ?? this.delegateSkills,
    dependencies: dependencies ?? this.dependencies,
    fragments: fragments ?? this.fragments,
    lastRun: lastRun ?? this.lastRun,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'agents': agents,
    'features': <String, Object?>{'guidelines': guidelines, 'mcp': mcp},
    'thirdPartyPackages': thirdPartyPackages,
    'delegateSkills': delegateSkills,
    if (dependencies != null) 'dependencies': dependencies,
    if (fragments != null) 'fragments': fragments,
    if (lastRun != null) 'lastRun': lastRun!.toJson(),
  };

  static BoostState fromJson(Map<String, Object?> json) {
    final features = json['features'];
    final featureMap = features is Map ? features : const <Object?, Object?>{};
    return BoostState(
      schemaVersion: (json['version'] as num?)?.toInt() ?? currentSchemaVersion,
      agents: _strings(json['agents']),
      guidelines: featureMap['guidelines'] as bool? ?? true,
      mcp: featureMap['mcp'] as bool? ?? true,
      thirdPartyPackages: _strings(json['thirdPartyPackages']),
      delegateSkills: json['delegateSkills'] as bool? ?? false,
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
  }

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

class BoostStateStore {
  const BoostStateStore(this.fileSystem, this.projectRoot);

  final FileSystem fileSystem;
  final Directory projectRoot;

  File get file =>
      fileSystem.file(p.join(projectRoot.path, BoostState.fileName));

  bool get exists => file.existsSync();

  /// Returns `null` when there is no state file; throws nothing when the file
  /// is corrupt -- a broken state file must not block a re-install.
  BoostState? read({void Function(String)? onWarning}) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      return BoostState.fromJson(decoded);
    } on Object catch (error) {
      onWarning?.call('Ignoring unreadable ${file.path}: $error');
      return null;
    }
  }

  void write(BoostState state) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(render(state));
  }

  static String render(BoostState state) =>
      '${const JsonEncoder.withIndent('  ').convert(state.toJson())}\n';
}

import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'machine_state.dart';

/// `dart_boost.json` at the project root -- what `install` chose, so `update`
/// can repeat it without re-asking.
///
/// Committed to git: these are decisions a human made (which agents, which
/// packages to trust), not facts about the machine that ran `install`. Per-run
/// observations live in [MachineState] instead, so that a teammate on a
/// different Flutter version does not rewrite this file just by running
/// `update`.
class BoostState {
  BoostState({
    this.schemaVersion = currentSchemaVersion,
    List<String>? agents,
    this.guidelines = true,
    this.mcp = true,
    List<String>? thirdPartyPackages,
    this.delegateSkills = false,
    this.rules = const RulesSettings(),
  }) : agents = agents ?? <String>[],
       thirdPartyPackages = thirdPartyPackages ?? <String>[];

  static const currentSchemaVersion = 2;
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

  final RulesSettings rules;

  bool trusts(String packageName) => thirdPartyPackages.contains(packageName);

  BoostState copyWith({
    List<String>? agents,
    bool? guidelines,
    bool? mcp,
    List<String>? thirdPartyPackages,
    bool? delegateSkills,
    RulesSettings? rules,
  }) => BoostState(
    schemaVersion: schemaVersion,
    agents: agents ?? this.agents,
    guidelines: guidelines ?? this.guidelines,
    mcp: mcp ?? this.mcp,
    thirdPartyPackages: thirdPartyPackages ?? this.thirdPartyPackages,
    delegateSkills: delegateSkills ?? this.delegateSkills,
    rules: rules ?? this.rules,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'agents': agents,
    'features': <String, Object?>{'guidelines': guidelines, 'mcp': mcp},
    'thirdPartyPackages': thirdPartyPackages,
    'delegateSkills': delegateSkills,
    'rules': rules.toJson(),
  };

  /// Forces [schemaVersion] to [currentSchemaVersion] regardless of what was
  /// on disk, so a plain read-then-write upgrades a v1 file without a
  /// separate migration step for the choices half.
  static BoostState fromJson(Map<String, Object?> json) {
    final features = json['features'];
    final featureMap = features is Map ? features : const <Object?, Object?>{};
    return BoostState(
      schemaVersion: currentSchemaVersion,
      agents: _strings(json['agents']),
      guidelines: featureMap['guidelines'] as bool? ?? true,
      mcp: featureMap['mcp'] as bool? ?? true,
      thirdPartyPackages: _strings(json['thirdPartyPackages']),
      delegateSkills: json['delegateSkills'] as bool? ?? false,
      rules: RulesSettings.fromJson(json['rules']),
    );
  }

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : <String>[];
}

/// Whether generated project rule files are kept in sync. Consumed by a later
/// task; defaults to on so opting out is a deliberate choice.
class RulesSettings {
  const RulesSettings({this.enabled = true});

  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{'enabled': enabled};

  static RulesSettings fromJson(Object? value) {
    if (value is! Map) return const RulesSettings();
    return RulesSettings(enabled: value['enabled'] as bool? ?? true);
  }
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
  ///
  /// `migrated` is non-null only when the file on disk predates the split
  /// (schema version 1), and carries the observations that used to live
  /// alongside the choices so the caller can write them into their new home
  /// ([MachineState]) instead of losing them.
  ({BoostState state, MachineState? migrated})? read({
    void Function(String)? onWarning,
  }) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;

      final version = (decoded['version'] as num?)?.toInt() ?? 1;
      final state = BoostState.fromJson(decoded);

      if (version >= 2) return (state: state, migrated: null);

      return (state: state, migrated: MachineState.fromJson(decoded));
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

import '../project/package_registry.dart';
import '../project/project.dart';
import '../project/workspace.dart';
import '../util/version_key.dart';
import '../version.dart';

/// The values a fragment can branch on and interpolate.
///
/// The Dart analog of Boost's `GuidelineAssist`. Version *branching* is
/// handled by the fragment tree, not here, so this stays a flat set of named
/// booleans plus a flat map of strings -- which is exactly the language the
/// renderer implements.
class GuidelineFacts {
  GuidelineFacts._({
    required this.project,
    required this.flags,
    required this.variables,
    required Set<String> vocabulary,
  }) : _vocabulary = vocabulary;

  final Project project;

  /// Flags that are currently true.
  final Set<String> flags;

  /// `{{name}}` substitutions.
  final Map<String, String> variables;

  /// Every flag name this object could have emitted, true or false. A name
  /// outside both [flags] and this set is a typo, and the renderer says so.
  final Set<String> _vocabulary;

  /// The contract version third-party fragments declare against. Bump this
  /// when a flag or variable is renamed or removed.
  static const factsVersion = 1;

  /// Every `{{name}}` a fragment may use. Part of the contract third-party
  /// fragments declare against, so it is named rather than implied.
  static const variableNames = <String>{
    'projectName',
    'boostVersion',
    'dartCommand',
    'flutterCommand',
    'sdkCommand',
    'dartRunCommand',
    'pubGetCommand',
    'pubAddCommand',
    'testCommand',
    'analyzeCommand',
    'formatCommand',
    'workspacePrefix',
    'dartVersion',
    'flutterVersion',
    'flutterChannel',
    'flutterMinor',
  };

  /// Names that are always meaningful regardless of what the project uses.
  static const conditionFlags = <String>{
    'isFlutterProject',
    'isDartOnlyProject',
    'isMonorepo',
    'isMelosWorkspace',
    'isPubWorkspace',
    'usesFvm',
    'usesCodegen',
    'hasTests',
    'hasFlutterVersion',
    'hasDartVersion',
  };

  /// Whether [name] is a flag this object could ever set.
  ///
  /// Condition flags are a closed set, so `isFlutterProjekt` is a typo and the
  /// renderer says so. Package flags are an *open* set -- a fragment may
  /// legitimately ask about `usesRiverpodGenerator` in a project that does not
  /// have it -- so anything shaped like one is simply false.
  bool isKnownFlag(String name) =>
      flags.contains(name) ||
      _vocabulary.contains(name) ||
      _packageFlagShape.hasMatch(name);

  static final _packageFlagShape = RegExp(r'^uses[A-Z]');

  bool hasFlag(String name) => flags.contains(name);

  String? variable(String name) => variables[name];

  factory GuidelineFacts.forProject(Project project) {
    final flags = <String>{};
    final vocabulary = <String>{...conditionFlags};

    final sdk = project.sdk;
    final workspace = project.workspace;

    void flag(String name, {required bool value}) {
      vocabulary.add(name);
      if (value) flags.add(name);
    }

    flag('isFlutterProject', value: project.isFlutterProject);
    flag('isDartOnlyProject', value: !project.isFlutterProject);
    flag('isMonorepo', value: workspace.isMonorepo);
    flag('isMelosWorkspace', value: workspace.kind == WorkspaceKind.melos);
    flag('isPubWorkspace', value: workspace.kind == WorkspaceKind.pubWorkspace);
    flag('usesFvm', value: sdk.usesFvm);
    flag('hasFlutterVersion', value: sdk.flutter != null);
    flag('hasDartVersion', value: sdk.dart != null);
    flag(
      'usesCodegen',
      value: project.packages['build_runner']?.isDirect ?? false,
    );
    flag(
      'hasTests',
      value:
          project.packages.containsKey('test') ||
          project.packages.containsKey('flutter_test'),
    );

    // Package flags cover the whole resolved graph, not just direct
    // dependencies: "does this app run riverpod 3" is the honest question a
    // fragment asks. Whether a *fragment* is included at all is a separate
    // decision, and that one does respect `mustBeDirect`.
    for (final package in project.packages.values) {
      final pascal = PackageRegistry.pascalCase(package.name);
      flag('uses$pascal', value: true);
      final key = package.versionKey;
      if (key != null) {
        flag('uses$pascal${versionKeyForFlag(key)}', value: true);
      }
    }

    return GuidelineFacts._(
      project: project,
      flags: flags,
      variables: _buildVariables(project),
      vocabulary: vocabulary,
    );
  }

  /// The invocation prefixes are the direct analog of Boost's Sail-aware
  /// `artisanCommand()` / `composerCommand()`: guidance that tells you to run
  /// `dart` when the project is FVM-pinned is guidance for the wrong SDK.
  static Map<String, String> _buildVariables(Project project) {
    final sdk = project.sdk;
    final fvm = sdk.usesFvm ? 'fvm ' : '';
    final dartCommand = '${fvm}dart';
    final flutterCommand = '${fvm}flutter';
    final sdkCommand = project.isFlutterProject ? flutterCommand : dartCommand;
    final isMelos = project.workspace.kind == WorkspaceKind.melos;

    return <String, String>{
      'projectName': project.name ?? 'this project',
      'boostVersion': packageVersion,

      // Invocation prefixes.
      'dartCommand': dartCommand,
      'flutterCommand': flutterCommand,
      'sdkCommand': sdkCommand,
      'dartRunCommand': '$dartCommand run',
      'pubGetCommand': '$sdkCommand pub get',
      'pubAddCommand': '$sdkCommand pub add',
      'testCommand':
          project.isFlutterProject
              ? '$flutterCommand test'
              : '$dartCommand test',
      'analyzeCommand': '$sdkCommand analyze',
      'formatCommand': '$dartCommand format',
      // Empty (not absent) outside a Melos repo, so fragments can always
      // write `{{workspacePrefix}}dart test` without branching.
      'workspacePrefix': isMelos ? 'melos exec -- ' : '',

      // Versions. Absent keys would make the renderer warn, so every one of
      // these is always present, falling back to a readable placeholder.
      'dartVersion': sdk.dart?.toString() ?? 'unknown',
      'flutterVersion': sdk.flutter?.toString() ?? 'unknown',
      'flutterChannel': sdk.channel ?? 'unknown',
      'flutterMinor': sdk.flutterKey ?? 'unknown',
    };
  }
}

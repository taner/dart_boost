import '../../agents/agent.dart';
import '../../guidelines/composer.dart';
import '../../guidelines/facts.dart';
import '../../project/package_registry.dart';
import '../../rules/rule_repository.dart';
import '../../util/version_key.dart';
import '../../writers/mcp_writer.dart';
import 'boost_command.dart';

/// Prints every fact dart_boost resolved, and where each came from.
///
/// The point is diagnosability: when composed guidance looks wrong, the first
/// question is always "which Flutter did it think you were on, and how did it
/// decide that".
class DoctorCommand extends BoostCommand {
  DoctorCommand() {
    argParser.addFlag(
      'agents',
      defaultsTo: true,
      help: 'Probe for installed agents (spawns one process per command).',
    );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Print the project facts dart_boost resolved.';

  @override
  Future<int> run() async {
    final project = context.resolveProject();
    final facts = GuidelineFacts.forProject(project);

    logger
      ..heading('Project')
      ..field('root', context.relative(project.root.path))
      ..field('package', project.name)
      ..field('workspace', project.workspace.kind.label)
      ..field('analysis root', context.relative(project.analysisRoot.path))
      ..field(
        'package config',
        project.packageConfigPath == null
            ? 'not found (run `pub get`)'
            : context.relative(project.packageConfigPath!),
      )
      ..field('dependency source', project.dependencySource)
      ..field(
        'dependencies',
        '${project.directPackages.length} direct, '
            '${project.packages.length} total',
      );

    final sdk = project.sdk;
    logger
      ..blank()
      ..heading('SDK')
      ..field('flutter project', project.isFlutterProject ? 'yes' : 'no')
      ..field('flutter', '${sdk.flutter ?? '-'}  (${sdk.flutterSource})')
      ..field('dart', '${sdk.dart ?? '-'}  (${sdk.dartSource})')
      ..field('channel', sdk.channel)
      ..field(
        'fvm',
        sdk.usesFvm ? 'yes, pinned to ${sdk.fvmPin ?? 'unknown'}' : 'no',
      )
      ..field('flutter sdk root', sdk.flutterSdkRoot);

    final assets = await context.assets();
    logger
      ..blank()
      ..heading('Guidelines');
    if (assets == null) {
      logger.warn(
        'Bundled guidelines/ tree not found. If this is a published release, '
        'the directory was stripped at publish time -- see the asset guard in '
        'tool/verify_assets.dart.',
      );
    } else {
      final compose =
          GuidelineComposer(
            fileSystem: context.fileSystem,
            assets: assets,
            project: project,
            facts: facts,
          ).compose();
      logger
        ..field('bundled tree', assets.guidelines.path)
        ..field('fragments', '${compose.fragments.length}')
        ..field('keys', compose.keys.isEmpty ? '-' : compose.keys.join(', '));
      if (compose.untrustedThirdParty.isNotEmpty) {
        logger.field(
          'untrusted',
          '${compose.untrustedThirdParty.join(', ')} '
              '(ship guidelines/, not yet opted in)',
        );
      }
      for (final warning in compose.warnings) {
        logger.warn(warning);
      }
    }

    // Only direct dependencies: the transitive flags are real, but there are
    // dozens of them and they bury the ones anybody reads this for.
    final directFlags = <String>[
      for (final package in project.directPackages) ...<String>[
        'uses${PackageRegistry.pascalCase(package.name)}',
        if (package.versionKey != null)
          'uses${PackageRegistry.pascalCase(package.name)}'
              '${versionKeyForFlag(package.versionKey!)}',
      ],
    ]..sort();
    logger
      ..field(
        'condition flags',
        facts.flags.where(GuidelineFacts.conditionFlags.contains).join(', '),
      )
      ..field('direct package flags', directFlags.join(', '))
      ..field(
        'commands',
        '${facts.variables['sdkCommand']} / '
            '${facts.variables['dartRunCommand']}',
      );

    final spec = McpCommandResolver.resolve(
      project: project,
      fileSystem: context.fileSystem,
      isWindows: context.isWindows,
      onWarning: logger.warn,
    );
    logger
      ..blank()
      ..heading('MCP')
      ..field('command', '${spec.command} ${spec.args.join(' ')}')
      ..field(
        'probe',
        McpCommandResolver.probe(spec, context.processRunner)
            ? 'responds'
            : 'no response (hidden subcommand; may be an older SDK)',
      );

    // Never probe `dart run dart_boost:mcp` with McpCommandResolver.probe:
    // unlike `dart mcp-server`, it is a stdio JSON-RPC server that blocks
    // reading its own stdin and does not understand `--version`, so spawning
    // it here would hang `doctor` forever. The real question -- "will an
    // agent be able to start this?" -- has a static answer instead: only when
    // dart_boost is a resolved dependency of the target project, because
    // `dart run dart_boost:mcp` cannot resolve otherwise.
    final rulesRepository = RuleRepository(
      fileSystem: context.fileSystem,
      projectRoot: project.root,
    );
    var failedRuleCount = 0;
    final ruleFiles = rulesRepository.readAll(
      onWarning: (_) => failedRuleCount++,
    );
    final rulesDirExists =
        context.fileSystem.directory(rulesRepository.directory).existsSync();
    final isDevDependency = project.package('dart_boost')?.isDirect ?? false;
    final rulesEnabled =
        context.stateStore(project.root).read()?.state.rules.enabled ?? true;

    logger
      ..blank()
      ..heading('Rules')
      ..field(
        'directory',
        context.relative(rulesRepository.directory) +
            (rulesDirExists ? '' : ' (not found)'),
      )
      ..field(
        'rule files',
        failedRuleCount == 0
            ? '${ruleFiles.length} rule file'
                '${ruleFiles.length == 1 ? '' : 's'} parsed'
            : '${ruleFiles.length} rule file'
                '${ruleFiles.length == 1 ? '' : 's'} parsed, '
                '$failedRuleCount failed to parse',
      )
      ..field(
        'dev dependency',
        isDevDependency
            ? 'yes'
            : 'not a dev dependency -- the rules server will not start '
                '(`dart run dart_boost:mcp` cannot resolve)',
      )
      ..field('server command', '${spec.command} run dart_boost:mcp')
      ..field('enabled', rulesEnabled ? 'yes' : 'no (see dart_boost.json)');

    if (argResults!['agents'] as bool) {
      final detector = context.detector();
      logger
        ..blank()
        ..heading('Agents');
      for (final agent in AgentRegistry.all) {
        final reason = detector.reasonFor(agent, project.root);
        if (reason == null) {
          logger.skipped('${agent.name.padRight(16)} not detected');
        } else {
          logger.success('${agent.name.padRight(16)} $reason');
        }
      }
    }

    for (final warning in project.warnings) {
      logger.warn(warning);
    }

    return 0;
  }
}

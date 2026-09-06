import 'package:args/args.dart';

import '../../agents/agent.dart';
import '../../install/installer.dart';
import '../../project/project.dart';
import '../../state/boost_state.dart';
import '../../version.dart';
import '../../writers/guidelines_writer.dart';
import '../../writers/mcp_writer.dart';
import 'boost_command.dart';

class InstallCommand extends BoostCommand {
  InstallCommand() {
    addInstallOptions(argParser);
  }

  @override
  String get name => 'install';

  @override
  String get description =>
      'Compose guidelines and wire up every AI agent in this project.';

  @override
  Future<int> run() async => runInstall(this, isUpdate: false);
}

/// Shared between `install` and `update` -- `update` is `install` with the
/// previous run's answers pre-filled.
void addInstallOptions(ArgParser parser) {
  parser
    ..addMultiOption(
      'agents',
      valueHelp: 'key',
      allowed: AgentRegistry.keys,
      help: 'Configure exactly these agents instead of the detected ones.',
    )
    ..addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Accept the detected agents without prompting.',
    )
    ..addFlag(
      'guidelines',
      defaultsTo: true,
      help: 'Write the guidelines file.',
    )
    ..addFlag('mcp', defaultsTo: true, help: 'Write the MCP server entry.')
    ..addMultiOption(
      'trust',
      valueHelp: 'package',
      help:
          'Opt in to guidelines shipped by these dependencies. Persisted to '
          '${BoostState.fileName}.',
    );
}

Future<int> runInstall(BoostCommand command, {required bool isUpdate}) async {
  final context = command.context;
  final logger = command.logger;
  final args = command.argResults!;

  final assets = await context.assets();
  if (assets == null) {
    logger.error(
      'Bundled guidelines/ tree not found. dart_boost cannot compose anything '
      'without it.',
    );
    return BoostCommand.softwareError;
  }

  final project = context.resolveProject();
  for (final warning in project.warnings) {
    logger.warn(warning);
  }
  if (project.packageConfigPath == null) {
    logger.warn(
      'No .dart_tool/package_config.json found. Run `pub get` first, or the '
      'composed guidelines will be keyed on incomplete information.',
    );
  }

  final store = context.stateStore(project.root);
  final previous = store.read(onWarning: logger.warn);

  if (isUpdate && previous == null) {
    logger.error(
      'No ${BoostState.fileName} in ${context.relative(project.root.path)}. '
      'Run `dart_boost install` first.',
    );
    return BoostCommand.usageError;
  }

  if (isUpdate) _reportDrift(command, project, previous!);

  final agents = await _selectAgents(
    command,
    project,
    previous,
    isUpdate: isUpdate,
  );
  if (agents == null) return BoostCommand.usageError;
  if (agents.isEmpty) {
    logger.warn('No agents selected; nothing to do.');
    return 0;
  }

  final trusted =
      <String>{
          ...?previous?.thirdPartyPackages,
          ...args['trust'] as List<String>,
        }.toList()
        ..sort();

  final plan = InstallPlan(
    agents: agents,
    guidelines: (args['guidelines'] as bool) && (previous?.guidelines ?? true),
    mcp: (args['mcp'] as bool) && (previous?.mcp ?? true),
    trustedThirdParty: trusted,
  );

  final report = Installer(
    context,
  ).run(project: project, assets: assets, plan: plan);

  _report(command, report, plan);

  if (!context.dryRun) {
    store.write(
      BoostState(
        agents: agents.map((agent) => agent.key).toList(),
        guidelines: plan.guidelines,
        mcp: plan.mcp,
        thirdPartyPackages: trusted,
        delegateSkills: previous?.delegateSkills ?? false,
        lastRun: LastRun(
          flutter: project.sdk.flutter?.toString(),
          dart: project.sdk.dart?.toString(),
          boostVersion: packageVersion,
        ),
      ),
    );
  }

  return report.hasFailures ? BoostCommand.softwareError : 0;
}

/// `null` means the selection failed and the caller should stop.
Future<List<Agent>?> _selectAgents(
  BoostCommand command,
  Project project,
  BoostState? previous, {
  required bool isUpdate,
}) async {
  final context = command.context;
  final logger = command.logger;
  final explicit = command.argResults!['agents'] as List<String>;

  if (explicit.isNotEmpty) {
    return explicit.map((key) => AgentRegistry.byKey(key)!).toList();
  }

  final detected = context.detector().detect(project.root);
  for (final entry in detected) {
    logger.detail('detected ${entry.agent.name} (${entry.reason})');
  }

  // `update` repeats the previous run's choices, plus anything newly installed.
  final preselected = <String>{
    ...?previous?.agents,
    if (!isUpdate || previous == null)
      ...detected.map((entry) => entry.agent.key),
  };
  if (isUpdate) {
    final fresh =
        detected
            .where(
              (entry) => !(previous?.agents.contains(entry.agent.key) ?? false),
            )
            .toList();
    for (final entry in fresh) {
      logger.info('New agent detected since the last run: ${entry.agent.name}');
      preselected.add(entry.agent.key);
    }
  }

  if ((command.argResults!['yes'] as bool) || !context.dialogs.interactive) {
    if (preselected.isEmpty) {
      logger.warn(
        'No agents detected. Pass --agents=${AgentRegistry.keys.take(2).join(',')} '
        'to configure specific ones.',
      );
    }
    return AgentRegistry.all
        .where((agent) => preselected.contains(agent.key))
        .toList();
  }

  logger.info(
    'Select the agents to configure (space to toggle, enter to confirm):',
  );
  final options =
      AgentRegistry.all.map((agent) {
        final reason =
            detected
                .where((entry) => entry.agent.key == agent.key)
                .map((entry) => entry.reason)
                .firstOrNull;
        return reason == null ? agent.name : '${agent.name}  ($reason)';
      }).toList();

  final selection = await context.dialogs.multiSelect(
    options,
    initialSelected: <int>{
      for (var i = 0; i < AgentRegistry.all.length; i++)
        if (preselected.contains(AgentRegistry.all[i].key)) i,
    },
  );
  if (selection == null) {
    logger.warn('Cancelled.');
    return <Agent>[];
  }
  return selection.map((index) => AgentRegistry.all[index]).toList();
}

void _reportDrift(BoostCommand command, Project project, BoostState previous) {
  final logger = command.logger;
  final last = previous.lastRun;
  if (last == null) return;

  final flutter = project.sdk.flutter?.toString();
  if (last.flutter != null && flutter != null && last.flutter != flutter) {
    logger.info('Flutter ${last.flutter} -> $flutter, re-composing.');
  }
  final dart = project.sdk.dart?.toString();
  if (last.dart != null && dart != null && last.dart != dart) {
    logger.info('Dart ${last.dart} -> $dart, re-composing.');
  }
  if (last.boostVersion != null && last.boostVersion != packageVersion) {
    logger.info('dart_boost ${last.boostVersion} -> $packageVersion.');
  }
}

void _report(BoostCommand command, InstallReport report, InstallPlan plan) {
  final logger = command.logger;
  final context = command.context;

  if (context.dryRun) logger.info('Dry run: nothing was written.');

  logger
    ..blank()
    ..heading('Guidelines');
  if (report.compose.isEmpty) {
    logger.warn('No fragments matched this project.');
  } else {
    logger.info(
      '${report.compose.fragments.length} fragments: '
      '${report.compose.keys.join(', ')}',
    );
  }
  for (final write in report.guidelineWrites) {
    final agents = write.agents.map((agent) => agent.name).join(', ');
    final line =
        '${context.relative(write.path).padRight(28)} '
        '${write.outcome.label}  ($agents)';
    write.outcome == GuidelineWriteOutcome.unchanged
        ? logger.skipped(line)
        : logger.success(line);
  }

  if (plan.mcp) {
    logger
      ..blank()
      ..heading('MCP')
      ..info('${report.spec.command} ${report.spec.args.join(' ')}');
    for (final write in report.mcpWrites) {
      final line =
          '${context.relative(write.path).padRight(28)} '
          '${write.outcome.label}  (${write.agent.name})';
      switch (write.outcome) {
        case McpWriteOutcome.failed:
          logger.error('$line -- ${write.message}; file left untouched');
        case McpWriteOutcome.unchanged:
          logger.skipped(line);
        case McpWriteOutcome.created:
        case McpWriteOutcome.updated:
          logger.success(line);
      }
    }
  }

  if (report.compose.untrustedThirdParty.isNotEmpty) {
    logger
      ..blank()
      ..heading('Third-party guidelines')
      ..info(
        'These dependencies ship a guidelines/ tree that was NOT read: '
        '${report.compose.untrustedThirdParty.join(', ')}.',
      )
      ..info(
        'Their text would go straight into an agent\'s system prompt, so each '
        'needs explicit opt-in: re-run with '
        '--trust=${report.compose.untrustedThirdParty.first}.',
      );
  }

  for (final warning in report.warnings) {
    logger.warn(warning);
  }
}

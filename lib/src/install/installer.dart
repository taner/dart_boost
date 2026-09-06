import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../agents/agent.dart';
import '../assets/bundled_assets.dart';
import '../cli/context.dart';
import '../guidelines/composer.dart';
import '../guidelines/facts.dart';
import '../project/project.dart';
import '../writers/guidelines_writer.dart';
import '../writers/mcp_writer.dart';

class InstallPlan {
  const InstallPlan({
    required this.agents,
    this.guidelines = true,
    this.mcp = true,
    this.trustedThirdParty = const <String>[],
  });

  final List<Agent> agents;
  final bool guidelines;
  final bool mcp;
  final List<String> trustedThirdParty;
}

class GuidelineFileReport {
  const GuidelineFileReport({
    required this.path,
    required this.agents,
    required this.outcome,
  });

  final String path;

  /// Every agent that reads this file. Several agents share `AGENTS.md`, and
  /// writing it once per agent would stack three sentinel blocks.
  final List<Agent> agents;

  final GuidelineWriteOutcome outcome;
}

class InstallReport {
  const InstallReport({
    required this.compose,
    required this.guidelineWrites,
    required this.mcpWrites,
    required this.spec,
    this.mcpAvailable = true,
    this.warnings = const <String>[],
  });

  final ComposeResult compose;
  final List<GuidelineFileReport> guidelineWrites;
  final List<McpWriteReport> mcpWrites;
  final McpServerSpec spec;

  /// Whether `dart mcp-server --version` answered.
  final bool mcpAvailable;

  final List<String> warnings;

  bool get hasFailures => mcpWrites.any((report) => !report.ok);
}

/// The shared body of `install` and `update`.
class Installer {
  const Installer(this.context);

  final BoostContext context;

  InstallReport run({
    required Project project,
    required BundledAssets assets,
    required InstallPlan plan,
  }) {
    final warnings = <String>[];

    final facts = GuidelineFacts.forProject(project);
    final compose =
        GuidelineComposer(
          fileSystem: context.fileSystem,
          assets: assets,
          project: project,
          facts: facts,
          trustedThirdParty: plan.trustedThirdParty,
        ).compose();
    warnings.addAll(compose.warnings);

    final guidelineWrites = <GuidelineFileReport>[];
    if (plan.guidelines && !compose.isEmpty) {
      final writer = GuidelinesWriter(
        context.fileSystem,
        dryRun: context.dryRun,
      );
      final byPath = groupGuidelineTargets(plan.agents, project.root);
      byPath.forEach((path, agents) {
        final outcome = writer.write(
          path: path,
          guidelines: compose.content,
          frontmatter: agents.any((agent) => agent.frontmatter),
        );
        guidelineWrites.add(
          GuidelineFileReport(path: path, agents: agents, outcome: outcome),
        );
      });
    }

    final spec = McpCommandResolver.resolve(
      project: project,
      fileSystem: context.fileSystem,
      isWindows: context.isWindows,
      onWarning: warnings.add,
    );

    var mcpAvailable = true;
    final mcpWrites = <McpWriteReport>[];
    if (plan.mcp) {
      mcpAvailable = McpCommandResolver.probe(spec, context.processRunner);
      if (!mcpAvailable) {
        warnings.add(
          '`${spec.command} ${spec.args.join(' ')} --version` did not answer. '
          'The subcommand is hidden (it does not appear in `dart help`), so '
          'this may just be an older SDK. The config below is still written; '
          'upgrade the SDK if the server fails to start.',
        );
      }
      final writer = McpWriter(
        fileSystem: context.fileSystem,
        dryRun: context.dryRun,
      );
      for (final agent in plan.agents) {
        mcpWrites.add(
          writer.write(agent: agent, projectRoot: project.root, spec: spec),
        );
      }
    }

    return InstallReport(
      compose: compose,
      guidelineWrites: guidelineWrites,
      mcpWrites: mcpWrites,
      spec: spec,
      mcpAvailable: mcpAvailable,
      warnings: warnings,
    );
  }
}

/// Groups agents by the guidelines file they share, keyed so that the file is
/// written exactly once.
///
/// Two separate requirements pull in opposite directions here. Seven of the
/// nine agents read `AGENTS.md`, so the *key* has to be canonical or the
/// sentinel block gets stacked seven deep. But the *path written* must not be
/// canonical: `p.canonicalize` lower-cases on Windows, so canonicalizing the
/// write target creates `claude.md` and `agents.md` there -- files that are
/// found on a case-insensitive filesystem and then silently not found by any
/// agent once the same repository is checked out on Linux or macOS.
///
/// So: key on the canonical form, write the spelling the agent declared.
Map<String, List<Agent>> groupGuidelineTargets(
  Iterable<Agent> agents,
  Directory projectRoot, {
  String Function(String path)? canonicalize,
}) {
  final canonical = canonicalize ?? p.canonicalize;
  final declaredForKey = <String, String>{};
  final byPath = <String, List<Agent>>{};

  for (final agent in agents) {
    final declared = agent.guidelinesPath(projectRoot);
    final path = declaredForKey.putIfAbsent(
      canonical(declared),
      () => declared,
    );
    byPath.putIfAbsent(path, () => <Agent>[]).add(agent);
  }

  return byPath;
}

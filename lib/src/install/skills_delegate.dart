import '../agents/agent_detector.dart';
import '../cli/context.dart';
import '../project/project.dart';
import '../util/process_runner.dart';

/// How `skills` was found, which decides how it gets invoked.
enum SkillsResolution {
  /// A resolved dependency of the target project. `dart run skills get` uses
  /// the version pub already picked, offline.
  dependency('a dependency of this project'),

  /// An executable on `PATH` (a `dart pub global activate`, or a wrapper).
  executable('on PATH'),

  /// Not present anywhere locally. Reachable only as `dart run skills@ get`,
  /// which resolves and downloads it from pub.dev.
  remote('published on pub.dev');

  const SkillsResolution(this.label);

  final String label;
}

/// What dart_boost would run to hand off to `package:skills`.
class SkillsInvocation {
  const SkillsInvocation(this.resolution, this.executable, this.arguments);

  final SkillsResolution resolution;
  final String executable;
  final List<String> arguments;

  String get display => <String>[executable, ...arguments].join(' ');
}

/// Result of the hand-off, for reporting and for the state file.
enum SkillsOutcome { notFound, declined, skipped, dryRun, ran, failed }

/// Delegation to `package:skills` after a successful install.
///
/// dart_boost writes guidelines and MCP config; `skills` fetches the agent
/// skills that packages ship. They are complementary and deliberately not
/// merged, so the honest thing after an install is to offer the other half
/// rather than reimplement it.
///
/// The hard rule is that this never fails an install. `skills` being absent,
/// declined, or exiting non-zero is reported and nothing more -- an install
/// that already wrote every file it promised has succeeded.
class SkillsDelegate {
  SkillsDelegate(this.context, {AgentDetector? detector})
    : _detector = detector ?? context.detector();

  final BoostContext context;
  final AgentDetector _detector;

  static const packageName = 'skills';

  /// The remote-run form. Deliberately not the default: it resolves and
  /// downloads a package from pub.dev, which is not something to do behind a
  /// `--yes` on a machine that never asked for it. `--skills` opts in.
  static const remoteInvocation = SkillsInvocation(
    SkillsResolution.remote,
    'dart',
    <String>['run', 'skills@', 'get'],
  );

  /// Locally resolvable forms only, unless [allowRemote].
  SkillsInvocation? resolve(Project project, {bool allowRemote = false}) {
    if (project.package(packageName) != null) {
      return const SkillsInvocation(
        SkillsResolution.dependency,
        'dart',
        <String>['run', packageName, 'get'],
      );
    }
    if (_detector.hasCommand(packageName)) {
      return const SkillsInvocation(
        SkillsResolution.executable,
        packageName,
        <String>['get'],
      );
    }
    return allowRemote ? remoteInvocation : null;
  }

  /// Offers -- or, with prior consent, just runs -- the hand-off.
  ///
  /// [requested] is the tri-state `--skills` flag: `true` forces the run and
  /// unlocks the remote form, `false` suppresses it entirely, `null` means
  /// "decide from what is installed and what the last run agreed to".
  Future<SkillsOutcome> offer({
    required Project project,
    required bool? requested,
    required bool consentedPreviously,
    required bool assumeYes,
  }) async {
    if (requested == false) return SkillsOutcome.skipped;

    final invocation = resolve(project, allowRemote: requested == true);
    if (invocation == null) {
      context.logger.detail(
        'package:skills is not resolvable here; skipping the skills hand-off.',
      );
      return SkillsOutcome.notFound;
    }

    if (!await _agreed(
      invocation,
      requested: requested,
      consentedPreviously: consentedPreviously,
      assumeYes: assumeYes,
    )) {
      return SkillsOutcome.declined;
    }

    context.logger
      ..blank()
      ..heading('Skills');

    if (context.dryRun) {
      context.logger.info('Dry run: would run `${invocation.display}`.');
      return SkillsOutcome.dryRun;
    }

    context.logger.info('Running `${invocation.display}` ...');
    final outcome = context.processRunner.run(
      invocation.executable,
      invocation.arguments,
      workingDirectory: project.root.path,
    );
    return _report(invocation, outcome);
  }

  Future<bool> _agreed(
    SkillsInvocation invocation, {
    required bool? requested,
    required bool consentedPreviously,
    required bool assumeYes,
  }) async {
    if (requested == true) return true;
    if (consentedPreviously) return true;
    if (assumeYes || !context.interactive) {
      // Without a human, only the locally resolvable forms run: nothing that
      // reaches the network happens because a script passed `--yes`.
      return invocation.resolution != SkillsResolution.remote;
    }
    return context.dialogs.confirm(
      'package:skills is ${invocation.resolution.label}. '
      'Run `${invocation.display}` to fetch the skills your dependencies ship?',
    );
  }

  SkillsOutcome _report(SkillsInvocation invocation, ProcessOutcome outcome) {
    final logger = context.logger;
    final text = <String>[
      outcome.stdout.trimRight(),
      outcome.stderr.trimRight(),
    ].where((part) => part.isNotEmpty).join('\n');

    if (outcome.succeeded) {
      if (text.isNotEmpty) logger.detail(text);
      logger.success('${invocation.display}  done');
      return SkillsOutcome.ran;
    }

    // Never fatal: the guidelines and MCP config are already on disk, and a
    // failed hand-off to a separate tool is that tool's problem to report.
    logger.warn(
      '`${invocation.display}` '
      '${outcome.exitCode < 0 ? 'could not be started' : 'exited ${outcome.exitCode}'}'
      '${text.isEmpty ? '' : ':\n$text'}',
    );
    logger.info('Guidelines and MCP config were written regardless.');
    return SkillsOutcome.failed;
  }
}

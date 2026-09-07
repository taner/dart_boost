import '../project/project.dart';
import '../util/process_runner.dart';

/// What happened when `install`/`update` tried to make project rules usable.
enum RulesWiringOutcome {
  disabled('rules are disabled'),
  alreadyPresent('dart_boost is already a dev dependency'),
  added('added dart_boost as a dev dependency'),
  declined('declined'),
  skippedUnattended('skipped: no one to confirm the pubspec change'),
  failed('could not add the dev dependency');

  const RulesWiringOutcome(this.label);

  final String label;

  /// Whether the `dart_boost` MCP server entry should be written for this
  /// outcome. Every other outcome means `dart run dart_boost:mcp` would not
  /// resolve, so writing the entry would just point an agent at a command
  /// that fails.
  bool get resolvable =>
      this == RulesWiringOutcome.alreadyPresent ||
      this == RulesWiringOutcome.added;
}

/// `dart run dart_boost:mcp` only resolves when dart_boost is a dependency of
/// the target project, so enabling rules means adding one.
///
/// Editing `pubspec.yaml` on a machine that never asked is the same class of
/// action as downloading a package unasked, which `--skills` already refuses
/// to do. So unattended runs skip the wiring and say so; the guidelines and
/// the SDK MCP entry are still written regardless.
Future<RulesWiringOutcome> ensureDevDependency({
  required Project project,
  required ProcessRunner processes,
  required bool interactive,
  required bool dryRun,
  required Future<bool> Function(String question) confirm,
  required void Function(String) log,
}) async {
  if (project.package('dart_boost')?.isDirect == true) {
    return RulesWiringOutcome.alreadyPresent;
  }

  if (!interactive) {
    log(
      'Project rules need dart_boost as a dev dependency, and adding one '
      'unattended is not something to do on a machine that did not ask. '
      'Run `dart pub add dev:dart_boost` and re-run, or pass --no-rules.',
    );
    return RulesWiringOutcome.skippedUnattended;
  }

  // Checked before asking, not after: a dry run never edits pubspec.yaml
  // regardless of the answer, so confirming first would be exactly the
  // prompt-for-a-write-it-will-not-make that `--dry-run` exists to avoid.
  if (dryRun) return RulesWiringOutcome.added;

  final agreed = await confirm(
    'Add dart_boost as a dev dependency so agents can record project rules?',
  );
  if (!agreed) return RulesWiringOutcome.declined;

  final result = processes.run('dart', const <String>[
    'pub',
    'add',
    'dev:dart_boost',
  ], workingDirectory: project.root.path);
  if (!result.succeeded) {
    log(
      '`dart pub add dev:dart_boost` failed; rules were not wired. ${result.stderr}',
    );
    return RulesWiringOutcome.failed;
  }

  return RulesWiringOutcome.added;
}

import '../../rules/rule_repository.dart';
import 'boost_command.dart';

/// `dart run dart_boost rules index`.
///
/// The index is regenerated on every `record_rule`, so this exists for the
/// one case that bypasses the tool: a rule file added or edited by hand,
/// which stays invisible to agents until the index names it.
class RulesCommand extends BoostCommand {
  RulesCommand() {
    addSubcommand(_RulesIndexCommand());
  }

  @override
  String get name => 'rules';

  @override
  String get description => 'Inspect and maintain .ai/rules.';
}

class _RulesIndexCommand extends BoostCommand {
  @override
  String get name => 'index';

  @override
  String get description =>
      'Regenerate .ai/rules/index.md from the rule files on disk.';

  @override
  Future<int> run() async {
    final repository = RuleRepository(
      fileSystem: context.fileSystem,
      projectRoot: context.workingDirectory,
      dryRun: context.dryRun,
    );

    // A malformed rule file is reported, not fatal -- the whole point of this
    // command is to let someone fix things up by hand, and a hard failure
    // here would block them from doing that for every *other* file too.
    final changed = repository.writeIndex(onWarning: logger.warn);

    // `writeIndex` returning `true` under `--dry-run` means "would change",
    // per `AtomicWriter.write` -- it never touches disk in that mode. Report
    // that honestly instead of claiming the write already happened, the same
    // way `install_command.dart` does for its own writes.
    if (context.dryRun) logger.info('Dry run: nothing was written.');
    final verb = context.dryRun ? 'Would rewrite' : 'Rewrote';
    logger.info(
      changed
          ? '$verb ${context.relative(repository.indexPath)}.'
          : 'Index already up to date.',
    );
    return 0;
  }
}

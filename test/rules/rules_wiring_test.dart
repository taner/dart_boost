@TestOn('vm')
library;

import 'package:dart_boost/src/cli/dialog_support.dart';
import 'package:dart_boost/src/install/rules_wiring.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:test/test.dart';

import '../support/fake_project.dart';

/// Direct coverage of `ensureDevDependency` -- the consent gate for editing a
/// user's `pubspec.yaml`. `test/rules/rules_install_test.dart` only ever
/// drives it through `--yes`, so it can only reach `alreadyPresent` and
/// `skippedUnattended`; this file is what actually exercises a human saying
/// yes or no, and pub succeeding or failing.
void main() {
  late FileSystem fs;
  late FakeProcessRunner processes;
  late List<String> logs;

  setUp(() {
    fs = memoryFs();
    processes = FakeProcessRunner();
    logs = <String>[];
  });

  Project projectWith({bool dependsOnDartBoost = false}) {
    final fake = FakeProject(fs, '/app')..pubspec(
      flutter: false,
      devDependencies:
          dependsOnDartBoost
              ? const <String, String>{'dart_boost': '^0.2.0'}
              : const <String, String>{},
    );
    return ProjectResolver(
      fileSystem: fs,
      processRunner: processes,
    ).resolve(fake.root);
  }

  test(
    'already a dev dependency: no confirm, no pub add, spec resolvable',
    () async {
      // A confirmation is scripted but must never be consumed.
      final dialogs = FakeDialogSupport(confirmations: <bool>[false]);

      final outcome = await ensureDevDependency(
        project: projectWith(dependsOnDartBoost: true),
        processes: processes,
        interactive: true,
        dryRun: false,
        confirm: dialogs.confirm,
        log: logs.add,
      );

      expect(outcome, RulesWiringOutcome.alreadyPresent);
      expect(outcome.resolvable, isTrue);
      expect(dialogs.questions, isEmpty);
      expect(processes.invocations, isEmpty);
    },
  );

  test(
    'declined: outcome is declined, pub add never runs, spec not resolvable',
    () async {
      final dialogs = FakeDialogSupport(confirmations: <bool>[false]);

      final outcome = await ensureDevDependency(
        project: projectWith(),
        processes: processes,
        interactive: true,
        dryRun: false,
        confirm: dialogs.confirm,
        log: logs.add,
      );

      expect(outcome, RulesWiringOutcome.declined);
      expect(outcome.resolvable, isFalse);
      expect(
        dialogs.questions.single,
        allOf(contains('dart_boost'), contains('dev dependency')),
      );
      expect(
        processes.invocations,
        isNot(contains('dart pub add dev:dart_boost')),
      );
    },
  );

  test(
    'added: a confirmed yes runs pub add, which succeeds; spec resolvable',
    () async {
      processes.responses['dart pub add dev:dart_boost'] = const ProcessOutcome(
        0,
        'Added dart_boost',
        '',
      );
      final dialogs = FakeDialogSupport(confirmations: <bool>[true]);

      final outcome = await ensureDevDependency(
        project: projectWith(),
        processes: processes,
        interactive: true,
        dryRun: false,
        confirm: dialogs.confirm,
        log: logs.add,
      );

      expect(outcome, RulesWiringOutcome.added);
      expect(outcome.resolvable, isTrue);
      expect(processes.invocations, <String>['dart pub add dev:dart_boost']);
    },
  );

  test(
    'failed: a confirmed yes runs pub add, which fails; reported, not fatal, '
    'spec not resolvable',
    () async {
      processes.responses['dart pub add dev:dart_boost'] = const ProcessOutcome(
        1,
        '',
        'Could not find a version that satisfies constraints',
      );
      final dialogs = FakeDialogSupport(confirmations: <bool>[true]);

      final outcome = await ensureDevDependency(
        project: projectWith(),
        processes: processes,
        interactive: true,
        dryRun: false,
        confirm: dialogs.confirm,
        log: logs.add,
      );

      expect(outcome, RulesWiringOutcome.failed);
      expect(outcome.resolvable, isFalse);
      expect(
        logs.join('\n'),
        contains('Could not find a version that satisfies constraints'),
      );
      // `ensureDevDependency` never throws: a broken `pub add` is reported
      // like any other outcome, not propagated as an exception that would
      // take the whole install down with it.
    },
  );

  test('unattended: skipped without ever asking, and says why', () async {
    final outcome = await ensureDevDependency(
      project: projectWith(),
      processes: processes,
      interactive: false,
      dryRun: false,
      confirm: (_) async {
        fail('must not ask when there is no one to answer');
      },
      log: logs.add,
    );

    expect(outcome, RulesWiringOutcome.skippedUnattended);
    expect(outcome.resolvable, isFalse);
    expect(logs.join('\n'), contains('dev dependency'));
    expect(processes.invocations, isEmpty);
  });

  test('dry run: resolves without asking or writing, since nothing will be '
      'written anyway', () async {
    final outcome = await ensureDevDependency(
      project: projectWith(),
      processes: processes,
      interactive: true,
      dryRun: true,
      confirm: (_) async {
        fail('must not ask to confirm a write that will not happen');
      },
      log: logs.add,
    );

    expect(outcome, RulesWiringOutcome.added);
    expect(processes.invocations, isEmpty);
  });
}

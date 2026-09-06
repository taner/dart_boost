import 'package:dart_boost/src/cli/context.dart';
import 'package:dart_boost/src/cli/dialog_support.dart';
import 'package:dart_boost/src/install/skills_delegate.dart';
import 'package:dart_boost/src/project/project.dart';
import 'package:dart_boost/src/util/logger.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;
  late List<String> output;
  late FakeProcessRunner processes;

  setUp(() {
    fs = memoryFs();
    output = <String>[];
    processes = FakeProcessRunner();
  });

  Project projectWith({bool dependsOnSkills = false}) {
    final fake =
        FakeProject(fs, '/app')
          ..pubspec(
            flutter: false,
            devDependencies:
                dependsOnSkills
                    ? const <String, String>{'skills': '^0.1.0'}
                    : const <String, String>{},
          )
          ..lock(<String, String>{
            if (dependsOnSkills) 'skills': '0.1.0 direct dev',
          });
    return ProjectResolver(
      fileSystem: fs,
      processRunner: processes,
    ).resolve(fake.root);
  }

  BoostContext contextWith({
    DialogSupport? dialogs,
    bool dryRun = false,
    Map<String, String> environment = const <String, String>{},
  }) => BoostContext(
    fileSystem: fs,
    processRunner: processes,
    logger: BoostLogger.buffered(output, verbose: true),
    dialogs: dialogs ?? const NonInteractiveDialogSupport(),
    workingDirectory: fs.directory('/app'),
    dryRun: dryRun,
    isWindows: false,
    environment: environment,
  );

  /// `skills get` succeeding, keyed as `FakeProcessRunner` keys invocations.
  void skillsSucceeds(String key) =>
      processes.responses[key] = const ProcessOutcome(
        0,
        'fetched 3 skills',
        '',
      );

  group('resolve', () {
    test('prefers the project dependency, which needs no network', () {
      final invocation = SkillsDelegate(
        contextWith(),
      ).resolve(projectWith(dependsOnSkills: true));

      expect(invocation!.resolution, SkillsResolution.dependency);
      expect(invocation.display, 'dart run skills get');
    });

    test('falls back to a `skills` on PATH', () {
      processes.responses['sh -c command -v skills'] = const ProcessOutcome(
        0,
        '/usr/local/bin/skills',
        '',
      );

      final invocation = SkillsDelegate(contextWith()).resolve(projectWith());

      expect(invocation!.resolution, SkillsResolution.executable);
      expect(invocation.display, 'skills get');
    });

    test('the remote form is reachable only when asked for', () {
      final delegate = SkillsDelegate(contextWith());

      expect(delegate.resolve(projectWith()), isNull);
      expect(
        delegate.resolve(projectWith(), allowRemote: true)!.display,
        'dart run skills@ get',
      );
    });
  });

  group('offer', () {
    test('is a no-op, not a failure, when skills is absent', () async {
      final outcome = await SkillsDelegate(contextWith()).offer(
        project: projectWith(),
        requested: null,
        consentedPreviously: false,
        assumeYes: true,
      );

      expect(outcome, SkillsOutcome.notFound);
      expect(processes.invocations, isNot(contains(contains('skills get'))));
    });

    test('--no-skills suppresses it without probing at all', () async {
      final outcome = await SkillsDelegate(contextWith()).offer(
        project: projectWith(dependsOnSkills: true),
        requested: false,
        consentedPreviously: true,
        assumeYes: true,
      );

      expect(outcome, SkillsOutcome.skipped);
      expect(processes.invocations, isEmpty);
    });

    test('--yes runs a locally resolvable skills without asking', () async {
      skillsSucceeds('dart run skills get');

      final outcome = await SkillsDelegate(contextWith()).offer(
        project: projectWith(dependsOnSkills: true),
        requested: null,
        consentedPreviously: false,
        assumeYes: true,
      );

      expect(outcome, SkillsOutcome.ran);
      expect(processes.invocations, contains('dart run skills get'));
    });

    test('--yes never reaches pub.dev on its own', () async {
      // The remote form downloads and runs a package. `--yes` means "do not
      // ask me", not "fetch code I never mentioned"; only `--skills` does that.
      skillsSucceeds('dart run skills@ get');

      final outcome = await SkillsDelegate(contextWith()).offer(
        project: projectWith(),
        requested: null,
        consentedPreviously: true,
        assumeYes: true,
      );

      expect(outcome, SkillsOutcome.notFound);
      expect(processes.invocations, isNot(contains('dart run skills@ get')));
    });

    test('--skills unlocks the remote form', () async {
      skillsSucceeds('dart run skills@ get');

      final outcome = await SkillsDelegate(contextWith()).offer(
        project: projectWith(),
        requested: true,
        consentedPreviously: false,
        assumeYes: false,
      );

      expect(outcome, SkillsOutcome.ran);
      expect(processes.invocations, contains('dart run skills@ get'));
    });

    test('asks before running when a human is watching', () async {
      skillsSucceeds('dart run skills get');
      final dialogs = FakeDialogSupport(confirmations: <bool>[true]);

      final outcome = await SkillsDelegate(contextWith(dialogs: dialogs)).offer(
        project: projectWith(dependsOnSkills: true),
        requested: null,
        consentedPreviously: false,
        assumeYes: false,
      );

      expect(outcome, SkillsOutcome.ran);
      expect(dialogs.questions.single, contains('dart run skills get'));
    });

    test('a declined offer runs nothing', () async {
      skillsSucceeds('dart run skills get');

      final outcome = await SkillsDelegate(
        contextWith(dialogs: FakeDialogSupport(confirmations: <bool>[false])),
      ).offer(
        project: projectWith(dependsOnSkills: true),
        requested: null,
        consentedPreviously: false,
        assumeYes: false,
      );

      expect(outcome, SkillsOutcome.declined);
      expect(processes.invocations, isNot(contains('dart run skills get')));
    });

    test('prior consent skips the question', () async {
      skillsSucceeds('dart run skills get');
      final dialogs = FakeDialogSupport(confirmations: <bool>[false]);

      final outcome = await SkillsDelegate(contextWith(dialogs: dialogs)).offer(
        project: projectWith(dependsOnSkills: true),
        requested: null,
        consentedPreviously: true,
        assumeYes: false,
      );

      expect(outcome, SkillsOutcome.ran);
      expect(dialogs.questions, isEmpty);
    });

    test(
      'CI is not interactive even with a scripted dialog available',
      () async {
        skillsSucceeds('dart run skills get');
        final dialogs = FakeDialogSupport(confirmations: <bool>[false]);

        final outcome = await SkillsDelegate(
          contextWith(
            dialogs: dialogs,
            environment: const <String, String>{'CI': 'true'},
          ),
        ).offer(
          project: projectWith(dependsOnSkills: true),
          requested: null,
          consentedPreviously: false,
          assumeYes: false,
        );

        expect(dialogs.questions, isEmpty);
        expect(outcome, SkillsOutcome.ran);
      },
    );

    test('--dry-run reports the command instead of running it', () async {
      skillsSucceeds('dart run skills get');

      final outcome = await SkillsDelegate(contextWith(dryRun: true)).offer(
        project: projectWith(dependsOnSkills: true),
        requested: null,
        consentedPreviously: true,
        assumeYes: true,
      );

      expect(outcome, SkillsOutcome.dryRun);
      expect(processes.invocations, isNot(contains('dart run skills get')));
      expect(output.join('\n'), contains('would run `dart run skills get`'));
    });

    test('a non-zero exit warns and is not fatal', () async {
      processes.responses['dart run skills get'] = const ProcessOutcome(
        1,
        '',
        'no skills found',
      );

      final outcome = await SkillsDelegate(contextWith()).offer(
        project: projectWith(dependsOnSkills: true),
        requested: null,
        consentedPreviously: true,
        assumeYes: true,
      );

      expect(outcome, SkillsOutcome.failed);
      final report = output.join('\n');
      expect(report, contains('exited 1'));
      expect(report, contains('no skills found'));
      expect(report, contains('written regardless'));
    });

    test(
      'a process that cannot start says so rather than "exited -1"',
      () async {
        // `FakeProcessRunner` answers anything unmapped with `ProcessOutcome
        // .failed()`, which is how a missing executable arrives.
        final outcome = await SkillsDelegate(contextWith()).offer(
          project: projectWith(dependsOnSkills: true),
          requested: null,
          consentedPreviously: true,
          assumeYes: true,
        );

        expect(outcome, SkillsOutcome.failed);
        expect(output.join('\n'), contains('could not be started'));
      },
    );
  });
}

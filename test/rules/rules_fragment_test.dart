@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test(
    'every project gets the project-rules stanza, with or without rules on disk',
    () async {
      await d.dir('app', <d.Descriptor>[
        d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      ]).create();

      final result = await runCli(<String>['compose', '-C', d.path('app')]);

      expect(result.output, contains('=== project rules ==='));
      expect(result.output, contains('.ai/rules/index.md'));
      expect(result.output, contains('.ai/infer-conventions.md'));
    },
  );

  test('the stanza carries no unrendered directives', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
    ]).create();

    final result = await runCli(<String>['compose', '-C', d.path('app')]);

    expect(result.output, isNot(contains('boost:if')));
    expect(result.output, isNot(contains('{{')));
  });
}

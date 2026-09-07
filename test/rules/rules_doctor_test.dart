@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test('doctor reports the rules server and the rule count', () async {
    await d.dir('app', <d.Descriptor>[
      d.file(
        'pubspec.yaml',
        'name: app\nenvironment:\n  sdk: ^3.7.0\n'
            'dev_dependencies:\n  dart_boost: ^0.2.0\n',
      ),
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[
          d.file(
            'models.md',
            '---\npaths:\n  - lib/models/**\n---\n\n# Models\n\n## A\n\na\n',
          ),
        ]),
      ]),
    ]).create();

    final result = await runCli(<String>['doctor', '-C', d.path('app')]);

    expect(result.output, contains('Rules'));
    expect(result.output, contains('1 rule file'));
    expect(result.output, contains('dart run dart_boost:mcp'));
  });

  test(
    'doctor says why rules are not wired when dart_boost is absent',
    () async {
      await d.dir('app', <d.Descriptor>[
        d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      ]).create();

      final result = await runCli(<String>['doctor', '-C', d.path('app')]);

      expect(result.output, contains('not a dev dependency'));
    },
  );
}

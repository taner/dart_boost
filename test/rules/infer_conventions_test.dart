@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test('install writes the procedure into the project', () async {
    await d.dir('app', <d.Descriptor>[
      d.file(
        'pubspec.yaml',
        'name: app\nenvironment:\n  sdk: ^3.7.0\n'
            'dev_dependencies:\n  dart_boost: ^0.2.0\n',
      ),
    ]).create();

    await runCli(<String>[
      'install',
      '-C',
      d.path('app'),
      '--agents=claude_code',
      '--yes',
    ]);

    final content = await readFile(d.path('app/.ai/infer-conventions.md'));
    expect(content, contains('record_rule'));
    expect(content, contains('analysis_options.yaml'));
    expect(content, contains('state management'));
  });

  test('the procedure is not written when rules are disabled', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      d.file(
        'dart_boost.json',
        '{"version":2,"agents":["claude_code"],'
            '"features":{"guidelines":true,"mcp":true},'
            '"rules":{"enabled":false}}',
      ),
    ]).create();

    await runCli(<String>['update', '-C', d.path('app'), '--yes']);

    expect(await exists(d.path('app/.ai/infer-conventions.md')), isFalse);
  });
}

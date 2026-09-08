@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  Future<void> project({
    String pubspec = 'name: app\nenvironment:\n  sdk: ^3.7.0\n',
  }) => d.dir('app', <d.Descriptor>[d.file('pubspec.yaml', pubspec)]).create();

  test(
    'writes both MCP servers when dart_boost is already a dev dependency',
    () async {
      await project(
        pubspec:
            'name: app\nenvironment:\n  sdk: ^3.7.0\n'
            'dev_dependencies:\n  dart_boost: ^0.2.0\n',
      );

      final result = await runCli(<String>[
        'install',
        '-C',
        d.path('app'),
        '--agents=claude_code',
        '--yes',
      ]);

      expect(result.exitCode, 0);
      final config = await readJson(d.path('app/.mcp.json'));
      expect(
        (config['mcpServers']! as Map).keys,
        containsAll(<String>['dart', 'dart_boost']),
      );
      expect(
        ((config['mcpServers']! as Map)['dart_boost']! as Map)['args'],
        <String>['run', 'dart_boost:mcp'],
      );
    },
  );

  test(
    'skips rules wiring unattended rather than editing pubspec.yaml',
    () async {
      await project();
      final before = await readFile(d.path('app/pubspec.yaml'));

      final result = await runCli(<String>[
        'install',
        '-C',
        d.path('app'),
        '--agents=claude_code',
        '--yes',
      ]);

      expect(result.exitCode, 0);
      expect(await readFile(d.path('app/pubspec.yaml')), before);

      final config = await readJson(d.path('app/.mcp.json'));
      expect((config['mcpServers']! as Map).keys, <String>['dart']);
      expect(result.output, contains('rules'));
      expect(result.output, contains('dev dependency'));
    },
  );

  test('writes no rules server when rules are disabled', () async {
    await project(
      pubspec:
          'name: app\nenvironment:\n  sdk: ^3.7.0\n'
          'dev_dependencies:\n  dart_boost: ^0.2.0\n',
    );
    await d.dir('app', <d.Descriptor>[
      d.file(
        'dart_boost.json',
        '{"version":2,"agents":["claude_code"],'
            '"features":{"guidelines":true,"mcp":true},'
            '"rules":{"enabled":false}}',
      ),
    ]).create();

    await runCli(<String>['update', '-C', d.path('app'), '--yes']);

    final config = await readJson(d.path('app/.mcp.json'));
    expect((config['mcpServers']! as Map).keys, <String>['dart']);
  });

  test('re-running reports already up to date', () async {
    await project(
      pubspec:
          'name: app\nenvironment:\n  sdk: ^3.7.0\n'
          'dev_dependencies:\n  dart_boost: ^0.2.0\n',
    );
    await runCli(<String>[
      'install',
      '-C',
      d.path('app'),
      '--agents=claude_code',
      '--yes',
    ]);
    final second = await runCli(<String>[
      'install',
      '-C',
      d.path('app'),
      '--agents=claude_code',
      '--yes',
    ]);

    expect(second.output, contains('already up to date'));

    // The rules row is idempotent on this run too -- it must report that
    // with the same "nothing changed" marker every other unchanged row uses,
    // not the one that means something was written.
    final rulesLine = second.output
        .split('\n')
        .firstWhere((line) => line.contains('dart_boost (rules)'));
    expect(rulesLine, contains('already a dev dependency'));
    expect(rulesLine, isNot(contains('+')));
  });
}

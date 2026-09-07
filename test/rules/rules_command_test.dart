@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../support/cli_harness.dart';

void main() {
  test('rules index rebuilds the index from a hand-added rule file', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[
          d.file(
            'models.md',
            '---\npaths:\n  - lib/models/**\n---\n\n# Models\n\n## A\n\na\n',
          ),
        ]),
      ]),
    ]).create();

    final result = await runCli(<String>[
      'rules',
      'index',
      '-C',
      d.path('app'),
    ]);

    expect(result.exitCode, 0);
    await d.dir('app', <d.Descriptor>[
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[
          d.file(
            'index.md',
            contains('| `lib/models/**` | `.ai/rules/models.md` |'),
          ),
        ]),
      ]),
    ]).validate();
  });

  test('rules index reports a malformed file without failing', () async {
    await d.dir('app', <d.Descriptor>[
      d.file('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.7.0\n'),
      d.dir('.ai', <d.Descriptor>[
        d.dir('rules', <d.Descriptor>[d.file('broken.md', 'nope\n')]),
      ]),
    ]).create();

    final result = await runCli(<String>[
      'rules',
      'index',
      '-C',
      d.path('app'),
    ]);

    expect(result.exitCode, 0);
    expect(result.output, contains('broken.md'));
  });
}

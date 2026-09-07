@TestOn('vm')
library;

import 'package:dart_boost/src/rules/rule_file.dart';
import 'package:test/test.dart';

void main() {
  group('RuleFile.parse', () {
    test('reads the paths list and keeps the body verbatim', () {
      const content = '''
---
paths:
  - lib/models/**
  - lib/entities/**
---

# Models

## Money is integer cents

Use `int` cents.
''';

      final file = RuleFile.parse('.ai/rules/models.md', content)!;

      expect(file.paths, <String>['lib/models/**', 'lib/entities/**']);
      expect(file.body, contains('## Money is integer cents'));
      expect(file.body, startsWith('# Models'));
    });

    test('returns null when there is no frontmatter', () {
      expect(RuleFile.parse('x.md', '# Just a heading\n'), isNull);
    });

    test('returns null when frontmatter has no paths key', () {
      expect(RuleFile.parse('x.md', '---\ntitle: nope\n---\n\nbody\n'), isNull);
    });

    test('returns null rather than throwing on malformed yaml', () {
      expect(
        RuleFile.parse('x.md', '---\npaths: [unclosed\n---\n\nbody\n'),
        isNull,
      );
    });

    test('round-trips CRLF content without corrupting it', () {
      const content =
          '---\r\npaths:\r\n  - test/**\r\n---\r\n\r\n# Testing\r\n';
      final file = RuleFile.parse('.ai/rules/test.md', content)!;

      expect(file.paths, <String>['test/**']);
      expect(file.body, '# Testing');
    });
  });

  group('renderRuleFile', () {
    test('emits frontmatter, heading and body', () {
      final out = renderRuleFile(
        paths: <String>['lib/models/**'],
        heading: 'Models',
        body: '## Money is integer cents\n\nUse `int` cents.',
      );

      expect(out, '''
---
paths:
  - lib/models/**
---

# Models

## Money is integer cents

Use `int` cents.
''');
    });

    test('parse and render round-trip', () {
      final rendered = renderRuleFile(
        paths: <String>['test/**'],
        heading: 'Test',
        body: '## Always use group()\n\nGroup related tests.',
      );

      final parsed = RuleFile.parse('.ai/rules/test.md', rendered)!;

      expect(parsed.paths, <String>['test/**']);
      expect(
        renderRuleFile(
          paths: parsed.paths,
          heading: 'Test',
          body: parsed.body.split('\n').skip(2).join('\n').trim(),
        ),
        rendered,
      );
    });
  });

  group('RuleFile.heading and bodyWithoutHeading getters', () {
    test(
      'expose heading and bodyWithoutHeading from a body with a # heading',
      () {
        const content = '''
---
paths:
  - lib/**
---

# My Heading

## Subheading

Body text.
''';

        final file = RuleFile.parse('.ai/rules/test.md', content)!;
        expect(file.heading, 'My Heading');
        expect(file.bodyWithoutHeading, '## Subheading\n\nBody text.');
      },
    );

    test(
      'expose heading and bodyWithoutHeading from a body without a # heading',
      () {
        const content = '''
---
paths:
  - lib/**
---

Just body text without a heading.
''';

        final file = RuleFile.parse('.ai/rules/test.md', content)!;
        expect(file.heading, '');
        expect(file.bodyWithoutHeading, 'Just body text without a heading.');
      },
    );
  });
}

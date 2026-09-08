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
      final content = '''
---
paths:
  - test/**
---

# Testing

## A rule

Some note.
'''.replaceAll('\n', '\r\n');
      final file = RuleFile.parse('.ai/rules/test.md', content)!;

      expect(file.paths, <String>['test/**']);
      expect(file.body, contains('# Testing'));

      // The point of this test: rendering back out must restore CRLF, not
      // just parse it away. A plain `parse` assertion cannot catch a writer
      // that silently downgrades the file to LF.
      expect(file.render(), content);
    });

    test('handles closing delimiter with 4 dashes', () {
      const content = '''
---
paths:
  - lib/**
----

# Body Heading

Some content.
''';

      final file = RuleFile.parse('.ai/rules/test.md', content)!;

      expect(file.paths, <String>['lib/**']);
      expect(file.body, '# Body Heading\n\nSome content.');
    });

    test('preserves horizontal rule (---) inside body', () {
      const content = '''
---
paths:
  - lib/**
---

intro

---

more
''';

      final file = RuleFile.parse('.ai/rules/test.md', content)!;

      expect(file.paths, <String>['lib/**']);
      expect(file.body, 'intro\n\n---\n\nmore');
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

  group('RuleFile.render()', () {
    test('parse then render produces byte-for-byte identical output', () {
      final original = '''
---
paths:
  - lib/models/**
  - lib/entities/**
---

# Models

## Money is integer cents

Use `int` cents.
''';

      final parsed = RuleFile.parse('.ai/rules/models.md', original)!;
      final rendered = parsed.render();

      expect(rendered, original);
    });
  });
}

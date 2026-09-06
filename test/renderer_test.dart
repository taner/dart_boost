import 'package:dart_boost/src/guidelines/renderer.dart';
import 'package:test/test.dart';

void main() {
  const renderer = GuidelineRenderer();

  RenderResult render(
    String source, {
    Set<String> flags = const <String>{},
    Map<String, String> variables = const <String, String>{},
    bool Function(String)? isKnownFlag,
  }) => renderer.render(
    source,
    flags: flags,
    variables: variables,
    isKnownFlag: isKnownFlag,
  );

  group('conditionals', () {
    test('emits the taken branch and drops the other', () {
      final result = render(
        '<!--boost:if usesRiverpod3-->\nthree\n<!--boost:else-->\ntwo\n<!--boost:end-->',
        flags: {'usesRiverpod3'},
      );
      expect(result.content, 'three');
      expect(result.isClean, isTrue);
    });

    test('takes the else branch when the flag is false', () {
      final result = render(
        '<!--boost:if usesRiverpod3-->\nthree\n<!--boost:else-->\ntwo\n<!--boost:end-->',
        flags: {'usesRiverpod2'},
      );
      expect(result.content, 'two');
    });

    test('nests without special handling', () {
      final source = [
        '<!--boost:if isFlutterProject-->',
        'flutter',
        '<!--boost:if usesFvm-->',
        'fvm',
        '<!--boost:else-->',
        'no fvm',
        '<!--boost:end-->',
        '<!--boost:end-->',
      ].join('\n');

      expect(
        render(source, flags: {'isFlutterProject'}).content,
        'flutter\nno fvm',
      );
      expect(
        render(source, flags: {'isFlutterProject', 'usesFvm'}).content,
        'flutter\nfvm',
      );
      expect(render(source, flags: {'usesFvm'}).content, isEmpty);
    });

    test('tolerates whitespace inside the comment', () {
      final result = render(
        '<!-- boost:if usesFoo -->\nx\n<!-- boost:end -->',
        flags: {'usesFoo'},
      );
      expect(result.content, 'x');
    });
  });

  group('degradation', () {
    test('an unknown flag is false and reported, never thrown', () {
      final result = render('<!--boost:if riverpod3-->\nx\n<!--boost:end-->');
      expect(result.content, isEmpty);
      expect(result.unknownFlags, {'riverpod3'});
    });

    test('a flag-shaped name that is simply false is not reported', () {
      final result = render(
        '<!--boost:if usesRiverpod9-->\nx\n<!--boost:end-->',
      );
      expect(result.content, isEmpty);
      expect(result.unknownFlags, isEmpty);
    });

    test('an unknown variable is left literal and reported', () {
      final result = render('Run {{ nope }} now');
      expect(result.content, 'Run {{ nope }} now');
      expect(result.unknownVars, {'nope'});
    });

    test('unbalanced directives are reported, not thrown', () {
      final result = render('<!--boost:if usesFoo-->\nx');
      expect(result.errors, isNotEmpty);
      final stray = render('<!--boost:end-->\nx');
      expect(stray.errors, isNotEmpty);
      expect(stray.content, 'x');
    });

    test('an injected vocabulary decides what counts as unknown', () {
      final result = render(
        '<!--boost:if somethingOdd-->\nx\n<!--boost:end-->',
        isKnownFlag: (name) => name == 'somethingOdd',
      );
      expect(result.unknownFlags, isEmpty);
    });
  });

  group('variables', () {
    test('substitutes with and without inner spaces', () {
      final result = render(
        '{{cmd}} and {{ cmd }}',
        variables: {'cmd': 'fvm dart run'},
      );
      expect(result.content, 'fvm dart run and fvm dart run');
    });
  });

  group('fenced code blocks', () {
    test('nothing inside a fence is touched', () {
      final source = [
        '```dart',
        '// {{ notAVariable }}',
        '<!--boost:if usesFoo-->',
        'const x = 1;',
        '<!--boost:end-->',
        '```',
      ].join('\n');

      final result = render(source);
      expect(result.content, source);
      expect(result.isClean, isTrue);
    });

    test('a longer fence is not closed by a shorter one', () {
      final source = [
        '````markdown',
        '```',
        '{{ x }}',
        '```',
        '````',
        '{{ x }}',
      ].join('\n');

      final result = render(source, variables: {'x': 'Y'});
      expect(
        result.content,
        ['````markdown', '```', '{{ x }}', '```', '````', 'Y'].join('\n'),
      );
    });

    test('a dropped branch takes its fence with it', () {
      final source = [
        '<!--boost:if usesFoo-->',
        '```',
        'dropped',
        '```',
        '<!--boost:end-->',
        'kept',
      ].join('\n');
      expect(render(source).content, 'kept');
    });
  });

  test('round-trips a trailing newline', () {
    expect(render('a\n').content, 'a\n');
    expect(render('a').content, 'a');
  });

  test('normalizes CRLF input', () {
    expect(render('a\r\nb').content, 'a\nb');
  });
}

@TestOn('vm')
library;

import 'package:dart_boost/src/rules/rule_area.dart';
import 'package:test/test.dart';

void main() {
  group('meaningfulSegments', () {
    test('drops wildcard and dotted segments', () {
      expect(meaningfulSegments('lib/models/**'), <String>['lib', 'models']);
      expect(meaningfulSegments('test/**/*_test.dart'), <String>['test']);
      expect(meaningfulSegments('lib/models/*.dart'), <String>[
        'lib',
        'models',
      ]);
      expect(meaningfulSegments('**'), isEmpty);
    });
  });

  group('areaKey', () {
    test('two globs over the same directory share an area', () {
      expect(areaKey('lib/models/**'), areaKey('lib/models/*.dart'));
    });

    test('different directories do not share an area', () {
      expect(areaKey('lib/models/**'), isNot(areaKey('lib/widgets/**')));
    });
  });

  group('filenameCandidates', () {
    test('offers the shortest slug first, then widens', () {
      expect(filenameCandidates('lib/src/widgets/**'), <String>[
        'widgets',
        'src-widgets',
        'lib-src-widgets',
      ]);
    });

    test('falls back to general when nothing is meaningful', () {
      expect(filenameCandidates('**'), <String>['general']);
    });

    test('slugs are lowercase and hyphenated', () {
      expect(filenameCandidates('lib/DataSources/**').first, 'datasources');
    });

    test('falls back to general when all slugs are empty', () {
      expect(filenameCandidates('___/**'), <String>['general']);
    });
  });

  group('normalizeGlob', () {
    test('makes an absolute path relative to the project root', () {
      expect(
        normalizeGlob(
          '/home/me/app/lib/models/**',
          projectRoot: '/home/me/app',
        ),
        'lib/models/**',
      );
    });

    test('converts backslashes', () {
      expect(
        normalizeGlob(r'lib\models\**', projectRoot: '/app'),
        'lib/models/**',
      );
    });

    test('rejects absolute paths outside the project root', () {
      expect(normalizeGlob('/lib/models/**', projectRoot: '/app'), isNull);
      expect(normalizeGlob('/etc/passwd', projectRoot: '/app'), isNull);
      expect(normalizeGlob('/application/x', projectRoot: '/app'), isNull);
      expect(normalizeGlob('/appdata/x', projectRoot: '/app'), isNull);
    });

    test('rejects a glob that escapes the project root', () {
      expect(normalizeGlob('../other/**', projectRoot: '/app'), isNull);
      expect(normalizeGlob('lib/../../escape/**', projectRoot: '/app'), isNull);
    });

    test('rejects an empty glob', () {
      expect(normalizeGlob('   ', projectRoot: '/app'), isNull);
    });

    test('accepts absolute paths under the project root', () {
      expect(normalizeGlob('/app/lib/x', projectRoot: '/app'), 'lib/x');
    });

    test('rejects Windows drive-absolute paths', () {
      expect(
        normalizeGlob(r'C:\Users\x\lib\file', projectRoot: '/app'),
        isNull,
      );
    });

    test('rejects UNC paths', () {
      expect(
        normalizeGlob(r'\\server\share\file', projectRoot: '/app'),
        isNull,
      );
    });

    test('normalizes .. in paths', () {
      expect(
        normalizeGlob('lib/models/../services/**', projectRoot: '/app'),
        'lib/services/**',
      );
    });

    test('normalizes doubled slashes', () {
      expect(
        normalizeGlob('lib//models/**', projectRoot: '/app'),
        'lib/models/**',
      );
    });
  });
}

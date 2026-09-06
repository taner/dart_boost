import 'dart:io';

import 'package:dart_boost/src/writers/toml_splicer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toml/toml.dart';

const _servers = <String, Map<String, Object?>>{
  'dart': <String, Object?>{
    'command': 'dart',
    'args': <String>['mcp-server'],
  },
};

void main() {
  const splicer = TomlConfigSplicer(configKey: 'mcp_servers');
  final fixtures = Directory(p.join('test', 'fixtures', 'toml'));
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';

  final inputs =
      fixtures
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.input.toml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final input in inputs) {
    final name = p.basename(input.path).replaceAll('.input.toml', '');
    final original = input.readAsStringSync();
    final result = splicer.splice(original, _servers);

    group(name, () {
      test('matches its golden', () {
        expect(result.error, isNull);
        final expected = File(p.join(fixtures.path, '$name.expected.toml'));
        if (update) expected.writeAsStringSync(result.content!);
        expect(
          expected.existsSync(),
          isTrue,
          reason: 'missing golden; re-run with UPDATE_GOLDENS=1',
        );
        expect(result.content, expected.readAsStringSync());
      });

      test('re-parses', () {
        expect(TomlConfigSplicer.validate(result.content!), isNull);
      });

      test('declares our server exactly once', () {
        final document = _toml(result.content!);
        final servers = document['mcp_servers']! as Map<String, dynamic>;
        expect(servers['dart'], <String, Object?>{
          'command': 'dart',
          'args': <String>['mcp-server'],
        });
        expect(
          RegExp(
            r'^\[mcp_servers\.dart\]$',
            multiLine: true,
          ).allMatches(_lf(result.content!)).length,
          1,
        );
      });

      test('keeps every other key', () {
        if (original.trim().isEmpty) return;
        final before = _toml(original);
        final after = _toml(result.content!);
        for (final key in before.keys) {
          if (key == 'mcp_servers') continue;
          expect(after[key], before[key]);
        }
        final beforeServers = before['mcp_servers'];
        if (beforeServers is! Map) return;
        final afterServers = after['mcp_servers']! as Map<String, dynamic>;
        for (final key in beforeServers.keys) {
          if (key == 'dart') continue;
          expect(afterServers[key], beforeServers[key]);
        }
      });

      test('keeps comments', () {
        for (final match in RegExp(
          '^#.*',
          multiLine: true,
        ).allMatches(original)) {
          expect(_lf(result.content!), contains(match.group(0)!.trim()));
        }
      });

      test('preserves line endings', () {
        expect(result.content!.contains('\r\n'), original.contains('\r\n'));
      });

      test('is idempotent', () {
        final second = splicer.splice(result.content!, _servers);
        expect(second.error, isNull);
        expect(second.changed, isFalse);
      });
    });
  }

  group('table semantics', () {
    // A `[table.header]` always opens a fresh scope, so appending at
    // end-of-file is always correct. Only removal needs span logic.
    test('appends at end of file, after any existing table', () {
      final output = splicer.splice('[a]\nx = 1\n', _servers).content!;
      expect(
        output.indexOf('[mcp_servers.dart]'),
        greaterThan(output.indexOf('[a]')),
      );
      expect(_toml(output)['a'], <String, Object?>{'x': 1});
    });

    test('replaces a previous run rather than appending a second table', () {
      final once = splicer.splice('', _servers).content!;
      final twice =
          splicer.splice(once, <String, Map<String, Object?>>{
            'dart': <String, Object?>{
              'command': '/pinned/bin/dart',
              'args': <String>['mcp-server'],
            },
          }).content!;

      expect(
        RegExp(
          r'^\[mcp_servers\.dart\]$',
          multiLine: true,
        ).allMatches(twice).length,
        1,
      );
      expect(twice, contains('/pinned/bin/dart'));
      expect(twice, isNot(contains('"dart"\n')));
    });

    test('removes the sub-table for env along with the main table', () {
      final withEnv =
          splicer.splice('', <String, Map<String, Object?>>{
            'dart': <String, Object?>{
              'command': 'dart',
              'args': <String>['mcp-server'],
              'env': <String, String>{'DART_BOOST': '1'},
            },
          }).content!;
      expect(withEnv, contains('[mcp_servers.dart.env]'));

      final withoutEnv = splicer.splice(withEnv, _servers).content!;
      expect(withoutEnv, isNot(contains('[mcp_servers.dart.env]')));
      expect(TomlConfigSplicer.validate(withoutEnv), isNull);
    });

    test('does not disturb a table whose name merely starts the same', () {
      final output =
          splicer
              .splice('[mcp_servers.dartlings]\ncommand = "x"\n', _servers)
              .content!;
      expect(output, contains('[mcp_servers.dartlings]'));
      expect(_toml(output)['mcp_servers'], containsPair('dartlings', anything));
    });
  });

  group('value formatting', () {
    test('escapes strings', () {
      expect(TomlConfigSplicer.formatValue(r'C:\dev\dart'), r'"C:\\dev\\dart"');
      expect(TomlConfigSplicer.formatValue('say "hi"'), r'"say \"hi\""');
    });

    test('renders lists, bools and numbers', () {
      expect(TomlConfigSplicer.formatValue(<String>['a', 'b']), '["a", "b"]');
      expect(TomlConfigSplicer.formatValue(true), 'true');
      expect(TomlConfigSplicer.formatValue(3), '3');
    });
  });

  test('aborts rather than writing when the result would not parse', () {
    // An unterminated string in the user's file makes any output invalid.
    final result = splicer.splice('broken = "unterminated\n', _servers);
    expect(result.ok, isFalse);
    expect(result.content, isNull);
  });
}

String _lf(String value) => value.replaceAll('\r\n', '\n');

Map<String, dynamic> _toml(String source) => TomlDocument.parse(source).toMap();

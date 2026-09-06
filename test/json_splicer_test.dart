import 'dart:convert';
import 'dart:io';

import 'package:dart_boost/src/writers/json_scanner.dart';
import 'package:dart_boost/src/writers/json_splicer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The server entry every fixture splices in.
const _entry = <String, Object?>{
  'dart': <String, Object?>{
    'command': 'dart',
    'args': <String>['mcp-server'],
  },
};

void main() {
  const splicer = JsonConfigSplicer(configKey: 'mcpServers');
  final fixtures = Directory(p.join('test', 'fixtures', 'mcp'));

  group('golden fixtures', () {
    final inputs =
        fixtures
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.input.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    // Run once with UPDATE_GOLDENS=1 to (re)generate the expected files, then
    // read every diff before committing them.
    final update = Platform.environment['UPDATE_GOLDENS'] == '1';

    for (final input in inputs) {
      final name = p.basename(input.path).replaceAll('.input.json', '');

      test(name, () {
        final original = input.readAsStringSync();
        final result = splicer.splice(original, _entry);

        expect(result.error, isNull, reason: 'splice must not abort');
        final output = result.content!;

        final expected = File(p.join(fixtures.path, '$name.expected.json'));
        if (update) {
          expected.writeAsStringSync(output);
        }
        expect(
          expected.existsSync(),
          isTrue,
          reason: 'missing golden; re-run with UPDATE_GOLDENS=1',
        );
        expect(output, expected.readAsStringSync());
      });
    }
  });

  group('properties that must hold for every fixture', () {
    final inputs =
        fixtures
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.input.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final input in inputs) {
      final name = p.basename(input.path).replaceAll('.input.json', '');
      final original = input.readAsStringSync();
      final output = splicer.splice(original, _entry).content!;

      test('$name: output re-parses', () {
        expect(JsonConfigSplicer.validate(output), isNull);
      });

      test('$name: our server is present exactly once', () {
        final decoded = _decode(output);
        final servers = decoded['mcpServers']! as Map<String, Object?>;
        expect(servers['dart'], _entry['dart']);
        // A duplicated key would be silently collapsed by jsonDecode, so count
        // the structural members too.
        final mask = JsonMask(_toLf(output));
        final config = mask
            .members(mask.findRootObject())
            .firstWhere((m) => m.name == 'mcpServers');
        final names =
            mask.members(config.valueStart).map((m) => m.name).toList();
        expect(names.where((n) => n == 'dart').length, 1);
      });

      test('$name: every original non-MCP key survives unchanged', () {
        if (original.trim().length < 3) return;
        final before = _decode(original);
        final after = _decode(output);
        for (final key in before.keys) {
          if (key == 'mcpServers') continue;
          expect(after[key], before[key], reason: 'key `$key` changed');
        }
      });

      test('$name: other servers survive unchanged', () {
        if (original.trim().length < 3) return;
        final before = _decode(original)['mcpServers'];
        if (before is! Map) return;
        final after = _decode(output)['mcpServers']! as Map<String, Object?>;
        for (final key in before.keys) {
          if (key == 'dart') continue;
          expect(after[key], before[key], reason: 'server `$key` changed');
        }
      });

      test('$name: comments survive', () {
        for (final comment in _commentsIn(original)) {
          expect(output, contains(comment));
        }
      });

      test('$name: line endings are preserved', () {
        expect(output.contains('\r\n'), original.contains('\r\n'));
      });

      test('$name: splicing twice changes nothing the second time', () {
        final second = splicer.splice(output, _entry);
        expect(second.error, isNull);
        expect(second.changed, isFalse, reason: 'install must be idempotent');
      });
    }
  });

  group('replace rather than duplicate', () {
    test('an existing entry with different args is overwritten', () {
      final original =
          File(
            p.join(fixtures.path, 'different_args.input.json'),
          ).readAsStringSync();
      final output = splicer.splice(original, _entry).content!;
      final servers = _decode(output)['mcpServers']! as Map<String, Object?>;

      expect(servers['dart'], _entry['dart']);
      expect(output, isNot(contains('/opt/old-sdk/bin/dart')));
      expect(output, isNot(contains('LEGACY')));
    });

    test('an identical entry is a no-op', () {
      final original =
          File(
            p.join(fixtures.path, 'already_present.input.json'),
          ).readAsStringSync();
      expect(splicer.splice(original, _entry).changed, isFalse);
    });
  });

  group('other config keys', () {
    test('writes VS Code\'s `servers` key', () {
      const copilot = JsonConfigSplicer(configKey: 'servers');
      final output =
          copilot.splice('{}\n', <String, Object?>{
            'dart': <String, Object?>{'type': 'stdio', 'command': 'dart'},
          }).content!;
      expect(_decode(output).keys, contains('servers'));
    });

    test(
      'writes Zed\'s `context_servers` key into an existing settings file',
      () {
        const zed = JsonConfigSplicer(configKey: 'context_servers');
        final output =
            zed.splice('{\n  "theme": "One Dark"\n}\n', <String, Object?>{
              'dart': <String, Object?>{'source': 'custom', 'command': 'dart'},
            }).content!;
        final decoded = _decode(output);
        expect(decoded['theme'], 'One Dark');
        expect(decoded['context_servers'], isA<Map<String, Object?>>());
      },
    );
  });

  group('refusal', () {
    test('aborts rather than writing when there is no object', () {
      final result = splicer.splice('not json at all\n', _entry);
      expect(result.ok, isFalse);
      expect(result.content, isNull);
    });

    test('aborts when the config key is not an object', () {
      final result = splicer.splice('{"mcpServers": 42}\n', _entry);
      expect(result.ok, isFalse);
    });

    test('accepts a file that was already non-strict JSON', () {
      // Unquoted key and single quotes: never valid JSON, but a real dialect
      // some editors write. Refusing would punish the user for it.
      const source = "{\n  mcpServers: {\n    fs: {command: 'npx'}\n  }\n}\n";
      final result = splicer.splice(source, _entry);
      expect(result.ok, isTrue);
      expect(result.content, contains('"dart"'));
      expect(result.content, contains("'npx'"));
    });
  });

  group('validate', () {
    test('accepts comments and trailing commas', () {
      expect(
        JsonConfigSplicer.validate('{\n // hi\n "a": [1,2,],\n}\n'),
        isNull,
      );
    });

    test('does not treat a comment inside a string as a comment', () {
      expect(JsonConfigSplicer.validate('{"a": "// not a comment"}'), isNull);
      expect(jsonDecode('{"a": "// not a comment"}'), {
        'a': '// not a comment',
      });
    });

    test('rejects unbalanced braces', () {
      expect(JsonConfigSplicer.validate('{"a": 1'), isNotNull);
    });
  });
}

String _toLf(String value) => value.replaceAll('\r\n', '\n');

Map<String, Object?> _decode(String source) =>
    jsonDecode(JsonConfigSplicer.toStrictJson(_toLf(source)))
        as Map<String, Object?>;

Iterable<String> _commentsIn(String source) sync* {
  for (final match in RegExp(r'//[^\n\r]*').allMatches(source)) {
    yield match.group(0)!.trimRight();
  }
  for (final match in RegExp(r'/\*[\s\S]*?\*/').allMatches(source)) {
    yield match.group(0)!;
  }
}

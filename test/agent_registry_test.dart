import 'package:dart_boost/src/agents/agent.dart';
import 'package:dart_boost/src/agents/agent_detector.dart';
import 'package:dart_boost/src/util/process_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  const spec = McpServerSpec(command: 'dart');

  group('registry', () {
    test('every key is unique and stable', () {
      final keys = AgentRegistry.all.map((a) => a.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(AgentRegistry.byKey('claude_code'), isA<ClaudeCode>());
      expect(AgentRegistry.byKey('nope'), isNull);
    });

    test('covers the nine-agent matrix', () {
      expect(AgentRegistry.all, hasLength(9));
    });

    test('several agents share AGENTS.md', () {
      final sharing =
          AgentRegistry.all
              .where((a) => a.guidelinesFile == 'AGENTS.md')
              .map((a) => a.key)
              .toList();
      expect(sharing.length, greaterThan(2));
    });

    test('agents that need a different config key say so', () {
      expect(const GithubCopilot().mcpConfigKey, 'servers');
      expect(const Codex().mcpConfigKey, 'mcp_servers');
      expect(const Zed().mcpConfigKey, 'context_servers');
      expect(const OpenCode().mcpConfigKey, 'mcp');
      expect(const ClaudeCode().mcpConfigKey, 'mcpServers');
    });

    test('agents that need a different entry shape override it', () {
      expect(const ClaudeCode().mcpEntry(spec), {
        'command': 'dart',
        'args': ['mcp-server'],
      });
      expect(
        const GithubCopilot().mcpEntry(spec),
        containsPair('type', 'stdio'),
      );
      expect(const Zed().mcpEntry(spec), containsPair('source', 'custom'));
      // OpenCode takes a single argv list, not command-plus-args.
      expect(const OpenCode().mcpEntry(spec), {
        'type': 'local',
        'command': ['dart', 'mcp-server'],
        'enabled': true,
      });
    });

    test('OpenCode uses whichever config file already exists', () {
      final fs = memoryFs();
      final root = fs.directory(p.join(fs.currentDirectory.path, 'app'))
        ..createSync(recursive: true);
      const agent = OpenCode();

      expect(agent.resolveMcpConfigFile(root, fs), 'opencode.json');

      fs.file(p.join(root.path, 'opencode.jsonc')).writeAsStringSync('{}');
      expect(agent.resolveMcpConfigFile(root, fs), 'opencode.jsonc');
    });
  });

  group('detection', () {
    late FileSystem fs;
    late Directory project;

    setUp(() {
      fs = memoryFs();
      project = fs.directory(p.join(fs.currentDirectory.path, 'app'))
        ..createSync(recursive: true);
    });

    AgentDetector detector(ProcessRunner runner, {String? home}) =>
        AgentDetector(
          fileSystem: fs,
          processRunner: runner,
          isWindows: false,
          homeDirectory: home,
        );

    test('a project directory is enough', () {
      fs.directory(p.join(project.path, '.cursor')).createSync();

      final found = detector(FakeProcessRunner()).detect(project);

      expect(found.map((d) => d.agent.key), contains('cursor'));
      expect(
        found.firstWhere((d) => d.agent.key == 'cursor').reason,
        'project directory: .cursor',
      );
    });

    test('a project file is enough', () {
      fs.file(p.join(project.path, 'opencode.json')).writeAsStringSync('{}');
      expect(
        detector(FakeProcessRunner()).detect(project).map((d) => d.agent.key),
        contains('opencode'),
      );
    });

    test('a command on PATH is enough', () {
      // `command -v` is a shell builtin, so it has to go through the shell.
      final runner = FakeProcessRunner({
        'sh -c command -v gemini': const ProcessOutcome(
          0,
          '/usr/bin/gemini',
          '',
        ),
      });

      expect(
        detector(runner).detect(project).map((d) => d.agent.key),
        contains('gemini'),
      );
    });

    test('command probes are cached rather than re-spawned', () {
      final runner = FakeProcessRunner();
      final probe = detector(runner);

      probe.detect(project);
      final first = runner.invocations.length;
      probe.detect(project);

      expect(runner.invocations.length, first);
      expect(first, greaterThan(0));
    });

    test('a system path is enough, with ~ expanded', () {
      final home = p.join(fs.currentDirectory.path, 'home');
      fs.directory(p.join(home, '.codex')).createSync(recursive: true);

      expect(
        detector(
          FakeProcessRunner(),
          home: home,
        ).detect(project).map((d) => d.agent.key),
        contains('codex'),
      );
    });

    test('nothing installed means nothing detected', () {
      expect(detector(FakeProcessRunner()).detect(project), isEmpty);
    });

    test('a %VAR% path that is not set is skipped rather than guessed', () {
      final windows = AgentDetector(
        fileSystem: fs,
        processRunner: FakeProcessRunner(),
        isWindows: true,
        environment: const <String, String>{},
      );
      expect(windows.expand(r'%LOCALAPPDATA%\Programs\cursor'), isNull);
    });
  });
}

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../util/process_runner.dart';
import 'agent.dart';

/// An agent that looks installed, and what gave it away.
class DetectedAgent {
  const DetectedAgent(this.agent, this.reason);

  final Agent agent;

  /// `command: claude`, `project directory: .cursor`, ...
  final String reason;
}

/// Declarative detection over commands, system paths, project directories and
/// project files, OR'd together.
///
/// Command probes are cached: spawning nine processes twice is visibly slow,
/// and `install` asks exactly the questions `doctor` just asked.
class AgentDetector {
  AgentDetector({
    required this.fileSystem,
    required this.processRunner,
    required this.isWindows,
    this.homeDirectory,
    Map<String, String>? environment,
  }) : environment = environment ?? const <String, String>{};

  final FileSystem fileSystem;
  final ProcessRunner processRunner;
  final bool isWindows;
  final String? homeDirectory;
  final Map<String, String> environment;

  final Map<String, bool> _commandCache = <String, bool>{};

  /// Command names come from the const registry, but the value is
  /// interpolated into a shell string, so it is checked rather than trusted.
  static final _safeCommand = RegExp(r'^[A-Za-z0-9_.-]+$');

  List<DetectedAgent> detect(
    Directory projectRoot, {
    Iterable<Agent> agents = AgentRegistry.all,
  }) {
    final found = <DetectedAgent>[];
    for (final agent in agents) {
      final reason = reasonFor(agent, projectRoot);
      if (reason != null) found.add(DetectedAgent(agent, reason));
    }
    return found;
  }

  String? reasonFor(Agent agent, Directory projectRoot) {
    final rules = agent.detection;

    for (final file in rules.projectFiles) {
      if (fileSystem
          .file(p.join(projectRoot.path, p.joinAll(file.split('/'))))
          .existsSync()) {
        return 'project file: $file';
      }
    }
    for (final dir in rules.projectPaths) {
      if (fileSystem
          .directory(p.join(projectRoot.path, p.joinAll(dir.split('/'))))
          .existsSync()) {
        return 'project directory: $dir';
      }
    }
    for (final command in rules.commands) {
      if (hasCommand(command)) return 'command: $command';
    }
    for (final path in rules.systemPaths) {
      final expanded = expand(path);
      if (expanded == null) continue;
      if (fileSystem.directory(expanded).existsSync() ||
          fileSystem.file(expanded).existsSync()) {
        return 'installed at: $path';
      }
    }
    return null;
  }

  bool hasCommand(String command) => _commandCache.putIfAbsent(command, () {
    if (!_safeCommand.hasMatch(command)) return false;
    if (isWindows) {
      return processRunner.run('where.exe', <String>[command]).succeeded;
    }
    // `command -v` is a shell builtin, not an executable, so it has to be
    // run through the shell; `which` is the fallback for shells that lack
    // it.
    final probe = processRunner.run('sh', <String>[
      '-c',
      'command -v $command',
    ]);
    if (probe.succeeded) return true;
    return processRunner.run('which', <String>[command]).succeeded;
  });

  /// Expands a leading `~` and a `%VAR%` reference, or returns `null` when the
  /// path names an environment that is not set here.
  String? expand(String path) {
    var result = path;
    if (result.startsWith('~')) {
      final home = homeDirectory;
      if (home == null) return null;
      final rest = result.substring(1).split('/').where((s) => s.isNotEmpty);
      result = rest.isEmpty ? home : p.join(home, p.joinAll(rest));
    }
    final variable = RegExp(r'%([A-Za-z_][A-Za-z0-9_]*)%').firstMatch(result);
    if (variable != null) {
      final value = environment[variable.group(1)!];
      if (value == null) return null;
      result = result.replaceRange(variable.start, variable.end, value);
    }
    return result;
  }
}

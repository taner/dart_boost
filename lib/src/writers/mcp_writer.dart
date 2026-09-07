import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../agents/agent.dart';
import '../project/project.dart';
import '../util/process_runner.dart';
import 'atomic_writer.dart';
import 'json_splicer.dart';
import 'toml_splicer.dart';

enum McpWriteOutcome {
  created('written'),
  updated('updated'),
  unchanged('already up to date'),
  failed('failed');

  const McpWriteOutcome(this.label);

  final String label;
}

class McpWriteReport {
  const McpWriteReport({
    required this.agent,
    required this.path,
    required this.outcome,
    this.message,
  });

  final Agent agent;
  final String path;
  final McpWriteOutcome outcome;
  final String? message;

  bool get ok => outcome != McpWriteOutcome.failed;
}

/// Decides which `dart` the MCP server should be launched with.
///
/// When the project is FVM-pinned, bare `dart` on PATH is the *wrong SDK* --
/// the agent would analyse the project against a different Dart than the one
/// it resolves against. The pinned absolute path is emitted instead. This
/// mirrors Boost's `useAbsolutePathForMcp()` and its Sail/WSL command
/// variants.
abstract final class McpCommandResolver {
  static McpServerSpec resolve({
    required Project project,
    required FileSystem fileSystem,
    required bool isWindows,
    void Function(String)? onWarning,
  }) {
    if (project.sdk.usesFvm) {
      final executable = isWindows ? 'dart.bat' : 'dart';
      for (final root in <String?>[
        p.join(project.analysisRoot.path, '.fvm', 'flutter_sdk'),
        project.sdk.flutterSdkRoot,
      ]) {
        if (root == null) continue;
        final candidate = p.join(root, 'bin', executable);
        if (fileSystem.file(candidate).existsSync()) {
          return McpServerSpec(command: candidate);
        }
      }
      onWarning?.call(
        'This project is FVM-pinned but the pinned SDK was not found on disk; '
        'falling back to `dart` on PATH, which may be a different SDK. '
        'Run `fvm install` and re-run dart_boost.',
      );
    }
    return const McpServerSpec(command: 'dart');
  }

  /// `dart mcp-server` is a hidden subcommand -- it works on 3.13.2 but does
  /// not appear in `dart help`, so its absence from help proves nothing.
  /// Probe it directly, and warn rather than fail: an older SDK is a reason to
  /// tell the user, not a reason to refuse to configure their agents.
  static bool probe(McpServerSpec spec, ProcessRunner runner) =>
      runner.run(spec.command, <String>[...spec.args, '--version']).succeeded;
}

/// Writes the MCP server entry into each agent's config.
///
/// Every write goes: splice -> re-parse -> temp file -> rename. If the spliced
/// output does not re-parse, that agent is skipped and reported, and its file
/// is left exactly as it was.
class McpWriter {
  const McpWriter({required this.fileSystem, this.dryRun = false});

  final FileSystem fileSystem;
  final bool dryRun;

  McpWriteReport write({
    required Agent agent,
    required Directory projectRoot,
    required List<McpServerSpec> specs,
  }) {
    final path = agent.mcpConfigPath(projectRoot, fileSystem);
    final file = fileSystem.file(path);
    final existing = file.existsSync() ? file.readAsStringSync() : '';

    // One splice per agent, from every spec at once: splicing twice would
    // both double the change reports and make "unchanged" detection see the
    // first splice's own output as the "existing" content for the second.
    final result = switch (agent.mcpFormat) {
      McpFormat.toml => TomlConfigSplicer(configKey: agent.mcpConfigKey).splice(
        existing,
        <String, Map<String, Object?>>{
          for (final spec in specs) spec.key: agent.mcpEntry(spec),
        },
      ),
      McpFormat.json || McpFormat.jsonc => JsonConfigSplicer(
        configKey: agent.mcpConfigKey,
      ).splice(existing, <String, Object?>{
        for (final spec in specs) spec.key: agent.mcpEntry(spec),
      }),
    };

    if (!result.ok) {
      return McpWriteReport(
        agent: agent,
        path: path,
        outcome: McpWriteOutcome.failed,
        message: result.error,
      );
    }

    if (!result.changed) {
      return McpWriteReport(
        agent: agent,
        path: path,
        outcome: McpWriteOutcome.unchanged,
      );
    }

    final existed = file.existsSync();
    AtomicWriter(fileSystem, dryRun: dryRun).write(path, result.content!);

    return McpWriteReport(
      agent: agent,
      path: path,
      outcome: existed ? McpWriteOutcome.updated : McpWriteOutcome.created,
    );
  }
}

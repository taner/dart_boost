import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// How an agent's MCP config file is encoded.
enum McpFormat { json, jsonc, toml }

/// The server we configure. There is deliberately only ever one: the official
/// `dart mcp-server` that ships in the Dart SDK. dart_boost does not implement
/// an MCP server of its own -- `dart mcp-server` already exposes ~24 tools
/// (`analyze_files`, `lsp`, `run_tests`, `hot_reload`, `widget_inspector`,
/// `get_runtime_errors`, ...) and connects to running apps through DTD.
class McpServerSpec {
  const McpServerSpec({
    this.key = 'dart',
    required this.command,
    this.args = const <String>['mcp-server'],
    this.env = const <String, String>{},
  });

  final String key;
  final String command;
  final List<String> args;
  final Map<String, String> env;
}

/// What makes an agent look installed. The clauses are OR'd.
class AgentDetection {
  const AgentDetection({
    this.commands = const <String>[],
    this.systemPaths = const <String>[],
    this.projectPaths = const <String>[],
    this.projectFiles = const <String>[],
  });

  /// Looked up with `command -v` on POSIX and `where.exe` on Windows.
  final List<String> commands;

  /// Absolute, or `~`-relative.
  final List<String> systemPaths;

  /// Directories relative to the project root.
  final List<String> projectPaths;

  /// Files relative to the project root.
  final List<String> projectFiles;
}

/// One AI coding agent dart_boost knows how to wire up.
///
/// `const` sealed subclasses rather than an enum, because several agents
/// override the server-entry shape and one resolves its config path at
/// runtime -- behaviour an enum cannot carry.
sealed class Agent {
  const Agent();

  /// Stable identifier, as persisted in `dart_boost.json`.
  String get key;

  String get name;

  /// Guidelines file, relative to the project root.
  String get guidelinesFile;

  /// MCP config file, relative to the project root.
  String get mcpConfigFile;

  /// The object inside the config that holds servers.
  String get mcpConfigKey;

  McpFormat get mcpFormat;

  AgentDetection get detection;

  /// Whether the guidelines file wants `alwaysApply` frontmatter.
  bool get frontmatter => false;

  /// The server entry as this agent expects it.
  Map<String, Object?> mcpEntry(McpServerSpec spec) => <String, Object?>{
    'command': spec.command,
    if (spec.args.isNotEmpty) 'args': spec.args,
    if (spec.env.isNotEmpty) 'env': spec.env,
  };

  /// Lets an agent whose config file has several accepted names pick the one
  /// already present.
  String resolveMcpConfigFile(Directory projectRoot, FileSystem fileSystem) =>
      mcpConfigFile;

  String guidelinesPath(Directory projectRoot) =>
      p.join(projectRoot.path, p.joinAll(guidelinesFile.split('/')));

  String mcpConfigPath(Directory projectRoot, FileSystem fileSystem) => p.join(
    projectRoot.path,
    p.joinAll(resolveMcpConfigFile(projectRoot, fileSystem).split('/')),
  );

  @override
  String toString() => key;
}

class ClaudeCode extends Agent {
  const ClaudeCode();

  @override
  String get key => 'claude_code';
  @override
  String get name => 'Claude Code';
  @override
  String get guidelinesFile => 'CLAUDE.md';
  @override
  String get mcpConfigFile => '.mcp.json';
  @override
  String get mcpConfigKey => 'mcpServers';
  @override
  McpFormat get mcpFormat => McpFormat.json;
  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['claude'],
    systemPaths: ['~/.claude'],
    projectPaths: ['.claude'],
    projectFiles: ['CLAUDE.md', '.mcp.json'],
  );
}

class Cursor extends Agent {
  const Cursor();

  @override
  String get key => 'cursor';
  @override
  String get name => 'Cursor';
  @override
  String get guidelinesFile => 'AGENTS.md';
  @override
  String get mcpConfigFile => '.cursor/mcp.json';
  @override
  String get mcpConfigKey => 'mcpServers';
  @override
  McpFormat get mcpFormat => McpFormat.json;
  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['cursor'],
    systemPaths: [
      '~/.cursor',
      '/Applications/Cursor.app',
      r'%LOCALAPPDATA%\Programs\cursor',
    ],
    projectPaths: ['.cursor'],
  );
}

class GithubCopilot extends Agent {
  const GithubCopilot();

  @override
  String get key => 'copilot';
  @override
  String get name => 'GitHub Copilot';
  @override
  String get guidelinesFile => 'AGENTS.md';
  @override
  String get mcpConfigFile => '.vscode/mcp.json';

  /// VS Code uses `servers`, not `mcpServers`.
  @override
  String get mcpConfigKey => 'servers';

  /// `.vscode/*.json` is JSONC by convention and usually has comments.
  @override
  McpFormat get mcpFormat => McpFormat.jsonc;

  @override
  Map<String, Object?> mcpEntry(McpServerSpec spec) => <String, Object?>{
    'type': 'stdio',
    'command': spec.command,
    if (spec.args.isNotEmpty) 'args': spec.args,
    if (spec.env.isNotEmpty) 'env': spec.env,
  };

  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['code', 'code-insiders'],
    systemPaths: ['~/.vscode', '~/.vscode-insiders'],
    projectPaths: ['.vscode', '.github'],
  );
}

class Codex extends Agent {
  const Codex();

  @override
  String get key => 'codex';
  @override
  String get name => 'Codex';
  @override
  String get guidelinesFile => 'AGENTS.md';
  @override
  String get mcpConfigFile => '.codex/config.toml';
  @override
  String get mcpConfigKey => 'mcp_servers';
  @override
  McpFormat get mcpFormat => McpFormat.toml;
  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['codex'],
    systemPaths: ['~/.codex'],
    projectPaths: ['.codex'],
  );
}

class Antigravity extends Agent {
  const Antigravity();

  @override
  String get key => 'antigravity';
  @override
  String get name => 'Antigravity';
  @override
  String get guidelinesFile => 'AGENTS.md';
  @override
  String get mcpConfigFile => '.agents/mcp_config.json';
  @override
  String get mcpConfigKey => 'mcpServers';
  @override
  McpFormat get mcpFormat => McpFormat.json;
  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['antigravity'],
    systemPaths: ['~/.antigravity', '/Applications/Antigravity.app'],
    projectPaths: ['.agents'],
  );
}

class GeminiCli extends Agent {
  const GeminiCli();

  @override
  String get key => 'gemini';
  @override
  String get name => 'Gemini CLI';
  @override
  String get guidelinesFile => 'GEMINI.md';
  @override
  String get mcpConfigFile => '.gemini/settings.json';
  @override
  String get mcpConfigKey => 'mcpServers';
  @override
  McpFormat get mcpFormat => McpFormat.json;
  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['gemini'],
    systemPaths: ['~/.gemini'],
    projectPaths: ['.gemini'],
  );
}

class Zed extends Agent {
  const Zed();

  @override
  String get key => 'zed';
  @override
  String get name => 'Zed';
  @override
  String get guidelinesFile => 'AGENTS.md';
  @override
  String get mcpConfigFile => '.zed/settings.json';

  /// Zed calls them context servers.
  @override
  String get mcpConfigKey => 'context_servers';
  @override
  McpFormat get mcpFormat => McpFormat.json;

  @override
  Map<String, Object?> mcpEntry(McpServerSpec spec) => <String, Object?>{
    'source': 'custom',
    'command': spec.command,
    if (spec.args.isNotEmpty) 'args': spec.args,
    'env': spec.env,
  };

  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['zed'],
    systemPaths: ['~/.config/zed', '/Applications/Zed.app'],
    projectPaths: ['.zed'],
  );
}

class OpenCode extends Agent {
  const OpenCode();

  @override
  String get key => 'opencode';
  @override
  String get name => 'OpenCode';
  @override
  String get guidelinesFile => 'AGENTS.md';
  @override
  String get mcpConfigFile => 'opencode.json';
  @override
  String get mcpConfigKey => 'mcp';
  @override
  McpFormat get mcpFormat => McpFormat.jsonc;

  /// OpenCode takes the command as a single argv list and wants an explicit
  /// transport and enabled flag.
  @override
  Map<String, Object?> mcpEntry(McpServerSpec spec) => <String, Object?>{
    'type': 'local',
    'command': <String>[spec.command, ...spec.args],
    'enabled': true,
    if (spec.env.isNotEmpty) 'environment': spec.env,
  };

  /// `opencode.json` and `opencode.jsonc` are both valid; never create the
  /// second file when the first already exists.
  @override
  String resolveMcpConfigFile(Directory projectRoot, FileSystem fileSystem) {
    for (final candidate in const ['opencode.json', 'opencode.jsonc']) {
      if (fileSystem.file(p.join(projectRoot.path, candidate)).existsSync()) {
        return candidate;
      }
    }
    return mcpConfigFile;
  }

  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['opencode'],
    systemPaths: ['~/.config/opencode', '~/.opencode'],
    projectFiles: ['opencode.json', 'opencode.jsonc'],
  );
}

class Windsurf extends Agent {
  const Windsurf();

  @override
  String get key => 'windsurf';
  @override
  String get name => 'Windsurf';
  @override
  String get guidelinesFile => 'AGENTS.md';
  @override
  String get mcpConfigFile => '.windsurf/mcp.json';
  @override
  String get mcpConfigKey => 'mcpServers';
  @override
  McpFormat get mcpFormat => McpFormat.json;
  @override
  AgentDetection get detection => const AgentDetection(
    commands: ['windsurf'],
    systemPaths: ['~/.codeium/windsurf', '/Applications/Windsurf.app'],
    projectPaths: ['.windsurf'],
  );
}

abstract final class AgentRegistry {
  static const all = <Agent>[
    ClaudeCode(),
    Cursor(),
    GithubCopilot(),
    Codex(),
    Antigravity(),
    GeminiCli(),
    Zed(),
    OpenCode(),
    Windsurf(),
  ];

  static Agent? byKey(String key) {
    for (final agent in all) {
      if (agent.key == key) return agent;
    }
    return null;
  }

  static List<String> get keys => all.map((a) => a.key).toList();
}

/// Version-aware AI coding guidelines and one-command multi-agent wiring for
/// Dart and Flutter projects.
///
/// dart_boost deliberately ships **no MCP server of its own**: the Dart SDK
/// already includes `dart mcp-server`, whose ~24 tools are strictly ahead of
/// what a hand-rolled one would offer. What is missing from the ecosystem, and
/// what this package provides, is (a) a single installer that detects your
/// agents and configures all of them, and (b) guidelines composed from *your*
/// resolved SDK and package versions.
library;

export 'src/agents/agent.dart';
export 'src/agents/agent_detector.dart';
export 'src/assets/bundled_assets.dart';
export 'src/cli/context.dart';
export 'src/cli/dialog_support.dart';
export 'src/cli/runner.dart';
export 'src/guidelines/composer.dart';
export 'src/guidelines/facts.dart';
export 'src/guidelines/markdown_formatter.dart';
export 'src/guidelines/renderer.dart';
export 'src/install/installer.dart';
export 'src/project/package_ref.dart';
export 'src/project/package_registry.dart';
export 'src/project/project.dart';
export 'src/project/sdk_versions.dart';
export 'src/project/workspace.dart';
export 'src/state/boost_state.dart';
export 'src/util/logger.dart';
export 'src/util/process_runner.dart';
export 'src/util/version_key.dart';
export 'src/version.dart';
export 'src/writers/atomic_writer.dart';
export 'src/writers/guidelines_writer.dart';
export 'src/writers/json_scanner.dart';
export 'src/writers/json_splicer.dart';
export 'src/writers/mcp_writer.dart';
export 'src/writers/toml_splicer.dart';

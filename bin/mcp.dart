import 'dart:io';

import 'package:dart_boost/src/mcp/rules_server.dart';
import 'package:dart_boost/src/rules/rule_repository.dart';
import 'package:dart_boost/src/state/boost_state.dart';
import 'package:file/local.dart';

/// `dart run dart_boost:mcp` -- stdio transport, project root is the cwd,
/// which is what every MCP client sets when it launches a server.
Future<void> main(List<String> args) async {
  const fileSystem = LocalFileSystem();
  final projectRoot = fileSystem.currentDirectory;
  final repository = RuleRepository(
    fileSystem: fileSystem,
    projectRoot: projectRoot,
  );

  final stateStore = BoostStateStore(fileSystem, projectRoot);
  final rulesEnabled = stateStore.read()?.state.rules.enabled ?? true;

  await serveRules(
    repository: repository,
    stdin: stdin,
    stdout: stdout,
    rulesEnabled: rulesEnabled,
  );
}

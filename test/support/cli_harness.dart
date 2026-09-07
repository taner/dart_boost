import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_boost/src/cli/dialog_support.dart';
import 'package:dart_boost/src/cli/runner.dart';
import 'package:dart_boost/src/util/logger.dart';
import 'package:dart_boost/src/util/process_runner.dart';

/// The outcome of a [runCli] invocation.
class CliResult {
  const CliResult(this.exitCode, this.output);

  final int exitCode;

  /// stdout and stderr, interleaved in write order, so a test can assert on
  /// a warning without caring which stream it landed on.
  final String output;
}

/// Enough of the process world for a command to run without actually
/// spawning `dart` -- mirrors the stub in `test/install_integration_test.dart`.
Map<String, ProcessOutcome> _defaultProcessResponses() =>
    <String, ProcessOutcome>{
      'dart mcp-server --version': const ProcessOutcome(
        0,
        'dart mcp-server 1.0',
        '',
      ),
    };

/// Runs the real `DartBoostRunner` on the on-disk sandbox that
/// `package:test_descriptor` builds, capturing everything it prints.
///
/// Deliberately *not* run on `MemoryFileSystem`: several commands shell out
/// (`dart`, `command -v`), which do not participate in that abstraction, so
/// only the process boundary is stubbed here -- pass [processResponses] to
/// override the default when a test needs a different answer. This mirrors
/// the private `run` helper in `test/install_integration_test.dart`; keep the
/// two in sync if either changes.
Future<CliResult> runCli(
  List<String> args, {
  Map<String, ProcessOutcome>? processResponses,
}) async {
  final output = <String>[];
  final runner = DartBoostRunner(
    processRunner: FakeProcessRunner(
      processResponses ?? _defaultProcessResponses(),
    ),
    logger: BoostLogger.buffered(output),
    dialogs: const NonInteractiveDialogSupport(),
    environment: const <String, String>{},
    isWindows: false,
  );
  // `CommandRunner.run` throws `UsageException` for a missing subcommand or
  // a bad flag rather than returning an exit code -- `bin/dart_boost.dart`
  // catches it and maps it to 64 (`EX_USAGE`), so mirror that here. Anything
  // else is a genuine bug and should still blow up the test.
  try {
    final exitCode = await runner.run(args) ?? 0;
    return CliResult(exitCode, output.join('\n'));
  } on UsageException catch (error) {
    return CliResult(64, <String>[...output, error.toString()].join('\n'));
  }
}

/// Reads a file at [path] (an absolute path, e.g. from `d.path(...)`).
Future<String> readFile(String path) => File(path).readAsString();

/// Reads and decodes a JSON file at [path].
Future<Map<String, Object?>> readJson(String path) async =>
    jsonDecode(await readFile(path)) as Map<String, Object?>;

/// Whether a file exists at [path].
Future<bool> exists(String path) => File(path).exists();

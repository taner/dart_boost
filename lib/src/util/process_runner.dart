import 'dart:convert';
import 'dart:io' as io;

/// The subset of a process result dart_boost cares about.
class ProcessOutcome {
  const ProcessOutcome(this.exitCode, this.stdout, this.stderr);

  const ProcessOutcome.failed() : exitCode = -1, stdout = '', stderr = '';

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

/// Every process dart_boost spawns goes through here so tests can stub the
/// world -- `command -v`, `dart mcp-server --version`, `flutter --version`
/// and `dart run skills@ get` are all injected, never called directly.
abstract class ProcessRunner {
  const ProcessRunner();

  ProcessOutcome run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

class SystemProcessRunner extends ProcessRunner {
  const SystemProcessRunner();

  @override
  ProcessOutcome run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    try {
      final result = io.Process.runSync(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return ProcessOutcome(
        result.exitCode,
        result.stdout as String? ?? '',
        result.stderr as String? ?? '',
      );
    } on io.ProcessException {
      return const ProcessOutcome.failed();
    } on io.OSError {
      return const ProcessOutcome.failed();
    }
  }
}

/// Answers from a lookup table; anything unmapped "fails to spawn".
class FakeProcessRunner extends ProcessRunner {
  FakeProcessRunner([Map<String, ProcessOutcome>? responses])
    : responses = responses ?? <String, ProcessOutcome>{};

  /// Keyed by `'<executable> <args joined by space>'`.
  final Map<String, ProcessOutcome> responses;

  final List<String> invocations = <String>[];

  @override
  ProcessOutcome run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    final key = <String>[executable, ...arguments].join(' ');
    invocations.add(key);
    return responses[key] ?? const ProcessOutcome.failed();
  }
}

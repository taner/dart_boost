import 'dart:async';
import 'dart:io' as io;

import 'package:cli_util/cli_components.dart';
import 'package:cli_util/windows_compatibility.dart';

/// Interactive prompts, behind an interface.
///
/// `package:skills` wraps `cli_util`'s `cli_components` behind an injectable
/// `DialogSupport` for exactly this reason: tests get a scripted fake, and CI
/// -- where `stdin.hasTerminal` is false -- gets a non-interactive
/// implementation instead of a hang.
abstract class DialogSupport {
  bool get interactive;

  /// Returns `null` when the user cancelled.
  Future<Set<int>?> multiSelect(
    List<String> options, {
    Set<int> initialSelected = const <int>{},
  });

  Future<bool> confirm(String question, {bool defaultValue = true});
}

/// Real terminal dialogs. Handles raw-mode toggling, mode restoration and
/// SIGINT cancel via `cli_components`, and converts Windows key events to ANSI
/// so arrow keys work.
class TerminalDialogSupport implements DialogSupport {
  TerminalDialogSupport();

  Stream<List<int>>? _input;
  StreamSubscription<List<int>>? _keepAlive;

  @override
  bool get interactive => io.stdin.hasTerminal && io.stdout.hasTerminal;

  Stream<List<int>> get _stream {
    final existing = _input;
    if (existing != null) return existing;
    final source = io.Platform.isWindows ? Win32AnsiStdin() : io.stdin;
    final broadcast = source.asBroadcastStream(
      onCancel: (subscription) => subscription.cancel(),
    );
    _keepAlive = broadcast.listen((_) {});
    return _input = broadcast;
  }

  @override
  Future<Set<int>?> multiSelect(
    List<String> options, {
    Set<int> initialSelected = const <int>{},
  }) => showMultiSelectDialog(
    options,
    _stream,
    initialSelected: initialSelected,
    maxVisibleItems: 10,
  );

  @override
  Future<bool> confirm(String question, {bool defaultValue = true}) async {
    io.stdout.write('$question ${defaultValue ? '[Y/n]' : '[y/N]'} ');
    final answer = io.stdin.readLineSync()?.trim().toLowerCase();
    if (answer == null || answer.isEmpty) return defaultValue;
    return answer == 'y' || answer == 'yes';
  }

  Future<void> dispose() async {
    await _keepAlive?.cancel();
    _keepAlive = null;
    _input = null;
  }
}

/// What CI gets. Accepts every default and never blocks.
class NonInteractiveDialogSupport implements DialogSupport {
  const NonInteractiveDialogSupport();

  @override
  bool get interactive => false;

  @override
  Future<Set<int>?> multiSelect(
    List<String> options, {
    Set<int> initialSelected = const <int>{},
  }) async => initialSelected;

  @override
  Future<bool> confirm(String question, {bool defaultValue = true}) async =>
      defaultValue;
}

/// Scripted answers, for tests.
class FakeDialogSupport implements DialogSupport {
  FakeDialogSupport({
    this.selections = const <Set<int>?>[],
    this.confirmations = const <bool>[],
  });

  final List<Set<int>?> selections;
  final List<bool> confirmations;

  final List<String> questions = <String>[];
  int _selectionIndex = 0;
  int _confirmIndex = 0;

  @override
  bool get interactive => true;

  @override
  Future<Set<int>?> multiSelect(
    List<String> options, {
    Set<int> initialSelected = const <int>{},
  }) async =>
      _selectionIndex < selections.length
          ? selections[_selectionIndex++]
          : initialSelected;

  @override
  Future<bool> confirm(String question, {bool defaultValue = true}) async {
    questions.add(question);
    return _confirmIndex < confirmations.length
        ? confirmations[_confirmIndex++]
        : defaultValue;
  }
}

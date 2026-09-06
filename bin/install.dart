import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_boost/src/cli/runner.dart';

/// `dart run dart_boost:install` -- a thin shim so the primary verb needs no
/// subcommand.
Future<void> main(List<String> arguments) async {
  try {
    exitCode =
        await DartBoostRunner().run(<String>['install', ...arguments]) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}

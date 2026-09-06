import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_boost/src/cli/runner.dart';

/// `dart run dart_boost:update`.
Future<void> main(List<String> arguments) async {
  try {
    exitCode =
        await DartBoostRunner().run(<String>['update', ...arguments]) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}

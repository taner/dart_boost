import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_boost/src/cli/runner.dart';

Future<void> main(List<String> arguments) async {
  final runner = DartBoostRunner();
  try {
    exitCode = await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}

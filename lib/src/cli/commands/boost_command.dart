import 'package:args/command_runner.dart';

import '../../util/logger.dart';
import '../context.dart';
import '../runner.dart';

abstract class BoostCommand extends Command<int> {
  BoostContext get context => (runner! as DartBoostRunner).context;

  BoostLogger get logger => context.logger;

  /// Exit code for "the user asked for something impossible" (`EX_USAGE`).
  static const usageError = 64;

  /// Exit code for "we could not do the work" (`EX_SOFTWARE`).
  static const softwareError = 70;
}

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import '../util/logger.dart';
import '../util/process_runner.dart';
import '../version.dart';
import 'commands/compose_command.dart';
import 'commands/doctor_command.dart';
import 'commands/install_command.dart';
import 'commands/rules_command.dart';
import 'commands/update_command.dart';
import 'context.dart';
import 'dialog_support.dart';

/// The single `CommandRunner`. `bin/` holds thin shims over it, so
/// `dart run dart_boost:install` and `dart_boost install` share one code path.
class DartBoostRunner extends CommandRunner<int> {
  DartBoostRunner({
    FileSystem? fileSystem,
    ProcessRunner? processRunner,
    BoostLogger? logger,
    DialogSupport? dialogs,
    Map<String, String>? environment,
    bool? isWindows,
    String? homeDirectory,
  }) : _fileSystem = fileSystem ?? const LocalFileSystem(),
       _processRunner = processRunner ?? const SystemProcessRunner(),
       _logger = logger,
       _dialogs = dialogs,
       _environment = environment,
       _isWindows = isWindows,
       _homeDirectory = homeDirectory,
       super('dart_boost', _description) {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        valueHelp: 'path',
        help: 'Run as if dart_boost were started in <path>.',
      )
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the dart_boost version and exit.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Report what would change without touching any file.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print detail about every decision.',
      )
      ..addFlag(
        'probe-sdk',
        negatable: false,
        help:
            'Allow spawning `flutter --version --machine` when the SDK '
            'version cannot be read from project files (slow, and can '
            'trigger an artifact download).',
      );

    addCommand(DoctorCommand());
    addCommand(ComposeCommand());
    addCommand(InstallCommand());
    addCommand(UpdateCommand());
    addCommand(RulesCommand());
  }

  static const _description =
      'Version-aware AI guidelines and one-command '
      'agent wiring for Dart and Flutter projects.';

  final FileSystem _fileSystem;
  final ProcessRunner _processRunner;
  final BoostLogger? _logger;
  final DialogSupport? _dialogs;
  final Map<String, String>? _environment;
  final bool? _isWindows;
  final String? _homeDirectory;

  late BoostContext context;

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['version'] as bool) {
      (_logger ?? BoostLogger()).info('dart_boost $packageVersion');
      return 0;
    }

    final directory = topLevelResults['directory'] as String?;
    context = BoostContext(
      fileSystem: _fileSystem,
      processRunner: _processRunner,
      logger:
          _logger ?? BoostLogger(verbose: topLevelResults['verbose'] as bool),
      dialogs: _dialogs,
      workingDirectory: _fileSystem.directory(
        directory ?? _fileSystem.currentDirectory.path,
      ),
      dryRun: topLevelResults['dry-run'] as bool,
      probeSdk: topLevelResults['probe-sdk'] as bool,
      isWindows: _isWindows,
      homeDirectory: _homeDirectory,
      environment: _environment,
    );

    if (!context.workingDirectory.existsSync()) {
      context.logger.error(
        'No such directory: ${context.workingDirectory.path}',
      );
      return 64;
    }

    return await super.runCommand(topLevelResults) ?? 0;
  }
}

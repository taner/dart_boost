import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../agents/agent_detector.dart';
import '../assets/bundled_assets.dart';
import '../project/project.dart';
import '../state/boost_state.dart';
import '../state/machine_state.dart';
import '../util/logger.dart';
import '../util/process_runner.dart';
import 'dialog_support.dart';

/// Everything a command needs, all of it injectable.
class BoostContext {
  BoostContext({
    FileSystem? fileSystem,
    ProcessRunner? processRunner,
    BoostLogger? logger,
    DialogSupport? dialogs,
    Directory? workingDirectory,
    this.dryRun = false,
    this.probeSdk = false,
    bool? isWindows,
    String? homeDirectory,
    Map<String, String>? environment,
    BundledAssets? assets,
  }) : fileSystem = fileSystem ?? const LocalFileSystem(),
       processRunner = processRunner ?? const SystemProcessRunner(),
       logger = logger ?? BoostLogger(),
       isWindows = isWindows ?? io.Platform.isWindows,
       environment = environment ?? io.Platform.environment,
       _dialogs = dialogs,
       _assets = assets {
    _workingDirectory =
        workingDirectory ??
        this.fileSystem.directory(this.fileSystem.currentDirectory.path);
    _homeDirectory =
        homeDirectory ??
        this.environment['HOME'] ??
        this.environment['USERPROFILE'];
  }

  final FileSystem fileSystem;
  final ProcessRunner processRunner;
  final BoostLogger logger;
  final bool dryRun;

  /// Whether `flutter --version --machine` may be spawned. It is 2-5s cold and
  /// can trigger an artifact download, so it stays opt-in.
  final bool probeSdk;

  final bool isWindows;
  final Map<String, String> environment;

  late final Directory _workingDirectory;
  late final String? _homeDirectory;
  DialogSupport? _dialogs;
  BundledAssets? _assets;

  Directory get workingDirectory => _workingDirectory;

  String? get homeDirectory => _homeDirectory;

  DialogSupport get dialogs {
    final existing = _dialogs;
    if (existing != null) return existing;
    final terminal = TerminalDialogSupport();
    return _dialogs =
        terminal.interactive ? terminal : const NonInteractiveDialogSupport();
  }

  /// Whether a prompt may be shown at all.
  ///
  /// A TTY is necessary but not sufficient: CI runners frequently allocate one
  /// (GitHub Actions' `docker run -t`, most self-hosted setups), so a
  /// `hasTerminal` check alone is exactly how a release pipeline ends up
  /// blocked on a multiselect nobody can answer. Checking the environment as
  /// well is what `--yes` would otherwise have to do by hand in every job.
  bool get interactive => !isCi && dialogs.interactive;

  /// The environment variables that mean "no human is watching".
  ///
  /// `CI` is the near-universal one; the rest are vendors that historically
  /// did not set it. A bare `TERM=dumb` also counts -- that is what a terminal
  /// says when it cannot render the cursor movement a multiselect needs.
  static const ciVariables = <String>[
    'CI',
    'CONTINUOUS_INTEGRATION',
    'BUILD_NUMBER',
    'GITHUB_ACTIONS',
    'GITLAB_CI',
    'TF_BUILD',
    'TEAMCITY_VERSION',
  ];

  late final bool isCi = _detectCi();

  bool _detectCi() {
    for (final name in ciVariables) {
      final value = environment[name];
      // Present-but-empty is how a shell spells "unset" often enough to
      // matter, and `CI=false` is set deliberately by people opting out.
      if (value == null || value.isEmpty) continue;
      if (value.toLowerCase() == 'false' || value == '0') continue;
      return true;
    }
    return environment['TERM'] == 'dumb';
  }

  BoostContext copyWith({Directory? workingDirectory}) => BoostContext(
    fileSystem: fileSystem,
    processRunner: processRunner,
    logger: logger,
    dialogs: _dialogs,
    workingDirectory: workingDirectory ?? _workingDirectory,
    dryRun: dryRun,
    probeSdk: probeSdk,
    isWindows: isWindows,
    homeDirectory: _homeDirectory,
    environment: environment,
    assets: _assets,
  );

  Future<BundledAssets?> assets() async =>
      _assets ??= await BundledAssets.locate(fileSystem: fileSystem);

  Project resolveProject() => ProjectResolver(
    fileSystem: fileSystem,
    processRunner: processRunner,
    allowProcessProbe: probeSdk,
  ).resolve(_workingDirectory);

  AgentDetector detector() => AgentDetector(
    fileSystem: fileSystem,
    processRunner: processRunner,
    isWindows: isWindows,
    homeDirectory: _homeDirectory,
    environment: environment,
  );

  BoostStateStore stateStore(Directory root) =>
      BoostStateStore(fileSystem, root);

  MachineStateStore machineStateStore(Directory root) =>
      MachineStateStore(fileSystem, root);

  /// Presents a path relative to the working directory when that is shorter.
  String relative(String path) {
    final rel = p.relative(path, from: _workingDirectory.path);
    return rel.length < path.length ? rel : path;
  }
}

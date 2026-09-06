import 'boost_command.dart';
import 'install_command.dart';

/// Re-runs the previous install with the answers already on file, reporting
/// what moved since -- an SDK bump, a new dependency, a newly installed agent.
class UpdateCommand extends BoostCommand {
  UpdateCommand() {
    addInstallOptions(argParser);
  }

  @override
  String get name => 'update';

  @override
  String get description =>
      'Re-compose and re-write using the choices saved by the last install.';

  @override
  Future<int> run() async => runInstall(this, isUpdate: true);
}

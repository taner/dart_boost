import '../../guidelines/composer.dart';
import '../../guidelines/facts.dart';
import 'boost_command.dart';

/// Prints the composed guidelines to stdout.
///
/// This is what makes the fragment library reviewable: you can diff composed
/// output across two real projects without writing anything to either.
class ComposeCommand extends BoostCommand {
  ComposeCommand() {
    argParser
      ..addFlag(
        'keys',
        negatable: false,
        help: 'List the fragment keys that matched instead of their content.',
      )
      ..addMultiOption(
        'trust',
        valueHelp: 'package',
        help: 'Include guidelines shipped by these dependencies.',
      )
      ..addMultiOption(
        'exclude',
        valueHelp: 'key',
        help: 'Drop a fragment by key (e.g. `riverpod/v3`).',
      );
  }

  @override
  String get name => 'compose';

  @override
  String get description => 'Print the guidelines composed for this project.';

  @override
  Future<int> run() async {
    final assets = await context.assets();
    if (assets == null) {
      logger.error('Bundled guidelines/ tree not found.');
      return BoostCommand.softwareError;
    }

    final project = context.resolveProject();
    final result =
        GuidelineComposer(
          fileSystem: context.fileSystem,
          assets: assets,
          project: project,
          facts: GuidelineFacts.forProject(project),
          trustedThirdParty: argResults!['trust'] as List<String>,
          excludeKeys: (argResults!['exclude'] as List<String>).toSet(),
        ).compose();

    for (final warning in result.warnings) {
      logger.warn(warning);
    }

    if (argResults!['keys'] as bool) {
      for (final fragment in result.fragments) {
        final tags = <String>[
          if (fragment.custom) 'custom',
          if (fragment.thirdParty) 'third-party',
        ];
        logger.info(
          '${fragment.key}${tags.isEmpty ? '' : '  [${tags.join(', ')}]'}',
        );
      }
      return 0;
    }

    if (result.isEmpty) {
      logger.warn('No fragments matched this project.');
      return 0;
    }

    logger.write(result.content.trimRight());
    return 0;
  }
}

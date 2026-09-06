import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../util/process_runner.dart';
import '../util/version_key.dart';

/// SDK versions as resolved *for the target project*.
///
/// Never read from `Platform.version`: under FVM or `dart pub global activate`
/// the running SDK is a different one from the project's, and version-keyed
/// guidelines would silently key on the wrong tree.
class SdkVersions {
  const SdkVersions({
    this.flutter,
    this.dart,
    this.channel,
    this.flutterSdkRoot,
    this.fvmPin,
    this.usesFvm = false,
    this.flutterSource = 'not found',
    this.dartSource = 'not found',
  });

  final Version? flutter;
  final Version? dart;
  final String? channel;

  /// Root of the Flutter SDK this project resolves against, when known.
  final String? flutterSdkRoot;

  /// The raw pin recorded by FVM. May be a channel (`stable`) rather than a
  /// version, which is why it is never used as the version on its own.
  final String? fvmPin;

  final bool usesFvm;

  /// Which link in the fallback chain answered, for `doctor` output.
  final String flutterSource;
  final String dartSource;

  bool get isFlutter => flutter != null;

  /// `3.47.2` -> `3.47`; the SDK fragments are keyed on the minor.
  String? get flutterKey {
    final v = flutter;
    return v == null ? null : sdkVersionKey(v);
  }
}

/// Walks the fallback chain that ends in an actual Flutter version.
class SdkResolver {
  const SdkResolver({
    required this.fileSystem,
    required this.processRunner,
    this.allowProcessProbe = false,
    this.onWarning,
  });

  final FileSystem fileSystem;
  final ProcessRunner processRunner;

  /// `flutter --version --machine` is 2-5s cold and can trigger an artifact
  /// download, so it stays behind `--probe-sdk`.
  final bool allowProcessProbe;

  final void Function(String)? onWarning;

  /// [projectRoot] is the directory owning `.dart_tool/`; [flutterPackagePath]
  /// is the `flutter` entry's rootUri from `package_config.json`, when present.
  SdkVersions resolve({
    required Directory projectRoot,
    String? flutterPackagePath,
    String? packageConfigGeneratorVersion,
  }) {
    final fvm = _readFvm(projectRoot);

    Version? flutter;
    var flutterSource = 'not found';
    String? channel;
    String? sdkRoot;

    // 1. `.dart_tool/version` -- written by flutter_tools on every `pub get`.
    //    Undocumented, but by far the cheapest accurate signal.
    final dartToolVersion = _readText(
      p.join(projectRoot.path, '.dart_tool', 'version'),
    );
    flutter = tryParseVersion(dartToolVersion);
    if (flutter != null) flutterSource = '.dart_tool/version';

    // 2/3. FVM's own pin, when it names a concrete version rather than a channel.
    if (flutter == null && fvm.pin != null) {
      flutter = tryParseVersion(fvm.pin);
      if (flutter != null) flutterSource = fvm.pinSource!;
    }

    // 4. `.fvm/flutter_sdk` symlink -- resolve the target and read its cache.
    if (fvm.sdkLinkTarget != null) {
      sdkRoot ??= fvm.sdkLinkTarget;
      if (flutter == null) {
        final fromLink = _readFlutterVersionJson(fvm.sdkLinkTarget!);
        if (fromLink != null) {
          flutter = fromLink.version;
          channel ??= fromLink.channel;
          flutterSource = '.fvm/flutter_sdk';
        }
      }
    }

    // 5. Derive the SDK root from the `flutter` package in package_config.json:
    //    `<sdk>/packages/flutter` -> `<sdk>`.
    if (flutterPackagePath != null) {
      sdkRoot ??= p.dirname(p.dirname(flutterPackagePath));
    }
    if (sdkRoot != null) {
      final fromCache = _readFlutterVersionJson(sdkRoot);
      if (fromCache != null) {
        channel ??= fromCache.channel;
        if (flutter == null) {
          flutter = fromCache.version;
          flutterSource = 'flutter.version.json';
        }
      }
    }

    // 6. Last resort, gated: spawn the toolchain.
    Version? dart;
    var dartSource = 'not found';
    if (flutter == null && flutterPackagePath != null && allowProcessProbe) {
      final probed = _probeFlutter(projectRoot, fvm);
      if (probed != null) {
        flutter = probed.version;
        channel ??= probed.channel;
        dart = probed.dartVersion;
        if (dart != null) dartSource = 'flutter --version --machine';
        flutterSource = 'flutter --version --machine';
      }
    } else if (flutter == null && flutterPackagePath != null) {
      onWarning?.call(
        'Could not resolve the Flutter version from project files. '
        'Re-run with --probe-sdk to ask the toolchain directly.',
      );
    }

    // The Dart version comes from the SDK that actually ran `pub get` here.
    if (dart == null) {
      dart = tryParseVersion(packageConfigGeneratorVersion);
      if (dart != null) dartSource = 'package_config.json generatorVersion';
    }
    if (dart == null && sdkRoot != null) {
      final cache = _readFlutterVersionJson(sdkRoot);
      dart = cache?.dartVersion;
      if (dart != null) dartSource = 'flutter.version.json';
    }

    return SdkVersions(
      flutter: flutter,
      dart: dart,
      channel: channel,
      flutterSdkRoot: sdkRoot,
      fvmPin: fvm.pin,
      usesFvm: fvm.usesFvm,
      flutterSource: flutterSource,
      dartSource: dartSource,
    );
  }

  _FvmState _readFvm(Directory projectRoot) {
    String? pin;
    String? pinSource;

    // FVM 3
    final fvmrc = _readJson(p.join(projectRoot.path, '.fvmrc'));
    if (fvmrc != null) {
      final value = fvmrc['flutter'];
      if (value is String && value.isNotEmpty) {
        pin = value;
        pinSource = '.fvmrc';
      }
    }

    // FVM 2
    if (pin == null) {
      final legacy = _readJson(
        p.join(projectRoot.path, '.fvm', 'fvm_config.json'),
      );
      final value = legacy?['flutterSdkVersion'];
      if (value is String && value.isNotEmpty) {
        pin = value;
        pinSource = '.fvm/fvm_config.json';
      }
    }

    final linkPath = p.join(projectRoot.path, '.fvm', 'flutter_sdk');
    String? linkTarget;
    if (fileSystem.link(linkPath).existsSync()) {
      try {
        linkTarget = fileSystem.link(linkPath).resolveSymbolicLinksSync();
      } on FileSystemException {
        linkTarget = null;
      }
    } else if (fileSystem.directory(linkPath).existsSync()) {
      linkTarget = linkPath;
    }

    final usesFvm =
        pin != null ||
        linkTarget != null ||
        fileSystem.directory(p.join(projectRoot.path, '.fvm')).existsSync();

    return _FvmState(
      pin: pin,
      pinSource: pinSource,
      sdkLinkTarget: linkTarget,
      usesFvm: usesFvm,
    );
  }

  _FlutterVersionFile? _readFlutterVersionJson(String sdkRoot) {
    final json = _readJson(
      p.join(sdkRoot, 'bin', 'cache', 'flutter.version.json'),
    );
    if (json == null) return null;
    return _FlutterVersionFile(
      version: tryParseVersion(json['frameworkVersion'] as String?),
      channel: json['channel'] as String?,
      dartVersion: tryParseVersion(json['dartSdkVersion'] as String?),
    );
  }

  _FlutterVersionFile? _probeFlutter(Directory projectRoot, _FvmState fvm) {
    final executable =
        fvm.usesFvm && fvm.sdkLinkTarget != null
            ? p.join(fvm.sdkLinkTarget!, 'bin', 'flutter')
            : 'flutter';
    final result = processRunner.run(executable, const [
      '--version',
      '--machine',
    ], workingDirectory: projectRoot.path);
    if (!result.succeeded) return null;
    try {
      // `flutter --version --machine` occasionally prefixes upgrade banners.
      final start = result.stdout.indexOf('{');
      if (start < 0) return null;
      final decoded =
          jsonDecode(result.stdout.substring(start)) as Map<String, dynamic>;
      return _FlutterVersionFile(
        version: tryParseVersion(decoded['frameworkVersion'] as String?),
        channel: decoded['channel'] as String?,
        dartVersion: tryParseVersion(decoded['dartSdkVersion'] as String?),
      );
    } on FormatException {
      return null;
    }
  }

  String? _readText(String path) {
    final file = fileSystem.file(path);
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  Map<String, dynamic>? _readJson(String path) {
    final raw = _readText(path);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      onWarning?.call('Ignoring malformed JSON at $path');
      return null;
    }
  }
}

class _FvmState {
  const _FvmState({
    this.pin,
    this.pinSource,
    this.sdkLinkTarget,
    this.usesFvm = false,
  });

  final String? pin;
  final String? pinSource;
  final String? sdkLinkTarget;
  final bool usesFvm;
}

class _FlutterVersionFile {
  const _FlutterVersionFile({this.version, this.channel, this.dartVersion});

  final Version? version;
  final String? channel;
  final Version? dartVersion;
}

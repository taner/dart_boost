import 'dart:io' as io;

/// Terminal output. Injectable so tests can assert on what was printed
/// without capturing the real stdout.
class BoostLogger {
  BoostLogger({
    this.verbose = false,
    bool? ansi,
    void Function(String)? out,
    void Function(String)? err,
  }) : _ansi = ansi ?? _supportsAnsi(),
       _out = out ?? io.stdout.writeln,
       _err = err ?? io.stderr.writeln;

  /// Collects everything written, for tests.
  factory BoostLogger.buffered(List<String> sink, {bool verbose = false}) =>
      BoostLogger(verbose: verbose, ansi: false, out: sink.add, err: sink.add);

  final bool verbose;
  final bool _ansi;
  final void Function(String) _out;
  final void Function(String) _err;

  static bool _supportsAnsi() {
    try {
      return io.stdout.hasTerminal && io.stdout.supportsAnsiEscapes;
    } on Object {
      return false;
    }
  }

  String _paint(String text, String code) =>
      _ansi ? '\x1b[${code}m$text\x1b[0m' : text;

  void write(String message) => _out(message);

  void blank() => _out('');

  void info(String message) => _out(message);

  void heading(String message) => _out(_paint(message, '1'));

  void success(String message) => _out('${_paint('+', '32')} $message');

  void skipped(String message) =>
      _out('${_paint('-', '90')} ${_paint(message, '90')}');

  void warn(String message) => _err('${_paint('!', '33')} $message');

  void error(String message) => _err('${_paint('x', '31')} $message');

  void detail(String message) {
    if (verbose) _out(_paint('  $message', '90'));
  }

  /// `key: value` aligned to [width], used by `doctor`.
  void field(String key, Object? value, {int width = 22}) =>
      _out('  ${_paint(key.padRight(width), '36')}${value ?? '-'}');
}

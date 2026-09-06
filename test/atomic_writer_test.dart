import 'package:dart_boost/src/writers/atomic_writer.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_project.dart';

void main() {
  late FileSystem fs;
  late String path;

  setUp(() {
    fs = memoryFs();
    path = p.join(fs.currentDirectory.path, 'app', '.mcp.json');
  });

  test('creates the file and its parent directory', () {
    expect(AtomicWriter(fs).write(path, 'hello\n'), isTrue);
    expect(fs.file(path).readAsStringSync(), 'hello\n');
  });

  test('leaves no temp file behind', () {
    AtomicWriter(fs).write(path, 'hello\n');
    expect(
      fs.directory(p.dirname(path)).listSync().map((e) => p.basename(e.path)),
      isNot(contains(contains('.tmp'))),
    );
  });

  test('backs the original up exactly once', () {
    fs.file(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('original\n');

    AtomicWriter(fs).write(path, 'first\n');
    AtomicWriter(fs).write(path, 'second\n');

    expect(
      fs.file('$path${AtomicWriter.backupSuffix}').readAsStringSync(),
      'original\n',
      reason:
          'the backup must keep the pre-dart_boost content, not the last write',
    );
  });

  test('an unchanged write is a no-op and creates no backup', () {
    fs.file(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('same\n');

    expect(AtomicWriter(fs).write(path, 'same\n'), isFalse);
    expect(fs.file('$path${AtomicWriter.backupSuffix}').existsSync(), isFalse);
  });

  test('a dry run reports the change without making it', () {
    expect(AtomicWriter(fs, dryRun: true).write(path, 'hello\n'), isTrue);
    expect(fs.file(path).existsSync(), isFalse);
  });
}

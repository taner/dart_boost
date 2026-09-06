import 'package:dart_boost/src/util/version_key.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  group('versionKey', () {
    // For 0.x the *minor* is pub's breaking axis (`^0.3.1` allows `<0.4.0`),
    // so keying on the major alone would silently collide 0.3 and 0.4.
    const cases = <String, String>{
      '2.6.1': '2',
      '3.0.0': '3',
      '16.2.4': '16',
      '0.4.2': '0.4',
      '0.3.9': '0.3',
      '0.0.1': '0.0',
      '3.0.0-dev.1': '3',
      '1.0.0+5': '1',
    };

    cases.forEach((input, expected) {
      test('$input -> $expected', () {
        expect(versionKey(Version.parse(input)), expected);
      });
    });
  });

  group('sdkVersionKey', () {
    test('keys Flutter on the minor', () {
      expect(sdkVersionKey(Version.parse('3.47.2')), '3.47');
      expect(sdkVersionKey(Version.parse('3.7.7')), '3.7');
    });
  });

  test('versionKeyForFlag makes a 0.x key a single token', () {
    expect(versionKeyForFlag('0.4'), '0_4');
    expect(versionKeyForFlag('3'), '3');
  });

  group('tryParseVersion', () {
    test('parses ordinary versions', () {
      expect(tryParseVersion('3.13.2'), Version.parse('3.13.2'));
    });

    test('recovers a version from loose toolchain output', () {
      expect(tryParseVersion('3.47.2 (channel stable)'), Version(3, 47, 2));
      expect(tryParseVersion('3.47'), Version(3, 47, 0));
    });

    test('returns null for nothing usable', () {
      expect(tryParseVersion(null), isNull);
      expect(tryParseVersion('   '), isNull);
      expect(tryParseVersion('unknown'), isNull);
    });
  });
}

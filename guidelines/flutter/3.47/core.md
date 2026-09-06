# Flutter 3.47

Guidance for the 3.47 line specifically. This SDK ships Dart 3.13, so the
language notes below do not apply to a 3.44 checkout of the same code.

## `flutter pub get` rewrites `analysis_options.yaml`

3.47 runs an analysis-options migration as part of `{{ pubGetCommand }}`: it
adds an `analyzer: exclude:` block covering `build/**` and whichever platform
directories exist (`android/**`, `ios/**`, `web/**`, ...). It only touches
packages that actually depend on `flutter`.

An unexplained diff in `analysis_options.yaml` after a pub get is the SDK, not
you. Commit it; do not revert it and do not re-add the excluded directories.

## `dart fix` now carries the Material/Cupertino package migration

This SDK's fix data contains a `replacedBy` transform pointing
`package:flutter/material.dart` at `package:material_ui/material_ui.dart`, and
`package:flutter/cupertino.dart` at `package:cupertino_ui/cupertino_ui.dart`.

Never run a blanket `{{ dartCommand }} fix --apply` and commit it unreviewed on
this SDK. Read the diff, and reject any rewritten `material.dart` or
`cupertino.dart` import unless migrating to those packages is the task you
were given -- they are not dependencies of this project unless someone added
them.

## Build version constants

`package:flutter/services.dart` exports `appBuildName` and `appBuildNumber`,
compiled in from the pubspec `version:` field (or `--build-name` /
`--build-number`). Use them for a version string in the UI instead of adding a
plugin or reading `version.json` at runtime; both are `String?` and are `null`
when the pubspec has no version.

## Dart 3.13 language

- Primary constructors are stable here. A value class can be one line, and
  that is the preferred shape for one.
- `package:flutter/foundation.dart` re-exports `awaitNotRequired`. Annotate a
  `Future`-returning API that callers may legitimately fire and forget, rather
  than spreading `unawaited(...)` across every call site.

```dart
// Primary constructor: no field declarations, no assignment boilerplate.
class Money(final int cents, final String currency) {
  String get formatted => '${cents / 100} $currency';
}
```

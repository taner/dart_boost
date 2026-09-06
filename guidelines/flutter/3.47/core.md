# Flutter 3.47

Guidance for the 3.47 line specifically, and only for what Flutter itself
changed. This SDK ships Dart 3.13; that language and core-library guidance is
composed separately as `dart/v3.13`, so it is not repeated here.

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

## `awaitNotRequired` comes from `foundation.dart`

`package:flutter/foundation.dart` re-exports `awaitNotRequired`, so a file that
already imports `foundation.dart` needs no further import to use it. Annotate
a `Future`-returning API that callers may legitimately fire and forget, rather
than spreading `unawaited(...)` across every call site.

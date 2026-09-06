# Flutter 3.44

Guidance for the 3.44 line specifically. This SDK ships Dart 3.12, and several
things written for the 3.47 line are not available here.

## Not available on this SDK

- **Primary constructors.** `class Money(final int cents);` does not analyze
  on Dart 3.12 -- it needs `--enable-experiment=primary-constructors`. Write
  the ordinary constructor with `this.` parameters; do not enable the
  experiment to work around this.
- **`appBuildName` / `appBuildNumber`.** `package:flutter/services.dart` does
  not export them yet. Get the app version from a `--dart-define`, from a
  plugin such as `package_info_plus`, or from a generated constant.
- **`awaitNotRequired` from `package:flutter/foundation.dart`.** Use
  `unawaited(...)` at the call site instead.

## `analysis_options.yaml` is yours to maintain

3.44 does not migrate `analysis_options.yaml` on `{{ pubGetCommand }}`. If the
analyzer is reporting problems in `build/` or in generated platform code, add
the exclusions yourself:

```yaml
analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
```

## `dart fix` is a lint cleanup here

Unlike 3.47, this SDK's fix data carries no library-level `replacedBy`
transform for `package:flutter/material.dart`, so
`{{ dartCommand }} fix --apply` will not rewrite your framework imports. Read
the diff anyway, but it is the ordinary mechanical cleanup.

# FVM

This project pins its Flutter SDK with FVM (currently {{ flutterVersion }},
channel {{ flutterChannel }}). The pin lives in `.fvmrc` at the project root
(older setups use `.fvm/fvm_config.json`), and `.fvm/flutter_sdk` is a symlink
to the installed SDK.

## The SDK on PATH is not this project's SDK

The `flutter` and `dart` on `PATH` resolve against a different SDK than the one
this project builds with, and the mismatch is silent -- you get a plausible
analyzer result for the wrong version. Every toolchain invocation needs the
`fvm` prefix:

- `{{ pubGetCommand }}`
- `{{ analyzeCommand }}`
- `{{ testCommand }}`
- `{{ formatCommand }} .`
- `{{ dartRunCommand }} <script>`

`{{ dartCommand }}` is the Dart bundled *inside* the pinned Flutter SDK. Do not
substitute a standalone Dart install for it.

## What is already wired up

The `dart` MCP server configured for this project points at the pinned SDK's
absolute path (`.fvm/flutter_sdk/bin/dart`), so `analyze_files`, `lsp` and
`rip_grep_packages` already read the right sources. Shell commands you type are
the ones that need the prefix.

If the MCP server reports a version that does not match {{ flutterVersion }},
the pinned SDK is missing from disk. Run `fvm install`, then re-run
`{{ dartCommand }} run dart_boost install` so the path is rewritten.

## Do not move the pin

- Do not run `fvm use <version>` unless changing the SDK is the task. It
  rewrites `.fvmrc`, relinks `.fvm/flutter_sdk`, and invalidates every
  version-specific section of this document.
- `.fvmrc` is committed; `.fvm/versions/` is not. If `.fvm/flutter_sdk` is
  dangling after a fresh clone, the fix is `fvm install`, not editing the pin.
- CI must run `fvm install` (or `fvm use --force`) before any build step, for
  the same reason.

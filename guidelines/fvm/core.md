# FVM

This project is pinned to a specific Flutter SDK with FVM
(currently {{ flutterVersion }}).

The `flutter` and `dart` on `PATH` are **not** the SDK this project resolves
against. Every toolchain invocation needs the `fvm` prefix -- `{{ pubGetCommand }}`,
`{{ analyzeCommand }}`, `{{ testCommand }}`, `{{ dartRunCommand }}`.

The MCP server dart_boost configured for this project already points at the
pinned SDK's absolute path, so tool calls analyse the right sources. Shell
commands you write are the ones that need the prefix.

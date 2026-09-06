# Changelog

## 0.1.0

Initial release: the installer and guidelines machinery.

- **Project detection.** Direct-vs-transitive resolution from
  `.dart_tool/package_graph.json`, falling back to `pubspec.lock`'s
  `dependency:` field and then `pubspec.yaml`. SDK version resolved from
  `.dart_tool/version` → FVM 3 → FVM 2 → the `.fvm/flutter_sdk` symlink →
  `flutter.version.json` → an opt-in `flutter --version --machine` probe.
  Pub workspaces and Melos monorepos handled.
- **Version-aware composition.** Fragments keyed on the resolved major (or the
  minor below `1.0.0`, which is pub's breaking axis) and on the Flutter SDK
  minor. Four-source layering with user overrides, priority and
  must-be-direct rules.
- **Renderer.** `if`/`else`/`end` over named flags plus `{{ variable }}`, with
  fenced code blocks masked and HTML-comment directives. Never throws.
- **Agent wiring.** Nine agents; guidelines written into a sentinel block that
  survives re-runs, and MCP entries spliced into JSON, JSONC and TOML configs
  without disturbing comments or formatting. Every splice is re-parsed before
  it is written, written atomically, and backed up once.
- **FVM-aware MCP command**, so an FVM-pinned project does not point its agents
  at the wrong SDK.
- `doctor`, `compose`, `install` and `update`, plus `--dry-run`.

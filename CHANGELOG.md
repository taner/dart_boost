# Changelog

## 0.1.0

Initial release: the installer, the guidelines machinery, and the first
fragment library.

- **Project detection.** Direct-vs-transitive resolution from
  `.dart_tool/package_graph.json`, falling back to `pubspec.lock`'s
  `dependency:` field and then `pubspec.yaml`. SDK version resolved from
  `.dart_tool/version` → FVM 3 → FVM 2 → the `.fvm/flutter_sdk` symlink →
  `flutter.version.json` → an opt-in `flutter --version --machine` probe.
  Pub workspaces and Melos monorepos handled.
- **Version-aware composition.** Fragments keyed on the resolved major (or the
  minor below `1.0.0`, which is pub's breaking axis) and on the SDK minor for
  both Flutter and Dart. The Dart SDK key applies to every project, Flutter or
  not, so a Dart-only project still gets version-keyed guidance. Four-source
  layering with user overrides, priority and must-be-direct rules.
- **Renderer.** `if`/`else`/`end` over named flags plus `{{ variable }}`, with
  fenced code blocks masked and HTML-comment directives. Never throws.
- **Agent wiring.** Nine agents; guidelines written into a sentinel block that
  survives re-runs, and MCP entries spliced into JSON, JSONC and TOML configs
  without disturbing comments or formatting. Every splice is re-parsed before
  it is written, written atomically, and backed up once.
- **FVM-aware MCP command**, so an FVM-pinned project does not point its agents
  at the wrong SDK.
- **40 bundled fragments.** `foundation` and `dart/core` always, plus Dart
  SDK-minor fragments for **3.12** and **3.13**; `flutter/core` plus Flutter
  SDK-minor fragments for **3.44** and **3.47**; and `testing`, `fvm` and
  `melos` when the project has tests, an FVM pin or a Melos workspace.
  Version-keyed package guidance for
  **riverpod** 2 and 3 (each with a `testing` fragment), **bloc** 7–9,
  **go_router** 14–18, **freezed** 2–4, **dio** 4 and 5, **get_it** 7–9 and
  **injectable** 2 and 3, plus unversioned **json_serializable**. Version
  directories exist only where the API actually diverged; every family also
  ships a `core` fragment that applies at any version.
- **Third-party fragments.** A direct dependency shipping `guidelines/**/*.md`
  at its package root contributes to the composition, but only after explicit
  per-package opt-in via `--trust=<package>`, which is persisted so `update`
  repeats it. A `guidelines/manifest.yaml` declaring a `boost_facts_version:`
  newer than this release implements is skipped with a warning.
- **Skills hand-off.** After a successful install, `install` and `update` offer
  to run `package:skills` for the agent skills your dependencies ship —
  `dart run skills get` when it is a dependency of the project, `skills get`
  when it is on `PATH`. The remote form, `dart run skills@ get`, downloads from
  pub.dev and is reachable only behind an explicit `--skills`; `--yes` and CI
  accept the locally resolvable forms and nothing else. `--no-skills` turns it
  off. Running it is remembered as `delegateSkills` so `update` repeats it, and
  declining is remembered as a no. The hand-off never fails an install: absent,
  declined or non-zero is reported and nothing more.
- **Dependency and guidance drift.** `dart_boost.json` now records
  `dependencies` (the direct dependency set, name to resolved version) and
  `fragments` (the keys the run composed), so `update` prints *Dependencies
  since the last run* — additions, removals, and only the upgrades that move a
  fragment key — followed by *Guidance changes*, the fragments that actually
  appeared or dropped out. Both keys are nullable: a state file written before
  they existed has no baseline, so `update` reports nothing rather than
  announcing every existing dependency as new.
- **CI-aware prompts.** Prompts are skipped when nothing can answer them: no
  TTY, or `CI`, `CONTINUOUS_INTEGRATION`, `BUILD_NUMBER`, `GITHUB_ACTIONS`,
  `GITLAB_CI`, `TF_BUILD` or `TEAMCITY_VERSION` set to anything but `false` or
  `0`, or `TERM=dumb`. A TTY alone is not enough — CI runners routinely
  allocate one — and `CI=false` opts back in. Interactively, `install` now
  lists the files it is about to touch and confirms once before writing;
  skipped under `--yes`, `--dry-run`, CI, and `update`.
- `doctor`, `compose`, `install` and `update`, plus `--dry-run`.
- **Asset guard.** `tool/verify_assets.dart` asserts every file under
  `guidelines/` appears in `dart pub publish`'s manifest, and both CI and the
  publish workflow gate on it. `pub publish` strips dot-prefixed paths, so a
  stray ignore entry would ship an empty fragment tree while every local run
  still passed.

### Fixed before release

- `package_config.json`'s `rootUri` resolved one directory too high. Pub writes
  a *relative* `rootUri` for the root package, every path dependency and every
  workspace member, and the base URI lacked the trailing separator that makes
  it a directory — so resolution climbed out of the project and third-party
  `guidelines/` discovery was a silent no-op for exactly the packages most
  likely to ship one.
- `install` in a directory with no `pubspec.yaml` wrote its files and reported
  success. It now warns first.

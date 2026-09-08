# Changelog

## 0.2.1

- **Adds an example.** `example/README.md` walks a real session: install,
  recording a rule, bootstrapping rules from an existing codebase, and reading
  `doctor`. pub.dev renders it as the package's Example tab, which was empty.
  No behaviour changed.

## 0.2.0

Project rules: dart_boost's own MCP server, so agents record durable
project-specific decisions instead of re-deriving them every session.

- **`record_rule` MCP server.** A second server, run via
  `dart run dart_boost:mcp`, wired into every selected agent's config unless
  `--no-rules`. Its one tool, `record_rule`, takes a glob, a title and a note,
  and files the rule into `.ai/rules/<area>.md` — grouped by the part of the
  codebase the glob covers, appended to an existing file when one already
  covers that area — then regenerates `.ai/rules/index.md`, a table of every
  glob and the file that backs it. The guidelines stanza tells every agent to
  check the index before touching a file and read only the matching rows, so
  a large project's rules do not all land in context at once. The server
  never crashes on a malformed rule file; it skips it silently, and
  `dart_boost rules index` and `doctor` are what report it.
- **`dart_boost rules index`.** Regenerates the index from whatever is on
  disk without touching the rule files themselves — for the one case that
  bypasses `record_rule`: a rule file added or edited by hand, or a merge
  conflict resolved badly.
- **`.ai/infer-conventions.md`.** Written alongside the guidelines whenever
  rules are enabled. Walks an agent through inferring this project's existing,
  unwritten conventions — state management, widget composition, error
  handling, testing, and more — from a representative sample of the code, and
  has it present every finding with evidence before recording anything, so a
  human decides what is a real convention and what is a coin flip.
- **Enabling rules adds a dev dependency, once, with consent.**
  `dart run dart_boost:mcp` only resolves when dart_boost is a dependency of
  the target project, so the first `install` with rules turned on asks before
  running `dart pub add dev:dart_boost` — the one pubspec edit this installer
  ever makes, and only after an explicit yes. Unattended runs (no TTY, CI)
  skip the edit and say so rather than editing `pubspec.yaml` on a machine
  that never asked; the guidelines and the SDK's own MCP entry are still
  written regardless. `--no-rules` turns the whole feature off — no server, no
  procedure file, no dependency — and `update` remembers that choice instead
  of silently turning it back on.
- **`doctor` reports on rules.** The rules directory and whether it exists,
  how many rule files parsed and how many failed to, whether dart_boost is a
  dev dependency (and what it means if not — the server cannot start), the
  exact server command, and whether rules are enabled in `dart_boost.json`.
  Reported statically rather than probed: unlike `dart mcp-server`, the rules
  server is a stdio JSON-RPC process that blocks reading its own stdin and
  does not understand `--version`, so spawning it to check would just hang
  `doctor`. The real question — will an agent be able to start this? — has a
  static answer: only when dart_boost is a resolved dependency.
- **`update` no longer adopts agents on its own.** It configures exactly the
  agents recorded by the last `install`. An agent installed since then is
  reported — `Cursor was installed since the last run` — and left alone, rather
  than being configured silently. The old behaviour wrote guidelines and MCP
  config to agents that had never been selected, and because `update` skips the
  confirmation prompt by contract, an unattended run gave you nothing to say no
  to. Adding an agent is now a deliberate act: `install`, or `--agents=`. This
  also means an agent you deliberately left unticked stays unticked instead of
  being re-offered on every run.
- **State file split.** `dart_boost.json` now holds only what a human chose
  (agents, feature flags, trusted packages, whether rules are on); the
  observations a previous run recorded (resolved dependency versions, the
  fragments they produced, the last-seen SDKs) moved to
  `.dart_tool/dart_boost/state.json`, which is per-machine and already
  gitignored by `.dart_tool/` convention. Keeping them together meant a
  teammate on a different Flutter version rewrote the committed file on every
  `update`, and made drift reporting compare against whoever last committed
  rather than against your own previous run. A `dart_boost.json` written
  before the split (schema version 1) is migrated automatically on the next
  `install` or `update`: its observations are moved into the new machine-state
  file and it is rewritten in the new, choices-only shape — nothing to do by
  hand.

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

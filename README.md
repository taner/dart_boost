# dart_boost

[![pub package](https://img.shields.io/pub/v/dart_boost.svg)](https://pub.dev/packages/dart_boost)

Version-aware AI coding guidelines and one-command multi-agent wiring for Dart
and Flutter projects.

```sh
dart run dart_boost@ install
```

That reads your project, composes guidelines from the versions you actually
resolved, writes them into every AI agent you have installed, and points each
of those agents at the official `dart mcp-server`.

Nothing to add to your `pubspec.yaml`, and nothing left running. It writes
files and exits.

## What it writes

For each agent you select:

| Agent | Guidelines | MCP config | Key |
| --- | --- | --- | --- |
| Claude Code | `CLAUDE.md` | `.mcp.json` | `mcpServers` |
| Cursor | `AGENTS.md` | `.cursor/mcp.json` | `mcpServers` |
| GitHub Copilot | `AGENTS.md` | `.vscode/mcp.json` | `servers` |
| Codex | `AGENTS.md` | `.codex/config.toml` | `mcp_servers` |
| Antigravity | `AGENTS.md` | `.agents/mcp_config.json` | `mcpServers` |
| Gemini CLI | `GEMINI.md` | `.gemini/settings.json` | `mcpServers` |
| Zed | `AGENTS.md` | `.zed/settings.json` | `context_servers` |
| OpenCode | `AGENTS.md` | `opencode.json(c)` | `mcp` |
| Windsurf | `AGENTS.md` | `.windsurf/mcp.json` | `mcpServers` |

`install` detects which of these you actually have — from `PATH`, config
directories and project files — and preselects them; the rest are still
listed, unticked. `--agents=<keys>` skips detection and the prompt entirely:
`claude_code`, `cursor`, `copilot`, `codex`, `antigravity`, `gemini`, `zed`,
`opencode`, `windsurf`.

Guidelines go inside a `<dart-boost-guidelines>` block; everything you wrote
around it is left alone, and re-running replaces the block in place rather than
appending a second one. Several agents share `AGENTS.md`, so it is written once.

MCP config is **spliced, never re-serialized**: comments, formatting, key order
and trailing commas all survive. The spliced result is re-parsed before it is
written, and if it does not parse, that agent is skipped and reported with its
file untouched. A one-time `<file>.dart-boost.bak` is dropped before the first
modification, and every write is atomic.

Re-running is safe. A second `install` with the same inputs reports "already up
to date" and leaves `git status` empty.

## Why this and not a Boost port

Laravel Boost bundles three things: an MCP server, a curated guideline library,
and an installer that wires both into your agents. Two of those already exist in
the Dart ecosystem, and are better than anything a port would produce:

| Boost capability | Dart/Flutter equivalent |
| --- | --- |
| MCP server with ~11 introspection tools | **`dart mcp-server`**, in the SDK. ~24 tools — `analyze_files`, `lsp`, `run_tests`, `dart_fix`, `pub_dev_search`, `hot_reload`, `widget_inspector`, `get_runtime_errors`, `vm_service` — and it attaches to a *running* app over DTD. |
| Package-shipped guidelines | **Agent Skills**. `dart run skills@ get` reads your pubspec and installs into `.claude/skills/`, `.cursor/skills/`, and the rest. |
| Curated first-party library | **`flutter/agent-plugins`** and **`dart-lang/skills`**. |

So dart_boost ships **no MCP server of its own**. What is genuinely missing is
the other two thirds:

1. **A unified installer.** Wiring a project up today means `claude plugin
   install …` *and* `npx skills add …` *and* hand-editing `.vscode/mcp.json`
   *and* `git clone`-ing into `~/.cursor/plugins/local`. Nothing detects your
   agents and configures all of them. `package:skills` notably does not
   configure MCP servers at all.
2. **Version-aware composed guidelines.** Nothing conditions guidance on *your*
   resolved versions — Flutter 3.47 vs 3.44, Riverpod 2 vs 3, go_router 14 vs
   18 — or composes one project-tailored file. This is Boost's real
   differentiator and it had no Dart analog.

## How version keying works

Fragments live in a `guidelines/` tree, and a directory is selected by what your
project actually resolved:

```
guidelines/
  foundation.md          # always
  dart/core.md           # always
  dart/3.13/core.md      # keyed on the resolved Dart SDK minor
  flutter/core.md        # any Flutter project
  flutter/3.47/core.md   # keyed on the resolved Flutter SDK minor
  riverpod/core.md       # any version of the package
  riverpod/3/core.md     # only when the resolved major is 3
  riverpod/3/testing.md  # extra fragments in a version directory also land
```

**The version key is the major** — except below `1.0.0`, where pub treats the
*minor* as the breaking axis, so `0.4.2` keys on `0.4`. The two SDKs are keyed
on the minor instead — `3.13.2` keys on `3.13` — because that is where their
APIs move. The Dart key applies to *every* project, not just Flutter ones: a
Dart-only project has no Flutter version to key on, and language features still
arrive in a particular release.

There is deliberately **no range matching and no fallback to a nearest-lower
version**. A missing version directory contributes nothing. Guessing that
go_router 19 behaves like 18 is exactly the kind of confidently-wrong guidance
this package exists to avoid; the unversioned `core` fragment still applies.

Versions come from `.dart_tool/package_graph.json`, falling back to
`pubspec.lock` and then `pubspec.yaml`. Direct and transitive dependencies are
distinguished, and some packages (`http`, `path`, `test`, …) only contribute
guidance when you depend on them *directly* — otherwise every project in the
ecosystem would get guidance for packages its author never chose.

Where two packages in the same family overlap, one wins. A project on
`flutter_riverpod` also has `riverpod` in its graph, and emitting both produces
two overlapping and occasionally contradictory sections — so `flutter_riverpod`
suppresses `riverpod`, `flutter_bloc` suppresses `bloc`, and the generator half
of a codegen pair (`freezed`, `json_serializable`, `injectable`) suppresses its
annotation package. Both halves map to the same fragment directory, so nothing
is lost; the rule only decides which package supplies the version key. The one
suppression that does drop guidance is `mocktail` over `mockito`, where the two
genuinely disagree.

### What ships in 0.1.0

| Fragments | Version directories |
| --- | --- |
| `foundation`, `dart` | always composed; `dart` additionally keyed `3.12`, `3.13` (SDK minor) |
| `flutter` | `3.44`, `3.47` (SDK minor) |
| `riverpod` (incl. `flutter_riverpod`, `hooks_riverpod`) | `2`, `3` — each with a `testing` fragment |
| `bloc` (incl. `flutter_bloc`) | `7`, `8`, `9` |
| `go_router` | `14`, `15`, `16`, `17`, `18` |
| `freezed` | `2`, `3`, `4` |
| `dio` | `4`, `5` |
| `get_it` | `7`, `8`, `9` |
| `injectable` | `2`, `3` |
| `json_serializable` | unversioned |
| `testing`, `fvm`, `melos` | when the project has tests, an FVM pin, or a Melos workspace |

40 fragments in all. Version directories exist only where the API actually
diverged.

## FVM and monorepos

**FVM.** If the project is FVM-pinned, the pinned SDK's version is what keys the
`flutter/<minor>` fragment — not whatever `flutter` on your `PATH` happens to
be. The MCP entry gets that SDK's **absolute** `dart` path, because a bare
`dart` on `PATH` would attach the agent to the wrong SDK, silently. Every
command inside the composed guidelines is prefixed `fvm` to match. The pin is
read from `.fvmrc`, `.fvm/fvm_config.json` or the `.fvm/flutter_sdk` symlink;
no `flutter` process is spawned unless you pass `--probe-sdk`.

**Pub workspaces and Melos.** Reading and writing are separate: versions are
resolved from the `.dart_tool/` and `pubspec.lock` that actually describe the
package you pointed at, while `CLAUDE.md`, `AGENTS.md`, the MCP configs and
`dart_boost.json` are written **once at the repository root**. Nine copies of
`AGENTS.md`, one per member, is not a useful outcome.

A Melos repo additionally gets the `melos` fragment and a `melos exec --`
prefix on the commands the guidelines suggest, so an agent told to run the
tests runs them across the workspace rather than in one package.

## Third-party fragments

A dependency contributes guidance by shipping `guidelines/**/*.md` at its
package root — deliberately the sibling of the `skills/` directory
`package:skills` already established. Direct dependencies only.

**Nothing is read without explicit per-package opt-in.** This is text from an
arbitrary pub package headed straight for an agent's system prompt, so
discovering it and trusting it are two different steps:

```sh
$ dart run dart_boost@ install
...
Third-party guidelines
  These dependencies ship a guidelines/ tree that was NOT read: serverpod.
  Their text would go straight into an agent's system prompt, so each needs
  explicit opt-in: re-run with --trust=serverpod.

$ dart run dart_boost@ install --trust=serverpod
```

The opt-in is persisted to `dart_boost.json`, so `update` repeats it without
asking again — and a *new* untrusted dependency shows up as a fresh prompt
rather than being swept in with the ones you already approved. Trust is
per-package and never implied by anything else.

Fragments are keyed `<package>/<path within its guidelines tree>`, so
`serverpod`'s `guidelines/core.md` composes under `=== serverpod/core rules ===`
and is rendered against your project's facts like any bundled fragment.

A package can declare the contract it was written against:

```yaml
# guidelines/manifest.yaml
boost_facts_version: 1
```

A fragment declaring a version newer than the dart_boost you are running is
skipped with a warning, because it would branch on flags this release does not
define. The manifest is optional; without one, the fragment is composed.

## Writing a fragment

The template language is `if`/`else`/`end` plus `{{ variable }}`, and that is
all — version branching is the tree's job.

```markdown
<!--boost:if usesRiverpod3-->
Riverpod 3 removed `StateProvider`. Use `NotifierProvider`.
<!--boost:else-->
`StateNotifierProvider` still exists but prefer `NotifierProvider`.
<!--boost:end-->

Run `{{ dartRunCommand }} build_runner build -d` after editing providers.
```

Two rules make this work:

- **Fenced code blocks are masked.** Nothing inside a fence is ever touched, so
  code samples need no escaping. The corollary is that `{{ variables }}` in a
  fence are *not* substituted — put interpolated commands in inline code spans.
- **Directives are HTML comments**, so a fragment renders correctly unprocessed
  in a GitHub preview.

Condition flags: `isFlutterProject`, `isDartOnlyProject`, `isMonorepo`,
`isMelosWorkspace`, `isPubWorkspace`, `usesFvm`, `usesCodegen`, `hasTests`,
`hasFlutterVersion`, `hasDartVersion`. Plus one open-ended flag per resolved
package — `usesRiverpod`, `usesRiverpod3`, `usesGoRouter18` — so a fragment can
branch on a package it does not own.

Variables: `projectName`, `boostVersion`, `dartCommand`, `flutterCommand`,
`sdkCommand`, `dartRunCommand`, `pubGetCommand`, `pubAddCommand`, `testCommand`,
`analyzeCommand`, `formatCommand`, `workspacePrefix`, `dartVersion`,
`flutterVersion`, `flutterChannel`, `flutterMinor`. The command variables carry
the `fvm` and `melos exec --` prefixes the project needs, which is the whole
point of using them instead of writing `dart test`.

Nothing throws. An unknown flag is `false` plus a warning; an unknown variable
is left literal plus a warning; a broken fragment omits itself. A bad
fragment — especially a third-party one — must degrade, not abort your install.

## Overriding

Drop a file at `.ai/guidelines/<same path as the bundled fragment>.md` and it
replaces that fragment in place. A file matching no bundled fragment is added
ahead of everything else, so house rules outrank everything dart_boost ships.

Sources are layered `user overrides → core → conditional → detected packages →
third-party`, and the output carries `=== <key> rules ===` separators so you can
see which fragment produced which guidance.

## Skills hand-off

dart_boost writes guidelines and MCP config; `package:skills` fetches the agent
skills your dependencies ship. The two are complementary and deliberately not
merged, so after a successful install dart_boost offers the other half rather
than reimplementing it:

```sh
$ dart run dart_boost@ install
...
package:skills is a dependency of this project. Run `dart run skills get` to
fetch the skills your dependencies ship?
> Yes  No
```

How it is invoked depends on where `skills` already is: a resolved dependency
of the project runs `dart run skills get`, and a `skills` on `PATH` runs
`skills get`. Neither touches the network. The remote form, `dart run skills@
get`, resolves and downloads a package from pub.dev, so it is reachable **only**
behind an explicit `--skills` — `--yes` and CI accept the locally resolvable
forms and nothing else, because downloading a package is not something to do on
a machine that never asked for it. `--no-skills` suppresses the hand-off
entirely.

Running it is remembered in `dart_boost.json` as `delegateSkills`, so `update`
repeats it without asking again. Declining is remembered too — as a no, so the
question comes back next time rather than being settled forever. A hand-off
that could not run, or that failed, leaves the previous answer alone.

**It never fails an install.** `skills` being absent, declined, or exiting
non-zero is reported and nothing more: the guidelines and MCP config are
already on disk, and an install that wrote every file it promised has
succeeded.

## Commands

```sh
dart run dart_boost@ doctor    # every fact it resolved, and where each came from
dart run dart_boost@ compose   # print the composed guidelines, write nothing
dart run dart_boost@ install   # write guidelines + MCP config
dart run dart_boost@ update    # re-run with the choices saved by install
```

Global flags: `-C, --directory <path>`, `--dry-run`, `--verbose`, `--version`,
`--probe-sdk`.

`install` and `update` take `--agents=<keys>`, `--yes`, `--no-guidelines`,
`--no-mcp`, `--trust=<packages>` and `--[no-]skills`. `compose` takes `--keys`
to list what matched instead of printing the text.

Start with `doctor` if anything surprises you: it prints every resolved fact
next to the file it came from, so a wrong fragment is traceable to a wrong
lockfile rather than a mystery.

Also installable as a dev dependency (`dart run dart_boost:install`) or globally
(`dart pub global activate dart_boost`).

### Prompts and CI

Every prompt is skipped when there is no human to answer it: no TTY, or any of
`CI`, `CONTINUOUS_INTEGRATION`, `BUILD_NUMBER`, `GITHUB_ACTIONS`, `GITLAB_CI`,
`TF_BUILD` or `TEAMCITY_VERSION` set to anything other than `false` or `0`, or
a bare `TERM=dumb`. A TTY alone is not enough to assume a human: CI runners
routinely allocate one, which is exactly how a pipeline ends up blocked on a
multiselect nobody can see. `CI=false` opts back in.

Without a prompt the detected agents are used as they stand — the same thing
`--yes` does — so `install` is safe to run unattended in a workflow.

Interactively, `install` lists the files it is about to touch and asks once
before writing any of them:

```sh
About to write
  CLAUDE.md                    Claude Code
  AGENTS.md                    GitHub Copilot, Codex
  .mcp.json                    Claude Code MCP
  .vscode/mcp.json             GitHub Copilot MCP
Proceed?
```

That confirmation is skipped by `--yes`, by `--dry-run` (which writes nothing
anyway), in CI, and by `update`, whose whole contract is to repeat the answers
already on file without re-asking.

## State

`dart_boost.json` at the project root records what `install` chose, so `update`
can repeat it and report drift:

```jsonc
{
  "version": 1,
  "agents": ["claude_code", "copilot", "codex"],
  "features": { "guidelines": true, "mcp": true },
  "thirdPartyPackages": ["serverpod"],
  "delegateSkills": false,
  "dependencies": { "go_router": "18.2.0", "riverpod": "3.0.1" },
  "fragments": ["foundation", "dart", "dart/v3.13", "go_router/core", "go_router/v18"],
  "lastRun": { "flutter": "3.47.2", "dart": "3.13.2", "boostVersion": "0.1.0" }
}
```

Commit it. It is the record of what your team's agents were configured with,
and `update` diffs against it — an SDK bump shows up as
`Flutter 3.47.2 -> 3.44.9` rather than as guidance that quietly went stale.

`dependencies` is the direct dependency set as the last run resolved it, name
to version (`-` for an SDK, path or git dependency, which has none), and
`fragments` is the keys that run actually composed. Together they let `update`
report what moved, and what it meant:

```sh
Dependencies since the last run
+ go_router 18.2.0
  riverpod 2.6.1 -> 3.0.1  (different guidance applies)
- provider 6.1.2

Guidance changes
added: go_router/core, go_router/v18, riverpod/v3
no longer applies: riverpod/v2
```

Only upgrades that move the fragment key are listed — `3.0.1 -> 3.0.2` changes
nothing dart_boost composes and does not deserve a line — and *Guidance
changes* is the honest answer to "so what?", since most packages have no
fragment at all. Direct dependencies only: a transitive bump is pub's business,
not something you did between two runs.

Both keys are **nullable**, and `null` does not mean empty. A state file
written before dart_boost recorded them has no baseline, so `update` says
nothing about what changed rather than announcing every existing dependency as
newly added; it notes that the next run will be able to diff, and writes both
keys on its way out.

## Requirements

Dart SDK 3.7 or newer. Works on Dart-only and Flutter projects, on macOS, Linux
and Windows.

## Status

0.1.0. The machinery is complete and tested; the fragment library is the part
that keeps growing. Still to come: path-scoped rules and coverage of more of
the package ecosystem.

## License

MIT

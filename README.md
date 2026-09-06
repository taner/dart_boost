# dart_boost

Version-aware AI coding guidelines and one-command multi-agent wiring for Dart
and Flutter projects.

```sh
dart run dart_boost@ install
```

That reads your project, composes guidelines from the versions you actually
resolved, writes them into every AI agent you have installed, and points each
of those agents at the official `dart mcp-server`.

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
   install … `*and*` npx skills add … `*and* hand-editing` .vscode/mcp.json`
   *and* `git clone`-ing into `~/.cursor/plugins/local`. Nothing detects your
   agents and configures all of them. `package:skills` notably does not
   configure MCP servers at all.
2. **Version-aware composed guidelines.** Nothing conditions guidance on *your*
   resolved versions — Flutter 3.47 vs 3.2, Riverpod 2 vs 3, go_router 14 vs 16
   — or composes one project-tailored file. This is Boost's real differentiator
   and it had no Dart analog.

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

Guidelines go inside a `<dart-boost-guidelines>` block; everything you wrote
around it is left alone, and re-running replaces the block in place rather than
appending a second one. Several agents share `AGENTS.md`, so it is written once.

MCP config is **spliced, never re-serialized**: comments, formatting, key order
and trailing commas all survive. The spliced result is re-parsed before it is
written, and if it does not parse, that agent is skipped and reported with its
file untouched. A one-time `<file>.dart-boost.bak` is dropped before the first
modification.

If your project is FVM-pinned, the MCP entry gets the pinned SDK's absolute
path — bare `dart` on `PATH` would be the wrong SDK.

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
`--no-mcp` and `--trust=<packages>`.

Also installable as a dev dependency (`dart run dart_boost:install`) or globally
(`dart pub global activate dart_boost`).

## How guidelines are composed

Fragments live in a `guidelines/` tree and are selected by what your project
actually resolved:

```
guidelines/
  foundation.md          # always
  dart/core.md           # always
  flutter/core.md        # if it is a Flutter project
  flutter/3.47/core.md   # keyed on the SDK minor
  riverpod/core.md       # any version of the package
  riverpod/3/core.md     # only when the resolved major is 3
  riverpod/3/testing.md
```

The version key is the major, except below `1.0.0` where pub treats the *minor*
as breaking, so `0.4.2` keys on `0.4`. There is deliberately **no range matching
and no fallback to a nearest-lower version**: a missing version directory
contributes nothing.

Sources are layered `user overrides → core → conditional → detected packages →
third-party`, and the output carries` === <key> rules ===` separators so you can
see which fragment produced which guidance.

### Writing a fragment

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

Nothing throws. An unknown flag is `false` plus a warning; an unknown variable
is left literal plus a warning; a broken fragment omits itself. A bad fragment —
especially a third-party one — must degrade, not abort your install.

### Overriding

Drop a file at `.ai/guidelines/<same path as the bundled fragment>.md` and it
replaces that fragment in place. A file matching no bundled fragment is added
ahead of everything else.

### Third-party fragments

A dependency contributes by shipping `guidelines/**/*.md` at its package root —
deliberately the sibling of the `skills/` directory `package:skills` already
established. Direct dependencies only.

Nothing is read without **explicit per-package opt-in** (`--trust=<package>`,
persisted to `dart_boost.json`): this is text from an arbitrary pub package
headed for an agent's system prompt. A package can declare
`guidelines/manifest.yaml` with `boost_facts_version:`; a fragment declaring a
newer contract than we implement is skipped with a warning.

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
  "lastRun": { "flutter": "3.47.2", "dart": "3.13.2", "boostVersion": "0.1.0" }
}
```

## Status

Machinery complete; the fragment library is deliberately small. The bundled
fragments (`foundation`, `dart`, `flutter`, `flutter/3.47`, `riverpod` 2 and 3,
`testing`, `fvm`, `melos`) exist to prove composition end to end — the full
library, and interactive prompts, `skills` delegation and path-scoped rules,
are still to come.

## License

MIT

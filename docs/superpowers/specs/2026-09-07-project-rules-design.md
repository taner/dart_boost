# Project rules for dart_boost

Design, 2026-09-07. Status: approved, not implemented.

## The gap

dart_boost composes guidelines: version-keyed guidance about the *ecosystem*,
loaded upfront into every agent. That is one of three layers Laravel Boost
offers, and dart_boost has only the first.

| Layer | Teaches the agent | Loaded | dart_boost today |
| --- | --- | --- | --- |
| Guidelines | how to write Dart/Flutter | upfront, always | yes |
| Skills | detailed task patterns | on demand | delegated to `package:skills` |
| **Project rules** | **how to write *this* application** | when the edited file matches | **missing** |

Nothing in dart_boost captures a decision your team made. Every new session
relearns that money is integer cents, or rediscovers why one directory does
things differently, or does not -- and writes the wrong code. The README already
names this as the next feature, under the name "path-scoped rules".

See `docs/reference/laravel-boost.md` for the captured Boost documentation this
design is measured against.

## Scope

Two capabilities:

1. **`record_rule`** -- an agent records a durable, glob-scoped rule mid-session.
2. **`infer-conventions`** -- a procedure that bootstraps rules from a codebase
   that already exists.

Plus two supporting changes they require:

3. dart_boost gains an **MCP server** and becomes a **dev dependency**.
4. `dart_boost.json` **splits** into committed choices and per-machine state.

### Out of scope

- **A documentation search API.** Boost's `search-docs` is backed by a hosted
  service with 17,000+ embedded documents. It is a genuine ecosystem gap and a
  far larger undertaking: ingestion, hosting, embeddings, and an ongoing service.
  Separate project, if ever.
- **Porting Boost's other eight MCP tools.** They exist because PHP has no
  first-party MCP server. `dart mcp-server` already covers that ground with ~24
  tools, and reimplementing it badly is exactly what dart_boost was designed not
  to do.
- **Boost's `syncManaged`/`clearManaged`.** In Boost, some rule files are owned
  and rewritten by Boost itself. In dart_boost every rule is user- or
  agent-authored, which removes an entire ownership axis. Nothing is lost.
- **A configurable rules directory.** `.ai/rules/` is fixed. A configurable path
  buys nothing and gives agents one more thing to get wrong.

## Approach

Two capabilities, two different delivery mechanisms, chosen by their nature.

`record_rule` is an **action taken mid-session**. It must be callable, and its
tool description is what makes an agent reach for it at the right moment.
Guidance buried in a 36 KB upfront file competes with everything else in the
context window; an entry in the tool list does not. It is an MCP tool.

`infer-conventions` is a **procedure the agent follows**, run roughly once in a
project's lifetime. Procedures are instructions, not actions. Shipping it as a
tool would pay its description cost in *every session for the life of the
project* in exchange for a single use. It is a markdown file.

That choice also widens reach. Boost ships `infer-conventions` as an Agent
Skill, which only works in agents that support skills. dart_boost already writes
guidelines to all nine of its agents, so a markdown file referenced from the
guidelines block reaches all nine with no per-agent work.

## Rule files

### Format

Rules live in `.ai/rules/`, **committed to source control**. `.ai/` is already
dart_boost's namespace for user overrides, so this is a sibling of
`.ai/guidelines/`.

```markdown
<!-- .ai/rules/models.md -->
---
paths:
  - lib/models/**
---

# Models

## Money is stored as integer cents

All money values are `int` cents, never `double`. Formatting happens at the
presentation layer via `MoneyFormatter`. A `double` here loses precision in
currency arithmetic, and the rounding errors surface only at invoice totals.
```

Frontmatter carries a `paths` list and nothing else. The body is a `#` heading
for the area followed by one `##` section per rule.

### The index

`.ai/rules/index.md` is generated, never hand-edited:

```markdown
# Project Rules Index

Before planning or editing a file, find the row whose globs match its path and
read that rule file.

| Applies to | Rule file |
| --- | --- |
| `lib/models/**` | `.ai/rules/models.md` |
| `lib/widgets/**` | `.ai/rules/widgets.md` |
| `test/**` | `.ai/rules/testing.md` |
```

The index is the load-bearing idea. Without it, every rule enters context in
every session and path-scoping achieves nothing. With it, an agent reads one
small table and then only the rule files that match the file it is about to
touch.

**Rows are sorted deterministically** -- by rule file path, then by glob within a
row. A committed file that reshuffles on every write is a permanent source of
git noise, so ordering is a tested property, not an incidental one.

### Area routing

Ported from Boost's `RuleRepository`, which solves this well.

1. **Meaningful segments.** Split the glob on `/`; drop segments that are empty
   or contain `*` or `.`. So `lib/models/**` gives `[lib, models]`, and
   `test/**/*_test.dart` gives `[test]`.
2. **Area key.** Those segments rejoined with `/`. Two globs with the same area
   key belong in the same file.
3. **Target file.** If an existing rule file lists this exact glob, or any glob
   with the same area key, append to it. Otherwise create a new file.
4. **Filename.** Try the last 1 segment as a slug, then the last 2, then the
   last 3, and take the first not already in use. `lib/src/widgets/**` becomes
   `widgets.md`, falling back to `src-widgets.md` only on collision, then
   `widgets-2.md`. Shortest name that stays unambiguous.
5. **No segments** (a glob like `**`) falls back to `general.md`.

Worked examples:

| Glob | Segments | File |
| --- | --- | --- |
| `lib/models/**` | `lib, models` | `models.md` |
| `lib/models/*.dart` | `lib, models` | `models.md` (same area, appends) |
| `test/**` | `test` | `test.md` |
| `lib/src/widgets/**` | `lib, src, widgets` | `widgets.md` |
| `packages/ui/lib/widgets/**` | `packages, ui, lib, widgets` | `widgets.md`, else `lib-widgets.md` |
| `**` | none | `general.md` |

## How rules reach the agent

The composed guidelines gain one short stanza, emitted **unconditionally**:

> Before planning or editing any file, check `.ai/rules/index.md` if it exists.
> Find the row whose globs match the file's path and read that rule file. These
> are this project's own decisions and they override general guidance.
>
> When asked to infer this project's conventions, read `.ai/infer-conventions.md`
> and follow it.

Two sentences, one stanza. The second is what makes `infer-conventions`
discoverable without costing a slot in the tool list.

Unconditional, rather than behind a `hasProjectRules` condition flag, because a
flag creates a lag: the first recorded rule would not be announced to agents
until the next `install` or `update`. The stanza is one sentence and tolerates a
missing file, so the cost of always emitting it is negligible and the behaviour
is correct from the first rule onward.

## The MCP server

### Dependency

`package:dart_mcp`, published by labs.dart.dev, the publisher behind
`dart mcp-server` itself. SDK constraint `^3.7.0`, which is exactly dart_boost's
existing floor, and its own dependencies (`json_rpc_2`, `stream_channel`,
`async`, `collection`, `meta`, `stream_transform`) are all uncontroversial.

Servers are built by extending `MCPServer` with the `ToolsSupport` mixin.

### The tool

One tool, `record_rule`, with three required string parameters:

| Parameter | Meaning |
| --- | --- |
| `glob` | Files the rule applies to, e.g. `lib/models/**`. Routes the rule to an area file and is how agents find it later. |
| `title` | A short, specific heading, e.g. "Money is stored as integer cents". |
| `note` | A few lines stating the rule plainly. |

The tool *description* is prompt engineering and deserves the same care Boost
gave it: record a settled decision, a non-obvious trap, or a standing
constraint; keep it to a few lines; record only what you would want to read in
three months; do not record secrets, transient state, or anything already
obvious from the code.

### Entry point and wiring

`bin/mcp.dart` provides `dart run dart_boost:mcp`. It is spliced into the MCP
configs dart_boost already writes, as a second server beside the SDK's:

```jsonc
{
  "mcpServers": {
    "dart":       { "command": "dart", "args": ["mcp-server"] },
    "dart_boost": { "command": "dart", "args": ["run", "dart_boost:mcp"] }
  }
}
```

FVM needs no new work: dart_boost already resolves the absolute pinned `dart`
path for the existing entry, and the same value applies. The existing splicers
already add a key without disturbing comments, key order or trailing commas, and
already re-parse before writing.

### Becoming a dev dependency

`dart run dart_boost:mcp` resolves only if dart_boost is a resolved dependency of
the project. When rules are enabled and it is not one, `install` runs
`dart pub add dev:dart_boost` through the existing `ProcessRunner`, behind an
explicit confirmation, letting pub edit the YAML rather than splicing
`pubspec.yaml` directly. This mirrors the existing `skills` hand-off.

The README's "nothing to add to your `pubspec.yaml`" becomes conditional rather
than false: still true when rules are off.

**Rules default to enabled**, but the dev dependency is never added unasked.
When there is no one to confirm -- `--yes`, or any of the CI conditions
`install` already recognises -- and dart_boost is not already a dependency, the
rules wiring is **skipped and reported**, not silently applied. Editing
`pubspec.yaml` on a machine that never asked is the same class of action as
downloading a package unasked, which the existing `--skills` handling already
refuses to do. The guidelines and MCP config still get written; only the rules
wiring is held back.

`update` repeats the saved `rules` choice and does not enable rules that were
previously off. A feature that turns itself on during an unattended `update`,
and edits `pubspec.yaml` doing it, is exactly the surprise this project avoids
elsewhere.

This also closes a reproducibility hole that exists today. `dart run dart_boost@
install` resolves the *latest* dart_boost from pub.dev on every run, so two
developers installing a month apart compose from different fragment libraries
and get different `CLAUDE.md` files. Pinned in `pubspec.lock`, everyone composes
from the same tree.

## infer-conventions

`install` writes `.ai/infer-conventions.md`, and the guidelines stanza points at
it: when the user asks to infer conventions, read that file and follow it.

The procedure sweeps the codebase across a checklist -- state management, widget
composition, navigation and routing, error handling, async and streams, testing
patterns, code generation, project layout -- then makes an open-ended pass for
base classes, shared mixins and module boundaries.

Four rules govern what it records, taken from Boost because each one earns its
place:

- Document what the code **actually does**, not what it should do.
- Record only **well-supported, non-default** conventions.
- **Skip anything the linter already enforces.** For Dart that means never
  restating `analysis_options.yaml`.
- **Report genuinely mixed patterns** rather than recording them as rules.

Every discovered convention is presented with its supporting evidence for
approval before anything is written.

The procedure **terminates in `record_rule` calls**. It writes no files itself.
That is why the two ship together: one is the bootstrap path for the other, and
neither needs to know the other's implementation.

## State split

`dart_boost.json` currently mixes team choices with per-machine observations.
`lastRun` records the running machine's SDK versions, so committing the file
makes every teammate on a different Flutter version rewrite it -- a permanent
merge-conflict generator in a file the README tells you to commit.

Schema version 2 splits them:

**`dart_boost.json`** -- choices. Committed.

```jsonc
{
  "version": 2,
  "agents": ["claude_code", "codex", "copilot"],
  "features": { "guidelines": true, "mcp": true },
  "thirdPartyPackages": ["serverpod"],
  "delegateSkills": false,
  "rules": { "enabled": true }
}
```

**`.dart_tool/dart_boost/state.json`** -- observations. Not committed;
`.dart_tool/` is already gitignored by convention in every Dart project, which is
precisely where Dart expects tool-generated machine state.

```jsonc
{
  "version": 2,
  "dependencies": { "go_router": "18.2.0", "riverpod": "3.0.1" },
  "fragments": ["foundation", "dart", "dart/v3.13", "go_router/core"],
  "lastRun": { "flutter": "3.47.2", "dart": "3.13.2", "boostVersion": "0.2.0" }
}
```

This is a correctness fix, not only tidiness. Drift means "what changed since
**I** last ran this". Today, when a teammate installs and commits, your `update`
diffs against **their** run and reports changes you did not make.

**Migration.** Reading a v1 file writes both v2 files, preserving every value.
The existing `null` versus empty distinction on `dependencies` and `fragments`
is preserved exactly: `null` means "predates this field" and must not be read as
"a project with no dependencies", or the next `update` announces every existing
dependency as newly added.

## Components

| Component | Responsibility |
| --- | --- |
| `lib/src/rules/rule_repository.dart` | `write(glob, title, note)`, `writeIndex()`, area routing, parsing. Uses the `FileSystem` abstraction, so it is testable in memory. Knows nothing about MCP. |
| `lib/src/rules/rule_file.dart` | Frontmatter parse and render. |
| `lib/src/mcp/rules_server.dart` | `MCPServer` + `ToolsSupport`, exposing `record_rule`. The only file that touches `package:dart_mcp`. |
| `bin/mcp.dart` | Entry point for `dart run dart_boost:mcp`. |
| `lib/src/cli/commands/rules_command.dart` | `dart run dart_boost rules index` -- regenerate the index. |
| `lib/src/state/machine_state.dart` | The gitignored half of the state split. |
| `lib/src/state/boost_state.dart` | Reduced to choices; gains `rules`; v1 to v2 migration. |
| `lib/src/assets/` | Ships `.ai/infer-conventions.md`. |
| `lib/src/writers/` | Writes `.ai/infer-conventions.md`; MCP writer gains the second server entry. |

## Data flow

```
record   agent -> record_rule(glob, title, note) -> normalize glob
               -> resolve target file (exact glob, else area key, else new)
               -> append or create -> regenerate index.md -> return path

read     guidelines stanza -> agent reads .ai/rules/index.md
               -> matches its file's path against the table
               -> reads only the matching rule files

infer    user asks -> agent reads .ai/infer-conventions.md -> sweeps checklist
               -> presents findings with evidence for approval
               -> calls record_rule per approved convention
```

## Error handling

dart_boost's existing contract is that nothing throws and a broken input
degrades rather than aborting. Rules follow it.

- **Input validation.** Empty or missing `glob`, `title` or `note` returns a
  structured error naming exactly which are missing -- an MCP error result, never
  a thrown exception. A tool that crashes the server is worse than one that says
  no.
- **Glob normalization.** Absolute paths become relative to the project root,
  backslashes become forward slashes for Windows, and a leading `/` is stripped.
- **Escaping globs are rejected.** A glob resolving outside the project root
  (`../`) is refused; rules describe this project.
- **Malformed rule files** are skipped during index regeneration with a warning,
  and are never rewritten or deleted. Same contract as a broken guideline
  fragment omitting itself.
- **The index is regenerated wholesale**, so hand edits to it are lost by design.
  A hand-added rule *file* is picked up by the next write or by
  `dart run dart_boost rules index`.
- **Atomic writes** via the existing `AtomicWriter`, so a crash cannot leave a
  truncated rule file.
- **Concurrency self-heals.** Two agents recording at once may race on the index,
  but since the index is rebuilt from whatever is on disk, the loser's file is
  picked up on the next write. No locking.
- **`doctor` probes the server** the way it already probes `dart mcp-server`, so
  an unresolvable dev dependency surfaces as a diagnostic rather than a silently
  dead server in someone's editor.
- **`"rules": { "enabled": false }`** registers no tool, writes no MCP entry and
  emits no guidelines stanza.

## Testing

Matching the existing suite: hermetic, in-memory, no network, no subprocesses.

- **Area routing table test** -- glob to expected filename, covering the
  collision fallback chain and the append-to-existing-area path.
- **Deterministic index ordering** -- an explicit test that recording rules in
  different orders produces byte-identical indexes. This is a committed file;
  reshuffling rows would be permanent git noise.
- **Frontmatter round-trip, CRLF included.** dart_boost already pins fixtures
  `-text` and round-trips CRLF through both splicers; rules must not be the one
  thing that breaks on Windows.
- **MCP tool tested in process.** `package:dart_mcp` connects client and server
  over stream channels, so `record_rule` is exercised without spawning a
  subprocess.
- **Migration tests** -- a v1 combined file splits into two v2 files with values
  preserved, and a v1 file with `null` `dependencies`/`fragments` still behaves.
- **Install integration** -- rules on gives dev dependency, MCP entry and stanza;
  rules off gives none of the three; a re-run reports "already up to date" and
  leaves `git status` empty.
- **Asset manifest guard** extended to cover `.ai/infer-conventions.md`.
- **Rejection tests** for escaping globs and for each missing-parameter case.

## Risks

- **`package:dart_mcp` is 0.5.2 and self-described as experimental, likely to
  evolve quickly.** Mitigated by confining every MCP contact to
  `rules_server.dart`: the repository knows nothing about MCP, so a breaking
  change upstream is a one-file fix, and `rules index` keeps working regardless.
- **A second MCP server costs context in every session.** Mitigated by shipping
  exactly one tool, and by keeping `infer-conventions` out of the tool list.
- **The dev-dependency requirement changes dart_boost's install story.**
  Mitigated by making it conditional on rules being enabled, and by an explicit
  confirmation before `dart pub add` runs.
- **Agents may not consult the index reliably.** This is the assumption the whole
  design rests on, and it is Boost's assumption too. If it proves weak the
  fallback is to inline short rules directly into the guidelines block and accept
  the context cost, but that should be measured before it is built.

## Documentation

The README gains a Project rules section and loses the "still to come:
path-scoped rules" line. The state section is rewritten for the split, and the
"nothing to add to your `pubspec.yaml`" claim is qualified. `CHANGELOG.md` gets a
0.2.0 entry. `VERIFICATION.md`'s stale test count (293; the suite is now 409) is
corrected as part of the same pass.

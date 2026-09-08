# Example

A short session against an existing Dart or Flutter project. Nothing here is
invented — this is what the commands actually print.

## 1. Install

Run it in the project you want configured:

```sh
dart run dart_boost@ install
```

It reads what your project resolved, composes guidelines from those versions,
and writes them into every agent it finds:

```text
Guidelines
8 fragments: foundation, project, dart, dart/v3.13, flutter, flutter/v3.47, go_router/core, go_router/v18
+ CLAUDE.md                    written  (Claude Code)
+ .ai/infer-conventions.md     written

MCP
dart mcp-server
+ .mcp.json                    written  (Claude Code)
+ dart_boost (rules)           dart_boost is already a dev dependency
```

Those eight fragments are chosen by *your* resolved versions. A project on
go_router 18 gets `go_router/v18`; one on 14 gets `go_router/v14`; one on a
version with no fragment gets the unversioned `go_router/core` and nothing
guessed.

Guidelines land inside a `<dart-boost-guidelines>` block, so anything you wrote
around them survives. Re-running replaces the block in place:

```text
- CLAUDE.md                    already up to date  (Claude Code)
```

**One confirmation.** Project rules need an MCP server, and
`dart run dart_boost:mcp` only resolves once dart_boost is a dependency, so the
first run asks before adding itself:

```text
Run `dart pub add dev:dart_boost` to add it as a dev dependency so agents can
record project rules?
```

Say no, or pass `--no-rules`, and everything else is still written. On CI or
under `--yes` it never asks and never adds — it reports what to run instead.

## 2. Record a rule

Now tell your agent something worth keeping:

> Remember that all money values are stored as integer cents, never doubles.

It calls the `record_rule` tool, and dart_boost files it:

```markdown
<!-- .ai/rules/models.md -->
---
paths:
  - lib/models/**
---

# Models

## Money is stored as integer cents

All money values are int cents, never double.
```

and regenerates the index that makes it discoverable:

```markdown
<!-- .ai/rules/index.md -->
# Project Rules Index

Before planning or editing a file, find the row whose globs match its path and read that rule file.

| Applies to | Rule file |
| --- | --- |
| `lib/models/**` | `.ai/rules/models.md` |
```

The index is the point. Agents are told to check it before editing any file and
read only the matching rows, so rules for code you are not touching stay out of
the context window. Commit `.ai/rules/` — it is shared with your team.

## 3. Bootstrap rules from code you already wrote

For a project with years of conventions in it, ask:

> Use the infer-conventions procedure

The agent sweeps state management, widget composition, routing, error handling,
async, testing, codegen and layout; skips anything `analysis_options.yaml`
already enforces; reports genuinely mixed patterns instead of recording them;
and presents each convention with evidence for your approval before writing.

## 4. Check what it resolved

```sh
dart run dart_boost doctor
```

```text
Rules
  directory             .ai/rules
  rule files            1 rule file parsed
  dev dependency        yes (dev)
  server command        dart run dart_boost:mcp
  enabled               yes
```

`doctor` prints every fact it resolved next to the file it came from, so a
surprising fragment is traceable to a lockfile rather than a mystery.

## Other commands

```sh
dart run dart_boost@ compose        # print the guidelines, write nothing
dart run dart_boost@ install --dry-run
dart run dart_boost rules index     # rebuild the index after a hand-edit
dart run dart_boost@ update         # re-run with the choices install saved
```

See the [README](https://pub.dev/packages/dart_boost) for version keying,
overrides, third-party fragments and the full flag list.

# dart_boost

A Dart CLI on pub.dev: installs version-aware AI coding guidelines and MCP config
into nine coding agents, and records a project's own decisions as glob-scoped
rules under `.ai/rules/`.

## What this project does

`openspec/specs/` is the current truth — read it there, not from git history.
`openspec view` shows specs and in-flight changes; `openspec list --specs` lists
capabilities. Today: `project-rules`, `guidelines-composition`, `agent-wiring`.

## How changes get built

OpenSpec owns *what* the project does. Superpowers owns *how* a change gets
built. They do not overlap, and each change uses both:

1. **`superpowers:brainstorming`** to shape the change. Write the resulting spec
   into the OpenSpec change folder — **not** into `docs/superpowers/specs/`.
2. **`superpowers:writing-plans`** for the implementation plan, written into the
   same change folder rather than `docs/superpowers/plans/`.
3. **`superpowers:subagent-driven-development`** to build it, with a review after
   each task and a whole-branch review at the end.
4. **After the branch merges, archive the change** so `openspec/specs/` becomes
   true again. This step is not optional — skipping it is what makes a repo stop
   being able to answer "what does this do?". A plan whose boxes are unticked and
   a spec that still says "not implemented" have both happened here before.

`docs/superpowers/` holds the project-rules change from before this setup. It is
history, not current truth; do not add to it.

## Constraints that bind every change

- Dart SDK floor is `^3.7.0`. Do not raise it.
- Nothing throws: malformed input degrades with a warning, never aborts a command.
- Every user-file write goes through `AtomicWriter` (temp file + rename).
- **Bundled assets are never dot-prefixed.** `dart pub publish` strips
  dot-prefixed paths, so a `.ai/` tree inside this package would work locally and
  be absent from the release. `guidelines/` and `assets/` are the payload trees;
  `tool/verify_assets.dart` guards them and must stay green.
- `dart format` clean and `dart analyze --fatal-infos` clean before any commit.
- Tests are hermetic: no network, no subprocesses outside `FakeProcessRunner`.
- Doc comments explain **why** a decision was made, not what the code does.

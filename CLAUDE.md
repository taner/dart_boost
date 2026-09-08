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
built.

**Always: an OpenSpec change. Only when architectural: a superpowers plan.**
Every change gets an OpenSpec change folder, because that is the mechanism that
keeps `openspec/specs/` true. The heavy plan-and-subagent machinery is for
architectural work; a ten-task plan for a six-line fix is waste.

1. **`superpowers:brainstorming`** to shape the change and get approval. Its
   classification decides the rest:
   - **bounded** — author the OpenSpec change directly (`proposal.md`, the delta
     under `specs/<capability>/`, `tasks.md`), then implement with TDD. No
     superpowers plan document.
   - **architectural** — also run **`superpowers:writing-plans`**, writing the
     plan into the same change folder, then
     **`superpowers:subagent-driven-development`** to build it with a review
     after each task and a whole-branch review at the end.
2. **After the branch merges, `openspec archive <change>`** so
   `openspec/specs/` becomes true again. This step is not optional — skipping it
   is what makes a repo stop being able to answer "what does this do?". A plan
   whose boxes are unticked and a spec still saying "not implemented" have both
   happened here.

Never write to `docs/superpowers/specs/` or `docs/superpowers/plans/`. Those
hold the project-rules change from before this setup — history, not truth.

### Two things that will bite you

**Brainstorming's "bounded" path says no spec file. That means no *superpowers*
design doc — it does not mean skip the OpenSpec change.** The change folder is
the mechanism that updates the specs, not design ceremony. Author it anyway.

**`ADDED` vs `MODIFIED` in a delta spec.** `MODIFIED` requires the requirement
header to already exist verbatim in the main spec; a *new* requirement inside an
existing capability is `ADDED`. Get it wrong and archive refuses the delta. Run
`openspec validate <change>` before you start implementing — it reports exactly
this as `Archive would refuse this delta`, and it is far cheaper to learn then
than at the end.

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

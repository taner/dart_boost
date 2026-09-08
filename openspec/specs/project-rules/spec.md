## Purpose

Capture a project's own decisions as durable, glob-scoped rules that every AI
agent inherits, so a settled decision is explained once rather than re-derived
in every session. Guidelines describe the Dart/Flutter ecosystem; project rules
describe *this* codebase.

## Requirements

### Requirement: Rules are stored as glob-scoped markdown under `.ai/rules/`

Each rule file SHALL carry a `paths:` frontmatter list of globs and one `##`
section per rule. Rule files MUST be committed to source control, so rules are
shared with the team rather than being personal to one agent session.

#### Scenario: Recording the first rule in an area
- **WHEN** a rule is recorded for a glob whose area has no file yet
- **THEN** a new `.ai/rules/<area>.md` is created, named for the shortest
  unambiguous slug derived from the glob's non-wildcard segments

#### Scenario: Recording a second rule in the same area
- **WHEN** a rule is recorded for a glob whose area already has a file
- **THEN** the rule is appended to that file, existing content is preserved
  verbatim, and the glob is added to `paths:` only if not already present

### Requirement: An index makes rules discoverable without loading all of them

`.ai/rules/index.md` SHALL be a generated glob-to-file table, and MUST NOT be
hand-edited. It is the mechanism that keeps path-scoping meaningful: an agent
reads one small table and then only the rule files matching the file it is about
to touch.

#### Scenario: The index is regenerated on every recorded rule
- **WHEN** a rule is recorded
- **THEN** the index is rebuilt from the rule files present on disk

#### Scenario: The index is deterministically ordered
- **WHEN** the same rules are recorded in different orders
- **THEN** the resulting index is byte-identical, so a committed file does not
  churn in version control

#### Scenario: A hand-written rule file is invisible until indexed
- **WHEN** a rule file is added by hand rather than through the tool
- **THEN** it does not appear in the index until `dart run dart_boost rules index`
  regenerates it

### Requirement: Agents are told to consult the index before editing

A `project` guidelines fragment SHALL be composed into every project
unconditionally, so the instruction is present from the first run before any
rule exists.

#### Scenario: Composing guidelines for any project
- **WHEN** guidelines are composed
- **THEN** the output contains a `=== project rules ===` section instructing the
  agent to check `.ai/rules/index.md` before planning or editing a file, and to
  read only the rows whose globs match that file's path

### Requirement: Rules are recorded through a callable tool

Recording is an action taken mid-session, so it MUST be exposed as a callable
MCP tool rather than as prose. `dart run dart_boost:mcp` SHALL serve exactly one
tool, `record_rule`, taking a required `glob`, `title` and `note`, and SHALL NOT
terminate on a malformed request.

#### Scenario: A glob that resolves outside the project root
- **WHEN** `record_rule` is called with a glob that escapes the project root, or
  with an absolute path not genuinely under it
- **THEN** the call returns an error result naming the problem, no file is
  written, and the server remains available

#### Scenario: A malformed request
- **WHEN** `record_rule` is called with a missing or wrong-typed argument
- **THEN** an error result is returned and the server remains available

#### Scenario: Rules disabled
- **WHEN** `rules.enabled` is false in `dart_boost.json`
- **THEN** the server registers no tools and still initialises cleanly

### Requirement: Enabling rules never edits `pubspec.yaml` without consent

`dart run dart_boost:mcp` resolves only when dart_boost is a dependency of the
target project, so enabling rules requires adding one. That edit MUST be
confirmed by a human, and MUST NOT happen on an unattended run.

#### Scenario: Unattended run without the dependency present
- **WHEN** `install` runs under `--yes` or in CI and dart_boost is not already a
  dependency
- **THEN** the rules wiring is skipped and reported with what to run next, while
  guidelines and the SDK's own MCP entry are still written

#### Scenario: The dependency is already present
- **WHEN** dart_boost is already a resolved dependency
- **THEN** no confirmation is requested and the rules MCP entry is written

### Requirement: Existing conventions can be bootstrapped into rules

`.ai/infer-conventions.md` SHALL ship a procedure that sweeps an existing
codebase and proposes conventions for approval before any rule is recorded.

#### Scenario: Inferring conventions
- **WHEN** an agent is asked to infer the project's conventions
- **THEN** it documents what the code actually does, records only well-supported
  non-default patterns, skips anything the linter already enforces, reports
  genuinely mixed patterns instead of recording them, and presents each finding
  with evidence for approval before recording anything

### Requirement: A malformed rule file degrades rather than breaking

A rule file that cannot be parsed MUST be skipped and left byte-identical on
disk. It MUST NOT abort the command that encountered it.

#### Scenario: A rule file with invalid frontmatter
- **WHEN** the rules directory contains a file that cannot be parsed
- **THEN** it is skipped, left byte-identical on disk, and reported by
  `rules index` and `doctor`; it never aborts a command

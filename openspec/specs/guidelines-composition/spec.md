## Purpose

Compose one project-tailored guidelines document from the SDK and package
versions a project actually resolved, so agents receive guidance that matches
the APIs in front of them rather than generic advice that may not compile.

## Requirements

### Requirement: Fragments SHALL be selected by resolved version

A fragment directory MUST be chosen from what the project actually resolved. The
version key SHALL be the major, except below `1.0.0` where pub treats the minor
as the breaking axis, and the two SDKs SHALL key on the minor because that is
where their APIs move.

#### Scenario: A package with a version-keyed fragment
- **WHEN** a project resolves a package that ships a fragment for its major
- **THEN** both the unversioned `core` fragment and the version-keyed fragment
  are composed

#### Scenario: A version with no fragment directory
- **WHEN** a project resolves a version for which no directory exists
- **THEN** nothing version-specific is contributed; there MUST be no range
  matching and no fallback to a nearest-lower version, because guessing that a
  newer major behaves like an older one produces confidently wrong guidance

### Requirement: Versions SHALL be read, never guessed

Resolution MUST come from `.dart_tool/package_graph.json`, falling back to
`pubspec.lock` and then `pubspec.yaml`. Direct and transitive dependencies MUST
be distinguished, and some packages SHALL contribute only when depended on
directly.

#### Scenario: An FVM-pinned project
- **WHEN** the project pins a Flutter SDK via FVM
- **THEN** the pinned SDK's version keys the fragment, not whatever `flutter` is
  on `PATH`

### Requirement: Rendering SHALL never throw

A fragment MUST degrade rather than abort an install.

#### Scenario: An unknown flag or variable
- **WHEN** a fragment references a condition flag or variable that does not exist
- **THEN** the flag is treated as false or the variable is left literal, a
  warning is emitted, and composition continues

#### Scenario: A broken fragment
- **WHEN** a fragment cannot be rendered
- **THEN** it omits itself and the remaining fragments still compose

### Requirement: Third-party fragments MUST be opt-in per package

Text from an arbitrary pub package goes straight into an agent's system prompt,
so discovering it and trusting it SHALL be separate steps.

#### Scenario: An untrusted dependency ships guidelines
- **WHEN** a direct dependency ships a `guidelines/` tree that has not been
  trusted
- **THEN** it is reported as available but NOT read, and requires an explicit
  per-package opt-in that is persisted for later runs

### Requirement: User overrides SHALL outrank bundled fragments

A file a project places under `.ai/guidelines/` MUST take precedence over the
fragment it matches, and a file matching nothing bundled MUST still be composed.

#### Scenario: An override matching a bundled fragment
- **WHEN** `.ai/guidelines/<same path>.md` exists
- **THEN** it replaces that bundled fragment in place

#### Scenario: An override matching nothing bundled
- **WHEN** an override matches no bundled fragment
- **THEN** it is added ahead of everything else, so house rules outrank
  everything shipped

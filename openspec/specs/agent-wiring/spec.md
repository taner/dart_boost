## Purpose

Detect the coding agents a developer actually has and configure all of them in
one command, writing guidelines and MCP server entries without disturbing what
the developer wrote around them.

## Requirements

### Requirement: Guidelines MUST be written without destroying user content

Guidelines SHALL be written inside a sentinel block. Content outside that block
MUST be preserved exactly, and a re-run MUST replace the block in place rather
than appending a second one.

#### Scenario: A file with user content around the block
- **WHEN** an agent's guidelines file has user-authored text before and after the
  block
- **THEN** that text survives the write byte-for-byte

#### Scenario: Agents sharing one guidelines file
- **WHEN** several selected agents share the same file name
- **THEN** the file is written once

### Requirement: MCP config MUST be spliced, never re-serialised

Comments, formatting, key order and trailing commas MUST survive. The spliced
result SHALL be re-parsed before it is written.

#### Scenario: A config that fails to re-parse after splicing
- **WHEN** the spliced output does not parse
- **THEN** that agent is skipped and reported, its file is left byte-identical,
  and the run exits non-zero

#### Scenario: Writing more than one server
- **WHEN** more than one MCP server entry is configured
- **THEN** all entries are spliced in a single write, producing one report per
  agent

### Requirement: Re-running MUST be safe

Re-running with unchanged inputs MUST NOT modify any file, so the command is
idempotent and leaves version control quiet.

#### Scenario: A second run with unchanged inputs
- **WHEN** the command is re-run with the same inputs
- **THEN** every file reports as already up to date and version control shows no
  change

### Requirement: Prompts MUST be skipped when there is no human to answer

A TTY alone SHALL NOT be taken as evidence of a human, because CI runners
routinely allocate one.

#### Scenario: Running in CI
- **WHEN** no TTY is present, or a recognised CI environment variable is set
- **THEN** prompts are skipped and the detected configuration is used as it
  stands, so the command is safe to run unattended

### Requirement: `update` MUST configure only the agents on file

`update` SHALL configure exactly the agents recorded by the last `install`. A
newly detected agent MUST NOT be configured automatically; it SHALL be reported
along with the command that adds it. Adding an agent MUST be a deliberate act —
either `install`, an explicit `--agents=`, or ticking it in the interactive
picker.

#### Scenario: An agent is installed after the last run, unattended
- **WHEN** `update` runs under `--yes`, in CI, or without a TTY, and an agent is
  detected that is not in the saved state
- **THEN** no files are written for that agent, and it is reported with the
  command that would add it

#### Scenario: An agent was deliberately unticked at install
- **WHEN** an agent was detected at install time but not selected
- **THEN** it is not pre-selected on any later run, because selection derives
  from saved state rather than from detection

#### Scenario: Previously chosen agents
- **WHEN** `update` runs
- **THEN** every agent recorded in the saved state is configured as before

## ADDED Requirements

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

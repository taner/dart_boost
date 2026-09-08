## Why

`update` silently configures agents the user never selected. On an unattended
run — `--yes`, CI, or no TTY — a freshly detected agent is added to the
selection and its guidelines and MCP config are written, with no prompt, because
`update` skips confirmation by contract.

This was found by running dart_boost against a real project: installing with
`--agents=claude_code,codex,copilot` and then running `update` wrote seven files
to five agents that had never been chosen.

It also contradicts the README, which says `update`'s "whole contract is to
repeat the answers already on file without re-asking", and it is inconsistent
with the two adjacent consent decisions in this codebase: the skills hand-off
remembers a decline as a no, and rules wiring refuses to touch `pubspec.yaml`
on an unattended run.

Now, because 0.2.0 is written but unpublished — this is the last moment to fix
it without it having ever shipped.

## What Changes

`update` configures exactly the agents recorded in `dart_boost.json`. A newly
detected agent is reported with what to run to add it, and is never configured
on its own.

An agent that was detected but deliberately unticked at install is no longer
pre-selected on every later run, because selection now derives from saved state
rather than from detection.

The interactive picker is unchanged: `update` still lists every agent with its
detection reason, so a new one can be ticked deliberately. Only the automatic
adoption goes away.

## Capabilities

### Modified Capabilities

- `agent-wiring`: adds a requirement that `update` configures only the agents on
  file, and reports rather than adopts a newly detected one.

## Impact

- `lib/src/cli/commands/install_command.dart` — `_selectAgents`, the `isUpdate`
  branch.
- `test/cli_ux_test.dart` — existing update tests.
- `README.md` — the update/drift section, which already describes the intended
  behaviour and is currently wrong about the implementation.
- `CHANGELOG.md` — folded into the unreleased 0.2.0 entry.

No API changes. No new dependencies. Behaviour change is strictly a reduction in
what `update` writes without being asked.

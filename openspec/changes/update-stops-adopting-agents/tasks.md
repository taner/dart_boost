## 1. Stop the automatic adoption

- [x] 1.1 Write a failing test: an unattended `update` with a newly detected
      agent absent from saved state must not write that agent's files, and the
      output must name the agent and the command that adds it.
- [x] 1.2 Write a failing test: an unattended `update` still configures every
      agent recorded in saved state.
- [x] 1.3 In `_selectAgents`, stop adding freshly detected agents to
      `preselected` on the `isUpdate` path; reword the report to name the agent
      and the command that adds it.
- [x] 1.4 Run the full suite; update any existing update test that asserted the
      old adoption behaviour rather than weakening it.

## 2. Documentation

- [x] 2.1 Correct the README's update/drift section to describe what the code
      now does.
- [x] 2.2 Fold the behaviour change into the unreleased 0.2.0 CHANGELOG entry.

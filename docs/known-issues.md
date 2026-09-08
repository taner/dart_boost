# Known issues

Accepted gaps: real, understood, and deliberately not fixed. They are not in
`openspec/specs/`, because those describe intended behaviour and these are
places the implementation knowingly falls short of it.

Fix one when it starts costing something, not because it is on a list.

## `--rules` cannot re-enable rules once they are off

`install_command.dart` ANDs the flag with the stored value, so passing `--rules`
against a `dart_boost.json` recording `rules.enabled: false` is a no-op. Only
editing that file turns them back on. This is consistent with how the existing
`guidelines` and `mcp` flags behave, and `doctor` prints `no (see
dart_boost.json)`, which is the recovery pointer.

## `--no-rules` leaves a stale MCP entry behind

The config splicers add and update keys; they never remove them. So a
`dart_boost` server entry written by an earlier run survives a later
`--no-rules` run. It is inert rather than broken: `bin/mcp.dart` reads
`rules.enabled` and registers zero tools, so the server starts and offers
nothing. The README's "no server" phrasing is stronger than the behaviour.

## A malformed rule file is silent on the `record_rule` path

`RuleRepository.write` calls `readAll()` and `writeIndex()` without an
`onWarning`, so recording a rule beside a malformed sibling reports nothing. The
file is skipped and left byte-identical, and `dart run dart_boost rules index`
and `doctor` both report it — but neither runs routinely, so every rule in that
file stays invisible to agents with no signal on the path people actually use.

Threading the skip warnings into the tool result would fix it cheaply.

## Index rows sort `models-2.md` before `models.md`

`.ai/rules/index.md` sorts rows by a plain string compare, and `-` (0x2D) sorts
before `.` (0x2E). Determinism is the property that matters — it is what keeps a
committed file from churning — and that holds. The ordering is simply not what a
human would eyeball first. Reachable only after a filename collision has forced
a numeric suffix.

## `install_integration_test.dart` keeps its own CLI runner

`test/support/cli_harness.dart` was extracted so several test files could share
one runner, but `install_integration_test.dart` still has a private `run` helper
of its own, and the harness carries a comment telling you to keep the two in
sync. Migrating it would remove the duplication.

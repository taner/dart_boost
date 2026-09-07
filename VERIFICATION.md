# Verification — dart_boost 0.1.0 (Phases 1–3)

Dart 3.13.2 / Flutter 3.47.2 (FVM), macOS arm64. Sandbox: `flutter create` +
`flutter_riverpod 3.4.3` + `go_router 18.0.1`, git-tracked.

## Passed

- **E2E.** `install --agents=claude_code --yes` composed 8 fragments and wrote
  `CLAUDE.md` + `.mcp.json`. Guidance matches installed majors: Riverpod **3**
  only (`StateProvider` removed, plain `Ref`), `flutter/v3.47` keyed off
  `.dart_tool/version`; `go_router 18` has no fragment, contributed nothing. No
  unrendered `<!--boost:-->` directives or `{{vars}}`.
- **All nine agents.** `AGENTS.md` written once across seven, user content
  preserved; every MCP config key shape correct.
- **Idempotence.** Runs 2 and 3: 12/12 "already up to date", `git status` empty.
- **Validate-before-write.** A malformed `.mcp.json` was reported, left
  byte-identical, and the run exited non-zero.
- **FVM.** A `.fvmrc`-pinned project got the absolute
  `<root>/.fvm/flutter_sdk/bin/dart` MCP command and `fvm flutter` prefixes.
- **Asset guard.** 11/11 `guidelines/` files in the manifest; no `guidelines` in
  `.gitignore`.
- **Live MCP.** The exact spec written (`dart mcp-server`) handshakes and lists
  14 tools when the client declares `roots` — including the `analyze_files`,
  `lsp` and `rip_grep_packages` that `foundation` cites (11 without `roots`).
- **CI.** `{ubuntu, macos, windows} × {stable, 3.7.0}` present. Windows covered:
  `p.joinAll(split('/'))` paths, `where.exe`, CRLF round-tripped by both
  splicers + guidelines writer + manifest parser, `.gitattributes` pinning
  fixtures `-text` (`git add --renormalize` is a no-op). Tests are hermetic.
- `dart format` clean, `dart analyze --fatal-infos` clean, **293 tests green**.

> **Note (0.2.0):** this Phase 1–3 pass predates project rules — the
> `record_rule` MCP server, `.ai/rules/`, `infer-conventions` and the
> `dart_boost.json`/`.dart_tool/dart_boost/state.json` split added after it.
> By the start of that work the suite had grown to 409 tests; the count above
> (293) was stale before this file was corrected and describes only what this
> page verifies. As of the project-rules work landing (Task 10), the suite is
> **485 tests green**, `dart format --set-exit-if-changed .` and
> `dart analyze --fatal-infos` clean, and `tool/verify_assets.dart` passes.

## Fixed (5 commits on `agent/worker-t005b-verification`)

1. **`package_config.json` `rootUri` resolved one directory too high.**
   `Uri.file(p.join(dir, ''))` is not a directory URI, so `resolve('../x')` ate
   `.dart_tool` *and* the project dir. Relative `rootUri`s are the common case
   (root package, path deps, workspace members; only hosted are absolute), so
   third-party `guidelines/` discovery was a silent no-op for them — neither
   offered for opt-in nor composed. Now `Uri.directory`. The old test missed it
   by writing absolute URIs; added a relative-`rootUri` test (red before the
   fix) and confirmed E2E with a path dep.
2. **No warning when the target dir has no `pubspec.yaml`** — `install` in a
   non-package scattered three files and reported success. Now warned first.
3. **Added the `verify_assets.parseManifest` regression test** the predecessor
   made the function public for: CRLF parity, pub's ASCII `|--` fallback tree,
   directory exclusion, garbage input — this is what makes the Windows CI leg
   actually guard the parser.
4. **Publishing was not gated on the asset guard** — nothing forced a `v*` tag
   onto a green commit, and a pub.dev release is unrecallable. `needs: assets`.
5. Merged the predecessor's WIP (CRLF preservation in `GuidelinesWriter`,
   Windows-safe `groupGuidelineTargets`, `.gitattributes`, `parseManifest`
   CRLF) — reviewed, kept in full.

## Remaining

- **Minimum *dependency* versions untested.** The `3.7.0` leg runs `pub get`,
  never `pub downgrade`. `analyze` passes against downgraded deps locally;
  `test` cannot be (downgraded `test` breaks on SDK 3.13.2), and a `downgrade`
  CI job would be red on `stable` for the same reason. Deliberate gap.
- Windows/Linux reasoned + unit-tested, not executed — first CI run is the real
  check. Interactive `cli_components` covered only by `FakeDialogSupport`.
- Phase 4/5 (content, skills delegation, `update` discovery) out of scope here.

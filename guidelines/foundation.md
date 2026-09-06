# Foundation

These guidelines were composed for **{{ projectName }}** by dart_boost
{{ boostVersion }} from its resolved dependency versions. They describe *this*
project, not Dart in general -- when they contradict a general habit, they win.

## Versions are facts, not guesses

- Every version-specific section below was selected from what this project
  *actually resolves*. Do not second-guess it against a version you remember.
- Do not upgrade, downgrade or add dependencies unless you were asked to. A
  `{{ pubAddCommand }}` you ran to "make the import work" silently invalidates
  the rest of this document.
- Never invent an API. If you are unsure whether a method exists on the
  installed version, look it up in the real resolved sources -- the `dart` MCP
  server's `analyze_files`, `lsp`, `read_package_uris` and
  `rip_grep_packages` all read them, and `pub_dev_search` does not.

## The verification loop

Run these before you consider a change finished. All three must be clean:

1. `{{ analyzeCommand }}` -- zero errors *and* zero warnings. A new lint on a
   line you touched is yours.
2. `{{ formatCommand }} .` -- formatting is not a matter of taste here.
3. `{{ testCommand }}` -- run the suite, not just the file you edited.

Do not write a throwaway script to prove a change works when a test can prove
it instead. If the behaviour is worth checking twice, it is worth a test.

## Conventions

- Follow the conventions already in this repository. Before creating a file,
  read its siblings for structure, naming and import style, and match them.
- Prefer editing an existing file over creating a new one. Prefer extending an
  existing widget, provider or helper over adding a parallel one.
- Descriptive names over short ones: `isEligibleForRefund`, not `check()`.
- Stick to the existing directory layout. Do not introduce a new top-level
  `lib/` folder without being asked.
- Only create Markdown documentation when you were explicitly asked to.

<!--boost:if isMelosWorkspace-->
## This is a Melos monorepo

A change is not finished when one package passes. See the `melos` section for
how to run the toolchain across every package.
<!--boost:end-->

<!--boost:if isPubWorkspace-->
## This is a pub workspace

Members share one resolution and one `.dart_tool/package_config.json` at the
workspace root. A dependency added to one member affects the version solve for
all of them, so `{{ pubGetCommand }}` at the root is what proves the change.
<!--boost:end-->

<!--boost:if usesFvm-->
## The SDK on PATH is the wrong one

This project is FVM-pinned. Every command above already carries the `fvm`
prefix for that reason -- see the `fvm` section before you type a bare
`flutter` or `dart`.
<!--boost:end-->

# Melos

This repository is a Melos monorepo. Every package keeps its own
`pubspec.yaml`, and the repository root owns the commands.

## Read the scripts before inventing a command

The Melos config lives either in `melos.yaml` or in a `melos:` block in the
root `pubspec.yaml` -- check which one this repo uses before editing either.
Its `scripts:` section almost certainly already defines `analyze`, `test` and
`format` the way this repository wants them run. Prefer
`melos run <script>` over reconstructing the command yourself; the script may
carry flags, scopes or an ordering that matters.

For anything without a script, run it across every package with
`{{ workspacePrefix }}<command>`, for example
`{{ workspacePrefix }}{{ testCommand }}`.

## Bootstrapping

- After changing any dependency, or after a fresh clone, run `melos bootstrap`
  (`melos bs`) from the root. That is what links local packages together; a
  bare `{{ pubGetCommand }}` inside one package is not equivalent and will
  either fail to resolve or resolve against the published version instead of
  the sibling on disk.
- Local packages depend on each other through `path:` dependencies, pub
  workspace resolution, or `dependency_overrides` that Melos manages. Do not
  hand-edit whichever of those this repo uses -- the next bootstrap rewrites
  it.

## Scope of a change

- Adding a dependency to one package does not add it to the others. Add it to
  the package that imports it, not to the root.
- A change is not finished when the package you edited passes. If you touched
  a package others depend on, the whole workspace has to analyze and test
  clean.
- Use `--scope` / `--ignore` (or `--diff`) to narrow a long run while
  iterating, then do a full run before you call it done.
- Version bumps and changelogs are Melos's job (`melos version`). Do not
  hand-edit a `version:` field or a `CHANGELOG.md` entry it manages.

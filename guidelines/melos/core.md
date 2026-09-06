# Melos

This repository is a Melos monorepo. Each package keeps its own `pubspec.yaml`
and its own resolution.

- Run something across every package with `{{ workspacePrefix }}<command>`, for
  example `{{ workspacePrefix }}{{ testCommand }}`.
- Check the `scripts:` section of `melos.yaml` before inventing a command --
  the repository almost certainly already defines `analyze`, `test` and
  `format` the way it wants them run.
- Adding a dependency to one package does not add it to the others. Local
  packages depend on each other through `path:` or `dependency_overrides`,
  which Melos manages -- do not hand-edit those.

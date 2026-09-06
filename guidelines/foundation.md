# Foundation

These guidelines were composed for **{{ projectName }}** by dart_boost
{{ boostVersion }} from its resolved dependency versions. They describe *this*
project, not Dart in general -- when they contradict a general habit, they win.

- Do not upgrade, downgrade or add dependencies unless you were asked to.
  Version-specific guidance below assumes the currently resolved versions.
- Run `{{ analyzeCommand }}` and `{{ formatCommand }} .` before considering a
  change finished. Both must be clean.
- Prefer editing an existing file over creating a new one, and match the
  conventions already present in the file you are editing.
- Never invent an API. If you are unsure whether a method exists on the
  installed version, look it up with the `dart` MCP server (`analyze_files`,
  `lsp` and `rip_grep_packages` all read the real resolved sources).

<!--boost:if isPubWorkspace-->
## This is a pub workspace

Members share one resolution and one `.dart_tool/package_config.json` at the
workspace root. A dependency added to one member affects the version solve for
all of them.
<!--boost:end-->

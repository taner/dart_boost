# Laravel Boost — reference

Captured 2026-09-07 from <https://laravel.com/framework/docs/boost>, cross-checked
against the `laravel/boost` clone at `../laravel-boost` (HEAD 2026-09-05).

dart_boost is the Dart counterpart to this. This file exists so its design can be
compared against the current Boost, not the Boost of a year ago.

## The three layers

Boost gives agents context at three levels. dart_boost implements the first and
third directly — guidelines, and, via its own `record_rule` MCP server, project
rules. The second, skills, it deliberately hands off to `package:skills`
instead of reimplementing (see the README's "Why this and not a Boost port").

| Aspect | Guidelines | Skills | Project Rules |
| --- | --- | --- | --- |
| Loaded | Upfront, always present | On-demand, when relevant | When the edited file matches a glob |
| Scope | Broad, foundational | Focused, task-specific | This application only |
| Purpose | Ecosystem conventions | Implementation patterns | Your team's decisions |
| Source | `.ai/**/*.blade.php` in the package | `SKILL.md` folders | `.ai/rules/*.md`, written by an agent |

Guidelines and skills describe the *ecosystem*. Project rules capture *your app*.

## Install

```sh
composer require laravel/boost --dev
php artisan boost:install     # writes guidelines, skills, MCP config
php artisan boost:update      # refresh published resources
php artisan boost:update --discover   # also scan for newly installed packages
```

Boost suggests `.gitignore`-ing `.mcp.json`, `CLAUDE.md`, `AGENTS.md` and
`boost.json` since they regenerate. `.ai/rules/` is the exception — commit it.

## MCP server

Registered as `command: php`, `args: ["artisan", "boost:mcp"]`.

| Tool | Notes |
| --- | --- |
| Application Info | PHP & Laravel versions, DB engine, ecosystem packages + versions, Eloquent models |
| Browser Logs | Logs and errors from the browser |
| Database Connections | Available connections, including the default |
| Database Query | Execute a query |
| Database Schema | Read the schema |
| Get Absolute URL | Relative path -> absolute, so agents emit valid URLs |
| Last Error | Last error from the log files |
| Read Log Entries | Last N log entries |
| **Record Rule** | Record a durable project rule into `.ai/rules` |
| **Search Docs** | Query the hosted documentation API for the installed packages |

Note how many of these are *runtime introspection of a running app*. This is the
part dart_boost deliberately does not reimplement, because `dart mcp-server`
already covers the analogous ground (`analyze_files`, `lsp`, `run_tests`,
`hot_reload`, `widget_inspector`, `get_runtime_errors`, `vm_service`).

`Record Rule` now has a Dart equivalent: dart_boost's own `record_rule`, the
one tool on `dart run dart_boost:mcp`. `Search Docs` is still the one with **no
Dart equivalent**.

## Guidelines

Composable instruction files loaded upfront. `core` is version-generic; version
directories layer on top.

| Package | Versions |
| --- | --- |
| Core & Boost | core |
| Laravel Framework | core, 10.x, 11.x, 12.x, 13.x |
| Livewire | core, 2.x, 3.x, 4.x |
| Flux UI | core, free, pro |
| Folio / Herd / MCP / Pennant / PHPUnit / Pint / Sail / Volt / Wayfinder | core |
| Inertia Laravel / React / Vue / Svelte | core, 1.x, 2.x, 3.x |
| Pest | core, 3.x, 4.x |
| Tailwind CSS | core, 3.x, 4.x |
| Enforce Tests | conditional |

- **Custom:** add `.blade.php` or `.md` under `.ai/guidelines/*`.
- **Override:** a custom file at the *same path* replaces the built-in one
  (e.g. `.ai/guidelines/inertia-react/2/forms.blade.php`).
- **Third-party:** a package ships `resources/boost/guidelines/core.blade.php`.

dart_boost's equivalents: `guidelines/` tree, `.ai/guidelines/<same path>.md`
overrides, and a third-party `guidelines/**/*.md` tree. Note dart_boost adds an
explicit `--trust=<package>` opt-in that Boost does not have — Boost loads
third-party guidelines automatically on install.

## Agent Skills

Installed based on `composer.json` detection. Standard Agent Skills format
(`SKILL.md` + YAML frontmatter `name`/`description`).

fluxui-development, folio-routing, **infer-conventions**, inertia-{react,svelte,vue}-development,
livewire-development, mcp-development, pennant-development, pest-testing,
tailwindcss-development, volt-development, wayfinder-development.

Custom skills go in `.ai/skills/{name}/SKILL.md`; a matching name overrides a
built-in. Third-party packages ship `resources/boost/skills/{name}/SKILL.md`.

## Project Rules

dart_boost now has this too — see "Implications for dart_boost" below for what
carried over and what didn't.

> "While guidelines and skills teach agents how to write Laravel, project rules
> teach them how to write your application."

Intended for: decisions made along the way; style preferences agents keep
missing; traps and constraints not inferable from surrounding code.

Stored as markdown in `.ai/rules/`, **committed to source control**. Each file
declares its globs in frontmatter:

```markdown
---
paths:
  - app/Http/Controllers/**
---

# Http Controllers

## Extend BaseController for tenant scoping

All controllers must extend `App\Http\Controllers\BaseController`, which applies
the current tenant's query scope. Extending Laravel's base controller directly
will leak data across tenants.
```

Boost maintains `.ai/rules/index.md`, a glob -> file table. **Agents are
instructed to consult the index before planning or editing any file**, so a rule
is loaded only when relevant. This is the mechanism that keeps path-scoped rules
from bloating context.

```markdown
# Project Rules Index

Before planning or editing, find the row whose globs match the file's path and read that rule file.

| Applies to | Rule file |
| --- | --- |
| app/Http/Controllers/** | .ai/rules/controllers.md |
| app/Models/** | .ai/rules/models.md |
```

### Recording

The user says, in plain language:

> Remember that all money values are stored as integer cents, never as floats.

The agent calls the `record-rule` MCP tool with `glob`, `title`, `note`. Boost
files it under the matching area, creating the file if needed, and regenerates
the index.

The docs are emphatic that rules must be recorded **through the tool, not by
hand**, because a hand-written file is invisible until the index is next
regenerated.

The tool description shipped in `src/Mcp/Tools/RecordRule.php` is itself the
prompt engineering that makes this work:

> "Record a durable project rule so the next agent or teammate inherits it
> instead of working it out again. Use it for a settled decision (why the project
> does something a certain way), a non-obvious trap, or a standing constraint
> that must always be followed. [...] Keep it to a few lines; only record what you
> would want to read in three months. Do not record secrets, transient state, or
> anything already obvious from the code."

Schema: `glob` (required, routes the rule into an area file), `title` (required,
"a short, specific heading"), `note` (required, "a few lines stating the rule
plainly. No essays."). Globs are normalized by `RuleRepository::normalizeGlob`.

### Bootstrapping from existing code

The `infer-conventions` skill sweeps an existing app across a checklist —
validation, controllers, authorization, models, architecture, testing, frontend,
database, console — then an open-ended pass for base classes, shared traits and
module layouts.

Design points worth stealing:

- Documents what the code **actually does**, not what it should do.
- Records only well-supported, **non-default** conventions.
- **Skips anything Pint or Rector already enforces** (i.e. don't duplicate the
  linter/formatter — for Dart, that means don't restate `analysis_options.yaml`).
- Reports genuinely **mixed** patterns rather than recording them as rules.
- Presents each convention with **supporting evidence for approval** before
  writing; "yolo" skips confirmation.

### Disabling

`BOOST_RULES_ENABLED=false` removes the `record-rule` tool and stops Boost
managing `.ai/rules`.

## Documentation API

A hosted service: 17,000+ pieces of Laravel-specific information, semantic search
over embeddings, queried via the `search-docs` MCP tool and scoped to the
packages you actually have installed. Guidelines and skills both instruct the
agent to use it.

Version coverage: Laravel 10-13, Filament 2-5, Flux UI 2 (free/pro), Inertia 1-2,
Livewire 1-4, Nova 4-5, Pest 3-4, Tailwind 3-4.

**No Dart equivalent exists.** `dart mcp-server` has `pub_dev_search`, which
finds packages, not documentation.

## Extending

Agents extend `Laravel\Boost\Install\Agents\Agent` and implement any of
`SupportsGuidelines`, `SupportsMcp`, `SupportsSkills`; registered via
`Boost::registerAgent('key', CustomAgent::class)`. dart_boost's `AgentRegistry`
is the analogue, but closed — agents are compiled in, not registrable.

## Implications for dart_boost

Items 1-3 below were written as forward-looking design notes before dart_boost
had project rules. All three shipped; the notes are kept as a record of what
was decided and why, now in the past tense.

1. **Project rules shipped, built on the index-file indirection.**
   `record_rule` writes into `.ai/rules/<area>.md` and regenerates
   `.ai/rules/index.md`, the same glob table Boost uses, for the same reason:
   a table the agent reads first, so only matching rules enter context.
2. **Recording needed a callable tool, so dart_boost grew a minimal one.** The
   "ships no MCP server" design decision from the first draft of this file
   *was* revisited, but narrowly: `dart run dart_boost:mcp` exposes exactly one
   tool, `record_rule`. It does not reimplement any of `dart mcp-server`'s
   introspection tools, and is wired in as a second server alongside it, not
   instead of it. Enabling it adds `dart_boost` as a dev dependency (with
   consent) because that command only resolves once dart_boost is one.
3. **`infer-conventions` shipped as a procedure, not a skill.** dart_boost has
   no skills mechanism of its own (see "Agent Skills" above), so the
   equivalent is `.ai/infer-conventions.md`, a bundled file an agent is told to
   read and follow when asked to infer a project's conventions — no MCP server
   involved, matching the original prediction that this was the cheaper half.
4. **Docs search is a genuine ecosystem gap**, and a much larger undertaking than
   rules (hosting, embeddings, ingestion). Still unaddressed.
5. Boost auto-loads third-party guidelines; dart_boost gates them behind
   `--trust=`. dart_boost's position is the safer one — worth keeping.

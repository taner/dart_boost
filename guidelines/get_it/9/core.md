# get_it 9

This project resolves get_it 9.

- **BREAKING vs 8: `strictDisposalOrder` is gone.** Passing it to `reset()`,
  `resetScope()`, `popScope()`, `popScopesTill()` or `dropScope()` no longer
  compiles. Disposal is now always strict LIFO by registration order, so a
  `dispose` callback can rely on anything registered before it still being
  available -- and code that depended on 8's unordered behaviour must be
  revisited rather than mechanically ported.
- `allReady()` caches its future and returns the same instance on repeated
  calls (9.2), invalidated when a new async singleton is registered. Awaiting
  it from several places is cheap; you no longer need to hold the future
  yourself.
- Unregistering a pending async singleton, or resetting its scope, now
  completes its ready completer, so `allReady()` cannot hang on a registration
  that was removed mid-flight.
- Everything 8 added is still here: cached factories, `getMaybe`, `findAll`,
  `resetLazySingletons`, `onCreated`, and `fromAllScopes` on `getAll`.
- The DevTools extension (9.1) lists live registrations with their scope and
  state. It only reports when `getIt.debugEventsEnabled = true` is set, which
  belongs behind a `kDebugMode` check.

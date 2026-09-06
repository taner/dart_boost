# get_it 8

This project resolves get_it 8.

- **Cached factories are available:** `registerCachedFactory` (and the `Async`
  and `Param` variants) hands out the same instance while something still holds
  a reference to it, and rebuilds after it is collected. It is the right tool
  for a per-screen object that several widgets share.
- `getMaybe<T>()` (8.1) returns `null` instead of throwing when nothing is
  registered. Prefer it over `isRegistered<T>()` followed by `get<T>()`.
- `dependsOn` is **required** on `registerSingletonWithDependencies` from 8.1.
- 8.3 adds `findAll()` for locating every registration matching a type
  (including subtypes and interfaces) and `resetLazySingletons()` for resetting
  several at once.
- `getAll<T>()` and `getAllAsync<T>()` take `fromAllScopes:` -- by default they
  only see the current scope, which is the usual surprise when a plugin
  registration made in an outer scope goes missing.
- `reset()`, `resetScope()`, `popScope()`, `popScopesTill()` and `dropScope()`
  accept `strictDisposalOrder:`. Pass `true` when a `dispose` callback needs
  another object to still be registered. **get_it 9 removes the parameter and
  always disposes strict LIFO**, so writing `strictDisposalOrder: true` today
  is also the smoother upgrade.
- 8.2 renamed internals (`ServiceFactory` became `ObjectRegistration`). The
  public API is unchanged, but tooling that reflected on the old names needs
  updating.

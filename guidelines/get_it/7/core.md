# get_it 7

This project resolves get_it 7. Several methods that current examples use do
not exist here.

- **No cached factories.** `registerCachedFactory`,
  `registerCachedFactoryAsync` and the `Param` variants arrive in 8. Model the
  same thing with a lazy singleton in a scope you push and pop.
- **No `getMaybe`** (added in 8.1). To resolve something that may not be
  registered, guard with `getIt.isRegistered<T>()` first -- `get<T>()` throws.
- **No `findAll()`, `resetLazySingletons()` or the `onCreated` callback**
  (8.3). Reset lazy singletons one at a time with
  `resetLazySingleton<T>(instance: ...)`.
- `getAll<T>()` has no `fromAllScopes` parameter here, so it only sees the
  current scope. `getAllAsync<T>()` exists from 7.7.0 on and not before.
- `registerSingletonWithDependencies` takes `dependsOn` as optional. It is
  required from 8.1, and omitting it never worked -- always pass it.
- Disposal order across mixed named and unnamed registrations is whatever the
  internal maps produce, **not** reverse registration order. Do not write a
  `dispose` callback that assumes another object is still registered; 9 makes
  the order strict LIFO, so code relying on today's order breaks on upgrade.

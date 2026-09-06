# injectable 2

This project resolves injectable 2.

- Micro packages are pulled in with `includeMicroPackages: true` on
  `@InjectableInit` -- the option that discovers `@InjectableInitMicroPackage`
  modules across the dependency graph. **injectable 3 removes it**, so if you
  are writing new code prefer the explicit form
  (`externalPackageModulesBefore` / `externalPackageModulesAfter`), which works
  in both.
- The `usesNullSafety` option still exists and is deprecated. Do not set it.
- `asExtension` defaults to `true` and `initializerName` to `'init'` (since
  2.0), so the generated entry point is `getIt.init()`. Older examples calling
  a top-level `$initGetIt(getIt)` are pre-2.0.
- There is no `allowMultipleRegistrations`; registering two implementations for
  one type is an error, so disambiguate with `@Named` or an environment.
- `generateAccessors: true` (2.7.1) generates typed getter extensions on
  `GetIt`, which is worth turning on -- it turns a missing registration into a
  compile error instead of a runtime throw.
- Cached-factory support (`@Injectable(...)` backed by get_it's cached
  factories) requires injectable >= 2.7.0 **and** get_it >= 8.3.0. Check the
  resolved get_it before using it.

# injectable 3

This project resolves injectable 3. Two options that injectable 2 examples use
were removed.

- **`includeMicroPackages` is gone.** Micro-package modules must be listed
  explicitly on `@InjectableInit`, which also makes their ordering relative to
  the local registrations part of the source:

```dart
@InjectableInit(
  externalPackageModulesBefore: [ExternalModule<CorePackageModule>()],
  externalPackageModulesAfter: [ExternalModule<AnalyticsPackageModule>()],
)
Future<void> configureDependencies() async => getIt.init();
```

- **`usesNullSafety` is gone.** Null safety is always assumed; delete the
  option rather than setting it to `true`.
- `allowMultipleRegistrations` is new: it permits several implementations to
  register for the same type. Turn it on deliberately, for a plugin-style
  collection resolved with `getAll<T>()` -- not to silence a duplicate
  registration that is actually a mistake.
- External dependencies (`@InjectableInit(externalPackageModules...)`,
  `dependsOn`-style ordering) are treated as non-blocking when environments are
  sorted, so a module gated to one environment no longer stalls the graph.
- Everything else carries over from 2: `asExtension`/`init()` naming,
  `@preResolve`, `@module`, `@Named`, environments, and `generateAccessors`.

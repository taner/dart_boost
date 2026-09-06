# get_it

- Register everything in **one** `configureDependencies()` called from `main`
  before `runApp`, and nowhere else. Registration scattered across the app
  makes the order of initialisation depend on which screen the user opened
  first.
- **Register against the interface, resolve the interface:**
  `getIt.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(...))`.
  Registering the concrete type is what makes a fake impossible to swap in.
- `registerLazySingleton` is the right default. Use `registerSingleton` only
  when the object must exist before the first `get`, and `registerFactory` when
  every caller needs its own instance.
- **Keep `getIt` at the composition root.** Resolve at the edge -- in `main`,
  in a route builder, in a provider -- and pass dependencies down as
  constructor arguments. A widget or a repository that reaches for `GetIt.I`
  internally has a hidden dependency that no test can override without mutating
  global state.
- Never call `getIt<T>()` inside `build`. Resolve once in `initState`, or take
  the object as a constructor argument.
- Async setup is `registerSingletonAsync` plus `await getIt.allReady()` before
  `runApp`. When one async singleton needs another, declare it with
  `registerSingletonWithDependencies(..., dependsOn: [Other])` instead of
  awaiting by hand -- get_it orders the graph for you.
- Use `pushScope` / `popScope` for objects with a lifetime shorter than the app
  (a signed-in session, a feature flow). Give registrations a `dispose:`
  callback and popping the scope tears them down in reverse order.
- In tests, `await getIt.reset()` in `tearDown`. Set `getIt.allowReassignment =
  true` only inside tests -- in production it turns a double registration, which
  is a bug, into silence.
- Named instances (`instanceName:`) are a last resort. Two objects of the same
  type usually want two types, or a wrapper.

```dart
final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  getIt
    ..registerLazySingleton<ApiClient>(() => ApiClient(getIt()))
    ..registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(getIt<ApiClient>()),
    )
    ..registerSingletonAsync<Database>(Database.open, dispose: (db) => db.close());

  await getIt.allReady();
}
```

<!--boost:if usesInjectable-->
This project also uses `injectable`, so registrations are generated from
annotations rather than written by hand. Do not add manual `registerX` calls
alongside the generated `init()` -- see the injectable guidance below.
<!--boost:end-->

# Bloc 9

This project resolves bloc 9. Everything in the shared section applies; the
notes below are where bloc 8 guidance found online is now wrong.

- **`BlocOverrides` is gone.** It was deprecated in 8.1 and removed in 9.0, so
  `BlocOverrides.runZoned(() => runApp(...), blocObserver: ...)` does not
  compile. Install the observer and the default transformer as statics in
  `main`: `Bloc.observer = MyBlocObserver();` and, if you need one,
  `Bloc.transformer = sequential<dynamic>();`.
- `BlocObserver` gained `onDone` in 9.1, called when a bloc's state stream
  finishes, and 9.2 added `MultiBlocObserver` so several observers can be
  installed at once instead of writing a forwarding observer:
  `Bloc.observer = MultiBlocObserver([LogObserver(), CrashObserver()]);`
- `BlocBase<State>` implements `EmittableStateStreamableSource<State>` rather
  than bloc 8's `StateStreamableSource<State>`. A hand-written fake bloc that
  satisfied the old interface no longer type-checks against `BlocProvider` or
  `BlocBuilder`; use `MockBloc` / `MockCubit` from `bloc_test`.
- `package:bloc_lint` ships bloc-specific analysis (lint rules plus an LSP
  server) for this major. It is opt-in and separate from the Dart analyzer --
  add it deliberately rather than assuming it is running.
- Companion majors that pair with bloc 9: `flutter_bloc` 9.x, `bloc_test` 10.x,
  `bloc_concurrency` 0.3.x.

<!--boost:if usesHydratedBloc-->
`hydrated_bloc` 10 and 11 are the versions that pair with bloc 9, and both
differ from the 9.x snippets still in circulation:

- Storage is `package:hive_ce`, and `HydratedStorage.build` takes
  `storageDirectory:` as a `HydratedStorageDirectory` -- `HydratedStorageDirectory.web`
  under `kIsWeb`, otherwise `HydratedStorageDirectory(path)`. Passing a
  `dart:io` `Directory` is the bloc-8-era API and no longer compiles.
- Storage can be overridden per bloc or cubit instance, which is the clean way
  to isolate one in a test. In `hydrated_bloc` 11 that override is a *named*
  parameter on `HydratedCubit`.
- `hydrate` takes an `onError` callback and a `HydrationErrorBehavior`, so
  corrupt persisted state can be dropped instead of crashing at startup.
<!--boost:end-->

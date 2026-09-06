# Bloc 8

This project resolves bloc 8. Everything in the shared section applies; the
differences from bloc 9 are in how the observer is installed and what a
hand-written test double has to implement.

- **Observer wiring depends on the patch version.** `Bloc.observer` and
  `Bloc.transformer` were removed in 8.0 in favour of `BlocOverrides.runZoned`
  and reinstated in 8.1, where `BlocOverrides` became deprecated. On 8.1+ set
  `Bloc.observer = MyBlocObserver();` in `main` and ignore `BlocOverrides`
  entirely; only reach for `BlocOverrides.runZoned` if the pin is 8.0.x.
- `BlocObserver` here is `onCreate`, `onEvent`, `onChange`, `onTransition`,
  `onError` and `onClose`. There is no `onDone` (bloc 9.1) and no
  `MultiBlocObserver` (bloc 9.2), so to run two observers write one that
  forwards to both.
- `BlocBase` implements `StateStreamableSource<State>`. Bloc 9 narrows that to
  `EmittableStateStreamableSource<State>`, so a hand-rolled fake bloc written
  against bloc 8 stops satisfying the interface at upgrade time. Use
  `MockBloc` / `MockCubit` from `bloc_test` instead of hand-rolling one.
- `package:bloc_lint` does not cover this major -- rely on the analyzer and
  `very_good_analysis` / `flutter_lints` for style.
- Companion majors that pair with bloc 8: `flutter_bloc` 8.x, `bloc_test` 9.x,
  `bloc_concurrency` 0.2.x.

<!--boost:if usesHydratedBloc-->
`hydrated_bloc` 9.x is the version that pairs with bloc 8. `HydratedStorage.build`
takes a `storageDirectory:` of type `Directory` from `dart:io`, which is why it
cannot run on the web without a shim, and storage is backed by classic Hive.
Both change in `hydrated_bloc` 10.
<!--boost:end-->

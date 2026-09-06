# Riverpod 2 -- testing

- Build a `ProviderContainer` per test and dispose it yourself. There is no
  `ProviderContainer.test()` in Riverpod 2 -- that arrives in 3.
- Replace dependencies with `overrides:` rather than reaching into providers.
- **Only `Provider.overrideWithValue` exists here.** Riverpod 2 removed
  `overrideWithValue` from every other provider type; `FutureProvider`,
  `StreamProvider` and `NotifierProvider` are overridden with
  `overrideWith((ref) => ...)`, which supplies a whole replacement body.
  Riverpod 3 brings `Future/StreamProvider.overrideWithValue` back, so a
  Riverpod 3 test snippet will not compile here.
- There is no `overrideWithBuild`, so a notifier cannot be half-stubbed.
  Override the dependency the notifier reads instead of the notifier itself.
- For widget tests, wrap in `ProviderScope(overrides: [...])`. There is no
  `WidgetTester.container` helper; hold the container through a
  `ProviderScope(parent: ...)` or read through `tester.element(...)`.
- A provider that failed stays failed, so an error-path test needs no special
  setup: assert on `AsyncError` directly. (Riverpod 3's automatic retry makes
  the same test flaky, which is worth knowing before you upgrade.)

```dart
final container = ProviderContainer(
  overrides: [apiProvider.overrideWithValue(FakeApi())],
);
addTearDown(container.dispose);

expect(container.read(counterProvider), 0);
```

# Riverpod 2 -- testing

- Build a `ProviderContainer` per test and dispose it yourself. There is no
  `ProviderContainer.test()` in Riverpod 2 -- that arrives in 3.
- Replace dependencies with `overrides:` rather than reaching into providers.
- For widget tests, wrap in `ProviderScope(overrides: [...])`. There is no
  `WidgetTester.container` helper; hold the container through a
  `ProviderScope(parent: ...)` or read through `tester.element(...)`.
- `overrideWithValue` works on any provider whose value type is plain.
  For a `FutureProvider`, override the dependency it reads rather than the
  future itself -- Riverpod 2 has no `overrideWithBuild`.
- A provider that failed stays failed, so an error-path test needs no special
  setup: assert on `AsyncError` directly.

```dart
final container = ProviderContainer(
  overrides: [apiProvider.overrideWithValue(FakeApi())],
);
addTearDown(container.dispose);

expect(container.read(counterProvider), 0);
```

# Riverpod 3 -- testing

- Use `ProviderContainer.test()`. It disposes itself when the test ends, so no
  `addTearDown` is needed. The bare `ProviderContainer()` constructor is for
  production code.
- Replace dependencies with `overrides:` rather than reaching into providers.
- For widget tests, wrap in `ProviderScope(overrides: [...])` and reach the
  container with `tester.container`.
- `NotifierProvider.overrideWithBuild` stubs just the `build` method and keeps
  the notifier's real methods. `FutureProvider.overrideWithValue` and
  `StreamProvider.overrideWithValue` are back in 3, so an async provider can be
  pinned to a value without a fake dependency.
- **Automatic retry breaks naive error tests.** A provider you push into
  `AsyncError` will retry and flip back to `AsyncLoading`. Pass
  `retry: (count, error) => null` to `ProviderContainer.test()` or
  `ProviderScope` in any test that asserts on a failure state.

```dart
final container = ProviderContainer.test(
  overrides: [apiProvider.overrideWithValue(FakeApi())],
  retry: (count, error) => null,
);

expect(container.read(counterProvider), 0);
```

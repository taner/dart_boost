# Riverpod 3 -- testing

- Build a `ProviderContainer` per test and `addTearDown(container.dispose)`.
- Replace dependencies with `overrides:` rather than reaching into providers.
- For widget tests, wrap in `ProviderScope(overrides: [...])`.

```dart
final container = ProviderContainer(
  overrides: [apiProvider.overrideWithValue(FakeApi())],
);
addTearDown(container.dispose);

expect(container.read(counterProvider), 0);
```

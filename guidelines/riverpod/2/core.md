# Riverpod 2

This project resolves Riverpod 2. Guidance written for Riverpod 3 does not
apply -- the differences below are real API differences, not style.

## Providers

- `StateProvider`, `StateNotifierProvider` and `ChangeNotifierProvider` are
  exported from the main entrypoint here and are not deprecated. Riverpod 3
  moves all three behind a `legacy.dart` import, so prefer `NotifierProvider`
  and `AsyncNotifierProvider` for anything new -- those are what survives.
- `Ref` is a family of types in Riverpod 2: `FutureProviderRef`,
  `StreamProviderRef`, `AutoDisposeRef`, and a generated `FooRef` per
  code-generated provider. Riverpod 3 collapses all of them into one plain
  `Ref`, so do not name these types in your own signatures or helper methods.
- `ref.refresh(p)` returns the new value; `ref.invalidate(p)` does not. Use
  `invalidate` unless you need the result immediately.
- There is no `Ref.mounted`. After an `await` inside a provider, guard with a
  flag you set from `ref.onDispose` rather than assuming the provider is alive.

## Failures

- A provider that throws stays in `AsyncError` until something invalidates it.
  Riverpod 2 does not retry. If a transient network error should recover, wire
  the retry yourself -- expose a `refresh()` on the notifier that calls
  `ref.invalidateSelf()`.
- The error reaches `AsyncValue.error` unwrapped. Riverpod 3 wraps read-time
  errors in `ProviderException`, so `catch` blocks that match on your own
  exception type will need revisiting at upgrade time.

<!--boost:if usesRiverpodGenerator-->
## Code generation

A generated function provider takes its own `Ref` subtype, named after the
provider:

```dart
@riverpod
Future<User> user(UserRef ref, String id) => ref.watch(apiProvider).user(id);
```

Generated providers are auto-dispose by default; opt out with
`@Riverpod(keepAlive: true)`. Type parameters on generated providers are not
supported in Riverpod 2 -- write the provider concretely.

Rebuild after any annotation change with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

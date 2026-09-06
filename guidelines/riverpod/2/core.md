# Riverpod 2

This project resolves Riverpod 2.

- `StateProvider` and `StateNotifierProvider` still exist here, but prefer
  `NotifierProvider` and `AsyncNotifierProvider` for anything new -- they are
  what Riverpod 3 keeps.
- `ref.refresh(p)` returns the new value; `ref.invalidate(p)` does not. Use
  `invalidate` unless you need the result immediately.

<!--boost:if usesRiverpodGenerator-->
## Code generation

Annotate with `@riverpod` and let the generator produce the provider:

```dart
@riverpod
Future<User> user(UserRef ref, String id) => ref.watch(apiProvider).user(id);
```

Note the generated `Ref` subtype (`UserRef`) -- Riverpod 3 replaces it with a
plain `Ref`, so do not write code that depends on the name.

Rebuild after any annotation change with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

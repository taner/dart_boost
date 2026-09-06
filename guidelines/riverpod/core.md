# Riverpod

- Providers are top-level `final` (or generated) declarations. Never create one
  inside `build`.
- Read with `ref.watch` when the widget should rebuild, `ref.read` for one-off
  actions inside callbacks, and `ref.listen` for side effects such as showing a
  snackbar.
- Keep providers free of `BuildContext`. If a provider needs something from the
  widget tree, pass it in as a family argument.
- Put the async boundary in the provider, not the widget: expose
  `AsyncValue<T>` and let the widget `switch` on it.

```dart
switch (ref.watch(userProvider)) {
  AsyncData(:final value) => UserView(user: value),
  AsyncError(:final error) => ErrorView(error: error),
  _ => const CircularProgressIndicator(),
}
```

# Riverpod

- Providers are top-level `final` (or generated) declarations. Never create one
  inside `build`.
- Read with `ref.watch` when the widget should rebuild, `ref.read` for one-off
  actions inside callbacks, and `ref.listen` for side effects such as showing a
  snackbar. `ref.watch` belongs in a `build` method (widget or notifier) and
  nowhere else -- watching from a callback leaks a subscription.
- Keep providers free of `BuildContext`. If a provider needs something from the
  widget tree, pass it in as a family argument.
- Family arguments are cache keys, so they must be stable under `==`. Pass an
  `int`, a `String`, or a value type with a real `==`; never a fresh `List` or
  a closure.
- Put the async boundary in the provider, not the widget: expose
  `AsyncValue<T>` and let the widget `switch` on it.
- Never mutate `state` in place. Assign a new value -- Riverpod compares with
  `==`, so an in-place `list.add` notifies nobody.
- State transitions are named methods on the notifier. A widget calls
  `ref.read(cartProvider.notifier).add(item)`; it never assembles the next
  state itself and never writes `state` from outside the notifier.
- `ref.watch(p)` inside a `Notifier.build` re-runs `build` and discards the
  current state when `p` changes. That reset is the point; when you want the
  dependency *without* it, read it inside the method that needs it.
- Narrow rebuilds with `select` when a widget uses one field:
  `ref.watch(userProvider.select((u) => u.name))`.
- Register `ref.onDispose` for anything you own (subscriptions, timers,
  controllers) at the point you create it.

```dart
switch (ref.watch(userProvider)) {
  AsyncData(:final value) => UserView(user: value),
  AsyncError(:final error) => ErrorView(error: error),
  _ => const CircularProgressIndicator(),
}
```

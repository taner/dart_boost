# Riverpod 3

This project resolves Riverpod 3. Guidance written for Riverpod 2 will not
compile here.

- `StateProvider` and `StateNotifierProvider` are gone. Use `NotifierProvider`
  and `AsyncNotifierProvider`.
- `ChangeNotifierProvider` is gone. Hold a `ChangeNotifier` in a `Notifier` and
  expose what the UI needs.
- Generated providers take a plain `Ref`, not a per-provider `FooRef` subtype.

```dart
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
}
```

<!--boost:if usesRiverpodGenerator-->
Rebuild after any annotation change with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

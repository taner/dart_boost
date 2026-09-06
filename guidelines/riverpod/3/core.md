# Riverpod 3

This project resolves Riverpod 3. Guidance written for Riverpod 2 will not
compile here.

## Providers

- `StateProvider`, `StateNotifierProvider` and `ChangeNotifierProvider` are
  legacy. They still exist, but only behind a separate import
  (`package:flutter_riverpod/legacy.dart`, `package:hooks_riverpod/legacy.dart`
  or `package:riverpod/legacy.dart`). Do not add that import to new code --
  use `NotifierProvider` and `AsyncNotifierProvider` instead.
- There is one `Ref`. The per-provider `FooRef` subtypes and the
  `AutoDisposeRef` / `FutureProviderRef` family are gone, so a generated
  provider's callback takes a plain `Ref`.
- `Ref.mounted` exists, mirroring `BuildContext.mounted`. Check it after an
  `await` before touching `state`.

```dart
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
}
```

## Failures and lifecycle

- Failing providers retry automatically with exponential backoff. That is on by
  default, so a provider stuck in `AsyncError` may re-enter `AsyncLoading` on
  its own. Turn it off per provider with `retry: (count, error) => null`, or
  globally on `ProviderScope`/`ProviderContainer`.
- A read that throws surfaces as a `ProviderException` wrapping the original.
  `AsyncValue.error`, `ref.listen(onError:)` and `ProviderObserver` still see
  the original error, so match on those rather than on `try`/`catch` around
  `ref.read`.
- Listeners inside widgets that are not visible are paused (Riverpod follows
  `TickerMode`). Do not rely on a provider continuing to tick while its widget
  is off-screen -- put anything that must keep running behind an explicit
  `ref.keepAlive()` or a service the provider reads.

<!--boost:if usesRiverpodGenerator-->
## Code generation

- The generated callback takes `Ref`, never `UserRef`.
- Generated providers may declare type parameters in Riverpod 3; a generic
  `@riverpod` function or class is supported.
- Rebuild after any annotation change with
  `{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

## Experimental

Offline persistence (`persist` / `@JsonPersist`) and mutations are shipped but
marked experimental. Do not reach for either unless the task asks for it, and
say so in the code review when you do.

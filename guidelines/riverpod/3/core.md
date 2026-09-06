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
  provider's callback takes a plain `Ref`. There is likewise no
  `AutoDisposeNotifier`: `Notifier` and `AsyncNotifier` cover both lifetimes
  and the provider's `.autoDispose` modifier decides.
- **A notifier is recreated on every provider rebuild.** Anything you stashed
  in a field rather than in `state` is gone after a dependency changes. This is
  what makes `Ref.mounted` reliable, and it is a behaviour change from
  Riverpod 2, where the instance was reused.
- `Ref.mounted` exists, mirroring `BuildContext.mounted`. Check it after an
  `await` before touching `state`. Every other `Ref` and notifier member throws
  once the provider is disposed -- in Riverpod 2 several of them no-oped.

```dart
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
}
```

## Failures and lifecycle

- `AsyncValue.value` returns `null` in the error state instead of throwing, and
  `AsyncValue.valueOrNull` has been removed -- `.value` is the safe read now.
  Use `requireValue` where you want the throw, including when combining async
  providers synchronously inside another provider's body.
- Failing providers retry automatically with exponential backoff. That is on by
  default, so a provider stuck in `AsyncError` may re-enter `AsyncLoading` on
  its own. Turn it off per provider with `retry: (count, error) => null`, or
  globally on `ProviderScope`/`ProviderContainer`.
- A read that throws surfaces as a `ProviderException` wrapping the original.
  `AsyncValue.error`, `ref.listen(onError:)` and `ProviderObserver` still see
  the original error, so match on those rather than on `try`/`catch` around
  `ref.read`.
- Listeners inside widgets that are not visible are paused (Riverpod follows
  `TickerMode`), and a provider counts as paused once *all* of its listeners
  are -- including a provider watched only by another paused provider. Do not
  rely on a provider continuing to tick off-screen; put anything that must keep
  running behind an explicit `ref.keepAlive()` or a service the provider reads.
- `ProviderObserver` is a `base` class and every callback takes a
  `ProviderObserverContext` rather than loose positional arguments. A Riverpod 2
  observer is a rewrite, not a recompile.

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

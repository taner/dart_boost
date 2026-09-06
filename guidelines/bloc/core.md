# Bloc

- Reach for `Cubit` first. Add a `Bloc` when you need the event log, an event
  transformer (debounce, drop-while-busy), or a genuinely event-sourced flow.
  A `Cubit` is a `Bloc` without the event plumbing, not a lesser one.
- States and events are immutable values with real equality -- `Equatable`,
  `freezed`, or a hand-written `==` and `hashCode`. `emit` compares with `==`
  and silently drops an equal state, so a state class without equality rebuilds
  the world and a mutated-in-place state rebuilds nothing.
- One sealed state hierarchy per bloc, so the UI can `switch` exhaustively
  instead of reading nullable fields off a single class with a status enum.
- Register one handler per event type in the constructor with `on<Event>`.
  Adding an event that has no registered handler throws `StateError`.
- `emit` is valid only while its handler is running. Never capture it in a
  stream callback or a timer, and after any `await` either check `emit.isDone`
  or do not emit at all. `emit` is never reachable from a widget.
- Consume a stream with `await emit.forEach(stream, onData: ...)` or
  `emit.onEach`, not a manual `listen`: both keep the handler alive for the
  stream's lifetime, forward errors, and stop when the bloc closes. Awaiting
  them is required -- an unawaited call trips an assertion.
- A bloc knows nothing about Flutter: no `BuildContext`, no `Navigator`, no
  widgets. It takes repositories through its constructor, which is exactly what
  lets it be tested with no widget tester.
- The default transformer is concurrent, so two fast taps run two handlers at
  once and may emit out of order. Pull in `bloc_concurrency` and pick
  `droppable`, `restartable` or `sequential` wherever ordering or
  de-duplication matters.
- Cancel subscriptions and controllers in `close()`, then call `super.close()`.

<!--boost:if usesFlutterBloc-->
## Widgets

- `BlocProvider(create: ...)` owns the bloc and closes it. `BlocProvider.value`
  does not close anything -- use it only to hand an *existing* bloc to a new
  subtree (a pushed route, a dialog). Passing a freshly constructed bloc to
  `.value` leaks it.
- `BlocBuilder` renders, `BlocListener` runs one-shot side effects (navigation,
  snackbars, dialogs), `BlocConsumer` does both, `BlocSelector` narrows to one
  field. Navigating from a `builder` fires again on every rebuild -- that
  belongs in a listener.
- `context.read<T>()` in callbacks, `initState` and event handlers;
  `context.watch<T>()` and `context.select` only inside `build`.
- Prefer `buildWhen` / `listenWhen` over splitting a state class just to
  control rebuilds.
- Provide repositories with `RepositoryProvider` above the blocs that need
  them, and use `MultiBlocProvider` rather than nesting providers by hand.
<!--boost:end-->

<!--boost:if usesBlocTest-->
## Testing

`blocTest` builds the bloc, acts on it, and compares against the states emitted
*after* the initial one. It fails on extra as well as missing states, so write
the whole expected sequence, and give `wait:` a duration when a transformer
debounces.

```dart
blocTest<CounterBloc, int>(
  'emits [1] when Increment is added',
  build: () => CounterBloc(),
  act: (bloc) => bloc.add(Increment()),
  expect: () => const <int>[1],
);
```
<!--boost:end-->

# Bloc 7

This project resolves bloc 7, which predates the `on<Event>` rewrite. Most
published bloc guidance -- including the shared section above -- is written for
bloc 8 or later and does not compile here unless you are on 7.2.

- `on<Event>` and `Emitter` only exist from 7.2.0. Below that the bloc's whole
  behaviour is one `Stream<State> mapEventToState(Event event)` that yields
  states, `transformEvents` reorders the event stream, and `transformTransitions`
  filters the output. If you are on 7.2, `on<Event>` is available and
  `mapEventToState` is deprecated -- write new handlers with `on<Event>`.
- The observer is a plain static: `Bloc.observer = MyBlocObserver();` in
  `main`. `BlocOverrides.runZoned` is a bloc 8.0 API and does not exist here.
- Adding an event to a closed bloc, or emitting from one, is ignored rather
  than throwing. Bloc 8 turns both into a `StateError`, so code that quietly
  works today will start failing loudly at upgrade time -- guard on `isClosed`
  now.
- An error escaping a handler is reported as a `BlocUnhandledErrorException`.
  Bloc 8 removes that type and rethrows the original error instead.
- `Cubit.emit` is public here, so a widget *can* call it. Do not: bloc 8 makes
  it `protected` and every such call site becomes a compile error.

Bloc 7 has been unsupported since January 2022. Treat the migration to bloc 8
(`mapEventToState` to `on<Event>`) as the fix for anything awkward in this
list, and do not add new `mapEventToState` blocs.

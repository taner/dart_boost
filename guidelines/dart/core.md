# Dart

Dart {{ dartVersion }} resolved this project's package graph. Everything below
is available on that version; nothing below needs an experiment flag.

## Types

- Sound null safety everywhere. Do not add `!` to silence the analyzer -- it
  is a claim about runtime that you must be able to justify.
- Use `Object` rather than `dynamic`. `dynamic` disables every check that
  makes the analyzer useful, and it does it silently.
- Prefer `final` for locals and fields that are not reassigned; prefer `const`
  when the value is known at compile time.
- Prefer `sealed` or `final` classes over open inheritance for types you own.
  `sealed` is what makes a `switch` exhaustive, which is what makes the
  analyzer tell you about the variant you forgot.

## Control flow

- Use exhaustive `switch` expressions over `if` chains on a sealed type or an
  enum. Never add a `default` clause to an exhaustive switch -- it converts a
  future compile error into a silent fallthrough.
- Use destructuring patterns instead of positional access on records and
  known-shape maps.
- Use a record for a small unnamed tuple of values. Reach for a class as soon
  as the fields want names, invariants or methods.

```dart
sealed class Result<T> {}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final Object error;
}

String describe(Result<int> result) => switch (result) {
  Ok(:final value) => 'ok $value',
  Err(:final error) => 'failed: $error',
};
```

## Modern syntax worth using

These read better than the workarounds they replace, and the analyzer accepts
them on this SDK:

- Dot shorthands for a known context type: `Alignment.center` becomes
  `.center` when the parameter type already says `Alignment`.
- Null-aware elements in collection literals: `[a, ?maybeB]` instead of
  `[a, if (maybeB != null) maybeB]`.
- Wildcards for bindings you do not use: `for (final _ in items)`,
  `(_, second)`.
- Digit separators for long literals: `1_000_000`, `0xFF_FF_00`.

## Asynchrony

- Never leave a `Future` unawaited by accident. If it is deliberate, say so
  with `unawaited(...)` from `dart:async` and explain why in a comment.
- Do not use `async` on a function that only forwards a `Future` -- return it.
- Prefer `Future.wait` over sequential awaits for independent work, and handle
  the fact that it reports only the first error.
- A `Stream` you subscribe to is a resource. Cancel the subscription in the
  same object that created it.

## Errors

- Throw a specific type, not `Exception('...')`, for anything a caller might
  want to distinguish.
- Catch narrowly. A bare `catch (e)` with no `on` clause also swallows the
  programming errors you wanted to see.
- Use `ArgumentError`/`StateError` for contract violations by the caller and
  reserve custom exceptions for conditions the caller can act on.
- Rethrow with `rethrow`, never `throw e` -- the second one discards the
  original stack trace.

## Style and tooling

- `{{ formatCommand }}` owns formatting. Do not hand-format around it, and do
  not add a trailing comma to force a split -- the current formatter decides
  line breaking from width, not from your commas. Set `formatter: page_width:`
  in `analysis_options.yaml` if the default width is wrong for this project.
- `{{ dartCommand }} fix --apply` clears mechanical lints. Read the diff before
  committing it; some fixes are library migrations, not cleanups.
- Public API gets doc comments. Private helpers get a comment only when the
  *why* is not obvious from the code.
- Do not commit `print`. Use the project's logger, or `debugPrint` in Flutter
  code.

<!--boost:if usesCodegen-->
## Code generation

This project uses `build_runner`. After editing any annotated source, run
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.

- Never hand-edit a `.g.dart`, `.freezed.dart` or `.mocks.dart` file -- the
  next build discards your change.
- A missing generated member is almost always a build you have not run yet,
  not an API that does not exist. Build first, then read the error.
- Use `watch` instead of `build` while iterating, and stop it before you run
  the analyzer so the two do not race on the same outputs.
<!--boost:end-->

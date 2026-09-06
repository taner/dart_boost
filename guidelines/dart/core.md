# Dart

Dart {{ dartVersion }} is what resolved this project's package graph.

## Language

- Sound null safety everywhere. Do not add `!` to silence the analyzer --
  it is a claim about runtime that you must be able to justify.
- Prefer `final` for locals and fields that are not reassigned.
- Use pattern matching and exhaustive `switch` expressions over long `if`
  chains on a sealed type; the analyzer will then tell you when a new variant
  is unhandled.
- Prefer `sealed` or `final` classes over open inheritance for types you own.
- Use `Object` rather than `dynamic`. `dynamic` disables every check that
  makes the analyzer useful.

## Errors

- Throw specific exception types, never bare `Exception('...')` for something a
  caller might want to distinguish.
- Catch narrowly. `catch (e)` with no `on` clause also swallows programming
  errors you wanted to see.
- Never leave a `Future` unawaited by accident; if it is deliberate, say so
  with `unawaited(...)`.

## Style

- `dart format` decides formatting. Do not hand-format around it.
- Public API gets doc comments; private helpers get a comment only when the
  *why* is not obvious from the code.

```dart
// Prefer expressing intent in the type, not in a comment.
sealed class Result<T> {}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final Object error;
}
```

<!--boost:if usesCodegen-->
## Code generation

This project uses `build_runner`. After editing any annotated source, run
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.

Never hand-edit a `.g.dart` or `.freezed.dart` file -- the next build discards
your change.
<!--boost:end-->

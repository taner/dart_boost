# Freezed 3

This project resolves Freezed 3. Several Freezed 2 habits no longer compile.

- **`when` and `map` are gone**, along with `maybeWhen`, `whenOrNull` and
  `maybeMap`. Use Dart pattern matching. A `sealed` union makes the `switch`
  exhaustive, so the analyzer tells you when a new case is unhandled.
- **A Freezed class must be `abstract`, `sealed`, or manually implement
  `_$MyClass`.** A bare `@freezed class Foo with _$Foo` from Freezed 2 is an
  error here: use `sealed` for a union and `abstract` for a single-constructor
  model.
- **Mixed mode:** a simple model no longer needs factory syntax. Declare normal
  final fields and a normal constructor, and Freezed still generates `==`,
  `hashCode`, `toString` and `copyWith`. Reserve the factory syntax for unions.
- The private `MyClass._()` constructor may now take parameters. That is what
  unlocks `extends` and non-constant defaults: factory constructors forward to
  it by name.
- A union case can be *ejected* -- point the factory at a class you wrote
  yourself and Freezed leaves it alone. The hand-written case must `extends`
  the parent (Dart has no `sealed mixin class`).
- Generated files start with `// dart format off` when formatting is disabled,
  so a formatting CI check no longer needs to exclude them.

```dart
// Simple model: no factory syntax needed.
@freezed
abstract class User with _$User {
  User({required this.id, required this.name});

  final String id;
  final String name;
}

// Union: sealed, factory constructors, non-constant default via `._()`.
@freezed
sealed class Response<T> with _$Response<T> {
  Response._({DateTime? at}) : at = at ?? DateTime.now();

  factory Response.data(T value, {DateTime? at}) = ResponseData<T>;
  factory Response.error(Object error) = ResponseError<T>;

  @override
  final DateTime at;
}

String describe(Response<int> r) => switch (r) {
  ResponseData(:final value) => 'ok $value',
  ResponseError(:final error) => 'err $error',
};
```

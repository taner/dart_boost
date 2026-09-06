# Freezed 2

This project resolves Freezed 2. Guidance written for Freezed 3 will not build
here.

- Every Freezed class is declared `@freezed class X with _$X` and all its
  fields come from `factory` constructors. There is no plain-class mode -- that
  arrives in 3.
- `when`, `map`, and their `maybeWhen` / `whenOrNull` / `maybeMap` variants
  exist here. They still work, but prefer Dart pattern matching: 3 removes them
  outright, and a `switch` is what will survive the upgrade.
- Adding a getter or a method to a Freezed class requires a private
  `const X._();` constructor, and that constructor must take **no parameters**.
- No `extends`, and no non-constant defaults. If a model needs either, keep it
  a hand-written class.
- `@unfreezed` gives mutable fields when you genuinely need them; the default
  is immutable and should stay that way.

```dart
@freezed
class Response with _$Response {
  const Response._();

  const factory Response({
    required String body,
    @Default(200) int status,
  }) = _Response;

  bool get isOk => status == 200;
}
```

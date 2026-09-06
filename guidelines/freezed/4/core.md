# Freezed 4

This project resolves Freezed 4. It keeps everything Freezed 3 introduced and
adds one breaking change.

- **`final` is no longer allowed inside a constructor parameter list.** Dart
  3.13 removed that syntax, so `@unfreezed` can no longer declare immutable
  fields that way -- drop the keyword, and if the field must stay immutable use
  a plain `@freezed` class instead.
- Primary constructors are supported, and the analyzer floor is 13.0. Freezed 4
  pairs with `freezed_annotation` 3.1.
- **A Freezed class must be `abstract`, `sealed`, or manually implement
  `_$MyClass`** -- unchanged from 3, and still the most common upgrade error
  coming from 2.
- **`when` / `map` and their variants do not exist.** Match with a `switch`
  over a `sealed` union so the analyzer catches an unhandled case.
- Mixed mode: a single-shape model is a normal class with normal final fields
  and a normal constructor. Factory syntax is for unions.
- The private `MyClass._()` constructor takes parameters, which is what enables
  `extends` and non-constant defaults; factory constructors forward to it by
  name.
- A union case can be ejected to a hand-written class that `extends` the
  parent.

```dart
@freezed
abstract class User with _$User {
  User({required this.id, required this.name});

  final String id;
  final String name;
}

@freezed
sealed class Response<T> with _$Response<T> {
  Response._({DateTime? at}) : at = at ?? DateTime.now();

  factory Response.data(T value, {DateTime? at}) = ResponseData<T>;
  factory Response.error(Object error) = ResponseError<T>;

  @override
  final DateTime at;
}
```

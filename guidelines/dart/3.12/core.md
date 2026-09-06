# Dart 3.12

Guidance for Dart 3.12 specifically. This project resolved Dart
{{ dartVersion }}, and several things written for Dart 3.13 do not analyze
here.

## Not available on this SDK

- **Primary constructors.** `class Money(final int cents);` needs Dart 3.13 --
  on 3.12 it fails with `experiment_not_enabled`. Write the ordinary
  constructor with `this.` parameters, and do not add
  `--enable-experiment=primary-constructors` to work around it.
- **`List.unmodifiableOf` / `Map.unmodifiableOf`.** Use `List.unmodifiable`
  and `Map.unmodifiable`, which are the same constructors under their older
  names.
- **`int.oneBitCount` / `int.trailingZeroBitCount`.** Count the bits yourself,
  or take the dependency; there is no core-library popcount here.
- **`Future.pause(duration)`.** Use `Future.delayed(duration)`.

```dart
// The 3.12 spelling of a value class.
class Money {
  const Money(this.cents, this.currency);

  final int cents;
  final String currency;
}
```

## Private named parameters are new here

3.12 is the release that lets a private field be initialized from a named
parameter. `this._value` in a named parameter position declares the parameter
as `value` at the call site and assigns the private field, so a class no
longer has to choose between a private field and a named constructor
argument.

```dart
class Session {
  Session({required this._token, this._retries = 0});

  final String _token;
  final int _retries;

  bool get isValid => _token.isNotEmpty && _retries < 3;
}

final session = Session(token: 'abc', retries: 1);
```

Do not reintroduce the old workarounds -- a public field you did not want, a
positional parameter, or a `_token` argument name that leaks the underscore
into the API.

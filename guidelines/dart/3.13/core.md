# Dart 3.13

Guidance for Dart 3.13 specifically. This project resolved Dart
{{ dartVersion }}, so everything below analyzes without an experiment flag --
and none of it compiles on a 3.12 checkout of the same code.

## Primary constructors

3.13 is the release that stabilizes them. A parameter list on the *class
header* declares the constructor, and each `final`/`var` parameter also
declares the matching field, so a value class is one line and has no
assignment boilerplate.

Prefer the header form for value classes, DTOs and any class whose
constructor only assigns fields. Keep a body constructor when the constructor
has to do work.

```dart
class Point(final int x, final int y) {
  double get magnitude => (x * x + y * y).toDouble();
}
```

The rules that actually bite:

- **`final` or `var` makes a field; a bare type does not.** `class W(int seed)`
  declares a parameter, not a field. It is in scope in *field initializers*
  (`final int start = seed * 2;`) and nowhere else -- methods cannot see it.
- **`const` goes on the class, not the constructor:** `class const
  Temp.celsius(final double degrees);` A header constructor may be named.
- **There is no initializer list.** `class A(int seed) : start = seed;` does
  not parse. Initialize in the field declaration instead.
- **There is no superclass argument list.** `class D(...) extends Base(id);`
  does not parse either. Forward with `super.` parameters:
  `class Derived(super.id, final String label) extends Base;`
- **A body constructor can redirect to the header one:**
  `Money.dollars(int d) : this(d * 100);`
- Named and optional parameters, defaults, `required`, annotations and doc
  comments all work in the header exactly as they do in a normal parameter
  list.
- Enums take a header constructor too:
  `enum Suit(final String glyph) { hearts('H'), spades('S') }`
- A class with a header constructor and nothing else ends in `;`, with no
  braces.

```dart
class Base(final int id);

class Derived(super.id, final String label) extends Base;

class Window(int seed, {final String title = 'untitled'}) {
  final int start = seed * 2;
}
```

Do not convert a whole codebase mechanically. Rewrite a class when you are
already editing it, and leave classes whose constructors validate, compute or
call `super` with real arguments alone.

## Core library additions

These do not exist on 3.12, so do not introduce them into a package whose
`environment: sdk:` lower bound is below `3.13.0`:

- `List.unmodifiableOf(elements)` and `Map.unmodifiableOf(other)` -- aliases
  for the `unmodifiable` constructors that read as the `of`-family
  counterparts they sit next to.
- `int.oneBitCount` and `int.trailingZeroBitCount` -- popcount and
  lowest-set-bit position. Both count against the platform integer width, so
  `(-1).oneBitCount` is 64 natively and 32 on the web.
- `Future.pause([duration])` -- `Future.delayed` without a computation, so it
  cannot complete with an error. Use it instead of
  `Future.delayed(d, () {})`.

`dart:isolate` also gained the synchronous `Isolate.create` / `runSync` /
`shutdownSync` / `runEventLoopSync` embedder API. It is for native code
driving a Dart isolate from a foreign event loop, not for application-level
concurrency -- keep using `Isolate.run`.

## Not new here

Augmentations (`augment class`), enhanced parts (a part file with its own
imports) and static extension members (`extension on F { static F make() }`
called as `F.make()`) are still experiments on this SDK. They do not analyze,
and enabling the experiment flag to use them is not an option this project
takes.

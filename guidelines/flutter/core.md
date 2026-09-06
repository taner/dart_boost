# Flutter

This project targets Flutter {{ flutterVersion }} ({{ flutterChannel }}).

## Widgets

- Compose small widgets rather than returning big trees from helper *methods*.
  A `Widget` subclass gets a `const` constructor and its own rebuild boundary;
  a `_buildFoo()` method gets neither.
- Add `const` wherever the analyzer allows it.
- Keep `build` free of side effects and expensive work. Anything that allocates
  or computes belongs in `initState`, a provider, or a memoised field.
- Prefer `ListView.builder` over `ListView(children: [...])` for any list whose
  length is not a small constant.

## State and lifecycle

- Dispose every `Controller`, `FocusNode`, `StreamSubscription` and
  `AnimationController` you create.
- Do not touch `BuildContext` across an `await` without checking `mounted`
  first.

```dart
Future<void> _save() async {
  await repository.save(draft);
  if (!mounted) return;
  Navigator.of(context).pop();
}
```

## Layout and platform

- Read sizing from `LayoutBuilder` or `MediaQuery` rather than hard-coding
  pixel values.
- Guard platform-specific code with `Theme.of(context).platform` or
  `defaultTargetPlatform`, not `dart:io`'s `Platform` -- that one throws on web.

## Testing

- `{{ testCommand }}` runs the suite. Widget tests are cheap; write one for
  every non-trivial widget rather than reaching for an integration test.
- Use `tester.pumpAndSettle()` only when you actually need every animation to
  finish; otherwise pump a fixed duration so a stuck animation fails loudly
  rather than hanging.

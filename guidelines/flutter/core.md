# Flutter

This project targets Flutter {{ flutterVersion }} ({{ flutterChannel }}).
Version-specific guidance for the {{ flutterMinor }} line, if any, follows this
section.

## Widgets

- Compose small `Widget` subclasses rather than returning big trees from
  helper *methods*. A subclass gets a `const` constructor and its own rebuild
  boundary; a `_buildFoo()` gets neither and rebuilds with its parent.
- Add `const` wherever the analyzer allows it. It is the cheapest performance
  work available and it also stops needless rebuilds.
- Keep `build` pure: no I/O, no allocation of controllers, no `setState`, no
  side effects. Anything expensive belongs in `initState`, a provider, or a
  memoised field.
- Prefer `ListView.builder` / `SliverList.builder` over `ListView(children:)`
  for any list whose length is not a small constant.
- Give a `Key` to widgets in a list whose identity outlives their position.
  Without one, Flutter reuses the wrong element when items reorder.

## State and lifecycle

- Dispose everything you create: `TextEditingController`, `FocusNode`,
  `ScrollController`, `AnimationController`, `StreamSubscription`, `Ticker`.
  A `dispose` that is missing one of them is the standard memory leak here.
- Do not touch `BuildContext` across an `await` without checking `mounted`
  first. This is a lint (`use_build_context_synchronously`), not a style note.
- Keep `setState` bodies to the assignment. Compute before the call, so a
  thrown exception cannot leave the widget half-updated.
- Handle changed configuration in `didUpdateWidget`, not by comparing in
  `build`.

```dart
Future<void> _save() async {
  await repository.save(draft);
  if (!mounted) return;
  Navigator.of(context).pop();
}
```

## Layout

- Read sizing from `LayoutBuilder`, `MediaQuery.sizeOf(context)` or the theme
  rather than hard-coding pixel values. Prefer the `.sizeOf`/`.paddingOf`
  accessors over `MediaQuery.of(context)`, which rebuilds on every change.
- `Expanded`/`Flexible` only inside a `Row`, `Column` or `Flex`. Unbounded
  constraints plus an unbounded child is the "RenderBox was not laid out"
  error you will otherwise spend an hour on.
- `IntrinsicHeight`, `IntrinsicWidth` and unbounded `shrinkWrap: true` lists
  are the expensive escape hatches. Use them knowingly, not by default.

## Theming and platform

- Take colours and text styles from `Theme.of(context)` /
  `ColorScheme.of(context)`. A hard-coded `Color(0xFF...)` in a widget is a
  dark-mode bug waiting to happen.
- Build the scheme with `ColorScheme.fromSeed` so light and dark stay in step.
- Branch on `Theme.of(context).platform` or `defaultTargetPlatform`, never on
  `dart:io`'s `Platform` -- that one throws on web.
- Impeller is the default renderer, with the legacy backend still reachable
  behind `--no-enable-impeller`. When you report a shader or raster problem,
  say which renderer you tested on.

## Iterating

- `flutter run` then hot reload (`r`) for widget and build-method changes. Hot
  restart (`R`) is required for `main()`, global state, `initState` shape and
  anything `const`-folded.
- Annotate a widget with `@Preview` and run
  `{{ flutterCommand }} widget-preview start` to iterate on it without booting
  the whole app.
- Profile with `{{ flutterCommand }} run --profile`. Debug-mode frame times
  are not evidence of anything.

## Assets and dependencies

- Declare every asset and font in `pubspec.yaml`. A file in `assets/` that is
  not declared is absent at runtime, and the failure is a load exception, not
  a build error.
- Platform channels and plugins need a full restart after
  `{{ pubGetCommand }}`; a hot reload will not register a new plugin.

# go_router 16

This project resolves go_router 16.

- **URLs are case-sensitive.** `/Home` and `/home` are distinct routes. Opt out
  per route with `caseSensitive: false` on the `GoRoute`.
- 16.3 adds a top-level `onEnter` callback on `GoRouter`, evaluated *before*
  the `redirect` chain. Return `Allow()` or `Block()`; both take an optional
  `then:` callback that runs after the decision is committed. Use it for the
  interception `redirect` cannot express -- a confirmation dialog, an
  analytics hop -- and keep pure URL rewriting in `redirect`.
- `ShellRoute` navigation does **not** notify the root router's observers in
  16; attach observers to the shell's own `navigatorKey`. 17 changes this.

<!--boost:if usesGoRouterBuilder-->
## Type-safe routes

16 requires `go_router_builder` >= 3.0.0. Two things changed with it:

- The route class applies the generated mixin: `with _$SongRoute`. Omitting it
  is the most common upgrade error and shows up as a missing-override analyzer
  failure.
- `GoRouteData` itself now defines `.location`, `.go(context)`,
  `.push(context)`, `.pushReplacement(context)` and `.replace(context)`, so the
  generated extension from builder 2.x is gone.

```dart
part 'routes.g.dart';

@TypedGoRoute<SongRoute>(path: '/song/:id')
class SongRoute extends GoRouteData with _$SongRoute {
  const SongRoute({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      SongScreen(id: id);
}

// Navigate with the object, not a string.
const SongRoute(id: 2).go(context);
```

Rebuild after touching a route class with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

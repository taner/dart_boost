# go_router 14

This project resolves go_router 14. Guidance written for 15+ does not apply.

- Path matching is **case-insensitive** here: `/Home` and `/home` reach the
  same route. 15 flipped that default, so do not build anything that depends
  on it.
- There is no top-level `onEnter` callback (16.3 adds it). Interception happens
  in `redirect`, which must stay side-effect free -- it can run several times
  for one navigation.
- `GoRouteData.onExit` takes two arguments here,
  `(BuildContext context, GoRouterState state)`. The single-argument form from
  13 no longer compiles.
- `ShellRoute` navigation does **not** notify the root router's observers.
  Analytics that listens on `GoRouter.observers` will miss in-shell
  navigations; attach an observer to the shell's own `navigatorKey` instead.

<!--boost:if usesGoRouterBuilder-->
## Type-safe routes

With `go_router_builder` 2.x a route class only `extends GoRouteData` -- there
is no `_$` mixin, and the navigation helpers arrive as a generated extension on
the class.

```dart
part 'routes.g.dart';

@TypedGoRoute<SongRoute>(path: '/song/:id')
class SongRoute extends GoRouteData {
  const SongRoute({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      SongScreen(id: id);
}
```

Rebuild after touching a route class with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

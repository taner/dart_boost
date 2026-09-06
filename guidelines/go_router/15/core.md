# go_router 15

This project resolves go_router 15.

- **URLs are case-sensitive** from 15.0.0 on. `/Home` no longer matches
  `/home`. If you are upgrading from 14 and relied on the old behaviour, set
  `caseSensitive: false` on the individual `GoRoute` rather than lowercasing
  links across the app.
- `caseSensitive` also exists on `TypedGoRoute` (15.1.0) and on
  `GoRouteData.$route` (15.1.1).
- There is no top-level `onEnter` callback (16.3 adds it). Interception happens
  in `redirect`, which must stay side-effect free.
- `ShellRoute` navigation does **not** notify the root router's observers;
  attach observers to the shell's own `navigatorKey` if you need those events.

<!--boost:if usesGoRouterBuilder-->
## Type-safe routes

Which form to write depends on the builder, and 15.x spans both:

- `go_router_builder` 2.x -- the route class only `extends GoRouteData`, and
  navigation helpers come from a generated extension.
- `go_router_builder` 3.x (needs go_router >= 15.2.0) -- apply the generated
  mixin and call the helpers on the route object itself.

Check the resolved `go_router_builder` version before writing either form, and
prefer the 3.x mixin for new code since 16 makes it the only option.

```dart
@TypedGoRoute<SongRoute>(path: '/song/:id')
class SongRoute extends GoRouteData with _$SongRoute {
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

# go_router 18

This project resolves go_router 18.

- 18.0.0 migrates the package to `material_ui` / `cupertino_ui` and raises the
  floor to **Flutter 3.44 / Dart 3.12**. If `pub get` refuses go_router 18, the
  SDK is the constraint, not the dependency graph.
- **URLs are case-sensitive.** Opt out per route with `caseSensitive: false` on
  the `GoRoute`.
- `ShellRoute` navigation notifies the root `GoRouter`'s observers by default
  (since 17). Set `notifyRootObserver: false` on the shell if a root observer
  should not see in-shell navigations.
- The top-level `onEnter` callback receives
  `(context, currentState, nextState, goRouter)` and returns `Allow()` or
  `Block()`, both taking an optional `then:` callback that runs after the
  decision is committed. It is evaluated **before** the `redirect` chain, so
  put "may this navigation happen at all" in `onEnter` and "where should this
  URL actually land" in `redirect`.
- Route `metadata` is inherited by child routes, overridable per route, and
  readable as `state.metadata`. Use it for per-route policy (auth required, an
  analytics screen name) instead of a side table keyed by path.
- `GoRoute.path` accepts regular-expression constraints on path parameters, so
  `/:id(\d+)` will not match `/abc`.

```dart
final router = GoRouter(
  onEnter: (context, current, next, goRouter) async {
    if (next.metadata['requiresAuth'] == true && !authState.isLoggedIn) {
      return Block(then: () => goRouter.go('/login'));
    }
    return const Allow();
  },
  routes: [
    GoRoute(
      path: '/orders/:id(\\d+)',
      metadata: const {'requiresAuth': true},
      builder: (context, state) =>
          OrderScreen(id: state.pathParameters['id']!),
    ),
  ],
);
```

<!--boost:if usesGoRouterBuilder-->
## Type-safe routes

Requires `go_router_builder` >= 3.0.0. The route class applies the generated
mixin (`class SongRoute extends GoRouteData with _$SongRoute`) and navigation
helpers live on `GoRouteData` itself: `.location`, `.go(context)`,
`.push(context)`, `.pushReplacement(context)`, `.replace(context)`.

Use `hasOverriddenOnExit: true` on the `$route` helper when a route data class
overrides `onExit`, and `TypedQueryParameter` when a query parameter's wire
name or encoding differs from the Dart field.

Rebuild after touching a route class with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

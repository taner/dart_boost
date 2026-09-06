# go_router 17

This project resolves go_router 17.

- **BREAKING vs 16:** `ShellRoute` navigation now notifies the root
  `GoRouter`'s observers by default. If your analytics or logging observer was
  attached to `GoRouter.observers` it will start seeing in-shell navigations it
  never saw before -- dedupe there, or set `notifyRootObserver: false` on the
  `ShellRouteBase` (also available on `ShellRoute`, `StatefulShellRoute`,
  `ShellRouteData.$route`, `TypedShellRoute` and `TypedStatefulShellRoute`).
- **URLs are case-sensitive.** Opt out per route with `caseSensitive: false`.
- The top-level `onEnter` callback receives
  `(context, currentState, nextState, goRouter)` and returns `Allow()` or
  `Block()`. It runs *before* the `redirect` chain. Both results take an
  optional `then:` callback that runs once the decision is committed.
  Blocking the very first navigation with no route to fall back to raises
  `BlockedInitialNavigationException` (17.4), a `GoException` subtype you can
  match on in `onException` instead of matching error strings.
- 17.5 adds route `metadata`, inherited by child routes and readable as
  `state.metadata` -- the right place for "this route requires auth" or an
  analytics screen name, rather than a parallel map keyed by path.

```dart
final router = GoRouter(
  onEnter: (context, current, next, goRouter) async {
    if (next.uri.path == '/checkout' && !authState.isLoggedIn) {
      return Block(then: () => goRouter.go('/login'));
    }
    return const Allow();
  },
  routes: routes,
);
```

<!--boost:if usesGoRouterBuilder-->
## Type-safe routes

Requires `go_router_builder` >= 3.0.0. Apply the generated mixin
(`class SongRoute extends GoRouteData with _$SongRoute`) and navigate on the
route object -- `GoRouteData` defines `.location`, `.go`, `.push`,
`.pushReplacement` and `.replace` directly.

17.3 adds `hasOverriddenOnExit` to the `$route` helpers, so a route data class
that overrides `onExit` actually has it invoked; pass `true` when you rely on
that.

Rebuild after touching a route class with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.
<!--boost:end-->

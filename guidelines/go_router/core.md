# go_router

- Build the `GoRouter` **once** and hold it outside the widget tree -- a
  top-level `final`, a provider, or a DI singleton. A router rebuilt inside
  `build` resets the navigation stack on every frame.
- Wire it with `MaterialApp.router(routerConfig: router)`.
- Declare routes as a *tree*: nesting `routes:` is what produces a back stack.
  A flat list of absolute paths gives you no stack at all.
- Child paths are relative and must not start with `/`. Only top-level routes
  use absolute paths.
- `context.go(...)` replaces the stack; `context.push(...)` stacks on top.
  `go` is the default -- reach for `push` only when the user must be able to
  pop back to exactly where they were.
- Prefer named routes (`name:` plus `context.goNamed(...)`) over hand-built URL
  strings, so a path change breaks in one place instead of ten.
- Read inputs off `GoRouterState`: `state.pathParameters['id']`,
  `state.uri.queryParameters['q']`, `state.matchedLocation`, `state.extra`.
  `state.extra` does not survive a deep link or a web refresh, so never make it
  load-bearing -- put anything the route genuinely needs in the path.
- Guard with `redirect`, never with a navigation call from `build` or
  `initState`. Return `null` to allow, or the location to send the user to.
  Keep it synchronous and cheap: it runs on every navigation and
  `redirectLimit` (default 5) trips on a loop.
- Drive re-evaluation with `refreshListenable:`. Do not rebuild the router to
  make a guard re-run.

```dart
final router = GoRouter(
  initialLocation: '/',
  refreshListenable: authState,
  redirect: (context, state) {
    final atLogin = state.matchedLocation == '/login';
    if (!authState.isLoggedIn) return atLogin ? null : '/login';
    return atLogin ? '/' : null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'song/:id',
          builder: (context, state) =>
              SongScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
  ],
);
```

- Use `ShellRoute` for a shared frame (an app bar, a drawer) and
  `StatefulShellRoute.indexedStack` for bottom-navigation tabs that must each
  keep their own stack. Give every shell its own `navigatorKey`.
- Handle failures with `onException` or `errorBuilder`; the default error
  screen is a debug affordance, not a shipping one.

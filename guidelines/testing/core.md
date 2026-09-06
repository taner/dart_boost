# Testing

`{{ testCommand }}` runs the suite for this project. Run the whole thing before
you call a change finished, not just the file you touched.

## What to write

- Test the behaviour, not the implementation. A test that breaks when you
  rename a private method was testing the wrong thing.
- One reason to fail per test. Assert several things only when together they
  describe one outcome.
- Name the test after the behaviour and the condition: `test('rejects an
  expired token')`, not `test('validate')`.
- When you fix a bug, write the failing test first. A regression test that was
  never seen red is not evidence.
- Prefer real objects over mocks for anything you own. Mock only at the
  process boundary: HTTP, platform channels, the filesystem, the clock.

## How to structure it

- `group` shares setup, not state. `setUp` runs per test for a reason -- never
  hoist mutable state into a `late` top-level to "save time".
- Register cleanup next to the thing that needs it with `addTearDown`, so a
  test that returns early still cleans up.
- Keep fixtures in the test that uses them until a second test needs them.
  A shared builder that every test has to read is worse than duplication.
- Never depend on test order, and never share a temp directory between tests.

```dart
test('rejects an expired token', () {
  final result = validate(Token(expiresAt: clock.now().subtract(oneHour)));

  expect(result, isA<Err<Session>>());
});
```

## Async and flakiness

- `await` or `return` every future in a test body. A dropped future turns a
  failure into a pass.
- Use `expectLater` with `emitsInOrder` for streams rather than collecting
  into a list and sleeping.
- Never call a real `Future.delayed` to wait for something. Inject a clock, or
  use `package:fake_async`.
- No network, no real filesystem outside a temp dir, no wall-clock assertions.
  Those are the three sources of a flaky suite.

<!--boost:if isFlutterProject-->
## Widget tests

- `testWidgets` with a `WidgetTester` is the default tool here. Widget tests
  are cheap; write one for every non-trivial widget instead of reaching for an
  integration test.
- Find by `Key` or by semantics before finding by text. `find.text` couples the
  test to copy and breaks the moment the string is localised.
- `pumpAndSettle()` only when you genuinely need every animation to finish.
  Otherwise `pump(duration)` a fixed amount, so an animation that never
  settles fails loudly instead of hanging until the timeout.
- Wrap the widget in the same `MaterialApp`/`Theme`/localisation ancestors it
  has in the app, or you are testing a widget that does not exist.
- Anything that needs a real event loop -- an actual HTTP client, an
  `Isolate`, a plugin -- goes inside `tester.runAsync`.
- Golden tests are for layout you cannot assert on otherwise. Regenerate with
  `--update-goldens` and *look at the produced image* before committing it.
<!--boost:end-->

<!--boost:if usesMocktail-->
## Mocktail

`when`/`verify` take callbacks, and unstubbed calls throw rather than
returning null. Register a fallback with `registerFallbackValue` for any type
you match with `any()`.
<!--boost:end-->

<!--boost:if usesMockito-->
## Mockito

Mocks are generated. Add `@GenerateNiceMocks` and run
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`; never
hand-edit `*.mocks.dart`.
<!--boost:end-->

<!--boost:if usesIntegrationTest-->
## Integration tests

`integration_test/` runs on a device or emulator and is an order of magnitude
slower than the widget suite. Keep it to the handful of end-to-end paths that
genuinely need a real engine; everything else belongs in a widget test.
<!--boost:end-->

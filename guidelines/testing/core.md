# Testing

`{{ testCommand }}` runs the suite for this project.

- Write the test against the behaviour, not the implementation. A test that
  breaks when you rename a private method was testing the wrong thing.
- One reason to fail per test. `expect` several things only when they describe
  one outcome.
- Use `group` to share setup, not to share state -- `setUp` runs per test for a
  reason.
- Prefer real objects over mocks for anything you own; mock only at the process
  boundary (HTTP, platform channels, clocks).
- When you fix a bug, add the test that would have caught it before you fix it.

```dart
test('rejects an expired token', () {
  final result = validate(Token(expiresAt: clock.now().subtract(oneHour)));

  expect(result, isA<Err<Session>>());
});
```

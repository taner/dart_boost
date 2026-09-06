# Freezed

- Freezed is a code generator, so every model file is a partial: it needs
  `part 'my_model.freezed.dart';` next to the imports, and
  `part 'my_model.g.dart';` as well when the model serialises JSON.
- Never hand-edit a `.freezed.dart` file; the next build discards the change.
  Both generated files are build output -- do not check them in unless the repo
  already does.
- Keep a model file small. `part` is per-library, so twenty models in one file
  means every one of them churns whenever any single field changes.
- Use a **sealed union** only for genuinely alternative shapes (loading / data /
  error). An optional field is a nullable field, not a union case.
- Match a union with Dart pattern matching, not with generated helper methods.
- `@Default(...)` takes a const expression. A `DateTime.now()` default belongs
  in the private constructor, not the annotation.
- Freezed compares collections deeply, so two instances holding equal lists are
  `==`. Do not add your own `==`/`hashCode` -- they will be overwritten.
- `copyWith` cannot distinguish "not passed" from "passed null". For a
  nullable field use the generated nested `copyWith` on that field, or model
  the erasure explicitly.

```dart
@freezed
sealed class Result<T> with _$Result<T> {
  const factory Result.data(T value) = ResultData<T>;
  const factory Result.failure(Object error) = ResultFailure<T>;
}

String describe(Result<int> result) => switch (result) {
  ResultData(:final value) => 'got $value',
  ResultFailure(:final error) => 'failed: $error',
};
```

<!--boost:if usesJsonSerializable-->
JSON support is `json_serializable` underneath: add `part 'x.g.dart';` and a
`factory X.fromJson(Map<String, Object?> json) => _$XFromJson(json);`. Freezed
writes `toJson` for you -- do not declare one by hand.
<!--boost:end-->

Rebuild after any annotation change with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`, or keep
`{{ dartRunCommand }} build_runner watch -d` running while you iterate.

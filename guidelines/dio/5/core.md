# Dio 5

This project resolves Dio 5. Anything written for Dio 4 -- which is still most
of what a search turns up -- names types that no longer exist.

- Errors are **`DioException`** with a **`DioExceptionType`**. `DioError` and
  `DioErrorType` are gone. The type values are `connectionTimeout`,
  `sendTimeout`, `receiveTimeout`, `badCertificate`, `badResponse`, `cancel`,
  `connectionError` and `unknown`. Note `badResponse` is 4's `response`, and
  4's catch-all `other` split into `connectionError`, `badCertificate` and
  `unknown` -- so `on DioException` with a `switch` on `type` is exhaustive in
  a way 4 could not be.
- Timeouts are **`Duration`**, not `int` milliseconds:
  `connectTimeout: const Duration(seconds: 5)`. A bare `5000` is a compile
  error, which is the one Dio-4 habit that fails loudly.
- The adapter is **implemented, not extended**, and lives behind a conditional
  import. Use `package:dio/io.dart` for `IOHttpClientAdapter(createHttpClient:)`
  and `package:dio/browser.dart` for `BrowserHttpClientAdapter`. Import neither
  from shared code -- put the adapter behind your own conditional export or the
  web build breaks on `dart:io`.
- `BackgroundTransformer` is the default, so JSON decoding already happens off
  the UI isolate. Do not add an isolate hop of your own for that reason alone.

```dart
final dio = Dio(
  BaseOptions(
    baseUrl: 'https://api.example.com/v1',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ),
);

try {
  final response = await dio.get<Map<String, Object?>>('/users/1');
  return User.fromJson(response.data!);
} on DioException catch (error) {
  throw switch (error.type) {
    DioExceptionType.badResponse => ApiFailure(
      error.response?.statusCode,
    ),
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const TimeoutFailure(),
    DioExceptionType.cancel => const CancelledFailure(),
    _ => NetworkFailure(error.message),
  };
}
```

- Build a failure with `DioException.badResponse(...)`,
  `DioException.connectionError(...)` and friends rather than the raw
  constructor; an interceptor that rejects with a hand-rolled exception loses
  `requestOptions` and breaks retry logic downstream.
- `error.response` is null for every transport-level failure. Check the type
  before reading a status code.
- Set `dio.options.validateStatus` only when the caller genuinely inspects an
  error body; otherwise let non-2xx throw so the failure mapping stays in one
  place.

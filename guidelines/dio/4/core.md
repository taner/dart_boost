# Dio 4

This project resolves Dio 4. Most Dio guidance online now targets 5, and the
two differ in places that do not fail loudly.

- Errors are **`DioError`** with a **`DioErrorType`**. `DioException` does not
  exist here. `DioErrorType.response` is "the server replied with a status
  `validateStatus` rejected"; `DioErrorType.other` is the catch-all that 5
  splits into `connectionError`, `badCertificate` and `unknown`.
- Timeouts are `int` **milliseconds**, not `Duration`:
  `BaseOptions(connectTimeout: 5000, receiveTimeout: 3000)`. Passing a
  `Duration` is a compile error, and the 5-style code you find online will not
  build.
- The default transformer is `DefaultTransformer`, which decodes on the calling
  isolate. A large JSON response janks the UI -- switch to a background
  transformer or decode off the main isolate yourself. Dio 5 makes
  `BackgroundTransformer` the default.
- `Headers` content-type constants carry `charset=utf-8` here; 5 drops it.
  Compare against the constant rather than a literal string.
- The adapter is **extended**, not implemented: customise TLS or proxying with
  `DefaultHttpClientAdapter` and its `onHttpClientCreate` hook. There is no
  `package:dio/io.dart` / `package:dio/browser.dart` split -- that arrives in
  5.
- `BaseOptions.setRequestContentTypeWhenNoPayload` exists here and is removed
  in 5.

```dart
final dio = Dio(
  BaseOptions(
    baseUrl: 'https://api.example.com/v1',
    connectTimeout: 5000,
    receiveTimeout: 3000,
  ),
);

try {
  final response = await dio.get<Map<String, dynamic>>('/users/1');
  return User.fromJson(response.data!);
} on DioError catch (error) {
  if (error.type == DioErrorType.response) {
    throw ApiFailure(error.response?.statusCode);
  }
  rethrow;
}
```

Upgrading to 5 is mostly mechanical: `DioError` -> `DioException`,
`DioErrorType` -> `DioExceptionType`, and every timeout becomes a `Duration`.

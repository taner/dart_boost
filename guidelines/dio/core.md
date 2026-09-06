# Dio

- One configured `Dio` per API, created once and injected. A `Dio` built per
  request throws away connection pooling and every interceptor you configured.
- Put the invariants in `BaseOptions` -- `baseUrl`, timeouts, default headers --
  so call sites carry only the path and its parameters.
- Interceptors are where cross-cutting behaviour belongs: auth headers,
  logging, retry. Use `QueuedInterceptor` when the handler must not run
  concurrently; a token refresh under parallel 401s is the canonical case.
- An interceptor must call exactly one of `handler.next`, `handler.resolve` or
  `handler.reject` on every path. Forgetting one hangs the request forever.
- Pass a `CancelToken` for any request tied to a widget's lifetime and cancel
  it in `dispose`, otherwise a completed request writes into a disposed state.
- `Response.data` is already decoded -- a `Map` or `List` for JSON. Do not call
  `jsonDecode` on it.
- Never let a Dio exception escape the data layer. Catch at the boundary and
  map to your own failure type; nothing above the repository should import
  `package:dio/dio.dart`.
- Non-2xx responses throw by default. Only change `validateStatus` when the
  caller genuinely wants to inspect an error body, and handle it explicitly
  when you do.
- Use `FormData` for multipart uploads, and `onSendProgress` /
  `onReceiveProgress` for progress. `dio.download` streams to a file rather
  than buffering it in memory.

```dart
final dio = Dio(
  BaseOptions(
    baseUrl: 'https://api.example.com/v1',
    headers: {'accept': 'application/json'},
  ),
)..interceptors.add(AuthInterceptor(tokenStore));
```

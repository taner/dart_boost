# injectable

- Injectable is a **code generator over get_it**: annotations describe the
  registrations, `build_runner` writes them, and `getIt.init()` applies them.
  It does not replace get_it -- everything in the get_it guidance still holds
  for how the resolved objects are used.
- The whole wiring is one file, conventionally `lib/injection.dart`:

```dart
part 'injection.config.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async => getIt.init();
```

- Annotate implementations, not interfaces, and say what to register them as:
  `@Injectable(as: AuthRepository)` or `@LazySingleton(as: AuthRepository)`.
  A bare `@injectable` registers the concrete type only, which defeats the
  point of the indirection.
- `@injectable` is a factory, `@lazySingleton` is the sensible default for a
  stateful collaborator, and `@singleton` constructs eagerly during `init()`.
- **Constructor injection is the whole mechanism.** Injectable reads the
  constructor's parameter types and resolves them; a class that calls
  `getIt<T>()` in its body is invisible to the generator's dependency ordering.
- Third-party types you do not own are registered through a `@module`:

```dart
@module
abstract class AppModule {
  @lazySingleton
  Dio dio() => Dio(BaseOptions(baseUrl: apiBaseUrl));

  @preResolve
  Future<SharedPreferences> get prefs => SharedPreferences.getInstance();
}
```

- `@preResolve` makes an async registration awaited during `init()`, so
  `configureDependencies()` returns only once it is ready. Without it the
  object is registered as an async singleton and callers must `getAsync`.
- Use `@Named('...')` (or `@Named.from(Type)`) when two implementations share
  an interface, and inject with the same annotation on the parameter.
- Environments (`@dev`, `@test`, `@prod`, or `@Environment('...')`) select
  registrations at init time via `getIt.init(environment: Environment.test)`.
  This is the supported way to swap a fake implementation in tests -- reach for
  it before `allowReassignment`.
- **Do not hand-write `registerX` calls next to the generated `init()`.** The
  generated file is the single source of truth for registration order; manual
  registrations run outside it and will resolve against a half-built graph.
- `.config.dart` is build output. Never edit it, and rerun
  `{{ dartRunCommand }} build_runner build --delete-conflicting-outputs` after
  touching any annotation.

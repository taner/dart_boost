# Flutter 3.47

Guidance that applies to the 3.47 line specifically.

- `MaterialApp` defaults to Material 3. Do not set `useMaterial3: true`; it is
  the default and the flag is on its way out.
- Prefer `ColorScheme.fromSeed` over hand-picked `ColorScheme` fields so light
  and dark stay in step.
- `WidgetStateProperty` is the current spelling; `MaterialStateProperty` is
  deprecated and will be removed.
- Impeller is the default renderer on iOS and Android. When you hit a shader
  or raster problem, say which renderer you tested on -- the Skia fallback
  behaves differently.

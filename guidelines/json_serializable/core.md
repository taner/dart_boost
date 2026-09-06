# json_serializable

- Annotate the class with `@JsonSerializable()`, add `part 'x.g.dart';`, and
  wire the two generated functions yourself -- the generator does not add the
  `fromJson` factory or the `toJson` method for you.

```dart
part 'user.g.dart';

@JsonSerializable(explicitToJson: true)
class User {
  const User({required this.id, required this.name, this.address});

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  final String id;
  final String name;
  final Address? address;

  Map<String, dynamic> toJson() => _$UserToJson(this);
}
```

- **Set `explicitToJson: true` for any model holding another model.** Without
  it the nested object is written straight into the map and you ship
  `Instance of 'Address'` to the server. Set it once in `build.yaml` rather
  than remembering it per class.
- Nullability *is* the contract. A non-nullable field whose key is missing or
  null throws at parse time. Make the field nullable when null is meaningful,
  and use `@JsonKey(defaultValue: ...)` when the server may simply omit it.
- Rename one field with `@JsonKey(name: 'created_at')` and all of them with
  `fieldRename: FieldRename.snake`. Pick one and apply it consistently.
- Use `@JsonKey(fromJson:, toJson:)` for a one-off conversion and a
  `JsonConverter<T, S>` when the same conversion repeats across models -- list
  the converter once in `converters:` on `@JsonSerializable` instead of on
  every field.
- `checked: true` reports a parse failure as a `CheckedFromJsonException` that
  names the offending key. Worth it for anything decoding a third-party API.
- Enums map by name. Give a value `@JsonValue('...')` when the wire form
  differs, and set `@JsonKey(unknownEnumValue: Status.unknown)` so a value the
  server adds later does not crash the client.
- Generic models need `genericArgumentFactories: true`; the generated
  functions then take a `fromJson`/`toJson` per type argument.
- `includeIfNull: false` keeps nulls out of the payload; leave it on when the
  API distinguishes "absent" from "null".
- Do not write manual `Map` plumbing beside a generated model -- two encoders
  for one type drift apart silently.

Project-wide defaults belong in `build.yaml` at the package root:

```yaml
targets:
  $default:
    builders:
      json_serializable:
        options:
          explicit_to_json: true
          field_rename: snake
          create_to_json: true
```

Rebuild after any annotation change with
`{{ dartRunCommand }} build_runner build --delete-conflicting-outputs`.

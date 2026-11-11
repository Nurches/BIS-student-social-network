/// Typed access to decoded JSON; a mismatch is a broken contract, reported as
/// a [FormatException] that repositories turn into `UnexpectedResponseException`.
T jsonField<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException(
    'Field "$key" expected $T, got ${value.runtimeType}: $value',
  );
}

/// docs/api.md: every timestamp is ISO 8601 with an offset; shown in device time.
DateTime jsonDateTime(Map<String, Object?> json, String key) {
  final raw = jsonField<String>(json, key);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('Field "$key" is not a date: $raw');
  return parsed.toLocal();
}

List<Map<String, Object?>> jsonObjects(Object? value, String what) => [
  for (final item
      in value is List ? value : throw FormatException('$what is not a list'))
    if (item is Map<String, Object?>)
      item
    else
      throw FormatException('$what item is not an object: $item'),
];

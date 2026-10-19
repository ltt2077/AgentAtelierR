/// A local editing copy. Committing it is explicit so Cancel never changes
/// active prompts or any of the other slots.
enum SettingsSlotKind { user, character, world }

class SettingsSlots {
  /// Tavern edition: 20 slots per kind. Slot 1 (index 0) keeps the original
  /// built-in defaults; slots 2-20 start from the tavern presets.
  static const count = 20;

  /// Slot count written by the original app (schema without `version`).
  static const legacyCount = 5;

  /// Schema version written by this build. Version 1 is the original 5-slot
  /// format, which never carried this field. Readers ignore unknown keys, so
  /// the original app can still read the first five slots of a v2 bank.
  static const schemaVersion = 2;

  SettingsSlots({this.active = 0, List<Map<String, String>?>? entries})
    : entries = List.generate(count, (i) {
        final entry = entries != null && i < entries.length ? entries[i] : null;
        return entry == null ? null : Map<String, String>.of(entry);
      });

  int active;
  final List<Map<String, String>?> entries;

  SettingsSlots copy() => SettingsSlots(active: active, entries: entries);

  /// Detects the schema of stored or imported slot data. Missing or invalid
  /// versions are the original 5-slot format.
  static int versionOf(Object? value) {
    if (value is! Map) return 1;
    final version = value['version'];
    return version is int && version >= 1 ? version : 1;
  }

  factory SettingsSlots.fromJson(Object? value) {
    if (value is! Map) return SettingsSlots();
    final raw = value['entries'];
    // A v1 bank (original app) holds five slots; v2+ banks are read up to
    // [count]. Extra entries are ignored rather than rejected.
    final limit = versionOf(value) >= 2 ? count : legacyCount;
    return SettingsSlots(
      active: value['active'] is int
          ? (value['active'] as int).clamp(0, limit - 1)
          : 0,
      entries: raw is List
          ? raw
                .take(limit)
                .map(
                  (entry) => entry is Map
                      ? <String, String>{
                          for (final item in entry.entries)
                            if (item.key is String && item.value is String)
                              item.key as String: item.value as String,
                        }
                      : null,
                )
                .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'active': active,
    'entries': entries,
  };
}

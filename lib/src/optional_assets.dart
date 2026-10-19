import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Tavern edition: the original repository does not ship its private data
/// files (character prompts, world map). Builds from public source would fail
/// at startup when these are missing, so missing bundled JSON falls back to an
/// empty document instead. Present files load exactly as before.
///
/// The manifest is checked first so a missing file never raises an asset
/// error (which tests and the runtime log would report as a failure).
Future<String> loadOptionalBundledText(String path, String fallback) async {
  try {
    final manifest = await (_manifest ??= AssetManifest.loadFromAssetBundle(
      rootBundle,
    ));
    if (!manifest.listAssets().contains(path)) return fallback;
    return await rootBundle.loadString(path);
  } on Object {
    return fallback;
  }
}

Future<AssetManifest>? _manifest;

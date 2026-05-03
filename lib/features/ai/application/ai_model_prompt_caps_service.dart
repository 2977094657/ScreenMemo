import 'dart:convert';

import 'package:screen_memo/data/database/screenshot_database.dart';

/// Global, provider-agnostic model prompt-cap overrides.
///
/// This is used to:
/// - Drive UI token progress bars with the correct model capacity.
/// - Allow user to override missing/wrong model limits without depending on a provider.
class AIModelPromptCapsService {
  AIModelPromptCapsService._internal();
  static final AIModelPromptCapsService instance =
      AIModelPromptCapsService._internal();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  // Mirror key in ai_settings for resilient restore/import paths that may only
  // retain key-value settings.
  static const String _mirrorAiSettingKey = 'model_prompt_caps_json_v1';

  // Cache: normalized model_key -> override (null means "no override").
  final Map<String, int?> _cache = <String, int?>{};
  final Map<String, int> _mirror = <String, int>{};
  bool _mirrorLoaded = false;

  static String normalizeKey(String model) => model.trim().toLowerCase();

  static String canonicalizeModel(String model) {
    final String t = model.trim();
    final int slash = t.lastIndexOf('/');
    if (slash < 0) return t;
    if (slash + 1 >= t.length) return t;
    return t.substring(slash + 1).trim();
  }

  static String dequalifyModel(String model) {
    String t = model.trim();
    if (t.isEmpty) return t;
    final int q = t.indexOf('?');
    if (q > 0) t = t.substring(0, q).trim();
    final int hash = t.indexOf('#');
    if (hash > 0) t = t.substring(0, hash).trim();

    // Strip route/provider qualifiers like ":free" when they appear on the
    // tail segment (after the last '/'), but keep namespace prefixes like
    // "hf:org/model".
    final int slash = t.lastIndexOf('/');
    final int colon = t.lastIndexOf(':');
    if (colon > 0 && colon > slash) {
      t = t.substring(0, colon).trim();
    }
    return t;
  }

  static List<String> keysForModel(String model) {
    final List<String> raw = <String>[
      model,
      canonicalizeModel(model),
      dequalifyModel(model),
      dequalifyModel(canonicalizeModel(model)),
    ];
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final String r in raw) {
      final String k = normalizeKey(r);
      if (k.isEmpty) continue;
      if (!seen.add(k)) continue;
      out.add(k);
    }
    return out;
  }

  int _sanitizeCap(int value) => value.clamp(256, 1 << 30).toInt();

  int? _parseCap(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return _sanitizeCap(raw);
    if (raw is num) return _sanitizeCap(raw.toInt());
    final int? parsed = int.tryParse(raw.toString().trim());
    if (parsed == null) return null;
    return _sanitizeCap(parsed);
  }

  Future<void> _loadMirrorIfNeeded() async {
    if (_mirrorLoaded) return;
    _mirrorLoaded = true;
    try {
      final String raw = (await _db.getAiSetting(_mirrorAiSettingKey) ?? '')
          .trim();
      if (raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final MapEntry<Object?, Object?> entry in decoded.entries) {
        final String key = normalizeKey((entry.key ?? '').toString());
        if (key.isEmpty) continue;
        final int? cap = _parseCap(entry.value);
        if (cap == null) continue;
        _mirror[key] = cap;
        _cache[key] = cap;
      }
    } catch (_) {}
  }

  Future<void> _persistMirror() async {
    try {
      if (_mirror.isEmpty) {
        await _db.setAiSetting(_mirrorAiSettingKey, null);
        return;
      }
      final List<String> keys = _mirror.keys.toList()..sort();
      final Map<String, int> ordered = <String, int>{
        for (final String key in keys) key: _mirror[key]!,
      };
      await _db.setAiSetting(_mirrorAiSettingKey, jsonEncode(ordered));
    } catch (_) {}
  }

  Future<void> _upsertMirrorEntry(String key, int cap) async {
    await _loadMirrorIfNeeded();
    final int sanitized = _sanitizeCap(cap);
    if (_mirror[key] == sanitized) return;
    _mirror[key] = sanitized;
    await _persistMirror();
  }

  int? peekOverride(String model) {
    final List<String> keys = keysForModel(model);
    if (keys.isEmpty) return null;
    // Prefer a non-null override if already cached.
    for (final String k in keys) {
      if (_cache.containsKey(k) && _cache[k] != null) return _cache[k];
    }
    // Otherwise return the first cached value (possibly null) if any.
    for (final String k in keys) {
      if (_cache.containsKey(k)) return _cache[k];
    }
    return null;
  }

  Future<int?> getOverride(String model) async {
    final List<String> keys = keysForModel(model);
    if (keys.isEmpty) return null;

    // Prefer cached non-null.
    for (final String k in keys) {
      if (_cache.containsKey(k) && _cache[k] != null) return _cache[k];
    }

    // Query DB in order; first hit wins.
    for (final String k in keys) {
      if (!_cache.containsKey(k)) {
        final int? v = await _db.getAiModelPromptCapTokens(k);
        _cache[k] = v;
        if (v != null) {
          // Backfill ai_settings mirror from legacy/main table data.
          await _upsertMirrorEntry(k, v);
          return v;
        }
      }
    }

    // Mirror fallback (resilient against partial restore paths).
    await _loadMirrorIfNeeded();
    for (final String k in keys) {
      final int? v = _mirror[k];
      if (v != null) {
        _cache[k] = v;
        return v;
      }
      if (!_cache.containsKey(k)) _cache[k] = null;
    }

    // Still none: all are cached as null or didn't exist.
    return peekOverride(model);
  }

  Future<void> setOverride(String model, int promptCapTokens) async {
    final List<String> keys = keysForModel(model);
    if (keys.isEmpty) return;
    final int cap = _sanitizeCap(promptCapTokens);
    await _loadMirrorIfNeeded();
    bool mirrorChanged = false;
    for (final String k in keys) {
      await _db.setAiModelPromptCapTokens(
        modelKey: k,
        promptCapTokens: cap,
        modelDisplay: model.trim(),
      );
      _cache[k] = cap;
      if (_mirror[k] != cap) {
        _mirror[k] = cap;
        mirrorChanged = true;
      }
    }
    if (mirrorChanged) await _persistMirror();
  }

  Future<void> clearOverride(String model) async {
    final List<String> keys = keysForModel(model);
    if (keys.isEmpty) return;
    await _loadMirrorIfNeeded();
    bool mirrorChanged = false;
    for (final String k in keys) {
      await _db.deleteAiModelPromptCapTokens(k);
      _cache[k] = null;
      if (_mirror.remove(k) != null) mirrorChanged = true;
    }
    if (mirrorChanged) await _persistMirror();
  }
}

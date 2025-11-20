import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/user_settings_keys.dart';
import 'flutter_logger.dart';
import 'screenshot_database.dart';

/// 统一的设置持久化服务，优先写入/读取 SQLite（随导出备份），并兼容老版 SharedPreferences。
class UserSettingsService {
  UserSettingsService._();

  static final UserSettingsService instance = UserSettingsService._();

  static const String _tableName = 'user_settings';

  Future<Database> get _db async => ScreenshotDatabase.instance.database;

  Future<void> setString(
    String key,
    String? value, {
    List<String> aliasKeys = const <String>[],
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    await _setRaw(key, value);
    for (final String alias in aliasKeys) {
      await _setRaw(alias, value);
    }
    final List<String> prefKeys = _uniqueKeys(
      <String>[key, ...aliasKeys, ...legacyPrefKeys],
    );
    if (value == null) {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        for (final String name in prefKeys) {
          await prefs.remove(name);
        }
      } catch (e) {
        await FlutterLogger.nativeWarn('UserSettings', 'remove prefs key=$key failed: $e');
      }
      return;
    }
    await _writePrefs<String>(
      key,
      value,
      prefKeys.skip(1).toList(),
      (prefs, k, v) async => prefs.setString(k, v),
    );
  }

  Future<void> setInt(
    String key,
    int value, {
    List<String> aliasKeys = const <String>[],
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String serialized = value.toString();
    await _setRaw(key, serialized);
    for (final String alias in aliasKeys) {
      await _setRaw(alias, serialized);
    }
    await _writePrefs<int>(
      key,
      value,
      <String>[
        ...aliasKeys,
        ...legacyPrefKeys,
      ],
      (prefs, k, v) async => prefs.setInt(k, v),
    );
  }

  Future<void> setBool(
    String key,
    bool value, {
    List<String> aliasKeys = const <String>[],
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String serialized = value ? '1' : '0';
    await _setRaw(key, serialized);
    for (final String alias in aliasKeys) {
      await _setRaw(alias, serialized);
    }
    await _writePrefs<bool>(
      key,
      value,
      <String>[
        ...aliasKeys,
        ...legacyPrefKeys,
      ],
      (prefs, k, v) async => prefs.setBool(k, v),
    );
  }

  Future<String?> getString(
    String key, {
    String? defaultValue,
    List<String> aliasKeys = const <String>[],
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String? fromDb = await _getRaw(key);
    if (fromDb != null) return fromDb;

    for (final String alias in aliasKeys) {
      final String? aliasValue = await _getRaw(alias);
      if (aliasValue != null) {
        await _setRaw(key, aliasValue);
        return aliasValue;
      }
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final String k in _uniqueKeys(<String>[key, ...aliasKeys, ...legacyPrefKeys])) {
      if (!prefs.containsKey(k)) continue;
      final Object? raw = prefs.get(k);
      String? value;
      if (raw is String) {
        value = raw;
      } else if (raw is int || raw is double || raw is bool) {
        value = raw.toString();
      }
      if (value != null) {
        await _setRaw(key, value);
        return value;
      }
    }
    return defaultValue;
  }

  Future<int> getInt(
    String key, {
    int defaultValue = 0,
    List<String> aliasKeys = const <String>[],
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String? raw = await getString(
      key,
      aliasKeys: aliasKeys,
      legacyPrefKeys: legacyPrefKeys,
    );
    if (raw == null) return defaultValue;
    final int? parsed = int.tryParse(raw);
    return parsed ?? defaultValue;
  }

  Future<bool> getBool(
    String key, {
    bool defaultValue = false,
    List<String> aliasKeys = const <String>[],
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String? raw = await getString(
      key,
      aliasKeys: aliasKeys,
      legacyPrefKeys: legacyPrefKeys,
    );
    if (raw == null) return defaultValue;
    final String lower = raw.toLowerCase();
    if (lower == '1' || lower == 'true' || lower == 'yes' || lower == 'on') {
      return true;
    }
    if (lower == '0' || lower == 'false' || lower == 'no' || lower == 'off') {
      return false;
    }
    return defaultValue;
  }

  Future<void> remove(String key) async {
    try {
      final Database db = await _db;
      await db.delete(_tableName, where: 'key = ?', whereArgs: <Object>[key]);
    } catch (e) {
      await FlutterLogger.nativeWarn('UserSettings', 'remove key=$key failed: $e');
    }
  }

  /// 导入数据后重建截图相关设置的 SharedPreferences 映射，确保原生服务立刻生效。
  Future<void> resyncScreenshotEncodingSettings() async {
    await _resaveStringSetting(
      UserSettingKeys.imageFormat,
      legacyPrefKeys: const <String>['image_format'],
    );
    await _resaveIntSetting(
      UserSettingKeys.imageQuality,
      legacyPrefKeys: const <String>['image_quality'],
    );
    await _resaveBoolSetting(
      UserSettingKeys.useTargetSize,
      legacyPrefKeys: const <String>['use_target_size'],
    );
    await _resaveIntSetting(
      UserSettingKeys.targetSizeKb,
      legacyPrefKeys: const <String>['target_size_kb'],
    );
    await _resaveBoolSetting(
      UserSettingKeys.screenshotExpireEnabled,
      legacyPrefKeys: const <String>['screenshot_expire_enabled'],
    );
    await _resaveIntSetting(
      UserSettingKeys.screenshotExpireDays,
      legacyPrefKeys: const <String>['screenshot_expire_days'],
    );
  }

  Future<String?> _getRaw(String key) async {
    try {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        _tableName,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: <Object>[key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (e) {
      await FlutterLogger.nativeWarn('UserSettings', 'read key=$key failed: $e');
      return null;
    }
  }

  Future<void> _resaveStringSetting(
    String key, {
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String? raw = await _getRaw(key);
    if (raw == null) return;
    await setString(
      key,
      raw,
      legacyPrefKeys: legacyPrefKeys,
    );
  }

  Future<void> _resaveIntSetting(
    String key, {
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String? raw = await _getRaw(key);
    final int? value = raw != null ? int.tryParse(raw) : null;
    if (value == null) return;
    await setInt(
      key,
      value,
      legacyPrefKeys: legacyPrefKeys,
    );
  }

  Future<void> _resaveBoolSetting(
    String key, {
    List<String> legacyPrefKeys = const <String>[],
  }) async {
    final String? raw = await _getRaw(key);
    final bool? value = raw != null ? _parseBool(raw) : null;
    if (value == null) return;
    await setBool(
      key,
      value,
      legacyPrefKeys: legacyPrefKeys,
    );
  }

  bool? _parseBool(String raw) {
    final String lower = raw.trim().toLowerCase();
    if (lower == '1' || lower == 'true' || lower == 'yes' || lower == 'on') {
      return true;
    }
    if (lower == '0' || lower == 'false' || lower == 'no' || lower == 'off') {
      return false;
    }
    return null;
  }

  Future<void> _setRaw(String key, String? value) async {
    try {
      final Database db = await _db;
      if (value == null) {
        await db.delete(_tableName, where: 'key = ?', whereArgs: <Object>[key]);
      } else {
        await db.insert(
          _tableName,
          <String, Object?>{
            'key': key,
            'value': value,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      await FlutterLogger.nativeError('UserSettings', 'write key=$key failed: $e');
    }
  }

  Future<void> _writePrefs<T>(
    String key,
    T value,
    List<String> extraKeys,
    Future<bool> Function(SharedPreferences prefs, String key, T value) writer,
  ) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> keys = _uniqueKeys(<String>[key, ...extraKeys]);
      for (final String k in keys) {
        await writer(prefs, k, value);
      }
    } catch (e) {
      await FlutterLogger.nativeWarn('UserSettings', 'write prefs key=$key failed: $e');
    }
  }

  List<String> _uniqueKeys(List<String> keys) {
    final Set<String> set = <String>{};
    final List<String> result = <String>[];
    for (final String key in keys) {
      if (set.add(key)) {
        result.add(key);
      }
    }
    return result;
  }
}



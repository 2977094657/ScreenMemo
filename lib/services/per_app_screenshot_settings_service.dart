import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'path_service.dart';

/// 每应用独立的截图设置服务（SQLite 存储于应用专属分库目录）。
/// 存储位置：output/databases/shards/<sanitizedPackage>/settings.db
/// 表结构：settings(key TEXT PRIMARY KEY, value TEXT)
/// 支持键：
/// - use_custom: '1' | '0'
/// - image_format: 'jpeg' | 'png' | 'webp_lossy' | 'webp_lossless'
/// - image_quality: '1'..'100'
/// - use_target_size: '1' | '0'
/// - target_size_kb: '>=50'
/// - screenshot_expire_enabled: '1' | '0'
/// - screenshot_expire_days: '>=1'
class PerAppScreenshotSettingsService {
  PerAppScreenshotSettingsService._internal();
  static final PerAppScreenshotSettingsService instance = PerAppScreenshotSettingsService._internal();

  final Map<String, Database> _dbCache = <String, Database>{};

  String _sanitizePackageName(String packageName) {
    return packageName.replaceAll(RegExp(r'[^\w]'), '_');
  }

  Future<String?> _resolveSettingsDbPath(String packageName) async {
    try {
      final base = await PathService.getExternalFilesDir(null);
      if (base == null) return null;
      final root = Directory(p.join(base.path, 'output', 'databases', 'shards', _sanitizePackageName(packageName)));
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      return p.join(root.path, 'settings.db');
    } catch (_) {
      return null;
    }
  }

  Future<Database?> _openDb(String packageName) async {
    final key = packageName;
    final cached = _dbCache[key];
    if (cached != null) return cached;
    final path = await _resolveSettingsDbPath(packageName);
    if (path == null) return null;
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
      },
    );
    _dbCache[key] = db;
    return db;
  }

  Future<String?> _getRaw(String packageName, String key) async {
    try {
      final db = await _openDb(packageName);
      if (db == null) return null;
      final rows = await db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setRaw(String packageName, String key, String? value) async {
    final db = await _openDb(packageName);
    if (db == null) return;
    if (value == null) {
      try { await db.delete('settings', where: 'key = ?', whereArgs: [key]); } catch (_) {}
      return;
    }
    try {
      await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      try { await db.update('settings', {'value': value}, where: 'key = ?', whereArgs: [key]); } catch (_) {}
    }
  }

  // ============== 顶层 API ==============

  Future<bool> getUseCustom(String packageName) async {
    final v = await _getRaw(packageName, 'use_custom');
    if (v == null) return false;
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setUseCustom(String packageName, bool enabled) async {
    await _setRaw(packageName, 'use_custom', enabled ? '1' : '0');
  }

  Future<Map<String, dynamic>> getQualitySettings(String packageName) async {
    final format = await _getRaw(packageName, 'image_format');
    final qualityStr = await _getRaw(packageName, 'image_quality');
    final uts = await _getRaw(packageName, 'use_target_size');
    final tkbStr = await _getRaw(packageName, 'target_size_kb');
    final useTarget = (uts?.toLowerCase() == '1' || uts?.toLowerCase() == 'true');
    final quality = int.tryParse(qualityStr ?? '');
    final tkb = int.tryParse(tkbStr ?? '');
    return <String, dynamic>{
      'image_format': format,
      'image_quality': quality,
      'use_target_size': useTarget,
      'target_size_kb': tkb,
    };
  }

  Future<void> saveQualitySettings({
    required String packageName,
    String? imageFormat,
    int? imageQuality,
    bool? useTargetSize,
    int? targetSizeKb,
  }) async {
    if (imageFormat != null) {
      await _setRaw(packageName, 'image_format', imageFormat);
    }
    if (imageQuality != null) {
      await _setRaw(packageName, 'image_quality', imageQuality.toString());
    }
    if (useTargetSize != null) {
      await _setRaw(packageName, 'use_target_size', useTargetSize ? '1' : '0');
    }
    if (targetSizeKb != null) {
      await _setRaw(packageName, 'target_size_kb', targetSizeKb.toString());
    }
  }

  Future<Map<String, dynamic>> getExpireSettings(String packageName) async {
    final enabledStr = await _getRaw(packageName, 'screenshot_expire_enabled');
    final daysStr = await _getRaw(packageName, 'screenshot_expire_days');
    final enabled = (enabledStr?.toLowerCase() == '1' || enabledStr?.toLowerCase() == 'true');
    final days = int.tryParse(daysStr ?? '');
    return <String, dynamic>{
      'enabled': enabled,
      'days': days,
    };
  }

  Future<void> saveExpireSettings({
    required String packageName,
    bool? enabled,
    int? days,
  }) async {
    if (enabled != null) {
      await _setRaw(packageName, 'screenshot_expire_enabled', enabled ? '1' : '0');
    }
    if (days != null) {
      await _setRaw(packageName, 'screenshot_expire_days', days.toString());
    }
  }

  // ============== 截图间隔（秒） ==============
  Future<int?> getScreenshotIntervalSeconds(String packageName) async {
    final v = await _getRaw(packageName, 'screenshot_interval_sec');
    return int.tryParse(v ?? '');
  }

  Future<void> saveScreenshotIntervalSeconds(String packageName, int seconds) async {
    final clamped = seconds < 5 ? 5 : (seconds > 60 ? 60 : seconds);
    await _setRaw(packageName, 'screenshot_interval_sec', clamped.toString());
  }
}



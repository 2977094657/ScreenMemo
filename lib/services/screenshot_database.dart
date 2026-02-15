import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import '../models/screenshot_record.dart';
import 'startup_profiler.dart';
import 'flutter_logger.dart';
import 'path_service.dart';

part 'screenshot_database_ai.dart';
part 'screenshot_database_meta.dart';
part 'screenshot_database_search.dart';
part 'screenshot_database_merge.dart';

/// 截屏数据库服务
class ScreenshotDatabase {
  static ScreenshotDatabase? _instance;
  static Database? _database;
  static const MethodChannel _channel = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  static ScreenshotDatabase get instance =>
      _instance ??= ScreenshotDatabase._();

  ScreenshotDatabase._();

  // 桌面端自定义根目录（用于合并工具）
  static String? _desktopBasePath;

  /// 为桌面端初始化数据库到指定目录
  /// 用于合并工具将数据保存到用户选择的目录
  Future<void> initializeForDesktop(String basePath) async {
    // 关闭现有连接
    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {}
      _database = null;
    }
    for (final db in _shardDbCache.values) {
      try {
        await db.close();
      } catch (_) {}
    }
    _shardDbCache.clear();

    // 设置新的基础路径
    _desktopBasePath = basePath;

    // 创建必要的目录结构
    final databasesDir = Directory(join(basePath, 'output', 'databases'));
    if (!await databasesDir.exists()) {
      await databasesDir.create(recursive: true);
    }

    // 重新初始化数据库
    _database = await _initDatabase();
  }

  /// 释放桌面端数据库资源，便于后续清理输出目录
  Future<void> disposeDesktop() async {
    try {
      if (_database != null) {
        try {
          await _database!.close();
        } catch (_) {}
        _database = null;
      }
      for (final db in _shardDbCache.values) {
        try {
          await db.close();
        } catch (_) {}
      }
      _shardDbCache.clear();
    } catch (_) {}
  }

  // 分库缓存（key: "<package>|<year>")
  static final Map<String, Database> _shardDbCache = {};
  // 分库根目录（相对外部存储目录）
  static const String _shardsDirRelative = 'output/databases/shards';

  /// 获取数据库实例
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    try {
      StartupProfiler.begin('ScreenshotDatabase._initDatabase');

      // 桌面端使用自定义路径
      if (_desktopBasePath != null) {
        final databasesDir = Directory(
          join(_desktopBasePath!, 'output', 'databases'),
        );
        if (!await databasesDir.exists()) {
          await databasesDir.create(recursive: true);
        }
        final path = join(databasesDir.path, 'screenshot_memo.db');
        final db = await openDatabase(
          path,
          version: 31,
          onConfigure: (db) async {
            try {
              await db.execute('PRAGMA journal_mode=WAL');
            } catch (_) {
              try {
                await db.rawQuery('PRAGMA journal_mode=WAL');
              } catch (_) {}
            }
            try {
              await db.execute('PRAGMA auto_vacuum=2');
            } catch (_) {}
          },
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        StartupProfiler.end('ScreenshotDatabase._initDatabase');
        return db;
      }

      // 获取应用的外部存储目录
      final internalDir =
          await PathService.getInternalAppDir(null) ??
          await _getInternalFilesDirFallback();
      if (internalDir != null) {
        // 创建 output/databases 目录
        final databasesDir = Directory(
          join(internalDir.path, 'output', 'databases'),
        );
        if (!await databasesDir.exists()) {
          await databasesDir.create(recursive: true);
        }

        // 主库（聚合、注册表等）
        final path = join(databasesDir.path, 'screenshot_memo.db');

        final db = await openDatabase(
          path,
          version: 31,
          onConfigure: (db) async {
            // 启用 WAL 提升并发写入与长事务期间读取能力
            try {
              await db.execute('PRAGMA journal_mode=WAL');
            } catch (_) {
              try {
                await db.rawQuery('PRAGMA journal_mode=WAL');
              } catch (_) {}
            }
            // 对于新库，尽早设置增量回收（必须在建表前设置）
            try {
              await db.execute('PRAGMA auto_vacuum=2');
            } catch (_) {}
          },
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        StartupProfiler.end('ScreenshotDatabase._initDatabase');
        return db;
      } else {
        // 备选方案：使用默认数据库路径
        final databasesPath = await getDatabasesPath();
        final path = join(databasesPath, 'screenshot_memo.db');
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'fallback internal db at ' + path,
          );
        } catch (_) {}

        final db = await openDatabase(
          path,
          version: 31,
          onConfigure: (db) async {
            try {
              await db.execute('PRAGMA journal_mode=WAL');
            } catch (_) {
              try {
                await db.rawQuery('PRAGMA journal_mode=WAL');
              } catch (_) {}
            }
            try {
              await db.execute('PRAGMA auto_vacuum=2');
            } catch (_) {}
          },
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        StartupProfiler.end('ScreenshotDatabase._initDatabase');
        return db;
      }
    } catch (e) {
      print('初始化数据库失败，使用默认路径: $e');
      // 出错时使用默认路径
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'screenshot_memo.db');

      final db = await openDatabase(
        path,
        version: 31,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      StartupProfiler.end('ScreenshotDatabase._initDatabase');
      return db;
    }
  }

  /// 获取内部存储目录的辅助方法
  Future<Directory?> _getInternalFilesDirFallback() async {
    try {
      if (Platform.isAndroid) {
        final dir = await getApplicationSupportDirectory();
        return dir;
      }

      // 其他平台或兜底：使用应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      return dir;
    } catch (e) {
      print('获取内部存储目录失败: $e');
      return null;
    }
  }

  // ===================== 分库/分表 工具函数 =====================

  String _sanitizePackageName(String packageName) {
    return packageName.replaceAll(RegExp(r'[^\w]'), '_');
  }

  Future<Directory?> _getShardsRootDir() async {
    final base =
        await PathService.getInternalAppDir(null) ??
        await _getInternalFilesDirFallback();
    if (base == null) return null;
    final dir = Directory(join(base.path, _shardsDirRelative));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _shardDbKey(String package, int year) => '${package}|$year';

  Future<String?> _resolveShardDbPath(String package, int year) async {
    final root = await _getShardsRootDir();
    if (root == null) return null;
    final pkgDir = Directory(
      join(root.path, _sanitizePackageName(package), '$year'),
    );
    if (!await pkgDir.exists()) {
      await pkgDir.create(recursive: true);
    }
    final fileName = 'smm_${_sanitizePackageName(package)}_${year}.db';
    return join(pkgDir.path, fileName);
  }

  Future<Database?> _openShardDb(String package, int year) async {
    final key = _shardDbKey(package, year);
    if (_shardDbCache.containsKey(key)) return _shardDbCache[key];
    final path = await _resolveShardDbPath(package, year);
    if (path == null) return null;
    final db = await openDatabase(path, version: 1);
    _shardDbCache[key] = db;
    // 记录到主库的 shard_registry
    try {
      final master = await database;
      await master.execute(
        'INSERT OR REPLACE INTO shard_registry(app_package_name, year, db_path) VALUES(?, ?, ?)',
        [package, year, path],
      );
    } catch (_) {}
    return db;
  }

  String _monthTableName(int year, int month) {
    final mm = month.toString().padLeft(2, '0');
    return 'shots_${year}${mm}';
  }

  Future<void> _ensureMonthTable(
    DatabaseExecutor shardDb,
    int year,
    int month,
  ) async {
    final table = _monthTableName(year, month);
    await shardDb.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL UNIQUE,
        capture_time INTEGER NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        page_url TEXT,
        ocr_text TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await shardDb.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_capture_time ON $table(capture_time)',
    );
    await shardDb.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_file_path ON $table(file_path)',
    );
    // 可选：为 ocr_text 建立索引（对前缀匹配有帮助；LIKE '%term%' 仍会扫描）
    try {
      await shardDb.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_ocr_text ON $table(ocr_text)',
      );
    } catch (_) {}
    // 兜底：老表添加缺失列
    try {
      await shardDb.execute("ALTER TABLE $table ADD COLUMN ocr_text TEXT");
    } catch (_) {}
    // 确保 FTS 虚拟表与触发器存在，并完成历史数据回填
    await _ensureMonthFts(shardDb, year, month);
  }

  /// 确保每月表具备 FTS（优先 FTS5，回退 FTS4），带触发器与一次性回填
  Future<void> _ensureMonthFts(
    DatabaseExecutor shardDb,
    int year,
    int month,
  ) async {
    final String table = _monthTableName(year, month);
    final String fts = '${table}_fts';
    try {
      if (!await _tableExists(shardDb, table)) return;
    } catch (_) {
      return;
    }

    // 记录构建状态
    try {
      await shardDb.execute('''
        CREATE TABLE IF NOT EXISTS fts_registry (
          table_name TEXT PRIMARY KEY,
          built INTEGER NOT NULL DEFAULT 0,
          last_built_at INTEGER
        )
      ''');
    } catch (_) {}

    bool ok = false;
    // 尝试 FTS5
    try {
      await shardDb.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS $fts USING fts5(ocr_text, content=$table, content_rowid=id, tokenize='unicode61', prefix='2 3 4')",
      );
      ok = true;
    } catch (_) {
      // 回退 FTS4
      try {
        await shardDb.execute(
          "CREATE VIRTUAL TABLE IF NOT EXISTS $fts USING fts4(ocr_text, content=$table)",
        );
        ok = true;
      } catch (_) {}
    }
    if (!ok) return;

    // 触发器保持同步
    try {
      await shardDb.execute('''
        CREATE TRIGGER IF NOT EXISTS ${table}_ai AFTER INSERT ON $table BEGIN
          INSERT INTO $fts(rowid, ocr_text) VALUES (new.id, new.ocr_text);
        END;
      ''');
    } catch (_) {}
    try {
      await shardDb.execute('''
        CREATE TRIGGER IF NOT EXISTS ${table}_au AFTER UPDATE OF ocr_text ON $table BEGIN
          UPDATE $fts SET ocr_text = new.ocr_text WHERE rowid = new.id;
        END;
      ''');
    } catch (_) {}
    try {
      await shardDb.execute('''
        CREATE TRIGGER IF NOT EXISTS ${table}_ad AFTER DELETE ON $table BEGIN
          DELETE FROM $fts WHERE rowid = old.id;
        END;
      ''');
    } catch (_) {}

    // 回填：若未构建则重建索引
    try {
      final rows = await (shardDb as Database).query(
        'fts_registry',
        columns: ['built'],
        where: 'table_name = ?',
        whereArgs: [table],
        limit: 1,
      );
      final built =
          rows.isNotEmpty && ((rows.first['built'] as int?) ?? 0) == 1;
      if (!built) {
        try {
          await shardDb.execute("INSERT INTO $fts($fts) VALUES('rebuild')");
        } catch (_) {
          try {
            await shardDb.execute(
              "INSERT OR IGNORE INTO $fts(rowid, ocr_text) SELECT id, ocr_text FROM $table WHERE ocr_text IS NOT NULL AND LENGTH(ocr_text) > 0",
            );
          } catch (_) {}
        }
        try {
          await (shardDb as Database).insert('fts_registry', {
            'table_name': table,
            'built': 1,
            'last_built_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (_) {}
      }
    } catch (_) {}
  }

  int _encodeGid(int year, int month, int localId) {
    return year * 100000000 + month * 1000000 + localId;
  }

  List<int>? _decodeGid(int gid) {
    if (gid <= 0) return null;
    final year = gid ~/ 100000000;
    final rem1 = gid % 100000000;
    final month = rem1 ~/ 1000000;
    final localId = rem1 % 1000000;
    if (year <= 1970 || month < 1 || month > 12 || localId <= 0) return null;
    return [year, month, localId];
  }

  int _yearFromMillis(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis).year;
  int _monthFromMillis(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis).month;

  /// 仅在主库中注册应用（不再在主库创建分表）
  Future<void> _registerAppIfNeeded(
    DatabaseExecutor db,
    String packageName,
    String appName,
  ) async {
    try {
      await db.execute(
        'INSERT OR REPLACE INTO app_registry(app_package_name, app_name, table_name) VALUES(?, ?, ?)',
        [packageName, appName, 'sharded'],
      );
    } catch (e) {
      print('注册应用失败: $e');
    }
  }

  Future<List<int>> _listShardYearsForApp(String packageName) async {
    try {
      final master = await database;
      final rows = await master.query(
        'shard_registry',
        columns: ['year'],
        where: 'app_package_name = ?',
        whereArgs: [packageName],
        orderBy: 'year DESC',
      );
      return rows.map((e) => (e['year'] as int)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    try {
      final res = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName],
      );
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Public helper for feature-gated code paths that need to check if a table
  /// exists (e.g. optional FTS virtual tables).
  Future<bool> tableExists(String tableName) async {
    final Database db = await database;
    return _tableExists(db, tableName);
  }

  /// 更新指定截图记录的文件大小（通过 gid + 包名精确定位）。
  Future<void> updateFileSizeByGid({
    required String packageName,
    required int gid,
    required int newSize,
  }) async {
    final List<int>? decoded = _decodeGid(gid);
    if (decoded == null) return;
    final int year = decoded[0];
    final int month = decoded[1];
    final int localId = decoded[2];
    if (localId <= 0) return;

    final Database? shardDb = await _openShardDb(packageName, year);
    if (shardDb == null) return;
    final String table = _monthTableName(year, month);
    if (!await _tableExists(shardDb, table)) return;

    try {
      await shardDb.update(
        table,
        <String, Object>{
          'file_size': newSize,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object>[localId],
      );
    } catch (e) {
      print('更新文件大小失败: $e, gid=$gid, package=$packageName');
    }
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // 新架构：应用注册表，记录所有已创建的应用表
    await db.execute('''
      CREATE TABLE app_registry (
        app_package_name TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        table_name TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
      )
    ''');

    // 聚合统计表（每个应用一行，避免首页实时 SUM/COUNT）
    await db.execute('''
      CREATE TABLE app_stats (
        app_package_name TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        total_size INTEGER NOT NULL DEFAULT 0,
        last_capture_time INTEGER,
        last_dhash INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_app_stats_last ON app_stats(last_capture_time)',
    );

    // 分库注册表（记录已存在的分库文件）
    await db.execute('''
      CREATE TABLE shard_registry (
        app_package_name TEXT NOT NULL,
        year INTEGER NOT NULL,
        db_path TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
        PRIMARY KEY (app_package_name, year)
      )
    ''');

    // 全局汇总统计表（单行记录，固定ID=1）
    await db.execute('''
      CREATE TABLE totals (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        app_count INTEGER NOT NULL DEFAULT 0,
        screenshot_count INTEGER NOT NULL DEFAULT 0,
        total_size_bytes INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    // v2: AI 配置与会话表
    await _createAiTables(db);
    // v6: 清理旧表与旧键
    await _cleanupLegacyAiArtifacts(db);

    // 收藏表
    await _createFavoritesTable(db);

    // NSFW 偏好相关表（域名规则 + 手动标记）
    await _createNsfwTables(db);

    // 全局设置表，确保导出时包含所有配置
    await _createUserSettingsTable(db);

    // 统一 SearchIndex（可选用，不影响现有搜索路径）
    await _createSearchIndexTables(db);
  }

  /// 升级回调：按版本增量迁移
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createAiTables(db);
    } else if (oldVersion < 4) {
      // 从版本2/3升级到版本4：创建汇总统计表
      await _createTotalsTable(db);
      // 幂等确保新表
      await _createAiTables(db);
    } else {
      // 幂等确保新表（v5 起包含 ai_providers）
      await _createAiTables(db);
    }
    // v8: 为 ai_messages 增加推理字段（兼容升级）
    if (oldVersion < 8) {
      try {
        await db.execute(
          'ALTER TABLE ai_messages ADD COLUMN reasoning_content TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_messages ADD COLUMN reasoning_duration_ms INTEGER',
        );
      } catch (_) {}
    }
    // v9: 为 ai_providers 增加 api_key 列（将 API Key 改存数据库）
    if (oldVersion < 9) {
      try {
        await db.execute('ALTER TABLE ai_providers ADD COLUMN api_key TEXT');
      } catch (_) {}
    }
    if (oldVersion < 10) {
      await _createMorningInsightsTable(db);
    }
    if (oldVersion < 11) {
      await _createWeeklySummariesTable(db);
    }
    // v6: 清理旧表与旧键
    await _cleanupLegacyAiArtifacts(db);
    // 幂等确保收藏表
    await _createFavoritesTable(db);

    // 幂等确保 NSFW 相关表
    await _createNsfwTables(db);

    if (oldVersion < 13) {
      await _createUserSettingsTable(db);
    }
    if (oldVersion < 14) {
      try {
        await db.execute(
          'ALTER TABLE ai_providers ADD COLUMN models_path TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 15) {
      // 为 segment_samples 增加 pHash/关键帧字段
      try {
        await db.execute(
          'ALTER TABLE segment_samples ADD COLUMN p_hash INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segment_samples ADD COLUMN is_keyframe INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segment_samples ADD COLUMN hash_distance INTEGER',
        );
      } catch (_) {}

      // 尝试创建 fts_content FTS5 虚拟表（如不支持 FTS5 则忽略）
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS fts_content USING fts5(
            sample_id UNINDEXED,
            segment_id UNINDEXED,
            ocr_text,
            summary,
            app_name
          )
        ''');
      } catch (e) {
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'FTS5 for fts_content not supported: ' + e.toString(),
          );
        } catch (_) {}
      }
    }
    // v18: 合并链路（非破坏性合并）字段
    if (oldVersion < 18) {
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merge_attempted INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merged_flag INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merged_into_id INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_segments_merged_into ON segments(merged_into_id)',
        );
      } catch (_) {}
    }
    // v19: 移除 embeddings 相关表与配置
    if (oldVersion < 19) {
      try {
        await db.execute('DROP TABLE IF EXISTS embeddings');
      } catch (_) {}
      try {
        await db.execute('DROP INDEX IF EXISTS idx_embeddings_segment');
      } catch (_) {}
      try {
        await db.delete(
          'user_settings',
          where: 'key LIKE ?',
          whereArgs: const <Object?>['embedding_%'],
        );
      } catch (_) {}
    }
    // v21: 统一 SearchIndex（search_docs + FTS）
    if (oldVersion < 21) {
      await _createSearchIndexTables(db);
    }
    // v22: segments 增加 segment_kind（当前仅使用 global）
    if (oldVersion < 22) {
      try {
        await db.execute(
          "ALTER TABLE segments ADD COLUMN segment_kind TEXT NOT NULL DEFAULT 'global'",
        );
      } catch (_) {}
      try {
        await db.execute(
          "UPDATE segments SET segment_kind = 'global' WHERE segment_kind IS NULL OR TRIM(segment_kind) = ''",
        );
      } catch (_) {}
      // Android 侧历史版本可能创建了“全局唯一窗口”索引；这里替换为 segment_kind=global 的部分唯一约束。
      try {
        await db.execute('DROP INDEX IF EXISTS uniq_segments_window');
      } catch (_) {}
      try {
        await db.execute(
          "CREATE UNIQUE INDEX IF NOT EXISTS uniq_segments_window_global ON segments(start_time, end_time) WHERE segment_kind = 'global'",
        );
      } catch (_) {}
    }
    // v23: segments 增加合并判定信息字段（用于展示合并原因/强制合并）
    if (oldVersion < 23) {
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merge_prev_id INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merge_decision_json TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merge_decision_reason TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merge_forced INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segments ADD COLUMN merge_decision_at INTEGER',
        );
      } catch (_) {}
    }
    // v24: 动态全文索引纳入 structured_json，支持搜索合并后的“原始事件”内容
    if (oldVersion < 24) {
      try {
        await db.execute('DROP TRIGGER IF EXISTS segment_results_ai');
      } catch (_) {}
      try {
        await db.execute('DROP TRIGGER IF EXISTS segment_results_ad');
      } catch (_) {}
      try {
        await db.execute('DROP TRIGGER IF EXISTS segment_results_au');
      } catch (_) {}
      try {
        await db.execute('DROP TABLE IF EXISTS segment_results_fts');
      } catch (_) {}
      await _createSegmentResultsFts(db);
      await _backfillSegmentResultsFts(db);
    }

    // v25: Conversation context system (summary + tool memory + rollout events).
    if (oldVersion < 25) {
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN summary TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN summary_updated_at INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN summary_tokens INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN compaction_count INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN last_compaction_reason TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN tool_memory_json TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN tool_memory_updated_at INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN last_prompt_tokens INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN last_prompt_at INTEGER',
        );
      } catch (_) {}
    }

    // v26: Persist chat UI thinking timeline (blocks/events) for stable restore.
    if (oldVersion < 26) {
      try {
        await db.execute(
          'ALTER TABLE ai_messages ADD COLUMN ui_thinking_json TEXT',
        );
      } catch (_) {}
    }

    // v28: Persist last prompt token breakdown JSON (for UI usage bar).
    if (oldVersion < 28) {
      try {
        await db.execute(
          'ALTER TABLE ai_conversations ADD COLUMN last_prompt_breakdown_json TEXT',
        );
      } catch (_) {}
    }

    // v29: raw transcript + per-request prompt usage events.
    if (oldVersion < 29) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_messages_raw (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT,
            api_content_json TEXT,
            tool_calls_json TEXT,
            tool_call_id TEXT,
            created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_messages_raw_conv ON ai_messages_raw(conversation_id, id)',
        );
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_prompt_usage_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id TEXT NOT NULL,
            model TEXT,
            prompt_est_before INTEGER,
            prompt_est_sent INTEGER,
            usage_prompt_tokens INTEGER,
            usage_completion_tokens INTEGER,
            usage_total_tokens INTEGER,
            usage_source TEXT,
            is_tool_loop INTEGER NOT NULL DEFAULT 0,
            include_history INTEGER NOT NULL DEFAULT 1,
            tools_count INTEGER NOT NULL DEFAULT 0,
            strict_full_attempted INTEGER NOT NULL DEFAULT 0,
            fallback_triggered INTEGER NOT NULL DEFAULT 0,
            breakdown_json TEXT,
            created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_prompt_usage_events_conv ON ai_prompt_usage_events(conversation_id, id)',
        );
      } catch (_) {}
    }

    // v30: Persist per-segment AI request/response traces (debugging).
    if (oldVersion < 30) {
      try {
        await db.execute(
          'ALTER TABLE segment_results ADD COLUMN raw_request TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE segment_results ADD COLUMN raw_response TEXT',
        );
      } catch (_) {}
    }

    // v31: Global, cross-conversation user memory (profile + items + evidence + index state).
    if (oldVersion < 31) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_memory_profile (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            user_markdown TEXT,
            auto_markdown TEXT,
            user_updated_at INTEGER,
            auto_updated_at INTEGER,
            created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
          )
        ''');
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_memory_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            memory_key TEXT,
            content TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            keywords_json TEXT,
            confidence REAL,
            pinned INTEGER NOT NULL DEFAULT 0,
            user_edited INTEGER NOT NULL DEFAULT 0,
            first_seen_at INTEGER,
            last_seen_at INTEGER,
            created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
            updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_memory_items_kind ON user_memory_items(kind, pinned DESC, updated_at DESC, id DESC)',
        );
      } catch (_) {}
      try {
        await db.execute(
          "CREATE UNIQUE INDEX IF NOT EXISTS uniq_user_memory_items_key ON user_memory_items(memory_key) WHERE memory_key IS NOT NULL AND TRIM(memory_key) != ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS uniq_user_memory_items_hash ON user_memory_items(content_hash)',
        );
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_memory_evidence (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            memory_item_id INTEGER NOT NULL,
            source_type TEXT NOT NULL,
            source_id TEXT NOT NULL,
            evidence_filenames_json TEXT,
            start_time INTEGER,
            end_time INTEGER,
            created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
            UNIQUE(memory_item_id, source_type, source_id)
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_memory_evidence_item ON user_memory_evidence(memory_item_id, created_at DESC, id DESC)',
        );
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_memory_index_state (
            source TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            cursor_json TEXT,
            stats_json TEXT,
            started_at INTEGER,
            finished_at INTEGER,
            updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
            error TEXT
          )
        ''');
      } catch (_) {}

      try {
        await _createUserMemoryItemsFts(db);
      } catch (_) {}
      try {
        await _backfillUserMemoryItemsFts(db);
      } catch (_) {}
    }
  }

  /// 创建汇总统计表（用于版本升级）
  Future<void> _createTotalsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS totals (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        app_count INTEGER NOT NULL DEFAULT 0,
        screenshot_count INTEGER NOT NULL DEFAULT 0,
        total_size_bytes INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
  }

  // 无升级逻辑：新安装直接按 _onCreate 创建所有表
  // 注：从 v2 起使用 _onUpgrade 进行增量迁移

  /// 检查文件路径是否已存在于数据库中（可选指定执行器，以便在事务中调用）
  Future<bool> isFilePathExists(
    String filePath, {
    DatabaseExecutor? exec,
  }) async {
    final DatabaseExecutor db = exec ?? await database;
    try {
      // 从文件路径推断应用包名
      final packageName = _extractPackageNameFromPath(filePath);
      if (packageName == null) {
        print('无法从路径推断包名: $filePath');
        return false;
      }

      final tableName = _getAppTableName(packageName);

      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        return false;
      }

      final result = await db.query(
        tableName,
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      print('检查文件路径是否存在失败: $e');
      return false;
    }
  }

  /// 插入截屏记录（如果不存在）
  Future<int?> insertScreenshotIfNotExists(ScreenshotRecord record) async {
    final db = await database; // 主库
    try {
      await db.transaction((txn) async {
        // 主库注册应用
        await _registerAppIfNeeded(txn, record.appPackageName, record.appName);

        final ts = record.captureTime.millisecondsSinceEpoch;
        final year = _yearFromMillis(ts);
        final month = _monthFromMillis(ts);
        final shardDb = await _openShardDb(record.appPackageName, year);
        if (shardDb == null) throw Exception('open shard db failed');

        // 月表建表
        await _ensureMonthTable(shardDb, year, month);
        final tableName = _monthTableName(year, month);

        // 去重：按 file_path 在该月表查重
        try {
          final rows = await shardDb.query(
            tableName,
            columns: ['id'],
            where: 'file_path = ?',
            whereArgs: [record.filePath],
            limit: 1,
          );
          if (rows.isNotEmpty) return null;
        } catch (_) {}

        // 计算实际文件大小
        final file = File(record.filePath);
        final actualFileSize = await file.exists() ? await file.length() : 0;
        final recordWithSize = record.copyWith(fileSize: actualFileSize);

        // 插入分库月表
        final map = {...recordWithSize.toMap()};
        map.remove('app_package_name');
        map.remove('app_name');
        final localId = await shardDb.insert(tableName, map);

        // 更新主库聚合
        await _upsertAppStatOnInsert(
          txn,
          recordWithSize.appPackageName,
          recordWithSize.appName,
          actualFileSize,
          ts,
        );

        // 更新汇总统计
        await this.updateTotalsOnInsert(
          [recordWithSize.appPackageName],
          1,
          actualFileSize,
        );

        final gid = _encodeGid(year, month, localId);
        print('分库插入成功 gid=$gid table=$tableName');
        return gid;
      });
    } catch (e) {
      print('插入截屏记录失败: $e');
      rethrow;
    }
  }

  /// 插入截屏记录（保留原方法以兼容性）
  Future<int> insertScreenshot(ScreenshotRecord record) async {
    // 兼容旧接口：返回本地ID（从gid中提取localId）
    final gid = await insertScreenshotIfNotExists(record);
    if (gid == null) return 0;
    final decoded = _decodeGid(gid);
    if (decoded == null) return 0;
    return decoded[2];
  }

  /// 批量插入（去重）：输入为记录列表，返回成功插入的数量
  Future<int> insertScreenshotsIfNotExistsBatch(
    List<ScreenshotRecord> records,
  ) async {
    if (records.isEmpty) return 0;
    final db = await database; // 主库
    int inserted = 0;
    final Map<String, int> packageCounts = {};
    final Map<String, int> packageSizes = {};

    try {
      await db.transaction((txn) async {
        for (final record in records) {
          await _registerAppIfNeeded(
            txn,
            record.appPackageName,
            record.appName,
          );
          final ts = record.captureTime.millisecondsSinceEpoch;
          final year = _yearFromMillis(ts);
          final month = _monthFromMillis(ts);
          final shardDb = await _openShardDb(record.appPackageName, year);
          if (shardDb == null) continue;
          await _ensureMonthTable(shardDb, year, month);
          final tableName = _monthTableName(year, month);
          try {
            final rows = await shardDb.query(
              tableName,
              columns: ['id'],
              where: 'file_path = ?',
              whereArgs: [record.filePath],
              limit: 1,
            );
            if (rows.isNotEmpty) continue; // 去重
          } catch (_) {}
          final file = File(record.filePath);
          final actualFileSize = await file.exists() ? await file.length() : 0;
          final recordWithSize = record.copyWith(fileSize: actualFileSize);
          final map = {...recordWithSize.toMap()};
          map.remove('app_package_name');
          map.remove('app_name');
          await shardDb.insert(tableName, map);
          await _upsertAppStatOnInsert(
            txn,
            recordWithSize.appPackageName,
            recordWithSize.appName,
            actualFileSize,
            ts,
          );
          inserted++;
          packageCounts[recordWithSize.appPackageName] =
              (packageCounts[recordWithSize.appPackageName] ?? 0) + 1;
          packageSizes[recordWithSize.appPackageName] =
              (packageSizes[recordWithSize.appPackageName] ?? 0) +
              actualFileSize;
        }

        // 批量更新汇总统计
        if (inserted > 0) {
          final packageNames = packageCounts.keys.toList();
          final totalScreenshots = packageCounts.values.fold(
            0,
            (sum, count) => sum + count,
          );
          final totalSize = packageSizes.values.fold(
            0,
            (sum, size) => sum + size,
          );
          await this.updateTotalsOnInsert(
            packageNames,
            totalScreenshots,
            totalSize,
          );
        }
      });
    } catch (e) {
      print('批量插入截图记录失败: $e');
    }
    return inserted;
  }

  /// 高速批量插入：
  /// - 使用单事务 + Batch + INSERT OR IGNORE，避免逐条去重查询
  /// - 以包维度预建表，一次性提交
  /// - 结尾对每个包做一次聚合重算，代替逐条增量更新
  Future<int> insertScreenshotsFast(List<ScreenshotRecord> records) async {
    if (records.isEmpty) return 0;
    final db = await database; // 主库
    int totalInserted = 0;
    final Map<String, int> packageCounts = {};
    final Map<String, int> packageSizes = {};

    try {
      // 按包分组（减少表切换开销）
      final Map<String, List<ScreenshotRecord>> byPkg =
          <String, List<ScreenshotRecord>>{};
      for (final r in records) {
        byPkg.putIfAbsent(r.appPackageName, () => <ScreenshotRecord>[]).add(r);
      }

      await db.transaction((txn) async {
        for (final entry in byPkg.entries) {
          final String packageName = entry.key;
          final List<ScreenshotRecord> list = entry.value;
          if (list.isEmpty) continue;

          // 注册应用
          final String appName = list.first.appName;
          await _registerAppIfNeeded(txn, packageName, appName);

          // 再按月份分组，分别写入对应分库月表
          final Map<int, List<ScreenshotRecord>> byYearMonthKey =
              <int, List<ScreenshotRecord>>{};
          for (final r in list) {
            final ts = r.captureTime.millisecondsSinceEpoch;
            final key = _yearFromMillis(ts) * 100 + _monthFromMillis(ts);
            byYearMonthKey.putIfAbsent(key, () => <ScreenshotRecord>[]).add(r);
          }

          for (final ym in byYearMonthKey.entries) {
            final int key = ym.key;
            final int year = key ~/ 100;
            final int month = key % 100;
            final shardDb = await _openShardDb(packageName, year);
            if (shardDb == null) continue;
            await _ensureMonthTable(shardDb, year, month);
            final String tableName = _monthTableName(year, month);

            final batch = shardDb.batch();
            for (final r in ym.value) {
              final map = {...r.toMap()};
              map.remove('app_package_name');
              map.remove('app_name');
              batch.insert(
                tableName,
                map,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
            final batchResult = await batch.commit(
              noResult: true,
              continueOnError: true,
            );
            if (batchResult != null) {
              totalInserted += batchResult.length;
            }

            // 重算该应用聚合一次（按包维度即可）
            await _recomputeAppStatForPackage(txn, packageName);

            // 累计统计数据
            packageCounts[packageName] =
                (packageCounts[packageName] ?? 0) + list.length;
            packageSizes[packageName] =
                (packageSizes[packageName] ?? 0) +
                list.fold(0, (sum, r) => sum + r.fileSize);
          }
        }

        // 批量更新汇总统计
        if (totalInserted > 0) {
          final packageNames = packageCounts.keys.toList();
          final totalScreenshots = packageCounts.values.fold(
            0,
            (sum, count) => sum + count,
          );
          final totalSize = packageSizes.values.fold(
            0,
            (sum, size) => sum + size,
          );
          await this.updateTotalsOnInsert(
            packageNames,
            totalScreenshots,
            totalSize,
          );
        }
      });
    } catch (e) {
      print('快速批量插入失败: $e');
    }
    return totalInserted;
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // ======= 聚合表维护辅助 =======
  Future<void> _upsertAppStatOnInsert(
    DatabaseExecutor db,
    String package,
    String appName,
    int fileSize,
    int captureTime,
  ) async {
    try {
      await db.execute(
        '''
        INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time)
        VALUES (?, ?, 1, ?, ?)
        ON CONFLICT(app_package_name) DO UPDATE SET
          app_name=excluded.app_name,
          total_count=app_stats.total_count + 1,
          total_size=app_stats.total_size + excluded.total_size,
          last_capture_time=CASE WHEN app_stats.last_capture_time IS NULL OR excluded.last_capture_time > app_stats.last_capture_time THEN excluded.last_capture_time ELSE app_stats.last_capture_time END
      ''',
        [package, appName, fileSize, captureTime],
      );
    } catch (e) {
      // 如设备SQLite不支持UPSERT，退化为全量重算
      await _recomputeAppStatForPackage(db, package);
    }
  }

  Future<void> _recomputeAppStatForPackage(
    DatabaseExecutor db,
    String package,
  ) async {
    try {
      // 聚合所有分库月表
      final master = await database;
      int totalCount = 0;
      int totalSize = 0;
      int lastCapture = 0;

      final years = await _listShardYearsForApp(package);
      for (final y in years) {
        final shardDb = await _openShardDb(package, y);
        if (shardDb == null) continue;
        for (int m = 1; m <= 12; m++) {
          final t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final rows = await shardDb.rawQuery(
              'SELECT COUNT(*) as c, COALESCE(SUM(file_size),0) as s, COALESCE(MAX(capture_time),0) as t FROM $t',
            );
            if (rows.isNotEmpty) {
              final c = (rows.first['c'] as int?) ?? 0;
              final s = (rows.first['s'] as int?) ?? 0;
              final tmax = (rows.first['t'] as int?) ?? 0;
              totalCount += c;
              totalSize += s;
              if (tmax > lastCapture) lastCapture = tmax;
            }
          } catch (_) {}
        }
      }

      if (totalCount <= 0) {
        await master.delete(
          'app_stats',
          where: 'app_package_name = ?',
          whereArgs: [package],
        );
        return;
      }

      // 读取 app_name
      String appName = package;
      try {
        final appInfo = await master.query(
          'app_registry',
          columns: ['app_name'],
          where: 'app_package_name = ?',
          whereArgs: [package],
          limit: 1,
        );
        if (appInfo.isNotEmpty) {
          appName = (appInfo.first['app_name'] as String?) ?? package;
        }
      } catch (_) {}

      await master.execute(
        '''INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(app_package_name) DO UPDATE SET app_name=excluded.app_name, total_count=excluded.total_count, total_size=excluded.total_size, last_capture_time=excluded.last_capture_time''',
        [package, appName, totalCount, totalSize, lastCapture],
      );
    } catch (e) {
      print('重新计算应用统计失败: $e');
    }
  }

  Future<void> recomputeAppStatsForPackage(String package) async {
    final db = await database;
    await _recomputeAppStatForPackage(db, package);
  }

  Future<List<String>> listRegisteredPackages() async {
    final db = await database;
    try {
      final rows = await db.query(
        'app_registry',
        columns: ['app_package_name'],
      );
      return rows
          .map((row) => row['app_package_name'] as String?)
          .whereType<String>()
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  // ======= 分表架构相关方法 =======

  // 已移除重复的 _sanitizePackageName 定义，使用文件顶部版本

  /// 获取应用表名
  String _getAppTableName(String packageName) {
    return 'screenshots_${_sanitizePackageName(packageName)}';
  }

  /// 从文件路径推断应用包名
  String? _extractPackageNameFromPath(String filePath) {
    // 适配新旧目录结构：
    // 新: .../output/screen/<package>/<yyyy-MM>/<dd>/<file>
    // 旧: .../<package>/screenshots/<file>
    final parts = filePath.split('/');
    if (parts.length >= 3) {
      for (int i = 0; i < parts.length - 1; i++) {
        final seg = parts[i];
        if (seg == 'output' &&
            i + 2 < parts.length &&
            parts[i + 1] == 'screen') {
          // output/screen/<package>
          return parts[i + 2];
        }
        if (i + 1 < parts.length && parts[i + 1] == 'screenshots') {
          // <package>/screenshots
          return seg;
        }
      }
    }
    return null;
  }

  /// 检查表是否存在
  Future<bool> _checkTableExists(DatabaseExecutor db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  /// 确保应用表存在
  Future<void> _ensureAppTableExists(
    DatabaseExecutor db,
    String packageName,
    String appName,
  ) async {
    final tableName = _getAppTableName(packageName);

    // 检查表是否存在
    if (await _checkTableExists(db, tableName)) {
      // 确保新增列存在（幂等地尝试添加）
      await _ensurePageUrlColumnExists(db, tableName);
      return;
    }

    // 创建应用表
    await _createAppTable(db, tableName);
    // 幂等确保新增列
    await _ensurePageUrlColumnExists(db, tableName);

    // 注册到app_registry
    await db.execute(
      '''
      INSERT OR REPLACE INTO app_registry (app_package_name, app_name, table_name)
      VALUES (?, ?, ?)
    ''',
      [packageName, appName, tableName],
    );

    print('已创建应用表: $tableName');
  }

  /// 幂等地为已有表添加 page_url 列（若已存在则忽略错误）
  Future<void> _ensurePageUrlColumnExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    try {
      await db.execute("ALTER TABLE $tableName ADD COLUMN page_url TEXT");
    } catch (e) {
      // 列已存在或不支持ALTER，忽略
    }
  }

  /// 创建应用表
  Future<void> _createAppTable(DatabaseExecutor db, String tableName) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_path TEXT NOT NULL UNIQUE,
          capture_time INTEGER NOT NULL,
          file_size INTEGER NOT NULL DEFAULT 0,
          page_url TEXT,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
          updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
        )
      ''');
    // 创建索引
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_capture_time ON $tableName(capture_time)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_file_path ON $tableName(file_path)',
    );
  }

  /// 获取所有应用表信息
  Future<List<Map<String, dynamic>>> _getAllAppTables(Database db) async {
    try {
      return await db.query('app_registry');
    } catch (e) {
      print('获取应用表列表失败: $e');
      return [];
    }
  }

  // ======= 日期范围查询辅助 =======
  List<List<int>> _listYearMonthBetween(DateTime start, DateTime end) {
    final DateTime s = DateTime(start.year, start.month, 1);
    final DateTime e = DateTime(end.year, end.month, 1);
    final List<List<int>> result = <List<int>>[];
    DateTime cur = s;
    while (!DateTime(cur.year, cur.month, 1).isAfter(e)) {
      result.add(<int>[cur.year, cur.month]);
      // 增加一个月
      final int nextMonth = cur.month == 12 ? 1 : cur.month + 1;
      final int nextYear = cur.month == 12 ? cur.year + 1 : cur.year;
      cur = DateTime(nextYear, nextMonth, 1);
    }
    return result;
  }

  // ===================== 汇总统计表操作 =====================

  /// 获取汇总统计数据（若不存在则初始化为0）
  Future<Map<String, dynamic>> getTotals() async {
    final db = await database;
    try {
      final rows = await db.query('totals', where: 'id = 1', limit: 1);
      if (rows.isEmpty) {
        // 初始化汇总表
        await db.insert('totals', {
          'id': 1,
          'app_count': 0,
          'screenshot_count': 0,
          'total_size_bytes': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
        return {
          'app_count': 0,
          'screenshot_count': 0,
          'total_size_bytes': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        };
      }
      return rows.first;
    } catch (e) {
      print('获取汇总统计失败: $e');
      return {
        'app_count': 0,
        'screenshot_count': 0,
        'total_size_bytes': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
    }
  }

  /// 增量更新汇总统计（在截图入库后调用）
  /// 对于新应用，先检查是否已存在于app_stats中判断是否首次出现
  Future<void> updateTotalsOnInsert(
    List<String> packageNames,
    int screenshotCount,
    int totalSizeBytes,
  ) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        int newAppCount = 0;

        // 检查哪些应用是首次出现（在app_stats中不存在）
        for (final packageName in packageNames) {
          final existing = await txn.query(
            'app_stats',
            columns: ['app_package_name'],
            where: 'app_package_name = ?',
            whereArgs: [packageName],
            limit: 1,
          );
          if (existing.isEmpty) {
            newAppCount++;
          }
        }

        // 更新汇总表
        await txn.execute(
          '''
          INSERT OR REPLACE INTO totals (id, app_count, screenshot_count, total_size_bytes, updated_at)
          VALUES (1,
            COALESCE((SELECT app_count FROM totals WHERE id = 1), 0) + ?,
            COALESCE((SELECT screenshot_count FROM totals WHERE id = 1), 0) + ?,
            COALESCE((SELECT total_size_bytes FROM totals WHERE id = 1), 0) + ?,
            ?
          )
        ''',
          [
            newAppCount,
            screenshotCount,
            totalSizeBytes,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
      });
    } catch (e) {
      print('更新汇总统计失败: $e');
    }
  }

  /// 从现有数据重新计算汇总统计（用于数据迁移或修复）
  Future<void> recalculateTotals() async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        // 计算应用数量
        final appStats = await txn.query('app_stats');
        final appCount = appStats.length;

        // 计算总截图数量和总大小
        int totalScreenshots = 0;
        int totalSizeBytes = 0;
        for (final stat in appStats) {
          totalScreenshots += (stat['total_count'] as int?) ?? 0;
          totalSizeBytes += (stat['total_size'] as int?) ?? 0;
        }

        // 更新或插入汇总表
        await txn.execute(
          '''
          INSERT OR REPLACE INTO totals (id, app_count, screenshot_count, total_size_bytes, updated_at)
          VALUES (1, ?, ?, ?, ?)
        ''',
          [
            appCount,
            totalScreenshots,
            totalSizeBytes,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );

        print(
          '重新计算汇总统计完成: 应用=$appCount, 截图=$totalScreenshots, 大小=$totalSizeBytes',
        );
      });
    } catch (e) {
      print('重新计算汇总统计失败: $e');
    }
  }
}

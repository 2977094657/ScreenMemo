import 'dart:io';
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

/// 截屏数据库服务
class ScreenshotDatabase {
  static ScreenshotDatabase? _instance;
  static Database? _database;
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  static ScreenshotDatabase get instance => _instance ??= ScreenshotDatabase._();

  ScreenshotDatabase._();

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
      // 获取应用的外部存储目录
      final externalDir = await PathService.getExternalFilesDir(null) ?? await _getExternalFilesDir(); 
      try { await FlutterLogger.nativeInfo('DB', 'init externalDir=' + (externalDir?.path ?? 'null')); } catch (_) {}
      if (externalDir != null) {
        // 创建 output/databases 目录
        final databasesDir = Directory(join(externalDir.path, 'output', 'databases'));
        if (!await databasesDir.exists()) {
          await databasesDir.create(recursive: true);
          print('数据库目录已创建: ${databasesDir.path}');
        }
        
        // 主库（聚合、注册表等）
        final path = join(databasesDir.path, 'screenshot_memo.db');
        try { await FlutterLogger.nativeInfo('DB', 'open master db at ' + path); } catch (_) {}
        print('数据库路径: $path');
        
        final db = await openDatabase(
          path,
          version: 3,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        StartupProfiler.end('ScreenshotDatabase._initDatabase');
        return db;
      } else {
        // 备选方案：使用默认数据库路径
        print('无法获取外部存储目录，使用默认数据库路径');
        final databasesPath = await getDatabasesPath();
        final path = join(databasesPath, 'screenshot_memo.db'); 
        try { await FlutterLogger.nativeWarn('DB', 'fallback internal db at ' + path); } catch (_) {}
        
        final db = await openDatabase(
          path,
          version: 3,
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
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      StartupProfiler.end('ScreenshotDatabase._initDatabase');
      return db;
    }
  }

  /// 获取外部存储目录的辅助方法
  Future<Directory?> _getExternalFilesDir() async {
    try {
      if (Platform.isAndroid) {
        // 优先尝试外部存储目录
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          return dir;
        }
      }
      
      // 备选方案：使用应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      return dir;
    } catch (e) {
      print('获取外部存储目录失败: $e');
      return null;
    }
  }

  // ===================== 分库/分表 工具函数 =====================

  String _sanitizePackageName(String packageName) {
    return packageName.replaceAll(RegExp(r'[^\w]'), '_');
  }

  Future<Directory?> _getShardsRootDir() async {
    final base = await PathService.getExternalFilesDir(null) ?? await _getExternalFilesDir();
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
    final pkgDir = Directory(join(root.path, _sanitizePackageName(package), '$year'));
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

  Future<void> _ensureMonthTable(DatabaseExecutor shardDb, int year, int month) async {
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
    await shardDb.execute('CREATE INDEX IF NOT EXISTS idx_${table}_capture_time ON $table(capture_time)');
    await shardDb.execute('CREATE INDEX IF NOT EXISTS idx_${table}_file_path ON $table(file_path)');
    // 兜底：老表添加缺失列
    try { await shardDb.execute("ALTER TABLE $table ADD COLUMN ocr_text TEXT"); } catch (_) {}
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

  int _yearFromMillis(int millis) => DateTime.fromMillisecondsSinceEpoch(millis).year;
  int _monthFromMillis(int millis) => DateTime.fromMillisecondsSinceEpoch(millis).month;

  /// 仅在主库中注册应用（不再在主库创建分表）
  Future<void> _registerAppIfNeeded(DatabaseExecutor db, String packageName, String appName) async {
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
      final res = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [tableName]);
      return res.isNotEmpty;
    } catch (_) {
      return false;
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
    await db.execute('CREATE INDEX idx_app_stats_last ON app_stats(last_capture_time)');

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

    // v2: AI 配置与会话表
    await _createAiTables(db);
  }

  /// 升级回调：按版本增量迁移
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createAiTables(db);
    } else {
      // 幂等确保新表
      await _createAiTables(db);
    }
  }

  Future<void> _createAiTables(DatabaseExecutor db) async {
    // ai_settings: 单行键值存储
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    // ai_messages: 简单会话历史（默认会话：conversation_id='default'）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_messages_conv ON ai_messages(conversation_id, id)');

    // ai_site_groups: 接口站点分组（用于多站点备用&排序）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_site_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT,
        model TEXT NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_site_groups_order ON ai_site_groups(enabled, order_index, id)');

    // 段落与结果表（与原生侧保持一致）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        duration_sec INTEGER NOT NULL,
        sample_interval_sec INTEGER NOT NULL,
        status TEXT NOT NULL,
        app_packages TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_segments_time ON segments(start_time, end_time)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS segment_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        segment_id INTEGER NOT NULL,
        capture_time INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        app_package_name TEXT NOT NULL,
        app_name TEXT NOT NULL,
        position_index INTEGER NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(segment_id, file_path)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_segment_samples_seg ON segment_samples(segment_id, position_index)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS segment_results (
        segment_id INTEGER PRIMARY KEY,
        ai_provider TEXT,
        ai_model TEXT,
        output_text TEXT,
        structured_json TEXT,
        categories TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
  }

  // ======= 段落查询接口 =======
  Future<Map<String, dynamic>?> getActiveSegment() async {
    final db = await database;
    try {
      final rows = await db.query(
        'segments',
        where: 'status = ?',
        whereArgs: ['collecting'],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>> listSegments({int limit = 50, int offset = 0}) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segments',
        orderBy: 'id DESC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (_) { return <Map<String, dynamic>>[]; }
  }

  /// 列出段落（带是否有总结标记），可选仅返回“无总结”的事件
  /// - has_summary: 0 表示无总结；1 表示已有总结
  /// - 仅返回“至少有一张样本图片”的事件，避免前端渲染后再隐藏导致滚动抖动
  Future<List<Map<String, dynamic>>> listSegmentsEx({int limit = 50, bool onlyNoSummary = false}) async {
    final db = await database;
    try {
      const String noSummaryCond =
          "r.segment_id IS NULL OR ((r.output_text IS NULL OR LOWER(TRIM(r.output_text)) IN ('','null')) AND (r.structured_json IS NULL OR LOWER(TRIM(r.structured_json)) IN ('','null')))";
      const String hasSamplesCond =
          "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
      // 组合 WHERE 子句
      final List<String> whereClauses = <String>[hasSamplesCond];
      if (onlyNoSummary) {
        whereClauses.add('(' + noSummaryCond + ')');
      }
      final String whereSql = whereClauses.isEmpty ? '' : ('WHERE ' + whereClauses.join(' AND '));
      final String sql = '''
        SELECT
          s.*,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary,
          (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count,
          -- 若 segments.app_packages 为空，回退为样本表去重聚合
          COALESCE(
            NULLIF(TRIM(s.app_packages), ''),
            (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
          ) AS app_packages_display,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        $whereSql
        ORDER BY s.id DESC
        LIMIT ?
      ''';
      final rows = await db.rawQuery(sql, [limit]);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 触发一次原生端的段落推进/补救扫描（用于点击刷新时重试缺失总结）
  Future<bool> triggerSegmentTick() async {
    try {
      final res = await _channel.invokeMethod('triggerSegmentTick');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// 通过原生接口按ID批量重试生成总结
  /// force=true 时无视已有结果与时间范围，直接强制重跑
  Future<int> retrySegments(List<int> ids, {bool force = false}) async {
    try {
      final res = await _channel.invokeMethod('retrySegments', {
        'ids': ids,
        'force': force,
      });
      if (res is int) return res;
      if (res is num) return res.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> listSegmentSamples(int segmentId) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segment_samples',
        where: 'segment_id = ?',
        whereArgs: [segmentId],
        orderBy: 'position_index ASC',
      );
      return rows;
    } catch (_) { return <Map<String, dynamic>>[]; }
  }

  Future<Map<String, dynamic>?> getSegmentResult(int segmentId) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segment_results',
        where: 'segment_id = ?',
        whereArgs: [segmentId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) { return null; }
  }
  /// 删除单个段落事件（仅删除事件及其结果/样本，不删除月表中的图片记录/文件）
  Future<bool> deleteSegmentOnly(int segmentId) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        await txn.delete('segment_results', where: 'segment_id = ?', whereArgs: [segmentId]);
        await txn.delete('segment_samples', where: 'segment_id = ?', whereArgs: [segmentId]);
        await txn.delete('segments', where: 'id = ?', whereArgs: [segmentId]);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // 无升级逻辑：新安装直接按 _onCreate 创建所有表
  // 注：从 v2 起使用 _onUpgrade 进行增量迁移

  /// 检查文件路径是否已存在于数据库中（可选指定执行器，以便在事务中调用）
  Future<bool> isFilePathExists(String filePath, {DatabaseExecutor? exec}) async {
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
      // 主库注册应用
      await _registerAppIfNeeded(db, record.appPackageName, record.appName);

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
        final rows = await shardDb.query(tableName, columns: ['id'], where: 'file_path = ?', whereArgs: [record.filePath], limit: 1);
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
        db,
        recordWithSize.appPackageName,
        recordWithSize.appName,
        actualFileSize,
        ts,
      );

      final gid = _encodeGid(year, month, localId);
      print('分库插入成功 gid=$gid table=$tableName');
      return gid;
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
  Future<int> insertScreenshotsIfNotExistsBatch(List<ScreenshotRecord> records) async {
    if (records.isEmpty) return 0;
    final db = await database; // 主库
    int inserted = 0;
    try {
      await db.transaction((txn) async {
        for (final record in records) {
          await _registerAppIfNeeded(txn, record.appPackageName, record.appName);
          final ts = record.captureTime.millisecondsSinceEpoch;
          final year = _yearFromMillis(ts);
          final month = _monthFromMillis(ts);
          final shardDb = await _openShardDb(record.appPackageName, year);
          if (shardDb == null) continue;
          await _ensureMonthTable(shardDb, year, month);
          final tableName = _monthTableName(year, month);
          try {
            final rows = await shardDb.query(tableName, columns: ['id'], where: 'file_path = ?', whereArgs: [record.filePath], limit: 1);
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
    try {
      // 按包分组（减少表切换开销）
      final Map<String, List<ScreenshotRecord>> byPkg = <String, List<ScreenshotRecord>>{};
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
          final Map<int, List<ScreenshotRecord>> byYearMonthKey = <int, List<ScreenshotRecord>>{};
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
          await batch.commit(noResult: true, continueOnError: true);

            // 重算该应用聚合一次（按包维度即可）
          await _recomputeAppStatForPackage(txn, packageName);
          }
        }
      });
    } catch (e) {
      print('快速批量插入失败: $e');
    }
    return totalInserted;
  }

  /// 根据应用包名获取截屏记录列表（支持分页）
  Future<List<ScreenshotRecord>> getScreenshotsByApp(String appPackageName, {int? limit, int? offset}) async {
    final db = await database; // 主库
    try {
      // 读取 app_name
      String appName = appPackageName;
      try {
      final appInfo = await db.query(
        'app_registry',
        columns: ['app_name'],
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
        limit: 1,
      );
      if (appInfo.isNotEmpty) {
          appName = (appInfo.first['app_name'] as String?) ?? appPackageName;
        }
      } catch (_) {}

      // 汇总所有已存在的分库年份
      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return [];

      // 合并所有月表数据后按时间排序 + 分页（按需抓取足量再截取）
      final List<Map<String, dynamic>> rows = [];
      // 计算本次请求的“需求量”= offset + limit，用较大的缓冲避免跨月不足
      final int requested = ((offset ?? 0) + (limit ?? 100));
      // 全局抓取目标：需求量的4倍作为缓冲，避免边界不足
      final int target = (requested <= 0 ? 400 : requested * 4);
      // 单表抓取上限：随需求线性放大，最小200，最大5000，避免一次性过大
      final int perTableLimit = (() {
        final int base = requested <= 0 ? 400 : requested * 2;
        if (base < 200) return 200;
        if (base > 5000) return 5000;
        return base;
      })();

      outer:
      for (final y in years) {
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        for (int m = 12; m >= 1; m--) {
          final t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final maps = await shardDb.query(
              t,
              orderBy: 'capture_time DESC',
              limit: perTableLimit,
              offset: 0,
            );
            for (final map in maps) {
              final full = Map<String, dynamic>.from(map);
              full['app_package_name'] = appPackageName;
              full['app_name'] = appName;
              // 构造 gid 供上层使用（不改变模型结构）
              final localId = (map['id'] as int?) ?? 0;
              full['id'] = _encodeGid(y, m, localId);
              rows.add(full);
              if (rows.length >= target) break outer;
            }
          } catch (_) {}
        }
      }

      rows.sort((a, b) {
        final int ta = (a['capture_time'] as int?) ?? 0;
        final int tb = (b['capture_time'] as int?) ?? 0;
        return tb.compareTo(ta);
      });

      // 应用分页
      int start = offset ?? 0;
      if (start < 0) start = 0;
      int end = limit != null ? (start + limit) : rows.length;
      if (start > rows.length) return [];
      if (end > rows.length) end = rows.length;
      final slice = rows.sublist(start, end);
      return slice.map((m) => ScreenshotRecord.fromMap(m)).toList();
    } catch (e) {
      print('查询截屏记录失败: $e');
      return [];
    }
  }

  /// 获取某应用所有截图的全局ID列表（不分页）
  Future<List<int>> getAllScreenshotIdsForApp(String appPackageName) async {
    final db = await database; // 主库
    try {
      final List<int> ids = <int>[];
      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return ids;
      for (final y in years) {
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        for (int m = 12; m >= 1; m--) {
          final t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final rows = await shardDb.query(
              t,
              columns: ['id'],
            );
            for (final r in rows) {
              final localId = (r['id'] as int?) ?? 0;
              if (localId > 0) ids.add(_encodeGid(y, m, localId));
            }
          } catch (_) {}
        }
      }
      return ids;
    } catch (e) {
      print('getAllScreenshotIdsForApp 失败: $e');
      return <int>[];
    }
  }

  /// 获取某应用在指定时间范围内的所有截图全局ID（不分页）
  Future<List<int>> getScreenshotIdsByAppBetween(
    String appPackageName, {
    required int startMillis,
    required int endMillis,
  }) async {
    final db = await database; // 主库
    try {
      final List<int> ids = <int>[];
      if (endMillis < startMillis) return ids;
      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return ids;
      final List<List<int>> ymList = _listYearMonthBetween(
        DateTime.fromMillisecondsSinceEpoch(startMillis),
        DateTime.fromMillisecondsSinceEpoch(endMillis),
      );
      for (final ym in ymList) {
        final int y = ym[0];
        final int m = ym[1];
        if (!years.contains(y)) continue;
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        final String t = _monthTableName(y, m);
        if (!await _tableExists(shardDb, t)) continue;
        try {
          final rows = await shardDb.query(
            t,
            columns: ['id'],
            where: 'capture_time >= ? AND capture_time <= ?',
            whereArgs: [startMillis, endMillis],
          );
          for (final r in rows) {
            final localId = (r['id'] as int?) ?? 0;
            if (localId > 0) ids.add(_encodeGid(y, m, localId));
          }
        } catch (_) {}
      }
      return ids;
    } catch (e) {
      print('getScreenshotIdsByAppBetween 失败: $e');
      return <int>[];
    }
  }

  /// 获取指定应用的截屏总数量
  Future<int> getScreenshotCountByApp(String appPackageName) async {
    final db = await database; // 主库
    try {
      // 直接走 app_stats 聚合
      final rows = await db.query(
        'app_stats',
        columns: ['total_count'],
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      return (rows.first['total_count'] as int?) ?? 0;
    } catch (e) {
      print('获取应用截屏数量失败: $e');
      return 0;
    }
  }

  /// 获取所有应用的截屏统计
  Future<Map<String, Map<String, dynamic>>> getScreenshotStatistics() async {
    StartupProfiler.begin('ScreenshotDatabase.getScreenshotStatistics');
    final db = await database;
    try {
      // 优先读取聚合表，避免每次实时聚合
      var maps = await db.rawQuery('''
        SELECT app_package_name, app_name, total_count, last_capture_time, total_size
        FROM app_stats
        ORDER BY last_capture_time DESC
      ''');

      final statistics = <String, Map<String, dynamic>>{};
      // 严格按写时维护统计，不做读时补偿，以保证性能和一致性

      for (final map in maps) {
        final packageName = map['app_package_name'] as String;
        statistics[packageName] = {
          'appName': map['app_name'] as String,
          'totalCount': map['total_count'] as int,
          'lastCaptureTime': map['last_capture_time'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['last_capture_time'] as int)
              : null,
          'totalSize': map['total_size'] as int,
        };
      }

      return statistics;
    } catch (e) {
      print('获取截屏统计失败: $e');
      // 如果app_stats表不存在或失败，返回空结果
      return {};
    }
    finally {
      StartupProfiler.end('ScreenshotDatabase.getScreenshotStatistics');
    }
  }

  /// 获取今日截屏数量
  Future<int> getTodayScreenshotCount() async {
    StartupProfiler.begin('ScreenshotDatabase.getTodayScreenshotCount');
    final db = await database; // 主库
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59).millisecondsSinceEpoch;

      // 获取所有应用
      final appTables = await _getAllAppTables(db);
      int totalCount = 0;
      final nowYear = today.year;
      final shardYears = await db.query('shard_registry', columns: ['app_package_name','year'], orderBy: 'year DESC');
      // 仅统计今天所在的年份分库（跨年边界可再扩展）
      for (final row in shardYears) {
        final String pkg = row['app_package_name'] as String;
        final int y = row['year'] as int;
        if (y != nowYear) continue;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        final int m = today.month;
        final t = _monthTableName(y, m);
        if (!await _tableExists(shardDb, t)) continue;
        try {
          final result = await shardDb.rawQuery('''
            SELECT COUNT(*) as count FROM $t WHERE capture_time >= ? AND capture_time <= ?
          ''', [startOfDay, endOfDay]);
          totalCount += (result.first['count'] as int?) ?? 0;
        } catch (e) {
          print('查询 $pkg/$t 今日数量失败: $e');
        }
      }

      return totalCount;
    } catch (e) {
      print('获取今日截屏数量失败: $e');
      return 0;
    }
    finally {
      StartupProfiler.end('ScreenshotDatabase.getTodayScreenshotCount');
    }
  }

  /// 全局：获取给定日期范围内的截图总数（所有应用，包含边界，毫秒）
  Future<int> getGlobalScreenshotCountBetween({
    required int startMillis,
    required int endMillis,
  }) async {
    final db = await database; // 主库
    try {
      if (endMillis < startMillis) return 0;
      int total = 0;
      final DateTime s = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final DateTime e = DateTime.fromMillisecondsSinceEpoch(endMillis);
      // 遍历分库注册表，找出涉及的年份与包名
      final rows = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      if (rows.isEmpty) return 0;
      // 需要的年月列表
      final ymList = _listYearMonthBetween(s, e);
      for (final row in rows) {
        final String pkg = row['app_package_name'] as String;
        final int y = row['year'] as int;
        // 仅处理日期范围涉及到的年份
        final containsYear = ymList.any((ym) => ym[0] == y);
        if (!containsYear) continue;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        for (final ym in ymList) {
          final int year = ym[0];
          final int month = ym[1];
          if (year != y) continue;
          final table = _monthTableName(year, month);
          if (!await _tableExists(shardDb, table)) continue;
          try {
            final res = await shardDb.rawQuery(
              'SELECT COUNT(*) as c FROM $table WHERE capture_time >= ? AND capture_time <= ?',
              [startMillis, endMillis],
            );
            total += (res.first['c'] as int?) ?? 0;
          } catch (_) {}
        }
      }
      return total;
    } catch (e) {
      print('getGlobalScreenshotCountBetween 失败: $e');
      return 0;
    }
  }

  /// 全局：获取给定日期范围内的截图列表（所有应用，按时间倒序，支持分页）
  Future<List<ScreenshotRecord>> getGlobalScreenshotsBetween({
    required int startMillis,
    required int endMillis,
    int? limit,
    int? offset,
  }) async {
    final db = await database; // 主库
    try {
      if (endMillis < startMillis) return <ScreenshotRecord>[];
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
      final DateTime s = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final DateTime e = DateTime.fromMillisecondsSinceEpoch(endMillis);
      final ymList = _listYearMonthBetween(s, e);

      // 遍历所有已注册的 (package, year)
      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      // 预读 app 名称以减少重复查询
      final Map<String, String> appNameCache = <String, String>{};
      try {
        final reg = await db.query('app_registry', columns: ['app_package_name', 'app_name']);
        for (final r in reg) {
          final pkg = r['app_package_name'] as String;
          final name = (r['app_name'] as String?) ?? pkg;
          appNameCache[pkg] = name;
        }
      } catch (_) {}

      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
        // 仅处理涉及到的年份
        final containsYear = ymList.any((ym) => ym[0] == y);
        if (!containsYear) continue;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        final String appName = appNameCache[pkg] ?? pkg;
        for (final ym in ymList) {
          final int year = ym[0];
          final int month = ym[1];
          if (year != y) continue;
          final t = _monthTableName(year, month);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final maps = await shardDb.query(
              t,
              where: 'capture_time >= ? AND capture_time <= ? AND is_deleted = 0',
              whereArgs: [startMillis, endMillis],
              orderBy: 'capture_time DESC',
            );
            for (final m in maps) {
              final full = Map<String, dynamic>.from(m);
              full['app_package_name'] = pkg;
              full['app_name'] = appName;
              final localId = (m['id'] as int?) ?? 0;
              full['id'] = _encodeGid(year, month, localId);
              rows.add(full);
            }
          } catch (_) {}
        }
      }

      // 全局排序
      rows.sort((a, b) {
        final int ta = (a['capture_time'] as int?) ?? 0;
        final int tb = (b['capture_time'] as int?) ?? 0;
        return tb.compareTo(ta);
      });

      // 分页
      int start = offset ?? 0;
      if (start < 0) start = 0;
      int end = limit != null ? (start + limit) : rows.length;
      if (start > rows.length) return <ScreenshotRecord>[];
      if (end > rows.length) end = rows.length;
      final slice = rows.sublist(start, end);
      return slice.map((m) => ScreenshotRecord.fromMap(m)).toList();
    } catch (e) {
      print('getGlobalScreenshotsBetween 失败: $e');
      return <ScreenshotRecord>[];
    }
  }

  /// 获取总截屏数量
  Future<int> getTotalScreenshotCount() async {
    StartupProfiler.begin('ScreenshotDatabase.getTotalScreenshotCount');
    final db = await database; // 主库
    try {
      final result = await db.rawQuery('SELECT SUM(total_count) as count FROM app_stats');
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      print('获取总截屏数量失败: $e');
      return 0;
    }
    finally {
      StartupProfiler.end('ScreenshotDatabase.getTotalScreenshotCount');
    }
  }

  /// 硬删除截屏记录（同时删除数据库记录和文件）
  Future<bool> deleteScreenshot(int id, String packageName) async {
    final db = await database; // 主库
    try {
      FlutterLogger.nativeInfo('DB', 'deleteScreenshot start id='+id.toString()+', package='+packageName);

      final decoded = _decodeGid(id);
      if (decoded == null) {
        FlutterLogger.nativeWarn('DB', '删除截图时无效的gid='+id.toString());
        return false;
      }
      final int year = decoded[0];
      final int month = decoded[1];
      final int localId = decoded[2];
      final shardDb = await _openShardDb(packageName, year);
      if (shardDb == null) return false;
      final tableName = _monthTableName(year, month);
      if (!await _tableExists(shardDb, tableName)) return false;
      // 读取文件路径
      final maps = await shardDb.query(
        tableName,
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (maps.isEmpty) return false;
      final filePath = maps.first['file_path'] as String;
      final result = await shardDb.delete(tableName, where: 'id = ?', whereArgs: [localId]);
      if (result <= 0) return false;
      // 删除物理文件
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            FlutterLogger.nativeInfo('FS', 'deleted file: '+filePath);
        }
      } catch (e) {
        FlutterLogger.nativeWarn('FS', 'delete file failed: '+e.toString());
      }
      // 重算聚合
        await _recomputeAppStatForPackage(db, packageName);
      FlutterLogger.nativeInfo('DB', '删除后重算统计 gid='+id.toString());
        return true;
    } catch (e) {
      print('删除截屏记录失败: $e');
      // ignore: unawaited_futures
      FlutterLogger.nativeError('DB', '删除截图时发生异常: '+e.toString());
      return false;
    }
  }

  /// 批量删除指定ID的截屏记录（高效，带增量统计更新与并发文件删除）
  /// 返回实际删除的数据库记录数
  Future<int> deleteScreenshotsByIds(String packageName, List<int> ids) async {
    final db = await database; // 主库
    try {
      if (ids.isEmpty) return 0;

          final sw = Stopwatch()..start();
      // 将 gid 解码并按 (year, month) 分组
      final Map<int, List<int>> byYm = {};
      for (final gid in ids) {
        final d = _decodeGid(gid);
        if (d == null) continue;
        final key = d[0] * 100 + d[1];
        byYm.putIfAbsent(key, () => <int>[]).add(d[2]);
      }

      // 预取所有文件路径
      final List<String> filePaths = [];
      int deletedTotal = 0;
      for (final entry in byYm.entries) {
        final int key = entry.key;
        final int year = key ~/ 100;
        final int month = key % 100;
        final shardDb = await _openShardDb(packageName, year);
        if (shardDb == null) continue;
        final tableName = _monthTableName(year, month);
        if (!await _tableExists(shardDb, tableName)) continue;
        try {
          final localIds = entry.value;
          if (localIds.isEmpty) continue;
          final ph = List.filled(localIds.length, '?').join(',');
          // 查询路径
          final rows = await shardDb.query(
            tableName,
            columns: ['file_path'],
            where: 'id IN ($ph)',
            whereArgs: localIds,
          );
          for (final r in rows) {
            final p = (r['file_path'] as String?);
            if (p != null) filePaths.add(p);
          }
          // 分片删除
          const int chunk = 900;
          for (int i = 0; i < localIds.length; i += chunk) {
            final sub = localIds.sublist(i, i + chunk > localIds.length ? localIds.length : i + chunk);
            final ph2 = List.filled(sub.length, '?').join(',');
            final count = await shardDb.rawDelete('DELETE FROM $tableName WHERE id IN ($ph2)', sub);
            deletedTotal += count;
              }
            } catch (_) {}
      }

      // 重算聚合
        await _recomputeAppStatForPackage(db, packageName);

      // 并发删除物理文件
      await _deleteFilesConcurrently(filePaths, maxConcurrent: 6);

      sw.stop();
      FlutterLogger.nativeInfo('TOTAL', '批量删除总耗时 ${sw.elapsedMilliseconds}ms');
      return deletedTotal;
    } catch (e) {
      print('批量删除截屏记录失败: $e');
      return 0;
    }
  }

  /// 受限并发删除物理文件，降低I/O抖动
  Future<void> _deleteFilesConcurrently(List<String> paths, {int maxConcurrent = 6}) async {
    if (paths.isEmpty) return;
    // 分批并发执行，控制并发度
    const int batch = 24; // 单批文件数
    for (int i = 0; i < paths.length; i += batch) {
      final sub = paths.sublist(i, i + batch > paths.length ? paths.length : i + batch);
      // 将子批次再按并发度切分执行
      for (int j = 0; j < sub.length; j += maxConcurrent) {
        final chunk = sub.sublist(j, j + maxConcurrent > sub.length ? sub.length : j + maxConcurrent);
        await Future.wait(chunk.map((p) async {
          try {
            final f = File(p);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (e) {
            print('批量删除文件失败: $e, $p');
          }
        }));
      }
    }
  }

  /// 删除某个应用的所有截图记录（批量删除，高性能）
  Future<int> deleteAllScreenshotsForApp(String appPackageName) async {
    final db = await database; // 主库
    try {
      // 统计所有分库月表条数并逐表删除
      int total = 0;
      final years = await _listShardYearsForApp(appPackageName);
      for (final y in years) {
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        for (int m = 1; m <= 12; m++) {
          final t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final rows = await shardDb.rawQuery('SELECT COUNT(*) as c FROM $t');
            final c = (rows.first['c'] as int?) ?? 0;
            total += c;
            await shardDb.execute('DROP TABLE IF EXISTS $t');
          } catch (_) {}
        }
      }

      // 清除主库注册与聚合
      await db.delete('shard_registry', where: 'app_package_name = ?', whereArgs: [appPackageName]);
      await db.delete('app_registry', where: 'app_package_name = ?', whereArgs: [appPackageName]);
      await db.delete('app_stats', where: 'app_package_name = ?', whereArgs: [appPackageName]);

      print('已删除应用 $appPackageName 的 $total 条记录');
      return total;
    } catch (e) {
      print('批量删除应用截屏记录失败: $e');
      return 0;
    }
  }



  /// 按ID列表获取记录的简要信息（用于快速删除/保留算法）
  Future<List<Map<String, dynamic>>> getRecordsByIds(String packageName, List<int> ids) async {
    final db = await database;
    try {
      if (ids.isEmpty) return [];

      final tableName = _getAppTableName(packageName);
      if (!await _checkTableExists(db, tableName)) {
        return [];
      }

      final placeholders = List.filled(ids.length, '?').join(',');
      final rows = await db.query(
        tableName,
        columns: ['id', 'file_path', 'capture_time', 'file_size'],
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      return rows;
    } catch (e) {
      print('按ID获取记录失败: $e');
      return [];
    }
  }

  /// 删除除保留ID外的所有记录，并重算统计
  Future<int> deleteAllExcept(String packageName, List<int> keepIds) async {
    final db = await database; // 主库
    try {
      if (keepIds.isEmpty) {
        // 直接删除全部
        return await deleteAllScreenshotsForApp(packageName);
      }

      // 将保留集合按 (year,month) -> localIds 划分
      final Map<int, Set<int>> keepByYm = {};
      for (final gid in keepIds) {
        final d = _decodeGid(gid);
        if (d == null) continue;
        final key = d[0] * 100 + d[1];
        keepByYm.putIfAbsent(key, () => <int>{}).add(d[2]);
      }

      int deletedTotal = 0;
      final years = await _listShardYearsForApp(packageName);
      for (final y in years) {
        final shardDb = await _openShardDb(packageName, y);
        if (shardDb == null) continue;
        for (int m = 1; m <= 12; m++) {
          final t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          final key = y * 100 + m;
          final keepSet = keepByYm[key] ?? <int>{};
          try {
            if (keepSet.isEmpty) {
              // 全删该月表
              final rows = await shardDb.rawQuery('SELECT COUNT(*) as c FROM $t');
              final c = (rows.first['c'] as int?) ?? 0;
              await shardDb.execute('DROP TABLE IF EXISTS $t');
              deletedTotal += c;
            } else {
              final placeholders = List.filled(keepSet.length, '?').join(',');
              final count = await shardDb.rawDelete('DELETE FROM $t WHERE id NOT IN ($placeholders)', keepSet.toList());
              deletedTotal += count;
            }
          } catch (_) {}
        }
      }

      await _recomputeAppStatForPackage(db, packageName);
      return deletedTotal;
    } catch (e) {
      print('删除非保留记录失败: $e');
      return 0;
    }
  }

  /// 根据文件路径查找记录（用于检查重复）
  Future<ScreenshotRecord?> getScreenshotByPath(String filePath) async {
    final db = await database; // 主库
    try {
      // 从文件路径推断应用包名
      final packageName = _extractPackageNameFromPath(filePath);
      if (packageName == null) {
        print('无法从路径推断包名: $filePath');
        return null;
      }
      // 穷举该应用的所有分库月表进行查找（先按年份倒序、月份倒序）
      String appName = packageName;
      try {
        final info = await db.query('app_registry', columns: ['app_name'], where: 'app_package_name = ?', whereArgs: [packageName], limit: 1);
        if (info.isNotEmpty) appName = (info.first['app_name'] as String?) ?? packageName;
      } catch (_) {}

      final years = await _listShardYearsForApp(packageName);
      for (final y in years) {
        final shardDb = await _openShardDb(packageName, y);
        if (shardDb == null) continue;
        for (int m = 12; m >= 1; m--) {
          final t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final maps = await shardDb.query(
              t,
              columns: ['id','file_path','capture_time','file_size','page_url','ocr_text','is_deleted'],
              where: 'file_path = ?',
              whereArgs: [filePath],
              limit: 1,
            );
            if (maps.isNotEmpty) {
              final full = Map<String, dynamic>.from(maps.first);
              full['app_package_name'] = packageName;
              full['app_name'] = appName;
              full['id'] = _encodeGid(y, m, (maps.first['id'] as int?) ?? 0);
              return ScreenshotRecord.fromMap(full);
            }
          } catch (_) {}
        }
      }
      return null;
    } catch (e) {
      print('根据路径查询截屏记录失败: $e');
      return null;
    }
  }

  /// 更新截屏记录
  Future<bool> updateScreenshot(ScreenshotRecord record) async {
    final db = await database; // 主库
    try {
      final gid = record.id;
      if (gid == null) return false;
      final decoded = _decodeGid(gid);
      if (decoded == null) return false;
      final int year = decoded[0];
      final int month = decoded[1];
      final int localId = decoded[2];
      final shardDb = await _openShardDb(record.appPackageName, year);
      if (shardDb == null) return false;
      final tableName = _monthTableName(year, month);
      if (!await _tableExists(shardDb, tableName)) return false;
      final updateMap = {...record.toMap(), 'updated_at': DateTime.now().millisecondsSinceEpoch};
      updateMap.remove('app_package_name');
      updateMap.remove('app_name');
      final result = await shardDb.update(tableName, updateMap, where: 'id = ?', whereArgs: [localId]);
      return result > 0;
    } catch (e) {
      print('更新截屏记录失败: $e');
      return false;
    }
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
  Future<void> _upsertAppStatOnInsert(DatabaseExecutor db, String package, String appName, int fileSize, int captureTime) async {
    try {
      await db.execute('''
        INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time)
        VALUES (?, ?, 1, ?, ?)
        ON CONFLICT(app_package_name) DO UPDATE SET
          app_name=excluded.app_name,
          total_count=app_stats.total_count + 1,
          total_size=app_stats.total_size + excluded.total_size,
          last_capture_time=CASE WHEN app_stats.last_capture_time IS NULL OR excluded.last_capture_time > app_stats.last_capture_time THEN excluded.last_capture_time ELSE app_stats.last_capture_time END
      ''', [package, appName, fileSize, captureTime]);
    } catch (e) {
      // 如设备SQLite不支持UPSERT，退化为全量重算
      await _recomputeAppStatForPackage(db, package);
    }
  }

  Future<void> _recomputeAppStatForPackage(DatabaseExecutor db, String package) async {
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
            final rows = await shardDb.rawQuery('SELECT COUNT(*) as c, COALESCE(SUM(file_size),0) as s, COALESCE(MAX(capture_time),0) as t FROM $t');
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
        await master.delete('app_stats', where: 'app_package_name = ?', whereArgs: [package]);
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

  /// 导出数据库到公共下载目录（Download/ScreenMemory）
  /// 返回导出结果（包含 displayPath 等），失败返回 null
  Future<Map<String, dynamic>?> exportDatabaseToDownloads() async {
    try {
      // 将 external/output 整个目录打包为 zip
      final base = await PathService.getExternalFilesDir(null) ?? await _getExternalFilesDir(); 
      await FlutterLogger.nativeInfo('EXPORT', 'baseDir=' + (base?.path ?? 'null'));
      if (base == null) return null; 
      final outputDir = Directory(join(base.path, 'output')); 
      if (!await outputDir.exists()) { await FlutterLogger.nativeWarn('EXPORT', 'output not found: ' + outputDir.path); return null; }

      // 生成临时zip路径
      final tmpZip = File(join(base.path, 'output_export.zip'));
      try { if (await tmpZip.exists()) await tmpZip.delete(); } catch (_) {}

      // 使用 archive 库打包
      final archive = Archive();
      await for (final entity in outputDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relPath = entity.path.substring(outputDir.path.length + 1).replaceAll('\\\\', '/');
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
        }
      }
      final encoder = ZipEncoder();
      final zipData = encoder.encode(archive);
      if (zipData == null) return null;
      await tmpZip.writeAsBytes(zipData, flush: true); 
      await FlutterLogger.nativeInfo('EXPORT', 'zip bytes=' + zipData.length.toString() + ' path=' + tmpZip.path);

      // 通过原生保存到 Download/ScreenMemory
      final result = await _channel.invokeMethod('exportFileToDownloads', {
        'sourcePath': tmpZip.path,
        'displayName': 'output_export.zip',
        'subDir': 'ScreenMemory',
      });

      // 清理临时文件
      try { await tmpZip.delete(); } catch (_) {}

      if (result is Map) { 
        final map = Map<String, dynamic>.from(result); 
        map['humanPath'] = (map['absolutePath'] as String?) ?? (map['displayPath'] as String?); 
        await FlutterLogger.nativeInfo('EXPORT', 'saved to ' + (map['humanPath']?.toString() ?? ''));
        return map; 
      } 
      return null;
    } catch (e) {
      print('导出output压缩包失败: $e');
      return null;
    }
  }

  /// 从 ZIP 归档导入数据到应用的外部存储 "output" 目录。
  /// 导出的 ZIP 包含相对于 "output" 文件夹的路径。
  /// 这将安全地将条目解压到 `<externalFilesDir>/output` 并重置
  /// 打开的数据库句柄，以便后续查询在导入的数据上操作。
  ///
  /// 返回: 成功时返回 { 'extracted': int, 'targetDir': String }；失败时返回 null。
  Future<Map<String, dynamic>?> importDataFromZip({
    String? zipPath,
    List<int>? zipBytes,
    bool overwrite = true,
  }) async {
    try {
      await FlutterLogger.nativeInfo('IMPORT', 'begin');
      await FlutterLogger.nativeDebug('IMPORT', 'args path=' + (zipPath ?? '') + ' bytes=' + ((zipBytes?.length ?? 0).toString()));
      if ((zipPath == null || zipPath.isEmpty) && (zipBytes == null || zipBytes.isEmpty)) {
        await FlutterLogger.nativeWarn('IMPORT', 'no input');
        return null;
      }

      final base = await PathService.getExternalFilesDir(null) ?? await _getExternalFilesDir();
      if (base == null) return null;
      final outputDir = Directory(join(base.path, 'output'));
      await FlutterLogger.nativeInfo('IMPORT', 'baseDir=' + base.path);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
        await FlutterLogger.nativeInfo('IMPORT', 'created outputDir=' + outputDir.path);
      }

      // 读取字节数据
      // 在导入前关闭DB句柄以避免冲突
      try { await _resetDatabasesAfterImport(); } catch (_) {}
      final bytes = zipBytes ?? await File(zipPath!).readAsBytes();
      if (bytes.isEmpty) return null;

      // 解码 ZIP
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      int extracted = 0; 
      await FlutterLogger.nativeInfo('IMPORT', 'entries=' + archive.length.toString());
      for (final entry in archive) {
        final relative = normalize(entry.name).replaceAll('\\', '/');
        final String rel = relative.startsWith('output/') ? relative.substring('output/'.length) : relative;
        if (rel.startsWith('../') || rel.startsWith('/')) { 
          // 跳过可疑路径
          continue;
        }
        final destPath = join(outputDir.path, rel);
        if (entry.isFile) {
          final file = File(destPath);
          final parent = file.parent;
          if (!await parent.exists()) {
            await parent.create(recursive: true);
          }
          if (!overwrite && await file.exists()) {
            // 保持现有文件
          } else {
            await file.writeAsBytes(entry.content as List<int>, flush: true);
            extracted++;
          }
        } else {
          final dir = Directory(destPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        }
      }

      // 重置打开的数据库句柄
      try {
        await _resetDatabasesAfterImport();
      } catch (_) {}

      final _res = { 
        'extracted': extracted, 
        'targetDir': outputDir.path, 
      }; 
      await FlutterLogger.nativeInfo('IMPORT', '完成 解压=' + extracted.toString() + ' 目标=' + outputDir.path);
      return _res; 
    } catch (e) {
      print('导入 ZIP 失败: $e');
      return null;
    }
  }

  /// 流式ZIP导入以防止大型归档OOM。推荐使用此方法。
  Future<Map<String, dynamic>?> importDataFromZipStreaming({
    String? zipPath,
    List<int>? zipBytes,
    bool overwrite = true,
  }) async {
    try {
      await FlutterLogger.nativeInfo('IMPORT', '开始(流式)');
      await FlutterLogger.nativeDebug('IMPORT', 'args path=' + (zipPath ?? '') + ' bytes=' + ((zipBytes?.length ?? 0).toString()));
      if ((zipPath == null || zipPath.isEmpty) && (zipBytes == null || zipBytes.isEmpty)) {
        await FlutterLogger.nativeWarn('IMPORT', 'no input');
        return null;
      }

      final base = await PathService.getExternalFilesDir(null) ?? await _getExternalFilesDir();
      if (base == null) return null;
      final outputDir = Directory(join(base.path, 'output'));
      await FlutterLogger.nativeInfo('IMPORT', 'baseDir=' + base.path);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
        await FlutterLogger.nativeInfo('IMPORT', 'created outputDir=' + outputDir.path);
      }

      // 在导入前关闭DB句柄以避免冲突
      try { await _resetDatabasesAfterImport(); } catch (_) {}

      // 解析本地zip文件路径（如果只提供字节则写入临时文件）
      String localZipPath;
      File? tmpZipFile;
      if (zipPath != null && zipPath.isNotEmpty) {
        localZipPath = zipPath;
      } else {
        final tmpDir = await getTemporaryDirectory();
        tmpZipFile = File(join(tmpDir.path, 'screenmemo_import_tmp.zip'));
        try { if (await tmpZipFile.exists()) await tmpZipFile.delete(); } catch (_) {}
        await tmpZipFile.writeAsBytes(zipBytes!, flush: true);
        localZipPath = tmpZipFile.path;
      }

      final input = InputFileStream(localZipPath);
      final archive = ZipDecoder().decodeBuffer(input);
      await FlutterLogger.nativeInfo('IMPORT', 'entries=' + archive.length.toString());
      int extracted = 0;
      int logged = 0;
      for (final f in archive.files) {
        final relative = normalize(f.name).replaceAll('\\', '/');
        final String rel = relative.startsWith('output/') ? relative.substring('output/'.length) : relative;
        if (logged < 10) { await FlutterLogger.nativeDebug('IMPORT', '条目: ' + relative + ' -> ' + rel); logged++; }
        if (rel.startsWith('../') || rel.startsWith('/')) {
          continue;
        }
        final destPath = join(outputDir.path, rel);
        if (f.isFile) {
          final parent = File(destPath).parent;
          if (!await parent.exists()) {
            await parent.create(recursive: true);
          }
          if (!overwrite && await File(destPath).exists()) {
            // 保持现有文件
          } else {
            final out = OutputFileStream(destPath);
            f.writeContent(out);
            out.close();
            extracted++;
          }
        } else {
          final dir = Directory(destPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        }
      }

      // 清理临时文件
      try { if (tmpZipFile != null) await tmpZipFile.delete(); } catch (_) {}

      // 为了安全起见，再次重置DB句柄
      try { await _resetDatabasesAfterImport(); } catch (_) {}

      final res = {
        'extracted': extracted,
        'targetDir': outputDir.path,
      };
      await FlutterLogger.nativeInfo('IMPORT', '完成(流式) 解压=' + extracted.toString() + ' 目标=' + outputDir.path);
      return res;
    } catch (e) {
      await FlutterLogger.nativeError('IMPORT', '异常(流式): ' + e.toString());
      return null;
    }
  }

  Future<void> _resetDatabasesAfterImport() async {
    try {
      if (_shardDbCache.isNotEmpty) {
        for (final db in _shardDbCache.values) {
          try { await db.close(); } catch (_) {}
        }
        _shardDbCache.clear();
      }
      if (_database != null) {
        try { await _database!.close(); } catch (_) {}
        _database = null;
      }
    } catch (_) {}
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
        if (seg == 'output' && i + 2 < parts.length && parts[i + 1] == 'screen') {
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
      [tableName]
    );
    return result.isNotEmpty;
  }
  
  /// 确保应用表存在
  Future<void> _ensureAppTableExists(DatabaseExecutor db, String packageName, String appName) async {
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
    await db.execute('''
      INSERT OR REPLACE INTO app_registry (app_package_name, app_name, table_name)
      VALUES (?, ?, ?)
    ''', [packageName, appName, tableName]);
    
    print('已创建应用表: $tableName');
  }

  /// 幂等地为已有表添加 page_url 列（若已存在则忽略错误）
  Future<void> _ensurePageUrlColumnExists(DatabaseExecutor db, String tableName) async {
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_${tableName}_capture_time ON $tableName(capture_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_${tableName}_file_path ON $tableName(file_path)');
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

  /// 获取指定应用在给定时间戳范围内的截图数量（包含边界，毫秒）
  Future<int> getScreenshotCountByAppBetween(String appPackageName, {required int startMillis, required int endMillis}) async {
    final db = await database; // 主库
    try {
      if (endMillis < startMillis) return 0;
      int total = 0;
      final DateTime s = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final DateTime e = DateTime.fromMillisecondsSinceEpoch(endMillis);
      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return 0;
      final List<List<int>> ymList = _listYearMonthBetween(s, e);
      for (final ym in ymList) {
        final int y = ym[0];
        final int m = ym[1];
        if (!years.contains(y)) continue;
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        final String t = _monthTableName(y, m);
        if (!await _tableExists(shardDb, t)) continue;
        try {
          final rows = await shardDb.rawQuery(
            'SELECT COUNT(*) as c FROM $t WHERE capture_time >= ? AND capture_time <= ?',
            [startMillis, endMillis],
          );
          total += (rows.first['c'] as int?) ?? 0;
        } catch (_) {}
      }
      return total;
    } catch (e) {
      print('getScreenshotCountByAppBetween 失败: $e');
      return 0;
    }
  }

  /// 获取指定应用在给定时间戳范围内的截图列表（按时间倒序，支持分页 offset/limit）
  Future<List<ScreenshotRecord>> getScreenshotsByAppBetween(
    String appPackageName, {
    required int startMillis,
    required int endMillis,
    int? limit,
    int? offset,
  }) async {
    final db = await database; // 主库
    try {
      if (endMillis < startMillis) return <ScreenshotRecord>[];
      // 读取 app_name
      String appName = appPackageName;
      try {
        final appInfo = await db.query(
          'app_registry',
          columns: ['app_name'],
          where: 'app_package_name = ?',
          whereArgs: [appPackageName],
          limit: 1,
        );
        if (appInfo.isNotEmpty) {
          appName = (appInfo.first['app_name'] as String?) ?? appPackageName;
        }
      } catch (_) {}

      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return <ScreenshotRecord>[];
      final List<List<int>> ymList = _listYearMonthBetween(
        DateTime.fromMillisecondsSinceEpoch(startMillis),
        DateTime.fromMillisecondsSinceEpoch(endMillis),
      );

      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
      for (final ym in ymList) {
        final int y = ym[0];
        final int m = ym[1];
        if (!years.contains(y)) continue;
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        final String t = _monthTableName(y, m);
        if (!await _tableExists(shardDb, t)) continue;
        try {
          final maps = await shardDb.query(
            t,
            where: 'capture_time >= ? AND capture_time <= ?',
            whereArgs: [startMillis, endMillis],
            orderBy: 'capture_time DESC',
          );
          for (final map in maps) {
            final full = Map<String, dynamic>.from(map);
            full['app_package_name'] = appPackageName;
            full['app_name'] = appName;
            final localId = (map['id'] as int?) ?? 0;
            full['id'] = _encodeGid(y, m, localId);
            rows.add(full);
          }
        } catch (_) {}
      }

      rows.sort((a, b) {
        final int ta = (a['capture_time'] as int?) ?? 0;
        final int tb = (b['capture_time'] as int?) ?? 0;
        return tb.compareTo(ta);
      });

      int start = offset ?? 0;
      if (start < 0) start = 0;
      int end = limit != null ? (start + limit) : rows.length;
      if (start > rows.length) return <ScreenshotRecord>[];
      if (end > rows.length) end = rows.length;
      final slice = rows.sublist(start, end);
      return slice.map((m) => ScreenshotRecord.fromMap(m)).toList();
    } catch (e) {
      print('getScreenshotsByAppBetween 查询失败: $e');
      return <ScreenshotRecord>[];
    }
  }

  /// 全局按 OCR 文本搜索（跨应用、跨年份分库，按时间倒序，支持分页）
  Future<List<ScreenshotRecord>> searchScreenshotsByOcr(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim();
      if (q.isEmpty) return <ScreenshotRecord>[];

      // 预读 app 名称，减少重复查询
      final Map<String, String> appNameCache = <String, String>{};
      try {
        final reg = await db.query('app_registry', columns: ['app_package_name', 'app_name']);
        for (final r in reg) {
          final pkg = r['app_package_name'] as String;
          final name = (r['app_name'] as String?) ?? pkg;
          appNameCache[pkg] = name;
        }
      } catch (_) {}

      // 请求规模估算
      final int requested = ((offset ?? 0) + (limit ?? 100));
      final int target = (requested <= 0 ? 400 : requested * 4);
      final int perTableLimit = (() {
        final int base = requested <= 0 ? 400 : requested * 2;
        if (base < 200) return 200;
        if (base > 5000) return 5000;
        return base;
      })();

      final String lowerQuery = '%${q.toLowerCase()}%';
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];

      // 遍历所有已注册的 (package, year)
      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );

      outer:
      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        final String appName = appNameCache[pkg] ?? pkg;
        for (int m = 12; m >= 1; m--) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final maps = await shardDb.query(
              t,
              where: "is_deleted = 0 AND ocr_text IS NOT NULL AND LENGTH(ocr_text) > 0 AND LOWER(ocr_text) LIKE ?",
              whereArgs: [lowerQuery],
              orderBy: 'capture_time DESC',
              limit: perTableLimit,
            );
            for (final mapp in maps) {
              final full = Map<String, dynamic>.from(mapp);
              full['app_package_name'] = pkg;
              full['app_name'] = appName;
              final localId = (mapp['id'] as int?) ?? 0;
              full['id'] = _encodeGid(y, m, localId);
              rows.add(full);
              if (rows.length >= target) break outer;
            }
          } catch (_) {}
        }
      }

      // 全局排序
      rows.sort((a, b) {
        final int ta = (a['capture_time'] as int?) ?? 0;
        final int tb = (b['capture_time'] as int?) ?? 0;
        return tb.compareTo(ta);
      });

      // 分页
      int start = offset ?? 0;
      if (start < 0) start = 0;
      int end = limit != null ? (start + limit) : rows.length;
      if (start > rows.length) return <ScreenshotRecord>[];
      if (end > rows.length) end = rows.length;
      final slice = rows.sublist(start, end);
      return slice.map((m) => ScreenshotRecord.fromMap(m)).toList();
    } catch (e) {
      print('searchScreenshotsByOcr 失败: $e');
      return <ScreenshotRecord>[];
    }
  }

  /// 按应用按 OCR 文本搜索（限定包名，按时间倒序，支持分页）
  Future<List<ScreenshotRecord>> searchScreenshotsByOcrForApp(
    String appPackageName,
    String query, {
    int? limit,
    int? offset,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim();
      if (q.isEmpty) return <ScreenshotRecord>[];

      // 读取 app_name
      String appName = appPackageName;
      try {
        final r = await db.query(
          'app_registry',
          columns: ['app_name'],
          where: 'app_package_name = ?',
          whereArgs: [appPackageName],
          limit: 1,
        );
        if (r.isNotEmpty) appName = (r.first['app_name'] as String?) ?? appPackageName;
      } catch (_) {}

      final int requested = ((offset ?? 0) + (limit ?? 100));
      final int target = (requested <= 0 ? 400 : requested * 4);
      final int perTableLimit = (() {
        final int base = requested <= 0 ? 400 : requested * 2;
        if (base < 200) return 200;
        if (base > 5000) return 5000;
        return base;
      })();

      final String lowerQuery = '%${q.toLowerCase()}%';
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];

      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return <ScreenshotRecord>[];
      outer:
      for (final y in years) {
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        for (int m = 12; m >= 1; m--) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final maps = await shardDb.query(
              t,
              where: "is_deleted = 0 AND ocr_text IS NOT NULL AND LENGTH(ocr_text) > 0 AND LOWER(ocr_text) LIKE ?",
              whereArgs: [lowerQuery],
              orderBy: 'capture_time DESC',
              limit: perTableLimit,
            );
            for (final mapp in maps) {
              final full = Map<String, dynamic>.from(mapp);
              full['app_package_name'] = appPackageName;
              full['app_name'] = appName;
              final localId = (mapp['id'] as int?) ?? 0;
              full['id'] = _encodeGid(y, m, localId);
              rows.add(full);
              if (rows.length >= target) break outer;
            }
          } catch (_) {}
        }
      }

      rows.sort((a, b) {
        final int ta = (a['capture_time'] as int?) ?? 0;
        final int tb = (b['capture_time'] as int?) ?? 0;
        return tb.compareTo(ta);
      });

      int start = offset ?? 0;
      if (start < 0) start = 0;
      int end = limit != null ? (start + limit) : rows.length;
      if (start > rows.length) return <ScreenshotRecord>[];
      if (end > rows.length) end = rows.length;
      final slice = rows.sublist(start, end);
      return slice.map((m) => ScreenshotRecord.fromMap(m)).toList();
    } catch (e) {
      print('searchScreenshotsByOcrForApp 失败: $e');
      return <ScreenshotRecord>[];
    }
  }

  // ===================== AI 配置与会话 便捷方法 =====================
  Future<String?> getAiSetting(String key) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ai_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setAiSetting(String key, String? value) async {
    final db = await database;
    if (value == null) {
      try { await db.delete('ai_settings', where: 'key = ?', whereArgs: [key]); } catch (_) {}
      return;
    }
    try {
      await db.execute(
        'INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)',
        [key, value],
      );
    } catch (_) {
      try {
        final count = await db.update('ai_settings', {'value': value}, where: 'key = ?', whereArgs: [key]);
        if (count == 0) {
          await db.insert('ai_settings', {'key': key, 'value': value});
        }
      } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> getAiMessages(String conversationId, {int? limit, int? offset}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ai_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'id ASC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> appendAiMessage(String conversationId, String role, String content, {int? createdAt}) async {
    try {
      final db = await database;
      await db.insert('ai_messages', {
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        if (createdAt != null) 'created_at': createdAt,
      });
    } catch (_) {}
  }

  Future<void> clearAiConversation(String conversationId) async {
    try {
      final db = await database;
      await db.delete('ai_messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
    } catch (_) {}
  }
}

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import '../models/screenshot_record.dart';
import 'startup_profiler.dart';

/// 截屏数据库服务
class ScreenshotDatabase {
  static ScreenshotDatabase? _instance;
  static Database? _database;
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  static ScreenshotDatabase get instance => _instance ??= ScreenshotDatabase._();

  ScreenshotDatabase._();

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
      final externalDir = await _getExternalFilesDir();
      if (externalDir != null) {
        // 创建 output/databases 目录
        final databasesDir = Directory(join(externalDir.path, 'output', 'databases'));
        if (!await databasesDir.exists()) {
          await databasesDir.create(recursive: true);
          print('数据库目录已创建: ${databasesDir.path}');
        }
        
        final path = join(databasesDir.path, 'screenshot_memo.db');
        print('数据库路径: $path');
        
        final db = await openDatabase(
          path,
          version: 2,
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
        
        final db = await openDatabase(
          path,
          version: 2,
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
        version: 2,
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

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE screenshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_package_name TEXT NOT NULL,
        app_name TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        capture_time INTEGER NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
      )
    ''');

    // 创建索引以提高查询性能
    await db.execute('CREATE INDEX idx_app_package_name ON screenshots(app_package_name)');
    await db.execute('CREATE INDEX idx_capture_time ON screenshots(capture_time)');
    await db.execute('CREATE INDEX idx_is_deleted ON screenshots(is_deleted)');

    // 聚合统计表（每个应用一行，避免首页实时 SUM/COUNT）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_stats (
        app_package_name TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        total_size INTEGER NOT NULL DEFAULT 0,
        last_capture_time INTEGER
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_stats_last ON app_stats(last_capture_time)');
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('数据库从版本 $oldVersion 升级到 $newVersion');
    if (oldVersion < 2) {
      // 新增 app_stats 表并用历史数据回填
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_stats (
          app_package_name TEXT PRIMARY KEY,
          app_name TEXT NOT NULL,
          total_count INTEGER NOT NULL DEFAULT 0,
          total_size INTEGER NOT NULL DEFAULT 0,
          last_capture_time INTEGER
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_app_stats_last ON app_stats(last_capture_time)');
      await db.execute('DELETE FROM app_stats');
      await db.execute('''
        INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time)
        SELECT app_package_name, app_name, COUNT(*), COALESCE(SUM(file_size),0), MAX(capture_time)
        FROM screenshots
        GROUP BY app_package_name, app_name
      ''');
    }
  }

  /// 检查文件路径是否已存在于数据库中
  Future<bool> isFilePathExists(String filePath) async {
    final db = await database;
    try {
      final result = await db.query(
        'screenshots',
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
    final db = await database;
    try {
      // 先检查记录是否已存在
      final exists = await isFilePathExists(record.filePath);
      if (exists) {
        print('截屏记录已存在，跳过插入: ${record.appName} - ${record.filePath}');
        return null;
      }

      // 检查文件是否存在
      final file = File(record.filePath);
      final actualFileSize = await file.exists() ? await file.length() : 0;

      final recordWithSize = record.copyWith(fileSize: actualFileSize);
      final id = await db.insert('screenshots', recordWithSize.toMap());
      // 增量维护聚合表
      await _upsertAppStatOnInsert(
        db,
        recordWithSize.appPackageName,
        recordWithSize.appName,
        actualFileSize,
        recordWithSize.captureTime.millisecondsSinceEpoch,
      );
      print('截屏记录已插入数据库: ${record.appName} - ${record.filePath}');
      return id;
    } catch (e) {
      print('插入截屏记录失败: $e');
      rethrow;
    }
  }

  /// 插入截屏记录（保留原方法以兼容性）
  Future<int> insertScreenshot(ScreenshotRecord record) async {
    final db = await database;
    try {
      // 检查文件是否存在
      final file = File(record.filePath);
      final actualFileSize = await file.exists() ? await file.length() : 0;

      final recordWithSize = record.copyWith(fileSize: actualFileSize);
      final id = await db.insert('screenshots', recordWithSize.toMap());
      await _upsertAppStatOnInsert(
        db,
        recordWithSize.appPackageName,
        recordWithSize.appName,
        actualFileSize,
        recordWithSize.captureTime.millisecondsSinceEpoch,
      );
      print('截屏记录已插入数据库: ${record.appName} - ${record.filePath}');
      return id;
    } catch (e) {
      print('插入截屏记录失败: $e');
      rethrow;
    }
  }

  /// 根据应用包名获取截屏记录列表
  Future<List<ScreenshotRecord>> getScreenshotsByApp(String appPackageName, {int? limit}) async {
    final db = await database;
    try {
      final maps = await db.query(
        'screenshots',
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
        orderBy: 'capture_time DESC',
        limit: limit,
      );

      return maps.map((map) => ScreenshotRecord.fromMap(map)).toList();
    } catch (e) {
      print('查询截屏记录失败: $e');
      return [];
    }
  }

  /// 获取所有应用的截屏统计
  Future<Map<String, Map<String, dynamic>>> getScreenshotStatistics() async {
    StartupProfiler.begin('ScreenshotDatabase.getScreenshotStatistics');
    final db = await database;
    try {
      // 优先读取聚合表，避免每次实时聚合
      final maps = await db.rawQuery('''
        SELECT app_package_name, app_name, total_count, last_capture_time, total_size
        FROM app_stats
        ORDER BY last_capture_time DESC
      ''');

      final statistics = <String, Map<String, dynamic>>{};
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
      // 兼容回退：如聚合表不存在则走旧逻辑
      try {
        final fallback = await db.rawQuery('''
          SELECT
            app_package_name,
            app_name,
            COUNT(*) as total_count,
            MAX(capture_time) as last_capture_time,
            SUM(file_size) as total_size
          FROM screenshots
          GROUP BY app_package_name, app_name
          ORDER BY last_capture_time DESC
        ''');
        final statistics = <String, Map<String, dynamic>>{};
        for (final map in fallback) {
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
      } catch (_) {
        return {};
      }
    }
    finally {
      StartupProfiler.end('ScreenshotDatabase.getScreenshotStatistics');
    }
  }

  /// 获取今日截屏数量
  Future<int> getTodayScreenshotCount() async {
    StartupProfiler.begin('ScreenshotDatabase.getTodayScreenshotCount');
    final db = await database;
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59).millisecondsSinceEpoch;

      final result = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM screenshots
        WHERE capture_time >= ? AND capture_time <= ?
      ''', [startOfDay, endOfDay]);

      return result.first['count'] as int;
    } catch (e) {
      print('获取今日截屏数量失败: $e');
      return 0;
    }
    finally {
      StartupProfiler.end('ScreenshotDatabase.getTodayScreenshotCount');
    }
  }

  /// 获取总截屏数量
  Future<int> getTotalScreenshotCount() async {
    StartupProfiler.begin('ScreenshotDatabase.getTotalScreenshotCount');
    final db = await database;
    try {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM screenshots');
      return result.first['count'] as int;
    } catch (e) {
      print('获取总截屏数量失败: $e');
      return 0;
    }
    finally {
      StartupProfiler.end('ScreenshotDatabase.getTotalScreenshotCount');
    }
  }

  /// 硬删除截屏记录（同时删除数据库记录和文件）
  Future<bool> deleteScreenshot(int id) async {
    final db = await database;
    try {
      // 首先获取文件路径
      final maps = await db.query(
        'screenshots',
        columns: ['file_path', 'app_package_name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        print('未找到ID为$id的截屏记录');
        return false;
      }

      final filePath = maps.first['file_path'] as String;
      final packageName = maps.first['app_package_name'] as String;

      // 删除数据库记录
      final result = await db.delete(
        'screenshots',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (result > 0) {
        // 数据库删除成功，尝试删除物理文件
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            print('成功删除文件: $filePath');
          } else {
            print('文件不存在，跳过删除: $filePath');
          }
        } catch (fileError) {
          // 文件删除失败不影响数据库删除的成功状态
          print('删除文件失败，但数据库记录已删除: $fileError');
        }
        // 重新计算该应用的聚合统计
        await _recomputeAppStatForPackage(db, packageName);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('删除截屏记录失败: $e');
      return false;
    }
  }



  /// 根据文件路径查找记录（用于检查重复）
  Future<ScreenshotRecord?> getScreenshotByPath(String filePath) async {
    final db = await database;
    try {
      final maps = await db.query(
        'screenshots',
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return ScreenshotRecord.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print('根据路径查询截屏记录失败: $e');
      return null;
    }
  }

  /// 更新截屏记录
  Future<bool> updateScreenshot(ScreenshotRecord record) async {
    final db = await database;
    try {
      final result = await db.update(
        'screenshots',
        {...record.toMap(), 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [record.id],
      );
      
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
  Future<void> _upsertAppStatOnInsert(Database db, String package, String appName, int fileSize, int captureTime) async {
    try {
      await db.execute('''
        INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time)
        VALUES (?, ?, 1, ?, ?)
        ON CONFLICT(app_package_name) DO UPDATE SET
          app_name=excluded.app_name,
          total_count=app_stats.total_count + 1,
          total_size=app_stats.total_size + excluded.total_size,
          last_capture_time=CASE WHEN excluded.last_capture_time > app_stats.last_capture_time THEN excluded.last_capture_time ELSE app_stats.last_capture_time END
      ''', [package, appName, fileSize, captureTime]);
    } catch (e) {
      // 如设备SQLite不支持UPSERT，退化为全量重算
      await _recomputeAppStatForPackage(db, package);
    }
  }

  Future<void> _recomputeAppStatForPackage(Database db, String package) async {
    try {
      final rows = await db.rawQuery(
        'SELECT app_package_name, MAX(app_name) as app_name, COUNT(*) as c, COALESCE(SUM(file_size),0) as s, MAX(capture_time) as t FROM screenshots WHERE app_package_name = ? GROUP BY app_package_name',
        [package],
      );
      if (rows.isEmpty) {
        await db.delete('app_stats', where: 'app_package_name = ?', whereArgs: [package]);
        return;
      }
      final r = rows.first;
      await db.execute(
        '''INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(app_package_name) DO UPDATE SET app_name=excluded.app_name, total_count=excluded.total_count, total_size=excluded.total_size, last_capture_time=excluded.last_capture_time''',
        [
          r['app_package_name'],
          r['app_name'],
          r['c'],
          r['s'],
          r['t'],
        ],
      );
    } catch (e) {
      // 忽略
    }
  }

  /// 导出数据库到公共下载目录（Download/ScreenMemory）
  /// 返回导出结果（包含 displayPath 等），失败返回 null
  Future<Map<String, dynamic>?> exportDatabaseToDownloads() async {
    try {
      // 确保数据库已创建，并获得路径
      final db = await database;
      final dbPath = db.path;

      // 临时关闭以避免正在写入时复制
      await db.close();
      _database = null;

      // 通过原生侧写入到下载目录（兼容 Android 10+/Scoped Storage）
      final result = await _channel.invokeMethod('exportFileToDownloads', {
        'sourcePath': dbPath,
        'displayName': 'screenshot_memo.db',
        'subDir': 'ScreenMemory',
      });

      // 复制完成后重新打开数据库
      await database;

      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        // 统一补充一个humanPath用于展示：优先absolutePath
        map['humanPath'] = (map['absolutePath'] as String?) ?? (map['displayPath'] as String?);
        return map;
      }
      return null;
    } catch (e) {
      // 尝试在失败情况下也确保数据库被重新打开
      try { await database; } catch (_) {}
      print('导出数据库到下载目录失败: $e');
      return null;
    }
  }
}
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/screenshot_record.dart';

/// 截屏数据库服务
class ScreenshotDatabase {
  static ScreenshotDatabase? _instance;
  static Database? _database;

  static ScreenshotDatabase get instance => _instance ??= ScreenshotDatabase._();

  ScreenshotDatabase._();

  /// 获取数据库实例
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'screenshot_memo.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
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
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来版本升级时的处理逻辑
    print('数据库从版本 $oldVersion 升级到 $newVersion');
  }

  /// 插入截屏记录
  Future<int> insertScreenshot(ScreenshotRecord record) async {
    final db = await database;
    try {
      // 检查文件是否存在
      final file = File(record.filePath);
      final actualFileSize = await file.exists() ? await file.length() : 0;
      
      final recordWithSize = record.copyWith(fileSize: actualFileSize);
      final id = await db.insert('screenshots', recordWithSize.toMap());
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
    final db = await database;
    try {
      final maps = await db.rawQuery('''
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
      return {};
    }
  }

  /// 获取今日截屏数量
  Future<int> getTodayScreenshotCount() async {
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
  }

  /// 获取总截屏数量
  Future<int> getTotalScreenshotCount() async {
    final db = await database;
    try {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM screenshots');
      return result.first['count'] as int;
    } catch (e) {
      print('获取总截屏数量失败: $e');
      return 0;
    }
  }

  /// 硬删除截屏记录（同时删除数据库记录和文件）
  Future<bool> deleteScreenshot(int id) async {
    final db = await database;
    try {
      // 首先获取文件路径
      final maps = await db.query(
        'screenshots',
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        print('未找到ID为$id的截屏记录');
        return false;
      }

      final filePath = maps.first['file_path'] as String;

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
}
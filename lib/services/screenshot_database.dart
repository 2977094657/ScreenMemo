import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import '../models/screenshot_record.dart';
import 'startup_profiler.dart';
import 'flutter_logger.dart';

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
          version: 1,
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
          version: 1,
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
        last_capture_time INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_app_stats_last ON app_stats(last_capture_time)');
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('数据库从版本 $oldVersion 升级到 $newVersion');
    // 不需要处理升级逻辑
  }

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
    final db = await database;
    try {
      // 先检查记录是否已存在
      final exists = await isFilePathExists(record.filePath);
      if (exists) {
        print('截屏记录已存在，跳过插入: ${record.appName} - ${record.filePath}');
        return null;
      }

      // 确保应用表存在
      await _ensureAppTableExists(db, record.appPackageName, record.appName);
      
      final tableName = _getAppTableName(record.appPackageName);

      // 检查文件是否存在
      final file = File(record.filePath);
      final actualFileSize = await file.exists() ? await file.length() : 0;

      final recordWithSize = record.copyWith(fileSize: actualFileSize);
      
      // 准备插入数据（去掉app相关字段，因为分表不需要）
      final insertMap = {...recordWithSize.toMap()};
      insertMap.remove('app_package_name');
      insertMap.remove('app_name');
      
      final id = await db.insert(tableName, insertMap);
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
      // 确保应用表存在
      await _ensureAppTableExists(db, record.appPackageName, record.appName);
      
      final tableName = _getAppTableName(record.appPackageName);
      
      // 检查文件是否存在
      final file = File(record.filePath);
      final actualFileSize = await file.exists() ? await file.length() : 0;

      final recordWithSize = record.copyWith(fileSize: actualFileSize);
      
      // 准备插入数据（去掉app相关字段，因为分表不需要）
      final insertMap = {...recordWithSize.toMap()};
      insertMap.remove('app_package_name');
      insertMap.remove('app_name');
      
      final id = await db.insert(tableName, insertMap);
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

  /// 批量插入（去重）：输入为记录列表，返回成功插入的数量
  Future<int> insertScreenshotsIfNotExistsBatch(List<ScreenshotRecord> records) async {
    if (records.isEmpty) return 0;
    final db = await database;
    int inserted = 0;
    try {
      await db.transaction((txn) async {
        for (final record in records) {
          // 逐项去重插入，避免UNIQUE冲突中断事务
          final exists = await isFilePathExists(record.filePath, exec: txn);
          if (exists) continue;
          await _ensureAppTableExists(txn, record.appPackageName, record.appName);
          final tableName = _getAppTableName(record.appPackageName);
          final file = File(record.filePath);
          final actualFileSize = await file.exists() ? await file.length() : 0;
          final recordWithSize = record.copyWith(fileSize: actualFileSize);
          final insertMap = {...recordWithSize.toMap()};
          insertMap.remove('app_package_name');
          insertMap.remove('app_name');
          await txn.insert(tableName, insertMap);
          await _upsertAppStatOnInsert(
            txn,
            recordWithSize.appPackageName,
            recordWithSize.appName,
            actualFileSize,
            recordWithSize.captureTime.millisecondsSinceEpoch,
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
    final db = await database;
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

          // 确保表存在（用第一条的 appName 进行注册）
          final String appName = list.first.appName;
          await _ensureAppTableExists(txn, packageName, appName);
          final String tableName = _getAppTableName(packageName);

          // 统计插入前数量，用于估算本次新增条数
          int beforeCount = 0;
          try {
            final rows = await txn.rawQuery('SELECT COUNT(*) as c FROM $tableName');
            beforeCount = (rows.first['c'] as int?) ?? 0;
          } catch (_) {}

          final batch = txn.batch();
          for (final r in list) {
            // 直接信任传入的 fileSize 以减少磁盘 stat；为空则回退为0
            final map = {...r.toMap()};
            map.remove('app_package_name');
            map.remove('app_name');
            batch.insert(
              tableName,
              map,
              conflictAlgorithm: ConflictAlgorithm.ignore, // 去重依赖 file_path UNIQUE
            );
          }
          // 提升性能：无需逐条返回 id
          await batch.commit(noResult: true, continueOnError: true);

          // 统计插入后数量
          int afterCount = beforeCount;
          try {
            final rows = await txn.rawQuery('SELECT COUNT(*) as c FROM $tableName');
            afterCount = (rows.first['c'] as int?) ?? beforeCount;
          } catch (_) {}
          final inserted = (afterCount - beforeCount).clamp(0, list.length);
          totalInserted += inserted;

          // 统一重算聚合（单次 O(1) 聚合查询），避免逐条 upsert 开销
          await _recomputeAppStatForPackage(txn, packageName);
        }
      });
    } catch (e) {
      print('快速批量插入失败: $e');
    }
    return totalInserted;
  }

  /// 根据应用包名获取截屏记录列表（支持分页）
  Future<List<ScreenshotRecord>> getScreenshotsByApp(String appPackageName, {int? limit, int? offset}) async {
    final db = await database;
    try {
      final tableName = _getAppTableName(appPackageName);
      
      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        return [];
      }
      
      final maps = await db.query(
        tableName,
        orderBy: 'capture_time DESC',
        limit: limit,
        offset: offset,
      );

      // 需要从 app_registry 获取 app_name
      String? appName;
      final appInfo = await db.query(
        'app_registry',
        columns: ['app_name'],
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
        limit: 1,
      );
      if (appInfo.isNotEmpty) {
        appName = appInfo.first['app_name'] as String;
      } else {
        appName = appPackageName; // 后备方案
      }
      
      // 重新添加 app 相关字段
      return maps.map((map) {
        final fullMap = Map<String, dynamic>.from(map);
        fullMap['app_package_name'] = appPackageName;
        fullMap['app_name'] = appName;
        return ScreenshotRecord.fromMap(fullMap);
      }).toList();
    } catch (e) {
      print('查询截屏记录失败: $e');
      return [];
    }
  }

  /// 获取指定应用的截屏总数量
  Future<int> getScreenshotCountByApp(String appPackageName) async {
    final db = await database;
    try {
      final tableName = _getAppTableName(appPackageName);
      
      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        return 0;
      }
      
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName',
      );
      return (result.first['count'] as int?) ?? 0;
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
    final db = await database;
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59).millisecondsSinceEpoch;

      // 获取所有应用表
      final appTables = await _getAllAppTables(db);
      int totalCount = 0;
      
      for (final table in appTables) {
        final tableName = table['table_name'] as String;
        try {
          final result = await db.rawQuery('''
            SELECT COUNT(*) as count
            FROM $tableName
            WHERE capture_time >= ? AND capture_time <= ?
          ''', [startOfDay, endOfDay]);
          
          totalCount += (result.first['count'] as int?) ?? 0;
        } catch (e) {
          print('查询表 $tableName 今日截屏数量失败: $e');
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

  /// 获取总截屏数量
  Future<int> getTotalScreenshotCount() async {
    StartupProfiler.begin('ScreenshotDatabase.getTotalScreenshotCount');
    final db = await database;
    try {
      // 直接从app_stats表获取总数，更高效
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
    final db = await database;
    try {
      // 在DB层记录删除开始
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('DB', 'deleteScreenshot start id='+id.toString()+', package='+packageName);
      // 构建应用特定的表名
      final tableName = _getAppTableName(packageName);
      
      // 首先查询记录是否存在，获取文件路径
      final maps = await db.query(
        tableName,
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        print('未找到ID为$id的截屏记录在应用$packageName的表中');
        // ignore: unawaited_futures
        FlutterLogger.nativeWarn('DB', 'deleteScreenshot not found id='+id.toString()+', package='+packageName);
        return false;
      }

      final filePath = maps.first['file_path'] as String;

      // 删除数据库记录
      final result = await db.delete(
        tableName,
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
            // ignore: unawaited_futures
            FlutterLogger.nativeInfo('FS', 'deleted file: '+filePath);
          } else {
            print('文件不存在，跳过删除: $filePath');
            // ignore: unawaited_futures
            FlutterLogger.nativeWarn('FS', 'file not exists, skip delete: '+filePath);
          }
        } catch (fileError) {
          // 文件删除失败不影响数据库删除的成功状态
          print('删除文件失败，但数据库记录已删除: $fileError');
          // ignore: unawaited_futures
          FlutterLogger.nativeError('FS', 'delete file failed but DB removed: '+fileError.toString());
        }
        // 重新计算该应用的聚合统计
        await _recomputeAppStatForPackage(db, packageName);
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('DB', 'recompute stats after delete id='+id.toString());
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('删除截屏记录失败: $e');
      // ignore: unawaited_futures
      FlutterLogger.nativeError('DB', 'deleteScreenshot exception: '+e.toString());
      return false;
    }
  }

  /// 批量删除指定ID的截屏记录（高效，带增量统计更新与并发文件删除）
  /// 返回实际删除的数据库记录数
  Future<int> deleteScreenshotsByIds(String packageName, List<int> ids) async {
    final db = await database;
    try {
      if (ids.isEmpty) return 0;

      final tableName = _getAppTableName(packageName);
      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        return 0;
      }

      final totalSw = Stopwatch()..start();
      final swQuery = Stopwatch()..start();
      // 先查询待删记录的文件信息与统计信息（一次性取出，避免删除后丢失）
      final records = await getRecordsByIds(packageName, ids);
      swQuery.stop();
      // 同时写入到原生日志，便于你在 screen_memo_debug.log 看到
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('DB', '批量删除-查询耗时 ${swQuery.elapsedMilliseconds}ms，待删ID数=${ids.length}，命中记录数=${records.length}');
      if (records.isEmpty) {
        return 0;
      }

      // 预计算删除集合的统计
      final int deletedSizeSum = records.fold<int>(0, (sum, r) => sum + ((r['file_size'] as int?) ?? 0));
      final int maxDeletedCapture = records.fold<int>(0, (max, r) {
        final t = (r['capture_time'] as int?) ?? 0;
        return t > max ? t : max;
      });

      int deletedTotal = 0;

      bool needsRecomputeFallback = false;
      final swTxn = Stopwatch()..start();
      await db.transaction((txn) async {
        // 1) 分片删除（规避SQLite参数上限999）
        const int chunk = 900;
        final swChunks = <int>[];
        for (int i = 0; i < ids.length; i += chunk) {
          final sub = ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk);
          if (sub.isEmpty) continue;
          final ph = List.filled(sub.length, '?').join(',');
          final sw = Stopwatch()..start();
          final count = await txn.rawDelete('DELETE FROM $tableName WHERE id IN ($ph)', sub);
          sw.stop();
          swChunks.add(sw.elapsedMilliseconds);
          deletedTotal += count;
        }
        if (swChunks.isNotEmpty) {
          final sum = swChunks.reduce((a, b) => a + b);
          final max = swChunks.reduce((a, b) => a > b ? a : b);
          final avg = sum / swChunks.length;
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo('DB', '批量删除-分片=${swChunks.length}，平均每片=${avg.toStringAsFixed(1)}ms，最大=${max}ms');
        }

        // 2) 增量更新聚合统计
        // 读取当前 app_stats
        int currentCount = 0;
        int currentSize = 0;
        int currentLast = 0;
        try {
          final stats = await txn.query(
            'app_stats',
            columns: ['total_count', 'total_size', 'last_capture_time'],
            where: 'app_package_name = ?',
            whereArgs: [packageName],
            limit: 1,
          );
          if (stats.isNotEmpty) {
            currentCount = (stats.first['total_count'] as int?) ?? 0;
            currentSize = (stats.first['total_size'] as int?) ?? 0;
            currentLast = (stats.first['last_capture_time'] as int?) ?? 0;
          }
        } catch (_) {}

        final int newCount = currentCount - deletedTotal <= 0 ? 0 : (currentCount - deletedTotal);
        final int newSize = currentSize - deletedSizeSum <= 0 ? 0 : (currentSize - deletedSizeSum);

        if (newCount == 0) {
          // 所有记录被删空，直接移除统计
          await txn.delete('app_stats', where: 'app_package_name = ?', whereArgs: [packageName]);
        } else {
          // 需要判断是否需要重算最大时间
          int newLast = currentLast;
          if (maxDeletedCapture >= currentLast) {
            try {
              final swMax = Stopwatch()..start();
              final rows = await txn.rawQuery('SELECT MAX(capture_time) as t FROM $tableName');
              swMax.stop();
              // ignore: unawaited_futures
              FlutterLogger.nativeInfo('DB', '重算最大时间(capture_time)耗时 ${swMax.elapsedMilliseconds}ms');
              newLast = (rows.first['t'] as int?) ?? 0;
            } catch (_) {
              newLast = 0;
            }
          }

          // 写回统计（使用UPSERT保障存在即更新）
          try {
            // 从注册表取 app_name（避免丢失）
            String appName = packageName;
            try {
              final appInfo = await txn.query(
                'app_registry',
                columns: ['app_name'],
                where: 'app_package_name = ?',
                whereArgs: [packageName],
                limit: 1,
              );
              if (appInfo.isNotEmpty) {
                appName = (appInfo.first['app_name'] as String?) ?? packageName;
              }
            } catch (_) {}

            final swUpsert = Stopwatch()..start();
            await txn.execute(
              '''
              INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time)
              VALUES (?, ?, ?, ?, ?)
              ON CONFLICT(app_package_name) DO UPDATE SET
                app_name=excluded.app_name,
                total_count=excluded.total_count,
                total_size=excluded.total_size,
                last_capture_time=excluded.last_capture_time
              ''',
              [packageName, appName, newCount, newSize, newLast],
            );
            swUpsert.stop();
            // ignore: unawaited_futures
            FlutterLogger.nativeInfo('DB', '更新统计表(app_stats)耗时 ${swUpsert.elapsedMilliseconds}ms');
          } catch (_) {
            // 失败则退化为全量重算，确保一致性（事务结束后再执行）
            needsRecomputeFallback = true;
          }
        }
      });
      swTxn.stop();
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('DB', '事务总耗时 ${swTxn.elapsedMilliseconds}ms');

      if (needsRecomputeFallback) {
        final swRe = Stopwatch()..start();
        await _recomputeAppStatForPackage(db, packageName);
        swRe.stop();
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('DB', 'fallback recompute took ${swRe.elapsedMilliseconds}ms');
      }

      // 3) 事务外并发删除文件，避免长事务
      final List<String> paths = records
          .map((r) => (r['file_path'] as String?))
          .whereType<String>()
          .toList(growable: false);

      final swFs = Stopwatch()..start();
      await _deleteFilesConcurrently(paths, maxConcurrent: 6);
      swFs.stop();
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('FS', '并发删除文件耗时 ${swFs.elapsedMilliseconds}ms，文件数=${paths.length}');

      totalSw.stop();
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('TOTAL', '批量删除总耗时 ${totalSw.elapsedMilliseconds}ms');
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
    final db = await database;
    try {
      final tableName = _getAppTableName(appPackageName);
      
      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        return 0;
      }
      
      // 删除数据库记录（删除整个表）
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
      final recordCount = (countResult.first['count'] as int?) ?? 0;
      
      if (recordCount > 0) {
        // 删除应用表
        await db.execute('DROP TABLE IF EXISTS $tableName');
        
        // 从 app_registry 中移除注册信息
        await db.delete(
          'app_registry',
          where: 'app_package_name = ?',
          whereArgs: [appPackageName],
        );
        
        // 删除聚合统计表中的记录
        await db.delete(
          'app_stats',
          where: 'app_package_name = ?',
          whereArgs: [appPackageName],
        );
      }

      print('已删除应用 $appPackageName 的 $recordCount 条记录');
      return recordCount;
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
    final db = await database;
    try {
      final tableName = _getAppTableName(packageName);
      if (!await _checkTableExists(db, tableName)) {
        return 0;
      }

      if (keepIds.isEmpty) {
        // 无需保留任何记录，等价于删除所有
        final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
        final recordCount = (countResult.first['count'] as int?) ?? 0;
        await db.execute('DROP TABLE IF EXISTS $tableName');
        await db.delete('app_registry', where: 'app_package_name = ?', whereArgs: [packageName]);
        await db.delete('app_stats', where: 'app_package_name = ?', whereArgs: [packageName]);
        return recordCount;
      }

      final placeholders = List.filled(keepIds.length, '?').join(',');
      final deleted = await db.rawDelete('DELETE FROM $tableName WHERE id NOT IN ($placeholders)', keepIds);

      // 重算统计
      await _recomputeAppStatForPackage(db, packageName);
      return deleted;
    } catch (e) {
      print('删除非保留记录失败: $e');
      return 0;
    }
  }

  /// 根据文件路径查找记录（用于检查重复）
  Future<ScreenshotRecord?> getScreenshotByPath(String filePath) async {
    final db = await database;
    try {
      // 从文件路径推断应用包名
      final packageName = _extractPackageNameFromPath(filePath);
      if (packageName == null) {
        print('无法从路径推断包名: $filePath');
        return null;
      }
      
      final tableName = _getAppTableName(packageName);
      
      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        return null;
      }
      
      final maps = await db.query(
        tableName,
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        // 需要从app_registry获取app_name
        String? appName;
        final appInfo = await db.query(
          'app_registry',
          columns: ['app_name'],
          where: 'app_package_name = ?',
          whereArgs: [packageName],
          limit: 1,
        );
        if (appInfo.isNotEmpty) {
          appName = appInfo.first['app_name'] as String;
        } else {
          appName = packageName; // 后备方案
        }
        
        // 重新添加app相关字段
        final fullMap = Map<String, dynamic>.from(maps.first);
        fullMap['app_package_name'] = packageName;
        fullMap['app_name'] = appName;
        return ScreenshotRecord.fromMap(fullMap);
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
      final tableName = _getAppTableName(record.appPackageName);
      
      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        print('应用表不存在: $tableName');
        return false;
      }
      
      // 准备更新数据（去掉app相关字段）
      final updateMap = {...record.toMap(), 'updated_at': DateTime.now().millisecondsSinceEpoch};
      updateMap.remove('app_package_name');
      updateMap.remove('app_name');
      
      final result = await db.update(
        tableName,
        updateMap,
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
  Future<void> _upsertAppStatOnInsert(DatabaseExecutor db, String package, String appName, int fileSize, int captureTime) async {
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

  Future<void> _recomputeAppStatForPackage(DatabaseExecutor db, String package) async {
    try {
      final tableName = _getAppTableName(package);
      
      // 检查表是否存在
      if (!await _checkTableExists(db, tableName)) {
        // 如果表不存在，直接删除app_stats中的记录
        await db.delete('app_stats', where: 'app_package_name = ?', whereArgs: [package]);
        return;
      }
      
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c, COALESCE(SUM(file_size),0) as s, MAX(capture_time) as t FROM $tableName',
      );
      
      if (rows.isEmpty || (rows.first['c'] as int) == 0) {
        await db.delete('app_stats', where: 'app_package_name = ?', whereArgs: [package]);
        return;
      }
      
      final r = rows.first;
      
      // 从app_registry获取app_name
      String? appName;
      final appInfo = await db.query(
        'app_registry',
        columns: ['app_name'],
        where: 'app_package_name = ?',
        whereArgs: [package],
        limit: 1,
      );
      if (appInfo.isNotEmpty) {
        appName = appInfo.first['app_name'] as String;
      } else {
        appName = package; // 后备方案
      }
      
      await db.execute(
        '''INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(app_package_name) DO UPDATE SET app_name=excluded.app_name, total_count=excluded.total_count, total_size=excluded.total_size, last_capture_time=excluded.last_capture_time''',
        [
          package,
          appName,
          r['c'],
          r['s'],
          r['t'],
        ],
      );
    } catch (e) {
      print('重新计算应用统计失败: $e');
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

  // ======= 分表架构相关方法 =======
  
  /// 包名清理函数：将包名转换为合法的表名
  String _sanitizePackageName(String packageName) {
    return packageName.replaceAll(RegExp(r'[^\w]'), '_');
  }
  
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
      return;
    }
    
    // 创建应用表
    await _createAppTable(db, tableName);
    
    // 注册到app_registry
    await db.execute('''
      INSERT OR REPLACE INTO app_registry (app_package_name, app_name, table_name)
      VALUES (?, ?, ?)
    ''', [packageName, appName, tableName]);
    
    print('已创建应用表: $tableName');
  }

  /// 创建应用表
  Future<void> _createAppTable(DatabaseExecutor db, String tableName) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_path TEXT NOT NULL UNIQUE,
          capture_time INTEGER NOT NULL,
          file_size INTEGER NOT NULL DEFAULT 0,
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
}
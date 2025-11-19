part of 'screenshot_database.dart';

/// 导入/导出进度数据（0~1）
class ImportExportProgress {
  /// 当前进度，范围 [0, 1]；未知时为 0
  final double value;

  /// 说明当前阶段（例如 'scanning', 'packing', 'extracting'）
  final String? stage;

  /// 当前处理的条目（相对路径或文件名），用于展示更细粒度的进度信息
  final String? currentEntry;

  const ImportExportProgress({
    required this.value,
    this.stage,
    this.currentEntry,
  });
}

// ===================== 导出/导入 Isolate 工具 =====================

/// 导出打包的 Isolate 入口
Future<void> _exportZipIsolateEntry(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'] as SendPort;
  final String outputDirPath = args['outputDirPath'] as String;
  final String tmpZipPath = args['tmpZipPath'] as String;

  try {
    final Directory dir = Directory(outputDirPath);
    if (!await dir.exists()) {
      sendPort.send({
        'type': 'error',
        'error': 'output directory not found: $outputDirPath',
      });
      return;
    }

    bool ignored(String relLower) {
      final List<String> parts = relLower.split('/');
      if (parts.isNotEmpty) {
        final String head = parts.first;
        if (head == 'cache' ||
            head == 'tmp' ||
            head == 'temp' ||
            head == '.thumbnails') {
          return true;
        }
      }
      // 保留 SQLite WAL/SHM 辅助文件，确保 WAL 模式数据库在导出时拥有最新数据
      if (relLower.endsWith('.db-journal')) {
        return true;
      }
      return false;
    }

    // 第一次遍历：只收集需要打包的相对路径，避免一次性打开过多文件句柄
    final List<String> files = <String>[];
    await for (final FileSystemEntity entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final String relPath =
          entity.path.substring(dir.path.length + 1).replaceAll('\\', '/');
      final String relLower = relPath.toLowerCase();
      if (ignored(relLower)) continue;
      files.add(relPath);
    }

    final int total = files.length;
    if (total == 0) {
      // 没有可导出的文件，直接返回空 zip 路径
      sendPort.send(<String, Object?>{
        'type': 'done',
        'zippedPath': tmpZipPath,
      });
      return;
    }

    sendPort.send(<String, Object?>{
      'type': 'progress',
      'progress': 0.0,
      'stage': 'scanning',
      'entry': null,
    });

    // 使用 ZipFileEncoder 逐个文件写入，避免“Too many open files”
    // 并将压缩级别设为 0（store 模式：只打包，不压缩）
    final ZipFileEncoder encoder = ZipFileEncoder();
    encoder.create(tmpZipPath, level: 0);
    for (int i = 0; i < files.length; i++) {
      final String relPath = files[i];
      final File f = File(join(outputDirPath, relPath));
      if (!await f.exists()) {
        // 跳过已不存在的文件
        continue;
      }
      // 旧版 archive 库的 addFile 使用位置参数指定文件名
      encoder.addFile(f, relPath);
      final double progress = (i + 1) / total;
      sendPort.send(<String, Object?>{
        'type': 'progress',
        'progress': progress.clamp(0.0, 1.0),
        'stage': 'packing',
        'entry': relPath,
      });
    }
    encoder.close();

    sendPort.send(<String, Object?>{
      'type': 'done',
      'zippedPath': tmpZipPath,
    });
  } catch (e) {
    sendPort.send(<String, Object?>{
      'type': 'error',
      'error': e.toString(),
    });
  }
}

/// 导入解压的 Isolate 入口
Future<void> _importZipIsolateEntry(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'] as SendPort;
  final String localZipPath = args['zipPath'] as String;
  final String outputDirPath = args['outputDirPath'] as String;
  final bool overwrite = (args['overwrite'] as bool?) ?? true;

  try {
    final Directory outputDir = Directory(outputDirPath);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final InputFileStream input = InputFileStream(localZipPath);
    final Archive archive = ZipDecoder().decodeBuffer(input);

    // 只统计文件项数量用于进度
    final List<ArchiveFile> files =
        archive.files.where((ArchiveFile f) => f.isFile).toList();
    final int total = files.length;
    if (total == 0) {
      input.close();
      sendPort.send(<String, Object?>{
        'type': 'done',
        'extracted': 0,
      });
      return;
    }

    int extracted = 0;
    sendPort.send(<String, Object?>{
      'type': 'progress',
      'progress': 0.0,
      'stage': 'extracting',
      'entry': null,
    });

    for (int i = 0; i < files.length; i++) {
      final ArchiveFile f = files[i];
      final String relative = normalize(f.name).replaceAll('\\', '/');
      final String rel = relative.startsWith('output/')
          ? relative.substring('output/'.length)
          : relative;

      // 安全检查，防止目录穿越
      if (rel.startsWith('../') || rel.startsWith('/')) {
        continue;
      }

      final String destPath = join(outputDir.path, rel);
      if (f.isFile) {
        final File destFile = File(destPath);
        final Directory parent = destFile.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        if (!overwrite && await destFile.exists()) {
          // 跳过覆盖
        } else {
          final OutputFileStream out = OutputFileStream(destPath);
          f.writeContent(out);
          await out.close();
          extracted++;
        }
      } else {
        final Directory d = Directory(destPath);
        if (!await d.exists()) {
          await d.create(recursive: true);
        }
      }

      final double progress = (i + 1) / total;
      sendPort.send(<String, Object?>{
        'type': 'progress',
        'progress': progress.clamp(0.0, 1.0),
        'stage': 'extracting',
        'entry': rel,
      });
    }

    input.close();

    sendPort.send(<String, Object?>{
      'type': 'done',
      'extracted': extracted,
    });
  } catch (e) {
    sendPort.send(<String, Object?>{
      'type': 'error',
      'error': e.toString(),
    });
  }
}

/// 导出打包的帮助函数：在主 Isolate 中管理进度与结果
Future<String?> _runExportZipWithProgress({
  required String outputDirPath,
  required String tmpZipPath,
  void Function(ImportExportProgress progress)? onProgress,
}) async {
  await FlutterLogger.nativeInfo(
    'EXPORT',
    'runExportZipWithProgress: outputDirPath=' +
        outputDirPath +
        ', tmpZipPath=' +
        tmpZipPath,
  );
  final ReceivePort receivePort = ReceivePort();
  Isolate? iso;
  try {
    iso = await Isolate.spawn<Map<String, dynamic>>(
      _exportZipIsolateEntry,
      <String, dynamic>{
        'sendPort': receivePort.sendPort,
        'outputDirPath': outputDirPath,
        'tmpZipPath': tmpZipPath,
      },
    );

    final Completer<String?> completer = Completer<String?>();
    late final StreamSubscription<dynamic> sub;
    sub = receivePort.listen((dynamic message) {
      if (message is! Map) return;
      final String? type = message['type'] as String?;
      if (type == 'progress') {
        final double? p = (message['progress'] as num?)?.toDouble();
        final String? stage = message['stage'] as String?;
        final String? entry = message['entry'] as String?;
        if (p != null && onProgress != null) {
          onProgress(
            ImportExportProgress(
              value: p.clamp(0.0, 1.0),
              stage: stage,
              currentEntry: entry,
            ),
          );
        }
      } else if (type == 'done') {
        if (!completer.isCompleted) {
          completer.complete(message['zippedPath'] as String?);
        }
      } else if (type == 'error') {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception(message['error'] as String? ?? 'export failed'),
          );
        }
      }
    });

    String? result;
    try {
      result = await completer.future;
      await FlutterLogger.nativeInfo(
        'EXPORT',
        'runExportZipWithProgress finished, result=' + (result ?? 'null'),
      );
    } finally {
      await sub.cancel();
      receivePort.close();
      iso.kill(priority: Isolate.immediate);
    }
    return result;
  } catch (e) {
    receivePort.close();
    iso?.kill(priority: Isolate.immediate);
    await FlutterLogger.nativeError(
      'EXPORT',
      'runExportZipWithProgress exception: ' + e.toString(),
    );
    rethrow;
  }
}

/// 导入解压的帮助函数：在主 Isolate 中管理进度与结果
Future<Map<String, dynamic>?> _runImportZipWithProgress({
  required String localZipPath,
  required String outputDirPath,
  required bool overwrite,
  void Function(ImportExportProgress progress)? onProgress,
}) async {
  final ReceivePort receivePort = ReceivePort();
  Isolate? iso;
  try {
    iso = await Isolate.spawn<Map<String, dynamic>>(
      _importZipIsolateEntry,
      <String, dynamic>{
        'sendPort': receivePort.sendPort,
        'zipPath': localZipPath,
        'outputDirPath': outputDirPath,
        'overwrite': overwrite,
      },
    );

    final Completer<Map<String, dynamic>?> completer =
        Completer<Map<String, dynamic>?>();
    int extracted = 0;
    late final StreamSubscription<dynamic> sub;
    sub = receivePort.listen((dynamic message) {
      if (message is! Map) return;
      final String? type = message['type'] as String?;
      if (type == 'progress') {
        final double? p = (message['progress'] as num?)?.toDouble();
        final String? stage = message['stage'] as String?;
        final String? entry = message['entry'] as String?;
        if (p != null && onProgress != null) {
          onProgress(
            ImportExportProgress(
              value: p.clamp(0.0, 1.0),
              stage: stage,
              currentEntry: entry,
            ),
          );
        }
      } else if (type == 'done') {
        extracted = (message['extracted'] as int?) ?? 0;
        if (!completer.isCompleted) {
          completer.complete(<String, dynamic>{
            'extracted': extracted,
            'targetDir': outputDirPath,
          });
        }
      } else if (type == 'error') {
        if (!completer.isCompleted) {
          FlutterLogger.nativeError(
            'IMPORT',
            'zip isolate error: ' +
                (message['error'] as String? ?? 'unknown'),
          );
          completer.completeError(
            Exception(message['error'] as String? ?? 'import failed'),
          );
        }
      }
    });

    Map<String, dynamic>? result;
    try {
      result = await completer.future;
    } finally {
      await sub.cancel();
      receivePort.close();
      iso.kill(priority: Isolate.immediate);
    }
    return result;
  } catch (e) {
    receivePort.close();
    iso?.kill(priority: Isolate.immediate);
    rethrow;
  }
}

// 收藏与 NSFW 偏好相关方法拆分为扩展
extension ScreenshotDatabaseMeta on ScreenshotDatabase {
  /// 检查本机 SQLite 是否支持 FTS（fts5/fts4 任一即可）
  /// 成功则返回 true，否则返回 false。
  Future<bool> isOcrIndexAvailable() async {
    final db = await database;
    bool ok = false;
    // 使用主库上临时虚拟表进行探测，避免遍历分库
    try {
      await db.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS _fts_probe USING fts5(x)",
      );
      ok = true;
    } catch (_) {
      try {
        await db.execute(
          "CREATE VIRTUAL TABLE IF NOT EXISTS _fts_probe USING fts4(x)",
        );
        ok = true;
      } catch (_) {}
    }
    if (ok) {
      try {
        await db.execute("DROP TABLE IF EXISTS _fts_probe");
      } catch (_) {}
    }
    return ok;
  }

  // ===================== OCR LIKE 回退搜索（非索引） =====================
  Future<List<ScreenshotRecord>> searchScreenshotsByOcrLike(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim().toLowerCase();
      if (q.isEmpty) return <ScreenshotRecord>[];

      // 预取应用名缓存
      final Map<String, String> appNameCache = <String, String>{};
      try {
        final reg = await db.query(
          'app_registry',
          columns: ['app_package_name', 'app_name'],
        );
        for (final r in reg) {
          final pkg = r['app_package_name'] as String;
          final name = (r['app_name'] as String?) ?? pkg;
          appNameCache[pkg] = name;
        }
      } catch (_) {}

      // 估算每表抓取上限
      final int requested = ((offset ?? 0) + (limit ?? 100));
      final int target = (requested <= 0 ? 400 : requested * 4);
      final int perTableLimit = (() {
        final int base = requested <= 0 ? 400 : requested * 2;
        if (base < 200) return 200;
        if (base > 5000) return 5000;
        return base;
      })();

      // 时间范围限制到需扫描的年月
      List<List<int>>? ymFilter;
      if (startMillis != null || endMillis != null) {
        final int s = startMillis ?? 0;
        final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
        ymFilter = _listYearMonthBetween(
          DateTime.fromMillisecondsSinceEpoch(s),
          DateTime.fromMillisecondsSinceEpoch(e),
        );
      }

      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
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
        final Iterable<int> months = () {
          if (ymFilter == null) return List<int>.generate(12, (i) => 12 - i);
          final ms =
              ymFilter!
                  .where((ym) => ym[0] == y)
                  .map((ym) => ym[1])
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          if (ms.isEmpty) return const <int>[];
          return ms;
        }();
        for (final m in months) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            // 构建 LIKE 条件（多词 AND）
            final parts = q
                .split(RegExp(r"\s+"))
                .where((e) => e.isNotEmpty)
                .toList();
            final List<String> filters = <String>[
              'm.is_deleted = 0',
              'm.ocr_text IS NOT NULL AND LENGTH(m.ocr_text) > 0',
            ];
            final List<Object?> args = <Object?>[];
            for (final w in parts) {
              filters.add('LOWER(m.ocr_text) LIKE ?');
              args.add('%' + w + '%');
            }
            if (startMillis != null || endMillis != null) {
              final int s = startMillis ?? 0;
              final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
              filters.add('m.capture_time >= ? AND m.capture_time <= ?');
              args
                ..add(s)
                ..add(e);
            }
            if (minSize != null && maxSize != null) {
              filters.add('m.file_size >= ? AND m.file_size <= ?');
              args
                ..add(minSize)
                ..add(maxSize);
            } else if (minSize != null) {
              filters.add('m.file_size >= ?');
              args.add(minSize);
            } else if (maxSize != null) {
              filters.add('m.file_size <= ?');
              args.add(maxSize);
            }

            final String sql =
                'SELECT m.* FROM ' +
                t +
                ' m WHERE ' +
                filters.join(' AND ') +
                ' ORDER BY m.capture_time DESC LIMIT ?';
            args.add(perTableLimit);
            final List<Map<String, Object?>> maps = await (shardDb as Database)
                .rawQuery(sql, args);
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
    } catch (_) {
      return <ScreenshotRecord>[];
    }
  }

  Future<int> countScreenshotsByOcrLike(
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim().toLowerCase();
      if (q.isEmpty) return 0;

      // 时间范围限制到需扫描的年月
      List<List<int>>? ymFilter;
      if (startMillis != null || endMillis != null) {
        final int s = startMillis ?? 0;
        final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
        ymFilter = _listYearMonthBetween(
          DateTime.fromMillisecondsSinceEpoch(s),
          DateTime.fromMillisecondsSinceEpoch(e),
        );
      }

      int total = 0;
      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        final Iterable<int> months = () {
          if (ymFilter == null) return List<int>.generate(12, (i) => 12 - i);
          final ms =
              ymFilter!
                  .where((ym) => ym[0] == y)
                  .map((ym) => ym[1])
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          if (ms.isEmpty) return const <int>[];
          return ms;
        }();
        for (final m in months) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final parts = q
                .split(RegExp(r"\s+"))
                .where((e) => e.isNotEmpty)
                .toList();
            final List<String> filters = <String>[
              'm.is_deleted = 0',
              'm.ocr_text IS NOT NULL AND LENGTH(m.ocr_text) > 0',
            ];
            final List<Object?> args = <Object?>[];
            for (final w in parts) {
              filters.add('LOWER(m.ocr_text) LIKE ?');
              args.add('%' + w + '%');
            }
            if (startMillis != null || endMillis != null) {
              final int s = startMillis ?? 0;
              final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
              filters.add('m.capture_time >= ? AND m.capture_time <= ?');
              args
                ..add(s)
                ..add(e);
            }
            if (minSize != null && maxSize != null) {
              filters.add('m.file_size >= ? AND m.file_size <= ?');
              args
                ..add(minSize)
                ..add(maxSize);
            } else if (minSize != null) {
              filters.add('m.file_size >= ?');
              args.add(minSize);
            } else if (maxSize != null) {
              filters.add('m.file_size <= ?');
              args.add(maxSize);
            }
            final String sql =
                'SELECT COUNT(*) AS c FROM ' +
                t +
                ' m WHERE ' +
                filters.join(' AND ');
            final List<Map<String, Object?>> rows = await (shardDb as Database)
                .rawQuery(sql, args);
            total += (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 创建收藏表
  Future<void> _createFavoritesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        screenshot_id INTEGER NOT NULL,
        app_package_name TEXT NOT NULL,
        favorite_time INTEGER NOT NULL,
        note TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(screenshot_id, app_package_name)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_favorites_screenshot ON favorites(screenshot_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_favorites_time ON favorites(favorite_time DESC)',
    );
  }

  // ===================== 截图查询与全局统计 =====================
  Future<List<ScreenshotRecord>> getScreenshotsByApp(
    String appPackageName, {
    int? limit,
    int? offset,
  }) async {
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
      final int requested = ((offset ?? 0) + (limit ?? 100));
      final int target = (requested <= 0 ? 400 : requested * 4);
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
            final rows = await shardDb.query(t, columns: ['id']);
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

  /// 通过全局ID(gid)与包名获取单条截图记录
  Future<ScreenshotRecord?> getScreenshotById(
    int gid,
    String appPackageName,
  ) async {
    final db = await database; // 主库
    try {
      final decoded = _decodeGid(gid);
      if (decoded == null) return null;
      final int year = decoded[0];
      final int month = decoded[1];
      final int localId = decoded[2];

      final shardDb = await _openShardDb(appPackageName, year);
      if (shardDb == null) return null;
      final String table = _monthTableName(year, month);
      if (!await _tableExists(shardDb, table)) return null;

      // 查询该月表中的本地ID
      final maps = await shardDb.query(
        table,
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (maps.isEmpty) return null;

      // 查 app 名称
      String appName = appPackageName;
      try {
        final rows = await db.query(
          'app_registry',
          columns: ['app_name'],
          where: 'app_package_name = ?',
          whereArgs: [appPackageName],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          appName = (rows.first['app_name'] as String?) ?? appPackageName;
        }
      } catch (_) {}

      final full = Map<String, dynamic>.from(maps.first);
      full['app_package_name'] = appPackageName;
      full['app_name'] = appName;
      full['id'] = gid;
      return ScreenshotRecord.fromMap(full);
    } catch (e) {
      print('getScreenshotById 失败: $e');
      return null;
    }
  }

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

  Future<int> getScreenshotCountByApp(String appPackageName) async {
    final db = await database; // 主库
    try {
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

  Future<Map<String, Map<String, dynamic>>> getScreenshotStatistics() async {
    StartupProfiler.begin('ScreenshotDatabase.getScreenshotStatistics');
    final db = await database;
    try {
      var maps = await db.rawQuery('''
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
              ? DateTime.fromMillisecondsSinceEpoch(
                  map['last_capture_time'] as int,
                )
              : null,
          'totalSize': map['total_size'] as int,
        };
      }

      return statistics;
    } catch (e) {
      print('获取截屏统计失败: $e');
      return {};
    } finally {
      StartupProfiler.end('ScreenshotDatabase.getScreenshotStatistics');
    }
  }

  Future<int> getTodayScreenshotCount() async {
    StartupProfiler.begin('ScreenshotDatabase.getTodayScreenshotCount');
    final db = await database; // 主库
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(
        today.year,
        today.month,
        today.day,
      ).millisecondsSinceEpoch;
      final endOfDay = DateTime(
        today.year,
        today.month,
        today.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;

      int totalCount = 0;
      final nowYear = today.year;
      final shardYears = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
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
          final result = await shardDb.rawQuery(
            '''
            SELECT COUNT(*) as count FROM $t WHERE capture_time >= ? AND capture_time <= ?
          ''',
            [startOfDay, endOfDay],
          );
          totalCount += (result.first['count'] as int?) ?? 0;
        } catch (e) {
          print('查询 $pkg/$t 今日数量失败: $e');
        }
      }

      return totalCount;
    } catch (e) {
      print('获取今日截屏数量失败: $e');
      return 0;
    } finally {
      StartupProfiler.end('ScreenshotDatabase.getTodayScreenshotCount');
    }
  }

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
      final rows = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      if (rows.isEmpty) return 0;
      final ymList = _listYearMonthBetween(s, e);
      for (final row in rows) {
        final String pkg = row['app_package_name'] as String;
        final int y = row['year'] as int;
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
              'SELECT COUNT(*) as c FROM $table WHERE capture_time >= ? AND capture_time <= ? AND is_deleted = 0',
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

      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      final Map<String, String> appNameCache = <String, String>{};
      try {
        final reg = await db.query(
          'app_registry',
          columns: ['app_package_name', 'app_name'],
        );
        for (final r in reg) {
          final pkg = r['app_package_name'] as String;
          final name = (r['app_name'] as String?) ?? pkg;
          appNameCache[pkg] = name;
        }
      } catch (_) {}

      // 预估需求量：按需设置每表抓取上限，避免一次性加载全部再排序
      final int requested = ((offset ?? 0) + (limit ?? 100));
      final int perTableLimit = (() {
        final int base = requested <= 0 ? 400 : (requested * 2);
        if (base < 200) return 200;
        if (base > 5000) return 5000;
        return base;
      })();

      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
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
            // 限流：每个分表仅取部分数据，后续统一排序并切片
            final maps = await shardDb.query(
              t,
              where:
                  'capture_time >= ? AND capture_time <= ? AND is_deleted = 0',
              whereArgs: [startMillis, endMillis],
              orderBy: 'capture_time DESC',
              limit: perTableLimit,
              offset: 0,
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
      print('getGlobalScreenshotsBetween 失败: $e');
      return <ScreenshotRecord>[];
    }
  }

  Future<int> getTotalScreenshotCount() async {
    StartupProfiler.begin('ScreenshotDatabase.getTotalScreenshotCount');
    final db = await database; // 主库
    try {
      final result = await db.rawQuery(
        'SELECT SUM(total_count) as count FROM app_stats',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      print('获取总截屏数量失败: $e');
      return 0;
    } finally {
      StartupProfiler.end('ScreenshotDatabase.getTotalScreenshotCount');
    }
  }

  // ===================== 截图删除与更新 =====================
  Future<bool> deleteScreenshot(int id, String packageName) async {
    final db = await database; // 主库
    try {
      FlutterLogger.nativeInfo(
        'DB',
        'deleteScreenshot start id=' +
            id.toString() +
            ', package=' +
            packageName,
      );

      final decoded = _decodeGid(id);
      if (decoded == null) {
        FlutterLogger.nativeWarn('DB', '删除截图时无效的gid=' + id.toString());
        return false;
      }
      final int year = decoded[0];
      final int month = decoded[1];
      final int localId = decoded[2];
      final shardDb = await _openShardDb(packageName, year);
      if (shardDb == null) return false;
      final tableName = _monthTableName(year, month);
      if (!await _tableExists(shardDb, tableName)) return false;
      final maps = await shardDb.query(
        tableName,
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (maps.isEmpty) return false;
      final filePath = maps.first['file_path'] as String;
      final result = await shardDb.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (result <= 0) return false;
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          FlutterLogger.nativeInfo('FS', 'deleted file: ' + filePath);
        }
      } catch (e) {
        FlutterLogger.nativeWarn('FS', 'delete file failed: ' + e.toString());
      }
      await _recomputeAppStatForPackage(db, packageName);
      FlutterLogger.nativeInfo('DB', '删除后重算统计 gid=' + id.toString());
      return true;
    } catch (e) {
      print('删除截屏记录失败: $e');
      FlutterLogger.nativeError('DB', '删除截图时发生异常: ' + e.toString());
      return false;
    }
  }

  Future<int> deleteScreenshotsByIds(String packageName, List<int> ids) async {
    final db = await database; // 主库
    if (ids.isEmpty) return 0;
    try {
      final sw = Stopwatch()..start();

      final Map<int, List<int>> byYm = {};
      for (final gid in ids) {
        final d = _decodeGid(gid);
        if (d == null) continue;
        final key = d[0] * 100 + d[1];
        (byYm[key] ??= <int>[]).add(d[2]);
      }

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
          final rows = await shardDb.query(
            tableName,
            columns: ['file_path'],
            where: 'id IN ($ph)',
            whereArgs: localIds,
          );
          for (final r in rows) {
            final p = r['file_path'] as String?;
            if (p != null) filePaths.add(p);
          }

          const int chunk = 900;
          for (int i = 0; i < localIds.length; i += chunk) {
            final sub = localIds.sublist(
              i,
              i + chunk > localIds.length ? localIds.length : i + chunk,
            );
            final ph2 = List.filled(sub.length, '?').join(',');
            final count = await shardDb.rawDelete(
              'DELETE FROM $tableName WHERE id IN ($ph2)',
              sub,
            );
            deletedTotal += count;
          }
        } catch (_) {}
      }

      await _recomputeAppStatForPackage(db, packageName);
      await _deleteFilesConcurrently(filePaths, maxConcurrent: 6);

      sw.stop();
      FlutterLogger.nativeInfo('TOTAL', '批量删除总耗时 ${sw.elapsedMilliseconds}ms');
      return deletedTotal;
    } catch (e) {
      print('批量删除截屏记录失败: $e');
      return 0;
    }
  }

  Future<void> _deleteFilesConcurrently(
    List<String> paths, {
    int maxConcurrent = 6,
  }) async {
    if (paths.isEmpty) return;
    const int batch = 24;
    for (int i = 0; i < paths.length; i += batch) {
      final sub = paths.sublist(
        i,
        i + batch > paths.length ? paths.length : i + batch,
      );
      for (int j = 0; j < sub.length; j += maxConcurrent) {
        final chunk = sub.sublist(
          j,
          j + maxConcurrent > sub.length ? sub.length : j + maxConcurrent,
        );
        await Future.wait(
          chunk.map((p) async {
            try {
              final f = File(p);
              if (await f.exists()) {
                await f.delete();
              }
            } catch (e) {
              print('批量删除文件失败: $e, $p');
            }
          }),
        );
      }
    }
  }

  Future<int> deleteAllScreenshotsForApp(String appPackageName) async {
    final db = await database; // 主库
    try {
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

      await db.delete(
        'shard_registry',
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
      );
      await db.delete(
        'app_registry',
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
      );
      await db.delete(
        'app_stats',
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
      );

      print('已删除应用 $appPackageName 的 $total 条记录');
      return total;
    } catch (e) {
      print('批量删除应用截屏记录失败: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getRecordsByIds(
    String packageName,
    List<int> ids,
  ) async {
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

  Future<int> deleteAllExcept(String packageName, List<int> keepIds) async {
    final db = await database; // 主库
    try {
      if (keepIds.isEmpty) {
        return await deleteAllScreenshotsForApp(packageName);
      }

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
              final rows = await shardDb.rawQuery(
                'SELECT COUNT(*) as c FROM $t',
              );
              final c = (rows.first['c'] as int?) ?? 0;
              await shardDb.execute('DROP TABLE IF EXISTS $t');
              deletedTotal += c;
            } else {
              final placeholders = List.filled(keepSet.length, '?').join(',');
              final count = await shardDb.rawDelete(
                'DELETE FROM $t WHERE id NOT IN ($placeholders)',
                keepSet.toList(),
              );
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

  Future<ScreenshotRecord?> getScreenshotByPath(String filePath) async {
    final db = await database; // 主库
    try {
      final packageName = _extractPackageNameFromPath(filePath);
      if (packageName == null) {
        print('无法从路径推断包名: $filePath');
        return null;
      }
      String appName = packageName;
      try {
        final info = await db.query(
          'app_registry',
          columns: ['app_name'],
          where: 'app_package_name = ?',
          whereArgs: [packageName],
          limit: 1,
        );
        if (info.isNotEmpty)
          appName = (info.first['app_name'] as String?) ?? packageName;
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
              columns: [
                'id',
                'file_path',
                'capture_time',
                'file_size',
                'page_url',
                'ocr_text',
                'is_deleted',
              ],
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

  /// 通过文件名在所有分库中查找截图的绝对路径（找到一条即返回）
  Future<String?> findScreenshotPathByBasename(String filename) async {
    try {
      if (filename.trim().isEmpty) return null;
      String name = filename.trim();
      // 提取不含扩展名的基名与候选扩展名集合
      String base = name;
      String? ext;
      final dot = name.lastIndexOf('.');
      if (dot > 0 && dot < name.length - 1) {
        base = name.substring(0, dot);
        ext = name.substring(dot + 1).toLowerCase();
      }
      final Set<String> extCandidates = <String>{};
      if (ext != null && ext.isNotEmpty) extCandidates.add(ext);
      extCandidates.addAll(<String>{'jpg', 'jpeg', 'png', 'webp'});
      final master = await database;
      // 先在 segment_samples（主库）中搜索，按可能扩展名匹配
      for (final e in extCandidates) {
        try {
          final rows = await master.query(
            'segment_samples',
            columns: ['file_path'],
            where: 'file_path LIKE ?',
            whereArgs: ['%' + base + '.' + e],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final p = (rows.first['file_path'] as String?) ?? '';
            if (p.isNotEmpty) return p;
          }
        } catch (_) {}
      }

      // 列出所有应用包（从 shard_registry 或 app_registry 猜测）
      List<String> packages = <String>[];
      try {
        final rows = await master.query(
          'shard_registry',
          columns: ['app_package_name'],
          distinct: true,
        );
        packages = rows
            .map((e) => (e['app_package_name'] as String?) ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {
        try {
          final rows = await master.query(
            'app_registry',
            columns: ['app_package_name'],
          );
          packages = rows
              .map((e) => (e['app_package_name'] as String?) ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        } catch (_) {}
      }
      if (packages.isEmpty) return null;

      for (final pkg in packages) {
        final years = await _listShardYearsForApp(pkg);
        for (final y in years) {
          final shardDb = await _openShardDb(pkg, y);
          if (shardDb == null) continue;
          for (int m = 12; m >= 1; m--) {
            final t = _monthTableName(y, m);
            if (!await _tableExists(shardDb, t)) continue;
            try {
              for (final e in extCandidates) {
                final pattern = '%' + base + '.' + e;
                final rows = await shardDb.query(
                  t,
                  columns: ['file_path'],
                  where: 'file_path LIKE ?',
                  whereArgs: [pattern],
                  limit: 1,
                );
                if (rows.isNotEmpty) {
                  final p = (rows.first['file_path'] as String?) ?? '';
                  if (p.isNotEmpty) return p;
                }
              }
            } catch (_) {}
          }
        }
      }
      // 若数据库未命中，回退到文件系统快速扫描（限定 output/screen 根目录下）
      try {
        final root = await PathService.getScreenshotDirectory();
        if (root != null) {
          final ent = root.list(recursive: true, followLinks: false);
          await for (final e in ent) {
            if (e is File) {
              final String pth = e.path;
              for (final ex in extCandidates) {
                if (pth.endsWith('/' + base + '.' + ex) ||
                    pth.endsWith('\\' + base + '.' + ex) ||
                    pth.endsWith(base + '.' + ex)) {
                  return pth;
                }
              }
            }
          }
        }
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 批量：通过文件名集合查找路径映射
  Future<Map<String, String>> findPathsByBasenames(
    Set<String> filenames,
  ) async {
    final Map<String, String> result = <String, String>{};
    for (final name in filenames) {
      final p = await findScreenshotPathByBasename(name);
      if (p != null && p.isNotEmpty) result[name] = p;
    }
    return result;
  }

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
      final updateMap = {
        ...record.toMap(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      updateMap.remove('app_package_name');
      updateMap.remove('app_name');
      final result = await shardDb.update(
        tableName,
        updateMap,
        where: 'id = ?',
        whereArgs: [localId],
      );
      return result > 0;
    } catch (e) {
      print('更新截屏记录失败: $e');
      return false;
    }
  }

  // ===================== OCR 搜索 =====================
  Future<List<ScreenshotRecord>> searchScreenshotsByOcr(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim();
      if (q.isEmpty) return <ScreenshotRecord>[];

      final Map<String, String> appNameCache = <String, String>{};
      try {
        final reg = await db.query(
          'app_registry',
          columns: ['app_package_name', 'app_name'],
        );
        for (final r in reg) {
          final pkg = r['app_package_name'] as String;
          final name = (r['app_name'] as String?) ?? pkg;
          appNameCache[pkg] = name;
        }
      } catch (_) {}

      final int requested = ((offset ?? 0) + (limit ?? 100));
      final int target = (requested <= 0 ? 400 : requested * 4);
      final int perTableLimit = (() {
        final int base = requested <= 0 ? 400 : requested * 2;
        if (base < 200) return 200;
        if (base > 5000) return 5000;
        return base;
      })();

      // FTS 模式，不使用 LIKE 兜底
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];

      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );

      // 若提供时间范围，则优先限定需要扫描的年月集合
      List<List<int>>? ymFilter;
      if (startMillis != null || endMillis != null) {
        final int s = startMillis ?? 0;
        final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
        ymFilter = _listYearMonthBetween(
          DateTime.fromMillisecondsSinceEpoch(s),
          DateTime.fromMillisecondsSinceEpoch(e),
        );
      }

      outer:
      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        final String appName = appNameCache[pkg] ?? pkg;
        // 选择需要扫描的月份
        final Iterable<int> months = () {
          if (ymFilter == null) return List<int>.generate(12, (i) => 12 - i);
          final ms =
              ymFilter!
                  .where((ym) => ym[0] == y)
                  .map((ym) => ym[1])
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          if (ms.isEmpty) return const <int>[];
          return ms;
        }();
        for (final m in months) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            // 尝试优先 FTS：确保当月FTS存在（首次会自动回填）
            try {
              await _ensureMonthFts(shardDb, y, m);
            } catch (_) {}

            // 构建 FTS MATCH 字符串（简单 AND + 前缀）
            String buildMatch(String text) {
              final parts = text
                  .split(RegExp(r"\s+"))
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (parts.isEmpty) return text;
              // 限制最多5个词，避免过长查询
              final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
              return limited
                  .map((w) => (w.replaceAll('"', '')) + '*')
                  .join(' AND ');
            }

            final String match = buildMatch(q);

            // 组合 SQL：fts JOIN 主表并应用过滤
            final String fts = '${t}_fts';
            // 禁止回退：如未成功创建/存在 FTS 表，直接抛错
            final bool ftsExists = await _tableExists(shardDb, fts);
            if (!ftsExists) {
              throw StateError('FTS not available for table ' + t);
            }
            final List<Object?> args = <Object?>[match];
            final List<String> filters = <String>['m.is_deleted = 0'];
            if (startMillis != null || endMillis != null) {
              final int s = startMillis ?? 0;
              final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
              filters.add('m.capture_time >= ? AND m.capture_time <= ?');
              args
                ..add(s)
                ..add(e);
            }
            if (minSize != null && maxSize != null) {
              filters.add('m.file_size >= ? AND m.file_size <= ?');
              args
                ..add(minSize)
                ..add(maxSize);
            } else if (minSize != null) {
              filters.add('m.file_size >= ?');
              args.add(minSize);
            } else if (maxSize != null) {
              filters.add('m.file_size <= ?');
              args.add(maxSize);
            }

            final sql =
                'SELECT m.* FROM ' +
                t +
                ' m JOIN ' +
                fts +
                ' f ON f.rowid = m.id ' +
                'WHERE ' +
                fts +
                ' MATCH ? AND ' +
                filters.join(' AND ') +
                ' ' +
                'ORDER BY m.capture_time DESC LIMIT ?';
            args.add(perTableLimit);

            List<Map<String, Object?>> maps = await (shardDb as Database)
                .rawQuery(sql, args);
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
      print('searchScreenshotsByOcr 失败: $e');
      rethrow;
    }
  }

  /// 统计全局按 OCR 文本匹配的总数量（强制使用 FTS）
  Future<int> countScreenshotsByOcr(
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim();
      if (q.isEmpty) return 0;

      // 时间范围转换为年月集合（用于限缩扫描表）
      List<List<int>>? ymFilter;
      if (startMillis != null || endMillis != null) {
        final int s = startMillis ?? 0;
        final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
        ymFilter = _listYearMonthBetween(
          DateTime.fromMillisecondsSinceEpoch(s),
          DateTime.fromMillisecondsSinceEpoch(e),
        );
      }

      // 构建 MATCH 字符串
      String buildMatch(String text) {
        final parts = text
            .split(RegExp(r"\s+"))
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isEmpty) return text;
        final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
        return limited.map((w) => (w.replaceAll('"', '')) + '*').join(' AND ');
      }

      final String match = buildMatch(q);

      int total = 0;
      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );

      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        final Iterable<int> months = () {
          if (ymFilter == null) return List<int>.generate(12, (i) => 12 - i);
          final ms =
              ymFilter!
                  .where((ym) => ym[0] == y)
                  .map((ym) => ym[1])
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          if (ms.isEmpty) return const <int>[];
          return ms;
        }();
        for (final m in months) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          // 确保 FTS 存在
          try {
            await _ensureMonthFts(shardDb, y, m);
          } catch (_) {}
          final String fts = '${t}_fts';
          final bool ftsExists = await _tableExists(shardDb, fts);
          if (!ftsExists) {
            throw StateError('FTS not available for table ' + t);
          }

          final List<Object?> args = <Object?>[match];
          final List<String> filters = <String>['m.is_deleted = 0'];
          if (startMillis != null || endMillis != null) {
            final int s = startMillis ?? 0;
            final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
            filters.add('m.capture_time >= ? AND m.capture_time <= ?');
            args
              ..add(s)
              ..add(e);
          }
          if (minSize != null && maxSize != null) {
            filters.add('m.file_size >= ? AND m.file_size <= ?');
            args
              ..add(minSize)
              ..add(maxSize);
          } else if (minSize != null) {
            filters.add('m.file_size >= ?');
            args.add(minSize);
          } else if (maxSize != null) {
            filters.add('m.file_size <= ?');
            args.add(maxSize);
          }

          final String sql =
              'SELECT COUNT(*) AS c FROM ' +
              t +
              ' m JOIN ' +
              fts +
              ' f ON f.rowid = m.id ' +
              'WHERE ' +
              fts +
              ' MATCH ? AND ' +
              filters.join(' AND ');
          final List<Map<String, Object?>> rows = await (shardDb as Database)
              .rawQuery(sql, args);
          total += (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
        }
      }
      return total;
    } catch (e) {
      print('countScreenshotsByOcr 失败: $e');
      rethrow;
    }
  }

  Future<List<ScreenshotRecord>> searchScreenshotsByOcrForApp(
    String appPackageName,
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim();
      if (q.isEmpty) return <ScreenshotRecord>[];

      String appName = appPackageName;
      try {
        final r = await db.query(
          'app_registry',
          columns: ['app_name'],
          where: 'app_package_name = ?',
          whereArgs: [appPackageName],
          limit: 1,
        );
        if (r.isNotEmpty)
          appName = (r.first['app_name'] as String?) ?? appPackageName;
      } catch (_) {}

      final int requested = ((offset ?? 0) + (limit ?? 100));
      final int target = (requested <= 0 ? 400 : requested * 4);
      final int perTableLimit = (() {
        final int base = requested <= 0 ? 400 : requested * 2;
        if (base < 200) return 200;
        if (base > 5000) return 5000;
        return base;
      })();

      // FTS 模式，不使用 LIKE 兜底
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];

      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return <ScreenshotRecord>[];
      // 时间过滤下的年月集合
      List<List<int>>? ymFilter;
      if (startMillis != null || endMillis != null) {
        final int s = startMillis ?? 0;
        final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
        ymFilter = _listYearMonthBetween(
          DateTime.fromMillisecondsSinceEpoch(s),
          DateTime.fromMillisecondsSinceEpoch(e),
        );
      }
      outer:
      for (final y in years) {
        if (ymFilter != null && ymFilter.every((ym) => ym[0] != y)) continue;
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        final Iterable<int> months = () {
          if (ymFilter == null) return List<int>.generate(12, (i) => 12 - i);
          final ms =
              ymFilter!
                  .where((ym) => ym[0] == y)
                  .map((ym) => ym[1])
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          if (ms.isEmpty) return const <int>[];
          return ms;
        }();
        for (final m in months) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            // 确保 FTS
            try {
              await _ensureMonthFts(shardDb, y, m);
            } catch (_) {}

            String buildMatch(String text) {
              final parts = text
                  .split(RegExp(r"\s+"))
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (parts.isEmpty) return text;
              final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
              return limited
                  .map((w) => (w.replaceAll('"', '')) + '*')
                  .join(' AND ');
            }

            final String match = buildMatch(q);

            final String fts = '${t}_fts';
            final bool ftsExists = await _tableExists(shardDb, fts);
            if (!ftsExists) {
              throw StateError('FTS not available for table ' + t);
            }
            final List<Object?> args = <Object?>[match];
            final List<String> filters = <String>['m.is_deleted = 0'];
            if (startMillis != null || endMillis != null) {
              final int s = startMillis ?? 0;
              final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
              filters.add('m.capture_time >= ? AND m.capture_time <= ?');
              args
                ..add(s)
                ..add(e);
            }
            if (minSize != null && maxSize != null) {
              filters.add('m.file_size >= ? AND m.file_size <= ?');
              args
                ..add(minSize)
                ..add(maxSize);
            } else if (minSize != null) {
              filters.add('m.file_size >= ?');
              args.add(minSize);
            } else if (maxSize != null) {
              filters.add('m.file_size <= ?');
              args.add(maxSize);
            }
            final sql =
                'SELECT m.* FROM ' +
                t +
                ' m JOIN ' +
                fts +
                ' f ON f.rowid = m.id ' +
                'WHERE ' +
                fts +
                ' MATCH ? AND ' +
                filters.join(' AND ') +
                ' ' +
                'ORDER BY m.capture_time DESC LIMIT ?';
            args.add(perTableLimit);

            List<Map<String, Object?>> maps = await (shardDb as Database)
                .rawQuery(sql, args);
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
      rethrow;
    }
  }

  /// 统计指定应用按 OCR 文本匹配的总数量（强制使用 FTS）
  Future<int> countScreenshotsByOcrForApp(
    String appPackageName,
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    final db = await database; // 主库
    try {
      final String q = query.trim();
      if (q.isEmpty) return 0;

      List<List<int>>? ymFilter;
      if (startMillis != null || endMillis != null) {
        final int s = startMillis ?? 0;
        final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
        ymFilter = _listYearMonthBetween(
          DateTime.fromMillisecondsSinceEpoch(s),
          DateTime.fromMillisecondsSinceEpoch(e),
        );
      }

      String buildMatch(String text) {
        final parts = text
            .split(RegExp(r"\s+"))
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isEmpty) return text;
        final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
        return limited.map((w) => (w.replaceAll('"', '')) + '*').join(' AND ');
      }

      final String match = buildMatch(q);

      int total = 0;
      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return 0;
      for (final y in years) {
        if (ymFilter != null && ymFilter.every((ym) => ym[0] != y)) continue;
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        final Iterable<int> months = () {
          if (ymFilter == null) return List<int>.generate(12, (i) => 12 - i);
          final ms =
              ymFilter!
                  .where((ym) => ym[0] == y)
                  .map((ym) => ym[1])
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          if (ms.isEmpty) return const <int>[];
          return ms;
        }();
        for (final m in months) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            await _ensureMonthFts(shardDb, y, m);
          } catch (_) {}
          final String fts = '${t}_fts';
          if (!await _tableExists(shardDb, fts)) {
            throw StateError('FTS not available for table ' + t);
          }

          final List<Object?> args = <Object?>[match];
          final List<String> filters = <String>['m.is_deleted = 0'];
          if (startMillis != null || endMillis != null) {
            final int s = startMillis ?? 0;
            final int e = endMillis ?? DateTime.now().millisecondsSinceEpoch;
            filters.add('m.capture_time >= ? AND m.capture_time <= ?');
            args
              ..add(s)
              ..add(e);
          }
          if (minSize != null && maxSize != null) {
            filters.add('m.file_size >= ? AND m.file_size <= ?');
            args
              ..add(minSize)
              ..add(maxSize);
          } else if (minSize != null) {
            filters.add('m.file_size >= ?');
            args.add(minSize);
          } else if (maxSize != null) {
            filters.add('m.file_size <= ?');
            args.add(maxSize);
          }

          final String sql =
              'SELECT COUNT(*) AS c FROM ' +
              t +
              ' m JOIN ' +
              fts +
              ' f ON f.rowid = m.id ' +
              'WHERE ' +
              fts +
              ' MATCH ? AND ' +
              filters.join(' AND ');
          final List<Map<String, Object?>> rows = await (shardDb as Database)
              .rawQuery(sql, args);
          total += (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
        }
      }
      return total;
    } catch (e) {
      print('countScreenshotsByOcrForApp 失败: $e');
      rethrow;
    }
  }

  Future<int> getScreenshotCountByAppBetween(
    String appPackageName, {
    required int startMillis,
    required int endMillis,
  }) async {
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

  /// 列出指定应用所有有数据的日期（本地时区），按日期倒序返回
  /// 返回元素：{ 'date': 'YYYY-MM-DD', 'count': <int> }
  Future<List<Map<String, dynamic>>> listAvailableDaysForApp(
    String appPackageName,
  ) async {
    final Map<String, int> dayToCount = <String, int>{};
    try {
      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return <Map<String, dynamic>>[];
      for (final y in years) {
        final shardDb = await _openShardDb(appPackageName, y);
        if (shardDb == null) continue;
        for (int m = 1; m <= 12; m++) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final List<Map<String, Object?>>
            rows = await (shardDb as Database).rawQuery(
              'SELECT date(capture_time/1000, "unixepoch", "localtime") AS d, COUNT(*) AS c FROM ' +
                  t +
                  ' WHERE is_deleted = 0 GROUP BY d',
            );
            for (final r in rows) {
              final String d = (r['d'] as String?) ?? '';
              if (d.isEmpty) continue;
              final int c = (r['c'] as int?) ?? 0;
              dayToCount[d] = (dayToCount[d] ?? 0) + c;
            }
          } catch (_) {}
        }
      }
      final List<Map<String, dynamic>> out = dayToCount.entries
          .map((e) => <String, dynamic>{'date': e.key, 'count': e.value})
          .toList();
      out.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      return out;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 全局列出所有有数据的日期（本地时区），按日期倒序返回
  /// 返回元素：{ 'date': 'YYYY-MM-DD', 'count': <int> }
  Future<List<Map<String, dynamic>>> listAvailableDaysGlobal() async {
    final Map<String, int> dayToCount = <String, int>{};
    try {
      final db = await database; // 主库
      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        for (int m = 1; m <= 12; m++) {
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            final List<Map<String, Object?>>
            rows = await (shardDb as Database).rawQuery(
              'SELECT date(capture_time/1000, "unixepoch", "localtime") AS d, COUNT(*) AS c FROM ' +
                  t +
                  ' WHERE is_deleted = 0 GROUP BY d',
            );
            for (final r in rows) {
              final String d = (r['d'] as String?) ?? '';
              if (d.isEmpty) continue;
              final int c = (r['c'] as int?) ?? 0;
              dayToCount[d] = (dayToCount[d] ?? 0) + c;
            }
          } catch (_) {}
        }
      }
      final List<Map<String, dynamic>> out = dayToCount.entries
          .map((e) => <String, dynamic>{'date': e.key, 'count': e.value})
          .toList();
      out.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      return out;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  // ===================== 收藏相关方法 =====================
  Future<bool> addOrUpdateFavorite({
    required int screenshotId,
    required String appPackageName,
    String? note,
  }) async {
    final db = await database;
    try {
      await db.insert('favorites', {
        'screenshot_id': screenshotId,
        'app_package_name': appPackageName,
        'favorite_time': DateTime.now().millisecondsSinceEpoch,
        'note': note,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } catch (e) {
      print('添加收藏失败: $e');
      return false;
    }
  }

  Future<bool> removeFavorite({
    required int screenshotId,
    required String appPackageName,
  }) async {
    final db = await database;
    try {
      final result = await db.delete(
        'favorites',
        where: 'screenshot_id = ? AND app_package_name = ?',
        whereArgs: [screenshotId, appPackageName],
      );
      return result > 0;
    } catch (e) {
      print('移除收藏失败: $e');
      return false;
    }
  }

  Future<bool> isFavorite({
    required int screenshotId,
    required String appPackageName,
  }) async {
    final db = await database;
    try {
      final result = await db.query(
        'favorites',
        where: 'screenshot_id = ? AND app_package_name = ?',
        whereArgs: [screenshotId, appPackageName],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      print('检查收藏状态失败: $e');
      return false;
    }
  }

  Future<Map<int, bool>> checkFavorites({
    required List<int> screenshotIds,
    required String appPackageName,
  }) async {
    final db = await database;
    final Map<int, bool> result = {};
    if (screenshotIds.isEmpty) return result;
    try {
      final placeholders = List.filled(screenshotIds.length, '?').join(',');
      final rows = await db.query(
        'favorites',
        columns: ['screenshot_id'],
        where: 'screenshot_id IN ($placeholders) AND app_package_name = ?',
        whereArgs: [...screenshotIds, appPackageName],
      );
      final favoriteIds = rows.map((r) => r['screenshot_id'] as int).toSet();
      for (final id in screenshotIds) {
        result[id] = favoriteIds.contains(id);
      }
    } catch (e) {
      print('批量检查收藏状态失败: $e');
      for (final id in screenshotIds) {
        result[id] = false;
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getAllFavorites({
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'favorites',
        orderBy: 'favorite_time DESC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (e) {
      print('获取收藏列表失败: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<int> getFavoritesCount() async {
    final db = await database;
    try {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM favorites',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      print('获取收藏数量失败: $e');
      return 0;
    }
  }

  Future<bool> updateFavoriteNote({
    required int screenshotId,
    required String appPackageName,
    String? note,
  }) async {
    final db = await database;
    try {
      final result = await db.update(
        'favorites',
        {'note': note, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'screenshot_id = ? AND app_package_name = ?',
        whereArgs: [screenshotId, appPackageName],
      );
      return result > 0;
    } catch (e) {
      print('更新收藏备注失败: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getFavoriteDetail({
    required int screenshotId,
    required String appPackageName,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'favorites',
        where: 'screenshot_id = ? AND app_package_name = ?',
        whereArgs: [screenshotId, appPackageName],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      print('获取收藏详情失败: $e');
      return null;
    }
  }

  // ===================== NSFW 偏好表（域名规则 + 手动标记） =====================
  Future<void> _createNsfwTables(DatabaseExecutor db) async {
    // 域名禁用规则
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nsfw_domain_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pattern TEXT NOT NULL UNIQUE,
        is_wildcard INTEGER NOT NULL DEFAULT 0,
        comment TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    // 手动 NSFW 标记
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nsfw_manual_flags (
        screenshot_id INTEGER NOT NULL,
        app_package_name TEXT NOT NULL,
        flag INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        PRIMARY KEY (screenshot_id, app_package_name)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_nsfw_manual_app ON nsfw_manual_flags(app_package_name, screenshot_id)',
    );
  }

  Future<void> _createUserSettingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_settings_updated_at ON user_settings(updated_at)',
    );
  }

  // ----- 域名规则 CRUD -----
  Future<List<Map<String, dynamic>>> listNsfwDomainRules() async {
    final db = await database;
    try {
      final rows = await db.query(
        'nsfw_domain_rules',
        orderBy: 'is_wildcard DESC, pattern ASC',
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<bool> addNsfwDomainRule({
    required String pattern,
    required bool isWildcard,
    String? comment,
  }) async {
    final db = await database;
    try {
      await db.insert('nsfw_domain_rules', {
        'pattern': pattern,
        'is_wildcard': isWildcard ? 1 : 0,
        'comment': comment,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeNsfwDomainRule(String pattern) async {
    final db = await database;
    try {
      final count = await db.delete(
        'nsfw_domain_rules',
        where: 'pattern = ?',
        whereArgs: [pattern],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  Future<int> clearNsfwDomainRules() async {
    final db = await database;
    try {
      return await db.delete('nsfw_domain_rules');
    } catch (_) {
      return 0;
    }
  }

  /// 近似统计指定主域名（可选含子域）的截图数量
  Future<int> countScreenshotsMatchingDomain({
    required String host,
    required bool includeSubdomains,
  }) async {
    final db = await database;
    try {
      int total = 0;
      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      if (shards.isEmpty) return 0;

      final String hostLower = host.toLowerCase();
      final like1 = '%://' + hostLower + '/%';
      final like2 = '%.' + hostLower + '/%';
      final like3 = '%//' + hostLower + '%';
      final like4 = '%.' + hostLower + '%';

      for (final sh in shards) {
        final String pkg = sh['app_package_name'] as String;
        final int y = sh['year'] as int;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        for (int m = 1; m <= 12; m++) {
          final t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            if (includeSubdomains) {
              final rows = await shardDb.rawQuery(
                "SELECT COUNT(*) AS c FROM $t WHERE page_url IS NOT NULL AND (LOWER(page_url) LIKE ? OR LOWER(page_url) LIKE ? OR LOWER(page_url) LIKE ? OR LOWER(page_url) LIKE ?)",
                [like1, like2, like3, like4],
              );
              total += (rows.first['c'] as int?) ?? 0;
            } else {
              final rows = await shardDb.rawQuery(
                "SELECT COUNT(*) AS c FROM $t WHERE page_url IS NOT NULL AND (LOWER(page_url) LIKE ? OR LOWER(page_url) LIKE ?)",
                [like1, like3],
              );
              total += (rows.first['c'] as int?) ?? 0;
            }
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ----- 手动 NSFW 标记 -----
  Future<bool> setManualNsfwFlag({
    required int screenshotId,
    required String appPackageName,
    required bool flag,
  }) async {
    final db = await database;
    try {
      if (flag) {
        await db.insert('nsfw_manual_flags', {
          'screenshot_id': screenshotId,
          'app_package_name': appPackageName,
          'flag': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await db.delete(
          'nsfw_manual_flags',
          where: 'screenshot_id = ? AND app_package_name = ?',
          whereArgs: [screenshotId, appPackageName],
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isManuallyNsfw({
    required int screenshotId,
    required String appPackageName,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'nsfw_manual_flags',
        columns: ['flag'],
        where: 'screenshot_id = ? AND app_package_name = ?',
        whereArgs: [screenshotId, appPackageName],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      return ((rows.first['flag'] as int?) ?? 0) == 1;
    } catch (_) {
      return false;
    }
  }

  Future<int> clearManualNsfwForApp(String appPackageName) async {
    final db = await database;
    try {
      return await db.delete(
        'nsfw_manual_flags',
        where: 'app_package_name = ?',
        whereArgs: [appPackageName],
      );
    } catch (_) {
      return 0;
    }
  }

  /// 批量检查手动 NSFW 标记状态
  Future<Map<int, bool>> checkManualNsfw({
    required List<int> screenshotIds,
    required String appPackageName,
  }) async {
    final db = await database;
    final Map<int, bool> result = {};
    if (screenshotIds.isEmpty) return result;
    try {
      final placeholders = List.filled(screenshotIds.length, '?').join(',');
      final rows = await db.query(
        'nsfw_manual_flags',
        columns: ['screenshot_id'],
        where:
            'screenshot_id IN ($placeholders) AND app_package_name = ? AND flag = 1',
        whereArgs: [...screenshotIds, appPackageName],
      );
      final flagged = rows.map((r) => r['screenshot_id'] as int).toSet();
      for (final id in screenshotIds) {
        result[id] = flagged.contains(id);
      }
    } catch (e) {
      for (final id in screenshotIds) {
        result[id] = false;
      }
    }
    return result;
  }

  // ======= 汇总统计表操作 =======
  Future<Map<String, dynamic>> getTotals() async {
    final db = await database;
    try {
      final rows = await db.query('totals', where: 'id = 1', limit: 1);
      if (rows.isEmpty) {
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

  Future<void> updateTotalsOnInsert(
    List<String> packageNames,
    int screenshotCount,
    int totalSizeBytes,
  ) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        int newAppCount = 0;
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

  Future<void> recalculateTotals() async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        final appStats = await txn.query('app_stats');
        final appCount = appStats.length;
        int totalScreenshots = 0;
        int totalSizeBytes = 0;
        for (final stat in appStats) {
          totalScreenshots += (stat['total_count'] as int?) ?? 0;
          totalSizeBytes += (stat['total_size'] as int?) ?? 0;
        }
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
      });
    } catch (e) {
      print('重新计算汇总统计失败: $e');
    }
  }

  // ======= 导出/导入 =======
  Future<Map<String, dynamic>?> exportDatabaseToDownloads({
    void Function(ImportExportProgress progress)? onProgress,
  }) async {
    try {
      final base =
          await PathService.getInternalAppDir(null) ??
          await _getInternalFilesDir();
      await FlutterLogger.nativeInfo(
        'EXPORT',
        'exportDatabaseToDownloads: baseDir=' + (base?.path ?? 'null'),
      );
      if (base == null) return null;
      final outputDir = Directory(join(base.path, 'output'));
      if (!await outputDir.exists()) {
        await FlutterLogger.nativeWarn(
          'EXPORT',
          'output not found: ' + outputDir.path,
        );
        return null;
      }

      // 若未请求进度，则优先尝试原生快速导出
      if (onProgress == null) {
        try {
          await FlutterLogger.nativeInfo(
            'EXPORT',
            'try native fast exportOutputToDownloadsNative',
          );
          final dynamic fast = await ScreenshotDatabase._channel.invokeMethod(
            'exportOutputToDownloadsNative',
            <String, Object?>{
              'displayName': 'output_export.zip',
              'subDir': 'ScreenMemory',
            },
          );
          if (fast is Map) {
            final Map<String, dynamic> map = Map<String, dynamic>.from(fast);
            map['humanPath'] =
                (map['absolutePath'] as String?) ??
                (map['displayPath'] as String?);
            await FlutterLogger.nativeInfo(
              'EXPORT',
              'native fast saved to ' + (map['humanPath']?.toString() ?? ''),
            );
            return map;
          }
        } catch (e) {
          await FlutterLogger.nativeWarn(
            'EXPORT',
            'native fast path unavailable, fallback: ' + e.toString(),
          );
        }
      }

      final tmpZip = File(join(base.path, 'output_export.zip'));
      try {
        if (await tmpZip.exists()) await tmpZip.delete();
      } catch (_) {}

      await FlutterLogger.nativeInfo(
        'EXPORT',
        'fallback zip path=' + tmpZip.path,
      );
      final String outputPath = outputDir.path;
      final String tmpZipPath = tmpZip.path;
      final String? zippedPath = await _runExportZipWithProgress(
        outputDirPath: outputPath,
        tmpZipPath: tmpZipPath,
        onProgress: onProgress,
      );

      if (zippedPath == null) return null;
      await FlutterLogger.nativeInfo(
        'EXPORT',
        'fallback zip ready path=' + zippedPath,
      );

      final dynamic result = await ScreenshotDatabase._channel
          .invokeMethod('exportFileToDownloads', <String, Object?>{
        'sourcePath': zippedPath,
        'displayName': 'output_export.zip',
        'subDir': 'ScreenMemory',
      });

      try {
        await tmpZip.delete();
      } catch (_) {}

      if (result is Map) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(result);
        map['humanPath'] =
            (map['absolutePath'] as String?) ?? (map['displayPath'] as String?);
        await FlutterLogger.nativeInfo(
          'EXPORT',
          'saved to ' + (map['humanPath']?.toString() ?? ''),
        );
        return map;
      }
      await FlutterLogger.nativeWarn(
        'EXPORT',
        'exportFileToDownloads result is not Map, result=' + result.toString(),
      );
      return null;
    } catch (e) {
      print('导出output压缩包失败: $e');
      try {
        await FlutterLogger.nativeError(
          'EXPORT',
          'exportDatabaseToDownloads exception: ' + e.toString(),
        );
      } catch (_) {}
      return null;
    }
  }

  Future<Map<String, dynamic>?> importDataFromZip({
    String? zipPath,
    List<int>? zipBytes,
    bool overwrite = true,
    void Function(ImportExportProgress progress)? onProgress,
  }) async {
    return importDataFromZipStreaming(
      zipPath: zipPath,
      zipBytes: zipBytes,
      overwrite: overwrite,
      onProgress: onProgress,
    );
  }

  Future<Map<String, dynamic>?> importDataFromZipStreaming({
    String? zipPath,
    List<int>? zipBytes,
    bool overwrite = true,
    void Function(ImportExportProgress progress)? onProgress,
  }) async {
    try {
      await FlutterLogger.nativeInfo('IMPORT', '开始(流式+Isolate)');
      await FlutterLogger.nativeDebug(
        'IMPORT',
        'args path=' +
            (zipPath ?? '') +
            ' bytes=' +
            ((zipBytes?.length ?? 0).toString()),
      );
      if ((zipPath == null || zipPath.isEmpty) &&
          (zipBytes == null || zipBytes.isEmpty)) {
        await FlutterLogger.nativeWarn('IMPORT', 'no input');
        return null;
      }

      final base =
          await PathService.getInternalAppDir(null) ??
          await _getInternalFilesDir();
      if (base == null) return null;
      final outputDir = Directory(join(base.path, 'output'));
      await FlutterLogger.nativeInfo('IMPORT', 'baseDir=' + base.path);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
        await FlutterLogger.nativeInfo(
          'IMPORT',
          'created outputDir=' + outputDir.path,
        );
      }

      try {
        // 导入前清理缓存目录，避免旧缓存占用空间并与新数据混淆
        await _clearOutputCacheDirs(outputDir);
      } catch (_) {}

      try {
        await _resetDatabasesAfterImport();
      } catch (_) {}

      String localZipPath;
      File? tmpZipFile;
      if (zipPath != null && zipPath.isNotEmpty) {
        localZipPath = zipPath;
      } else {
        final tmpDir = await getTemporaryDirectory();
        tmpZipFile = File(join(tmpDir.path, 'screenmemo_import_tmp.zip'));
        try {
          if (await tmpZipFile.exists()) await tmpZipFile.delete();
        } catch (_) {}
        await tmpZipFile.writeAsBytes(zipBytes!, flush: true);
        localZipPath = tmpZipFile.path;
      }

      final Map<String, dynamic>? res = await _runImportZipWithProgress(
        localZipPath: localZipPath,
        outputDirPath: outputDir.path,
        overwrite: overwrite,
        onProgress: onProgress,
      );

      try {
        if (tmpZipFile != null) await tmpZipFile.delete();
        // 如果是从 FilePicker 之类复制到临时目录的缓存 ZIP（zipPath 在临时目录下），导入后也一并删除
        if (tmpZipFile == null && zipPath != null && zipPath.isNotEmpty) {
          try {
            final Directory tmpDir = await getTemporaryDirectory();
            final String tmpRoot = tmpDir.path;
            if (zipPath.startsWith(tmpRoot)) {
              final File cachedZip = File(zipPath);
              if (await cachedZip.exists()) {
                await cachedZip.delete();
                await FlutterLogger.nativeInfo(
                  'IMPORT',
                  'deleted cached import zip: ' + zipPath,
                );
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
      try {
        await _resetDatabasesAfterImport();
      } catch (_) {}

      await FlutterLogger.nativeInfo(
        'IMPORT',
        '完成(流式+Isolate) 解压=' +
            ((res?['extracted'] as int?) ?? 0).toString() +
            ' 目标=' +
            outputDir.path,
      );
      return res;
    } catch (e) {
      await FlutterLogger.nativeError('IMPORT', '异常(流式): ' + e.toString());
      return null;
    }
  }

  Future<Directory?> _getInternalFilesDir() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return dir;
    } catch (e) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        return dir;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _resetDatabasesAfterImport() async {
    try {
      if (ScreenshotDatabase._shardDbCache.isNotEmpty) {
        for (final db in ScreenshotDatabase._shardDbCache.values) {
          try {
            await db.close();
          } catch (_) {}
        }
        ScreenshotDatabase._shardDbCache.clear();
      }
      if (ScreenshotDatabase._database != null) {
        try {
          await ScreenshotDatabase._database!.close();
        } catch (_) {}
        ScreenshotDatabase._database = null;
      }
    } catch (_) {}
  }

  /// 清理 output 目录下的缓存子目录，避免导入后旧缓存占用空间
  Future<void> _clearOutputCacheDirs(Directory outputDir) async {
    final List<String> names = <String>['cache', 'tmp', 'temp', '.thumbnails'];
    for (final String name in names) {
      final Directory d = Directory(join(outputDir.path, name));
      try {
        if (await d.exists()) {
          await d.delete(recursive: true);
          await FlutterLogger.nativeInfo(
            'IMPORT',
            'cleared cache dir: ' + d.path,
          );
        }
      } catch (_) {}
    }
  }
}

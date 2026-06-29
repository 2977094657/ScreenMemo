part of 'screenshot_database.dart';

const Set<String> _outputCacheDirNames = <String>{
  'cache',
  'tmp',
  'temp',
  '.thumbnails',
};

const String _mainDatabaseArchivePath = 'output/databases/screenshot_memo.db';

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

/// 全量备份导出的 Isolate 入口
Future<void> _exportBackupZipIsolateEntry(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'] as SendPort;
  final String tmpZipPath = args['tmpZipPath'] as String;
  final String manifestPath = args['manifestPath'] as String;
  final List<dynamic> rawEntries = (args['entries'] as List?) ?? <dynamic>[];
  final ReceivePort controlPort = ReceivePort();
  StreamSubscription<dynamic>? controlSub;
  bool cancelled = false;

  try {
    controlSub = controlPort.listen((dynamic message) {
      if (message == 'cancel') {
        cancelled = true;
      }
    });
    sendPort.send(<String, Object?>{
      'type': 'ready',
      'controlPort': controlPort.sendPort,
    });

    final ZipFileEncoder encoder = ZipFileEncoder();
    bool encoderClosed = false;
    try {
      final File manifestFile = File(manifestPath);
      if (!manifestFile.existsSync()) {
        throw StateError('backup_manifest_missing:$manifestPath');
      }

      encoder.create(tmpZipPath, level: 0);
      await encoder.addFile(
        manifestFile,
        backupManifestFileName,
        ZipFileEncoder.STORE,
      );

      int completedBytes = 0;
      for (final dynamic rawEntry in rawEntries) {
        if (cancelled) {
          sendPort.send(<String, Object?>{'type': 'cancelled'});
          return;
        }
        if (rawEntry is! Map) {
          continue;
        }

        final String sourcePath = rawEntry['sourcePath']?.toString() ?? '';
        final String archivePath = rawEntry['archivePath']?.toString() ?? '';
        final String categoryId = rawEntry['categoryId']?.toString() ?? '';
        final int entryBytes = (rawEntry['bytes'] as num?)?.toInt() ?? 0;
        if (sourcePath.isEmpty || archivePath.isEmpty || categoryId.isEmpty) {
          continue;
        }

        final File source = File(sourcePath);
        if (!source.existsSync()) {
          throw StateError('backup_source_missing:$archivePath');
        }
        final int actualBytes = source.lengthSync();
        if (categoryId == BackupCategoryIds.mainDatabase &&
            entryBytes > 0 &&
            actualBytes <= 0) {
          throw StateError(
            'backup_main_database_empty:$archivePath:expected=$entryBytes:actual=$actualBytes',
          );
        }

        sendPort.send(<String, Object?>{
          'type': 'entryStart',
          'completedBytes': completedBytes,
          'entryBytes': entryBytes,
          'categoryId': categoryId,
          'entry': archivePath,
        });
        await encoder.addFile(source, archivePath, ZipFileEncoder.STORE);
        completedBytes += entryBytes;
        sendPort.send(<String, Object?>{
          'type': 'progress',
          'completedBytes': completedBytes,
          'entryBytes': entryBytes,
          'categoryId': categoryId,
          'entry': archivePath,
        });
      }

      if (cancelled) {
        sendPort.send(<String, Object?>{'type': 'cancelled'});
        return;
      }

      encoder.close();
      encoderClosed = true;
      sendPort.send(<String, Object?>{'type': 'done'});
    } finally {
      if (!encoderClosed) {
        try {
          encoder.close();
        } catch (_) {}
      }
    }
  } catch (e) {
    sendPort.send(<String, Object?>{'type': 'error', 'error': e.toString()});
  } finally {
    await controlSub?.cancel();
    controlPort.close();
  }
}

/// 导入解压的 Isolate 入口
Future<void> _importZipIsolateEntry(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'] as SendPort;
  final String localZipPath = args['zipPath'] as String;
  final Map<String, String> targetRoots = Map<String, String>.from(
    (args['targetRoots'] as Map?) ?? const <String, String>{},
  );
  final bool overwrite = (args['overwrite'] as bool?) ?? true;
  final bool skipMissingTargets =
      (args['skipMissingTargets'] as bool?) ?? false;
  final bool treatDatabasesAsOutputWhenNoManifest =
      (args['treatDatabasesAsOutputWhenNoManifest'] as bool?) ?? false;

  try {
    final InputFileStream input = InputFileStream(localZipPath);
    final Archive archive = ZipDecoder().decodeBuffer(input);
    final BackupArchiveInspection inspection =
        BackupInventoryService.inspectArchiveEntries(
          archive.files.map((ArchiveFile file) => file.name),
        );

    final List<ArchiveFile> files = archive.files
        .where(
          (ArchiveFile f) =>
              f.isFile &&
              f.name.replaceAll('\\', '/') != backupManifestFileName,
        )
        .toList();
    final int total = files.length;
    if (total == 0) {
      input.close();
      sendPort.send(<String, Object?>{
        'type': 'done',
        'extracted': 0,
        'restoredRoots': inspection.rootEntries.toList(),
        'requiresRestart': inspection.manifestRequiresRestart,
      });
      return;
    }

    int extracted = 0;
    final Set<String> restoredRoots = <String>{};
    sendPort.send(<String, Object?>{
      'type': 'progress',
      'progress': 0.0,
      'stage': 'extracting',
      'entry': null,
    });

    const int kProgressEveryFiles = 50;
    const int kProgressEveryMs = 150;
    final Stopwatch progressThrottle = Stopwatch()..start();
    int lastProgressIndex = -1;

    for (int i = 0; i < files.length; i++) {
      final ArchiveFile f = files[i];
      final String normalizedEntry = normalize(
        f.name,
      ).replaceAll('\\', '/').trimLeft();
      if (normalizedEntry.isEmpty ||
          normalizedEntry == backupManifestFileName) {
        continue;
      }

      String? rootEntry = BackupInventoryService.rootEntryForArchivePath(
        normalizedEntry,
      );
      String relativePath;
      if (rootEntry == null) {
        if (inspection.hasManifest) {
          throw StateError('unsupported_backup_root:$normalizedEntry');
        }
        rootEntry = 'output';
        relativePath = normalizedEntry;
      } else {
        if (rootEntry == backupManifestFileName) {
          continue;
        }
        relativePath = normalizedEntry.length == rootEntry.length
            ? ''
            : normalizedEntry.substring(rootEntry.length + 1);
      }

      final String rel = _normalizeBackupImportRelativePath(relativePath);
      if (rel.isEmpty) {
        continue;
      }
      if (BackupInventoryService.shouldSkipImportedRelativePath(
        rootEntry,
        rel,
      )) {
        continue;
      }

      String effectiveRootEntry = rootEntry;
      String effectiveRel = rel;
      String? destRootPath = targetRoots[effectiveRootEntry];
      if ((destRootPath == null || destRootPath.isEmpty) &&
          !inspection.hasManifest &&
          treatDatabasesAsOutputWhenNoManifest &&
          rootEntry == 'databases') {
        final String? outputRootPath = targetRoots['output'];
        if (outputRootPath != null && outputRootPath.isNotEmpty) {
          effectiveRootEntry = 'output';
          effectiveRel = _normalizeBackupImportRelativePath('databases/$rel');
          destRootPath = outputRootPath;
        }
      }
      if (destRootPath == null || destRootPath.isEmpty) {
        if (inspection.hasManifest &&
            (!skipMissingTargets || rootEntry == 'output')) {
          throw StateError('missing_import_target:$rootEntry');
        }
        continue;
      }

      final String destPath = join(destRootPath, effectiveRel);
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
          restoredRoots.add(effectiveRootEntry);
        }
      }

      final bool isLast = i == total - 1;
      final bool shouldSend =
          isLast ||
          (i - lastProgressIndex) >= kProgressEveryFiles ||
          progressThrottle.elapsedMilliseconds >= kProgressEveryMs;
      if (shouldSend) {
        final double progress = (i + 1) / total;
        sendPort.send(<String, Object?>{
          'type': 'progress',
          'progress': progress.clamp(0.0, 1.0),
          'stage': 'extracting',
          'entry': effectiveRel,
        });
        lastProgressIndex = i;
        progressThrottle.reset();
      }
    }

    input.close();

    sendPort.send(<String, Object?>{
      'type': 'done',
      'extracted': extracted,
      'restoredRoots': restoredRoots.toList(),
      'requiresRestart':
          inspection.manifestRequiresRestart ||
          restoredRoots.any((String root) => root != 'output'),
    });
  } catch (e) {
    sendPort.send(<String, Object?>{'type': 'error', 'error': e.toString()});
  }
}

String _escapeSqliteStringLiteral(String input) => input.replaceAll("'", "''");

Future<({BackupInventory inventory, Directory? stagingDir})>
_prepareInventoryForExport({
  required BackupInventory inventory,
  required Directory tempDir,
}) async {
  final BackupInventoryCategory? mainCategory = inventory.categoryById(
    BackupCategoryIds.mainDatabase,
  );
  if (mainCategory == null || mainCategory.files.isEmpty) {
    return (inventory: inventory, stagingDir: null);
  }

  BackupInventoryFile? mainDbEntry;
  for (final BackupInventoryFile file in mainCategory.files) {
    if (file.archivePath == _mainDatabaseArchivePath) {
      mainDbEntry = file;
      break;
    }
  }
  if (mainDbEntry == null) {
    return (inventory: inventory, stagingDir: null);
  }

  final String timestamp = DateTime.now().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
  final Directory stageDir = Directory(
    join(tempDir.path, 'screen_memo_backup_stage_$timestamp'),
  );
  await stageDir.create(recursive: true);

  try {
    final Database db = await ScreenshotDatabase.instance.database;
    final File snapshotFile = File(
      join(stageDir.path, 'output', 'databases', 'screenshot_memo.db'),
    );
    await snapshotFile.parent.create(recursive: true);
    if (await snapshotFile.exists()) {
      await snapshotFile.delete();
    }

    await FlutterLogger.nativeInfo(
      'EXPORT',
      '准备主库快照：source=${mainDbEntry.sourcePath}, expectedBytes=${mainDbEntry.bytes}',
    );
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE);');
    } catch (_) {}
    await db.execute(
      "VACUUM INTO '${_escapeSqliteStringLiteral(snapshotFile.path)}'",
    );
    final int snapshotBytes = await snapshotFile.length();
    if (mainDbEntry.bytes > 0 && snapshotBytes <= 0) {
      throw StateError(
        'backup_main_database_snapshot_empty:${snapshotFile.path}',
      );
    }

    await FlutterLogger.nativeInfo(
      'EXPORT',
      '主库快照完成：snapshot=${snapshotFile.path}, bytes=$snapshotBytes',
    );
    final BackupInventoryCategory replacement = BackupInventoryCategory(
      id: mainCategory.id,
      files: <BackupInventoryFile>[
        BackupInventoryFile(
          sourcePath: snapshotFile.path,
          archivePath: _mainDatabaseArchivePath,
          bytes: snapshotBytes,
          categoryId: BackupCategoryIds.mainDatabase,
        ),
      ],
      totalBytes: snapshotBytes,
      fileCount: 1,
    );
    return (
      inventory: _replaceInventoryCategory(inventory, replacement),
      stagingDir: stageDir,
    );
  } catch (e) {
    await FlutterLogger.nativeWarn('EXPORT', '主库 VACUUM 快照失败，回退到文件复制：$e');

    final List<BackupInventoryFile> stagedFiles = <BackupInventoryFile>[];
    for (final BackupInventoryFile file in mainCategory.files) {
      final File source = File(file.sourcePath);
      if (!await source.exists()) {
        throw StateError('backup_source_missing:${file.archivePath}');
      }
      final File dest = File(
        joinAll(<String>[stageDir.path, ...file.archivePath.split('/')]),
      );
      await dest.parent.create(recursive: true);
      if (await dest.exists()) {
        await dest.delete();
      }
      await source.copy(dest.path);
      final int copiedBytes = await dest.length();
      if (file.archivePath == _mainDatabaseArchivePath &&
          file.bytes > 0 &&
          copiedBytes <= 0) {
        throw StateError(
          'backup_main_database_copy_empty:${file.archivePath}:expected=${file.bytes}:actual=$copiedBytes',
        );
      }
      stagedFiles.add(
        BackupInventoryFile(
          sourcePath: dest.path,
          archivePath: file.archivePath,
          bytes: copiedBytes,
          categoryId: file.categoryId,
        ),
      );
    }

    final int totalBytes = stagedFiles.fold<int>(
      0,
      (int sum, BackupInventoryFile file) => sum + file.bytes,
    );
    await FlutterLogger.nativeInfo(
      'EXPORT',
      '主库文件复制快照完成：files=${stagedFiles.length}, bytes=$totalBytes',
    );
    final BackupInventoryCategory replacement = BackupInventoryCategory(
      id: mainCategory.id,
      files: List<BackupInventoryFile>.unmodifiable(stagedFiles),
      totalBytes: totalBytes,
      fileCount: stagedFiles.length,
    );
    return (
      inventory: _replaceInventoryCategory(inventory, replacement),
      stagingDir: stageDir,
    );
  }
}

BackupInventory _replaceInventoryCategory(
  BackupInventory inventory,
  BackupInventoryCategory replacement,
) {
  final List<BackupInventoryCategory> categories = inventory.categories
      .map(
        (BackupInventoryCategory category) =>
            category.id == replacement.id ? replacement : category,
      )
      .where((BackupInventoryCategory category) => category.fileCount > 0)
      .toList(growable: false);
  final int totalBytes = categories.fold<int>(
    0,
    (int sum, BackupInventoryCategory category) => sum + category.totalBytes,
  );
  final int totalFiles = categories.fold<int>(
    0,
    (int sum, BackupInventoryCategory category) => sum + category.fileCount,
  );
  return BackupInventory(
    roots: inventory.roots,
    categories: categories,
    excludedItems: inventory.excludedItems,
    totalBytes: totalBytes,
    totalFiles: totalFiles,
    warnings: inventory.warnings,
  );
}

Future<void> _runBackupExportZipWithProgress({
  required BackupInventory inventory,
  required String manifestPath,
  required String tmpZipPath,
  void Function(
    int completedBytes,
    String categoryId,
    String currentEntry,
    int entryBytes,
  )?
  onEntryStart,
  required void Function(
    int completedBytes,
    String categoryId,
    String currentEntry,
    int entryBytes,
  )
  onProgress,
  bool Function()? shouldCancel,
}) async {
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[
    for (final BackupInventoryCategory category in inventory.categories)
      for (final BackupInventoryFile entry in category.files)
        <String, Object?>{
          'sourcePath': entry.sourcePath,
          'archivePath': entry.archivePath,
          'bytes': entry.bytes,
          'categoryId': entry.categoryId,
        },
  ];

  final ReceivePort receivePort = ReceivePort();
  Isolate? iso;
  Timer? cancelTimer;
  try {
    iso = await Isolate.spawn<Map<String, dynamic>>(
      _exportBackupZipIsolateEntry,
      <String, dynamic>{
        'sendPort': receivePort.sendPort,
        'manifestPath': manifestPath,
        'tmpZipPath': tmpZipPath,
        'entries': entries,
      },
    );

    final Completer<void> completer = Completer<void>();
    SendPort? controlPort;
    bool cancelRequested = false;
    bool cancelSignalSent = false;
    void requestCancel() {
      cancelRequested = true;
      if (cancelSignalSent || controlPort == null) {
        return;
      }
      cancelSignalSent = true;
      controlPort?.send('cancel');
    }

    late final StreamSubscription<dynamic> sub;
    sub = receivePort.listen((dynamic message) {
      if (message is! Map) {
        return;
      }
      final String? type = message['type'] as String?;
      switch (type) {
        case 'ready':
          final dynamic rawPort = message['controlPort'];
          if (rawPort is SendPort) {
            controlPort = rawPort;
          }
          if (cancelRequested || shouldCancel?.call() == true) {
            requestCancel();
          }
          break;
        case 'progress':
          final int completedBytes =
              (message['completedBytes'] as num?)?.toInt() ?? 0;
          final int entryBytes = (message['entryBytes'] as num?)?.toInt() ?? 0;
          final String categoryId = message['categoryId']?.toString() ?? '';
          final String currentEntry = message['entry']?.toString() ?? '';
          if (categoryId.isNotEmpty && currentEntry.isNotEmpty) {
            onProgress(completedBytes, categoryId, currentEntry, entryBytes);
          }
          if (shouldCancel?.call() == true) {
            requestCancel();
          }
          break;
        case 'entryStart':
          final int completedBytes =
              (message['completedBytes'] as num?)?.toInt() ?? 0;
          final int entryBytes = (message['entryBytes'] as num?)?.toInt() ?? 0;
          final String categoryId = message['categoryId']?.toString() ?? '';
          final String currentEntry = message['entry']?.toString() ?? '';
          if (categoryId.isNotEmpty && currentEntry.isNotEmpty) {
            onEntryStart?.call(
              completedBytes,
              categoryId,
              currentEntry,
              entryBytes,
            );
          }
          if (shouldCancel?.call() == true) {
            requestCancel();
          }
          break;
        case 'done':
          if (!completer.isCompleted) {
            completer.complete();
          }
          break;
        case 'cancelled':
          if (!completer.isCompleted) {
            completer.completeError(const BackupExportCancelledException());
          }
          break;
        case 'error':
          if (!completer.isCompleted) {
            completer.completeError(
              Exception(message['error'] as String? ?? 'backup zip failed'),
            );
          }
          break;
      }
    });

    cancelTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (shouldCancel?.call() == true) {
        requestCancel();
      }
    });

    try {
      await completer.future;
    } finally {
      cancelTimer.cancel();
      await sub.cancel();
      receivePort.close();
      iso.kill(priority: Isolate.immediate);
    }
  } catch (e) {
    cancelTimer?.cancel();
    receivePort.close();
    iso?.kill(priority: Isolate.immediate);
    rethrow;
  }
}

String _normalizeBackupImportRelativePath(String raw) {
  String sanitized = raw.replaceAll('\\', '/').trim();
  while (sanitized.startsWith('./')) {
    sanitized = sanitized.substring(2);
  }
  sanitized = sanitized.replaceFirst(RegExp(r'^/+'), '');
  if (sanitized.isEmpty) {
    return '';
  }
  final List<String> parts = sanitized.split('/');
  final List<String> result = <String>[];
  for (final String part in parts) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      return '';
    }
    result.add(part);
  }
  return result.join('/');
}

/// 导入解压的帮助函数：在主 Isolate 中管理进度与结果
Future<Map<String, dynamic>?> _runImportZipWithProgress({
  required String localZipPath,
  required Map<String, String> targetRoots,
  required bool overwrite,
  void Function(ImportExportProgress progress)? onProgress,
  bool skipMissingTargets = false,
  bool treatDatabasesAsOutputWhenNoManifest = false,
}) async {
  final ReceivePort receivePort = ReceivePort();
  Isolate? iso;
  try {
    iso = await Isolate.spawn<Map<String, dynamic>>(
      _importZipIsolateEntry,
      <String, dynamic>{
        'sendPort': receivePort.sendPort,
        'zipPath': localZipPath,
        'targetRoots': targetRoots,
        'overwrite': overwrite,
        'skipMissingTargets': skipMissingTargets,
        'treatDatabasesAsOutputWhenNoManifest':
            treatDatabasesAsOutputWhenNoManifest,
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
            'restoredRoots': List<String>.from(
              (message['restoredRoots'] as List?) ?? const <String>[],
            ),
            'requiresRestart': message['requiresRestart'] == true,
          });
        }
      } else if (type == 'error') {
        if (!completer.isCompleted) {
          FlutterLogger.nativeError(
            'IMPORT',
            'zip isolate error: ' + (message['error'] as String? ?? 'unknown'),
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
      final Map<int, List<Map<String, Object?>>> shardsByYear =
          <int, List<Map<String, Object?>>>{};
      for (final sh in shards) {
        final int y = sh['year'] as int;
        (shardsByYear[y] ??= <Map<String, Object?>>[]).add(sh);
      }
      final List<List<int>> scanYearMonths = <List<int>>[];
      final Set<String> seenYm = <String>{};
      void addScanYearMonth(int y, int m) {
        final String key = '$y-$m';
        if (seenYm.add(key)) scanYearMonths.add(<int>[y, m]);
      }

      if (ymFilter != null) {
        for (final ym in ymFilter) {
          addScanYearMonth(ym[0], ym[1]);
        }
      } else {
        final years = shardsByYear.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        for (final y in years) {
          for (int m = 12; m >= 1; m--) {
            addScanYearMonth(y, m);
          }
        }
      }
      scanYearMonths.sort((a, b) {
        final int yc = b[0].compareTo(a[0]);
        if (yc != 0) return yc;
        return b[1].compareTo(a[1]);
      });

      outer:
      for (final ym in scanYearMonths) {
        final int y = ym[0];
        final int m = ym[1];
        final yearShards = shardsByYear[y] ?? const <Map<String, Object?>>[];
        for (final sh in yearShards) {
          final String pkg = sh['app_package_name'] as String;
          final shardDb = await _openShardDb(pkg, y);
          if (shardDb == null) continue;
          final String appName = appNameCache[pkg] ?? pkg;
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
            final List<Map<String, Object?>> maps = await shardDb.rawQuery(
              sql,
              args,
            );
            for (final mapp in maps) {
              final full = Map<String, dynamic>.from(mapp);
              full['app_package_name'] = pkg;
              full['app_name'] = appName;
              final localId = (mapp['id'] as int?) ?? 0;
              full['id'] = _encodeGid(y, m, localId);
              rows.add(full);
            }
          } catch (_) {}
        }
        if (rows.length >= target) break outer;
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
      final db = await database;
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
              ymFilter
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
            final List<Map<String, Object?>> rows = await shardDb.rawQuery(
              sql,
              args,
            );
            total += (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<List<ScreenshotRecord>> searchScreenshotsByOcrLikeForApp(
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
      final String q = query.trim().toLowerCase();
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
        if (r.isNotEmpty) {
          appName = (r.first['app_name'] as String?) ?? appPackageName;
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
      final years = await _listShardYearsForApp(appPackageName);
      if (years.isEmpty) return <ScreenshotRecord>[];

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
    } catch (_) {
      return <ScreenshotRecord>[];
    }
  }

  Future<int> countScreenshotsByOcrLikeForApp(
    String appPackageName,
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

  /// 获取全局最新截图时间戳（毫秒）
  ///
  /// 读取自主库 `app_stats.last_capture_time` 的聚合值，避免扫描分库。
  Future<int?> getGlobalLatestCaptureTimeMillis() async {
    final db = await database; // 主库
    try {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT MAX(last_capture_time) AS m FROM app_stats',
      );
      if (rows.isEmpty) return null;
      final Object? m = rows.first['m'];
      if (m == null) return null;
      if (m is int) return m;
      if (m is num) return m.toInt();
      return int.tryParse(m.toString());
    } catch (_) {
      return null;
    }
  }

  /// 获取指定应用最新截图时间戳（毫秒）
  ///
  /// 读取主库 `app_stats.last_capture_time`，避免为日期 Tab 初始化扫描分库。
  Future<int?> getLatestCaptureTimeMillisForApp(String appPackageName) async {
    final String packageName = appPackageName.trim();
    if (packageName.isEmpty) return null;
    final db = await database; // 主库
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'app_stats',
        columns: const <String>['last_capture_time'],
        where: 'app_package_name = ?',
        whereArgs: <Object?>[packageName],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final Object? value = rows.first['last_capture_time'];
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    } catch (_) {
      return null;
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

  /// 列出所有存在截图分库的应用包名。
  ///
  /// 全局历史压缩需要以包为单位更新分库记录与统计，因此这里直接以
  /// shard_registry 为准，不依赖可能缺失或延迟更新的 app_registry。
  Future<List<String>> listPackagesWithScreenshotShards() async {
    final db = await database;
    try {
      final rows = await db.rawQuery(
        'SELECT DISTINCT app_package_name FROM shard_registry ORDER BY app_package_name ASC',
      );
      return rows
          .map((row) => (row['app_package_name'] as String?)?.trim())
          .whereType<String>()
          .where((pkg) => pkg.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      print('listPackagesWithScreenshotShards 失败: $e');
      return <String>[];
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

  /// 全局：按 bucket 抽样获取给定时间范围内的截图帧（所有应用，按时间正序）
  ///
  /// - `bucketMillis` 会将范围按 `(capture_time - startMillis) / bucketMillis` 分桶。
  /// - 每个桶取 `MIN(capture_time)` 的那一条（尽量取最早帧，便于正序回放）。
  /// - 该方法返回的是候选帧集合；上层仍需按全局 bucket 去重/裁剪到目标帧数。
  Future<List<ScreenshotRecord>> getGlobalScreenshotsBucketedBetween({
    required int startMillis,
    required int endMillis,
    required int bucketMillis,
  }) async {
    final db = await database; // 主库
    try {
      if (endMillis < startMillis) return <ScreenshotRecord>[];
      final int bucket = bucketMillis <= 0 ? 1 : bucketMillis;

      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
      final DateTime s = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final DateTime e = DateTime.fromMillisecondsSinceEpoch(endMillis);
      final ymList = _listYearMonthBetween(s, e);

      final shards = await db.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
        orderBy: 'year DESC',
      );
      if (shards.isEmpty) return <ScreenshotRecord>[];

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
            // 每个 bucket 取最早的一帧；返回 t.* 以兼容未来字段变更。
            final sql =
                '''
              SELECT t.*
              FROM $t t
              JOIN (
                SELECT CAST((capture_time - ?) / ? AS INTEGER) AS b, MIN(capture_time) AS min_ct
                FROM $t
                WHERE capture_time >= ? AND capture_time <= ? AND is_deleted = 0
                GROUP BY b
              ) x
              ON CAST((t.capture_time - ?) / ? AS INTEGER) = x.b AND t.capture_time = x.min_ct
              WHERE t.capture_time >= ? AND t.capture_time <= ? AND t.is_deleted = 0
              ORDER BY t.capture_time ASC
            ''';
            final args = <Object?>[
              startMillis,
              bucket,
              startMillis,
              endMillis,
              startMillis,
              bucket,
              startMillis,
              endMillis,
            ];
            final maps = await (shardDb as Database).rawQuery(sql, args);
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
        return ta.compareTo(tb);
      });

      return rows.map((m) => ScreenshotRecord.fromMap(m)).toList();
    } catch (e) {
      print('getGlobalScreenshotsBucketedBetween 失败: $e');
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
      if (shardDb == null) {
        await _deleteFavoriteRowsForScreenshots(db, packageName, <int>[id]);
        return true;
      }
      final tableName = _monthTableName(year, month);
      if (!await _tableExists(shardDb, tableName)) {
        await _deleteFavoriteRowsForScreenshots(db, packageName, <int>[id]);
        return true;
      }
      final maps = await shardDb.query(
        tableName,
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (maps.isEmpty) {
        await _deleteFavoriteRowsForScreenshots(db, packageName, <int>[id]);
        return true;
      }
      final filePath = maps.first['file_path'] as String;
      final result = await shardDb.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (result <= 0) return false;
      await _deleteScreenshotPathLookupByPath(db, filePath);
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          FlutterLogger.nativeInfo('FS', '已删除文件：' + filePath);
        }
      } catch (e) {
        FlutterLogger.nativeWarn('FS', '删除文件失败：' + e.toString());
      }
      await _deleteFavoriteRowsForScreenshots(db, packageName, <int>[id]);
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
      await _deleteFavoriteRowsForScreenshots(db, packageName, ids);
      await _deleteScreenshotPathLookupsByPaths(db, filePaths);
      await _deleteFilesConcurrently(filePaths, maxConcurrent: 6);

      sw.stop();
      FlutterLogger.nativeInfo('TOTAL', '批量删除总耗时 ${sw.elapsedMilliseconds}毫秒');
      return deletedTotal;
    } catch (e) {
      print('批量删除截屏记录失败: $e');
      return 0;
    }
  }

  Future<void> _deleteFavoriteRowsForScreenshots(
    DatabaseExecutor db,
    String appPackageName,
    Iterable<int> screenshotIds,
  ) async {
    final List<int> ids = screenshotIds
        .where((int id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;

    const int chunkSize = 900;
    for (int i = 0; i < ids.length; i += chunkSize) {
      final List<int> chunk = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      final String placeholders = List.filled(chunk.length, '?').join(',');
      try {
        await db.delete(
          'favorites',
          where: 'app_package_name = ? AND screenshot_id IN ($placeholders)',
          whereArgs: <Object>[appPackageName, ...chunk],
        );
      } catch (e) {
        print('删除截图关联收藏失败: $e');
      }

      for (final int id in chunk) {
        try {
          await deleteSearchDoc(
            _favoriteNoteDocKey(appPackageName, id),
            exec: db,
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _deleteAllFavoriteRowsForApp(
    DatabaseExecutor db,
    String appPackageName,
  ) async {
    try {
      await db.delete(
        'favorites',
        where: 'app_package_name = ?',
        whereArgs: <Object>[appPackageName],
      );
    } catch (e) {
      print('删除应用关联收藏失败: $e');
    }
    try {
      await db.delete(
        'search_docs',
        where: 'doc_type = ? AND doc_key LIKE ?',
        whereArgs: <Object>[
          kSearchDocTypeFavoriteNote,
          'fav_note:${appPackageName.trim().toLowerCase()}:%',
        ],
      );
    } catch (_) {}
  }

  Future<void> _deleteFavoriteRowsExceptScreenshots(
    DatabaseExecutor db,
    String appPackageName,
    Iterable<int> keepScreenshotIds,
  ) async {
    final Set<int> keep = keepScreenshotIds.where((int id) => id > 0).toSet();
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'favorites',
        columns: const <String>['screenshot_id'],
        where: 'app_package_name = ?',
        whereArgs: <Object>[appPackageName],
      );
      final List<int> deleteIds = <int>[];
      for (final Map<String, Object?> row in rows) {
        final int id = (row['screenshot_id'] as int?) ?? 0;
        if (id > 0 && !keep.contains(id)) {
          deleteIds.add(id);
        }
      }
      await _deleteFavoriteRowsForScreenshots(db, appPackageName, deleteIds);
    } catch (e) {
      print('清理非保留截图收藏失败: $e');
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
      await _deleteAllFavoriteRowsForApp(db, appPackageName);
      await _deleteScreenshotPathLookupsByPackage(db, appPackageName);

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
      final List<String> deletedPaths = <String>[];
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
              try {
                final pathRows = await shardDb.query(
                  t,
                  columns: const <String>['file_path'],
                );
                for (final row in pathRows) {
                  final String p = ((row['file_path'] as String?) ?? '').trim();
                  if (p.isNotEmpty) deletedPaths.add(p);
                }
              } catch (_) {}
              await shardDb.execute('DROP TABLE IF EXISTS $t');
              deletedTotal += c;
            } else {
              final placeholders = List.filled(keepSet.length, '?').join(',');
              try {
                final pathRows = await shardDb.query(
                  t,
                  columns: const <String>['file_path'],
                  where: 'id NOT IN ($placeholders)',
                  whereArgs: keepSet.toList(),
                );
                for (final row in pathRows) {
                  final String p = ((row['file_path'] as String?) ?? '').trim();
                  if (p.isNotEmpty) deletedPaths.add(p);
                }
              } catch (_) {}
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
      await _deleteFavoriteRowsExceptScreenshots(db, packageName, keepIds);
      await _deleteScreenshotPathLookupsByPaths(db, deletedPaths);
      return deletedTotal;
    } catch (e) {
      print('删除非保留记录失败: $e');
      return 0;
    }
  }

  Future<ScreenshotRecord?> getScreenshotByPath(String filePath) async {
    final Stopwatch sw = Stopwatch()..start();
    final db = await database; // 主库
    int yearsChecked = 0;
    int tablesChecked = 0;
    try {
      int? asInt(Object? value) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        return int.tryParse('${value ?? ''}');
      }

      final Map<String, Object?>? indexed =
          await _readScreenshotPathLookupByPath(db, filePath);
      final String indexedPackageName =
          ((indexed?['app_package_name'] as String?) ?? '').trim();
      final int? indexedCaptureTime = asInt(indexed?['capture_time']);
      final packageName = indexedPackageName.isNotEmpty
          ? indexedPackageName
          : _extractPackageNameFromPath(filePath);
      if (packageName == null) {
        print('无法从路径推断包名: $filePath');
        _logDatabaseAiChatPerf(
          'EvidenceRecord.getByPath.skip',
          stopwatch: sw,
          detail: 'reason=noPackage path=$filePath',
        );
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

      Future<ScreenshotRecord?> readFromShard({
        required int year,
        required int month,
        required String stage,
      }) async {
        final shardDb = await _openShardDb(packageName, year);
        if (shardDb == null) return null;
        final t = _monthTableName(year, month);
        if (!await _tableExists(shardDb, t)) return null;
        tablesChecked += 1;
        try {
          final maps = await shardDb.query(
            t,
            columns: const [
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
          if (maps.isEmpty) return null;
          final full = Map<String, dynamic>.from(maps.first);
          full['app_package_name'] = packageName;
          full['app_name'] = appName;
          full['id'] = _encodeGid(year, month, (maps.first['id'] as int?) ?? 0);
          await _upsertScreenshotPathLookup(
            db,
            filePath: filePath,
            appPackageName: packageName,
            captureTime: asInt(maps.first['capture_time']),
          );
          _logDatabaseAiChatPerf(
            'EvidenceRecord.getByPath.hit',
            stopwatch: sw,
            detail:
                'stage=$stage package=$packageName year=$year month=$month years=$yearsChecked tables=$tablesChecked path=$filePath',
          );
          return ScreenshotRecord.fromMap(full);
        } catch (_) {
          return null;
        }
      }

      if (indexedCaptureTime != null && indexedCaptureTime > 0) {
        yearsChecked += 1;
        final int indexedYear = _yearFromMillis(indexedCaptureTime);
        final int indexedMonth = _monthFromMillis(indexedCaptureTime);
        final ScreenshotRecord? indexedRecord = await readFromShard(
          year: indexedYear,
          month: indexedMonth,
          stage: 'path_lookup',
        );
        if (indexedRecord != null) return indexedRecord;
      }

      final years = await _listShardYearsForApp(packageName);
      for (final y in years) {
        yearsChecked += 1;
        for (int m = 12; m >= 1; m--) {
          final ScreenshotRecord? record = await readFromShard(
            year: y,
            month: m,
            stage: 'scan',
          );
          if (record != null) return record;
        }
      }
      if (indexed != null) {
        await _deleteScreenshotPathLookupByPath(db, filePath);
      }
      _logDatabaseAiChatPerf(
        'EvidenceRecord.getByPath.miss',
        stopwatch: sw,
        detail:
            'package=$packageName years=$yearsChecked tables=$tablesChecked path=$filePath',
      );
      return null;
    } catch (e) {
      print('根据路径查询截屏记录失败: $e');
      _logDatabaseAiChatPerf(
        'EvidenceRecord.getByPath.error',
        stopwatch: sw,
        detail:
            'years=$yearsChecked tables=$tablesChecked path=$filePath err=$e',
      );
      return null;
    }
  }

  /// 批量读取截图 OCR 文本（按 segment_samples 的字段：file_path/app_package_name/capture_time）。
  ///
  /// - 返回值 key 为 file_path（与入参一致）
  /// - 仅返回非空 OCR（trim 后长度 > 0）
  /// - 通过 capture_time 计算 year/month 定位分库分表，避免对所有表进行全量扫描
  Future<Map<String, String>> getOcrTextBySampleRows(
    List<Map<String, dynamic>> sampleRows,
  ) async {
    final Map<String, String> out = <String, String>{};
    if (sampleRows.isEmpty) return out;

    int? asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    final Map<String, Map<int, Map<int, Set<String>>>> grouped =
        <String, Map<int, Map<int, Set<String>>>>{};

    for (final Map<String, dynamic> row in sampleRows) {
      final String pkg = ((row['app_package_name'] as String?) ?? '').trim();
      final String path = ((row['file_path'] as String?) ?? '').trim();
      final int? ts = asInt(row['capture_time']);
      if (pkg.isEmpty || path.isEmpty || ts == null || ts <= 0) continue;

      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
      final int year = dt.year;
      final int month = dt.month;
      if (year <= 1970 || month < 1 || month > 12) continue;

      grouped
          .putIfAbsent(pkg, () => <int, Map<int, Set<String>>>{})
          .putIfAbsent(year, () => <int, Set<String>>{})
          .putIfAbsent(month, () => <String>{})
          .add(path);
    }

    if (grouped.isEmpty) return out;

    // SQLite 参数默认上限 999，这里保守分批。
    const int chunkSize = 400;

    for (final pkgEntry in grouped.entries) {
      final String pkg = pkgEntry.key;
      for (final yearEntry in pkgEntry.value.entries) {
        final int year = yearEntry.key;
        final shardDb = await _openShardDb(pkg, year);
        if (shardDb == null) continue;

        for (final monthEntry in yearEntry.value.entries) {
          final int month = monthEntry.key;
          final String table = _monthTableName(year, month);
          if (!await _tableExists(shardDb, table)) continue;

          final List<String> paths = monthEntry.value.toList(growable: false);
          if (paths.isEmpty) continue;

          for (int i = 0; i < paths.length; i += chunkSize) {
            final int end = (i + chunkSize) > paths.length
                ? paths.length
                : (i + chunkSize);
            final List<String> chunk = paths.sublist(i, end);
            final String placeholders = List.filled(
              chunk.length,
              '?',
            ).join(',');

            try {
              final List<Map<String, Object?>> rows = await shardDb.query(
                table,
                columns: const <String>['file_path', 'ocr_text'],
                where:
                    'file_path IN ($placeholders) AND ocr_text IS NOT NULL AND LENGTH(ocr_text) > 0',
                whereArgs: chunk,
              );
              for (final r in rows) {
                final String? p = r['file_path'] as String?;
                if (p == null || p.trim().isEmpty) continue;
                final String t = ((r['ocr_text'] as String?) ?? '').trim();
                if (t.isEmpty) continue;
                out[p.trim()] = t;
              }
            } catch (_) {}
          }
        }
      }
    }

    return out;
  }

  /// 通过文件名在所有分库中查找截图的绝对路径（找到一条即返回）
  Future<String?> findScreenshotPathByBasename(String filename) async {
    final Stopwatch sw = Stopwatch()..start();
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
      final bool hasExtension = ext != null && ext.isNotEmpty;
      final Set<String> extCandidates = <String>{};
      if (hasExtension) extCandidates.add(ext!);
      extCandidates.addAll(<String>{'jpg', 'jpeg', 'png', 'webp'});
      final master = await database;
      int segmentQueries = 0;
      int segmentRows = 0;
      int shardPackages = 0;
      int shardYears = 0;
      int shardTables = 0;
      int shardQueries = 0;
      int shardRows = 0;
      int fsEntries = 0;

      String counts() =>
          'segmentQueries=$segmentQueries segmentRows=$segmentRows shardPackages=$shardPackages shardYears=$shardYears shardTables=$shardTables shardQueries=$shardQueries shardRows=$shardRows fsEntries=$fsEntries';

      int? asInt(Object? value) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        return int.tryParse('${value ?? ''}');
      }

      Future<String?> hit(
        String stage,
        String path, {
        String? extra,
        String? appPackageName,
        int? captureTime,
        bool remember = true,
      }) async {
        if (remember) {
          await _upsertScreenshotPathLookup(
            master,
            filePath: path,
            appPackageName: appPackageName,
            captureTime: captureTime,
          );
        }
        _logDatabaseAiChatPerf(
          'EvidencePath.findByBasename.hit',
          stopwatch: sw,
          detail:
              'stage=$stage name=$name base=$base path=$path ${counts()} ${extra ?? ''}',
        );
        return path;
      }

      String? miss(String stage, {String? extra}) {
        _logDatabaseAiChatPerf(
          'EvidencePath.findByBasename.miss',
          stopwatch: sw,
          detail:
              'stage=$stage name=$name base=$base ${counts()} ${extra ?? ''}',
        );
        return null;
      }

      _logDatabaseAiChatPerf(
        'EvidencePath.findByBasename.start',
        detail: 'name=$name base=$base exts=${extCandidates.join("|")}',
      );

      final String? indexedPath = await _pickExistingScreenshotPathLookup(
        master,
        filename: name,
        base: base,
        hasExtension: hasExtension,
      );
      if (indexedPath != null && indexedPath.isNotEmpty) {
        return await hit('path_lookup', indexedPath, remember: false);
      }

      // 先在 segment_samples（主库）中搜索，按可能扩展名匹配
      for (final e in extCandidates) {
        try {
          segmentQueries += 1;
          final rows = await master.query(
            'segment_samples',
            columns: ['file_path', 'app_package_name', 'capture_time'],
            where: "file_path LIKE ? ESCAPE '\\'",
            whereArgs: ['%${_escapeSqlLikePattern('$base.$e')}'],
            // 同名文件可能跨天重复（文件名仅 HHmmss_SSS）；按时间倒序取一批并优先返回仍存在的文件，
            // 以避免 UI 退出/进入后解析到已被清理的旧路径。
            orderBy: 'capture_time DESC, id DESC',
            limit: 20,
          );
          segmentRows += rows.length;
          for (final r in rows) {
            final p = (r['file_path'] as String?) ?? '';
            if (p.isEmpty) continue;
            try {
              if (await File(p).exists()) {
                return await hit(
                  'segment_samples',
                  p,
                  extra: 'ext=$e',
                  appPackageName: (r['app_package_name'] as String?)?.trim(),
                  captureTime: asInt(r['capture_time']),
                );
              }
            } catch (_) {
              // ignore
            }
          }
        } catch (_) {}
      }

      // 兼容：聊天引用可能是 segment_id（纯数字），而不是文件名。
      // 这种情况下，尝试从 segment_samples 中取该段的一张“代表截图”（优先 keyframe）。
      final int? segmentId = int.tryParse(base);
      if (segmentId != null && segmentId > 0) {
        Future<Map<String, Object?>?> pickSegmentSampleRow({
          required bool keyframesOnly,
        }) async {
          try {
            final String where = keyframesOnly
                ? 'segment_id = ? AND is_keyframe = 1'
                : 'segment_id = ?';
            final List<Map<String, Object?>> stats = await master.rawQuery(
              'SELECT MIN(position_index) AS minp, MAX(position_index) AS maxp FROM segment_samples WHERE $where',
              <Object?>[segmentId],
            );
            if (stats.isEmpty) return null;
            final int? minp = stats.first['minp'] as int?;
            final int? maxp = stats.first['maxp'] as int?;
            if (minp == null || maxp == null) return null;
            final int target = ((minp + maxp) / 2).round();

            final List<Map<String, Object?>> pick = await master.rawQuery(
              'SELECT file_path, app_package_name, capture_time FROM segment_samples WHERE $where ORDER BY ABS(position_index - ?) ASC, position_index ASC LIMIT 1',
              <Object?>[segmentId, target],
            );
            if (pick.isEmpty) return null;
            final String p = (pick.first['file_path'] as String?) ?? '';
            return p.isEmpty ? null : pick.first;
          } catch (_) {
            return null;
          }
        }

        final Map<String, Object?>? keyframeRow = await pickSegmentSampleRow(
          keyframesOnly: true,
        );
        final String keyframePath =
            ((keyframeRow?['file_path'] as String?) ?? '').trim();
        if (keyframePath.isNotEmpty) {
          return await hit(
            'segment_sample_keyframe',
            keyframePath,
            appPackageName: (keyframeRow?['app_package_name'] as String?)
                ?.trim(),
            captureTime: asInt(keyframeRow?['capture_time']),
          );
        }

        final Map<String, Object?>? anyRow = await pickSegmentSampleRow(
          keyframesOnly: false,
        );
        final String anyPath = ((anyRow?['file_path'] as String?) ?? '').trim();
        if (anyPath.isNotEmpty) {
          return await hit(
            'segment_sample_any',
            anyPath,
            appPackageName: (anyRow?['app_package_name'] as String?)?.trim(),
            captureTime: asInt(anyRow?['capture_time']),
          );
        }

        // 兜底：若该段没有 segment_samples（例如仅有 AI 结果、样本表为空/被清理），
        // 则尝试用 segments 的时间窗在分库截图表中挑一张“最接近中间时间”的截图作为代表。
        final String? shardPicked =
            await _pickRepresentativeScreenshotPathForSegment(segmentId);
        if (shardPicked != null && shardPicked.isNotEmpty) {
          return await hit('segment_representative_shard', shardPicked);
        }
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
      if (packages.isEmpty) return miss('no_packages');

      for (final pkg in packages) {
        shardPackages += 1;
        final years = await _listShardYearsForApp(pkg);
        for (final y in years) {
          shardYears += 1;
          final shardDb = await _openShardDb(pkg, y);
          if (shardDb == null) continue;
          for (int m = 12; m >= 1; m--) {
            final t = _monthTableName(y, m);
            if (!await _tableExists(shardDb, t)) continue;
            shardTables += 1;
            try {
              for (final e in extCandidates) {
                final pattern = '%${_escapeSqlLikePattern('$base.$e')}';
                shardQueries += 1;
                final rows = await shardDb.query(
                  t,
                  columns: ['file_path', 'capture_time'],
                  where: "file_path LIKE ? ESCAPE '\\'",
                  whereArgs: [pattern],
                  orderBy: 'capture_time DESC, id DESC',
                  limit: 20,
                );
                shardRows += rows.length;
                for (final r in rows) {
                  final p = (r['file_path'] as String?) ?? '';
                  if (p.isEmpty) continue;
                  try {
                    if (await File(p).exists()) {
                      return await hit(
                        'shard_like',
                        p,
                        appPackageName: pkg,
                        captureTime: asInt(r['capture_time']),
                        extra: 'package=$pkg year=$y month=$m ext=$e',
                      );
                    }
                  } catch (_) {
                    // ignore
                  }
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
          _logDatabaseAiChatPerf(
            'EvidencePath.findByBasename.filesystem.start',
            stopwatch: sw,
            detail: 'name=$name base=$base root=${root.path} ${counts()}',
          );
          final ent = root.list(recursive: true, followLinks: false);
          await for (final e in ent) {
            fsEntries += 1;
            if (e is File) {
              final String pth = e.path;
              for (final ex in extCandidates) {
                if (pth.endsWith('/' + base + '.' + ex) ||
                    pth.endsWith('\\' + base + '.' + ex) ||
                    pth.endsWith(base + '.' + ex)) {
                  return await hit('filesystem_scan', pth, extra: 'ext=$ex');
                }
              }
            }
          }
        }
      } catch (_) {}
      return miss('not_found');
    } catch (e) {
      _logDatabaseAiChatPerf(
        'EvidencePath.findByBasename.error',
        stopwatch: sw,
        detail: 'filename=$filename err=$e',
      );
      return null;
    }
  }

  List<String> _splitCsv(String raw) => raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  Future<String?> _pickRepresentativeScreenshotPathForSegment(
    int segmentId,
  ) async {
    try {
      final master = await database;
      final segRows = await master.query(
        'segments',
        columns: const <String>['start_time', 'end_time', 'app_packages'],
        where: 'id = ?',
        whereArgs: <Object?>[segmentId],
        limit: 1,
      );
      if (segRows.isEmpty) return null;
      final int startMillis = (segRows.first['start_time'] as int?) ?? 0;
      final int endMillis0 = (segRows.first['end_time'] as int?) ?? 0;
      if (startMillis <= 0 || endMillis0 <= 0) return null;
      final int endMillis = endMillis0 >= startMillis
          ? endMillis0
          : startMillis;
      final int midMillis = ((startMillis + endMillis) / 2).round();

      final String pkgsRaw =
          (segRows.first['app_packages'] as String?)?.trim() ?? '';
      final List<String> pkgs = pkgsRaw.isEmpty
          ? const <String>[]
          : _splitCsv(pkgsRaw);

      final DateTime ds = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final DateTime de = DateTime.fromMillisecondsSinceEpoch(endMillis);
      final List<List<int>> ymList = _listYearMonthBetween(ds, de);

      String? bestPath;
      int bestDiff = 1 << 62;

      void considerCandidate(String path, int captureTime) {
        if (path.trim().isEmpty) return;
        final int diff = (captureTime - midMillis).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestPath = path;
        }
      }

      Future<void> considerFromTable(Database shardDb, String table) async {
        List<Map<String, Object?>> rows = const <Map<String, Object?>>[];

        // <= mid (before)
        try {
          rows = await shardDb.rawQuery(
            'SELECT file_path, capture_time FROM $table WHERE capture_time >= ? AND capture_time <= ? AND is_deleted = 0 AND capture_time <= ? ORDER BY capture_time DESC LIMIT 1',
            <Object?>[startMillis, endMillis, midMillis],
          );
        } catch (_) {
          try {
            rows = await shardDb.rawQuery(
              'SELECT file_path, capture_time FROM $table WHERE capture_time >= ? AND capture_time <= ? AND capture_time <= ? ORDER BY capture_time DESC LIMIT 1',
              <Object?>[startMillis, endMillis, midMillis],
            );
          } catch (_) {
            rows = const <Map<String, Object?>>[];
          }
        }
        if (rows.isNotEmpty) {
          final String p = (rows.first['file_path'] as String?) ?? '';
          final int t = (rows.first['capture_time'] as int?) ?? 0;
          if (p.isNotEmpty && t > 0) considerCandidate(p, t);
        }

        // >= mid (after)
        try {
          rows = await shardDb.rawQuery(
            'SELECT file_path, capture_time FROM $table WHERE capture_time >= ? AND capture_time <= ? AND is_deleted = 0 AND capture_time >= ? ORDER BY capture_time ASC LIMIT 1',
            <Object?>[startMillis, endMillis, midMillis],
          );
        } catch (_) {
          try {
            rows = await shardDb.rawQuery(
              'SELECT file_path, capture_time FROM $table WHERE capture_time >= ? AND capture_time <= ? AND capture_time >= ? ORDER BY capture_time ASC LIMIT 1',
              <Object?>[startMillis, endMillis, midMillis],
            );
          } catch (_) {
            rows = const <Map<String, Object?>>[];
          }
        }
        if (rows.isNotEmpty) {
          final String p = (rows.first['file_path'] as String?) ?? '';
          final int t = (rows.first['capture_time'] as int?) ?? 0;
          if (p.isNotEmpty && t > 0) considerCandidate(p, t);
        }
      }

      // 优先：若 segments.app_packages 给出了应用集合，则仅在这些应用的分库中寻找
      if (pkgs.isNotEmpty) {
        for (final pkg in pkgs) {
          final years = await _listShardYearsForApp(pkg);
          if (years.isEmpty) continue;
          for (final ym in ymList) {
            final int y = ym[0];
            final int m = ym[1];
            if (!years.contains(y)) continue;
            final shardDb = await _openShardDb(pkg, y);
            if (shardDb == null) continue;
            final String t = _monthTableName(y, m);
            if (!await _tableExists(shardDb, t)) continue;
            await considerFromTable(shardDb, t);
          }
        }
        return bestPath;
      }

      // 兜底：未知应用时，全局扫描 shard_registry（仅扫描时间窗涉及的 year）
      final shardRows = await master.query(
        'shard_registry',
        columns: const <String>['app_package_name', 'year'],
        distinct: true,
      );
      if (shardRows.isEmpty) return null;
      for (final sh in shardRows) {
        final String pkg = (sh['app_package_name'] as String?) ?? '';
        final int y = (sh['year'] as int?) ?? 0;
        if (pkg.isEmpty || y <= 0) continue;
        final bool containsYear = ymList.any((ym) => ym[0] == y);
        if (!containsYear) continue;
        final shardDb = await _openShardDb(pkg, y);
        if (shardDb == null) continue;
        for (final ym in ymList) {
          final int year = ym[0];
          final int month = ym[1];
          if (year != y) continue;
          final String t = _monthTableName(year, month);
          if (!await _tableExists(shardDb, t)) continue;
          await considerFromTable(shardDb, t);
        }
      }

      return bestPath;
    } catch (_) {
      return null;
    }
  }

  /// 批量：通过文件名集合查找路径映射
  Future<Map<String, String>> findPathsByBasenames(
    Set<String> filenames,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    final Map<String, String> result = <String, String>{};
    _logDatabaseAiChatPerf(
      'EvidencePath.findMany.start',
      detail: 'names=${filenames.length}',
    );
    for (final name in filenames) {
      final p = await findScreenshotPathByBasename(name);
      if (p != null && p.isNotEmpty) result[name] = p;
    }
    _logDatabaseAiChatPerf(
      'EvidencePath.findMany.done',
      stopwatch: sw,
      detail: 'names=${filenames.length} found=${result.length}',
    );
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
      if (result > 0) {
        await _upsertScreenshotPathLookup(
          db,
          filePath: record.filePath,
          appPackageName: record.appPackageName,
          captureTime: record.captureTime.millisecondsSinceEpoch,
        );
        return true;
      }
      return false;
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
    bool matchAllTerms = true,
    bool rankByRelevance = false,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database; // 主库
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
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
      final Map<int, List<Map<String, Object?>>> shardsByYear =
          <int, List<Map<String, Object?>>>{};
      for (final sh in shards) {
        final int y = sh['year'] as int;
        (shardsByYear[y] ??= <Map<String, Object?>>[]).add(sh);
      }

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
      final List<List<int>> scanYearMonths = <List<int>>[];
      final Set<String> seenYm = <String>{};
      void addScanYearMonth(int y, int m) {
        final String key = '$y-$m';
        if (seenYm.add(key)) scanYearMonths.add(<int>[y, m]);
      }

      if (ymFilter != null) {
        for (final ym in ymFilter) {
          addScanYearMonth(ym[0], ym[1]);
        }
      } else {
        final years = shardsByYear.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        for (final y in years) {
          for (int m = 12; m >= 1; m--) {
            addScanYearMonth(y, m);
          }
        }
      }
      scanYearMonths.sort((a, b) {
        final int yc = b[0].compareTo(a[0]);
        if (yc != 0) return yc;
        return b[1].compareTo(a[1]);
      });

      outer:
      for (final ym in scanYearMonths) {
        final int y = ym[0];
        final int m = ym[1];
        final yearShards = shardsByYear[y] ?? const <Map<String, Object?>>[];
        for (final sh in yearShards) {
          final String pkg = sh['app_package_name'] as String;
          final shardDb = await _openShardDb(pkg, y);
          if (shardDb == null) continue;
          final String appName = appNameCache[pkg] ?? pkg;
          final String t = _monthTableName(y, m);
          if (!await _tableExists(shardDb, t)) continue;
          try {
            // 尝试优先 FTS：确保当月FTS存在（首次会自动回填）
            try {
              await _ensureMonthFts(shardDb, y, m);
            } catch (_) {}

            final String match = ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: matchAllTerms,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
            final String matchEff = (adv != null)
                ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
                : match;

            // 组合 SQL：fts JOIN 主表并应用过滤
            final String fts = '${t}_fts';
            // 禁止回退：如未成功创建/存在 FTS 表，直接抛错
            final bool ftsExists = await _tableExists(shardDb, fts);
            if (!ftsExists) {
              throw StateError('FTS not available for table ' + t);
            }
            final List<Object?> args = <Object?>[matchEff];
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

            final String sqlTime =
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
            final String sqlRank =
                'SELECT m.*, bm25(' +
                fts +
                ') AS fts_rank FROM ' +
                t +
                ' m JOIN ' +
                fts +
                ' f ON f.rowid = m.id ' +
                'WHERE ' +
                fts +
                ' MATCH ? AND ' +
                filters.join(' AND ') +
                ' ' +
                'ORDER BY fts_rank ASC, m.capture_time DESC LIMIT ?';

            args.add(perTableLimit);
            List<Map<String, Object?>> maps;
            if (rankByRelevance) {
              try {
                maps = await (shardDb as Database).rawQuery(sqlRank, args);
              } catch (_) {
                maps = await (shardDb as Database).rawQuery(sqlTime, args);
              }
            } else {
              maps = await (shardDb as Database).rawQuery(sqlTime, args);
            }
            for (final mapp in maps) {
              final full = Map<String, dynamic>.from(mapp);
              full['app_package_name'] = pkg;
              full['app_name'] = appName;
              final localId = (mapp['id'] as int?) ?? 0;
              full['id'] = _encodeGid(y, m, localId);
              rows.add(full);
            }
          } catch (_) {}
        }
        if (rows.length >= target) break outer;
      }

      rows.sort((a, b) {
        if (rankByRelevance) {
          final double ra =
              (a['fts_rank'] as num?)?.toDouble() ?? double.infinity;
          final double rb =
              (b['fts_rank'] as num?)?.toDouble() ?? double.infinity;
          if (ra != rb) return ra.compareTo(rb);
        }
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
    bool matchAllTerms = true,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database; // 主库
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
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

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: matchAllTerms,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );

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
    bool matchAllTerms = true,
    bool rankByRelevance = false,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database; // 主库
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
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

            final String match = ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: matchAllTerms,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
            final String matchEff = (adv != null)
                ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
                : match;

            final String fts = '${t}_fts';
            final bool ftsExists = await _tableExists(shardDb, fts);
            if (!ftsExists) {
              throw StateError('FTS not available for table ' + t);
            }
            final List<Object?> args = <Object?>[matchEff];
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
            final String sqlTime =
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
            final String sqlRank =
                'SELECT m.*, bm25(' +
                fts +
                ') AS fts_rank FROM ' +
                t +
                ' m JOIN ' +
                fts +
                ' f ON f.rowid = m.id ' +
                'WHERE ' +
                fts +
                ' MATCH ? AND ' +
                filters.join(' AND ') +
                ' ' +
                'ORDER BY fts_rank ASC, m.capture_time DESC LIMIT ?';
            args.add(perTableLimit);

            List<Map<String, Object?>> maps;
            if (rankByRelevance) {
              try {
                maps = await (shardDb as Database).rawQuery(sqlRank, args);
              } catch (_) {
                maps = await (shardDb as Database).rawQuery(sqlTime, args);
              }
            } else {
              maps = await (shardDb as Database).rawQuery(sqlTime, args);
            }
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
        if (rankByRelevance) {
          final double ra =
              (a['fts_rank'] as num?)?.toDouble() ?? double.infinity;
          final double rb =
              (b['fts_rank'] as num?)?.toDouble() ?? double.infinity;
          if (ra != rb) return ra.compareTo(rb);
        }
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
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database; // 主库
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
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

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: true,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );

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
}

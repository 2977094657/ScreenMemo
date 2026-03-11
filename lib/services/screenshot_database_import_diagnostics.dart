part of 'screenshot_database.dart';

enum ImportDiagnosticsLevel { ok, warn, error }

class ImportDiagnosticsPaths {
  final String? baseDirPath;
  final String? outputDirPath;

  final String? expectedMasterDbPath;
  final bool expectedMasterDbExists;
  final int expectedMasterDbSizeBytes;

  final String? openedMasterDbPath;
  final bool openedMasterDbPathMatchesExpected;

  const ImportDiagnosticsPaths({
    required this.baseDirPath,
    required this.outputDirPath,
    required this.expectedMasterDbPath,
    required this.expectedMasterDbExists,
    required this.expectedMasterDbSizeBytes,
    required this.openedMasterDbPath,
    required this.openedMasterDbPathMatchesExpected,
  });
}

class ImportDiagnosticsFilesystem {
  final bool outputDirExists;

  final String? screenDirPath;
  final bool screenDirExists;
  final int screenPackageDirCount;
  final List<String> samplePackages;

  final String? shardsDirPath;
  final bool shardsDirExists;
  final int shardDbFileCount;
  final int shardSmmDbFileCount;
  final List<String> sampleShardDbFiles;
  final List<String> sampleShardSmmDbFiles;

  const ImportDiagnosticsFilesystem({
    required this.outputDirExists,
    required this.screenDirPath,
    required this.screenDirExists,
    required this.screenPackageDirCount,
    required this.samplePackages,
    required this.shardsDirPath,
    required this.shardsDirExists,
    required this.shardDbFileCount,
    required this.shardSmmDbFileCount,
    required this.sampleShardDbFiles,
    required this.sampleShardSmmDbFiles,
  });
}

class ImportDiagnosticsDatabase {
  final bool openOk;
  final String? openError;

  final int? userVersion;

  /// tableName -> exists
  final Map<String, bool> tableExists;

  /// tableName -> rowCount (null means failed to query)
  final Map<String, int?> tableRowCounts;

  const ImportDiagnosticsDatabase({
    required this.openOk,
    required this.openError,
    required this.userVersion,
    required this.tableExists,
    required this.tableRowCounts,
  });
}

class ImportDiagnosticsTimeline {
  final int lookbackDays;
  final int? latestCaptureMillis;
  final int rangeStartMillis;
  final int rangeEndMillis;
  final int availableDays;
  final List<String> sampleDays;

  const ImportDiagnosticsTimeline({
    required this.lookbackDays,
    required this.latestCaptureMillis,
    required this.rangeStartMillis,
    required this.rangeEndMillis,
    required this.availableDays,
    required this.sampleDays,
  });
}

class ImportDiagnosticsOcr {
  final int totalRowsInRange;
  final int rowsWithOcrInRange;
  final int rowsMissingOcrInRange;
  final List<String> sampleMissingPaths;

  const ImportDiagnosticsOcr({
    required this.totalRowsInRange,
    required this.rowsWithOcrInRange,
    required this.rowsMissingOcrInRange,
    required this.sampleMissingPaths,
  });
}

class ImportDiagnosticsReport {
  final int timestampMillis;
  final int durationMs;
  final ImportDiagnosticsLevel level;

  final ImportDiagnosticsPaths paths;
  final ImportDiagnosticsFilesystem filesystem;
  final ImportDiagnosticsDatabase database;
  final ImportDiagnosticsTimeline timeline;
  final ImportDiagnosticsOcr ocr;

  final List<String> warnings;
  final List<String> errors;
  final List<String> suggestions;

  /// Whether a safe "repair index" action is likely to help.
  final bool canRepairIndex;
  final bool canRepairOcr;

  const ImportDiagnosticsReport({
    required this.timestampMillis,
    required this.durationMs,
    required this.level,
    required this.paths,
    required this.filesystem,
    required this.database,
    required this.timeline,
    required this.ocr,
    required this.warnings,
    required this.errors,
    required this.suggestions,
    required this.canRepairIndex,
    required this.canRepairOcr,
  });

  String toText() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('ScreenMemo 导入诊断');
    sb.writeln('运行时间: ${_fmtTime(timestampMillis)}');
    sb.writeln('耗时: ${durationMs}ms');
    sb.writeln('状态: ${_levelLabel(level)}');
    sb.writeln();

    sb.writeln('[路径]');
    sb.writeln('baseDir: ${paths.baseDirPath ?? '(null)'}');
    sb.writeln('outputDir: ${paths.outputDirPath ?? '(null)'}');
    sb.writeln(
      'expectedMasterDb: ${paths.expectedMasterDbPath ?? '(null)'} (exists=${paths.expectedMasterDbExists} size=${paths.expectedMasterDbSizeBytes})',
    );
    sb.writeln(
      'openedMasterDb: ${paths.openedMasterDbPath ?? '(null)'} (matchesExpected=${paths.openedMasterDbPathMatchesExpected})',
    );
    sb.writeln();

    sb.writeln('[文件]');
    sb.writeln('outputDirExists: ${filesystem.outputDirExists}');
    sb.writeln(
      'screenDir: ${filesystem.screenDirPath ?? '(null)'} (exists=${filesystem.screenDirExists} packages=${filesystem.screenPackageDirCount} sample=${filesystem.samplePackages.join(', ')})',
    );
    sb.writeln(
      'shardsDir: ${filesystem.shardsDirPath ?? '(null)'} (exists=${filesystem.shardsDirExists} dbFiles=${filesystem.shardDbFileCount} sample=${filesystem.sampleShardDbFiles.join(', ')})',
    );
    sb.writeln(
      'shardSmmDbFiles: ${filesystem.shardSmmDbFileCount} sample=${filesystem.sampleShardSmmDbFiles.join(', ')}',
    );
    sb.writeln();

    sb.writeln('[数据库]');
    sb.writeln('openOk: ${database.openOk}');
    if (!database.openOk && database.openError != null) {
      sb.writeln('openError: ${database.openError}');
    }
    sb.writeln('userVersion: ${database.userVersion?.toString() ?? '(null)'}');
    for (final String t in database.tableExists.keys) {
      final bool ex = database.tableExists[t] ?? false;
      final int? c = database.tableRowCounts[t];
      sb.writeln('table $t: exists=$ex rows=${c?.toString() ?? '(n/a)'}');
    }
    sb.writeln();

    sb.writeln('[时间线自检]');
    sb.writeln('lookbackDays: ${timeline.lookbackDays}');
    sb.writeln(
      'latestCapture: ${timeline.latestCaptureMillis == null ? '(null)' : _fmtTime(timeline.latestCaptureMillis!)}',
    );
    sb.writeln(
      'range: ${_fmtTime(timeline.rangeStartMillis)} ~ ${_fmtTime(timeline.rangeEndMillis)}',
    );
    sb.writeln(
      'availableDays: ${timeline.availableDays} sample=${timeline.sampleDays.join(', ')}',
    );
    sb.writeln();

    sb.writeln('[OCR 自检]');
    sb.writeln('rowsInRange: ${ocr.totalRowsInRange}');
    sb.writeln('rowsWithOcr: ${ocr.rowsWithOcrInRange}');
    sb.writeln('rowsMissingOcr: ${ocr.rowsMissingOcrInRange}');
    sb.writeln('sampleMissing: ${ocr.sampleMissingPaths.join(', ')}');
    sb.writeln();

    if (warnings.isNotEmpty) {
      sb.writeln('[警告]');
      for (final w in warnings) {
        sb.writeln('- $w');
      }
      sb.writeln();
    }

    if (errors.isNotEmpty) {
      sb.writeln('[错误]');
      for (final e in errors) {
        sb.writeln('- $e');
      }
      sb.writeln();
    }

    sb.writeln('[建议]');
    if (suggestions.isEmpty) {
      sb.writeln('- 未发现明显异常（如仍无数据，建议到日志面板搜索 IMPORT/DB 进一步排查）');
    } else {
      for (final s in suggestions) {
        sb.writeln('- $s');
      }
    }

    return sb.toString().trimRight();
  }
}

class ImportRepairReport {
  final int timestampMillis;
  final int durationMs;

  final int packageCount;
  final int pairCount;
  final int shardRegistryUpserted;
  final int shardRegistrySkippedMissingDb;

  /// How many shard DB files were created from screen files (when missing).
  final int shardDbCreated;

  /// How many screenshot rows were inserted into shard DBs (best-effort count).
  final int shardRowsInserted;

  final List<String> warnings;
  final List<String> errors;

  const ImportRepairReport({
    required this.timestampMillis,
    required this.durationMs,
    required this.packageCount,
    required this.pairCount,
    required this.shardRegistryUpserted,
    required this.shardRegistrySkippedMissingDb,
    required this.shardDbCreated,
    required this.shardRowsInserted,
    required this.warnings,
    required this.errors,
  });

  String toText() {
    final sb = StringBuffer();
    sb.writeln('ScreenMemo 导入索引修复');
    sb.writeln('运行时间: ${_fmtTime(timestampMillis)}');
    sb.writeln('耗时: ${durationMs}ms');
    sb.writeln('packages: $packageCount');
    sb.writeln('pairs(pkg/year): $pairCount');
    sb.writeln('shard_registry upserted: $shardRegistryUpserted');
    sb.writeln('skipped(missing shard db): $shardRegistrySkippedMissingDb');
    sb.writeln('created shard db(from screen): $shardDbCreated');
    sb.writeln('inserted rows(from screen): $shardRowsInserted');
    if (warnings.isNotEmpty) {
      sb.writeln();
      sb.writeln('[警告]');
      for (final w in warnings) sb.writeln('- $w');
    }
    if (errors.isNotEmpty) {
      sb.writeln();
      sb.writeln('[错误]');
      for (final e in errors) sb.writeln('- $e');
    }
    return sb.toString().trimRight();
  }
}

class ImportOcrRepairReport {
  final int timestampMillis;
  final int durationMs;
  final int candidateRows;
  final int processedRows;
  final int updatedRows;
  final int emptyTextRows;
  final int failedRows;
  final int missingFiles;
  final List<String> warnings;
  final List<String> errors;

  const ImportOcrRepairReport({
    required this.timestampMillis,
    required this.durationMs,
    required this.candidateRows,
    required this.processedRows,
    required this.updatedRows,
    required this.emptyTextRows,
    required this.failedRows,
    required this.missingFiles,
    required this.warnings,
    required this.errors,
  });

  String toText() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('ScreenMemo 导入图片文字修复');
    sb.writeln('运行时间: ${_fmtTime(timestampMillis)}');
    sb.writeln('耗时: ${durationMs}ms');
    sb.writeln('候选记录: $candidateRows');
    sb.writeln('已处理: $processedRows');
    sb.writeln('写入 OCR: $updatedRows');
    sb.writeln('识别为空: $emptyTextRows');
    sb.writeln('失败: $failedRows');
    sb.writeln('缺失文件: $missingFiles');
    if (warnings.isNotEmpty) {
      sb.writeln();
      sb.writeln('[警告]');
      for (final String w in warnings) {
        sb.writeln('- $w');
      }
    }
    if (errors.isNotEmpty) {
      sb.writeln();
      sb.writeln('[错误]');
      for (final String e in errors) {
        sb.writeln('- $e');
      }
    }
    return sb.toString().trimRight();
  }
}

class ImportOcrRepairTaskStatus {
  final String taskId;
  final String status;
  final bool onlyMissing;
  final int batchSize;
  final int startedAt;
  final int updatedAt;
  final int completedAt;
  final int candidateRows;
  final int processedRows;
  final int updatedRows;
  final int emptyTextRows;
  final int failedRows;
  final int missingFiles;
  final int currentWorkIndex;
  final int currentLastId;
  final String currentPackageName;
  final int currentYear;
  final String currentTableName;
  final int totalWorks;
  final String? lastError;
  final List<String> warnings;
  final List<String> errors;
  final bool isActive;
  final String progressPercent;

  const ImportOcrRepairTaskStatus({
    required this.taskId,
    required this.status,
    required this.onlyMissing,
    required this.batchSize,
    required this.startedAt,
    required this.updatedAt,
    required this.completedAt,
    required this.candidateRows,
    required this.processedRows,
    required this.updatedRows,
    required this.emptyTextRows,
    required this.failedRows,
    required this.missingFiles,
    required this.currentWorkIndex,
    required this.currentLastId,
    required this.currentPackageName,
    required this.currentYear,
    required this.currentTableName,
    required this.totalWorks,
    required this.lastError,
    required this.warnings,
    required this.errors,
    required this.isActive,
    required this.progressPercent,
  });

  factory ImportOcrRepairTaskStatus.fromMap(Map<dynamic, dynamic>? map) {
    final data = map == null ? const <dynamic, dynamic>{} : map;
    final String? lastErrorRaw = (data['lastError'] as String?)?.trim();
    return ImportOcrRepairTaskStatus(
      taskId: (data['taskId'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'idle',
      onlyMissing: data['onlyMissing'] == true,
      batchSize: _safeIntStatic(data['batchSize']),
      startedAt: _safeIntStatic(data['startedAt']),
      updatedAt: _safeIntStatic(data['updatedAt']),
      completedAt: _safeIntStatic(data['completedAt']),
      candidateRows: _safeIntStatic(data['candidateRows']),
      processedRows: _safeIntStatic(data['processedRows']),
      updatedRows: _safeIntStatic(data['updatedRows']),
      emptyTextRows: _safeIntStatic(data['emptyTextRows']),
      failedRows: _safeIntStatic(data['failedRows']),
      missingFiles: _safeIntStatic(data['missingFiles']),
      currentWorkIndex: _safeIntStatic(data['currentWorkIndex']),
      currentLastId: _safeIntStatic(data['currentLastId']),
      currentPackageName: (data['currentPackageName'] as String?) ?? '',
      currentYear: _safeIntStatic(data['currentYear']),
      currentTableName: (data['currentTableName'] as String?) ?? '',
      totalWorks: _safeIntStatic(data['totalWorks']),
      lastError: lastErrorRaw == null || lastErrorRaw.isEmpty ? null : lastErrorRaw,
      warnings: ((data['warnings'] as List?) ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      errors: ((data['errors'] as List?) ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      isActive: data['isActive'] == true,
      progressPercent: (data['progressPercent'] as String?) ?? '0%',
    );
  }

  static int _safeIntStatic(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool get isIdle => status == 'idle' || taskId.isEmpty;
  bool get isPreparing => status == 'preparing';
  bool get isPending => status == 'pending';
  bool get isRunning => status == 'running';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';

  String toText() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('ScreenMemo 导入图片文字后台修复');
    sb.writeln('taskId: ${taskId.isEmpty ? '(none)' : taskId}');
    sb.writeln('status: $status');
    sb.writeln('startedAt: ${startedAt > 0 ? _fmtTime(startedAt) : '(null)'}');
    sb.writeln('updatedAt: ${updatedAt > 0 ? _fmtTime(updatedAt) : '(null)'}');
    sb.writeln('completedAt: ${completedAt > 0 ? _fmtTime(completedAt) : '(null)'}');
    sb.writeln('candidateRows: $candidateRows');
    sb.writeln('processedRows: $processedRows');
    sb.writeln('progress: $progressPercent');
    sb.writeln('updatedRows: $updatedRows');
    sb.writeln('emptyTextRows: $emptyTextRows');
    sb.writeln('failedRows: $failedRows');
    sb.writeln('missingFiles: $missingFiles');
    sb.writeln('work: ${currentWorkIndex}/${totalWorks}');
    sb.writeln(
      'current: ${currentPackageName.isEmpty ? '(none)' : '$currentPackageName/$currentYear/$currentTableName'}',
    );
    if (lastError != null) {
      sb.writeln('lastError: $lastError');
    }
    if (warnings.isNotEmpty) {
      sb.writeln('[警告]');
      for (final String warning in warnings) {
        sb.writeln('- $warning');
      }
    }
    if (errors.isNotEmpty) {
      sb.writeln('[错误]');
      for (final String error in errors) {
        sb.writeln('- $error');
      }
    }
    return sb.toString().trimRight();
  }
}

extension ScreenshotDatabaseImportDiagnostics on ScreenshotDatabase {
  Future<ImportDiagnosticsReport> diagnoseImportState({
    int lookbackDays = 120,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final List<String> warnings = <String>[];
    final List<String> errors = <String>[];
    final List<String> suggestions = <String>[];

    Directory? base;
    try {
      base = await PathService.getInternalAppDir(null);
    } catch (_) {}
    base ??= await _getInternalFilesDirFallback();

    final String? basePath = base?.path;
    final String? outputPath =
        basePath == null ? null : join(basePath, 'output');
    final Directory? outputDir = outputPath == null ? null : Directory(outputPath);

    bool outputExists = false;
    try {
      outputExists = outputDir != null && await outputDir.exists();
    } catch (_) {
      outputExists = false;
    }
    if (!outputExists) {
      warnings.add('outputDir 不存在：${outputPath ?? '(null)'}');
    }

    final String? expectedMasterDbPath = outputPath == null
        ? null
        : join(outputPath, 'databases', 'screenshot_memo.db');
    bool expectedMasterDbExists = false;
    int expectedMasterDbSize = 0;
    try {
      if (expectedMasterDbPath != null) {
        final f = File(expectedMasterDbPath);
        expectedMasterDbExists = await f.exists();
        if (expectedMasterDbExists) {
          expectedMasterDbSize = await f.length();
        }
      }
    } catch (_) {}

    // Screen packages (sample)
    final String? screenDirPath =
        outputPath == null ? null : join(outputPath, 'screen');
    bool screenDirExists = false;
    int pkgCount = 0;
    final List<String> pkgs = <String>[];
    try {
      if (screenDirPath != null) {
        final dir = Directory(screenDirPath);
        screenDirExists = await dir.exists();
        if (screenDirExists) {
          await for (final ent in dir.list(followLinks: false)) {
            if (ent is Directory) {
              pkgCount++;
              if (pkgs.length < 50) {
                final String name = basename(ent.path).trim();
                if (name.isNotEmpty) pkgs.add(name);
              }
            }
          }
          pkgs.sort();
        }
      }
    } catch (e) {
      warnings.add('读取 screen 目录失败: $e');
    }
    final List<String> samplePkgs =
        pkgs.length <= 10 ? pkgs : pkgs.take(10).toList();

    // Shards db files (sample)
    final String? shardsDirPath = outputPath == null
        ? null
        : join(outputPath, 'databases', 'shards');
    bool shardsDirExists = false;
    int shardDbFiles = 0;
    int shardSmmDbFiles = 0;
    final List<String> shardSamples = <String>[];
    final List<String> smmSamples = <String>[];
    try {
      if (shardsDirPath != null) {
        final dir = Directory(shardsDirPath);
        shardsDirExists = await dir.exists();
        if (shardsDirExists) {
          await for (final ent in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (ent is! File) continue;
            final String p = ent.path;
            final String lower = p.toLowerCase();
            if (!lower.endsWith('.db')) continue;
            shardDbFiles++;
            final String bn = basename(p).toLowerCase();
            if (bn.startsWith('smm_') && bn.endsWith('.db')) {
              shardSmmDbFiles++;
              if (smmSamples.length < 10) {
                smmSamples.add(_relativeTo(basePath, p));
              }
            }
            if (shardSamples.length < 10) {
              shardSamples.add(_relativeTo(basePath, p));
            }
          }
        }
      }
    } catch (e) {
      warnings.add('扫描 shards 目录失败: $e');
    }

    // Database checks
    bool openOk = false;
    String? openErr;
    String? openedDbPath;
    int? userVersion;
    final Map<String, bool> tableExists = <String, bool>{
      'app_registry': false,
      'app_stats': false,
      'shard_registry': false,
      'totals': false,
    };
    final Map<String, int?> tableRowCounts = <String, int?>{};

    Database? db;
    try {
      db = await database;
      openOk = true;
      try {
        openedDbPath = db.path;
      } catch (_) {}

      try {
        final rows = await db.rawQuery('PRAGMA user_version');
        if (rows.isNotEmpty) {
          final Object? v = rows.first.values.isNotEmpty
              ? rows.first.values.first
              : rows.first['user_version'];
          if (v is int) userVersion = v;
          if (v is num) userVersion = v.toInt();
          userVersion ??= int.tryParse(v?.toString() ?? '');
        }
      } catch (e) {
        warnings.add('读取 user_version 失败: $e');
      }

      for (final String t in tableExists.keys) {
        try {
          final ex = await _tableExists(db, t);
          tableExists[t] = ex;
          if (ex) {
            try {
              final rows = await db.rawQuery(
                'SELECT COUNT(*) AS c FROM $t',
              );
              final Object? c = rows.isNotEmpty ? rows.first['c'] : null;
              if (c is int) {
                tableRowCounts[t] = c;
              } else if (c is num) {
                tableRowCounts[t] = c.toInt();
              } else {
                tableRowCounts[t] = int.tryParse(c?.toString() ?? '');
              }
            } catch (e2) {
              tableRowCounts[t] = null;
              warnings.add('读取表行数失败: $t err=$e2');
            }
          } else {
            tableRowCounts[t] = 0;
          }
        } catch (e) {
          tableExists[t] = false;
          tableRowCounts[t] = null;
          warnings.add('检查表存在失败: $t err=$e');
        }
      }
    } catch (e) {
      openOk = false;
      openErr = e.toString();
      errors.add('打开主库失败: $e');
    }

    final bool openedMatchesExpected = (() {
      if (openedDbPath == null || expectedMasterDbPath == null) return false;
      try {
        final a = openedDbPath.replaceAll('\\', '/');
        final b = expectedMasterDbPath.replaceAll('\\', '/');
        return a == b;
      } catch (_) {
        return false;
      }
    })();

    if (expectedMasterDbExists && !openedMatchesExpected && openedDbPath != null) {
      suggestions.add(
        '主库路径不一致：导入的 masterDb 存在，但应用当前打开的是另一个 DB。可能导致“文件存在但页面无数据”。',
      );
    }

    // Timeline self-check
    int? latestCaptureMillis;
    int rangeStartMillis = DateTime.now().millisecondsSinceEpoch;
    int rangeEndMillis = rangeStartMillis;
    int availableDays = 0;
    final List<String> sampleDays = <String>[];
    int ocrTotalRows = 0;
    int ocrRowsWithText = 0;
    int ocrRowsMissingText = 0;
    final List<String> sampleMissingOcrPaths = <String>[];
    try {
      latestCaptureMillis = await getGlobalLatestCaptureTimeMillis();
    } catch (_) {}
    try {
      final DateTime baseTime = (latestCaptureMillis == null || latestCaptureMillis <= 0)
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(latestCaptureMillis);
      final DateTime endDay = DateTime(baseTime.year, baseTime.month, baseTime.day);
      final int endMillis = DateTime(
        endDay.year,
        endDay.month,
        endDay.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final DateTime startDay = endDay.subtract(Duration(days: lookbackDays - 1));
      final int startMillis = startDay.millisecondsSinceEpoch;
      rangeStartMillis = startMillis;
      rangeEndMillis = endMillis;

      final days = await listAvailableDaysGlobalRange(
        startMillis: startMillis,
        endMillis: endMillis,
      );
      availableDays = days.length;
      for (final m in days.take(6)) {
        final String ds = (m['date'] as String?) ?? '';
        final Object? c0 = m['count'];
        final int c = c0 is int ? c0 : int.tryParse(c0?.toString() ?? '') ?? 0;
        if (ds.isEmpty) continue;
        sampleDays.add('$ds($c)');
      }
    } catch (e) {
      warnings.add('时间线自检失败: $e');
    }

    if (openOk) {
      try {
        final _ImportOcrCoverage coverage = await _scanImportOcrCoverage(
          startMillis: rangeStartMillis,
          endMillis: rangeEndMillis,
          sampleLimit: 6,
          basePath: basePath,
          warnings: warnings,
        );
        ocrTotalRows = coverage.totalRows;
        ocrRowsWithText = coverage.rowsWithOcr;
        ocrRowsMissingText = coverage.rowsMissingOcr;
        sampleMissingOcrPaths.addAll(coverage.sampleMissingPaths);
      } catch (e) {
        warnings.add('OCR 自检失败: $e');
      }
    }

    final int shardRegistryRows = tableRowCounts['shard_registry'] ?? 0;
    final int appStatsRows = tableRowCounts['app_stats'] ?? 0;
    final bool indexLikelyMissing = pkgCount > 0 && shardRegistryRows <= 0;
    final bool canRepairIndex = indexLikelyMissing;
    final bool canRepairOcr = ocrRowsMissingText > 0 && ocrTotalRows > 0;

    if (indexLikelyMissing) {
      suggestions.add(
        '检测到 output/screen 下存在应用目录，但 shard_registry 为空：高度疑似“索引缺失”。可尝试点击“修复索引”。',
      );
    }
    if (pkgCount > 0 && shardSmmDbFiles == 0) {
      suggestions.add(
        '检测到 output/screen 有内容，但未发现任何分库 DB（smm_*.db）：通常意味着“只导入了图片文件，没有导入数据库”。此时页面会全部无数据；可尝试点击“修复索引”从 screen 文件重建分库（可能耗时）。',
      );
    }
    if (openOk && availableDays == 0 && pkgCount > 0 && shardRegistryRows > 0) {
      suggestions.add(
        'shard_registry 存在但时间线窗口内无可用日期：可能是数据时间范围不在最近 $lookbackDays 天，或分库表为空。',
      );
    }
    if (openOk && shardRegistryRows > 0 && appStatsRows == 0) {
      suggestions.add(
        '检测到 app_stats 为空：可能导致应用列表/图库等统计入口无数据。可到「设置 -> 数据备份」点击“重新计算统计”。',
      );
    }
    if (openOk && ocrTotalRows > 0 && ocrRowsWithText == 0 && ocrRowsMissingText > 0) {
      suggestions.add(
        '检测到截图记录已存在，但 OCR 文本全部缺失：图片会显示，按文字搜索会无结果。可尝试点击“修复图片文字”。',
      );
    } else if (openOk &&
        ocrTotalRows > 0 &&
        ocrRowsMissingText > 0 &&
        ocrRowsWithText > 0) {
      suggestions.add(
        '检测到部分截图缺少 OCR 文本：搜索结果可能不完整。可按需点击“修复图片文字”补齐。',
      );
    }

    ImportDiagnosticsLevel level = ImportDiagnosticsLevel.ok;
    if (errors.isNotEmpty || !openOk) level = ImportDiagnosticsLevel.error;
    if (indexLikelyMissing) level = ImportDiagnosticsLevel.error;
    if (level == ImportDiagnosticsLevel.ok && warnings.isNotEmpty) {
      level = ImportDiagnosticsLevel.warn;
    }
    if (level == ImportDiagnosticsLevel.ok && suggestions.isNotEmpty) {
      level = ImportDiagnosticsLevel.warn;
    }
    if (expectedMasterDbExists && !openedMatchesExpected) {
      if (level == ImportDiagnosticsLevel.ok) level = ImportDiagnosticsLevel.warn;
    }

    sw.stop();

    return ImportDiagnosticsReport(
      timestampMillis: ts,
      durationMs: sw.elapsedMilliseconds,
      level: level,
      paths: ImportDiagnosticsPaths(
        baseDirPath: basePath,
        outputDirPath: outputPath,
        expectedMasterDbPath: expectedMasterDbPath,
        expectedMasterDbExists: expectedMasterDbExists,
        expectedMasterDbSizeBytes: expectedMasterDbSize,
        openedMasterDbPath: openedDbPath,
        openedMasterDbPathMatchesExpected: openedMatchesExpected,
      ),
      filesystem: ImportDiagnosticsFilesystem(
        outputDirExists: outputExists,
        screenDirPath: screenDirPath,
        screenDirExists: screenDirExists,
        screenPackageDirCount: pkgCount,
        samplePackages: samplePkgs,
        shardsDirPath: shardsDirPath,
        shardsDirExists: shardsDirExists,
        shardDbFileCount: shardDbFiles,
        shardSmmDbFileCount: shardSmmDbFiles,
        sampleShardDbFiles: shardSamples,
        sampleShardSmmDbFiles: smmSamples,
      ),
      database: ImportDiagnosticsDatabase(
        openOk: openOk,
        openError: openErr,
        userVersion: userVersion,
        tableExists: tableExists,
        tableRowCounts: tableRowCounts,
      ),
      timeline: ImportDiagnosticsTimeline(
        lookbackDays: lookbackDays,
        latestCaptureMillis: latestCaptureMillis,
        rangeStartMillis: rangeStartMillis,
        rangeEndMillis: rangeEndMillis,
        availableDays: availableDays,
        sampleDays: sampleDays,
      ),
      ocr: ImportDiagnosticsOcr(
        totalRowsInRange: ocrTotalRows,
        rowsWithOcrInRange: ocrRowsWithText,
        rowsMissingOcrInRange: ocrRowsMissingText,
        sampleMissingPaths: sampleMissingOcrPaths,
      ),
      warnings: warnings,
      errors: errors,
      suggestions: suggestions,
      canRepairIndex: canRepairIndex,
      canRepairOcr: canRepairOcr,
    );
  }

  Future<ImportRepairReport> repairImportIndex() async {
    final Stopwatch sw = Stopwatch()..start();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final List<String> warnings = <String>[];
    final List<String> errors = <String>[];

    Directory? base;
    try {
      base = await PathService.getInternalAppDir(null);
    } catch (_) {}
    base ??= await _getInternalFilesDirFallback();

    if (base == null) {
      sw.stop();
      return ImportRepairReport(
        timestampMillis: ts,
        durationMs: sw.elapsedMilliseconds,
        packageCount: 0,
        pairCount: 0,
        shardRegistryUpserted: 0,
        shardRegistrySkippedMissingDb: 0,
        shardDbCreated: 0,
        shardRowsInserted: 0,
        warnings: const <String>[],
        errors: <String>['baseDir 不可用，无法修复'],
      );
    }

    final String outputPath = join(base.path, 'output');
    final Directory screenDir = Directory(join(outputPath, 'screen'));
    final Directory shardsDir = Directory(join(outputPath, 'databases', 'shards'));

    bool screenExists = false;
    try {
      screenExists = await screenDir.exists();
    } catch (_) {}
    if (!screenExists) {
      warnings.add('screen 目录不存在：${screenDir.path}');
    }

    // Ensure tables exist (non-destructive)
    Database? master;
    try {
      master = await database;
      await _ensureImportIndexTables(master);
    } catch (e) {
      errors.add('打开/修复主库失败: $e');
    }

    // Collect (pkg, year) pairs from screen folder structure.
    final Map<String, Set<int>> pkgToYears = <String, Set<int>>{};
    final Map<String, Map<int, List<Directory>>> pkgYearToYearMonthDirs =
        <String, Map<int, List<Directory>>>{};
    if (screenExists) {
      try {
        await for (final ent in screenDir.list(followLinks: false)) {
          if (ent is! Directory) continue;
          final String pkg = basename(ent.path).trim();
          if (pkg.isEmpty) continue;
          final Set<int> years = pkgToYears.putIfAbsent(pkg, () => <int>{});
          final Map<int, List<Directory>> ymd =
              pkgYearToYearMonthDirs.putIfAbsent(pkg, () => <int, List<Directory>>{});

          // New structure: output/screen/<pkg>/<yyyy-MM>/...
          try {
            await for (final child in ent.list(followLinks: false)) {
              if (child is! Directory) continue;
              final String name = basename(child.path).trim();
              if (!_looksLikeYearMonthDir(name)) continue;
              final int? y = int.tryParse(name.substring(0, 4));
              if (y != null && y > 1970) {
                years.add(y);
                ymd.putIfAbsent(y, () => <Directory>[]).add(child);
              }
            }
          } catch (_) {}

          // Fallback: scan shards dir for years
          if (years.isEmpty) {
            try {
              final String sanitized = _sanitizePackageName(pkg);
              final Directory shardPkgDir = Directory(join(shardsDir.path, sanitized));
              if (await shardPkgDir.exists()) {
                await for (final yd in shardPkgDir.list(followLinks: false)) {
                  if (yd is! Directory) continue;
                  final String yName = basename(yd.path).trim();
                  final int? y = int.tryParse(yName);
                  if (y != null && y > 1970) years.add(y);
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        warnings.add('扫描 screen 目录失败: $e');
      }
    }

    int upserted = 0;
    int skippedMissingDb = 0;
    int pairCount = 0;
    int createdShardDb = 0;
    int insertedRows = 0;

    if (master != null) {
      for (final MapEntry<String, Set<int>> e in pkgToYears.entries) {
        final String pkg = e.key;
        try {
          await _registerAppIfNeeded(master, pkg, pkg);
        } catch (_) {}
        for (final int year in e.value) {
          pairCount++;
          final String sanitized = _sanitizePackageName(pkg);
          final String shardPath = join(
            shardsDir.path,
            sanitized,
            '$year',
            'smm_${sanitized}_${year}.db',
          );
          bool exists = false;
          try {
            exists = await File(shardPath).exists();
          } catch (_) {}

          if (!exists) {
            // Try rebuilding missing shard DB from screen files.
            final List<Directory> ymDirs =
                pkgYearToYearMonthDirs[pkg]?[year] ?? const <Directory>[];
            if (ymDirs.isNotEmpty) {
              try {
                final _RebuildShardFromFilesResult r = await _rebuildShardDbFromScreenYear(
                  packageName: pkg,
                  year: year,
                  yearMonthDirs: ymDirs,
                  shardsDir: shardsDir,
                  warnings: warnings,
                );
                if (r.created) createdShardDb++;
                insertedRows += r.insertedRows;
              } catch (e) {
                warnings.add('从 screen 重建分库失败: $pkg/$year err=$e');
              }
              try {
                exists = await File(shardPath).exists();
              } catch (_) {}
            }
          }

          if (!exists) {
            skippedMissingDb++;
            if (skippedMissingDb <= 20) {
              warnings.add('分库 DB 缺失：$shardPath');
            }
            continue;
          }
          try {
            await master.execute(
              'INSERT OR REPLACE INTO shard_registry(app_package_name, year, db_path) VALUES(?, ?, ?)',
              <Object?>[pkg, year, shardPath],
            );
            upserted++;
          } catch (e2) {
            warnings.add('写入 shard_registry 失败: $pkg/$year err=$e2');
          }
        }

        // Recompute app_stats for better UX (so home/gallery won't be empty).
        try {
          await _recomputeAppStatForPackage(master, pkg);
        } catch (e) {
          warnings.add('重新计算 app_stats 失败: $pkg err=$e');
        }
      }
    }

    try {
      // Ensure totals is consistent with app_stats.
      await recalculateTotals();
    } catch (e) {
      warnings.add('recalculateTotals 失败: $e');
    }

    await _resetImportRepairCaches();

    sw.stop();
    return ImportRepairReport(
      timestampMillis: ts,
      durationMs: sw.elapsedMilliseconds,
      packageCount: pkgToYears.length,
      pairCount: pairCount,
      shardRegistryUpserted: upserted,
      shardRegistrySkippedMissingDb: skippedMissingDb,
      shardDbCreated: createdShardDb,
      shardRowsInserted: insertedRows,
      warnings: warnings,
      errors: errors,
    );
  }

  Future<ImportOcrRepairReport> repairImportOcr({
    bool onlyMissing = true,
    int batchSize = 12,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final List<String> warnings = <String>[];
    final List<String> errors = <String>[];

    Database? master;
    try {
      master = await database;
    } catch (e) {
      errors.add('打开主库失败: $e');
    }

    if (master == null) {
      sw.stop();
      return ImportOcrRepairReport(
        timestampMillis: ts,
        durationMs: sw.elapsedMilliseconds,
        candidateRows: 0,
        processedRows: 0,
        updatedRows: 0,
        emptyTextRows: 0,
        failedRows: 0,
        missingFiles: 0,
        warnings: warnings,
        errors: errors,
      );
    }

    final List<_ImportShardRegistryEntry> registry = await _listImportShardRegistry(
      master,
      warnings,
    );
    if (registry.isEmpty) {
      warnings.add('shard_registry 为空，当前没有可修复 OCR 的分库。');
      sw.stop();
      return ImportOcrRepairReport(
        timestampMillis: ts,
        durationMs: sw.elapsedMilliseconds,
        candidateRows: 0,
        processedRows: 0,
        updatedRows: 0,
        emptyTextRows: 0,
        failedRows: 0,
        missingFiles: 0,
        warnings: warnings,
        errors: errors,
      );
    }

    final List<_ImportOcrTableWork> works = <_ImportOcrTableWork>[];
    int candidateRows = 0;
    for (final _ImportShardRegistryEntry entry in registry) {
      final Database? shardDb = await _openShardDb(entry.packageName, entry.year);
      if (shardDb == null) {
        if (warnings.length < 20) {
          warnings.add('打开分库失败: ${entry.packageName}/${entry.year}');
        }
        continue;
      }
      for (int month = 1; month <= 12; month++) {
        final String tableName = _monthTableName(entry.year, month);
        bool exists = false;
        try {
          exists = await _tableExists(shardDb, tableName);
        } catch (_) {
          exists = false;
        }
        if (!exists) continue;
        final int count = await _countImportOcrCandidatesInTable(
          shardDb,
          tableName,
          onlyMissing: onlyMissing,
        );
        if (count <= 0) continue;
        candidateRows += count;
        works.add(
          _ImportOcrTableWork(
            packageName: entry.packageName,
            year: entry.year,
            tableName: tableName,
            candidateCount: count,
          ),
        );
      }
    }

    if (candidateRows <= 0) {
      warnings.add(onlyMissing ? '未发现缺失 OCR 的截图记录。' : '没有可执行 OCR 修复的截图记录。');
      sw.stop();
      return ImportOcrRepairReport(
        timestampMillis: ts,
        durationMs: sw.elapsedMilliseconds,
        candidateRows: 0,
        processedRows: 0,
        updatedRows: 0,
        emptyTextRows: 0,
        failedRows: 0,
        missingFiles: 0,
        warnings: warnings,
        errors: errors,
      );
    }

    try {
      await FlutterLogger.nativeInfo(
        'IMPORT_DIAG',
        'repairImportOcr start: candidates=$candidateRows tables=${works.length} batchSize=$batchSize onlyMissing=$onlyMissing',
      );
    } catch (_) {}

    int processedRows = 0;
    int updatedRows = 0;
    int emptyTextRows = 0;
    int failedRows = 0;
    int missingFiles = 0;
    int loggedFailureCount = 0;
    int batchIndex = 0;

    for (final _ImportOcrTableWork work in works) {
      final Database? shardDb = await _openShardDb(work.packageName, work.year);
      if (shardDb == null) {
        if (warnings.length < 20) {
          warnings.add('执行 OCR 修复时无法重新打开分库: ${work.packageName}/${work.year}');
        }
        continue;
      }

      int lastId = 0;
      while (true) {
        final List<Map<String, Object?>> rows;
        try {
          rows = await shardDb.query(
            work.tableName,
            columns: const <String>['id', 'file_path'],
            where: onlyMissing
                ? 'id > ? AND (ocr_text IS NULL OR LENGTH(TRIM(ocr_text)) = 0)'
                : 'id > ?',
            whereArgs: <Object?>[lastId],
            orderBy: 'id ASC',
            limit: batchSize,
          );
        } catch (e) {
          if (warnings.length < 20) {
            warnings.add(
              '读取待修复 OCR 记录失败: ${work.packageName}/${work.tableName} err=$e',
            );
          }
          break;
        }
        if (rows.isEmpty) break;

        final List<String> filePaths = <String>[];
        for (final Map<String, Object?> row in rows) {
          final String filePath = (row['file_path'] as String?)?.trim() ?? '';
          if (filePath.isNotEmpty) filePaths.add(filePath);
          final int rowId = _safeInt(row['id']);
          if (rowId > lastId) lastId = rowId;
        }
        if (filePaths.isEmpty) continue;

        final Map<String, dynamic> nativeResult = await _invokeImportOcrBatch(
          filePaths,
        );
        batchIndex++;
        processedRows += _safeInt(nativeResult['processed']);
        updatedRows += _safeInt(nativeResult['updated']);
        emptyTextRows += _safeInt(nativeResult['empty']);
        failedRows += _safeInt(nativeResult['failed']);
        missingFiles += _safeInt(nativeResult['missingFiles']);

        final List<dynamic> failureSamples =
            (nativeResult['failureSamples'] as List?) ?? const <dynamic>[];
        for (final dynamic sample in failureSamples) {
          if (loggedFailureCount >= 20) break;
          final String text = sample.toString().trim();
          if (text.isEmpty) continue;
          warnings.add('OCR 批处理告警: $text');
          loggedFailureCount++;
        }

        if (batchIndex == 1 ||
            batchIndex % 10 == 0 ||
            processedRows >= candidateRows) {
          try {
            await FlutterLogger.nativeInfo(
              'IMPORT_DIAG',
              'repairImportOcr progress: batch=$batchIndex processed=$processedRows/$candidateRows updated=$updatedRows empty=$emptyTextRows failed=$failedRows missingFiles=$missingFiles',
            );
          } catch (_) {}
        }
      }
    }

    await _resetImportRepairCaches();

    sw.stop();
    return ImportOcrRepairReport(
      timestampMillis: ts,
      durationMs: sw.elapsedMilliseconds,
      candidateRows: candidateRows,
      processedRows: processedRows,
      updatedRows: updatedRows,
      emptyTextRows: emptyTextRows,
      failedRows: failedRows,
      missingFiles: missingFiles,
      warnings: warnings,
      errors: errors,
    );
  }

  Future<ImportOcrRepairTaskStatus> startImportOcrRepairTask({
    bool onlyMissing = true,
    int batchSize = 12,
  }) async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'startImportOcrRepairTask',
      <String, dynamic>{
        'onlyMissing': onlyMissing,
        'batchSize': batchSize,
      },
    );
    if (raw is Map) {
      return ImportOcrRepairTaskStatus.fromMap(raw);
    }
    return const ImportOcrRepairTaskStatus(
      taskId: '',
      status: 'idle',
      onlyMissing: true,
      batchSize: 12,
      startedAt: 0,
      updatedAt: 0,
      completedAt: 0,
      candidateRows: 0,
      processedRows: 0,
      updatedRows: 0,
      emptyTextRows: 0,
      failedRows: 0,
      missingFiles: 0,
      currentWorkIndex: 0,
      currentLastId: 0,
      currentPackageName: '',
      currentYear: 0,
      currentTableName: '',
      totalWorks: 0,
      lastError: null,
      warnings: <String>[],
      errors: <String>[],
      isActive: false,
      progressPercent: '0%',
    );
  }

  Future<ImportOcrRepairTaskStatus> getImportOcrRepairTaskStatus() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'getImportOcrRepairTaskStatus',
    );
    if (raw is Map) {
      return ImportOcrRepairTaskStatus.fromMap(raw);
    }
    return ImportOcrRepairTaskStatus.fromMap(null);
  }

  Future<ImportOcrRepairTaskStatus> ensureImportOcrRepairTaskResumed() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'ensureImportOcrRepairTaskResumed',
    );
    if (raw is Map) {
      return ImportOcrRepairTaskStatus.fromMap(raw);
    }
    return ImportOcrRepairTaskStatus.fromMap(null);
  }

  Future<ImportOcrRepairTaskStatus> cancelImportOcrRepairTask() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'cancelImportOcrRepairTask',
    );
    if (raw is Map) {
      return ImportOcrRepairTaskStatus.fromMap(raw);
    }
    return ImportOcrRepairTaskStatus.fromMap(null);
  }

  Future<_ImportOcrCoverage> _scanImportOcrCoverage({
    required int startMillis,
    required int endMillis,
    required int sampleLimit,
    required String? basePath,
    required List<String> warnings,
  }) async {
    final Database master = await database;
    final List<_ImportShardRegistryEntry> registry = await _listImportShardRegistry(
      master,
      warnings,
      startYear: DateTime.fromMillisecondsSinceEpoch(startMillis).year,
      endYear: DateTime.fromMillisecondsSinceEpoch(endMillis).year,
    );

    int totalRows = 0;
    int rowsWithOcr = 0;
    int rowsMissingOcr = 0;
    final List<String> sampleMissingPaths = <String>[];

    for (final _ImportShardRegistryEntry entry in registry) {
      final Database? shardDb = await _openShardDb(entry.packageName, entry.year);
      if (shardDb == null) {
        if (warnings.length < 20) {
          warnings.add('OCR 自检无法打开分库: ${entry.packageName}/${entry.year}');
        }
        continue;
      }

      for (int month = 1; month <= 12; month++) {
        final int monthStart = DateTime(entry.year, month, 1).millisecondsSinceEpoch;
        final int monthEnd = month == 12
            ? DateTime(entry.year + 1, 1, 1).millisecondsSinceEpoch - 1
            : DateTime(entry.year, month + 1, 1).millisecondsSinceEpoch - 1;
        if (monthEnd < startMillis || monthStart > endMillis) continue;

        final String tableName = _monthTableName(entry.year, month);
        bool exists = false;
        try {
          exists = await _tableExists(shardDb, tableName);
        } catch (_) {
          exists = false;
        }
        if (!exists) continue;

        try {
          final List<Map<String, Object?>> rows = await shardDb.rawQuery(
            '''
            SELECT
              COUNT(*) AS total_count,
              SUM(CASE WHEN ocr_text IS NOT NULL AND LENGTH(TRIM(ocr_text)) > 0 THEN 1 ELSE 0 END) AS with_ocr,
              SUM(CASE WHEN ocr_text IS NULL OR LENGTH(TRIM(ocr_text)) = 0 THEN 1 ELSE 0 END) AS missing_ocr
            FROM $tableName
            WHERE capture_time >= ? AND capture_time <= ?
            ''',
            <Object?>[startMillis, endMillis],
          );
          if (rows.isNotEmpty) {
            final Map<String, Object?> row = rows.first;
            totalRows += _safeInt(row['total_count']);
            rowsWithOcr += _safeInt(row['with_ocr']);
            rowsMissingOcr += _safeInt(row['missing_ocr']);
          }
        } catch (e) {
          if (warnings.length < 20) {
            warnings.add(
              'OCR 自检统计失败: ${entry.packageName}/$tableName err=$e',
            );
          }
        }

        if (sampleMissingPaths.length >= sampleLimit) continue;
        try {
          final List<Map<String, Object?>> rows = await shardDb.query(
            tableName,
            columns: const <String>['file_path'],
            where:
                'capture_time >= ? AND capture_time <= ? AND (ocr_text IS NULL OR LENGTH(TRIM(ocr_text)) = 0)',
            whereArgs: <Object?>[startMillis, endMillis],
            orderBy: 'capture_time DESC, id DESC',
            limit: sampleLimit - sampleMissingPaths.length,
          );
          for (final Map<String, Object?> row in rows) {
            final String path = (row['file_path'] as String?)?.trim() ?? '';
            if (path.isEmpty) continue;
            sampleMissingPaths.add(_relativeTo(basePath, path));
          }
        } catch (_) {}
      }
    }

    return _ImportOcrCoverage(
      totalRows: totalRows,
      rowsWithOcr: rowsWithOcr,
      rowsMissingOcr: rowsMissingOcr,
      sampleMissingPaths: sampleMissingPaths,
    );
  }

  Future<List<_ImportShardRegistryEntry>> _listImportShardRegistry(
    Database master,
    List<String> warnings, {
    int? startYear,
    int? endYear,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await master.query(
        'shard_registry',
        columns: const <String>['app_package_name', 'year'],
        where: startYear != null && endYear != null ? 'year >= ? AND year <= ?' : null,
        whereArgs: startYear != null && endYear != null
            ? <Object?>[startYear, endYear]
            : null,
        orderBy: 'app_package_name ASC, year ASC',
      );
      return rows
          .map((Map<String, Object?> row) {
            final String packageName =
                (row['app_package_name'] as String?)?.trim() ?? '';
            final int year = _safeInt(row['year']);
            if (packageName.isEmpty || year <= 0) return null;
            return _ImportShardRegistryEntry(packageName: packageName, year: year);
          })
          .whereType<_ImportShardRegistryEntry>()
          .toList();
    } catch (e) {
      warnings.add('读取 shard_registry 失败: $e');
      return <_ImportShardRegistryEntry>[];
    }
  }

  Future<int> _countImportOcrCandidatesInTable(
    Database shardDb,
    String tableName, {
    required bool onlyMissing,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await shardDb.rawQuery(
        onlyMissing
            ? 'SELECT COUNT(*) AS c FROM $tableName WHERE ocr_text IS NULL OR LENGTH(TRIM(ocr_text)) = 0'
            : 'SELECT COUNT(*) AS c FROM $tableName',
      );
      if (rows.isEmpty) return 0;
      return _safeInt(rows.first['c']);
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> _invokeImportOcrBatch(List<String> filePaths) async {
    try {
      final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
        'repairImportOcrBatch',
        <String, dynamic>{'filePaths': filePaths},
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      return <String, dynamic>{
        'processed': filePaths.length,
        'updated': 0,
        'empty': 0,
        'failed': filePaths.length,
        'missingFiles': 0,
        'failureSamples': <String>['批量 OCR 调用失败: $e'],
      };
    }
    return <String, dynamic>{
      'processed': filePaths.length,
      'updated': 0,
      'empty': 0,
      'failed': filePaths.length,
      'missingFiles': 0,
      'failureSamples': const <String>['批量 OCR 返回结果为空'],
    };
  }

  Future<void> _resetImportRepairCaches() async {
    try {
      for (final Database db in ScreenshotDatabase._shardDbCache.values) {
        try {
          await db.close();
        } catch (_) {}
      }
      ScreenshotDatabase._shardDbCache.clear();
      if (ScreenshotDatabase._database != null) {
        try {
          await ScreenshotDatabase._database!.close();
        } catch (_) {}
        ScreenshotDatabase._database = null;
      }
    } catch (_) {}
  }

  Future<_RebuildShardFromFilesResult> _rebuildShardDbFromScreenYear({
    required String packageName,
    required int year,
    required List<Directory> yearMonthDirs,
    required Directory shardsDir,
    required List<String> warnings,
  }) async {
    final String sanitized = _sanitizePackageName(packageName);
    final String shardPath = join(
      shardsDir.path,
      sanitized,
      '$year',
      'smm_${sanitized}_${year}.db',
    );

    bool created = false;
    try {
      created = !await File(shardPath).exists();
    } catch (_) {}

    try {
      final Directory parent = Directory(dirname(shardPath));
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
    } catch (_) {}

    int inserted = 0;
    Database? shardDb;
    try {
      final Database db = await openDatabase(shardPath, version: 1);
      shardDb = db;
      for (final Directory ymDir in yearMonthDirs) {
        final String ymName = basename(ymDir.path).trim();
        if (!_looksLikeYearMonthDir(ymName)) continue;
        final int? month = int.tryParse(ymName.substring(5, 7));
        if (month == null || month < 1 || month > 12) continue;
        await _ensureMonthTable(db, year, month);
        final String tableName = _monthTableName(year, month);

        Batch batch = db.batch();
        int batchSize = 0;

        await for (final ent in ymDir.list(followLinks: false)) {
          if (ent is! Directory) continue;
          final String dayName = basename(ent.path).trim();
          final int? day = int.tryParse(dayName);
          if (day == null || day < 1 || day > 31) continue;

          await for (final fe in ent.list(followLinks: false)) {
            if (fe is! File) continue;
            final String p = fe.path;
            if (!_looksLikeScreenshotImage(p)) continue;

            int size = 0;
            try {
              size = await fe.length();
            } catch (_) {}

            final String base = basenameWithoutExtension(p);
            int captureMillis =
                _tryParseCaptureTimeMillisFromScreenPath(year, month, day, base) ??
                DateTime(year, month, day).millisecondsSinceEpoch;

            batch.insert(
              tableName,
              <String, Object?>{
                'file_path': p,
                'capture_time': captureMillis,
                'file_size': size,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            inserted++;
            batchSize++;
            if (batchSize >= 500) {
              try {
                await batch.commit(noResult: true, continueOnError: true);
              } catch (_) {}
              batch = db.batch();
              batchSize = 0;
            }
          }
        }

        if (batchSize > 0) {
          try {
            await batch.commit(noResult: true, continueOnError: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      warnings.add('重建分库 DB 失败: $packageName/$year err=$e');
    } finally {
      try {
        await shardDb?.close();
      } catch (_) {}
    }

    if (inserted == 0) {
      warnings.add('重建分库完成但未插入任何行: $packageName/$year');
    }

    return _RebuildShardFromFilesResult(
      created: created,
      insertedRows: inserted,
    );
  }

  Future<void> _ensureImportIndexTables(DatabaseExecutor db) async {
    // Note: schemas keep consistent with ScreenshotDatabase._onCreate
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_registry (
        app_package_name TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        table_name TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_stats (
        app_package_name TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        total_size INTEGER NOT NULL DEFAULT 0,
        last_capture_time INTEGER,
        last_dhash INTEGER
      )
    ''');
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_stats_last ON app_stats(last_capture_time)',
      );
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS shard_registry (
        app_package_name TEXT NOT NULL,
        year INTEGER NOT NULL,
        db_path TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
        PRIMARY KEY (app_package_name, year)
      )
    ''');

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
}

class _RebuildShardFromFilesResult {
  final bool created;
  final int insertedRows;
  const _RebuildShardFromFilesResult({
    required this.created,
    required this.insertedRows,
  });
}

class _ImportShardRegistryEntry {
  final String packageName;
  final int year;

  const _ImportShardRegistryEntry({
    required this.packageName,
    required this.year,
  });
}

class _ImportOcrTableWork {
  final String packageName;
  final int year;
  final String tableName;
  final int candidateCount;

  const _ImportOcrTableWork({
    required this.packageName,
    required this.year,
    required this.tableName,
    required this.candidateCount,
  });
}

class _ImportOcrCoverage {
  final int totalRows;
  final int rowsWithOcr;
  final int rowsMissingOcr;
  final List<String> sampleMissingPaths;

  const _ImportOcrCoverage({
    required this.totalRows,
    required this.rowsWithOcr,
    required this.rowsMissingOcr,
    required this.sampleMissingPaths,
  });
}

String _levelLabel(ImportDiagnosticsLevel lv) {
  switch (lv) {
    case ImportDiagnosticsLevel.ok:
      return 'OK';
    case ImportDiagnosticsLevel.warn:
      return 'WARN';
    case ImportDiagnosticsLevel.error:
      return 'ERROR';
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

String _fmtTime(int ms) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

String _relativeTo(String? basePath, String path) {
  if (basePath == null || basePath.trim().isEmpty) return path;
  try {
    final String baseN = basePath.replaceAll('\\', '/');
    final String pN = path.replaceAll('\\', '/');
    if (pN.startsWith(baseN)) {
      final String rel = pN.substring(baseN.length);
      return rel.startsWith('/') ? rel.substring(1) : rel;
    }
  } catch (_) {}
  return path;
}

int _safeInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _looksLikeYearMonthDir(String name) {
  if (name.length != 7) return false;
  final RegExp re = RegExp(r'^\d{4}-\d{2}$');
  return re.hasMatch(name);
}

bool _looksLikeScreenshotImage(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}

int? _tryParseCaptureTimeMillisFromScreenPath(
  int year,
  int month,
  int day,
  String baseName,
) {
  // Android native naming: HHmmss_SSS (see ScreenCaptureAccessibilityService.kt)
  final RegExp re = RegExp(r'^(\d{2})(\d{2})(\d{2})_(\d{3})');
  final Match? m = re.firstMatch(baseName);
  if (m == null) return null;
  try {
    final int hh = int.parse(m.group(1)!);
    final int mm = int.parse(m.group(2)!);
    final int ss = int.parse(m.group(3)!);
    final int ms = int.parse(m.group(4)!);
    if (hh < 0 || hh > 23) return null;
    if (mm < 0 || mm > 59) return null;
    if (ss < 0 || ss > 59) return null;
    if (ms < 0 || ms > 999) return null;
    return DateTime(year, month, day, hh, mm, ss, ms).millisecondsSinceEpoch;
  } catch (_) {
    return null;
  }
}

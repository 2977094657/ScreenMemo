part of 'screenshot_database.dart';

/// 导入合并结果统计
class MergeReport {
  final int copiedFiles;
  final int reusedFiles;
  final int insertedScreenshots;
  final int skippedScreenshotDuplicates;
  final Set<String> affectedPackages;
  final List<String> warnings;

  const MergeReport({
    required this.copiedFiles,
    required this.reusedFiles,
    required this.insertedScreenshots,
    required this.skippedScreenshotDuplicates,
    required this.affectedPackages,
    required this.warnings,
  });
}

class MergeZipAuditReport {
  final String sourcePath;
  final String sourceKind;
  final int timestampMillis;
  final int durationMs;
  final int screenFileCount;
  final int screenPackageCount;
  final List<String> samplePackages;
  final bool masterDbExists;
  final bool masterDbReadable;
  final String? masterDbReadError;
  final int? userVersion;
  final int smmDbCount;
  final List<String> sampleSmmDbPaths;
  final int dbSidecarFileCount;
  final List<String> sampleDbSidecarPaths;
  final Map<String, int?> registryCounts;
  final List<String> blockingIssues;
  final List<String> warnings;

  const MergeZipAuditReport({
    required this.sourcePath,
    required this.sourceKind,
    required this.timestampMillis,
    required this.durationMs,
    required this.screenFileCount,
    required this.screenPackageCount,
    required this.samplePackages,
    required this.masterDbExists,
    required this.masterDbReadable,
    required this.masterDbReadError,
    required this.userVersion,
    required this.smmDbCount,
    required this.sampleSmmDbPaths,
    required this.dbSidecarFileCount,
    required this.sampleDbSidecarPaths,
    required this.registryCounts,
    required this.blockingIssues,
    required this.warnings,
  });

  bool get isValidForMerge => blockingIssues.isEmpty;

  String toText() {
    final StringBuffer sb = StringBuffer()
      ..writeln('ScreenMemo 合并预检')
      ..writeln('sourceKind: $sourceKind')
      ..writeln('sourcePath: $sourcePath')
      ..writeln('运行时间: ${_fmtTime(timestampMillis)}')
      ..writeln('耗时: ${durationMs}ms')
      ..writeln('状态: ${isValidForMerge ? 'OK' : 'BLOCKED'}')
      ..writeln()
      ..writeln('[文件]')
      ..writeln(
        'screenFiles: $screenFileCount packages=$screenPackageCount sample=${samplePackages.join(', ')}',
      )
      ..writeln('smmDbFiles: $smmDbCount sample=${sampleSmmDbPaths.join(', ')}')
      ..writeln(
        'dbSidecars: $dbSidecarFileCount sample=${sampleDbSidecarPaths.join(', ')}',
      )
      ..writeln()
      ..writeln('[主库]')
      ..writeln('masterDbExists: $masterDbExists')
      ..writeln('masterDbReadable: $masterDbReadable')
      ..writeln('userVersion: ${userVersion?.toString() ?? '(null)'}');
    if (masterDbReadError != null && masterDbReadError!.trim().isNotEmpty) {
      sb.writeln('masterDbReadError: $masterDbReadError');
    }
    sb
      ..writeln(
        'registryCounts: app_registry=${registryCounts['app_registry'] ?? '(n/a)'}, '
        'app_stats=${registryCounts['app_stats'] ?? '(n/a)'}, '
        'shard_registry=${registryCounts['shard_registry'] ?? '(n/a)'}, '
        'totals=${registryCounts['totals'] ?? '(n/a)'}',
      )
      ..writeln();

    if (blockingIssues.isNotEmpty) {
      sb.writeln('[阻断问题]');
      for (final String issue in blockingIssues) {
        sb.writeln('- $issue');
      }
      sb.writeln();
    }

    if (warnings.isNotEmpty) {
      sb.writeln('[警告]');
      for (final String warning in warnings) {
        sb.writeln('- $warning');
      }
    }

    return sb.toString().trimRight();
  }
}

class MergeAuditException implements Exception {
  final String code;
  final String message;
  final MergeZipAuditReport? report;

  const MergeAuditException({
    required this.code,
    required this.message,
    this.report,
  });

  @override
  String toString() => '$code: $message';
}

class _MasterDbProbeResult {
  final bool openOk;
  final String? openError;
  final int? userVersion;
  final Map<String, int?> rowCounts;
  final bool sidecarOpenFailed;
  final String? sidecarOpenError;

  const _MasterDbProbeResult({
    required this.openOk,
    required this.openError,
    required this.userVersion,
    required this.rowCounts,
    required this.sidecarOpenFailed,
    required this.sidecarOpenError,
  });
}

class _MergeContext {
  final Map<int, int> gidMapping = <int, int>{};
  final Map<String, String> relativePathMapping = <String, String>{};
  final Set<String> affectedPackages = <String>{};
  final List<String> warnings = <String>[];
  int copiedFiles = 0;
  int reusedFiles = 0;
  int insertedScreenshots = 0;
  int skippedScreenshotDuplicates = 0;

  MergeReport toReport() {
    return MergeReport(
      copiedFiles: copiedFiles,
      reusedFiles: reusedFiles,
      insertedScreenshots: insertedScreenshots,
      skippedScreenshotDuplicates: skippedScreenshotDuplicates,
      affectedPackages: affectedPackages,
      warnings: List<String>.from(warnings),
    );
  }
}

extension ScreenshotDatabaseMerge on ScreenshotDatabase {
  /// 将导出的 ZIP 数据与当前数据库进行合并，保留现有数据并合并新增内容。
  ///
  /// - 若 `zipPath` 与 `zipBytes` 均为空，则直接返回 null。
  /// - 该方法会在内部使用临时目录解压数据，完成后会清理。
  /// - 返回 `MergeReport` 用于展示合并统计信息。
  Future<MergeReport?> mergeDataFromZip({
    String? zipPath,
    List<int>? zipBytes,
    void Function(ImportExportProgress progress)? onProgress,
    bool throwOnError = false,
    bool requireCompleteShardData = false,
    MergeZipAuditReport? preflightAuditReport,
  }) async {
    if ((zipPath == null || zipPath.isEmpty) &&
        (zipBytes == null || zipBytes.isEmpty)) {
      const msg = 'mergeDataFromZip：未提供输入数据';
      await FlutterLogger.nativeWarn('MERGE', msg);
      if (throwOnError) {
        throw ArgumentError(msg);
      }
      return null;
    }

    // 优先使用桌面端设置的目录，否则使用默认目录
    Directory? base;
    if (ScreenshotDatabase._desktopBasePath != null &&
        ScreenshotDatabase._desktopBasePath!.isNotEmpty) {
      base = Directory(ScreenshotDatabase._desktopBasePath!);
    } else {
      base =
          await PathService.getInternalAppDir(null) ??
          await _getInternalFilesDir();
    }
    if (base == null) {
      const msg = 'mergeDataFromZip：base 目录不可用';
      await FlutterLogger.nativeError('MERGE', msg);
      if (throwOnError) {
        throw StateError(msg);
      }
      return null;
    }

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final Directory stagingRoot = Directory(
      join(base.path, 'output', '_merge_staging', timestamp),
    );
    final Directory stagingOutput = Directory(join(stagingRoot.path, 'output'));

    File? tempZipFile;
    String? localZipPath = zipPath;
    String? lastStage;
    String? lastEntry;
    int lastProgressEmitMs = 0;
    double lastProgressEmitValue = -1;
    String? lastProgressEmitStage;

    void reportProgress(ImportExportProgress progress) {
      lastStage = progress.stage;
      lastEntry = progress.currentEntry;
      final cb = onProgress;
      if (cb == null) return;

      final int now = DateTime.now().millisecondsSinceEpoch;
      final String? stage = progress.stage;
      final bool stageChanged = stage != lastProgressEmitStage;
      final bool isEdge = progress.value <= 0.0 || progress.value >= 1.0;
      final bool timeOk = (now - lastProgressEmitMs) >= 150;
      final bool valueChanged =
          lastProgressEmitValue < 0 ||
          (progress.value - lastProgressEmitValue).abs() >= 0.01;

      if (stageChanged || isEdge || (timeOk && valueChanged)) {
        lastProgressEmitMs = now;
        lastProgressEmitValue = progress.value;
        lastProgressEmitStage = stage;
        cb(progress);
      }
    }

    try {
      if (!await stagingOutput.exists()) {
        await stagingOutput.create(recursive: true);
      }

      if ((localZipPath == null || localZipPath.isEmpty) &&
          zipBytes != null &&
          zipBytes.isNotEmpty) {
        tempZipFile = await _createTempZipFile(zipBytes);
        localZipPath = tempZipFile.path;
      }

      if (requireCompleteShardData) {
        final MergeZipAuditReport audit =
            preflightAuditReport ?? await auditMergeInputZip(localZipPath!);
        if (!audit.isValidForMerge) {
          throw MergeAuditException(
            code: 'invalid_source_zip',
            message: audit.blockingIssues.isNotEmpty
                ? audit.blockingIssues.first
                : 'ZIP 预检未通过',
            report: audit,
          );
        }
      }

      final Map<String, dynamic>? extraction = await _runImportZipWithProgress(
        localZipPath: localZipPath!,
        targetRoots: <String, String>{'output': stagingOutput.path},
        overwrite: true,
        onProgress: (progress) {
          reportProgress(
            ImportExportProgress(
              value: progress.value * 0.3,
              stage: 'merge_extracting',
              currentEntry: progress.currentEntry,
            ),
          );
        },
      );
      if (extraction == null) {
        final msg =
            'mergeDataFromZip：解压结果为 null (zipPath=${zipPath ?? ''} localZipPath=$localZipPath)';
        await FlutterLogger.nativeWarn('MERGE', msg);
        if (throwOnError) {
          throw StateError(msg);
        }
        return null;
      }

      final _MergeContext ctx = _MergeContext();
      await _mergeExtractedOutput(
        baseDir: base,
        stagingOutput: stagingOutput,
        ctx: ctx,
        progress: reportProgress,
        requireCompleteShardData: requireCompleteShardData,
      );

      try {
        final Directory outputDir = Directory(join(base.path, 'output'));
        await _clearOutputCacheDirs(outputDir);
      } catch (_) {}

      return ctx.toReport();
    } catch (e, st) {
      final contextInfo =
          'zipPath=${zipPath ?? ''} localZipPath=${localZipPath ?? ''} base=${base.path} stage=${lastStage ?? ''} entry=${lastEntry ?? ''}';
      await FlutterLogger.handle(
        e,
        st,
        tag: 'MERGE',
        message: 'mergeDataFromZip 异常：$contextInfo',
      );
      if (throwOnError) {
        Error.throwWithStackTrace(e, st);
      }
      return null;
    } finally {
      try {
        if (await stagingRoot.exists()) {
          await stagingRoot.delete(recursive: true);
        }
      } catch (_) {}
      if (tempZipFile != null) {
        try {
          if (await tempZipFile.exists()) {
            await tempZipFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<File> _createTempZipFile(List<int> bytes) async {
    final Directory tempDir = await getTemporaryDirectory();
    final File tempFile = File(
      join(
        tempDir.path,
        'screenmemo_merge_${DateTime.now().millisecondsSinceEpoch}.zip',
      ),
    );
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile;
  }

  Future<void> _mergeExtractedOutput({
    required Directory baseDir,
    required Directory stagingOutput,
    required _MergeContext ctx,
    void Function(ImportExportProgress progress)? progress,
    bool requireCompleteShardData = false,
  }) async {
    final Directory targetOutput = Directory(join(baseDir.path, 'output'));
    if (!await targetOutput.exists()) {
      await targetOutput.create(recursive: true);
    }

    await _copyScreenshots(
      stagingOutput: stagingOutput,
      targetOutput: targetOutput,
      ctx: ctx,
      progress: progress,
    );

    await _copyGenericEntries(
      stagingOutput: stagingOutput,
      targetOutput: targetOutput,
      ctx: ctx,
      progress: progress,
    );

    await _mergeScreenshotDatabases(
      baseDir: baseDir,
      stagingOutput: stagingOutput,
      ctx: ctx,
      progress: progress,
      requireCompleteShardData: requireCompleteShardData,
    );

    await _mergeMetadataDatabase(
      baseDir: baseDir,
      stagingOutput: stagingOutput,
      ctx: ctx,
      progress: progress,
    );

    await _copyRemainingDatabases(
      baseDir: baseDir,
      stagingOutput: stagingOutput,
      ctx: ctx,
    );

    await _finalizeMerge(ctx);

    progress?.call(
      const ImportExportProgress(
        value: 1.0,
        stage: 'merge_finalizing',
        currentEntry: null,
      ),
    );
  }

  Future<void> _copyScreenshots({
    required Directory stagingOutput,
    required Directory targetOutput,
    required _MergeContext ctx,
    void Function(ImportExportProgress progress)? progress,
  }) async {
    final Directory stagingScreen = Directory(
      join(stagingOutput.path, 'screen'),
    );
    if (!await stagingScreen.exists()) {
      return;
    }

    final List<FileSystemEntity> entries = await stagingScreen
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .toList();
    final int total = entries.length;
    int processed = 0;

    for (final FileSystemEntity entity in entries) {
      processed++;
      final File src = entity as File;
      final String rel = _relativeFromScreenPath(stagingScreen.path, src.path);
      if (rel.isEmpty) continue;

      final String mappingKey = 'screen/$rel'.replaceAll('//', '/');
      final File dest = File(join(targetOutput.path, mappingKey));
      final Directory parent = dest.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      if (await dest.exists()) {
        final bool same = await _filesIdentical(src, dest);
        if (same) {
          ctx.reusedFiles++;
          ctx.relativePathMapping[mappingKey] = dest.path;
        } else {
          final File uniqueDest = await _resolveUniqueFile(dest);
          await src.copy(uniqueDest.path);
          ctx.copiedFiles++;
          ctx.relativePathMapping[mappingKey] = uniqueDest.path;
        }
      } else {
        await src.copy(dest.path);
        ctx.copiedFiles++;
        ctx.relativePathMapping[mappingKey] = dest.path;
      }

      if (progress != null) {
        progress(
          ImportExportProgress(
            value: 0.3 + (processed / total) * 0.2,
            stage: 'merge_copying_files',
            currentEntry: rel,
          ),
        );
      }
    }
  }

  Future<void> _copyGenericEntries({
    required Directory stagingOutput,
    required Directory targetOutput,
    required _MergeContext ctx,
    void Function(ImportExportProgress progress)? progress,
  }) async {
    final List<FileSystemEntity> topEntries = await stagingOutput
        .list(followLinks: false)
        .toList();
    final List<FileSystemEntity> genericEntries = <FileSystemEntity>[];
    for (final FileSystemEntity entry in topEntries) {
      final String name = basename(entry.path);
      final String lowerName = name.toLowerCase();
      if (name == 'screen' || name == 'databases') {
        continue;
      }
      if (lowerName == 'memory_notes') {
        // Memory archive disabled: ignore imported memory notes.
        continue;
      }
      if (_outputCacheDirNames.contains(lowerName)) {
        continue;
      }
      genericEntries.add(entry);
    }
    if (genericEntries.isEmpty) return;

    final int total = genericEntries.length;
    int processed = 0;

    for (final FileSystemEntity entry in genericEntries) {
      processed++;
      final String rel = entry.path
          .substring(stagingOutput.path.length + 1)
          .replaceAll('\\', '/');
      final String targetPath = join(targetOutput.path, rel);

      if (entry is Directory) {
        await _copyGenericDirectory(
          source: entry,
          destination: Directory(targetPath),
          ctx: ctx,
        );
      } else if (entry is File) {
        await _copyGenericFile(
          source: entry,
          destination: File(targetPath),
          ctx: ctx,
        );
      }

      if (progress != null) {
        progress(
          ImportExportProgress(
            value: 0.5 + (processed / total) * 0.1,
            stage: 'merge_copying_generic',
            currentEntry: rel,
          ),
        );
      }
    }
  }

  Future<void> _copyGenericDirectory({
    required Directory source,
    required Directory destination,
    required _MergeContext ctx,
  }) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    await for (final FileSystemEntity entity in source.list(
      followLinks: false,
    )) {
      final String childPath = join(destination.path, basename(entity.path));
      if (entity is Directory) {
        await _copyGenericDirectory(
          source: entity,
          destination: Directory(childPath),
          ctx: ctx,
        );
      } else if (entity is File) {
        await _copyGenericFile(
          source: entity,
          destination: File(childPath),
          ctx: ctx,
        );
      }
    }
  }

  Future<void> _copyGenericFile({
    required File source,
    required File destination,
    required _MergeContext ctx,
  }) async {
    final Directory parent = destination.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    if (await destination.exists()) {
      final bool same = await _filesIdentical(source, destination);
      if (same) {
        ctx.reusedFiles++;
        return;
      }
      final File uniqueDest = await _resolveUniqueFile(destination);
      await source.copy(uniqueDest.path);
      ctx.copiedFiles++;
      return;
    }

    await source.copy(destination.path);
    ctx.copiedFiles++;
  }

  Future<void> _mergeScreenshotDatabases({
    required Directory baseDir,
    required Directory stagingOutput,
    required _MergeContext ctx,
    void Function(ImportExportProgress progress)? progress,
    bool requireCompleteShardData = false,
  }) async {
    final Directory stagingDbDir = Directory(
      join(stagingOutput.path, 'databases'),
    );
    if (!await stagingDbDir.exists()) {
      ctx.warnings.add(
        'Staging databases directory missing: ${stagingDbDir.path}',
      );
      return;
    }

    progress?.call(
      const ImportExportProgress(
        value: 0.6,
        stage: 'merge_shard_databases',
        currentEntry: null,
      ),
    );

    final File importedMaster = File(
      join(stagingDbDir.path, 'screenshot_memo.db'),
    );
    if (!await importedMaster.exists()) {
      if (requireCompleteShardData) {
        throw const MergeAuditException(
          code: 'invalid_master_db',
          message: 'Imported screenshot_memo.db not found.',
        );
      }
      ctx.warnings.add(
        'Imported screenshot_memo.db not found, try infer shards from copied screen files.',
      );
    }

    List<Map<String, Object?>> shards = <Map<String, Object?>>[];
    final Map<String, String> appNames = <String, String>{};
    final int? currentUserVersion = await _tryReadUserVersion(await database);
    int? importedUserVersion;

    Database? importedDb;
    try {
      if (await importedMaster.exists()) {
        importedDb = await openDatabase(importedMaster.path, readOnly: true);
        importedUserVersion = await _tryReadUserVersion(importedDb);
        if (importedUserVersion != null && currentUserVersion != null) {
          if (importedUserVersion > currentUserVersion) {
            ctx.warnings.add(
              'Imported screenshot_memo.db user_version=$importedUserVersion is newer than current=$currentUserVersion; consider updating the app before merging.',
            );
          } else if (importedUserVersion < currentUserVersion) {
            ctx.warnings.add(
              'Imported screenshot_memo.db user_version=$importedUserVersion (current=$currentUserVersion).',
            );
          }
        }

        try {
          final List<Map<String, Object?>> apps = await importedDb.query(
            'app_registry',
            columns: ['app_package_name', 'app_name'],
          );
          for (final Map<String, Object?> row in apps) {
            final String? pkg = row['app_package_name'] as String?;
            if (pkg == null) continue;
            final String? name = row['app_name'] as String?;
            appNames[pkg] = name ?? pkg;
          }
        } catch (e) {
          ctx.warnings.add(
            'Failed to read imported app_registry (will fall back to package name): $e',
          );
        }

        try {
          shards = await importedDb.query(
            'shard_registry',
            columns: ['app_package_name', 'year'],
          );
        } catch (e) {
          ctx.warnings.add('Failed to read imported shard_registry: $e');
          shards = <Map<String, Object?>>[];
        }
      }
    } catch (e) {
      if (requireCompleteShardData) {
        throw MergeAuditException(
          code: 'invalid_master_db',
          message:
              'Failed to open/read imported screenshot_memo.db (${importedMaster.path}): $e',
        );
      }
      ctx.warnings.add(
        'Failed to open/read imported screenshot_memo.db (${importedMaster.path}): $e',
      );
    } finally {
      await importedDb?.close();
    }

    if (shards.isEmpty) {
      if (requireCompleteShardData) {
        throw const MergeAuditException(
          code: 'missing_shard_db',
          message:
              'Imported screenshot_memo.db has no shard_registry rows while screen files exist.',
        );
      }
      shards = _inferShardRegistryRowsFromCopiedScreens(ctx);
      if (shards.isNotEmpty) {
        ctx.warnings.add(
          'Using inferred shard list from copied screen files (imported screenshot_memo.db unavailable).',
        );
      }
    }

    if (shards.isEmpty) {
      ctx.warnings.add('No shard registry available; skip shard DB merge.');
      return;
    }

    int processed = 0;
    final int total = shards.length;

    for (final Map<String, Object?> row in shards) {
      final String? pkg = row['app_package_name'] as String?;
      final int? year = row['year'] as int?;
      if (pkg == null || year == null) continue;
      processed++;

      ctx.affectedPackages.add(pkg);
      final String sanitized = _sanitizePackageName(pkg);
      final String shardPath = join(
        stagingDbDir.path,
        'shards',
        sanitized,
        '$year',
        'smm_${sanitized}_$year.db',
      );

      final File shardFile = File(shardPath);
      if (!await shardFile.exists()) {
        if (requireCompleteShardData) {
          throw MergeAuditException(
            code: 'missing_shard_db',
            message: 'Shard file missing for $pkg/$year: $shardPath',
          );
        }
        ctx.warnings.add('Shard file missing for $pkg - $year: $shardPath');
        continue;
      }

      await _mergeSingleShard(
        packageName: pkg,
        appName: appNames[pkg] ?? pkg,
        year: year,
        shardFile: shardFile,
        ctx: ctx,
      );

      if (progress != null && total > 0) {
        progress(
          ImportExportProgress(
            value: 0.6 + (processed / total) * 0.25,
            stage: 'merge_shard_databases',
            currentEntry: '$pkg/$year',
          ),
        );
      }
    }
  }

  List<Map<String, Object?>> _inferShardRegistryRowsFromCopiedScreens(
    _MergeContext ctx,
  ) {
    final Set<String> seen = <String>{};
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final String rel in ctx.relativePathMapping.keys) {
      final List<String> parts = rel.split('/');
      if (parts.length < 3) continue;
      if (parts.first != 'screen') continue;
      final String pkg = parts[1];
      final String ym = parts[2];
      if (pkg.isEmpty || ym.length < 4) continue;
      final int? year = int.tryParse(ym.substring(0, 4));
      if (year == null) continue;
      final String key = '$pkg|$year';
      if (!seen.add(key)) continue;
      result.add(<String, Object?>{'app_package_name': pkg, 'year': year});
    }
    return result;
  }

  Future<void> _mergeSingleShard({
    required String packageName,
    required String appName,
    required int year,
    required File shardFile,
    required _MergeContext ctx,
  }) async {
    Database? importedShard;
    try {
      importedShard = await openDatabase(shardFile.path, readOnly: true);
      final Database? targetShard = await _openShardDb(packageName, year);
      if (targetShard == null) {
        ctx.warnings.add('Failed to open target shard for $packageName/$year');
        return;
      }

      final List<Map<String, Object?>> tables = await importedShard.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'shots_%'",
      );

      final Map<String, Set<String>> targetColumnsCache =
          <String, Set<String>>{};

      for (final Map<String, Object?> tableRow in tables) {
        final String? tableName = tableRow['name'] as String?;
        if (tableName == null || tableName.length < 11) continue;
        final String suffix = tableName.substring(tableName.length - 2);
        final int? month = int.tryParse(suffix);
        if (month == null || month < 1 || month > 12) continue;

        await _ensureMonthTable(targetShard, year, month);

        final Set<String> targetColumns = targetColumnsCache[tableName] ??=
            await _tryListTableColumns(targetShard, tableName);

        final List<Map<String, Object?>> existingRows = await targetShard.query(
          tableName,
          columns: ['id', 'file_path'],
        );
        final Map<String, int> existingPaths = <String, int>{};
        int maxId = 0;
        int existingIndex = 0;
        for (final Map<String, Object?> row in existingRows) {
          existingIndex++;
          final String? path = row['file_path'] as String?;
          final int id = (row['id'] as int?) ?? 0;
          if (path != null && path.isNotEmpty) {
            existingPaths[path] = id;
          }
          if (id > maxId) maxId = id;
          if (existingIndex % 5000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        final List<Map<String, Object?>> rows = await importedShard.query(
          tableName,
        );

        int rowIndex = 0;
        for (final Map<String, Object?> row in rows) {
          rowIndex++;
          final int oldId = (row['id'] as int?) ?? 0;
          if (oldId <= 0) continue;

          final String? oldPath = row['file_path'] as String?;
          if (oldPath == null || oldPath.isEmpty) {
            ctx.warnings.add(
              'Row with empty file_path skipped: $packageName $year $tableName',
            );
            continue;
          }

          final String? relative = _relativizeOutputPath(oldPath);
          if (relative == null || relative.isEmpty) {
            ctx.warnings.add('Cannot relativize $oldPath, skip.');
            continue;
          }

          final String? newAbsolute = ctx.relativePathMapping[relative];
          if (newAbsolute == null || newAbsolute.isEmpty) {
            ctx.warnings.add('File not copied for $relative, skip record.');
            continue;
          }

          if (existingPaths.containsKey(newAbsolute)) {
            ctx.skippedScreenshotDuplicates++;
            final int existingId = existingPaths[newAbsolute]!;
            final int existingGid = _encodeGid(year, month, existingId);
            final int oldGid = _encodeGid(year, month, oldId);
            ctx.gidMapping[oldGid] = existingGid;
            if (rowIndex % 5000 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
            continue;
          }

          maxId++;
          final Map<String, Object?> insertRow = _filterByColumns(
            row,
            targetColumns,
          );
          if (targetColumns.contains('id')) {
            insertRow['id'] = maxId;
          }
          if (targetColumns.contains('file_path')) {
            insertRow['file_path'] = newAbsolute;
          }
          try {
            final File f = File(newAbsolute);
            if (await f.exists()) {
              if (targetColumns.contains('file_size')) {
                insertRow['file_size'] = await f.length();
              }
            }
          } catch (_) {}

          await targetShard.insert(
            tableName,
            insertRow,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );

          final int newGid = _encodeGid(year, month, maxId);
          final int oldGid = _encodeGid(year, month, oldId);
          ctx.gidMapping[oldGid] = newGid;
          existingPaths[newAbsolute] = maxId;
          ctx.insertedScreenshots++;

          if (rowIndex % 5000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      }
    } catch (e) {
      ctx.warnings.add('Failed to merge shard for $packageName/$year: $e');
    } finally {
      await importedShard?.close();
    }
  }

  Future<void> _mergeMetadataDatabase({
    required Directory baseDir,
    required Directory stagingOutput,
    required _MergeContext ctx,
    void Function(ImportExportProgress progress)? progress,
  }) async {
    final Directory targetDbDir = Directory(
      join(baseDir.path, 'output', 'databases'),
    );
    if (!await targetDbDir.exists()) {
      await targetDbDir.create(recursive: true);
    }
    final File targetMaster = File(
      join(targetDbDir.path, 'screenshot_memo.db'),
    );
    if (!await targetMaster.exists()) {
      ctx.warnings.add(
        'Target screenshot_memo.db missing, skip metadata merge.',
      );
      return;
    }

    final File importedMaster = File(
      join(stagingOutput.path, 'databases', 'screenshot_memo.db'),
    );
    if (!await importedMaster.exists()) {
      ctx.warnings.add(
        'Imported screenshot_memo.db missing, skip metadata merge.',
      );
      return;
    }

    Database? targetDb;
    Database? importedDb;
    try {
      targetDb = await openDatabase(targetMaster.path);
      importedDb = await openDatabase(importedMaster.path, readOnly: true);

      await targetDb.transaction((txn) async {
        await _mergeFavoritesTable(importedDb!, txn, ctx);
        await _mergeNsfwFlags(importedDb, txn, ctx);
        await _mergeUserSettings(importedDb, txn);
      });
    } catch (e) {
      ctx.warnings.add('Metadata merge failed: $e');
    } finally {
      await importedDb?.close();
      await targetDb?.close();
    }
  }

  Future<void> _copyRemainingDatabases({
    required Directory baseDir,
    required Directory stagingOutput,
    required _MergeContext ctx,
  }) async {
    final Directory stagingDbDir = Directory(
      join(stagingOutput.path, 'databases'),
    );
    if (!await stagingDbDir.exists()) return;

    final Directory targetDbDir = Directory(
      join(baseDir.path, 'output', 'databases'),
    );
    if (!await targetDbDir.exists()) {
      await targetDbDir.create(recursive: true);
    }

    final List<FileSystemEntity> entries = await stagingDbDir
        .list(followLinks: false)
        .toList();
    for (final FileSystemEntity entry in entries) {
      if (entry is! File) continue;
      final String name = basename(entry.path);
      if (name == 'screenshot_memo.db' || name == 'memory_backend.db') {
        continue;
      }
      final File destination = File(join(targetDbDir.path, name));
      File targetFile = destination;
      if (await destination.exists()) {
        targetFile = await _resolveUniqueFile(destination);
        ctx.warnings.add(
          'Database $name already exists; copied as ${basename(targetFile.path)}',
        );
      }
      await entry.copy(targetFile.path);
      ctx.copiedFiles++;
      await _copyDbSidecar(entry.path, targetFile.path, '-wal');
      await _copyDbSidecar(entry.path, targetFile.path, '-shm');
    }
  }

  Future<void> _mergeFavoritesTable(
    Database importedDb,
    Transaction txn,
    _MergeContext ctx,
  ) async {
    if (!await _tableExists(importedDb, 'favorites')) {
      return;
    }
    if (!await _tableExists(txn, 'favorites')) {
      return;
    }
    final Set<String> importCols = await _tryListTableColumns(
      importedDb,
      'favorites',
    );
    final Set<String> targetCols = await _tryListTableColumns(txn, 'favorites');
    if (!importCols.contains('screenshot_id') ||
        !importCols.contains('app_package_name')) {
      return;
    }
    final List<String> selectCols = <String>[
      'screenshot_id',
      'app_package_name',
      if (importCols.contains('favorite_time')) 'favorite_time',
      if (importCols.contains('note')) 'note',
      if (importCols.contains('created_at')) 'created_at',
      if (importCols.contains('updated_at')) 'updated_at',
    ];
    final List<Map<String, Object?>> rows = await importedDb.query(
      'favorites',
      columns: selectCols,
    );
    for (final Map<String, Object?> row in rows) {
      final int? oldId = row['screenshot_id'] as int?;
      final String? pkg = row['app_package_name'] as String?;
      if (oldId == null || pkg == null) continue;
      final int? newId = ctx.gidMapping[oldId];
      if (newId == null) continue;

      try {
        final Map<String, Object?> insertRow = <String, Object?>{
          if (targetCols.contains('screenshot_id')) 'screenshot_id': newId,
          if (targetCols.contains('app_package_name')) 'app_package_name': pkg,
          if (targetCols.contains('favorite_time'))
            'favorite_time': row['favorite_time'],
          if (targetCols.contains('note')) 'note': row['note'],
          if (targetCols.contains('created_at'))
            'created_at': row['created_at'],
          if (targetCols.contains('updated_at'))
            'updated_at': row['updated_at'],
        };
        await txn.insert(
          'favorites',
          insertRow,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (e) {
        ctx.warnings.add('Insert favorite failed for $pkg/$newId: $e');
      }
    }
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    try {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ? LIMIT 1",
        <Object?>[tableName],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _mergeNsfwFlags(
    Database importedDb,
    Transaction txn,
    _MergeContext ctx,
  ) async {
    if (!await _tableExists(importedDb, 'nsfw_manual_flags')) {
      return;
    }
    if (!await _tableExists(txn, 'nsfw_manual_flags')) {
      return;
    }
    final Set<String> importCols = await _tryListTableColumns(
      importedDb,
      'nsfw_manual_flags',
    );
    final Set<String> targetCols = await _tryListTableColumns(
      txn,
      'nsfw_manual_flags',
    );
    if (!importCols.contains('screenshot_id') ||
        !importCols.contains('app_package_name')) {
      return;
    }
    final List<String> selectCols = <String>[
      'screenshot_id',
      'app_package_name',
      if (importCols.contains('flag')) 'flag',
      if (importCols.contains('created_at')) 'created_at',
      if (importCols.contains('updated_at')) 'updated_at',
    ];
    final List<Map<String, Object?>> rows = await importedDb.query(
      'nsfw_manual_flags',
      columns: selectCols,
    );
    for (final Map<String, Object?> row in rows) {
      final int? oldId = row['screenshot_id'] as int?;
      final String? pkg = row['app_package_name'] as String?;
      if (oldId == null || pkg == null) continue;
      final int? newId = ctx.gidMapping[oldId];
      if (newId == null) continue;
      try {
        final Map<String, Object?> insertRow = <String, Object?>{
          if (targetCols.contains('screenshot_id')) 'screenshot_id': newId,
          if (targetCols.contains('app_package_name')) 'app_package_name': pkg,
          if (targetCols.contains('flag')) 'flag': row['flag'],
          if (targetCols.contains('created_at'))
            'created_at': row['created_at'],
          if (targetCols.contains('updated_at'))
            'updated_at': row['updated_at'],
        };
        await txn.insert(
          'nsfw_manual_flags',
          insertRow,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (e) {
        ctx.warnings.add('Insert NSFW flag failed for $pkg/$newId: $e');
      }
    }
  }

  Future<void> _mergeUserSettings(Database importedDb, Transaction txn) async {
    if (!await _tableExists(importedDb, 'user_settings')) {
      return;
    }
    if (!await _tableExists(txn, 'user_settings')) {
      return;
    }
    final Set<String> importCols = await _tryListTableColumns(
      importedDb,
      'user_settings',
    );
    final Set<String> targetCols = await _tryListTableColumns(
      txn,
      'user_settings',
    );
    if (!importCols.contains('key')) {
      return;
    }
    final List<String> selectCols = <String>[
      'key',
      if (importCols.contains('value')) 'value',
      if (importCols.contains('updated_at')) 'updated_at',
    ];
    final List<Map<String, Object?>> rows = await importedDb.query(
      'user_settings',
      columns: selectCols,
    );

    final List<Map<String, Object?>> existing = await txn.query(
      'user_settings',
      columns: ['key'],
    );
    final Set<String> existingKeys = existing
        .map((Map<String, Object?> e) => e['key'] as String?)
        .whereType<String>()
        .toSet();

    for (final Map<String, Object?> row in rows) {
      final String? key = row['key'] as String?;
      if (key == null || existingKeys.contains(key)) continue;
      try {
        final Map<String, Object?> insertRow = <String, Object?>{
          if (targetCols.contains('key')) 'key': key,
          if (targetCols.contains('value')) 'value': row['value'],
          if (targetCols.contains('updated_at'))
            'updated_at': row['updated_at'],
        };
        await txn.insert(
          'user_settings',
          insertRow,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (_) {}
    }
  }

  Future<int?> _tryReadUserVersion(DatabaseExecutor db) async {
    try {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'PRAGMA user_version',
      );
      if (rows.isEmpty) return null;
      final Object? v = rows.first['user_version'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _tryListTableColumns(
    DatabaseExecutor db,
    String tableName,
  ) async {
    try {
      final String safe = tableName.replaceAll("'", "''");
      final List<Map<String, Object?>> rows = await db.rawQuery(
        "PRAGMA table_info('$safe')",
      );
      final Set<String> cols = <String>{};
      for (final Map<String, Object?> row in rows) {
        final String? name = row['name'] as String?;
        if (name == null || name.isEmpty) continue;
        cols.add(name);
      }
      return cols;
    } catch (_) {
      return <String>{};
    }
  }

  Map<String, Object?> _filterByColumns(
    Map<String, Object?> row,
    Set<String> allowed,
  ) {
    if (allowed.isEmpty) {
      return Map<String, Object?>.from(row);
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in row.entries) {
      if (!allowed.contains(entry.key)) continue;
      result[entry.key] = entry.value;
    }
    return result;
  }

  Future<void> _finalizeMerge(_MergeContext ctx) async {
    final Database db = await database;
    try {
      for (final String pkg in ctx.affectedPackages) {
        await _recomputeAppStatForPackage(db, pkg);
      }
      await recalculateTotals();
    } catch (e) {
      ctx.warnings.add('Failed to recompute totals: $e');
    }
  }

  Future<bool> _filesIdentical(File a, File b) async {
    try {
      final int lenA = await a.length();
      final int lenB = await b.length();
      if (lenA != lenB) return false;
      final RandomAccessFile rafA = await a.open();
      final RandomAccessFile rafB = await b.open();
      final int chunkSize = 64 * 1024;
      final Uint8List bufferA = Uint8List(chunkSize);
      final Uint8List bufferB = Uint8List(chunkSize);
      try {
        while (true) {
          final int readA = await rafA.readInto(bufferA);
          final int readB = await rafB.readInto(bufferB);
          if (readA != readB) return false;
          if (readA == 0) break;
          for (int i = 0; i < readA; i++) {
            if (bufferA[i] != bufferB[i]) {
              return false;
            }
          }
        }
      } finally {
        await rafA.close();
        await rafB.close();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File> _resolveUniqueFile(File original) async {
    File candidate = original;
    int counter = 1;
    final String dir = candidate.parent.path;
    final String name = basenameWithoutExtension(candidate.path);
    final String ext = extension(candidate.path);
    while (await candidate.exists()) {
      candidate = File(join(dir, '${name}_merge_$counter$ext'));
      counter++;
    }
    return candidate;
  }

  Future<void> _copyDbSidecar(
    String sourceBase,
    String targetBase,
    String suffix,
  ) async {
    final File source = File(sourceBase + suffix);
    if (!await source.exists()) return;
    final File target = File(targetBase + suffix);
    final Directory parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await source.copy(target.path);
  }

  Future<MergeZipAuditReport> auditMergeInputZip(String zipPath) async {
    final Stopwatch sw = Stopwatch()..start();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final List<String> warnings = <String>[];
    final List<String> blockingIssues = <String>[];
    final Set<String> packages = <String>{};
    final List<String> smmSamples = <String>[];
    final List<String> sidecarSamples = <String>[];
    int screenFileCount = 0;
    int smmDbCount = 0;
    int dbSidecarFileCount = 0;
    bool masterDbExists = false;
    late final Archive archive;

    try {
      final InputFileStream input = InputFileStream(zipPath);
      try {
        archive = ZipDecoder().decodeBuffer(input);
      } finally {
        input.close();
      }
    } catch (e) {
      sw.stop();
      return MergeZipAuditReport(
        sourcePath: zipPath,
        sourceKind: 'zip',
        timestampMillis: ts,
        durationMs: sw.elapsedMilliseconds,
        screenFileCount: 0,
        screenPackageCount: 0,
        samplePackages: const <String>[],
        masterDbExists: false,
        masterDbReadable: false,
        masterDbReadError: e.toString(),
        userVersion: null,
        smmDbCount: 0,
        sampleSmmDbPaths: const <String>[],
        dbSidecarFileCount: 0,
        sampleDbSidecarPaths: const <String>[],
        registryCounts: const <String, int?>{
          'app_registry': null,
          'app_stats': null,
          'shard_registry': null,
          'totals': null,
        },
        blockingIssues: <String>['ZIP 无法读取或不是有效备份：$e'],
        warnings: const <String>[],
      );
    }

    ArchiveFile? masterEntry;
    ArchiveFile? walEntry;
    ArchiveFile? shmEntry;

    for (final ArchiveFile file in archive.files) {
      if (!file.isFile) continue;
      final String normalized = _normalizeMergeBackupEntryPath(file.name);
      if (normalized.isEmpty) continue;
      final String lower = normalized.toLowerCase();
      if (lower.startsWith('screen/')) {
        screenFileCount++;
        final List<String> parts = normalized.split('/');
        if (parts.length >= 2 && parts[1].trim().isNotEmpty) {
          packages.add(parts[1].trim());
        }
      }
      if (lower == 'databases/screenshot_memo.db') {
        masterDbExists = true;
        masterEntry = file;
      } else if (lower == 'databases/screenshot_memo.db-wal') {
        walEntry = file;
        dbSidecarFileCount++;
        if (sidecarSamples.length < 10) {
          sidecarSamples.add(normalized);
        }
      } else if (lower == 'databases/screenshot_memo.db-shm') {
        shmEntry = file;
        dbSidecarFileCount++;
        if (sidecarSamples.length < 10) {
          sidecarSamples.add(normalized);
        }
      } else if (_isSmmShardDbPath(normalized)) {
        smmDbCount++;
        if (smmSamples.length < 10) {
          smmSamples.add(normalized);
        }
      } else if (lower.endsWith('.db-wal') || lower.endsWith('.db-shm')) {
        dbSidecarFileCount++;
        if (sidecarSamples.length < 10) {
          sidecarSamples.add(normalized);
        }
      }
    }

    if (screenFileCount <= 0) {
      blockingIssues.add('未发现任何 screen 文件，不能作为可合并备份。');
    }
    if (!masterDbExists) {
      blockingIssues.add('缺少 databases/screenshot_memo.db。');
    }
    if (screenFileCount > 0 && smmDbCount <= 0) {
      blockingIssues.add('检测到 screen 有内容，但没有任何 smm_*.db 分库。');
    }

    _MasterDbProbeResult? probe;
    if (masterEntry != null) {
      Directory? tempDir;
      try {
        tempDir = await Directory.systemTemp.createTemp(
          'screenmemo_merge_zip_',
        );
        final String masterPath = join(tempDir.path, 'screenshot_memo.db');
        final OutputFileStream masterOut = OutputFileStream(masterPath);
        masterEntry.writeContent(masterOut);
        await masterOut.close();

        if (walEntry != null) {
          final OutputFileStream walOut = OutputFileStream('$masterPath-wal');
          walEntry.writeContent(walOut);
          await walOut.close();
        }
        if (shmEntry != null) {
          final OutputFileStream shmOut = OutputFileStream('$masterPath-shm');
          shmEntry.writeContent(shmOut);
          await shmOut.close();
        }

        probe = await _probeMasterDbSnapshot(masterPath);
      } catch (e) {
        warnings.add('读取 ZIP 内 screenshot_memo.db 失败: $e');
      } finally {
        if (tempDir != null) {
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        }
      }
    }

    final Map<String, int?> registryCounts =
        probe?.rowCounts ??
        <String, int?>{
          'app_registry': null,
          'app_stats': null,
          'shard_registry': null,
          'totals': null,
        };

    if (probe != null) {
      if (!probe.openOk) {
        blockingIssues.add('主库不可读：${probe.openError ?? 'unknown error'}');
      }
      if (probe.sidecarOpenFailed) {
        blockingIssues.add(
          '主库 WAL/SHM 快照不一致：${probe.sidecarOpenError ?? 'unknown error'}',
        );
      }
    }

    if (screenFileCount > 0 && (registryCounts['shard_registry'] ?? 0) <= 0) {
      blockingIssues.add('主库 shard_registry 为空。');
    }
    if (screenFileCount > 0 && (registryCounts['app_registry'] ?? 0) <= 0) {
      blockingIssues.add('主库 app_registry 为空。');
    }
    if (screenFileCount > 0 && (registryCounts['app_stats'] ?? 0) <= 0) {
      blockingIssues.add('主库 app_stats 为空。');
    }
    if (screenFileCount > 0 && (registryCounts['totals'] ?? 0) <= 0) {
      blockingIssues.add('主库 totals 为空。');
    }

    sw.stop();
    final List<String> samplePackages = packages.toList()..sort();
    final MergeZipAuditReport report = MergeZipAuditReport(
      sourcePath: zipPath,
      sourceKind: 'zip',
      timestampMillis: ts,
      durationMs: sw.elapsedMilliseconds,
      screenFileCount: screenFileCount,
      screenPackageCount: packages.length,
      samplePackages: samplePackages.length <= 10
          ? samplePackages
          : samplePackages.take(10).toList(),
      masterDbExists: masterDbExists,
      masterDbReadable: probe?.openOk ?? false,
      masterDbReadError: probe?.openError,
      userVersion: probe?.userVersion,
      smmDbCount: smmDbCount,
      sampleSmmDbPaths: smmSamples,
      dbSidecarFileCount: dbSidecarFileCount,
      sampleDbSidecarPaths: sidecarSamples,
      registryCounts: registryCounts,
      blockingIssues: blockingIssues,
      warnings: warnings,
    );
    try {
      await FlutterLogger.nativeInfo('MERGE_AUDIT', report.toText());
    } catch (_) {}
    return report;
  }

  Future<void> freezeMergedOutputForBackup({
    required String baseDirPath,
  }) async {
    final Directory dbRoot = Directory(
      join(baseDirPath, 'output', 'databases'),
    );
    if (!await dbRoot.exists()) return;

    final List<File> dbFiles = <File>[];
    await for (final FileSystemEntity entity in dbRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (entity.path.toLowerCase().endsWith('.db')) {
        dbFiles.add(entity);
      }
    }

    for (final File dbFile in dbFiles) {
      Database? db;
      try {
        db = await openDatabase(dbFile.path, singleInstance: false);
        try {
          await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        } catch (_) {
          await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        }
      } catch (e) {
        throw MergeAuditException(
          code: 'invalid_merged_output',
          message: '无法固化数据库 ${dbFile.path}: $e',
        );
      } finally {
        try {
          await db?.close();
        } catch (_) {}
      }
    }

    await for (final FileSystemEntity entity in dbRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final String lower = entity.path.toLowerCase();
      if (!lower.endsWith('.db-wal') && !lower.endsWith('.db-shm')) {
        continue;
      }
      try {
        await entity.delete();
      } catch (e) {
        throw MergeAuditException(
          code: 'invalid_merged_output',
          message: '无法删除数据库 sidecar ${entity.path}: $e',
        );
      }
    }
  }

  Future<MergeZipAuditReport> auditMergedOutputDirectory({
    required String baseDirPath,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final List<String> warnings = <String>[];
    final List<String> blockingIssues = <String>[];
    final Set<String> packages = <String>{};
    final List<String> smmSamples = <String>[];
    final List<String> sidecarSamples = <String>[];
    int screenFileCount = 0;
    int smmDbCount = 0;
    int dbSidecarFileCount = 0;

    final Directory outputDir = Directory(join(baseDirPath, 'output'));
    final Directory screenDir = Directory(join(outputDir.path, 'screen'));
    final Directory dbRoot = Directory(join(outputDir.path, 'databases'));
    final File masterDbFile = File(
      join(outputDir.path, 'databases', 'screenshot_memo.db'),
    );

    if (await screenDir.exists()) {
      await for (final FileSystemEntity entity in screenDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        screenFileCount++;
        final String relative = _relativeTo(outputDir.path, entity.path);
        final List<String> parts = relative.split('/');
        if (parts.length >= 2 &&
            parts.first == 'screen' &&
            parts[1].trim().isNotEmpty) {
          packages.add(parts[1].trim());
        }
      }
    }

    if (await dbRoot.exists()) {
      await for (final FileSystemEntity entity in dbRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final String relative = _relativeTo(outputDir.path, entity.path);
        final String lower = relative.toLowerCase();
        if (_isSmmShardDbPath(relative)) {
          smmDbCount++;
          if (smmSamples.length < 10) {
            smmSamples.add(relative);
          }
        }
        if (lower.endsWith('.db-wal') || lower.endsWith('.db-shm')) {
          dbSidecarFileCount++;
          if (sidecarSamples.length < 10) {
            sidecarSamples.add(relative);
          }
        }
      }
    }

    final bool masterDbExists = await masterDbFile.exists();
    _MasterDbProbeResult? probe;
    if (masterDbExists) {
      Directory? tempDir;
      try {
        tempDir = await Directory.systemTemp.createTemp(
          'screenmemo_merge_out_',
        );
        final String tempMasterPath = join(tempDir.path, 'screenshot_memo.db');
        await masterDbFile.copy(tempMasterPath);
        final File walFile = File('${masterDbFile.path}-wal');
        if (await walFile.exists()) {
          await walFile.copy('$tempMasterPath-wal');
        }
        final File shmFile = File('${masterDbFile.path}-shm');
        if (await shmFile.exists()) {
          await shmFile.copy('$tempMasterPath-shm');
        }
        probe = await _probeMasterDbSnapshot(tempMasterPath);
      } catch (e) {
        warnings.add('读取输出目录主库失败: $e');
      } finally {
        if (tempDir != null) {
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        }
      }
    }

    final Map<String, int?> registryCounts =
        probe?.rowCounts ??
        <String, int?>{
          'app_registry': null,
          'app_stats': null,
          'shard_registry': null,
          'totals': null,
        };

    if (screenFileCount <= 0) {
      blockingIssues.add('输出目录未发现任何 screen 文件。');
    }
    if (packages.isEmpty) {
      blockingIssues.add('输出目录未发现任何截图包目录。');
    }
    if (!masterDbExists) {
      blockingIssues.add('输出目录缺少 databases/screenshot_memo.db。');
    }
    if (smmDbCount <= 0) {
      blockingIssues.add('输出目录没有任何 smm_*.db 分库。');
    }
    if (dbSidecarFileCount > 0) {
      blockingIssues.add('输出目录仍残留 .db-wal/.db-shm sidecar 文件。');
    }
    if (probe != null) {
      if (!probe.openOk) {
        blockingIssues.add('输出目录主库不可读：${probe.openError ?? 'unknown error'}');
      }
      if (probe.sidecarOpenFailed) {
        blockingIssues.add(
          '输出目录主库 WAL/SHM 快照不一致：${probe.sidecarOpenError ?? 'unknown error'}',
        );
      }
    }
    if ((registryCounts['shard_registry'] ?? 0) <= 0) {
      blockingIssues.add('输出目录主库 shard_registry 为空。');
    }
    if ((registryCounts['app_registry'] ?? 0) <= 0) {
      blockingIssues.add('输出目录主库 app_registry 为空。');
    }
    if ((registryCounts['app_stats'] ?? 0) <= 0) {
      blockingIssues.add('输出目录主库 app_stats 为空。');
    }
    if ((registryCounts['totals'] ?? 0) <= 0) {
      blockingIssues.add('输出目录主库 totals 为空。');
    }

    sw.stop();
    final List<String> samplePackages = packages.toList()..sort();
    final MergeZipAuditReport report = MergeZipAuditReport(
      sourcePath: outputDir.path,
      sourceKind: 'output_dir',
      timestampMillis: ts,
      durationMs: sw.elapsedMilliseconds,
      screenFileCount: screenFileCount,
      screenPackageCount: packages.length,
      samplePackages: samplePackages.length <= 10
          ? samplePackages
          : samplePackages.take(10).toList(),
      masterDbExists: masterDbExists,
      masterDbReadable: probe?.openOk ?? false,
      masterDbReadError: probe?.openError,
      userVersion: probe?.userVersion,
      smmDbCount: smmDbCount,
      sampleSmmDbPaths: smmSamples,
      dbSidecarFileCount: dbSidecarFileCount,
      sampleDbSidecarPaths: sidecarSamples,
      registryCounts: registryCounts,
      blockingIssues: blockingIssues,
      warnings: warnings,
    );
    try {
      await FlutterLogger.nativeInfo('MERGE_AUDIT', report.toText());
    } catch (_) {}
    return report;
  }

  String _relativeFromScreenPath(String screenRoot, String absolutePath) {
    final String normalizedRoot = screenRoot.replaceAll('\\', '/');
    final String normalizedPath = absolutePath.replaceAll('\\', '/');
    if (!normalizedPath.startsWith(normalizedRoot)) {
      final int idx = normalizedPath.indexOf('/screen/');
      if (idx >= 0) {
        return normalizedPath.substring(idx + '/screen/'.length);
      }
      return '';
    }
    final int start = normalizedRoot.length + 1;
    if (start >= normalizedPath.length) return '';
    return normalizedPath.substring(start);
  }

  String? _relativizeOutputPath(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int idx = normalized.indexOf('/output/');
    if (idx >= 0 && idx + 8 <= normalized.length) {
      return normalized.substring(idx + '/output/'.length);
    }
    return null;
  }
}

Future<_MasterDbProbeResult> _probeMasterDbSnapshot(String masterDbPath) async {
  final String walPath = '$masterDbPath-wal';
  final String shmPath = '$masterDbPath-shm';
  final bool hasSidecars =
      await File(walPath).exists() || await File(shmPath).exists();

  final _MasterDbProbeResult result = await _queryMasterDb(masterDbPath);
  if (result.openOk || !hasSidecars) {
    return result;
  }

  final String sidecarError = result.openError ?? 'unknown error';
  try {
    if (await File(walPath).exists()) {
      await File(walPath).delete();
    }
  } catch (_) {}
  try {
    if (await File(shmPath).exists()) {
      await File(shmPath).delete();
    }
  } catch (_) {}

  final _MasterDbProbeResult fallback = await _queryMasterDb(masterDbPath);
  if (fallback.openOk) {
    return _MasterDbProbeResult(
      openOk: true,
      openError: null,
      userVersion: fallback.userVersion,
      rowCounts: fallback.rowCounts,
      sidecarOpenFailed: true,
      sidecarOpenError: sidecarError,
    );
  }

  return _MasterDbProbeResult(
    openOk: false,
    openError: result.openError ?? fallback.openError,
    userVersion: fallback.userVersion,
    rowCounts: fallback.rowCounts,
    sidecarOpenFailed: true,
    sidecarOpenError: sidecarError,
  );
}

Future<_MasterDbProbeResult> _queryMasterDb(String dbPath) async {
  final Map<String, int?> rowCounts = <String, int?>{
    'app_registry': null,
    'app_stats': null,
    'shard_registry': null,
    'totals': null,
  };
  Database? db;
  try {
    db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    int? userVersion;
    try {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'PRAGMA user_version',
      );
      if (rows.isNotEmpty) {
        final Object? value = rows.first.values.isNotEmpty
            ? rows.first.values.first
            : rows.first['user_version'];
        if (value is int) {
          userVersion = value;
        } else if (value is num) {
          userVersion = value.toInt();
        } else {
          userVersion = int.tryParse(value?.toString() ?? '');
        }
      }
    } catch (_) {}

    for (final String table in rowCounts.keys) {
      final bool exists = await _auditTableExists(db, table);
      if (!exists) {
        rowCounts[table] = 0;
        continue;
      }
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table',
      );
      final Object? value = rows.isNotEmpty ? rows.first['c'] : null;
      if (value is int) {
        rowCounts[table] = value;
      } else if (value is num) {
        rowCounts[table] = value.toInt();
      } else {
        rowCounts[table] = int.tryParse(value?.toString() ?? '');
      }
    }

    return _MasterDbProbeResult(
      openOk: true,
      openError: null,
      userVersion: userVersion,
      rowCounts: rowCounts,
      sidecarOpenFailed: false,
      sidecarOpenError: null,
    );
  } catch (e) {
    return _MasterDbProbeResult(
      openOk: false,
      openError: e.toString(),
      userVersion: null,
      rowCounts: rowCounts,
      sidecarOpenFailed: false,
      sidecarOpenError: null,
    );
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}

String _normalizeMergeBackupEntryPath(String raw) {
  String path = raw.replaceAll('\\', '/').trim();
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  path = path.replaceFirst(RegExp(r'^/+'), '');
  if (path.startsWith('output/')) {
    path = path.substring('output/'.length);
  }
  return path;
}

bool _isSmmShardDbPath(String path) {
  final String normalized = path.replaceAll('\\', '/');
  final String lower = normalized.toLowerCase();
  if (!lower.startsWith('databases/shards/')) return false;
  final String name = basename(lower);
  return name.startsWith('smm_') && name.endsWith('.db');
}

Future<bool> _auditTableExists(DatabaseExecutor db, String tableName) async {
  try {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ? LIMIT 1",
      <Object?>[tableName],
    );
    return rows.isNotEmpty;
  } catch (_) {
    return false;
  }
}

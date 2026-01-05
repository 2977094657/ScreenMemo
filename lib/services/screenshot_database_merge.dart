part of 'screenshot_database.dart';

/// 导入合并结果统计
class MergeReport {
  final int copiedFiles;
  final int reusedFiles;
  final int insertedScreenshots;
  final int skippedScreenshotDuplicates;
  final int mergedMemoryEvents;
  final int mergedMemoryTags;
  final int mergedMemoryEvidence;
  final Set<String> affectedPackages;
  final List<String> warnings;

  const MergeReport({
    required this.copiedFiles,
    required this.reusedFiles,
    required this.insertedScreenshots,
    required this.skippedScreenshotDuplicates,
    required this.mergedMemoryEvents,
    required this.mergedMemoryTags,
    required this.mergedMemoryEvidence,
    required this.affectedPackages,
    required this.warnings,
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
  int mergedMemoryEvents = 0;
  int mergedMemoryTags = 0;
  int mergedMemoryEvidence = 0;

  MergeReport toReport() {
    return MergeReport(
      copiedFiles: copiedFiles,
      reusedFiles: reusedFiles,
      insertedScreenshots: insertedScreenshots,
      skippedScreenshotDuplicates: skippedScreenshotDuplicates,
      mergedMemoryEvents: mergedMemoryEvents,
      mergedMemoryTags: mergedMemoryTags,
      mergedMemoryEvidence: mergedMemoryEvidence,
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

      final Map<String, dynamic>? extraction = await _runImportZipWithProgress(
        localZipPath: localZipPath!,
        outputDirPath: stagingOutput.path,
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
    );

    await _mergeMemoryDatabase(
      baseDir: baseDir,
      stagingOutput: stagingOutput,
      ctx: ctx,
      progress: progress,
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

    final File importedMaster = File(
      join(stagingDbDir.path, 'screenshot_memo.db'),
    );
    if (!await importedMaster.exists()) {
      ctx.warnings.add('Imported screenshot_memo.db not found, skip DB merge.');
      return;
    }

    Database? importedDb;
    try {
      importedDb = await openDatabase(importedMaster.path, readOnly: true);
      final List<Map<String, Object?>> apps = await importedDb.query(
        'app_registry',
        columns: ['app_package_name', 'app_name'],
      );
      final Map<String, String> appNames = <String, String>{};
      for (final Map<String, Object?> row in apps) {
        final String? pkg = row['app_package_name'] as String?;
        if (pkg == null) continue;
        final String? name = row['app_name'] as String?;
        appNames[pkg] = name ?? pkg;
      }

      final List<Map<String, Object?>> shards = await importedDb.query(
        'shard_registry',
        columns: ['app_package_name', 'year'],
      );

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
          'smm_${sanitized}_${year}.db',
        );

        final File shardFile = File(shardPath);
        if (!await shardFile.exists()) {
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
    } finally {
      await importedDb?.close();
    }
  }

  Future<void> _mergeMemoryDatabase({
    required Directory baseDir,
    required Directory stagingOutput,
    required _MergeContext ctx,
    void Function(ImportExportProgress progress)? progress,
  }) async {
    final File importedMemory = File(
      join(stagingOutput.path, 'databases', 'memory_backend.db'),
    );
    if (!await importedMemory.exists()) {
      return;
    }

    final Directory targetDbDir = Directory(
      join(baseDir.path, 'output', 'databases'),
    );
    if (!await targetDbDir.exists()) {
      await targetDbDir.create(recursive: true);
    }
    final File targetMemory = File(join(targetDbDir.path, 'memory_backend.db'));

    if (!await targetMemory.exists()) {
      Database? importDb;
      try {
        importDb = await openDatabase(importedMemory.path, readOnly: true);
        ctx.mergedMemoryEvents +=
            Sqflite.firstIntValue(
              await importDb.rawQuery('SELECT COUNT(*) FROM memory_events'),
            ) ??
            0;
        ctx.mergedMemoryTags +=
            Sqflite.firstIntValue(
              await importDb.rawQuery('SELECT COUNT(*) FROM memory_tags'),
            ) ??
            0;
        ctx.mergedMemoryEvidence +=
            Sqflite.firstIntValue(
              await importDb.rawQuery(
                'SELECT COUNT(*) FROM memory_tag_evidence',
              ),
            ) ??
            0;
      } catch (e) {
        ctx.warnings.add('读取记忆数据库失败: $e');
      } finally {
        await importDb?.close();
      }

      await importedMemory.copy(targetMemory.path);
      ctx.copiedFiles++;
      await _copyDbSidecar(importedMemory.path, targetMemory.path, '-wal');
      await _copyDbSidecar(importedMemory.path, targetMemory.path, '-shm');
      ctx.affectedPackages.add('memory_backend');
      progress?.call(
        const ImportExportProgress(
          value: 0.9,
          stage: 'merge_memory_database',
          currentEntry: null,
        ),
      );
      return;
    }

    Database? importDb;
    Database? targetDb;
    try {
      importDb = await openDatabase(importedMemory.path, readOnly: true);
      targetDb = await openDatabase(targetMemory.path);

      await targetDb.transaction((txn) async {
        final Map<int, int> eventIdMap = <int, int>{};
        final Map<String, int> externalEventMap = <String, int>{};
        final Map<String, int> compositeEventMap = <String, int>{};

        final List<Map<String, Object?>> existingEvents = await txn.query(
          'memory_events',
          columns: [
            'id',
            'external_id',
            'occurred_at',
            'source',
            'type',
            'content',
          ],
        );
        int existingEventIndex = 0;
        for (final Map<String, Object?> row in existingEvents) {
          existingEventIndex++;
          final int id = (row['id'] as int?) ?? 0;
          final String? ext = row['external_id'] as String?;
          if (ext != null && ext.isNotEmpty) {
            externalEventMap[ext] = id;
          }
          compositeEventMap[_memoryEventKey(row)] = id;
          if (existingEventIndex % 5000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        final List<Map<String, Object?>> importEvents = await importDb!.query(
          'memory_events',
          orderBy: 'id ASC',
        );
        int importEventIndex = 0;
        for (final Map<String, Object?> row in importEvents) {
          importEventIndex++;
          final int oldId = (row['id'] as int?) ?? 0;
          if (oldId <= 0) continue;
          int? resolvedId;
          final String? ext = row['external_id'] as String?;
          if (ext != null && ext.isNotEmpty) {
            resolvedId = externalEventMap[ext];
          }
          if (resolvedId == null) {
            resolvedId = compositeEventMap[_memoryEventKey(row)];
          }
          if (resolvedId != null) {
            eventIdMap[oldId] = resolvedId;
            if (importEventIndex % 5000 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
            continue;
          }

          final Map<String, Object?> insertRow = Map<String, Object?>.from(row);
          insertRow.remove('id');
          final int newId = await txn.insert('memory_events', insertRow);
          if (newId > 0) {
            eventIdMap[oldId] = newId;
            if (ext != null && ext.isNotEmpty) {
              externalEventMap[ext] = newId;
            }
            compositeEventMap[_memoryEventKey(row)] = newId;
            ctx.mergedMemoryEvents++;
          } else if (ext != null && ext.isNotEmpty) {
            final List<Map<String, Object?>> fallback = await txn.query(
              'memory_events',
              columns: ['id'],
              where: 'external_id = ?',
              whereArgs: [ext],
              limit: 1,
            );
            if (fallback.isNotEmpty) {
              final int existingId = (fallback.first['id'] as int?) ?? 0;
              if (existingId > 0) {
                eventIdMap[oldId] = existingId;
              }
            }
          }
          if (importEventIndex % 5000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        final Map<int, int> tagIdMap = <int, int>{};
        final Map<String, Map<String, Object?>> existingTagRows =
            <String, Map<String, Object?>>{};
        final Map<String, int> tagKeyToId = <String, int>{};

        final List<Map<String, Object?>> existingTags = await txn.query(
          'memory_tags',
        );
        int existingTagIndex = 0;
        for (final Map<String, Object?> row in existingTags) {
          existingTagIndex++;
          final String key = (row['tag_key'] as String?) ?? '';
          if (key.isEmpty) continue;
          final int id = (row['id'] as int?) ?? 0;
          tagKeyToId[key] = id;
          existingTagRows[key] = Map<String, Object?>.from(row);
          if (existingTagIndex % 5000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        final List<Map<String, Object?>> importTags = await importDb.query(
          'memory_tags',
          orderBy: 'id ASC',
        );
        for (final Map<String, Object?> row in importTags) {
          final int oldId = (row['id'] as int?) ?? 0;
          if (oldId <= 0) continue;
          final String tagKey = (row['tag_key'] as String?) ?? '';
          if (tagKey.isEmpty) continue;

          if (tagKeyToId.containsKey(tagKey)) {
            final int existingId = tagKeyToId[tagKey]!;
            final Map<String, Object?> merged = _mergeTagRows(
              existingTagRows[tagKey] ?? <String, Object?>{},
              row,
            );
            final Map<String, Object?> updateRow = Map<String, Object?>.from(
              merged,
            )..remove('id');
            await txn.update(
              'memory_tags',
              updateRow,
              where: 'id = ?',
              whereArgs: [existingId],
            );
            existingTagRows[tagKey] = Map<String, Object?>.from(merged)
              ..['id'] = existingId;
            tagIdMap[oldId] = existingId;
            continue;
          }

          final Map<String, Object?> insertRow = Map<String, Object?>.from(row)
            ..remove('id');
          final int newTagId = await txn.insert('memory_tags', insertRow);
          if (newTagId > 0) {
            tagIdMap[oldId] = newTagId;
            tagKeyToId[tagKey] = newTagId;
            existingTagRows[tagKey] = Map<String, Object?>.from(row)
              ..['id'] = newTagId;
            ctx.mergedMemoryTags++;
          }
        }

        final List<Map<String, Object?>> importMetadata = await importDb.query(
          'memory_metadata',
        );
        for (final Map<String, Object?> row in importMetadata) {
          final String? key = row['key'] as String?;
          if (key == null) continue;
          final List<Map<String, Object?>> existing = await txn.query(
            'memory_metadata',
            where: '`key` = ?',
            whereArgs: [key],
            limit: 1,
          );
          if (existing.isEmpty) {
            await txn.insert('memory_metadata', row);
          } else {
            final String? currentValue = existing.first['value'] as String?;
            final String? incomingValue = row['value'] as String?;
            if ((currentValue == null || currentValue.isEmpty) &&
                (incomingValue != null && incomingValue.isNotEmpty)) {
              await txn.update(
                'memory_metadata',
                {'value': incomingValue},
                where: '`key` = ?',
                whereArgs: [key],
              );
            }
          }
        }

        final List<Map<String, Object?>> importEvidence = await importDb.query(
          'memory_tag_evidence',
          orderBy: 'id ASC',
        );
        for (final Map<String, Object?> row in importEvidence) {
          final int oldTagId = (row['tag_id'] as int?) ?? -1;
          final int oldEventId = (row['event_id'] as int?) ?? -1;
          final int? newTagId = tagIdMap[oldTagId];
          final int? newEventId = eventIdMap[oldEventId];
          if (newTagId == null || newEventId == null) continue;

          final Map<String, Object?> insertRow = Map<String, Object?>.from(row);
          insertRow.remove('id');
          insertRow['tag_id'] = newTagId;
          insertRow['event_id'] = newEventId;
          final int insertedId = await txn.insert(
            'memory_tag_evidence',
            insertRow,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (insertedId > 0) {
            ctx.mergedMemoryEvidence++;
          }
        }
      });
      ctx.affectedPackages.add('memory_backend');
    } catch (e) {
      ctx.warnings.add('合并记忆数据库失败: $e');
    } finally {
      await importDb?.close();
      await targetDb?.close();
    }

    progress?.call(
      const ImportExportProgress(
        value: 0.9,
        stage: 'merge_memory_database',
        currentEntry: null,
      ),
    );
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

      for (final Map<String, Object?> tableRow in tables) {
        final String? tableName = tableRow['name'] as String?;
        if (tableName == null || tableName.length < 11) continue;
        final String suffix = tableName.substring(tableName.length - 2);
        final int? month = int.tryParse(suffix);
        if (month == null || month < 1 || month > 12) continue;

        await _ensureMonthTable(targetShard, year, month);

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
          final Map<String, Object?> insertRow = Map<String, Object?>.from(row);
          insertRow['id'] = maxId;
          insertRow['file_path'] = newAbsolute;
          try {
            final File f = File(newAbsolute);
            if (await f.exists()) {
              insertRow['file_size'] = await f.length();
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
    final List<Map<String, Object?>> rows = await importedDb.query(
      'favorites',
      columns: [
        'screenshot_id',
        'app_package_name',
        'favorite_time',
        'note',
        'created_at',
        'updated_at',
      ],
    );
    for (final Map<String, Object?> row in rows) {
      final int? oldId = row['screenshot_id'] as int?;
      final String? pkg = row['app_package_name'] as String?;
      if (oldId == null || pkg == null) continue;
      final int? newId = ctx.gidMapping[oldId];
      if (newId == null) continue;

      try {
        await txn.insert('favorites', <String, Object?>{
          'screenshot_id': newId,
          'app_package_name': pkg,
          'favorite_time': row['favorite_time'],
          'note': row['note'],
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
    final List<Map<String, Object?>> rows = await importedDb.query(
      'nsfw_manual_flags',
      columns: [
        'screenshot_id',
        'app_package_name',
        'flag',
        'created_at',
        'updated_at',
      ],
    );
    for (final Map<String, Object?> row in rows) {
      final int? oldId = row['screenshot_id'] as int?;
      final String? pkg = row['app_package_name'] as String?;
      if (oldId == null || pkg == null) continue;
      final int? newId = ctx.gidMapping[oldId];
      if (newId == null) continue;
      try {
        await txn.insert('nsfw_manual_flags', <String, Object?>{
          'screenshot_id': newId,
          'app_package_name': pkg,
          'flag': row['flag'],
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
    final List<Map<String, Object?>> rows = await importedDb.query(
      'user_settings',
      columns: ['key', 'value', 'updated_at'],
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
        await txn.insert('user_settings', <String, Object?>{
          'key': key,
          'value': row['value'],
          'updated_at': row['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }
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

  String _memoryEventKey(Map<String, Object?> row) {
    final Object? occurred = row['occurred_at'];
    final String type = (row['type'] as String?) ?? '';
    final String source = (row['source'] as String?) ?? '';
    final String content = (row['content'] as String?) ?? '';
    return '${occurred ?? 0}|$source|$type|$content';
  }

  Map<String, Object?> _mergeTagRows(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    if (existing.isEmpty) {
      return Map<String, Object?>.from(incoming);
    }

    final Map<String, Object?> result = Map<String, Object?>.from(existing);

    result['label'] = _preferString(existing['label'], incoming['label']);
    result['level1'] = _preferString(existing['level1'], incoming['level1']);
    result['level2'] = _preferString(existing['level2'], incoming['level2']);
    result['level3'] = _preferString(existing['level3'], incoming['level3']);
    result['level4'] = _preferString(existing['level4'], incoming['level4']);
    result['full_path'] = _preferString(
      existing['full_path'],
      incoming['full_path'],
    );

    final int existingOccurrences = _asInt(existing['occurrences']);
    final int incomingOccurrences = _asInt(incoming['occurrences']);
    result['occurrences'] = existingOccurrences + incomingOccurrences;

    final double existingConfidence = _asDouble(existing['confidence']);
    final double incomingConfidence = _asDouble(incoming['confidence']);
    result['confidence'] = math.max(existingConfidence, incomingConfidence);

    final int existingFirst = _asInt(existing['first_seen_at']);
    final int incomingFirst = _asInt(incoming['first_seen_at']);
    if (existingFirst == 0) {
      result['first_seen_at'] = incomingFirst;
    } else if (incomingFirst == 0) {
      result['first_seen_at'] = existingFirst;
    } else {
      result['first_seen_at'] = math.min(existingFirst, incomingFirst);
    }

    final int existingLast = _asInt(existing['last_seen_at']);
    final int incomingLast = _asInt(incoming['last_seen_at']);
    result['last_seen_at'] = math.max(existingLast, incomingLast);

    final String existingStatus = (existing['status'] as String?) ?? 'pending';
    final String incomingStatus = (incoming['status'] as String?) ?? 'pending';
    if (incomingStatus == 'confirmed' || existingStatus == 'confirmed') {
      result['status'] = 'confirmed';
    }

    final String existingCategory =
        (existing['category'] as String?) ?? 'other';
    final String incomingCategory =
        (incoming['category'] as String?) ?? existingCategory;
    if (existingCategory == 'other' && incomingCategory.isNotEmpty) {
      result['category'] = incomingCategory;
    }

    final int incomingAutoConfirmed = _asInt(incoming['auto_confirmed_at']);
    final int existingAutoConfirmed = _asInt(existing['auto_confirmed_at']);
    if (existingAutoConfirmed == 0 && incomingAutoConfirmed != 0) {
      result['auto_confirmed_at'] = incomingAutoConfirmed;
    }

    final int incomingManualConfirmed = _asInt(incoming['manual_confirmed_at']);
    final int existingManualConfirmed = _asInt(existing['manual_confirmed_at']);
    if (existingManualConfirmed == 0 && incomingManualConfirmed != 0) {
      result['manual_confirmed_at'] = incomingManualConfirmed;
    }

    return result;
  }

  String _preferString(Object? primary, Object? secondary) {
    final String first = (primary as String?)?.trim() ?? '';
    if (first.isNotEmpty) return first;
    return (secondary as String?)?.trim() ?? '';
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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

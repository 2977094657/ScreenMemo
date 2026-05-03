import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:screen_memo/data/platform/path_service.dart';

const String backupManifestFileName = 'backup_manifest.json';
const int backupManifestVersion = 2;

class BackupCategoryIds {
  static const String screenshots = 'screenshots';
  static const String mainDatabase = 'main_database';
  static const String shardDatabases = 'shard_databases';
  static const String perAppSettings = 'per_app_settings';
  static const String otherOutput = 'other_output';
  static const String sharedPrefs = 'shared_prefs';
  static const String appFlutter = 'app_flutter';
  static const String noBackup = 'no_backup';
  static const String appDatabases = 'app_databases';

  static const List<String> ordered = <String>[
    screenshots,
    mainDatabase,
    shardDatabases,
    perAppSettings,
    otherOutput,
    sharedPrefs,
    appFlutter,
    noBackup,
    appDatabases,
  ];

  static const Set<String> databaseOnly = <String>{
    mainDatabase,
    shardDatabases,
    perAppSettings,
    appDatabases,
  };
}

class BackupExcludedIds {
  static const String cache = 'cache';
  static const String codeCache = 'code_cache';
  static const String outputTemp = 'output_temp';
  static const String externalLogs = 'external_logs';
}

class BackupRootPaths {
  const BackupRootPaths({
    required this.filesDirPath,
    required this.dataRootPath,
    required this.outputDirPath,
    required this.appDatabasesDirPath,
    this.sharedPrefsDirPath,
    this.appFlutterDirPath,
    this.noBackupDirPath,
  });

  final String filesDirPath;
  final String dataRootPath;
  final String outputDirPath;
  final String appDatabasesDirPath;
  final String? sharedPrefsDirPath;
  final String? appFlutterDirPath;
  final String? noBackupDirPath;

  Map<String, String> toImportTargetMap() {
    final Map<String, String> map = <String, String>{
      'output': outputDirPath,
      'databases': appDatabasesDirPath,
    };
    if (sharedPrefsDirPath != null) {
      map['shared_prefs'] = sharedPrefsDirPath!;
    }
    if (appFlutterDirPath != null) {
      map['app_flutter'] = appFlutterDirPath!;
    }
    if (noBackupDirPath != null) {
      map['no_backup'] = noBackupDirPath!;
    }
    return map;
  }
}

class BackupInventoryFile {
  const BackupInventoryFile({
    required this.sourcePath,
    required this.archivePath,
    required this.bytes,
    required this.categoryId,
  });

  final String sourcePath;
  final String archivePath;
  final int bytes;
  final String categoryId;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourcePath': sourcePath,
    'archivePath': archivePath,
    'bytes': bytes,
    'categoryId': categoryId,
  };
}

class BackupInventoryCategory {
  const BackupInventoryCategory({
    required this.id,
    required this.files,
    required this.totalBytes,
    required this.fileCount,
  });

  final String id;
  final List<BackupInventoryFile> files;
  final int totalBytes;
  final int fileCount;

  Map<String, Object?> toManifestJson() => <String, Object?>{
    'id': id,
    'totalBytes': totalBytes,
    'fileCount': fileCount,
  };
}

class BackupExcludedItem {
  const BackupExcludedItem({
    required this.id,
    required this.reason,
    this.bytes = 0,
  });

  final String id;
  final String reason;
  final int bytes;

  Map<String, Object?> toManifestJson() => <String, Object?>{
    'id': id,
    'reason': reason,
    'bytes': bytes,
  };
}

class BackupInventory {
  const BackupInventory({
    required this.roots,
    required this.categories,
    required this.excludedItems,
    required this.totalBytes,
    required this.totalFiles,
    required this.warnings,
  });

  final BackupRootPaths roots;
  final List<BackupInventoryCategory> categories;
  final List<BackupExcludedItem> excludedItems;
  final int totalBytes;
  final int totalFiles;
  final List<String> warnings;

  bool get isEmpty => totalFiles <= 0 || totalBytes <= 0;

  bool get requiresRestartAfterImport => categories.any(
    (BackupInventoryCategory category) =>
        category.id == BackupCategoryIds.sharedPrefs ||
        category.id == BackupCategoryIds.appFlutter ||
        category.id == BackupCategoryIds.noBackup ||
        category.id == BackupCategoryIds.appDatabases,
  );

  BackupInventoryCategory? categoryById(String id) {
    for (final BackupInventoryCategory category in categories) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }

  Map<String, Object?> toManifestJson({
    required DateTime createdAt,
    required String archiveFileName,
  }) => <String, Object?>{
    'format': 'screen_memo_backup',
    'version': backupManifestVersion,
    'createdAt': createdAt.toIso8601String(),
    'archiveFileName': archiveFileName,
    'totalBytes': totalBytes,
    'totalFiles': totalFiles,
    'requiresRestartAfterImport': requiresRestartAfterImport,
    'categories': categories.map((e) => e.toManifestJson()).toList(),
    'excluded': excludedItems.map((e) => e.toManifestJson()).toList(),
    'warnings': warnings,
  };
}

class BackupArchiveInspection {
  const BackupArchiveInspection({
    required this.hasManifest,
    required this.rootEntries,
    required this.manifestRequiresRestart,
  });

  final bool hasManifest;
  final Set<String> rootEntries;
  final bool manifestRequiresRestart;
}

enum BackupExportScope { full, databasesOnly }

enum ExportPhase {
  idle,
  scanning,
  packing,
  verifying,
  completed,
  failed,
  cancelled,
}

class ExportProgressSnapshot {
  const ExportProgressSnapshot({
    required this.phase,
    required this.overallProgress,
    required this.completedBytes,
    required this.totalBytes,
    required this.categoryCompletedBytes,
    this.inventory,
    this.currentEntry,
    this.currentCategoryId,
    this.outputPath,
    this.errorMessage,
  });

  final ExportPhase phase;
  final double overallProgress;
  final int completedBytes;
  final int totalBytes;
  final Map<String, int> categoryCompletedBytes;
  final BackupInventory? inventory;
  final String? currentEntry;
  final String? currentCategoryId;
  final String? outputPath;
  final String? errorMessage;

  bool get isTerminal =>
      phase == ExportPhase.completed ||
      phase == ExportPhase.failed ||
      phase == ExportPhase.cancelled;
}

class BackupExportCancelledException implements Exception {
  const BackupExportCancelledException();

  @override
  String toString() => 'backup_export_cancelled';
}

typedef BackupScanProgressCallback =
    void Function(String scopeId, String? currentPath);

class BackupInventoryService {
  BackupInventoryService._();

  static const Set<String> _ignoredOutputDirNames = <String>{
    'cache',
    'tmp',
    'temp',
    '.thumbnails',
  };

  static const Set<String> _ignoredTopLevelDirNames = <String>{
    'cache',
    'code_cache',
  };

  static Future<BackupRootPaths?> resolveDefaultRoots() async {
    final Directory? filesDir = await PathService.getInternalAppDir(null);
    if (filesDir == null) {
      return null;
    }

    final Directory dataRoot = filesDir.parent;
    final String dbPath = await getDatabasesPath();
    final String appDatabasesDirPath = p.dirname(dbPath);

    final String sharedPrefsDirPath = p.join(dataRoot.path, 'shared_prefs');
    final String appFlutterDirPath = p.join(dataRoot.path, 'app_flutter');
    final String noBackupDirPath = p.join(dataRoot.path, 'no_backup');

    return BackupRootPaths(
      filesDirPath: filesDir.path,
      dataRootPath: dataRoot.path,
      outputDirPath: p.join(filesDir.path, 'output'),
      appDatabasesDirPath: appDatabasesDirPath,
      sharedPrefsDirPath: sharedPrefsDirPath,
      appFlutterDirPath: appFlutterDirPath,
      noBackupDirPath: noBackupDirPath,
    );
  }

  static Future<BackupInventory> scan({
    BackupRootPaths? roots,
    BackupScanProgressCallback? onProgress,
  }) async {
    final BackupRootPaths? resolvedRoots = roots ?? await resolveDefaultRoots();
    if (resolvedRoots == null) {
      throw StateError('backup_roots_unavailable');
    }

    final Map<String, List<BackupInventoryFile>> filesByCategory =
        <String, List<BackupInventoryFile>>{
          for (final String id in BackupCategoryIds.ordered)
            id: <BackupInventoryFile>[],
        };
    final Map<String, int> excludedBytes = <String, int>{
      BackupExcludedIds.cache: 0,
      BackupExcludedIds.codeCache: 0,
      BackupExcludedIds.outputTemp: 0,
      BackupExcludedIds.externalLogs: 0,
    };
    final Set<String> seenSourcePaths = <String>{};
    final List<String> warnings = <String>[];

    await _scanArchiveRoot(
      absoluteRootPath: resolvedRoots.outputDirPath,
      archiveRoot: 'output',
      onProgress: onProgress,
      scopeId: 'output',
      filesByCategory: filesByCategory,
      seenSourcePaths: seenSourcePaths,
      warnings: warnings,
      excludedBytes: excludedBytes,
      ignoreTopLevelDirectories: _ignoredOutputDirNames,
      categoryForArchivePath: _categorizeArchivePath,
    );

    await _scanArchiveRoot(
      absoluteRootPath: resolvedRoots.sharedPrefsDirPath,
      archiveRoot: 'shared_prefs',
      onProgress: onProgress,
      scopeId: BackupCategoryIds.sharedPrefs,
      filesByCategory: filesByCategory,
      seenSourcePaths: seenSourcePaths,
      warnings: warnings,
      excludedBytes: excludedBytes,
      categoryForArchivePath: _categorizeArchivePath,
    );

    await _scanArchiveRoot(
      absoluteRootPath: resolvedRoots.appFlutterDirPath,
      archiveRoot: 'app_flutter',
      onProgress: onProgress,
      scopeId: BackupCategoryIds.appFlutter,
      filesByCategory: filesByCategory,
      seenSourcePaths: seenSourcePaths,
      warnings: warnings,
      excludedBytes: excludedBytes,
      categoryForArchivePath: _categorizeArchivePath,
    );

    await _scanArchiveRoot(
      absoluteRootPath: resolvedRoots.noBackupDirPath,
      archiveRoot: 'no_backup',
      onProgress: onProgress,
      scopeId: BackupCategoryIds.noBackup,
      filesByCategory: filesByCategory,
      seenSourcePaths: seenSourcePaths,
      warnings: warnings,
      excludedBytes: excludedBytes,
      categoryForArchivePath: _categorizeArchivePath,
    );

    await _scanArchiveRoot(
      absoluteRootPath: resolvedRoots.appDatabasesDirPath,
      archiveRoot: 'databases',
      onProgress: onProgress,
      scopeId: BackupCategoryIds.appDatabases,
      filesByCategory: filesByCategory,
      seenSourcePaths: seenSourcePaths,
      warnings: warnings,
      excludedBytes: excludedBytes,
      categoryForArchivePath: _categorizeArchivePath,
    );

    excludedBytes[BackupExcludedIds.cache] = await _measureDirectorySafe(
      p.join(resolvedRoots.dataRootPath, 'cache'),
    );
    excludedBytes[BackupExcludedIds.codeCache] = await _measureDirectorySafe(
      p.join(resolvedRoots.dataRootPath, 'code_cache'),
    );

    final List<BackupInventoryCategory> categories = <BackupInventoryCategory>[
      for (final String id in BackupCategoryIds.ordered)
        BackupInventoryCategory(
          id: id,
          files: List<BackupInventoryFile>.unmodifiable(
            (filesByCategory[id] ?? <BackupInventoryFile>[])
              ..sort((a, b) => a.archivePath.compareTo(b.archivePath)),
          ),
          totalBytes: (filesByCategory[id] ?? const <BackupInventoryFile>[])
              .fold<int>(0, (int sum, BackupInventoryFile e) => sum + e.bytes),
          fileCount:
              (filesByCategory[id] ?? const <BackupInventoryFile>[]).length,
        ),
    ].where((BackupInventoryCategory e) => e.fileCount > 0).toList();

    final int totalBytes = categories.fold<int>(
      0,
      (int sum, BackupInventoryCategory e) => sum + e.totalBytes,
    );
    final int totalFiles = categories.fold<int>(
      0,
      (int sum, BackupInventoryCategory e) => sum + e.fileCount,
    );

    final List<BackupExcludedItem> excludedItems = <BackupExcludedItem>[
      BackupExcludedItem(
        id: BackupExcludedIds.cache,
        reason: 'Cache directory is temporary and can be rebuilt.',
        bytes: excludedBytes[BackupExcludedIds.cache] ?? 0,
      ),
      BackupExcludedItem(
        id: BackupExcludedIds.codeCache,
        reason: 'Code cache is regenerated automatically after launch.',
        bytes: excludedBytes[BackupExcludedIds.codeCache] ?? 0,
      ),
      BackupExcludedItem(
        id: BackupExcludedIds.outputTemp,
        reason: 'Temporary output cache and thumbnails are excluded.',
        bytes: excludedBytes[BackupExcludedIds.outputTemp] ?? 0,
      ),
      const BackupExcludedItem(
        id: BackupExcludedIds.externalLogs,
        reason: 'External logs are intentionally excluded from backups.',
      ),
    ];

    return BackupInventory(
      roots: resolvedRoots,
      categories: categories,
      excludedItems: excludedItems,
      totalBytes: totalBytes,
      totalFiles: totalFiles,
      warnings: warnings,
    );
  }

  static String? rootEntryForArchivePath(String archivePath) {
    final String normalized = archivePath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      return null;
    }
    final List<String> parts = normalized.split('/');
    final String head = parts.first;
    if (head == backupManifestFileName) {
      return backupManifestFileName;
    }
    if (head == 'output' ||
        head == 'shared_prefs' ||
        head == 'app_flutter' ||
        head == 'no_backup' ||
        head == 'databases') {
      return head;
    }
    return null;
  }

  static bool shouldSkipImportedRelativePath(
    String rootEntry,
    String relativePath,
  ) {
    final String lower = relativePath.replaceAll('\\', '/').toLowerCase();
    if (lower.isEmpty) {
      return false;
    }
    if (lower.endsWith('.db-journal')) {
      return true;
    }
    if (rootEntry != 'output') {
      return false;
    }
    for (final String part in lower.split('/')) {
      if (_ignoredOutputDirNames.contains(part)) {
        return true;
      }
      if (part.contains('thumbnail')) {
        return true;
      }
    }
    return false;
  }

  static BackupArchiveInspection inspectArchiveEntries(
    Iterable<String> entryNames,
  ) {
    final Set<String> roots = <String>{};
    bool hasManifest = false;
    bool requiresRestart = false;
    for (final String rawName in entryNames) {
      final String normalized = rawName.replaceAll('\\', '/').trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (normalized == backupManifestFileName) {
        hasManifest = true;
        continue;
      }
      final String? root = rootEntryForArchivePath(normalized);
      if (root == null) {
        roots.add('output');
        continue;
      }
      if (root == backupManifestFileName) {
        continue;
      }
      roots.add(root);
      if (root != 'output') {
        requiresRestart = true;
      }
    }
    return BackupArchiveInspection(
      hasManifest: hasManifest,
      rootEntries: roots,
      manifestRequiresRestart: requiresRestart,
    );
  }

  static Future<BackupArchiveInspection> inspectArchiveFile(
    String zipPath,
  ) async {
    final InputFileStream input = InputFileStream(zipPath);
    try {
      final _ZipCentralDirectoryMetadata directory =
          _readZipCentralDirectoryMetadata(input);
      final InputStreamBase dirStream = input.subset(
        directory.centralDirectoryOffset,
        directory.centralDirectorySize,
      );
      final List<String> entryNames = <String>[];
      while (!dirStream.isEOS) {
        final int fileSig = dirStream.readUint32();
        if (fileSig != ZipFileHeader.SIGNATURE) {
          break;
        }
        entryNames.add(ZipFileHeader(dirStream).filename);
      }
      return inspectArchiveEntries(entryNames);
    } finally {
      await input.close();
    }
  }

  static BackupInventory filterInventoryByScope(
    BackupInventory inventory,
    BackupExportScope scope,
  ) {
    if (scope == BackupExportScope.full) {
      return inventory;
    }

    final List<BackupInventoryCategory> categories = inventory.categories
        .where(
          (BackupInventoryCategory category) =>
              BackupCategoryIds.databaseOnly.contains(category.id),
        )
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
      categories: List<BackupInventoryCategory>.unmodifiable(categories),
      excludedItems: inventory.excludedItems,
      totalBytes: totalBytes,
      totalFiles: totalFiles,
      warnings: inventory.warnings,
    );
  }

  static String encodeManifestJson(
    BackupInventory inventory, {
    required DateTime createdAt,
    required String archiveFileName,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      inventory.toManifestJson(
        createdAt: createdAt,
        archiveFileName: archiveFileName,
      ),
    );
  }

  static Future<void> _scanArchiveRoot({
    required String? absoluteRootPath,
    required String archiveRoot,
    required String scopeId,
    required BackupScanProgressCallback? onProgress,
    required Map<String, List<BackupInventoryFile>> filesByCategory,
    required Set<String> seenSourcePaths,
    required List<String> warnings,
    required Map<String, int> excludedBytes,
    required String Function(String archivePath) categoryForArchivePath,
    Set<String> ignoreTopLevelDirectories = const <String>{},
  }) async {
    if (absoluteRootPath == null || absoluteRootPath.isEmpty) {
      return;
    }
    final Directory root = Directory(absoluteRootPath);
    if (!await root.exists()) {
      return;
    }

    onProgress?.call(scopeId, absoluteRootPath);

    final List<Directory> stack = <Directory>[root];
    while (stack.isNotEmpty) {
      final Directory current = stack.removeLast();
      List<FileSystemEntity> children;
      try {
        children = current.listSync(followLinks: false);
      } catch (e) {
        warnings.add('scan_failed:$absoluteRootPath::$e');
        continue;
      }
      children.sort((FileSystemEntity a, FileSystemEntity b) {
        return a.path.compareTo(b.path);
      });

      for (final FileSystemEntity entity in children) {
        final String relPath = p
            .relative(entity.path, from: root.path)
            .replaceAll('\\', '/');
        if (relPath.isEmpty || relPath == '.') {
          continue;
        }
        final String archivePath = '$archiveRoot/$relPath';
        final List<String> parts = relPath.split('/');
        final String headLower = parts.first.toLowerCase();

        if (entity is Directory) {
          if (ignoreTopLevelDirectories.contains(headLower)) {
            excludedBytes[BackupExcludedIds.outputTemp] =
                (excludedBytes[BackupExcludedIds.outputTemp] ?? 0) +
                await _measureDirectorySafe(entity.path);
            continue;
          }
          if (_ignoredTopLevelDirNames.contains(headLower) &&
              archiveRoot != 'output') {
            continue;
          }
          stack.add(entity);
          continue;
        }

        if (entity is! File) {
          continue;
        }

        final String archiveLower = archivePath.toLowerCase();
        if (archiveRoot == 'output' &&
            shouldSkipImportedRelativePath('output', relPath)) {
          excludedBytes[BackupExcludedIds.outputTemp] =
              (excludedBytes[BackupExcludedIds.outputTemp] ?? 0) +
              await entity.length();
          continue;
        }
        if (archiveLower.endsWith('.db-journal')) {
          continue;
        }

        final String normalizedSource = p.normalize(entity.absolute.path);
        if (!seenSourcePaths.add(normalizedSource)) {
          continue;
        }

        final int bytes = await entity.length();
        final String categoryId = categoryForArchivePath(archivePath);
        filesByCategory[categoryId]!.add(
          BackupInventoryFile(
            sourcePath: entity.path,
            archivePath: archivePath,
            bytes: bytes,
            categoryId: categoryId,
          ),
        );
      }
    }
  }

  static Future<int> _measureDirectorySafe(String? path) async {
    if (path == null || path.isEmpty) {
      return 0;
    }
    final Directory root = Directory(path);
    if (!await root.exists()) {
      return 0;
    }
    int total = 0;
    final List<Directory> stack = <Directory>[root];
    while (stack.isNotEmpty) {
      final Directory current = stack.removeLast();
      List<FileSystemEntity> children;
      try {
        children = current.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final FileSystemEntity entity in children) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        } else if (entity is Directory) {
          stack.add(entity);
        }
      }
    }
    return total;
  }

  static String _categorizeArchivePath(String archivePath) {
    final String normalized = archivePath.replaceAll('\\', '/');
    final String lower = normalized.toLowerCase();
    final String name = p.basename(lower);
    if (lower.startsWith('output/screen/')) {
      return BackupCategoryIds.screenshots;
    }
    if (lower == 'output/databases/screenshot_memo.db' ||
        lower == 'output/databases/screenshot_memo.db-wal' ||
        lower == 'output/databases/screenshot_memo.db-shm') {
      return BackupCategoryIds.mainDatabase;
    }
    if (lower.startsWith('output/databases/shards/') &&
        (name == 'settings.db' ||
            name == 'settings.db-wal' ||
            name == 'settings.db-shm')) {
      return BackupCategoryIds.perAppSettings;
    }
    if (lower.startsWith('output/databases/shards/') &&
        (name.startsWith('smm_') &&
            (name.endsWith('.db') ||
                name.endsWith('.db-wal') ||
                name.endsWith('.db-shm')))) {
      return BackupCategoryIds.shardDatabases;
    }
    if (lower.startsWith('output/')) {
      return BackupCategoryIds.otherOutput;
    }
    if (lower.startsWith('shared_prefs/')) {
      return BackupCategoryIds.sharedPrefs;
    }
    if (lower.startsWith('app_flutter/')) {
      return BackupCategoryIds.appFlutter;
    }
    if (lower.startsWith('no_backup/')) {
      return BackupCategoryIds.noBackup;
    }
    if (lower.startsWith('databases/')) {
      return BackupCategoryIds.appDatabases;
    }
    return BackupCategoryIds.otherOutput;
  }

  static _ZipCentralDirectoryMetadata _readZipCentralDirectoryMetadata(
    InputStreamBase input,
  ) {
    final int filePosition = _findZipEocdrSignature(input);
    final int originalPosition = input.position;
    input.position = filePosition;

    input.readUint32(); // EOCD signature
    int numberOfThisDisk = input.readUint16();
    int diskWithTheStartOfTheCentralDirectory = input.readUint16();
    int totalCentralDirectoryEntriesOnThisDisk = input.readUint16();
    int totalCentralDirectoryEntries = input.readUint16();
    int centralDirectorySize = input.readUint32();
    int centralDirectoryOffset = input.readUint32();

    final int commentLength = input.readUint16();
    if (commentLength > 0) {
      input.skip(commentLength);
    }

    if (centralDirectoryOffset == 0xffffffff ||
        centralDirectorySize == 0xffffffff ||
        totalCentralDirectoryEntriesOnThisDisk == 0xffff ||
        numberOfThisDisk == 0xffff) {
      final _ZipCentralDirectoryMetadata? zip64Metadata =
          _readZip64CentralDirectoryMetadata(input, filePosition);
      if (zip64Metadata != null) {
        numberOfThisDisk = zip64Metadata.numberOfThisDisk;
        diskWithTheStartOfTheCentralDirectory =
            zip64Metadata.diskWithTheStartOfTheCentralDirectory;
        totalCentralDirectoryEntriesOnThisDisk =
            zip64Metadata.totalCentralDirectoryEntriesOnThisDisk;
        totalCentralDirectoryEntries =
            zip64Metadata.totalCentralDirectoryEntries;
        centralDirectorySize = zip64Metadata.centralDirectorySize;
        centralDirectoryOffset = zip64Metadata.centralDirectoryOffset;
      }
    }

    input.position = originalPosition;
    return _ZipCentralDirectoryMetadata(
      numberOfThisDisk: numberOfThisDisk,
      diskWithTheStartOfTheCentralDirectory:
          diskWithTheStartOfTheCentralDirectory,
      totalCentralDirectoryEntriesOnThisDisk:
          totalCentralDirectoryEntriesOnThisDisk,
      totalCentralDirectoryEntries: totalCentralDirectoryEntries,
      centralDirectorySize: centralDirectorySize,
      centralDirectoryOffset: centralDirectoryOffset,
    );
  }

  static _ZipCentralDirectoryMetadata? _readZip64CentralDirectoryMetadata(
    InputStreamBase input,
    int filePosition,
  ) {
    final int originalPosition = input.position;
    final int locatorPosition =
        filePosition - _ZipCentralDirectoryMetadata.zip64EocdLocatorSize;
    if (locatorPosition < 0) {
      input.position = originalPosition;
      return null;
    }

    final InputStreamBase zip64Locator = input.subset(
      locatorPosition,
      _ZipCentralDirectoryMetadata.zip64EocdLocatorSize,
    );
    final int locatorSignature = zip64Locator.readUint32();
    if (locatorSignature != _ZipCentralDirectoryMetadata.zip64EocdLocatorSig) {
      input.position = originalPosition;
      return null;
    }

    zip64Locator.readUint32(); // disk number with zip64 EOCD
    final int zip64DirectoryOffset = zip64Locator.readUint64();
    zip64Locator.readUint32(); // total number of disks

    input.position = zip64DirectoryOffset;
    final int zip64Signature = input.readUint32();
    if (zip64Signature != _ZipCentralDirectoryMetadata.zip64EocdSig) {
      input.position = originalPosition;
      return null;
    }

    input.readUint64(); // zip64 EOCD record size
    input.readUint16(); // version made by
    input.readUint16(); // version needed to extract
    final int numberOfThisDisk = input.readUint32();
    final int diskWithTheStartOfTheCentralDirectory = input.readUint32();
    final int totalCentralDirectoryEntriesOnThisDisk = input.readUint64();
    final int totalCentralDirectoryEntries = input.readUint64();
    final int centralDirectorySize = input.readUint64();
    final int centralDirectoryOffset = input.readUint64();

    input.position = originalPosition;
    return _ZipCentralDirectoryMetadata(
      numberOfThisDisk: numberOfThisDisk,
      diskWithTheStartOfTheCentralDirectory:
          diskWithTheStartOfTheCentralDirectory,
      totalCentralDirectoryEntriesOnThisDisk:
          totalCentralDirectoryEntriesOnThisDisk,
      totalCentralDirectoryEntries: totalCentralDirectoryEntries,
      centralDirectorySize: centralDirectorySize,
      centralDirectoryOffset: centralDirectoryOffset,
    );
  }

  static int _findZipEocdrSignature(InputStreamBase input) {
    final int originalPosition = input.position;
    final int length = input.length;

    for (int position = length - 5; position >= 0; position--) {
      input.position = position;
      final int signature = input.readUint32();
      if (signature == _ZipCentralDirectoryMetadata.eocdLocatorSig) {
        input.position = originalPosition;
        return position;
      }
    }

    input.position = originalPosition;
    throw ArchiveException('Could not find End of Central Directory Record');
  }
}

class _ZipCentralDirectoryMetadata {
  const _ZipCentralDirectoryMetadata({
    required this.numberOfThisDisk,
    required this.diskWithTheStartOfTheCentralDirectory,
    required this.totalCentralDirectoryEntriesOnThisDisk,
    required this.totalCentralDirectoryEntries,
    required this.centralDirectorySize,
    required this.centralDirectoryOffset,
  });

  static const int eocdLocatorSig = 0x06054b50;
  static const int zip64EocdLocatorSig = 0x07064b50;
  static const int zip64EocdSig = 0x06064b50;
  static const int zip64EocdLocatorSize = 20;

  final int numberOfThisDisk;
  final int diskWithTheStartOfTheCentralDirectory;
  final int totalCentralDirectoryEntriesOnThisDisk;
  final int totalCentralDirectoryEntries;
  final int centralDirectorySize;
  final int centralDirectoryOffset;
}

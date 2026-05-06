import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_memo/data/platform/path_service.dart';

/// 某一天落盘日志的聚合信息。
class LogDaySummary {
  const LogDaySummary({
    required this.date,
    required this.directory,
    required this.fileCount,
    required this.totalBytes,
    required this.latestModified,
  });

  final DateTime date;
  final Directory directory;
  final int fileCount;
  final int totalBytes;
  final DateTime latestModified;
}

/// 单个落盘日志文件的信息。
class LogFileSummary {
  const LogFileSummary({
    required this.date,
    required this.file,
    required this.relativePath,
    required this.archivePath,
    required this.bytes,
    required this.modified,
  });

  /// 文件所在日期目录，对应 output/logs/yyyy/MM/dd。
  final DateTime date;

  /// 实际落盘文件。
  final File file;

  /// 相对 output/logs 的路径，例如 2026/05/06/06_info.log。
  final String relativePath;

  /// ZIP 内路径，例如 output/logs/2026/05/06/06_info.log。
  final String archivePath;

  final int bytes;
  final DateTime modified;

  String get fileName => p.basename(file.path);
}

/// 日志目录浏览项类型。
enum LogBrowserEntryType { directory, file }

/// 当前目录下的直接子项。
class LogBrowserEntry {
  const LogBrowserEntry({
    required this.type,
    required this.name,
    required this.path,
    required this.relativePath,
    required this.archivePath,
    required this.fileCount,
    required this.totalBytes,
    required this.latestModified,
  });

  final LogBrowserEntryType type;
  final String name;
  final String path;

  /// 相对 output/logs 的路径，根目录下的 2026/05 会记录为 2026/05。
  final String relativePath;

  /// ZIP 内路径，文件和文件夹均保留 output/logs 前缀。
  final String archivePath;

  /// 文件夹下的递归文件数量；文件自身为 1。
  final int fileCount;
  final int totalBytes;
  final DateTime? latestModified;

  bool get isDirectory => type == LogBrowserEntryType.directory;

  bool get isFile => type == LogBrowserEntryType.file;
}

/// 某个日志目录的直接子项与递归汇总。
class LogDirectoryListing {
  const LogDirectoryListing({
    required this.relativePath,
    required this.archivePath,
    required this.entries,
    required this.fileCount,
    required this.totalBytes,
    required this.latestModified,
    required this.exists,
  });

  final String relativePath;
  final String archivePath;
  final List<LogBrowserEntry> entries;
  final int fileCount;
  final int totalBytes;
  final DateTime? latestModified;
  final bool exists;

  bool get isRoot => relativePath.isEmpty;
}

/// 删除日志文件/目录后的结果。
class LogDeleteResult {
  const LogDeleteResult({required this.fileCount, required this.targetDeleted});

  final int fileCount;
  final bool targetDeleted;
}

class _LogFolderStats {
  const _LogFolderStats({
    required this.fileCount,
    required this.totalBytes,
    required this.latestModified,
  });

  final int fileCount;
  final int totalBytes;
  final DateTime? latestModified;
}

/// 日志导出选择范围。
class LogExportSelection {
  const LogExportSelection._({this.date});

  factory LogExportSelection.all() => const LogExportSelection._();

  factory LogExportSelection.day(DateTime date) {
    return LogExportSelection._(
      date: DateTime(date.year, date.month, date.day),
    );
  }

  final DateTime? date;

  bool get isAll => date == null;
}

/// 以落盘日志为准的扫描与 ZIP 打包服务。
class LogExportService {
  const LogExportService._();

  static const int largeExportThresholdBytes = 50 * 1024 * 1024;

  /// 浏览 output/logs 下指定相对目录，只返回该目录的直接子项。
  ///
  /// 目录项会带递归文件数/大小汇总，但 UI 只需要渲染当前层级，避免日志很多时
  /// 一次性创建大量列表项。
  static Future<LogDirectoryListing> listDirectory({
    String relativePath = '',
    Directory? logsRoot,
  }) async {
    final Directory? root = await _resolveLogsRoot(logsRoot);
    final String normalized = _normalizeRelativePath(relativePath);
    final String archivePath = normalized.isEmpty
        ? 'output/logs'
        : 'output/logs/$normalized';
    if (root == null || !await root.exists()) {
      return LogDirectoryListing(
        relativePath: normalized,
        archivePath: archivePath,
        entries: const <LogBrowserEntry>[],
        fileCount: 0,
        totalBytes: 0,
        latestModified: null,
        exists: false,
      );
    }

    final Directory directory = _resolveChildDirectory(root, normalized);
    if (!await directory.exists()) {
      return LogDirectoryListing(
        relativePath: normalized,
        archivePath: archivePath,
        entries: const <LogBrowserEntry>[],
        fileCount: 0,
        totalBytes: 0,
        latestModified: null,
        exists: false,
      );
    }

    final _LogFolderStats folderStats = await _summarizeDirectory(directory);
    final List<LogBrowserEntry> entries = <LogBrowserEntry>[];
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      final String name = p.basename(entity.path);
      final String childRelative = _joinRelativePath(normalized, name);
      try {
        if (entity is Directory) {
          final _LogFolderStats stats = await _summarizeDirectory(entity);
          final FileStat dirStat = await entity.stat();
          entries.add(
            LogBrowserEntry(
              type: LogBrowserEntryType.directory,
              name: name,
              path: entity.path,
              relativePath: childRelative,
              archivePath: 'output/logs/$childRelative',
              fileCount: stats.fileCount,
              totalBytes: stats.totalBytes,
              latestModified: stats.latestModified ?? dirStat.modified,
            ),
          );
        } else if (entity is File) {
          final FileStat stat = await entity.stat();
          entries.add(
            LogBrowserEntry(
              type: LogBrowserEntryType.file,
              name: name,
              path: entity.path,
              relativePath: childRelative,
              archivePath: 'output/logs/$childRelative',
              fileCount: 1,
              totalBytes: stat.size,
              latestModified: stat.modified,
            ),
          );
        }
      } catch (_) {
        // 日志文件/目录可能正在轮转或删除，当前刷新跳过即可。
      }
    }

    entries.sort(_compareBrowserEntries);
    return LogDirectoryListing(
      relativePath: normalized,
      archivePath: archivePath,
      entries: entries,
      fileCount: folderStats.fileCount,
      totalBytes: folderStats.totalBytes,
      latestModified: folderStats.latestModified,
      exists: true,
    );
  }

  /// 扫描 output/logs/yyyy/MM/dd，并按日期、修改时间倒序返回单个日志文件。
  static Future<List<LogFileSummary>> listLogFiles({
    Directory? logsRoot,
  }) async {
    final Directory? root = await _resolveLogsRoot(logsRoot);
    if (root == null || !await root.exists()) {
      return const <LogFileSummary>[];
    }

    final List<LogFileSummary> files = <LogFileSummary>[];
    await for (final FileSystemEntity yearEntity in root.list(
      followLinks: false,
    )) {
      if (yearEntity is! Directory) continue;
      final int? year = _parseFixedInt(p.basename(yearEntity.path), 4);
      if (year == null) continue;

      await for (final FileSystemEntity monthEntity in yearEntity.list(
        followLinks: false,
      )) {
        if (monthEntity is! Directory) continue;
        final int? month = _parseFixedInt(p.basename(monthEntity.path), 2);
        if (month == null) continue;

        await for (final FileSystemEntity dayEntity in monthEntity.list(
          followLinks: false,
        )) {
          if (dayEntity is! Directory) continue;
          final int? day = _parseFixedInt(p.basename(dayEntity.path), 2);
          if (day == null) continue;
          final DateTime? date = _safeDate(year, month, day);
          if (date == null) continue;

          await _collectLogFilesForDay(
            date: date,
            directory: dayEntity,
            output: files,
          );
        }
      }
    }

    files.sort((LogFileSummary a, LogFileSummary b) {
      final int dateCompare = b.date.compareTo(a.date);
      if (dateCompare != 0) return dateCompare;
      final int modifiedCompare = b.modified.compareTo(a.modified);
      if (modifiedCompare != 0) return modifiedCompare;
      return a.relativePath.compareTo(b.relativePath);
    });
    return files;
  }

  /// 扫描 output/logs/yyyy/MM/dd，并按日期倒序返回有文件的日志天。
  static Future<List<LogDaySummary>> listLogDays({Directory? logsRoot}) async {
    final Directory? root = await _resolveLogsRoot(logsRoot);
    if (root == null || !await root.exists()) {
      return const <LogDaySummary>[];
    }

    final List<LogDaySummary> summaries = <LogDaySummary>[];
    await for (final FileSystemEntity yearEntity in root.list(
      followLinks: false,
    )) {
      if (yearEntity is! Directory) continue;
      final int? year = _parseFixedInt(p.basename(yearEntity.path), 4);
      if (year == null) continue;

      await for (final FileSystemEntity monthEntity in yearEntity.list(
        followLinks: false,
      )) {
        if (monthEntity is! Directory) continue;
        final int? month = _parseFixedInt(p.basename(monthEntity.path), 2);
        if (month == null) continue;

        await for (final FileSystemEntity dayEntity in monthEntity.list(
          followLinks: false,
        )) {
          if (dayEntity is! Directory) continue;
          final int? day = _parseFixedInt(p.basename(dayEntity.path), 2);
          if (day == null) continue;
          final DateTime? date = _safeDate(year, month, day);
          if (date == null) continue;

          final LogDaySummary? summary = await _summarizeDay(date, dayEntity);
          if (summary != null) {
            summaries.add(summary);
          }
        }
      }
    }

    summaries.sort((LogDaySummary a, LogDaySummary b) {
      return b.date.compareTo(a.date);
    });
    return summaries;
  }

  /// 将单个日志文件打包为 ZIP，ZIP 内保留 output/logs/yyyy/MM/dd/... 路径。
  static Future<File> createZipForFile(
    LogFileSummary logFile, {
    Directory? outputDirectory,
  }) async {
    final Directory outDir = await _resolveOutputDirectory(outputDirectory);
    final String sourceName = _shortSafeFileName(
      p.basenameWithoutExtension(logFile.fileName),
    );
    final File zipFile = File(
      p.join(
        outDir.path,
        'screenmemo_log_${_formatDateDash(logFile.date)}_'
        '${sourceName}_${_formatTimestamp(DateTime.now())}.zip',
      ),
    );
    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    final ZipFileEncoder encoder = ZipFileEncoder();
    bool closed = false;
    int addedFiles = 0;

    try {
      encoder.create(zipFile.path, level: 0);
      try {
        if (await logFile.file.exists()) {
          await encoder.addFile(
            logFile.file,
            logFile.archivePath,
            ZipFileEncoder.STORE,
          );
          addedFiles = 1;
        }
      } catch (_) {
        // 日志文件可能正在轮转/删除；按无可导出文件处理。
      }
      encoder.close();
      closed = true;

      if (addedFiles <= 0) {
        try {
          if (await zipFile.exists()) {
            await zipFile.delete();
          }
        } catch (_) {}
        throw StateError('no_log_files_to_export');
      }
      return zipFile;
    } finally {
      if (!closed) {
        try {
          encoder.close();
        } catch (_) {}
      }
    }
  }

  /// 将浏览器中的文件或文件夹打包为 ZIP。
  static Future<File> createZipForBrowserEntry(
    LogBrowserEntry entry, {
    Directory? outputDirectory,
  }) async {
    if (entry.isDirectory) {
      return _createZipFromDirectory(
        sourceRoot: Directory(entry.path),
        archivePrefix: entry.archivePath,
        outputFileName:
            'screenmemo_logs_${_shortSafeFileName(entry.relativePath.replaceAll('/', '_'))}_${_formatTimestamp(DateTime.now())}.zip',
        outputDirectory: outputDirectory,
      );
    }
    return _createZipFromSingleFile(
      sourceFile: File(entry.path),
      archivePath: entry.archivePath,
      outputFileName:
          'screenmemo_log_${_shortSafeFileName(p.basenameWithoutExtension(entry.name))}_${_formatTimestamp(DateTime.now())}.zip',
      outputDirectory: outputDirectory,
    );
  }

  /// 将指定某天的日志目录打包为 ZIP，ZIP 内保留 output/logs/yyyy/MM/dd。
  static Future<File> createZipForDay(
    LogDaySummary day, {
    Directory? outputDirectory,
  }) async {
    final String dateKey = _formatDateDash(day.date);
    return _createZipFromDirectory(
      sourceRoot: day.directory,
      archivePrefix: _archivePrefixForDate(day.date),
      outputFileName:
          'screenmemo_logs_${dateKey}_${_formatTimestamp(DateTime.now())}.zip',
      outputDirectory: outputDirectory,
    );
  }

  /// 将指定日期的日志目录打包为 ZIP，ZIP 内保留 output/logs/yyyy/MM/dd。
  static Future<File> createZipForDate(
    DateTime date, {
    Directory? logsRoot,
    Directory? outputDirectory,
  }) async {
    final Directory? root = await _resolveLogsRoot(logsRoot);
    if (root == null || !await root.exists()) {
      throw StateError('no_log_files_to_export');
    }

    final DateTime day = DateTime(date.year, date.month, date.day);
    final String dateKey = _formatDateDash(day);
    return _createZipFromDirectory(
      sourceRoot: _directoryForDate(root, day),
      archivePrefix: _archivePrefixForDate(day),
      outputFileName:
          'screenmemo_logs_${dateKey}_${_formatTimestamp(DateTime.now())}.zip',
      outputDirectory: outputDirectory,
    );
  }

  /// 将全部落盘日志打包为 ZIP，ZIP 内保留 output/logs。
  static Future<File> createZipForAll({
    Directory? logsRoot,
    Directory? outputDirectory,
  }) async {
    final Directory? root = await _resolveLogsRoot(logsRoot);
    if (root == null || !await root.exists()) {
      throw StateError('no_log_files_to_export');
    }

    return _createZipFromDirectory(
      sourceRoot: root,
      archivePrefix: 'output/logs',
      outputFileName:
          'screenmemo_logs_all_${_formatTimestamp(DateTime.now())}.zip',
      outputDirectory: outputDirectory,
    );
  }

  /// 删除单个日志文件。返回值表示文件是否实际存在并被删除。
  static Future<bool> deleteLogFile(LogFileSummary logFile) async {
    if (!await logFile.file.exists()) {
      return false;
    }
    await logFile.file.delete();
    return true;
  }

  /// 删除浏览器中的文件或文件夹。
  static Future<LogDeleteResult> deleteBrowserEntry(
    LogBrowserEntry entry,
  ) async {
    if (entry.isFile) {
      final File file = File(entry.path);
      if (!await file.exists()) {
        return const LogDeleteResult(fileCount: 0, targetDeleted: false);
      }
      await file.delete();
      return const LogDeleteResult(fileCount: 1, targetDeleted: true);
    }

    final Directory directory = Directory(entry.path);
    if (!await directory.exists()) {
      return const LogDeleteResult(fileCount: 0, targetDeleted: false);
    }

    int deletedFiles = 0;
    await for (final FileSystemEntity entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        if (!await entity.exists()) continue;
        await entity.delete();
        deletedFiles += 1;
      } catch (_) {
        // 文件可能仍在写入或已被日志轮转删除；继续处理其他文件。
      }
    }

    bool targetDeleted = false;
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      targetDeleted = !await directory.exists();
    } catch (_) {
      targetDeleted = !await directory.exists();
    }
    return LogDeleteResult(
      fileCount: deletedFiles,
      targetDeleted: targetDeleted,
    );
  }

  /// 删除指定日期目录下的所有日志文件。返回实际删除的文件数量。
  static Future<int> deleteLogFilesForDate(
    DateTime date, {
    Directory? logsRoot,
  }) async {
    final Directory? root = await _resolveLogsRoot(logsRoot);
    if (root == null || !await root.exists()) {
      return 0;
    }

    final Directory dayDirectory = _directoryForDate(
      root,
      DateTime(date.year, date.month, date.day),
    );
    if (!await dayDirectory.exists()) {
      return 0;
    }

    int deletedFiles = 0;
    await for (final FileSystemEntity entity in dayDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        if (!await entity.exists()) continue;
        await entity.delete();
        deletedFiles += 1;
      } catch (_) {
        // 文件可能仍在写入或已被日志轮转删除；继续处理其他文件。
      }
    }

    try {
      if (await dayDirectory.exists()) {
        await dayDirectory.delete(recursive: true);
      }
    } catch (_) {
      // 如果日志线程同时重建了目录或文件，保留剩余内容，下次刷新再显示。
    }
    return deletedFiles;
  }

  static Future<Directory?> _resolveLogsRoot(Directory? override) async {
    if (override != null) return override;
    return PathService.getLegacyExternalFilesDir('output/logs');
  }

  static Future<Directory> _resolveOutputDirectory(
    Directory? outputDirectory,
  ) async {
    if (outputDirectory != null) {
      if (!await outputDirectory.exists()) {
        await outputDirectory.create(recursive: true);
      }
      return outputDirectory;
    }
    final Directory temp = await getTemporaryDirectory();
    final Directory dir = Directory(
      p.join(temp.path, 'screen_memo_log_exports'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<_LogFolderStats> _summarizeDirectory(
    Directory directory,
  ) async {
    if (!await directory.exists()) {
      return const _LogFolderStats(
        fileCount: 0,
        totalBytes: 0,
        latestModified: null,
      );
    }

    int fileCount = 0;
    int totalBytes = 0;
    DateTime? latestModified;

    await for (final FileSystemEntity entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        final FileStat stat = await entity.stat();
        fileCount += 1;
        totalBytes += stat.size;
        final DateTime modified = stat.modified;
        if (latestModified == null || modified.isAfter(latestModified)) {
          latestModified = modified;
        }
      } catch (_) {
        // 文件可能正在被日志线程轮转/删除，扫描时忽略即可。
      }
    }

    return _LogFolderStats(
      fileCount: fileCount,
      totalBytes: totalBytes,
      latestModified: latestModified,
    );
  }

  static Future<LogDaySummary?> _summarizeDay(
    DateTime date,
    Directory directory,
  ) async {
    if (!await directory.exists()) return null;

    final _LogFolderStats stats = await _summarizeDirectory(directory);

    if (stats.fileCount <= 0 || stats.latestModified == null) return null;
    return LogDaySummary(
      date: date,
      directory: directory,
      fileCount: stats.fileCount,
      totalBytes: stats.totalBytes,
      latestModified: stats.latestModified!,
    );
  }

  static Future<void> _collectLogFilesForDay({
    required DateTime date,
    required Directory directory,
    required List<LogFileSummary> output,
  }) async {
    if (!await directory.exists()) return;

    final String dayPrefix =
        '${_four(date.year)}/${_two(date.month)}/${_two(date.day)}';
    await for (final FileSystemEntity entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        final FileStat stat = await entity.stat();
        final String relativeInDay = p
            .relative(entity.path, from: directory.path)
            .replaceAll('\\', '/');
        if (relativeInDay.isEmpty || relativeInDay.startsWith('..')) continue;
        final String relativePath = '$dayPrefix/$relativeInDay';
        output.add(
          LogFileSummary(
            date: date,
            file: entity,
            relativePath: relativePath,
            archivePath: 'output/logs/$relativePath',
            bytes: stat.size,
            modified: stat.modified,
          ),
        );
      } catch (_) {
        // 文件可能正在被日志线程轮转/删除，扫描时忽略即可。
      }
    }
  }

  static Future<File> _createZipFromDirectory({
    required Directory sourceRoot,
    required String archivePrefix,
    required String outputFileName,
    Directory? outputDirectory,
  }) async {
    if (!await sourceRoot.exists()) {
      throw StateError('no_log_files_to_export');
    }

    final Directory outDir = await _resolveOutputDirectory(outputDirectory);
    final File zipFile = File(p.join(outDir.path, outputFileName));
    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    final ZipFileEncoder encoder = ZipFileEncoder();
    bool closed = false;
    int addedFiles = 0;

    try {
      encoder.create(zipFile.path, level: 0);
      await for (final FileSystemEntity entity in sourceRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          if (!await entity.exists()) continue;
          final String relative = p
              .relative(entity.path, from: sourceRoot.path)
              .replaceAll('\\', '/');
          if (relative.isEmpty || relative.startsWith('..')) continue;
          final String archivePath = '$archivePrefix/$relative';
          await encoder.addFile(entity, archivePath, ZipFileEncoder.STORE);
          addedFiles += 1;
        } catch (_) {
          // 导出时日志文件可能被删除或仍在写入；单个文件失败不阻断整体分享。
        }
      }
      encoder.close();
      closed = true;

      if (addedFiles <= 0) {
        try {
          if (await zipFile.exists()) {
            await zipFile.delete();
          }
        } catch (_) {}
        throw StateError('no_log_files_to_export');
      }
      return zipFile;
    } finally {
      if (!closed) {
        try {
          encoder.close();
        } catch (_) {}
      }
    }
  }

  static Future<File> _createZipFromSingleFile({
    required File sourceFile,
    required String archivePath,
    required String outputFileName,
    Directory? outputDirectory,
  }) async {
    final Directory outDir = await _resolveOutputDirectory(outputDirectory);
    final File zipFile = File(p.join(outDir.path, outputFileName));
    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    final ZipFileEncoder encoder = ZipFileEncoder();
    bool closed = false;
    int addedFiles = 0;

    try {
      encoder.create(zipFile.path, level: 0);
      try {
        if (await sourceFile.exists()) {
          await encoder.addFile(sourceFile, archivePath, ZipFileEncoder.STORE);
          addedFiles = 1;
        }
      } catch (_) {
        // 日志文件可能正在轮转/删除；按无可导出文件处理。
      }
      encoder.close();
      closed = true;

      if (addedFiles <= 0) {
        try {
          if (await zipFile.exists()) {
            await zipFile.delete();
          }
        } catch (_) {}
        throw StateError('no_log_files_to_export');
      }
      return zipFile;
    } finally {
      if (!closed) {
        try {
          encoder.close();
        } catch (_) {}
      }
    }
  }

  static String _normalizeRelativePath(String relativePath) {
    final List<String> parts = p
        .split(relativePath.replaceAll('\\', '/'))
        .where((String part) => part.isNotEmpty && part != '.')
        .toList(growable: false);
    if (parts.any((String part) => part == '..' || p.isAbsolute(part))) {
      throw ArgumentError.value(relativePath, 'relativePath');
    }
    return parts.join('/');
  }

  static Directory _resolveChildDirectory(Directory root, String relativePath) {
    if (relativePath.isEmpty) return root;
    return Directory(
      p.joinAll(<String>[root.path, ...relativePath.split('/')]),
    );
  }

  static String _joinRelativePath(String parent, String name) {
    final String safeName = _normalizeRelativePath(name);
    if (safeName.isEmpty) return parent;
    return parent.isEmpty ? safeName : '$parent/$safeName';
  }

  static int _compareBrowserEntries(LogBrowserEntry a, LogBrowserEntry b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }

    if (a.isDirectory && b.isDirectory) {
      final bool aNumeric = _isNumericName(a.name);
      final bool bNumeric = _isNumericName(b.name);
      if (aNumeric && bNumeric) {
        return b.name.compareTo(a.name);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    final DateTime? aModified = a.latestModified;
    final DateTime? bModified = b.latestModified;
    if (aModified != null && bModified != null) {
      final int modifiedCompare = bModified.compareTo(aModified);
      if (modifiedCompare != 0) return modifiedCompare;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  static bool _isNumericName(String name) {
    return RegExp(r'^\d+$').hasMatch(name);
  }

  static int? _parseFixedInt(String text, int digits) {
    if (text.length != digits || !RegExp(r'^\d+$').hasMatch(text)) {
      return null;
    }
    return int.tryParse(text);
  }

  static DateTime? _safeDate(int year, int month, int day) {
    try {
      final DateTime date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return date;
    } catch (_) {
      return null;
    }
  }

  static String _formatDateDash(DateTime date) {
    return '${_four(date.year)}-${_two(date.month)}-${_two(date.day)}';
  }

  static String _formatTimestamp(DateTime date) {
    return '${_four(date.year)}${_two(date.month)}${_two(date.day)}_'
        '${_two(date.hour)}${_two(date.minute)}${_two(date.second)}';
  }

  static Directory _directoryForDate(Directory logsRoot, DateTime date) {
    return Directory(
      p.join(logsRoot.path, _four(date.year), _two(date.month), _two(date.day)),
    );
  }

  static String _archivePrefixForDate(DateTime date) {
    return 'output/logs/${_four(date.year)}/${_two(date.month)}/${_two(date.day)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _four(int value) => value.toString().padLeft(4, '0');

  static String _shortSafeFileName(String text) {
    final String sanitized = text
        .replaceAll(RegExp(r'[^\w.\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final String safe = sanitized.isEmpty ? 'file' : sanitized;
    return safe.length <= 48 ? safe : safe.substring(0, 48);
  }
}

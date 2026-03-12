import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/backup_inventory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scan classifies full backup roots and excluded bytes', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'screenmemo_backup_inventory_',
    );
    try {
      final Directory dataRoot = Directory('${tempDir.path}/data');
      final Directory filesDir = Directory('${dataRoot.path}/files');
      final Directory outputDir = Directory('${filesDir.path}/output');
      final Directory sharedPrefsDir = Directory(
        '${dataRoot.path}/shared_prefs',
      );
      final Directory appFlutterDir = Directory('${dataRoot.path}/app_flutter');
      final Directory noBackupDir = Directory('${dataRoot.path}/no_backup');
      final Directory appDatabasesDir = Directory('${dataRoot.path}/databases');
      final Directory cacheDir = Directory('${dataRoot.path}/cache');
      final Directory codeCacheDir = Directory('${dataRoot.path}/code_cache');

      await File('${outputDir.path}/screen/com.demo/a.png')
          .create(recursive: true)
          .then((File f) => f.writeAsBytes(List<int>.filled(10, 1)));
      await File(
        '${outputDir.path}/databases/screenshot_memo.db',
      ).create(recursive: true).then((File f) => f.writeAsString('master'));
      await File(
        '${outputDir.path}/databases/screenshot_memo.db-wal',
      ).create(recursive: true).then((File f) => f.writeAsString('wal'));
      await File(
        '${outputDir.path}/databases/shards/com_demo/2024/smm_com_demo_2024.db',
      ).create(recursive: true).then((File f) => f.writeAsString('shard'));
      await File(
        '${outputDir.path}/databases/shards/com_demo/settings.db',
      ).create(recursive: true).then((File f) => f.writeAsString('settings'));
      await File(
        '${outputDir.path}/replay/replay.jsonl',
      ).create(recursive: true).then((File f) => f.writeAsString('replay'));
      await File(
        '${sharedPrefsDir.path}/FlutterSharedPreferences.xml',
      ).create(recursive: true).then((File f) => f.writeAsString('prefs'));
      await File(
        '${appFlutterDir.path}/state.json',
      ).create(recursive: true).then((File f) => f.writeAsString('flutter'));
      await File(
        '${noBackupDir.path}/session.txt',
      ).create(recursive: true).then((File f) => f.writeAsString('no_backup'));
      await File(
        '${appDatabasesDir.path}/plugin.db',
      ).create(recursive: true).then((File f) => f.writeAsString('plugin'));
      await File('${cacheDir.path}/cache.bin')
          .create(recursive: true)
          .then((File f) => f.writeAsBytes(List<int>.filled(7, 2)));
      await File('${codeCacheDir.path}/code.bin')
          .create(recursive: true)
          .then((File f) => f.writeAsBytes(List<int>.filled(9, 3)));
      await File('${outputDir.path}/cache/tmp.bin')
          .create(recursive: true)
          .then((File f) => f.writeAsBytes(List<int>.filled(5, 4)));

      final BackupInventory inventory = await BackupInventoryService.scan(
        roots: BackupRootPaths(
          filesDirPath: filesDir.path,
          dataRootPath: dataRoot.path,
          outputDirPath: outputDir.path,
          appDatabasesDirPath: appDatabasesDir.path,
          sharedPrefsDirPath: sharedPrefsDir.path,
          appFlutterDirPath: appFlutterDir.path,
          noBackupDirPath: noBackupDir.path,
        ),
      );

      expect(inventory.totalFiles, 9);
      expect(
        inventory.categoryById(BackupCategoryIds.screenshots)?.fileCount,
        1,
      );
      expect(
        inventory.categoryById(BackupCategoryIds.mainDatabase)?.fileCount,
        2,
      );
      expect(
        inventory.categoryById(BackupCategoryIds.shardDatabases)?.fileCount,
        1,
      );
      expect(
        inventory.categoryById(BackupCategoryIds.perAppSettings)?.fileCount,
        1,
      );
      expect(
        inventory.categoryById(BackupCategoryIds.otherOutput)?.fileCount,
        1,
      );
      expect(
        inventory.categoryById(BackupCategoryIds.sharedPrefs)?.fileCount,
        1,
      );
      expect(
        inventory.categoryById(BackupCategoryIds.appFlutter)?.fileCount,
        1,
      );
      expect(inventory.categoryById(BackupCategoryIds.noBackup)?.fileCount, 1);
      expect(
        inventory.categoryById(BackupCategoryIds.appDatabases)?.fileCount,
        1,
      );
      expect(inventory.requiresRestartAfterImport, isTrue);

      final BackupExcludedItem cacheExcluded = inventory.excludedItems
          .firstWhere(
            (BackupExcludedItem item) => item.id == BackupExcludedIds.cache,
          );
      final BackupExcludedItem outputTempExcluded = inventory.excludedItems
          .firstWhere(
            (BackupExcludedItem item) =>
                item.id == BackupExcludedIds.outputTemp,
          );
      expect(cacheExcluded.bytes, greaterThan(0));
      expect(outputTempExcluded.bytes, greaterThan(0));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

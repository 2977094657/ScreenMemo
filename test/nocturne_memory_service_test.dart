import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/services/nocturne_memory_service.dart';
import 'package:screen_memo/services/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Directory> _prepareDesktopDbRoot() async {
  final Directory tmp = await Directory.systemTemp.createTemp(
    'screen_memo_nocturne_memory_',
  );
  final Directory root = Directory(p.join(tmp.path, 'root'));
  await root.create(recursive: true);
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  return tmp;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Nocturne URI graph: CRUD + alias cascade', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      final NocturneMemoryService mem = NocturneMemoryService.instance;

      final Map<String, dynamic> agent = await mem.createMemory(
        parentUri: 'core://',
        title: 'agent',
        content: 'Hello agent.',
        priority: 1,
        disclosure: 'When starting a new session',
      );
      expect(agent['uri'], 'core://agent');

      await mem.createMemory(
        parentUri: 'core://agent',
        title: 'my_user',
        content: 'User is named Salem.',
        priority: 1,
        disclosure: 'When user identity matters',
      );

      final Map<String, dynamic> read1 = await mem.readMemory('core://agent');
      expect((read1['content'] as String?) ?? '', contains('Hello'));
      expect(read1['children'], isA<List>());
      expect((read1['children'] as List).length, 1);

      final Map<String, dynamic> alias = await mem.addAlias(
        newUri: 'dynamic://agent_alias',
        targetUri: 'core://agent',
        priority: 0,
        disclosure: 'When browsing dynamic feed',
      );
      expect(alias['new_uri'], 'dynamic://agent_alias');

      final List<Map<String, dynamic>> dynIndex =
          await mem.getAllPaths(domain: 'dynamic');
      final Set<String> dynUris =
          dynIndex.map((e) => (e['uri'] ?? '').toString()).toSet();
      expect(dynUris, contains('dynamic://agent_alias'));
      expect(dynUris, contains('dynamic://agent_alias/my_user'));

      await mem.updateMemory(
        uri: 'core://agent',
        oldString: 'Hello',
        newString: 'Hi',
      );
      final Map<String, dynamic> read2 =
          await mem.readMemory('dynamic://agent_alias');
      expect((read2['content'] as String?) ?? '', contains('Hi agent.'));

      final Map<String, dynamic> del = await mem.deleteMemory(uri: 'core://agent');
      expect(del['deleted_paths'], 2);

      await expectLater(mem.readMemory('core://agent'), throwsA(isA<StateError>()));

      final Map<String, dynamic> still = await mem.readMemory('dynamic://agent_alias');
      expect(still['uri'], 'dynamic://agent_alias');
      expect((still['children'] as List).length, 1);
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });
}

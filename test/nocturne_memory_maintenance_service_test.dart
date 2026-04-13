import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/services/nocturne_memory_maintenance_service.dart';
import 'package:screen_memo/services/nocturne_memory_roots.dart';
import 'package:screen_memo/services/nocturne_memory_service.dart';
import 'package:screen_memo/services/nocturne_memory_signal_service.dart';
import 'package:screen_memo/services/screenshot_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Directory> _prepareDesktopDbRoot() async {
  final Directory tmp = await Directory.systemTemp.createTemp(
    'screen_memo_maintenance_memory_',
  );
  final Directory root = Directory(p.join(tmp.path, 'root'));
  await root.create(recursive: true);
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  return tmp;
}

Future<void> _bootstrapRoots() async {
  final NocturneMemoryService mem = NocturneMemoryService.instance;
  final NocturneMemorySignalService signals =
      NocturneMemorySignalService.instance;
  await mem.resetAll();
  await signals.resetAll();
  await mem.createMemory(
    parentUri: 'core://',
    title: 'agent',
    content: '你是 ScreenMemo 内置的助手。',
    priority: 0,
  );
  await mem.createMemory(
    parentUri: 'core://',
    title: 'my_user',
    content: '这里存放用户长期记忆。',
    priority: 0,
  );
  await mem.createMemory(
    parentUri: 'core://agent',
    title: 'my_user',
    content: '与用户交互时优先尊重用户偏好。',
    priority: 0,
  );
  for (final NocturneMemoryRootSpec root in NocturneMemoryRoots.all) {
    await mem.createMemory(
      parentUri: 'core://my_user',
      title: root.name,
      content: '（自动构建中）',
      priority: 1,
    );
  }
}

NocturneMemorySignalContext _ctx(
  int segmentId,
  DateTime when, {
  int batchIndex = 1,
  List<String> apps = const <String>['哔哩哔哩'],
}) {
  final int ms = when.millisecondsSinceEpoch;
  return NocturneMemorySignalContext(
    segmentId: segmentId,
    batchIndex: batchIndex,
    segmentStartMs: ms,
    segmentEndMs: ms,
    evidenceSummary: '来自动态段 #$segmentId 的截图证据（${when.toIso8601String()}）',
    appNames: apps,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('maintenance parser keeps only safe supported suggestions', () {
    const String raw = '''
```json
{
  "summary": "需要清理一批节点",
  "suggestions": [
    {
      "action": "rewrite_memory",
      "target_uri": "core://my_user/interests/dyson_sphere_program",
      "content": "- 用户长期关注《戴森球计划》\\n- 经常搜索攻略与玩法讨论",
      "reason": "把重复 bullet 合并成稳定节点内容",
      "evidence": "该节点已出现跨天重复证据"
    },
    {
      "action": "rewrite_memory",
      "target_uri": "core://my_user/interests/dyson_sphere_program",
      "content": "- 记忆信号状态：活跃",
      "reason": "错误示例",
      "evidence": "不应保留"
    },
    {
      "action": "move_memory",
      "target_uri": "core://my_user/other/misplaced_item",
      "new_uri": "core://my_user/projects/misplaced_item",
      "reason": "节点归类错误",
      "evidence": "它描述的是持续项目，不是 other"
    },
    {
      "action": "drop_candidate",
      "target_uri": "core://my_user/location/noisy_topic",
      "reason": "非法根路径",
      "evidence": "不应保留"
    }
  ]
}
```''';

    final NocturneMemoryMaintenancePlan plan =
        NocturneMemoryMaintenanceService.parseModelOutput(raw);

    expect(plan.summary, '需要清理一批节点');
    expect(plan.suggestions, hasLength(2));
    expect(
      plan.suggestions.first.action,
      NocturneMemoryMaintenanceAction.rewriteMemory,
    );
    expect(
      plan.suggestions.first.targetUri,
      'core://my_user/interests/dyson_sphere_program',
    );
    expect(
      plan.suggestions.last.action,
      NocturneMemoryMaintenanceAction.moveMemory,
    );
  });

  test(
    'applySuggestions rewrites both profile content and materialized memory',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryService mem = NocturneMemoryService.instance;
        final NocturneMemoryMaintenanceService maintenance =
            NocturneMemoryMaintenanceService.instance;
        await maintenance.resetForTest();
        final DateTime now = DateTime.now();

        await signals.seedCreateActionForTest(
          parentUri: 'core://my_user/interests',
          title: 'dyson_sphere_program',
          content: '用户持续关注《戴森球计划》相关内容。',
          context: _ctx(1, now.subtract(const Duration(days: 3))),
        );
        await signals.seedUpdateActionForTest(
          uri: 'core://my_user/interests/dyson_sphere_program',
          bulletLines: const <String>['- 经常搜索《戴森球计划》攻略与玩法讨论'],
          context: _ctx(2, now),
        );
        await signals.materializeProfiles();

        await maintenance.applySuggestions(
          suggestions: const <NocturneMemoryMaintenanceSuggestion>[
            NocturneMemoryMaintenanceSuggestion(
              action: NocturneMemoryMaintenanceAction.rewriteMemory,
              targetUri: 'core://my_user/interests/dyson_sphere_program',
              content: '- 用户长期关注《戴森球计划》\n- 经常搜索攻略与玩法讨论',
              reason: '把候选草稿整理成更稳定的规范内容',
              evidence: '该节点已跨天出现并正式物化',
            ),
          ],
        );

        final NocturneMemorySignalDiagnosticItem item = (await signals
            .loadDiagnosticItem(
              'core://my_user/interests/dyson_sphere_program',
            ))!;
        expect(item.latestContent, contains('用户长期关注《戴森球计划》'));

        final Map<String, dynamic> node = await mem.readMemory(
          'core://my_user/interests/dyson_sphere_program',
        );
        final String content = (node['content'] as String?) ?? '';
        expect(content, contains('用户长期关注《戴森球计划》'));
        expect(content, contains('记忆信号状态：活跃'));
        expect(maintenance.lastApplyStatus, 'completed');
      } finally {
        await NocturneMemoryMaintenanceService.instance.resetForTest();
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'applySuggestions can add alias for an existing managed memory',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemoryService mem = NocturneMemoryService.instance;
        final NocturneMemoryMaintenanceService maintenance =
            NocturneMemoryMaintenanceService.instance;
        await maintenance.resetForTest();

        await mem.createMemory(
          parentUri: 'core://my_user/organizations',
          title: 'screenpipe',
          content: '用户长期关注 Screenpipe 这个项目相关组织实体。',
          priority: 2,
        );

        await maintenance.applySuggestions(
          suggestions: const <NocturneMemoryMaintenanceSuggestion>[
            NocturneMemoryMaintenanceSuggestion(
              action: NocturneMemoryMaintenanceAction.addAlias,
              targetUri: 'core://my_user/organizations/screenpipe',
              newUri: 'core://my_user/other/screenpipe_ref',
              reason: '需要增加一个跨目录访问入口',
              evidence: '该实体会在其他整理路径中被引用',
            ),
          ],
        );

        final Map<String, dynamic> target = await mem.readMemory(
          'core://my_user/organizations/screenpipe',
        );
        final Map<String, dynamic> alias = await mem.readMemory(
          'core://my_user/other/screenpipe_ref',
        );
        expect(alias['node_uuid'], target['node_uuid']);
        expect(maintenance.lastApplyStatus, 'completed');
      } finally {
        await NocturneMemoryMaintenanceService.instance.resetForTest();
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test('applySuggestions can move an active leaf profile', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final NocturneMemoryMaintenanceService maintenance =
          NocturneMemoryMaintenanceService.instance;
      await maintenance.resetForTest();
      final DateTime now = DateTime.now();

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/other',
        title: 'side_project',
        content: '用户正在维护一个名为 Side Project 的持续项目。',
        context: _ctx(1, now.subtract(const Duration(days: 4))),
      );
      await signals.seedUpdateActionForTest(
        uri: 'core://my_user/other/side_project',
        bulletLines: const <String>['- 持续开发并跟进版本迭代'],
        context: _ctx(2, now),
      );
      await signals.materializeProfiles();

      await maintenance.applySuggestions(
        suggestions: const <NocturneMemoryMaintenanceSuggestion>[
          NocturneMemoryMaintenanceSuggestion(
            action: NocturneMemoryMaintenanceAction.moveMemory,
            targetUri: 'core://my_user/other/side_project',
            newUri: 'core://my_user/projects/side_project',
            reason: '该节点是项目，不应留在 other',
            evidence: '内容明确是持续维护中的项目',
          ),
        ],
      );

      expect(
        await signals.loadDiagnosticItem('core://my_user/other/side_project'),
        isNull,
      );
      final NocturneMemorySignalDiagnosticItem moved = (await signals
          .loadDiagnosticItem('core://my_user/projects/side_project'))!;
      expect(moved.rootUri, 'core://my_user/projects');

      final Map<String, dynamic> node = await mem.readMemory(
        'core://my_user/projects/side_project',
      );
      expect((node['content'] as String?) ?? '', contains('记忆信号状态：活跃'));
      expect(
        () => mem.readMemory('core://my_user/other/side_project'),
        throwsA(isA<StateError>()),
      );
      expect(maintenance.lastApplyStatus, 'completed');
    } finally {
      await NocturneMemoryMaintenanceService.instance.resetForTest();
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('applySuggestions can archive an active leaf profile', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final NocturneMemoryMaintenanceService maintenance =
          NocturneMemoryMaintenanceService.instance;
      await maintenance.resetForTest();
      final DateTime now = DateTime.now();

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/projects',
        title: 'finished_project',
        content: '用户曾持续维护一个已完成的项目。',
        context: _ctx(1, now.subtract(const Duration(days: 3))),
      );
      await signals.seedUpdateActionForTest(
        uri: 'core://my_user/projects/finished_project',
        bulletLines: const <String>['- 已进入收尾阶段并停止新增功能'],
        context: _ctx(2, now),
      );
      await signals.materializeProfiles();

      await maintenance.applySuggestions(
        suggestions: const <NocturneMemoryMaintenanceSuggestion>[
          NocturneMemoryMaintenanceSuggestion(
            action: NocturneMemoryMaintenanceAction.archiveMemory,
            targetUri: 'core://my_user/projects/finished_project',
            reason: '项目已结束，需要进入封存状态',
            evidence: '内容已明确项目完成且停止继续推进',
          ),
        ],
      );

      final NocturneMemorySignalDiagnosticItem archived = (await signals
          .loadDiagnosticItem('core://my_user/projects/finished_project'))!;
      expect(archived.status, NocturneMemorySignalStatus.archived);

      final Map<String, dynamic> node = await mem.readMemory(
        'core://my_user/projects/archive/finished_project',
      );
      expect((node['content'] as String?) ?? '', contains('记忆信号状态：已封存'));
      expect(
        () => mem.readMemory('core://my_user/projects/finished_project'),
        throwsA(isA<StateError>()),
      );
      expect(maintenance.lastApplyStatus, 'completed');
    } finally {
      await NocturneMemoryMaintenanceService.instance.resetForTest();
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('applySuggestions can delete an active leaf profile', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final NocturneMemoryMaintenanceService maintenance =
          NocturneMemoryMaintenanceService.instance;
      await maintenance.resetForTest();
      final DateTime now = DateTime.now();

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/other',
        title: 'obsolete_item',
        content: '这是一条测试用的可删除记忆。',
        context: _ctx(1, now.subtract(const Duration(days: 3))),
      );
      await signals.seedUpdateActionForTest(
        uri: 'core://my_user/other/obsolete_item',
        bulletLines: const <String>['- 已确认无保留价值'],
        context: _ctx(2, now),
      );
      await signals.materializeProfiles();

      await maintenance.applySuggestions(
        suggestions: const <NocturneMemoryMaintenanceSuggestion>[
          NocturneMemoryMaintenanceSuggestion(
            action: NocturneMemoryMaintenanceAction.deleteMemory,
            targetUri: 'core://my_user/other/obsolete_item',
            reason: '该节点已确认无效，应直接删除',
            evidence: '它只是测试残留，不应继续保留',
          ),
        ],
      );

      expect(
        await signals.loadDiagnosticItem('core://my_user/other/obsolete_item'),
        isNull,
      );
      expect(
        () => mem.readMemory('core://my_user/other/obsolete_item'),
        throwsA(isA<StateError>()),
      );
      expect(maintenance.lastApplyStatus, 'completed');
    } finally {
      await NocturneMemoryMaintenanceService.instance.resetForTest();
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test(
    'applyPendingSuggestion removes only the applied pending item',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryMaintenanceService maintenance =
            NocturneMemoryMaintenanceService.instance;
        await maintenance.resetForTest();
        final DateTime now = DateTime.now();

        await signals.seedCreateActionForTest(
          parentUri: 'core://my_user/interests',
          title: 'topic_one',
          content: '用户持续关注主题一。',
          context: _ctx(1, now.subtract(const Duration(days: 3))),
        );
        await signals.seedUpdateActionForTest(
          uri: 'core://my_user/interests/topic_one',
          bulletLines: const <String>['- 经常搜索主题一的资料'],
          context: _ctx(2, now),
        );
        await signals.materializeProfiles();

        maintenance
            .setSuggestionsForTest(const <NocturneMemoryMaintenanceSuggestion>[
              NocturneMemoryMaintenanceSuggestion(
                action: NocturneMemoryMaintenanceAction.rewriteMemory,
                targetUri: 'core://my_user/interests/topic_one',
                content: '- 用户长期关注主题一',
                reason: '整理内容',
                evidence: '已有正式证据',
              ),
              NocturneMemoryMaintenanceSuggestion(
                action: NocturneMemoryMaintenanceAction.dropCandidate,
                targetUri: 'core://my_user/interests/topic_two',
                reason: '保留用于测试剩余项',
                evidence: '测试',
              ),
            ]);

        await maintenance.applyPendingSuggestion(maintenance.suggestions.first);

        expect(maintenance.suggestions, hasLength(1));
        expect(
          maintenance.suggestions.single.targetUri,
          'core://my_user/interests/topic_two',
        );
        expect(maintenance.lastApplyStatus, 'completed');
      } finally {
        await NocturneMemoryMaintenanceService.instance.resetForTest();
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test('dismissSuggestion removes only the dismissed pending item', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemoryMaintenanceService maintenance =
          NocturneMemoryMaintenanceService.instance;
      await maintenance.resetForTest();
      maintenance
          .setSuggestionsForTest(const <NocturneMemoryMaintenanceSuggestion>[
            NocturneMemoryMaintenanceSuggestion(
              action: NocturneMemoryMaintenanceAction.dropCandidate,
              targetUri: 'core://my_user/interests/noisy_a',
              reason: '测试忽略 A',
              evidence: '测试',
            ),
            NocturneMemoryMaintenanceSuggestion(
              action: NocturneMemoryMaintenanceAction.dropCandidate,
              targetUri: 'core://my_user/interests/noisy_b',
              reason: '测试忽略 B',
              evidence: '测试',
            ),
          ]);

      await maintenance.dismissSuggestion(maintenance.suggestions.first);

      expect(maintenance.suggestions, hasLength(1));
      expect(
        maintenance.suggestions.single.targetUri,
        'core://my_user/interests/noisy_b',
      );
      expect(maintenance.lastApplyStatus, 'dismissed');
    } finally {
      await NocturneMemoryMaintenanceService.instance.resetForTest();
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('applySuggestions can drop a noisy candidate profile', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryMaintenanceService maintenance =
          NocturneMemoryMaintenanceService.instance;
      await maintenance.resetForTest();

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'flash_topic',
        content: '用户短暂浏览过某个热点话题。',
        context: _ctx(1, DateTime.now()),
      );

      final NocturneMemorySignalDashboard before = await signals.loadDashboard(
        limitPerStatus: 5,
      );
      expect(before.candidateCount, greaterThanOrEqualTo(1));

      await maintenance.applySuggestions(
        suggestions: const <NocturneMemoryMaintenanceSuggestion>[
          NocturneMemoryMaintenanceSuggestion(
            action: NocturneMemoryMaintenanceAction.dropCandidate,
            targetUri: 'core://my_user/interests/flash_topic',
            reason: '只有一次弱证据，且不值得长期跟踪',
            evidence: '没有跨天、没有主动搜索、没有后续出现',
          ),
        ],
      );

      final NocturneMemorySignalDiagnosticItem? after = await signals
          .loadDiagnosticItem('core://my_user/interests/flash_topic');
      expect(after, isNull);
      expect(maintenance.lastApplyStatus, 'completed');
    } finally {
      await NocturneMemoryMaintenanceService.instance.resetForTest();
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });
}

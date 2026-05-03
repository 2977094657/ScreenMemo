import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_roots.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_service.dart';

class MemoryEntityRootPolicy {
  const MemoryEntityRootPolicy({
    required this.rootKey,
    required this.rootUri,
    required this.entityType,
    required this.activationScore,
    required this.minDistinctDays,
    required this.allowSingleStrongActivation,
    required this.archiveAfterDays,
    required this.decayTauDays,
    required this.allowRootMaterialization,
    required this.preferSpecificChildNodes,
    required this.strongKeywords,
  });

  final String rootKey;
  final String rootUri;
  final String entityType;
  final double activationScore;
  final int minDistinctDays;
  final bool allowSingleStrongActivation;
  final int archiveAfterDays;
  final int decayTauDays;
  final bool allowRootMaterialization;
  final bool preferSpecificChildNodes;
  final List<String> strongKeywords;
}

class MemoryEntityPolicies {
  MemoryEntityPolicies._();

  static const Map<String, MemoryEntityRootPolicy>
  byRootUri = <String, MemoryEntityRootPolicy>{
    'core://my_user/identity': MemoryEntityRootPolicy(
      rootKey: 'identity',
      rootUri: 'core://my_user/identity',
      entityType: 'identity',
      activationScore: 1.4,
      minDistinctDays: 1,
      allowSingleStrongActivation: true,
      archiveAfterDays: 240,
      decayTauDays: 180,
      allowRootMaterialization: true,
      preferSpecificChildNodes: false,
      strongKeywords: <String>['职业', '身份', '擅长', '设备', '长期', '使用', '工作'],
    ),
    'core://my_user/people': MemoryEntityRootPolicy(
      rootKey: 'people',
      rootUri: 'core://my_user/people',
      entityType: 'people',
      activationScore: 2.0,
      minDistinctDays: 2,
      allowSingleStrongActivation: true,
      archiveAfterDays: 180,
      decayTauDays: 150,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>['朋友', '同事', '家人', '导师', '对象', '联系人', '客户', '长期'],
    ),
    'core://my_user/places': MemoryEntityRootPolicy(
      rootKey: 'places',
      rootUri: 'core://my_user/places',
      entityType: 'places',
      activationScore: 2.0,
      minDistinctDays: 2,
      allowSingleStrongActivation: true,
      archiveAfterDays: 120,
      decayTauDays: 90,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>['住在', '常去', '经常去', '公司', '学校', '家', '住所', '长期'],
    ),
    'core://my_user/organizations': MemoryEntityRootPolicy(
      rootKey: 'organizations',
      rootUri: 'core://my_user/organizations',
      entityType: 'organizations',
      activationScore: 2.0,
      minDistinctDays: 2,
      allowSingleStrongActivation: true,
      archiveAfterDays: 180,
      decayTauDays: 150,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>['公司', '学校', '团队', '社区', '品牌', '平台', '长期'],
    ),
    'core://my_user/preferences': MemoryEntityRootPolicy(
      rootKey: 'preferences',
      rootUri: 'core://my_user/preferences',
      entityType: 'preferences',
      activationScore: 1.4,
      minDistinctDays: 1,
      allowSingleStrongActivation: true,
      archiveAfterDays: 180,
      decayTauDays: 120,
      allowRootMaterialization: true,
      preferSpecificChildNodes: false,
      strongKeywords: <String>['喜欢', '偏好', '常用', '默认', '不喜欢', '讨厌', '倾向'],
    ),
    'core://my_user/interests': MemoryEntityRootPolicy(
      rootKey: 'interests',
      rootUri: 'core://my_user/interests',
      entityType: 'interests',
      activationScore: 2.6,
      minDistinctDays: 2,
      allowSingleStrongActivation: false,
      archiveAfterDays: 45,
      decayTauDays: 30,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>[
        '持续',
        '长期',
        '经常',
        '常看',
        '关注',
        '研究',
        '学习',
        '搜索',
        '收藏',
        '订阅',
        '反复',
      ],
    ),
    'core://my_user/projects': MemoryEntityRootPolicy(
      rootKey: 'projects',
      rootUri: 'core://my_user/projects',
      entityType: 'projects',
      activationScore: 1.8,
      minDistinctDays: 2,
      allowSingleStrongActivation: true,
      archiveAfterDays: 120,
      decayTauDays: 90,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>['项目', '开发', '维护', '版本', '需求', '计划', '正在'],
    ),
    'core://my_user/goals': MemoryEntityRootPolicy(
      rootKey: 'goals',
      rootUri: 'core://my_user/goals',
      entityType: 'goals',
      activationScore: 1.8,
      minDistinctDays: 1,
      allowSingleStrongActivation: true,
      archiveAfterDays: 120,
      decayTauDays: 90,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>['目标', '计划', '打算', '准备', '想要', '希望'],
    ),
    'core://my_user/habits': MemoryEntityRootPolicy(
      rootKey: 'habits',
      rootUri: 'core://my_user/habits',
      entityType: 'habits',
      activationScore: 2.8,
      minDistinctDays: 3,
      allowSingleStrongActivation: false,
      archiveAfterDays: 90,
      decayTauDays: 60,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>['每天', '每周', '习惯', '总是', '通常', '固定', '经常'],
    ),
    'core://my_user/other': MemoryEntityRootPolicy(
      rootKey: 'other',
      rootUri: 'core://my_user/other',
      entityType: 'other',
      activationScore: 3.0,
      minDistinctDays: 2,
      allowSingleStrongActivation: false,
      archiveAfterDays: 90,
      decayTauDays: 60,
      allowRootMaterialization: false,
      preferSpecificChildNodes: true,
      strongKeywords: <String>['长期', '持续', '反复', '稳定'],
    ),
  };

  static final Map<String, MemoryEntityRootPolicy> byRootKey =
      <String, MemoryEntityRootPolicy>{
        for (final MemoryEntityRootPolicy policy in byRootUri.values)
          policy.rootKey: policy,
      };

  static MemoryEntityRootPolicy? forRootUri(String uri) {
    final String normalized = NocturneMemoryService.instance.makeUri(
      NocturneMemoryService.instance.parseUri(uri).domain,
      NocturneMemoryService.instance.parseUri(uri).path,
    );
    if (byRootUri.containsKey(normalized)) {
      return byRootUri[normalized];
    }
    for (final NocturneMemoryRootSpec root in NocturneMemoryRoots.all) {
      if (normalized == root.uri || normalized.startsWith('${root.uri}/')) {
        return byRootUri[root.uri];
      }
    }
    return null;
  }

  static MemoryEntityRootPolicy? forRootKey(String rootKey) {
    return byRootKey[rootKey.trim().toLowerCase()];
  }

  static List<String> get rootKeys => byRootKey.keys.toList(growable: false);

  static String? rootUriForKey(String rootKey) {
    return forRootKey(rootKey)?.rootUri;
  }
}

import 'screenshot_database.dart';

/// 站点分组实体（用户可配置多个接口站点作为备用）
class AISiteGroup {
  final int id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final String model;
  final int orderIndex;
  final bool enabled;

  AISiteGroup({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.orderIndex,
    required this.enabled,
  });

  AISiteGroup copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? orderIndex,
    bool? enabled,
  }) {
    return AISiteGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      orderIndex: orderIndex ?? this.orderIndex,
      enabled: enabled ?? this.enabled,
    );
  }

  static AISiteGroup fromMap(Map<String, dynamic> m) {
    return AISiteGroup(
      id: (m['id'] as int?) ?? 0,
      name: (m['name'] as String?)?.trim() ?? 'Group',
      baseUrl: (m['base_url'] as String?)?.trim() ?? '',
      apiKey: (m['api_key'] as String?)?.trim(),
      model: (m['model'] as String?)?.trim() ?? 'gpt-4o-mini',
      orderIndex: (m['order_index'] as int?) ?? 0,
      enabled: ((m['enabled'] as int?) ?? 1) != 0,
    );
  }
}

/// 发送请求所需的端点（可为分组，也可为“未分组”单站点）
class AIEndpoint {
  final int? groupId; // null 表示使用未分组（ai_settings）
  final String baseUrl;
  final String? apiKey;
  final String model;

  AIEndpoint({required this.groupId, required this.baseUrl, required this.apiKey, required this.model});
}

/// AI 设置与会话持久化服务
/// - 支持分组多站点，失败自动切换
/// - 会话历史按分组隔离（conversation_id = 'group:<id>' 或 'default'）
class AISettingsService {
  AISettingsService._internal();
  static final AISettingsService instance = AISettingsService._internal();

  // 存储键名（SQLite ai_settings 表）
  static const String _keyBaseUrl = 'base_url';
  static const String _keyApiKey = 'api_key';
  static const String _keyModel = 'model';
  static const String _keyStreamEnabled = 'stream_enabled';
  static const String _keyActiveGroupId = 'active_group_id'; // 当前激活的分组
  // 提示词键名
  static const String _keyPromptSegment = 'prompt_segment';
  static const String _keyPromptMerge = 'prompt_merge';

  // 默认值
  static const String _defaultBaseUrl = 'https://api.openai.com';
  static const String _defaultModel = 'gpt-4o-mini';

  // 历史限制（仅保存最近 N 条，避免无限膨胀）
  static const int _maxHistoryMessages = 40;

  // ========== 基础布尔设置（流式开关） ==========
  Future<bool> getStreamEnabled() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyStreamEnabled);
    if (v == null || v.isEmpty) return true; // 默认开启
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setStreamEnabled(bool enabled) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyStreamEnabled, enabled ? '1' : '0');
  }

  // ========== 分组管理 ==========

  Future<int?> getActiveGroupId() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyActiveGroupId);
    if (v == null || v.trim().isEmpty) return null;
    return int.tryParse(v.trim());
  }

  Future<void> setActiveGroupId(int? id) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyActiveGroupId, id == null ? null : id.toString());
  }

  Future<List<AISiteGroup>> listSiteGroups() async {
    final master = await ScreenshotDatabase.instance.database;
    final rows = await master.query(
      'ai_site_groups',
      orderBy: 'enabled DESC, order_index ASC, id ASC',
    );
    return rows.map((e) => AISiteGroup.fromMap(e)).toList();
  }

  Future<AISiteGroup?> getSiteGroupById(int id) async {
    final master = await ScreenshotDatabase.instance.database;
    final rows = await master.query('ai_site_groups', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return AISiteGroup.fromMap(rows.first);
  }

  Future<int> addSiteGroup({
    required String name,
    required String baseUrl,
    String? apiKey,
    required String model,
    bool enabled = true,
  }) async {
    final master = await ScreenshotDatabase.instance.database;
    int maxOrder = 0;
    try {
      final res = await master.rawQuery('SELECT COALESCE(MAX(order_index), -1) AS m FROM ai_site_groups');
      maxOrder = ((res.first['m'] as int?) ?? -1) + 1;
    } catch (_) {
      maxOrder = 0;
    }
    final id = await master.insert('ai_site_groups', {
      'name': name.trim(),
      'base_url': baseUrl.trim(),
      'api_key': (apiKey ?? '').trim().isEmpty ? null : apiKey!.trim(),
      'model': model.trim(),
      'order_index': maxOrder,
      'enabled': enabled ? 1 : 0,
    });
    return id;
  }

  Future<void> updateSiteGroup(AISiteGroup g) async {
    final master = await ScreenshotDatabase.instance.database;
    await master.update('ai_site_groups', {
      'name': g.name.trim(),
      'base_url': g.baseUrl.trim(),
      'api_key': (g.apiKey ?? '').trim().isEmpty ? null : g.apiKey!.trim(),
      'model': g.model.trim(),
      'order_index': g.orderIndex,
      'enabled': g.enabled ? 1 : 0,
    }, where: 'id = ?', whereArgs: [g.id]);
  }

  Future<void> deleteSiteGroup(int id) async {
    final master = await ScreenshotDatabase.instance.database;
    try {
      await master.delete('ai_site_groups', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
    // 清理该分组的会话历史
    try {
      await ScreenshotDatabase.instance.clearAiConversation(_conversationIdForGroup(id));
    } catch (_) {}
    // 如果当前激活组是它，则清空激活
    try {
      final active = await getActiveGroupId();
      if (active == id) {
        await setActiveGroupId(null);
      }
    } catch (_) {}
  }

  // ========== 单站点（未分组）键值对（保持兼容） ==========

  Future<String> getBaseUrl() async {
    final activeId = await getActiveGroupId();
    if (activeId != null) {
      final g = await getSiteGroupById(activeId);
      if (g != null) return g.baseUrl;
    }
    // 回退到未分组
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyBaseUrl);
    return (v == null || v.isEmpty) ? _defaultBaseUrl : v;
  }

  Future<void> setBaseUrl(String url) async {
    // 未分组场景更新（分组下请使用 updateSiteGroup）
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyBaseUrl, url.trim());
  }

  Future<String?> getApiKey() async {
    final activeId = await getActiveGroupId();
    if (activeId != null) {
      final g = await getSiteGroupById(activeId);
      if (g != null) return (g.apiKey ?? '').isEmpty ? null : g.apiKey;
    }
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyApiKey);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setApiKey(String? key) async {
    // 未分组场景更新（分组下请使用 updateSiteGroup）
    final db = ScreenshotDatabase.instance;
    if (key == null || key.trim().isEmpty) {
      await db.setAiSetting(_keyApiKey, null);
    } else {
      await db.setAiSetting(_keyApiKey, key.trim());
    }
  }

  Future<String> getModel() async {
    final activeId = await getActiveGroupId();
    if (activeId != null) {
      final g = await getSiteGroupById(activeId);
      if (g != null) return g.model;
    }
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyModel);
    return (v == null || v.isEmpty) ? _defaultModel : v;
  }

  Future<void> setModel(String model) async {
    // 未分组场景更新（分组下请使用 updateSiteGroup）
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyModel, model.trim());
  }

  // ========== 提示词管理 ==========
  Future<String?> getPromptSegment() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyPromptSegment);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> setPromptSegment(String? value) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyPromptSegment, (value == null || value.trim().isEmpty) ? null : value.trim());
  }

  Future<String?> getPromptMerge() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyPromptMerge);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> setPromptMerge(String? value) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyPromptMerge, (value == null || value.trim().isEmpty) ? null : value.trim());
  }

  // ========== 端点候选（用于失败自动切换） ==========

  Future<List<AIEndpoint>> getEndpointCandidates() async {
    final groups = await listSiteGroups();
    if (groups.isNotEmpty) {
      final active = await getActiveGroupId();
      final enabledGroups = groups.where((g) => g.enabled).toList();
      enabledGroups.sort((a, b) {
        if (active != null) {
          if (a.id == active && b.id != active) return -1;
          if (b.id == active && a.id != active) return 1;
        }
        final oi = a.orderIndex.compareTo(b.orderIndex);
        if (oi != 0) return oi;
        return a.id.compareTo(b.id);
      });
      return enabledGroups
          .map((g) => AIEndpoint(groupId: g.id, baseUrl: g.baseUrl, apiKey: g.apiKey, model: g.model))
          .toList();
    }

    // 未分组回退
    final db = ScreenshotDatabase.instance;
    final rawBase = await db.getAiSetting(_keyBaseUrl);
    final baseUrl = (rawBase == null || rawBase.isEmpty) ? _defaultBaseUrl : rawBase;
    final apiKey = await db.getAiSetting(_keyApiKey);
    final rawModel = await db.getAiSetting(_keyModel);
    final model = (rawModel == null || rawModel.isEmpty) ? _defaultModel : rawModel;
    return <AIEndpoint>[AIEndpoint(groupId: null, baseUrl: baseUrl, apiKey: apiKey, model: model)];
  }

  // ========== 会话历史（按分组隔离） ==========

  String _conversationIdForGroup(int? groupId) => groupId == null ? 'default' : 'group:$groupId';

  Future<List<AIMessage>> getChatHistory() async {
    final gid = await getActiveGroupId();
    return getChatHistoryByGroup(gid);
  }

  Future<List<AIMessage>> getChatHistoryByGroup(int? groupId) async {
    final db = ScreenshotDatabase.instance;
    final rows = await db.getAiMessages(_conversationIdForGroup(groupId));
    return rows
        .map((e) => AIMessage(
              role: (e['role'] as String?) ?? 'user',
              content: (e['content'] as String?) ?? '',
            ))
        .toList();
  }

  Future<void> saveChatHistory(List<AIMessage> messages) async {
    final gid = await getActiveGroupId();
    await saveChatHistoryByGroup(gid, messages);
  }

  Future<void> saveChatHistoryByGroup(int? groupId, List<AIMessage> messages) async {
    final db = ScreenshotDatabase.instance;
    final trimmed = messages.length > _maxHistoryMessages
        ? messages.sublist(messages.length - _maxHistoryMessages)
        : messages;
    final conv = _conversationIdForGroup(groupId);
    await db.clearAiConversation(conv);
    for (final m in trimmed) {
      await db.appendAiMessage(conv, m.role, m.content);
    }
  }

  Future<void> clearChatHistory() async {
    final gid = await getActiveGroupId();
    await clearChatHistoryByGroup(gid);
  }

  Future<void> clearChatHistoryByGroup(int? groupId) async {
    final db = ScreenshotDatabase.instance;
    await db.clearAiConversation(_conversationIdForGroup(groupId));
  }
}

/// 简单的对话消息模型
class AIMessage {
  final String role; // system | user | assistant
  final String content;

  AIMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };

  factory AIMessage.fromJson(Map<String, dynamic> json) {
    return AIMessage(
      role: (json['role'] as String?) ?? 'user',
      content: (json['content'] as String?) ?? '',
    );
  }
}

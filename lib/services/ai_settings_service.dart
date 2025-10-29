import 'dart:async';
import 'package:flutter/widgets.dart';
import 'screenshot_database.dart';
import 'locale_service.dart';
import 'ai_providers_service.dart';
import 'package:flutter/services.dart'; // Added for MethodChannel
import 'flutter_logger.dart';

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
  final int? groupId; // null 表示使用未分组（ai_settings）；负数表示 ProviderID 映射
  final String baseUrl;
  final String? apiKey;
  final String model;
  final String chatPath; // 基于 Provider 的可配置路径，默认 /v1/chat/completions

  AIEndpoint({
    required this.groupId,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.chatPath = '/v1/chat/completions',
  });
}

/// AI 设置与会话持久化服务
/// - 支持分组多站点，失败自动切换
/// - 会话历史按分组隔离（conversation_id = 'group:<id>' 或 'default'）
class AISettingsService {
  AISettingsService._internal();
  static final AISettingsService instance = AISettingsService._internal();

  // 上下文变更事件（如 chat 选择变更）广播
  final StreamController<String> _ctxChangedController = StreamController<String>.broadcast();
  Stream<String> get onContextChanged => _ctxChangedController.stream;

  // 存储键名（SQLite ai_settings 表）
  static const String _keyBaseUrl = 'base_url';
  static const String _keyApiKey = 'api_key';
  static const String _keyModel = 'model';
  static const String _keyStreamEnabled = 'stream_enabled';
  static const String _keyRenderImagesDuringStreaming = 'render_images_during_streaming';
  static const String _keyActiveGroupId = 'active_group_id'; // 当前激活的分组
  // 提示词键名（历史兼容 + 语言区分）
  static const String _keyPromptSegment = 'prompt_segment';         // 旧版（不分语种）
  static const String _keyPromptMerge   = 'prompt_merge';           // 旧版（不分语种）
  static const String _keyPromptDaily   = 'prompt_daily';           // 旧版（不分语种）
  static const String _keyPromptSegmentZh = 'prompt_segment_zh';
  static const String _keyPromptSegmentEn = 'prompt_segment_en';
  static const String _keyPromptMergeZh   = 'prompt_merge_zh';
  static const String _keyPromptMergeEn   = 'prompt_merge_en';
  static const String _keyPromptDailyZh   = 'prompt_daily_zh';
  static const String _keyPromptDailyEn   = 'prompt_daily_en';

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

  // 是否在流式期间实时渲染图片（默认 false：为提升性能，完成后再统一渲染）
  Future<bool> getRenderImagesDuringStreaming() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyRenderImagesDuringStreaming);
    if (v == null || v.isEmpty) return false;
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setRenderImagesDuringStreaming(bool value) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyRenderImagesDuringStreaming, value ? '1' : '0');
  }

  // ========== 分组管理（v6 起移除 legacy，统一使用提供商+上下文） ==========
 
  Future<int?> getActiveGroupId() async {
    try {
      final ctx = await ScreenshotDatabase.instance.getAIContext('chat');
      if (ctx != null && ctx['provider_id'] is int) {
        final int pid = ctx['provider_id'] as int;
        return -pid.abs(); // 使用负的 ProviderID 作为 groupId
      }
      return null;
    } catch (_) {
      return null;
    }
  }
 
  Future<void> setActiveGroupId(int? id) async {
    // v6: 不再使用独立的激活组键，改为依赖 ai_contexts('chat')
    return;
  }
 
  Future<List<AISiteGroup>> listSiteGroups() async {
    return <AISiteGroup>[];
  }
 
  Future<AISiteGroup?> getSiteGroupById(int id) async {
    return null;
  }
 
  Future<int> addSiteGroup({
    required String name,
    required String baseUrl,
    String? apiKey,
    required String model,
    bool enabled = true,
  }) async {
    return 0;
  }
 
  Future<void> updateSiteGroup(AISiteGroup g) async {
    return;
  }
 
  Future<void> deleteSiteGroup(int id) async {
    return;
  }

  // ========== 单站点（未分组）键值对（保持兼容） ==========

  Future<String> getBaseUrl() async {
    try {
      final providers = await AIProvidersService.instance.listProviders();
      if (providers.isEmpty) return _defaultBaseUrl;
      final ctx = await ScreenshotDatabase.instance.getAIContext('chat');
      AIProvider? sel;
      if (ctx != null && ctx['provider_id'] is int) {
        sel = providers.firstWhere(
          (p) => (p.id ?? -1) == (ctx['provider_id'] as int),
          orElse: () => providers.first,
        );
      }
      sel ??= (await AIProvidersService.instance.getDefaultProvider()) ?? providers.first;
      final base = sel.baseUrl;
      if (base == null || base.trim().isEmpty) return _defaultBaseUrl;
      return base.trim();
    } catch (_) {
      return _defaultBaseUrl;
    }
  }

  Future<void> setBaseUrl(String url) async {
    // v6: baseUrl 请在“提供商”中配置；此处不再写 ai_settings
    return;
  }

  Future<String?> getApiKey() async {
    try {
      final ctx = await ScreenshotDatabase.instance.getAIContext('chat');
      if (ctx != null && ctx['provider_id'] is int) {
        return await AIProvidersService.instance.getApiKey(ctx['provider_id'] as int);
      }
      final def = await AIProvidersService.instance.getDefaultProvider();
      if (def?.id != null) {
        return await AIProvidersService.instance.getApiKey(def!.id!);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setApiKey(String? key) async {
    try {
      final ctx = await ScreenshotDatabase.instance.getAIContext('chat');
      AIProvider? sel;
      if (ctx != null && ctx['provider_id'] is int) {
        sel = await AIProvidersService.instance.getProvider(ctx['provider_id'] as int);
      } else {
        sel = await AIProvidersService.instance.getDefaultProvider();
      }
      final int? pid = sel?.id;
      if (pid == null) return;
      if (key == null || key.trim().isEmpty) {
        await AIProvidersService.instance.deleteApiKey(pid);
      } else {
        await AIProvidersService.instance.saveApiKey(pid, key.trim());
      }
    } catch (_) {}
  }

  Future<String> getModel() async {
    try {
      final providers = await AIProvidersService.instance.listProviders();
      if (providers.isEmpty) return _defaultModel;
      final ctx = await ScreenshotDatabase.instance.getAIContext('chat');
      AIProvider? sel;
      if (ctx != null && ctx['provider_id'] is int) {
        sel = providers.firstWhere(
          (p) => (p.id ?? -1) == (ctx['provider_id'] as int),
          orElse: () => providers.first,
        );
      }
      sel ??= (await AIProvidersService.instance.getDefaultProvider()) ?? providers.first;
      String model = (ctx != null && (ctx['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctx['model'] as String).trim()
          : (sel.extra['active_model'] as String? ?? sel.defaultModel).toString().trim();
      if (model.isEmpty) {
        model = sel.models.isNotEmpty ? sel.models.first : _defaultModel;
      }
      return model;
    } catch (_) {
      return _defaultModel;
    }
  }

  Future<void> setModel(String model) async {
    try {
      // 更新聊天上下文的模型，保持 provider 不变
      final ctx = await ScreenshotDatabase.instance.getAIContext('chat');
      int providerId;
      if (ctx != null && ctx['provider_id'] is int) {
        providerId = ctx['provider_id'] as int;
      } else {
        final def = await AIProvidersService.instance.getDefaultProvider();
        if (def?.id == null) return;
        providerId = def!.id!;
      }
      await ScreenshotDatabase.instance.setAIContext(context: 'chat', providerId: providerId, model: model.trim());
      try { _ctxChangedController.add('chat'); } catch (_) {}
    } catch (_) {}
  }

  // ========== 提示词管理 ==========
  String _currentLang() {
    // 优先应用语言；为空时回退系统语言；仅识别 zh / en
    final loc = LocaleService.instance.locale;
    final code = (loc?.languageCode ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode)
        .toLowerCase();
    return code.startsWith('zh') ? 'zh' : 'en';
  }

  Future<String?> getPromptSegment() async {
    final db = ScreenshotDatabase.instance;
    final lang = _currentLang();
    // 先取语种键；不存在则回退历史通用键
    final key = lang == 'zh' ? _keyPromptSegmentZh : _keyPromptSegmentEn;
    String? v = await db.getAiSetting(key);
    v ??= await db.getAiSetting(_keyPromptSegment);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> setPromptSegment(String? value) async {
    final db = ScreenshotDatabase.instance;
    final lang = _currentLang();
    final key = lang == 'zh' ? _keyPromptSegmentZh : _keyPromptSegmentEn;
    await db.setAiSetting(key, (value == null || value.trim().isEmpty) ? null : value.trim());
  }

  Future<String?> getPromptMerge() async {
    final db = ScreenshotDatabase.instance;
    final lang = _currentLang();
    final key = lang == 'zh' ? _keyPromptMergeZh : _keyPromptMergeEn;
    String? v = await db.getAiSetting(key);
    v ??= await db.getAiSetting(_keyPromptMerge);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> setPromptMerge(String? value) async {
    final db = ScreenshotDatabase.instance;
    final lang = _currentLang();
    final key = lang == 'zh' ? _keyPromptMergeZh : _keyPromptMergeEn;
    await db.setAiSetting(key, (value == null || value.trim().isEmpty) ? null : value.trim());
  }

  // ========== 每日总结提示词 ==========
  Future<String?> getPromptDaily() async {
    final db = ScreenshotDatabase.instance;
    final lang = _currentLang();
    final key = lang == 'zh' ? _keyPromptDailyZh : _keyPromptDailyEn;
    String? v = await db.getAiSetting(key);
    v ??= await db.getAiSetting(_keyPromptDaily);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> setPromptDaily(String? value) async {
    final db = ScreenshotDatabase.instance;
    final lang = _currentLang();
    final key = lang == 'zh' ? _keyPromptDailyZh : _keyPromptDailyEn;
    await db.setAiSetting(key, (value == null || value.trim().isEmpty) ? null : value.trim());
  }

  // ========== 端点候选（用于失败自动切换） ==========

  /// 基于 Provider 的端点候选（仅提供商+上下文）
  /// - context: 'chat' | 其他（如 'segments'）
  /// - 不再回退到 site_groups/ai_settings
  Future<List<AIEndpoint>> getEndpointCandidates({String context = 'chat'}) async {
    final providers = await AIProvidersService.instance.listProviders();
    if (providers.isEmpty) {
      // 对于 segments 上下文，尝试直接从原生配置复用（确保与动态一致）
      if (context == 'segments') {
        try {
          const MethodChannel ch = MethodChannel('com.fqyw.screen_memo/accessibility');
          final Map<dynamic, dynamic>? segCfg = await ch.invokeMethod('getSegmentsAIConfig');
          if (segCfg != null) {
            final String baseUrl = ((segCfg['baseUrl'] as String?) ?? '').trim();
            final String model = ((segCfg['model'] as String?) ?? '').trim();
            final String? apiKey = ((segCfg['apiKey'] as String?) ?? '').trim();
            if (model.isNotEmpty && (apiKey != null && apiKey.isNotEmpty)) {
              return <AIEndpoint>[
                AIEndpoint(
                  groupId: -1,
                  baseUrl: baseUrl.isEmpty ? _defaultBaseUrl : baseUrl,
                  apiKey: apiKey,
                  model: model,
                  chatPath: '/v1/chat/completions',
                )
              ];
            }
          }
        } catch (_) {}
      }
      return <AIEndpoint>[];
    }
 
    // 读取上下文选择：优先 ai_contexts(context)，否则默认提供商，否则列表首项
    final db = ScreenshotDatabase.instance;
    final ctx = await db.getAIContext(context);
    AIProvider? pSelected;
    if (ctx != null && ctx['provider_id'] is int) {
      pSelected = providers.firstWhere(
        (p) => (p.id ?? -1) == (ctx['provider_id'] as int),
        orElse: () => providers.first,
      );
    }
    pSelected ??= (await AIProvidersService.instance.getDefaultProvider()) ?? providers.first;
 
    // 解析模型：上下文显式 -> extra.active_model -> default_model -> models.first -> 默认
    String model = (ctx != null && (ctx['model'] as String?)?.trim().isNotEmpty == true)
        ? (ctx['model'] as String).trim()
        : (pSelected.extra['active_model'] as String? ?? pSelected.defaultModel).toString().trim();
    if (model.isEmpty) {
      model = pSelected.models.isNotEmpty ? pSelected.models.first : _defaultModel;
    }
 
    // 读取 API Key
    String? apiKey = await AIProvidersService.instance.getApiKey(pSelected.id!);
    // 对于“动态(segments)”上下文：
    // 1) 优先原生配置（与动态完全一致）
    // 2) 其次 DB 中的 ai_settings.api_key_segments
    String baseUrlOverride = '';
    if (context == 'segments') {
      bool setFromNative = false;
      try {
        const MethodChannel ch = MethodChannel('com.fqyw.screen_memo/accessibility');
        final Map<dynamic, dynamic>? segCfg = await ch.invokeMethod('getSegmentsAIConfig');
        if (segCfg != null) {
          final String baseFromNative = ((segCfg['baseUrl'] as String?) ?? '').trim();
          final String modelFromNative = ((segCfg['model'] as String?) ?? '').trim();
          final String? keyFromNative = ((segCfg['apiKey'] as String?) ?? '').trim();
          if ((keyFromNative != null && keyFromNative.isNotEmpty)) {
            apiKey = keyFromNative;
            setFromNative = true;
          }
          if (modelFromNative.isNotEmpty) model = modelFromNative;
          if (baseFromNative.isNotEmpty) baseUrlOverride = baseFromNative;
        }
      } catch (_) {}
      if (!setFromNative) {
        try {
          final k = await ScreenshotDatabase.instance.getAiSetting('api_key_segments');
          if (k != null && k.trim().isNotEmpty) {
            apiKey = k.trim();
          }
        } catch (_) {}
      }
    }
 
    // 规范化 base 与 chatPath（若上方从原生覆盖 model/base，应在此处理）
    String baseUrl = (pSelected.baseUrl == null || pSelected.baseUrl!.trim().isEmpty)
        ? _defaultBaseUrl
        : pSelected.baseUrl!.trim();
    if (baseUrlOverride.isNotEmpty) baseUrl = baseUrlOverride;
    final String chatPath = (pSelected.chatPath == null || pSelected.chatPath!.trim().isEmpty)
        ? '/v1/chat/completions'
        : pSelected.chatPath!.trim();
 
    // 使用负的 ProviderID 作为 groupId，隔离会话历史
    final int groupId = -1 * (pSelected.id ?? 0).abs();
 
    return <AIEndpoint>[
      AIEndpoint(
        groupId: groupId,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        chatPath: chatPath,
      )
    ];
  }

  // ========== 会话（Conversation）管理与历史 ==========
 
  String _conversationIdForGroup(int? groupId) => groupId == null ? 'default' : 'group:$groupId';
 
  // 读取/初始化当前激活会话CID（ai_settings.chat_active_cid）
  Future<String> getActiveConversationCid() async {
    try {
      final db = ScreenshotDatabase.instance;
      String? cid = await db.getAiSetting('chat_active_cid');
      if (cid != null && cid.trim().isNotEmpty) return cid.trim();
      // 初始化：确保 default 存在并设为激活
      try {
        // 不使用硬编码标题，留空以便前端按本地化占位显示
        final created = await db.createAiConversation(title: '', cid: 'default');
        cid = created;
      } catch (_) {
        cid = 'default';
      }
      await db.setAiSetting('chat_active_cid', cid);
      return cid;
    } catch (_) {
      return 'default';
    }
  }
 
  Future<void> setActiveConversationCid(String cid) async {
    try {
      final db = ScreenshotDatabase.instance;
      await db.setAiSetting('chat_active_cid', cid.trim());
      try { await db.touchAiConversation(cid.trim()); } catch (_) {}
      try { _ctxChangedController.add('chat'); } catch (_) {}
    } catch (_) {}
  }
 
  Future<List<Map<String, dynamic>>> listAiConversations({int? limit, int? offset}) {
    return ScreenshotDatabase.instance.listAiConversations(limit: limit, offset: offset);
  }
 
  Future<String> createConversation({String? title}) async {
    final db = ScreenshotDatabase.instance;
    // 留空标题，UI 层使用本地化的无标题占位
    final cid = await db.createAiConversation(title: (title == null || title.trim().isEmpty) ? '' : title.trim());
    await setActiveConversationCid(cid);
    return cid;
  }
 
  Future<bool> renameConversation(String cid, String title) {
    return ScreenshotDatabase.instance.renameAiConversation(cid, title);
  }
 
  Future<bool> deleteConversation(String cid) async {
    final db = ScreenshotDatabase.instance;
    final sw = Stopwatch()..start();
    final ok = await db.deleteAiConversation(cid);
    sw.stop();
    try { await FlutterLogger.nativeInfo('UI', 'deleteConversation done ms='+sw.elapsedMilliseconds.toString()+' cid='+cid); } catch (_) {}
    if (ok) {
      // 若删除的是当前激活，则选择最新一条或 default
      try {
        final active = await getActiveConversationCid();
        if (active == cid) {
          final rows = await db.listAiConversations(limit: 1, offset: 0);
          if (rows.isNotEmpty) {
            final nextCid = (rows.first['cid'] as String?) ?? 'default';
            await setActiveConversationCid(nextCid);
          } else {
            await setActiveConversationCid('default');
          }
        }
      } catch (_) {}
      try { _ctxChangedController.add('chat'); } catch (_) {}
      // 广播删除事件，供 UI 进行“立即清空并计时到首帧完成”
      try { _ctxChangedController.add('chat:deleted'); } catch (_) {}
    }
    return ok;
  }
 
  Future<List<AIMessage>> getChatHistory() async {
    final cid = await getActiveConversationCid();
    return getChatHistoryByCid(cid);
  }
 
  Future<List<AIMessage>> getChatHistoryByCid(String conversationCid) async {
    final db = ScreenshotDatabase.instance;
    // 仅取尾部 N 条，避免 UI 在大历史下卡顿
    final rows = await db.getAiMessagesTail(conversationCid, limit: _maxHistoryMessages);
    return rows
        .map((e) => AIMessage(
              role: (e['role'] as String?) ?? 'user',
              content: (e['content'] as String?) ?? '',
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                (e['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
              ),
              reasoningContent: (e['reasoning_content'] as String?),
              reasoningDuration: ((e['reasoning_duration_ms'] as int?) != null)
                  ? Duration(milliseconds: (e['reasoning_duration_ms'] as int))
                  : null,
            ))
        .toList();
  }
 
  Future<void> saveChatHistory(List<AIMessage> messages) async {
    await saveChatHistoryActive(messages);
  }
 
  Future<void> saveChatHistoryActive(List<AIMessage> messages) async {
    final cid = await getActiveConversationCid();
    await saveChatHistoryByCid(cid, messages);
  }
 
  Future<void> saveChatHistoryByCid(String conversationCid, List<AIMessage> messages) async {
    final db = ScreenshotDatabase.instance;
    final trimmed = messages.length > _maxHistoryMessages
        ? messages.sublist(messages.length - _maxHistoryMessages)
        : messages;
    await db.clearAiConversation(conversationCid);
    for (final m in trimmed) {
      await db.appendAiMessage(
        conversationCid,
        m.role,
        m.content,
        createdAt: m.createdAt.millisecondsSinceEpoch,
        reasoningContent: m.reasoningContent,
        reasoningDurationMs: m.reasoningDuration?.inMilliseconds,
      );
    }
    try { await db.touchAiConversation(conversationCid); } catch (_) {}
  }
 
  Future<void> clearChatHistory() async {
    final cid = await getActiveConversationCid();
    await clearChatHistoryByCid(cid);
  }

  // ========== Provider 上下文选择（供 UI 设置与显示） ==========

  Future<Map<String, dynamic>?> getAIContextRow(String context) async {
    return await ScreenshotDatabase.instance.getAIContext(context);
  }

  Future<void> setAIContextSelection({
    required String context,
    required int providerId,
    required String model,
  }) async {
    await ScreenshotDatabase.instance.setAIContext(context: context, providerId: providerId, model: model.trim());
    // 若为聊天上下文，则同时切换激活会话组到“负的 ProviderID”，以隔离历史
    if (context == 'chat') {
      await setActiveGroupId(-providerId.abs());
    }
    // 若为“动态(segments)”上下文：同步当前所选提供商的 API Key 至 ai_settings.api_key_segments，供原生侧读取
    if (context == 'segments') {
      try {
        final key = await AIProvidersService.instance.getApiKey(providerId);
        await ScreenshotDatabase.instance.setAiSetting('api_key_segments', (key == null || key.trim().isEmpty) ? null : key.trim());
      } catch (_) {}
    }
    // 广播上下文变更事件，驱动相关页面（如对话页）刷新
    try { _ctxChangedController.add(context); } catch (_) {}
  }

 Future<void> clearChatHistoryByGroup(int? groupId) async {
   final db = ScreenshotDatabase.instance;
   await db.clearAiConversation(_conversationIdForGroup(groupId));
 }

 Future<void> clearChatHistoryByCid(String conversationCid) async {
   final db = ScreenshotDatabase.instance;
   await db.clearAiConversation(conversationCid);
   try { await db.touchAiConversation(conversationCid); } catch (_) {}
 }
}

/// 简单的对话消息模型
class AIMessage {
  final String role; // system | user | assistant
  final String content;
  final DateTime createdAt;
  // 新增：深度思考内容与耗时（仅用于本地持久化与 UI 展示，不参与上行）
  final String? reasoningContent;
  final Duration? reasoningDuration;

  AIMessage({
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.reasoningContent,
    this.reasoningDuration,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };

  factory AIMessage.fromJson(Map<String, dynamic> json) {
    return AIMessage(
      role: (json['role'] as String?) ?? 'user',
      content: (json['content'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      // 注意：fromJson 仅用于与上游 API 的消息互转，不含 reasoning 字段
    );
  }
}

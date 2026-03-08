import 'dart:async';
import 'package:flutter/widgets.dart';
import 'screenshot_database.dart';
import 'locale_service.dart';
import 'ai_providers_service.dart';
import 'ai_context_budgets.dart';
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
  // Provider 元信息（用于日志与调试展示）。
  final int? providerId;
  final String? providerName;
  final String? providerType;
  final String baseUrl;
  final String? apiKey;
  final String model;
  final String chatPath; // 基于 Provider 的可配置路径，默认 /v1/chat/completions
  final bool useResponseApi; // OpenAI Responses API 兼容模式

  AIEndpoint({
    required this.groupId,
    this.providerId,
    this.providerName,
    this.providerType,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.chatPath = '/v1/chat/completions',
    this.useResponseApi = false,
  });
}

/// AI 设置与会话持久化服务
/// - 支持分组多站点，失败自动切换
/// - 会话历史按分组隔离（conversation_id = 'group:<id>' 或 'default'）
class AISettingsService {
  AISettingsService._internal();
  static final AISettingsService instance = AISettingsService._internal();

  // 上下文变更事件（如 chat 选择变更）广播
  final StreamController<String> _ctxChangedController =
      StreamController<String>.broadcast();
  Stream<String> get onContextChanged => _ctxChangedController.stream;

  /// Broadcast a context-change event.
  ///
  /// Note: keep payloads as small strings so listeners can cheaply filter.
  void notifyContextChanged(String context) {
    try {
      _ctxChangedController.add(context);
    } catch (_) {}
  }

  /// Broadcast that a specific conversation's persisted chat history changed.
  ///
  /// This is used for background tool-loop updates where we want the active
  /// chat UI (if it is currently showing the same conversation) to refresh,
  /// without forcing unrelated conversations to reload.
  void notifyChatHistoryChanged(String conversationCid) {
    final String cid = conversationCid.trim();
    if (cid.isEmpty) {
      notifyContextChanged('chat:history');
      return;
    }
    try {
      _ctxChangedController.add('chat:history:$cid');
    } catch (_) {}
  }

  // 存储键名（SQLite ai_settings 表）
  static const String _keyBaseUrl = 'base_url';
  static const String _keyApiKey = 'api_key';
  static const String _keyModel = 'model';
  static const String _keyStreamEnabled = 'stream_enabled';
  static const String _keyRenderImagesDuringStreaming =
      'render_images_during_streaming';
  // 是否显示 AIChat 页面的性能日志悬浮窗（UiPerfOverlay）。默认关闭。
  static const String _keyAiChatPerfOverlayEnabled =
      'ai_chat_perf_overlay_enabled';
  static const String _keyAtomicMemoryInjectionEnabled =
      'atomic_memory_injection_enabled';
  static const String _keyAtomicMemoryAutoExtractEnabled =
      'atomic_memory_auto_extract_enabled';
  static const String _keyAtomicMemoryPromptTokens =
      'atomic_memory_prompt_tokens';
  static const String _keyAtomicMemoryMaxItems = 'atomic_memory_max_items';
  static const String _keyUserMemoryInjectionEnabled =
      'user_memory_injection_enabled';
  static const String _keyUserMemoryPromptTokens = 'user_memory_prompt_tokens';
  static const String _keyUserMemoryMaxItems = 'user_memory_max_items';
  static const String _keyActiveGroupId = 'active_group_id'; // 当前激活的分组
  // 提示词键名（历史兼容 + 语言区分）
  static const String _keyPromptSegmentExtraZh = 'prompt_segment_extra_zh';
  static const String _keyPromptSegmentExtraEn = 'prompt_segment_extra_en';
  static const String _keyPromptMergeExtraZh = 'prompt_merge_extra_zh';
  static const String _keyPromptMergeExtraEn = 'prompt_merge_extra_en';
  static const String _keyPromptDailyExtraZh = 'prompt_daily_extra_zh';
  static const String _keyPromptDailyExtraEn = 'prompt_daily_extra_en';
  static const String _keyPromptMorningExtraZh = 'prompt_morning_extra_zh';
  static const String _keyPromptMorningExtraEn = 'prompt_morning_extra_en';
  // Dynamic (segments) - structured_json 解析失败时的自动重试次数（原生侧也会读取）
  static const String _keySegmentsJsonAutoRetryMax =
      'segments_json_auto_retry_max';

  // 默认值
  static const String _defaultBaseUrl = 'https://api.openai.com';
  static const String _defaultModel = 'gpt-4o-mini';

  // Prompt budgets should scale with the active model's prompt/context window.
  // Ratios are derived from the old fixed defaults (tuned around ~32k prompt cap).
  static const double _defaultAtomicMemoryPromptTokensRatio = 700.0 / 32000.0;
  static const double _defaultUserMemoryPromptTokensRatio = 1200.0 / 32000.0;

  // Hard safety caps (we still want scaling, but avoid absurd token budgets on
  // ultra-large context models).
  static const int _atomicMemoryPromptTokensAbsMax = 8000;
  static const int _userMemoryPromptTokensAbsMax = 12000;

  // Max budget as a percentage of prompt cap.
  static const double _atomicMemoryPromptTokensMaxRatio = 0.15;
  static const double _userMemoryPromptTokensMaxRatio = 0.10;

  static const int _atomicMemoryPromptTokensMin = 100;
  static const int _userMemoryPromptTokensMin = 200;

  static const int _defaultAtomicMemoryMaxItems = 24;
  static const int _defaultUserMemoryMaxItems = 24;
  static const int _defaultSegmentsJsonAutoRetryMax = 1;

  // 历史限制（仅保存最近 N 条，避免无限膨胀）
  static const int _maxHistoryMessages = 40;

  Future<int> _promptCapTokensForBudget() async {
    try {
      final String model = await getModel();
      final AIContextBudgets budgets =
          await AIContextBudgets.forModelWithOverrides(model);
      return budgets.promptCapTokens;
    } catch (_) {
      return AIContextBudgets.forModel(_defaultModel).promptCapTokens;
    }
  }

  static int _capByPct(
    int cap,
    double ratio, {
    required int min,
    required int absMax,
  }) {
    final int v = (cap * ratio).round();
    return v.clamp(min, absMax);
  }

  static int _maxAtomicMemoryTokensForCap(int cap) {
    return _capByPct(
      cap,
      _atomicMemoryPromptTokensMaxRatio,
      min: _atomicMemoryPromptTokensMin,
      absMax: _atomicMemoryPromptTokensAbsMax,
    );
  }

  static int _defaultAtomicMemoryTokensForCap(int cap) {
    final int suggested = (cap * _defaultAtomicMemoryPromptTokensRatio).round();
    return suggested.clamp(
      _atomicMemoryPromptTokensMin,
      _maxAtomicMemoryTokensForCap(cap),
    );
  }

  static int _clampAtomicMemoryTokens(int value, int cap) {
    return value.clamp(
      _atomicMemoryPromptTokensMin,
      _maxAtomicMemoryTokensForCap(cap),
    );
  }

  static int _maxUserMemoryTokensForCap(int cap) {
    return _capByPct(
      cap,
      _userMemoryPromptTokensMaxRatio,
      min: _userMemoryPromptTokensMin,
      absMax: _userMemoryPromptTokensAbsMax,
    );
  }

  static int _defaultUserMemoryTokensForCap(int cap) {
    final int suggested = (cap * _defaultUserMemoryPromptTokensRatio).round();
    return suggested.clamp(
      _userMemoryPromptTokensMin,
      _maxUserMemoryTokensForCap(cap),
    );
  }

  static int _clampUserMemoryTokens(int value, int cap) {
    return value.clamp(
      _userMemoryPromptTokensMin,
      _maxUserMemoryTokensForCap(cap),
    );
  }

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

  // AIChat 页面的性能日志悬浮窗开关（默认 false：避免默认刷屏）
  Future<bool> getAiChatPerfOverlayEnabled() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyAiChatPerfOverlayEnabled);
    if (v == null || v.isEmpty) return false;
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setAiChatPerfOverlayEnabled(bool enabled) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyAiChatPerfOverlayEnabled, enabled ? '1' : '0');
  }

  // ========== 原子记忆注入（SimpleMem-style） ==========

  Future<bool> getAtomicMemoryInjectionEnabled() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyAtomicMemoryInjectionEnabled);
    if (v == null || v.isEmpty) return true; // 默认开启（若无数据则不注入）
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setAtomicMemoryInjectionEnabled(bool enabled) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(
      _keyAtomicMemoryInjectionEnabled,
      enabled ? '1' : '0',
    );
  }

  /// Whether to auto-extract atomic memories after each turn (uses AI calls).
  /// Defaults to false to avoid unexpected cost.
  Future<bool> getAtomicMemoryAutoExtractEnabled() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyAtomicMemoryAutoExtractEnabled);
    if (v == null || v.isEmpty) return false;
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setAtomicMemoryAutoExtractEnabled(bool enabled) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(
      _keyAtomicMemoryAutoExtractEnabled,
      enabled ? '1' : '0',
    );
  }

  Future<int> getAtomicMemoryPromptTokens() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyAtomicMemoryPromptTokens);
    final int? parsed = int.tryParse((v ?? '').trim());
    final int cap = await _promptCapTokensForBudget();
    final int raw = parsed ?? _defaultAtomicMemoryTokensForCap(cap);
    return _clampAtomicMemoryTokens(raw, cap);
  }

  Future<void> setAtomicMemoryPromptTokens(int value) async {
    final db = ScreenshotDatabase.instance;
    final int cap = await _promptCapTokensForBudget();
    final int v = _clampAtomicMemoryTokens(value, cap);
    await db.setAiSetting(_keyAtomicMemoryPromptTokens, v.toString());
  }

  Future<int> getAtomicMemoryMaxItems() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyAtomicMemoryMaxItems);
    final int? parsed = int.tryParse((v ?? '').trim());
    final int raw = parsed ?? _defaultAtomicMemoryMaxItems;
    return raw.clamp(5, 80);
  }

  Future<void> setAtomicMemoryMaxItems(int value) async {
    final db = ScreenshotDatabase.instance;
    final int v = value.clamp(5, 80);
    await db.setAiSetting(_keyAtomicMemoryMaxItems, v.toString());
  }

  // ========== 全局用户记忆注入（跨会话 UserMemory） ==========

  Future<bool> getUserMemoryInjectionEnabled() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyUserMemoryInjectionEnabled);
    if (v == null || v.isEmpty) return true; // 默认开启（若无数据则不注入）
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setUserMemoryInjectionEnabled(bool enabled) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyUserMemoryInjectionEnabled, enabled ? '1' : '0');
  }

  Future<int> getUserMemoryPromptTokens() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyUserMemoryPromptTokens);
    final int? parsed = int.tryParse((v ?? '').trim());
    final int cap = await _promptCapTokensForBudget();
    final int raw = parsed ?? _defaultUserMemoryTokensForCap(cap);
    return _clampUserMemoryTokens(raw, cap);
  }

  Future<void> setUserMemoryPromptTokens(int value) async {
    final db = ScreenshotDatabase.instance;
    final int cap = await _promptCapTokensForBudget();
    final int v = _clampUserMemoryTokens(value, cap);
    await db.setAiSetting(_keyUserMemoryPromptTokens, v.toString());
  }

  Future<int> getUserMemoryMaxItems() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyUserMemoryMaxItems);
    final int? parsed = int.tryParse((v ?? '').trim());
    final int raw = parsed ?? _defaultUserMemoryMaxItems;
    return raw.clamp(5, 120);
  }

  Future<void> setUserMemoryMaxItems(int value) async {
    final db = ScreenshotDatabase.instance;
    final int v = value.clamp(5, 120);
    await db.setAiSetting(_keyUserMemoryMaxItems, v.toString());
  }

  // ========== 动态（segments）自动重试 ==========

  /// When native fails to parse structured_json for a segment result, it can
  /// auto-retry the call with a stricter "JSON-only" prompt.
  ///
  /// - 0 disables auto retry.
  /// - Default: 1.
  Future<int> getSegmentsJsonAutoRetryMax() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keySegmentsJsonAutoRetryMax);
    final int? parsed = int.tryParse((v ?? '').trim());
    final int raw = parsed ?? _defaultSegmentsJsonAutoRetryMax;
    return raw.clamp(0, 5);
  }

  Future<void> setSegmentsJsonAutoRetryMax(int value) async {
    final db = ScreenshotDatabase.instance;
    final int v = value.clamp(0, 5);
    await db.setAiSetting(_keySegmentsJsonAutoRetryMax, v.toString());
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
      sel ??=
          (await AIProvidersService.instance.getDefaultProvider()) ??
          providers.first;
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
        return await AIProvidersService.instance.getApiKey(
          ctx['provider_id'] as int,
        );
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
        sel = await AIProvidersService.instance.getProvider(
          ctx['provider_id'] as int,
        );
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
      sel ??=
          (await AIProvidersService.instance.getDefaultProvider()) ??
          providers.first;
      String model =
          (ctx != null && (ctx['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctx['model'] as String).trim()
          : (sel.extra['active_model'] as String? ?? sel.defaultModel)
                .toString()
                .trim();
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
      await ScreenshotDatabase.instance.setAIContext(
        context: 'chat',
        providerId: providerId,
        model: model.trim(),
      );
      try {
        _ctxChangedController.add('chat');
      } catch (_) {}
    } catch (_) {}
  }

  // ========== 提示词管理 ==========
  String _currentLang() {
    // 优先应用语言；为空时回退系统语言；仅识别 zh / en
    final loc = LocaleService.instance.locale;
    final code =
        (loc?.languageCode ??
                WidgetsBinding.instance.platformDispatcher.locale.languageCode)
            .toLowerCase();
    return code.startsWith('zh') ? 'zh' : 'en';
  }

  static const int _maxPromptAddonLength = 2000;

  Future<String?> getPromptSegment() async {
    final lang = _currentLang();
    return _getPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptSegmentExtraZh
          : _keyPromptSegmentExtraEn,
    );
  }

  Future<void> setPromptSegment(String? value) async {
    final lang = _currentLang();
    await _setPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptSegmentExtraZh
          : _keyPromptSegmentExtraEn,
      value: value,
    );
  }

  Future<String?> getPromptMerge() async {
    final lang = _currentLang();
    return _getPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptMergeExtraZh
          : _keyPromptMergeExtraEn,
    );
  }

  Future<void> setPromptMerge(String? value) async {
    final lang = _currentLang();
    await _setPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptMergeExtraZh
          : _keyPromptMergeExtraEn,
      value: value,
    );
  }

  // ========== 每日总结提示词 ==========
  Future<String?> getPromptDaily() async {
    final lang = _currentLang();
    return _getPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptDailyExtraZh
          : _keyPromptDailyExtraEn,
    );
  }

  Future<void> setPromptDaily(String? value) async {
    final lang = _currentLang();
    await _setPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptDailyExtraZh
          : _keyPromptDailyExtraEn,
      value: value,
    );
  }

  // ========== 晨间行动提示词 ==========
  Future<String?> getPromptMorning() async {
    final lang = _currentLang();
    return _getPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptMorningExtraZh
          : _keyPromptMorningExtraEn,
    );
  }

  Future<void> setPromptMorning(String? value) async {
    final lang = _currentLang();
    await _setPromptAddon(
      primaryKey: lang == 'zh'
          ? _keyPromptMorningExtraZh
          : _keyPromptMorningExtraEn,
      value: value,
    );
  }

  // ========== 端点候选（用于失败自动切换） ==========

  /// 基于 Provider 的端点候选（仅提供商+上下文）
  /// - context: 'chat' | 其他（如 'segments'）
  /// - 不再回退到 site_groups/ai_settings
  Future<List<AIEndpoint>> getEndpointCandidates({
    String context = 'chat',
  }) async {
    final providers = await AIProvidersService.instance.listProviders();
    if (providers.isEmpty) {
      // 对于 segments 上下文，尝试直接从原生配置复用（确保与动态一致）
      if (context == 'segments') {
        try {
          const MethodChannel ch = MethodChannel(
            'com.fqyw.screen_memo/accessibility',
          );
          final Map<dynamic, dynamic>? segCfg = await ch.invokeMethod(
            'getSegmentsAIConfig',
          );
          if (segCfg != null) {
            final String baseUrl = ((segCfg['baseUrl'] as String?) ?? '')
                .trim();
            final String model = ((segCfg['model'] as String?) ?? '').trim();
            final String? apiKey = ((segCfg['apiKey'] as String?) ?? '').trim();
            if (model.isNotEmpty && (apiKey != null && apiKey.isNotEmpty)) {
              return <AIEndpoint>[
                AIEndpoint(
                  groupId: -1,
                  providerId: null,
                  providerName: 'segments(native)',
                  providerType: 'native',
                  baseUrl: baseUrl.isEmpty ? _defaultBaseUrl : baseUrl,
                  apiKey: apiKey,
                  model: model,
                  chatPath: '/v1/chat/completions',
                  useResponseApi: false,
                ),
              ];
            }
          }
        } catch (_) {}
      }
      return <AIEndpoint>[];
    }

    // 读取上下文选择：优先 ai_contexts(context)，否则默认提供商，否则列表首项
    final db = ScreenshotDatabase.instance;
    Map<String, dynamic>? ctx = await db.getAIContext(context);
    AIProvider? pSelected;
    final int? ctxProviderId = (ctx != null && ctx['provider_id'] is int)
        ? (ctx['provider_id'] as int)
        : null;
    if (ctxProviderId != null) {
      pSelected = providers.firstWhere(
        (p) => (p.id ?? -1) == ctxProviderId,
        orElse: () => providers.first,
      );
    }
    pSelected ??=
        (await AIProvidersService.instance.getDefaultProvider()) ??
        providers.first;

    // 解析模型：上下文显式 -> extra.active_model -> default_model -> models.first -> 默认
    final String ctxModel = (ctx == null)
        ? ''
        : ((ctx['model'] as String?)?.trim() ?? '');
    String model = ctxModel.isNotEmpty
        ? ctxModel
        : (pSelected.extra['active_model'] as String? ?? pSelected.defaultModel)
              .toString()
              .trim();
    if (model.isEmpty) {
      model = pSelected.models.isNotEmpty
          ? pSelected.models.first
          : _defaultModel;
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
        const MethodChannel ch = MethodChannel(
          'com.fqyw.screen_memo/accessibility',
        );
        final Map<dynamic, dynamic>? segCfg = await ch.invokeMethod(
          'getSegmentsAIConfig',
        );
        if (segCfg != null) {
          final String baseFromNative = ((segCfg['baseUrl'] as String?) ?? '')
              .trim();
          final String modelFromNative = ((segCfg['model'] as String?) ?? '')
              .trim();
          final String? keyFromNative = ((segCfg['apiKey'] as String?) ?? '')
              .trim();
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
          final k = await ScreenshotDatabase.instance.getAiSetting(
            'api_key_segments',
          );
          if (k != null && k.trim().isNotEmpty) {
            apiKey = k.trim();
          }
        } catch (_) {}
      }
    }

    // 规范化 base 与 chatPath（若上方从原生覆盖 model/base，应在此处理）
    String baseUrl =
        (pSelected.baseUrl == null || pSelected.baseUrl!.trim().isEmpty)
        ? _defaultBaseUrl
        : pSelected.baseUrl!.trim();
    if (baseUrlOverride.isNotEmpty) baseUrl = baseUrlOverride;
    final String chatPath =
        (pSelected.chatPath == null || pSelected.chatPath!.trim().isEmpty)
        ? '/v1/chat/completions'
        : pSelected.chatPath!.trim();

    // 使用负的 ProviderID 作为 groupId，隔离会话历史
    final int groupId = -1 * (pSelected.id ?? 0).abs();

    return <AIEndpoint>[
      AIEndpoint(
        groupId: groupId,
        providerId: pSelected.id,
        providerName: pSelected.name,
        providerType: pSelected.type,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        chatPath: chatPath,
        useResponseApi: pSelected.useResponseApi,
      ),
    ];
  }

  // ========== 会话（Conversation）管理与历史 ==========

  String _conversationIdForGroup(int? groupId) =>
      groupId == null ? 'default' : 'group:$groupId';

  // 读取/初始化当前激活会话CID（ai_settings.chat_active_cid）
  Future<String> getActiveConversationCid() async {
    try {
      final db = ScreenshotDatabase.instance;
      String? cid = await db.getAiSetting('chat_active_cid');
      if (cid != null && cid.trim().isNotEmpty) return cid.trim();
      // 初始化：确保 default 存在并设为激活
      try {
        // 不使用硬编码标题，留空以便前端按本地化占位显示
        final created = await db.createAiConversation(
          title: '',
          cid: 'default',
        );
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
      try {
        await db.touchAiConversation(cid.trim());
      } catch (_) {}
      try {
        _ctxChangedController.add('chat');
      } catch (_) {}
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listAiConversations({
    int? limit,
    int? offset,
  }) {
    return ScreenshotDatabase.instance.listAiConversations(
      limit: limit,
      offset: offset,
    );
  }

  Future<String> createConversation({String? title}) async {
    final db = ScreenshotDatabase.instance;
    // 留空标题，UI 层使用本地化的无标题占位
    final cid = await db.createAiConversation(
      title: (title == null || title.trim().isEmpty) ? '' : title.trim(),
    );
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
    try {
      await FlutterLogger.nativeInfo(
        'UI',
        '删除对话完成 耗时(毫秒)=' + sw.elapsedMilliseconds.toString() + ' cid=' + cid,
      );
    } catch (_) {}
    if (ok) {
      // 若删除的是当前激活，则选择最新一条或 default
      bool deletedWasActive = false;
      try {
        final active = await getActiveConversationCid();
        if (active == cid) {
          deletedWasActive = true;
          final rows = await db.listAiConversations(limit: 1, offset: 0);
          if (rows.isNotEmpty) {
            final nextCid = (rows.first['cid'] as String?) ?? 'default';
            await setActiveConversationCid(nextCid);
          } else {
            await setActiveConversationCid('default');
          }
        }
      } catch (_) {}
      // - 非激活会话删除：仅通知刷新列表（chat）
      // - 激活会话删除：setActiveConversationCid() 已广播 chat，这里仅额外广播 chat:deleted
      if (!deletedWasActive) {
        try {
          _ctxChangedController.add('chat');
        } catch (_) {}
      } else {
        // 广播删除事件，供 UI 进行“立即清空并计时到首帧完成”
        try {
          _ctxChangedController.add('chat:deleted');
        } catch (_) {}
      }
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
    final rows = await db.getAiMessagesTail(
      conversationCid,
      limit: _maxHistoryMessages,
    );

    String sanitizeEphemeralChatStatusContent({
      required String role,
      required String content,
    }) {
      // Older builds persisted internal "phase 1/4 ... 3/4 ..." placeholders
      // into ai_messages. When a conversation is restored (e.g. after switching
      // pages/conversations), those placeholders can show up as the assistant
      // answer. They are UI-only progress text and should not participate in
      // rendering nor prompt history.
      if (role.trim() != 'assistant') return content;
      final String t = content.trim();
      if (t.isEmpty) return content;
      final bool hasPhaseMarker = RegExp(
        r'(^|\n)\s*(?:[123]/4|Phase [123]/4|阶段 [123]/4)',
      ).hasMatch(t);
      if (!hasPhaseMarker) return content;

      final String lower = t.toLowerCase();
      final bool looksLikeStatus =
          t.contains('分析用户意图') ||
          t.contains('查找上下文') ||
          t.contains('生成回答') ||
          t.contains('无需上下文') ||
          t.contains('意图:') ||
          lower.contains('intent:') ||
          lower.contains('building context') ||
          lower.contains('generating answer') ||
          lower.contains('no context needed');
      if (!looksLikeStatus) return content;

      return '';
    }

    return rows.map((e) {
      final String role = (e['role'] as String?) ?? 'user';
      final String contentRaw = (e['content'] as String?) ?? '';
      final String content = sanitizeEphemeralChatStatusContent(
        role: role,
        content: contentRaw,
      );
      return AIMessage(
        role: role,
        content: content,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (e['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        ),
        reasoningContent: (e['reasoning_content'] as String?),
        reasoningDuration: ((e['reasoning_duration_ms'] as int?) != null)
            ? Duration(milliseconds: (e['reasoning_duration_ms'] as int))
            : null,
        uiThinkingJson: (e['ui_thinking_json'] as String?),
      );
    }).toList();
  }

  Future<void> saveChatHistory(List<AIMessage> messages) async {
    await saveChatHistoryActive(messages);
  }

  Future<void> saveChatHistoryActive(List<AIMessage> messages) async {
    final cid = await getActiveConversationCid();
    await saveChatHistoryByCid(cid, messages);
  }

  Future<void> saveChatHistoryByCid(
    String conversationCid,
    List<AIMessage> messages,
  ) async {
    final db = ScreenshotDatabase.instance;
    final trimmed = messages.length > _maxHistoryMessages
        ? messages.sublist(messages.length - _maxHistoryMessages)
        : messages;
    try {
      final storage = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await storage.transaction((txn) async {
        // 确保会话条目存在（若无则占位创建）
        try {
          await txn.execute(
            'INSERT OR IGNORE INTO ai_conversations(cid, title, created_at, updated_at) VALUES(?, ?, ?, ?)',
            [conversationCid, null, now, now],
          );
        } catch (_) {}

        await txn.delete(
          'ai_messages',
          where: 'conversation_id = ?',
          whereArgs: [conversationCid],
        );

        final batch = txn.batch();
        for (final m in trimmed) {
          batch.insert('ai_messages', {
            'conversation_id': conversationCid,
            'role': m.role,
            'content': m.content,
            if (m.reasoningContent != null)
              'reasoning_content': m.reasoningContent,
            if (m.reasoningDuration != null)
              'reasoning_duration_ms': m.reasoningDuration!.inMilliseconds,
            if (m.uiThinkingJson != null) 'ui_thinking_json': m.uiThinkingJson,
            'created_at': m.createdAt.millisecondsSinceEpoch,
          });
        }
        await batch.commit(noResult: true);

        // 更新会话的最近更新时间
        try {
          await txn.update(
            'ai_conversations',
            {'updated_at': now},
            where: 'cid = ?',
            whereArgs: [conversationCid],
          );
        } catch (_) {}
      });
    } catch (_) {}
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
    await ScreenshotDatabase.instance.setAIContext(
      context: context,
      providerId: providerId,
      model: model.trim(),
    );
    // 若为聊天上下文，则同时切换激活会话组到“负的 ProviderID”，以隔离历史
    if (context == 'chat') {
      await setActiveGroupId(-providerId.abs());
    }
    // 若为“动态(segments)”上下文：同步当前所选提供商的 API Key 至 ai_settings.api_key_segments，供原生侧读取
    if (context == 'segments') {
      try {
        final key = await AIProvidersService.instance.getApiKey(providerId);
        await ScreenshotDatabase.instance.setAiSetting(
          'api_key_segments',
          (key == null || key.trim().isEmpty) ? null : key.trim(),
        );
      } catch (_) {}
    }
    // 广播上下文变更事件，驱动相关页面（如对话页）刷新
    try {
      _ctxChangedController.add(context);
    } catch (_) {}
  }

  Future<void> clearChatHistoryByGroup(int? groupId) async {
    final db = ScreenshotDatabase.instance;
    await db.clearAiConversation(_conversationIdForGroup(groupId));
  }

  Future<void> clearChatHistoryByCid(String conversationCid) async {
    final db = ScreenshotDatabase.instance;
    await db.clearAiConversation(conversationCid);
    try {
      await db.touchAiConversation(conversationCid);
    } catch (_) {}
    try {
      _ctxChangedController.add('chat:cleared');
    } catch (_) {}
  }

  Future<String?> _getPromptAddon({required String primaryKey}) async {
    final db = ScreenshotDatabase.instance;
    String? raw = await db.getAiSetting(primaryKey);
    final sanitized = _sanitizePromptAddon(raw);
    return sanitized;
  }

  Future<void> _setPromptAddon({
    required String primaryKey,
    required String? value,
  }) async {
    final db = ScreenshotDatabase.instance;
    final sanitized = _sanitizePromptAddon(value);
    await db.setAiSetting(primaryKey, sanitized);
  }

  String? _sanitizePromptAddon(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > _maxPromptAddonLength) {
      return normalized.substring(0, _maxPromptAddonLength).trim();
    }
    return normalized;
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
  // UI-only: persist thinking timeline blocks/events for stable restore.
  final String? uiThinkingJson;
  // —— 以下字段仅用于上行请求（不参与本地持久化）——
  // 多模态/结构化 content：如 [{type:'text',text:'..'},{type:'image_url',image_url:{url:'data:...'}}]
  final Object? apiContent;
  // 工具调用：role=assistant 时附带 tool_calls；role=tool 时附带 tool_call_id
  final List<Map<String, dynamic>>? toolCalls;
  final String? toolCallId;

  AIMessage({
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.reasoningContent,
    this.reasoningDuration,
    this.uiThinkingJson,
    this.apiContent,
    this.toolCalls,
    this.toolCallId,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{'role': role};

    Object? effectiveContent = apiContent ?? content;
    if (role == 'assistant' &&
        apiContent == null &&
        (toolCalls != null && toolCalls!.isNotEmpty) &&
        content.trim().isEmpty) {
      effectiveContent = null;
    }
    m['content'] = effectiveContent;

    if (toolCalls != null && toolCalls!.isNotEmpty) m['tool_calls'] = toolCalls;
    if (toolCallId != null && toolCallId!.trim().isNotEmpty) {
      m['tool_call_id'] = toolCallId!.trim();
    }
    return m;
  }

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

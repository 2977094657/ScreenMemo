import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/core/localization/locale_service.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai/application/ai_context_budgets.dart';
import 'package:flutter/services.dart'; // Added for MethodChannel
import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/data/settings/user_settings_service.dart';

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
  final int? providerKeyId;
  final String? providerKeyName;
  final int? providerKeyPriority;
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
    this.providerKeyId,
    this.providerKeyName,
    this.providerKeyPriority,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.chatPath = '/v1/chat/completions',
    this.useResponseApi = false,
  });
}

/// RikkaHub 风格的推理/思考等级。
///
/// `auto` 保持默认，由模型/提供商自行决定；其他等级会尽量映射到各家接口的
/// reasoning/thinking 参数。不是所有兼容接口都支持这些字段，网关会在失败时回退。
enum AIReasoningLevel {
  off('off', 0, 'none'),
  auto('auto', -1, 'auto'),
  low('low', 1000, 'low'),
  medium('medium', 2000, 'medium'),
  high('high', 8000, 'high'),
  xhigh('xhigh', 16000, 'xhigh');

  const AIReasoningLevel(this.storageValue, this.budgetTokens, this.effort);

  final String storageValue;
  final int budgetTokens;
  final String effort;

  bool get isEnabled => this != AIReasoningLevel.off;

  static AIReasoningLevel fromStorage(String? value) {
    final String raw = (value ?? '').trim().toLowerCase();
    for (final AIReasoningLevel level in AIReasoningLevel.values) {
      if (level.storageValue == raw || level.name == raw) return level;
    }
    return AIReasoningLevel.auto;
  }
}

/// AI 设置与会话持久化服务
/// - 支持分组多站点，失败自动切换
/// - 会话历史按分组隔离（conversation_id = `group:<id>` 或 `default`）
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
  static const String _keyChatReasoningLevel = 'chat_reasoning_level';
  static const String _keyRenderImagesDuringStreaming =
      'render_images_during_streaming';
  // 是否显示 AIChat 页面的性能日志悬浮窗（UiPerfOverlay）。默认关闭。
  static const String _keyAiChatPerfOverlayEnabled =
      'ai_chat_perf_overlay_enabled';
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
  static const int _defaultSegmentsJsonAutoRetryMax = 1;
  static const int _defaultRawResponseCleanupDays = 30;
  static const int _rawResponseCleanupThrottleMs = 12 * 60 * 60 * 1000;
  // 历史限制（仅保存最近 N 条，避免无限膨胀）
  static const int _maxHistoryMessages = 40;
  bool _rawResponseCleanupRunning = false;

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

  Future<AIReasoningLevel> getChatReasoningLevel() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyChatReasoningLevel);
    return AIReasoningLevel.fromStorage(v);
  }

  Future<void> setChatReasoningLevel(AIReasoningLevel level) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyChatReasoningLevel, level.storageValue);
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

  Future<bool> getRawResponseCleanupEnabled() async {
    return UserSettingsService.instance.getBool(
      UserSettingKeys.aiRawResponseCleanupEnabled,
      defaultValue: true,
    );
  }

  Future<int> getRawResponseCleanupDays() async {
    final int raw = await UserSettingsService.instance.getInt(
      UserSettingKeys.aiRawResponseCleanupDays,
      defaultValue: _defaultRawResponseCleanupDays,
    );
    return raw < 1 ? 1 : raw;
  }

  Future<void> setRawResponseCleanupEnabled(bool value) async {
    await UserSettingsService.instance.setBool(
      UserSettingKeys.aiRawResponseCleanupEnabled,
      value,
    );
  }

  Future<void> setRawResponseCleanupDays(int value) async {
    await UserSettingsService.instance.setInt(
      UserSettingKeys.aiRawResponseCleanupDays,
      value < 1 ? 1 : value,
    );
  }

  Future<int> cleanupExpiredRawResponsesIfNeeded({bool force = false}) async {
    if (_rawResponseCleanupRunning) return 0;
    try {
      final bool enabled = await getRawResponseCleanupEnabled();
      if (!enabled) return 0;
      final int days = await getRawResponseCleanupDays();
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int lastRunMs = await UserSettingsService.instance.getInt(
        UserSettingKeys.aiRawResponseCleanupLastTs,
        defaultValue: 0,
      );
      if (!force &&
          lastRunMs > 0 &&
          (now - lastRunMs) < _rawResponseCleanupThrottleMs) {
        return 0;
      }
      _rawResponseCleanupRunning = true;
      final int cutoffMs = now - days * 24 * 60 * 60 * 1000;
      final int cleaned = await ScreenshotDatabase.instance
          .cleanupExpiredRawResponses(
            cutoffMs: cutoffMs,
            includeMorningInsights: true,
          );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.aiRawResponseCleanupLastTs,
        now,
      );
      try {
        await FlutterLogger.nativeInfo(
          'AI_SETTINGS',
          'raw_response 自动清理执行完成：days=$days cleaned=$cleaned force=$force',
        );
      } catch (_) {}
      return cleaned;
    } catch (e) {
      try {
        await FlutterLogger.nativeWarn('AI_SETTINGS', 'raw_response 自动清理失败：$e');
      } catch (_) {}
      return 0;
    } finally {
      _rawResponseCleanupRunning = false;
    }
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

    final db = ScreenshotDatabase.instance;
    final Map<String, dynamic>? ctx = await db.getAIContext(context);
    if (context == 'image_generation' && ctx == null) {
      return <AIEndpoint>[];
    }
    AIProvider? pSelected;
    final int? ctxProviderId = (ctx != null && ctx['provider_id'] is int)
        ? (ctx['provider_id'] as int)
        : null;
    if (ctxProviderId != null) {
      for (final AIProvider provider in providers) {
        if ((provider.id ?? -1) == ctxProviderId) {
          pSelected = provider;
          break;
        }
      }
    }
    if (context == 'image_generation') {
      if (ctxProviderId == null || pSelected == null) {
        return <AIEndpoint>[];
      }
      final String imageModel = ((ctx?['model'] as String?) ?? '').trim();
      if (imageModel.isEmpty) {
        return <AIEndpoint>[];
      }
    }
    pSelected ??=
        (await AIProvidersService.instance.getDefaultProvider()) ??
        providers.first;

    final String ctxModel = (ctx == null)
        ? ''
        : ((ctx['model'] as String?)?.trim() ?? '');
    String model = ctxModel.isNotEmpty
        ? ctxModel
        : (pSelected.extra['active_model'] as String? ?? pSelected.defaultModel)
              .toString()
              .trim();
    if (context != 'image_generation' &&
        (model.isEmpty ||
            (pSelected.models.isNotEmpty &&
                !pSelected.models.any(
                  (m) => m.trim().toLowerCase() == model.toLowerCase(),
                )))) {
      final String fb =
          (pSelected.extra['active_model'] as String? ?? pSelected.defaultModel)
              .toString()
              .trim();
      model = fb.isNotEmpty
          ? fb
          : (pSelected.models.isNotEmpty
                ? pSelected.models.first
                : _defaultModel);
    }

    String baseUrl =
        (pSelected.baseUrl == null || pSelected.baseUrl!.trim().isEmpty)
        ? _defaultBaseUrl
        : pSelected.baseUrl!.trim();
    final String chatPath =
        (pSelected.chatPath == null || pSelected.chatPath!.trim().isEmpty)
        ? '/v1/chat/completions'
        : pSelected.chatPath!.trim();
    final int groupId = -1 * (pSelected.id ?? 0).abs();
    final int selectedProviderId = pSelected.id ?? 0;

    if (context == 'segments') {
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
          if (modelFromNative.isNotEmpty) model = modelFromNative;
          if (baseFromNative.isNotEmpty) baseUrl = baseFromNative;
        }
      } catch (_) {}
    }

    final List<AIProviderKey> keys = await AIProvidersService.instance
        .listProviderKeys(pSelected.id!, includeDisabled: false);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<AIProviderKey> usableKeys = keys.where((k) {
      if (k.apiKey.trim().isEmpty) return false;
      if (k.isAuthFailed) return false;
      if (k.isCoolingDown(now)) return false;
      return k.supportsModel(model);
    }).toList();

    if (usableKeys.isEmpty) {
      final String? legacyKey = await AIProvidersService.instance.getApiKey(
        pSelected.id!,
      );
      if (legacyKey != null && legacyKey.trim().isNotEmpty) {
        return <AIEndpoint>[
          AIEndpoint(
            groupId: groupId,
            providerId: pSelected.id,
            providerName: pSelected.name,
            providerType: pSelected.type,
            baseUrl: baseUrl,
            apiKey: legacyKey,
            model: model,
            chatPath: chatPath,
            useResponseApi: pSelected.useResponseApi,
          ),
        ];
      }
      return <AIEndpoint>[];
    }

    int fixedOrder(AIProviderKey a, AIProviderKey b) {
      final int priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      final int order = a.orderIndex.compareTo(b.orderIndex);
      if (order != 0) return order;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    }

    int dynamicDefaultOrder(AIProviderKey a, AIProviderKey b) {
      // 默认优先级代表“交给系统分配”：先避免连续失败，再选更久未尝试的 Key。
      final int failures = a.failureCount.compareTo(b.failureCount);
      if (failures != 0) return failures;

      final int aLastUse = <int>[
        a.lastSuccessAt ?? 0,
        a.lastFailedAt ?? 0,
      ].reduce((value, element) => value > element ? value : element);
      final int bLastUse = <int>[
        b.lastSuccessAt ?? 0,
        b.lastFailedAt ?? 0,
      ].reduce((value, element) => value > element ? value : element);
      final int lastUse = aLastUse.compareTo(bLastUse);
      if (lastUse != 0) return lastUse;

      final double aRate =
          (a.successCount + 1) /
          (a.successCount + a.failureTotalCount + 2).clamp(1, 1 << 30);
      final double bRate =
          (b.successCount + 1) /
          (b.successCount + b.failureTotalCount + 2).clamp(1, 1 << 30);
      final int rate = bRate.compareTo(aRate);
      if (rate != 0) return rate;

      return fixedOrder(a, b);
    }

    Future<List<AIProviderKey>> rotateFixedPriorityGroups(
      List<AIProviderKey> keys,
    ) async {
      if (keys.isEmpty) return <AIProviderKey>[];
      keys.sort(fixedOrder);
      final List<AIProviderKey> out = <AIProviderKey>[];
      int i = 0;
      while (i < keys.length) {
        final int priority = keys[i].priority;
        final group = <AIProviderKey>[];
        while (i < keys.length && keys[i].priority == priority) {
          group.add(keys[i]);
          i++;
        }
        final String cursorKey =
            'ai_key_fixed_${selectedProviderId}_${model.toLowerCase()}_$priority';
        final int cursor =
            int.tryParse((await db.getAiSetting(cursorKey)) ?? '') ?? 0;
        final int start = cursor % group.length;
        out.addAll(<AIProviderKey>[...group.skip(start), ...group.take(start)]);
        try {
          await db.setAiSetting(
            cursorKey,
            ((cursor + 1) % group.length).toString(),
          );
        } catch (_) {}
      }
      return out;
    }

    Future<List<AIProviderKey>> rotateDynamicDefaultKeys(
      List<AIProviderKey> keys,
    ) async {
      if (keys.isEmpty) return <AIProviderKey>[];
      keys.sort(dynamicDefaultOrder);
      final String cursorKey =
          'ai_key_dynamic_${selectedProviderId}_${model.toLowerCase()}';
      final int cursor =
          int.tryParse((await db.getAiSetting(cursorKey)) ?? '') ?? 0;
      final int start = cursor % keys.length;
      final List<AIProviderKey> out = <AIProviderKey>[
        ...keys.skip(start),
        ...keys.take(start),
      ];
      try {
        await db.setAiSetting(
          cursorKey,
          ((cursor + 1) % keys.length).toString(),
        );
      } catch (_) {}
      return out;
    }

    final List<AIProviderKey> fixedHighPriority = <AIProviderKey>[];
    final List<AIProviderKey> dynamicDefaultPriority = <AIProviderKey>[];
    final List<AIProviderKey> fixedLowPriority = <AIProviderKey>[];
    for (final key in usableKeys) {
      if (key.usesDefaultPriority) {
        dynamicDefaultPriority.add(key);
      } else if (key.priority < AIProviderKey.defaultPriority) {
        fixedHighPriority.add(key);
      } else {
        fixedLowPriority.add(key);
      }
    }

    final List<AIProviderKey> ordered = <AIProviderKey>[
      ...await rotateFixedPriorityGroups(fixedHighPriority),
      ...await rotateDynamicDefaultKeys(dynamicDefaultPriority),
      ...await rotateFixedPriorityGroups(fixedLowPriority),
    ];

    final endpoints = <AIEndpoint>[];
    for (final key in ordered) {
      for (int attempt = 0; attempt < 3; attempt++) {
        endpoints.add(
          AIEndpoint(
            groupId: groupId,
            providerId: pSelected.id,
            providerName: pSelected.name,
            providerType: pSelected.type,
            providerKeyId: key.id,
            providerKeyName: key.name,
            providerKeyPriority: key.priority,
            baseUrl: baseUrl,
            apiKey: key.apiKey,
            model: model,
            chatPath: chatPath,
            useResponseApi: pSelected.useResponseApi,
          ),
        );
      }
    }
    return endpoints;
  }

  // ========== 多会话 Conversation 管理 ==========

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
        usagePromptTokens: e['usage_prompt_tokens'] as int?,
        usageCompletionTokens: e['usage_completion_tokens'] as int?,
        usageTotalTokens: e['usage_total_tokens'] as int?,
        usageCacheHitTokens: e['usage_cache_hit_tokens'] as int?,
        usageCacheMissTokens: e['usage_cache_miss_tokens'] as int?,
        responseDuration: ((e['response_duration_ms'] as int?) != null)
            ? Duration(milliseconds: (e['response_duration_ms'] as int))
            : null,
        webSearchCalls: AIMessage.decodeWebSearchCallsJson(
          e['web_search_calls_json'] as String?,
        ),
        citations: AIMessage.decodeCitationsJson(
          e['citations_json'] as String?,
        ),
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
      try {
        await db.ensureAiChatSchemaForRuntime();
      } catch (_) {}
      int assistantWithUsage = 0;
      AIMessage? lastAssistant;
      for (final AIMessage m in trimmed) {
        if (m.role != 'assistant') continue;
        lastAssistant = m;
        if (m.usagePromptTokens != null ||
            m.usageCompletionTokens != null ||
            m.usageTotalTokens != null ||
            m.usageCacheHitTokens != null ||
            m.usageCacheMissTokens != null) {
          assistantWithUsage += 1;
        }
      }
      unawaited(
        FlutterLogger.nativeDebug(
          'AIUsageTrace',
          [
            'DB_SAVE_HISTORY',
            'cid=$conversationCid messages=${trimmed.length} assistantWithUsage=$assistantWithUsage',
            'lastPrompt=${lastAssistant?.usagePromptTokens ?? '-'} lastCompletion=${lastAssistant?.usageCompletionTokens ?? '-'} lastTotal=${lastAssistant?.usageTotalTokens ?? '-'} lastCacheHit=${lastAssistant?.usageCacheHitTokens ?? '-'} lastCacheMiss=${lastAssistant?.usageCacheMissTokens ?? '-'} responseMs=${lastAssistant?.responseDuration?.inMilliseconds ?? '-'}',
          ].join('\n'),
        ).catchError((_) {}),
      );
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
          final String? webSearchCallsJson = AIMessage.encodeWebSearchCallsJson(
            m.webSearchCalls,
          );
          final String? citationsJson = AIMessage.encodeCitationsJson(
            m.citations,
          );
          batch.insert('ai_messages', {
            'conversation_id': conversationCid,
            'role': m.role,
            'content': m.content,
            if (m.reasoningContent != null)
              'reasoning_content': m.reasoningContent,
            if (m.reasoningDuration != null)
              'reasoning_duration_ms': m.reasoningDuration!.inMilliseconds,
            if (m.uiThinkingJson != null) 'ui_thinking_json': m.uiThinkingJson,
            if (m.usagePromptTokens != null)
              'usage_prompt_tokens': m.usagePromptTokens,
            if (m.usageCompletionTokens != null)
              'usage_completion_tokens': m.usageCompletionTokens,
            if (m.usageTotalTokens != null)
              'usage_total_tokens': m.usageTotalTokens,
            if (m.usageCacheHitTokens != null)
              'usage_cache_hit_tokens': m.usageCacheHitTokens,
            if (m.usageCacheMissTokens != null)
              'usage_cache_miss_tokens': m.usageCacheMissTokens,
            if (m.responseDuration != null)
              'response_duration_ms': m.responseDuration!.inMilliseconds,
            if (webSearchCallsJson != null)
              'web_search_calls_json': webSearchCallsJson,
            if (citationsJson != null) 'citations_json': citationsJson,
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

  Future<void> truncateConversationAfterCreatedAt(
    String conversationCid,
    int cutoffCreatedAtMs, {
    bool notify = true,
  }) async {
    final String cid = conversationCid.trim();
    if (cid.isEmpty || cutoffCreatedAtMs <= 0) return;
    await ScreenshotDatabase.instance.truncateAiConversationAfterCreatedAt(
      cid,
      cutoffCreatedAtMs,
    );
    if (!notify) return;
    try {
      _ctxChangedController.add('chat:history');
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

/// OpenAI Responses 内置搜索调用元数据，仅用于本地渲染和持久化。
class AIWebSearchSource {
  const AIWebSearchSource({required this.url, this.title});

  final String url;
  final String? title;

  bool get isEmpty => url.trim().isEmpty && (title ?? '').trim().isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (url.trim().isNotEmpty) 'url': url.trim(),
    if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
  };

  factory AIWebSearchSource.fromJson(Map<String, dynamic> json) {
    final String url = (json['url'] ?? json['uri'] ?? json['link'] ?? '')
        .toString()
        .trim();
    final String title = (json['title'] ?? json['name'] ?? '')
        .toString()
        .trim();
    return AIWebSearchSource(url: url, title: title.isEmpty ? null : title);
  }
}

class AIWebSearchCall {
  const AIWebSearchCall({
    this.id,
    this.status,
    this.actionType,
    this.query,
    this.queries = const <String>[],
    this.url,
    this.pattern,
    this.sources = const <AIWebSearchSource>[],
    this.startedAtMs,
    this.completedAtMs,
    this.durationMs,
  });

  final String? id;
  final String? status;
  final String? actionType;
  final String? query;
  final List<String> queries;
  final String? url;
  final String? pattern;
  final List<AIWebSearchSource> sources;
  final int? startedAtMs;
  final int? completedAtMs;
  final int? durationMs;

  bool get isEmpty =>
      (id ?? '').trim().isEmpty &&
      (status ?? '').trim().isEmpty &&
      (actionType ?? '').trim().isEmpty &&
      (query ?? '').trim().isEmpty &&
      queries.where((String e) => e.trim().isNotEmpty).isEmpty &&
      (url ?? '').trim().isEmpty &&
      (pattern ?? '').trim().isEmpty &&
      sources.where((AIWebSearchSource e) => !e.isEmpty).isEmpty &&
      (startedAtMs ?? 0) <= 0 &&
      (completedAtMs ?? 0) <= 0 &&
      (durationMs ?? 0) <= 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if ((id ?? '').trim().isNotEmpty) 'id': id!.trim(),
    if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
    if ((actionType ?? '').trim().isNotEmpty) 'action_type': actionType!.trim(),
    if ((query ?? '').trim().isNotEmpty) 'query': query!.trim(),
    if (queries.where((String e) => e.trim().isNotEmpty).isNotEmpty)
      'queries': queries
          .map((String e) => e.trim())
          .where((String e) => e.isNotEmpty)
          .toList(growable: false),
    if ((url ?? '').trim().isNotEmpty) 'url': url!.trim(),
    if ((pattern ?? '').trim().isNotEmpty) 'pattern': pattern!.trim(),
    if (sources.where((AIWebSearchSource e) => !e.isEmpty).isNotEmpty)
      'sources': sources
          .where((AIWebSearchSource e) => !e.isEmpty)
          .map((AIWebSearchSource e) => e.toJson())
          .where((Map<String, dynamic> e) => e.isNotEmpty)
          .toList(growable: false),
    if ((startedAtMs ?? 0) > 0) 'started_at_ms': startedAtMs,
    if ((completedAtMs ?? 0) > 0) 'completed_at_ms': completedAtMs,
    if ((durationMs ?? 0) > 0) 'duration_ms': durationMs,
  };

  factory AIWebSearchCall.fromJson(Map<String, dynamic> json) {
    String? readString(String key) {
      final Object? value = json[key];
      final String text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    int? readInt(String key) {
      final Object? value = json[key];
      final int n = value is num
          ? value.toInt()
          : int.tryParse(value?.toString().trim() ?? '') ?? 0;
      return n > 0 ? n : null;
    }

    List<String> readStrings(String key) {
      final Object? value = json[key];
      if (value is! List) return const <String>[];
      return value
          .map((Object? e) => e?.toString().trim() ?? '')
          .where((String e) => e.isNotEmpty)
          .toList(growable: false);
    }

    List<AIWebSearchSource> readSources(String key) {
      final Object? value = json[key];
      if (value is! List) return const <AIWebSearchSource>[];
      return value
          .whereType<Map>()
          .map(
            (Map e) => AIWebSearchSource.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((AIWebSearchSource e) => !e.isEmpty)
          .toList(growable: false);
    }

    return AIWebSearchCall(
      id: readString('id'),
      status: readString('status'),
      actionType: readString('action_type') ?? readString('actionType'),
      query: readString('query'),
      queries: readStrings('queries'),
      url: readString('url'),
      pattern: readString('pattern'),
      sources: readSources('sources'),
      startedAtMs: readInt('started_at_ms') ?? readInt('startedAtMs'),
      completedAtMs: readInt('completed_at_ms') ?? readInt('completedAtMs'),
      durationMs: readInt('duration_ms') ?? readInt('durationMs'),
    );
  }
}

String _webSearchCallMergeKey(AIWebSearchCall call) {
  final String id = (call.id ?? '').trim();
  if (id.isNotEmpty) return 'id:$id';
  return <String>[
    (call.actionType ?? '').trim(),
    (call.query ?? '').trim(),
    call.queries
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .join('|'),
    (call.url ?? '').trim(),
    (call.pattern ?? '').trim(),
  ].join('\u0001');
}

int _webSearchStatusRank(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'completed':
    case 'failed':
      return 4;
    case 'searching':
      return 3;
    case 'in_progress':
      return 2;
    default:
      return 1;
  }
}

List<AIWebSearchSource> mergeAIWebSearchSources(
  List<AIWebSearchSource> base,
  List<AIWebSearchSource> incoming,
) {
  final Map<String, AIWebSearchSource> byKey = <String, AIWebSearchSource>{};
  void add(AIWebSearchSource source) {
    if (source.isEmpty) return;
    final String url = source.url.trim();
    final String title = (source.title ?? '').trim();
    final String key = url.isNotEmpty ? url : title;
    if (key.isEmpty) return;
    final AIWebSearchSource? prev = byKey[key];
    byKey[key] = AIWebSearchSource(
      url: url.isNotEmpty ? url : prev?.url ?? '',
      title: title.isNotEmpty ? title : prev?.title,
    );
  }

  for (final AIWebSearchSource source in base) {
    add(source);
  }
  for (final AIWebSearchSource source in incoming) {
    add(source);
  }
  return byKey.values.toList(growable: false);
}

AIWebSearchCall _mergeAIWebSearchCall(
  AIWebSearchCall base,
  AIWebSearchCall incoming,
) {
  String? pickText(String? oldValue, String? newValue) {
    final String text = (newValue ?? '').trim();
    return text.isNotEmpty ? text : oldValue;
  }

  final String? incomingStatus = (incoming.status ?? '').trim().isEmpty
      ? null
      : incoming.status;
  final String? baseStatus = (base.status ?? '').trim().isEmpty
      ? null
      : base.status;
  final String? status =
      incomingStatus != null &&
          _webSearchStatusRank(incomingStatus) >=
              _webSearchStatusRank(baseStatus)
      ? incomingStatus
      : baseStatus;
  final int? startedAtMs = _minPositiveInt(
    base.startedAtMs,
    incoming.startedAtMs,
  );
  final int? completedAtMs = _maxPositiveInt(
    base.completedAtMs,
    incoming.completedAtMs,
  );
  final int? explicitDurationMs = _maxPositiveInt(
    base.durationMs,
    incoming.durationMs,
  );
  final int? computedDurationMs =
      explicitDurationMs ??
      ((startedAtMs ?? 0) > 0 &&
              (completedAtMs ?? 0) > 0 &&
              completedAtMs! >= startedAtMs!
          ? completedAtMs - startedAtMs
          : null);

  return AIWebSearchCall(
    id: pickText(base.id, incoming.id),
    status: status,
    actionType: pickText(base.actionType, incoming.actionType),
    query: pickText(base.query, incoming.query),
    queries: incoming.queries.isNotEmpty ? incoming.queries : base.queries,
    url: pickText(base.url, incoming.url),
    pattern: pickText(base.pattern, incoming.pattern),
    sources: mergeAIWebSearchSources(base.sources, incoming.sources),
    startedAtMs: startedAtMs,
    completedAtMs: completedAtMs,
    durationMs: computedDurationMs,
  );
}

int? _minPositiveInt(int? a, int? b) {
  final int av = a ?? 0;
  final int bv = b ?? 0;
  if (av <= 0) return bv > 0 ? bv : null;
  if (bv <= 0) return av;
  return av < bv ? av : bv;
}

int? _maxPositiveInt(int? a, int? b) {
  final int av = a ?? 0;
  final int bv = b ?? 0;
  if (av <= 0) return bv > 0 ? bv : null;
  if (bv <= 0) return av;
  return av > bv ? av : bv;
}

List<AIWebSearchCall> mergeAIWebSearchCalls(
  List<AIWebSearchCall> base,
  List<AIWebSearchCall> incoming,
) {
  final Map<String, AIWebSearchCall> byKey = <String, AIWebSearchCall>{};

  void add(AIWebSearchCall call) {
    if (call.isEmpty) return;
    final String key = _webSearchCallMergeKey(call);
    if (key.trim().isEmpty) return;
    final AIWebSearchCall? prev = byKey[key];
    byKey[key] = prev == null ? call : _mergeAIWebSearchCall(prev, call);
  }

  for (final AIWebSearchCall call in base) {
    add(call);
  }
  for (final AIWebSearchCall call in incoming) {
    add(call);
  }
  return byKey.values.toList(growable: false);
}

List<AIUrlCitation> mergeAIUrlCitations(
  List<AIUrlCitation> base,
  List<AIUrlCitation> incoming,
) {
  final Map<String, AIUrlCitation> byKey = <String, AIUrlCitation>{};

  void add(AIUrlCitation citation) {
    final String url = citation.url.trim();
    if (url.isEmpty) return;
    final String title = (citation.title ?? '').trim();
    final String key = <Object?>[
      url,
      title,
      citation.startIndex ?? '',
      citation.endIndex ?? '',
    ].join('\u0001');
    final AIUrlCitation? prev = byKey[key];
    byKey[key] = AIUrlCitation(
      url: url,
      title: title.isNotEmpty ? title : prev?.title,
      startIndex: citation.startIndex ?? prev?.startIndex,
      endIndex: citation.endIndex ?? prev?.endIndex,
    );
  }

  for (final AIUrlCitation citation in base) {
    add(citation);
  }
  for (final AIUrlCitation citation in incoming) {
    add(citation);
  }
  return byKey.values.toList(growable: false);
}

/// OpenAI Responses 输出文本里的 URL 引用标注。
class AIUrlCitation {
  const AIUrlCitation({
    required this.url,
    this.title,
    this.startIndex,
    this.endIndex,
  });

  final String url;
  final String? title;
  final int? startIndex;
  final int? endIndex;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url.trim(),
    if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
    if (startIndex != null) 'start_index': startIndex,
    if (endIndex != null) 'end_index': endIndex,
  };

  factory AIUrlCitation.fromJson(Map<String, dynamic> json) {
    int? readInt(String key) {
      final Object? value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final String url = (json['url']?.toString() ?? '').trim();
    final String title = (json['title']?.toString() ?? '').trim();
    return AIUrlCitation(
      url: url,
      title: title.isEmpty ? null : title,
      startIndex: readInt('start_index') ?? readInt('startIndex'),
      endIndex: readInt('end_index') ?? readInt('endIndex'),
    );
  }
}

/// 简单的对话消息模型
class AIMessage {
  static final RegExp _evidenceRefPattern = RegExp(
    r'\[\s*evidence\s*[:：]\s*([^\]]+?)\s*\]',
    caseSensitive: false,
  );
  static final RegExp _windowsAbsolutePathPattern = RegExp(r'^[A-Za-z]:[\\/]');

  final String role; // system | user | assistant
  final String content;
  final DateTime createdAt;
  // 新增：深度思考内容与耗时（仅用于本地持久化与 UI 展示，不参与上行）
  final String? reasoningContent;
  final Duration? reasoningDuration;
  // UI-only: persist thinking timeline blocks/events for stable restore.
  final String? uiThinkingJson;
  // UI stats: token usage and end-to-end assistant response duration.
  final int? usagePromptTokens;
  final int? usageCompletionTokens;
  final int? usageTotalTokens;
  final int? usageCacheHitTokens;
  final int? usageCacheMissTokens;
  final Duration? responseDuration;
  // UI-only: OpenAI Responses web_search 调用与引用来源。
  final List<AIWebSearchCall> webSearchCalls;
  final List<AIUrlCitation> citations;
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
    this.usagePromptTokens,
    this.usageCompletionTokens,
    this.usageTotalTokens,
    this.usageCacheHitTokens,
    this.usageCacheMissTokens,
    this.responseDuration,
    this.webSearchCalls = const <AIWebSearchCall>[],
    this.citations = const <AIUrlCitation>[],
    this.apiContent,
    this.toolCalls,
    this.toolCallId,
  }) : createdAt = createdAt ?? DateTime.now();

  static List<AIWebSearchCall> decodeWebSearchCallsJson(String? raw) {
    final String text = (raw ?? '').trim();
    if (text.isEmpty) return const <AIWebSearchCall>[];
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! List) return const <AIWebSearchCall>[];
      return decoded
          .whereType<Map>()
          .map(
            (Map e) => AIWebSearchCall.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((AIWebSearchCall e) => !e.isEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <AIWebSearchCall>[];
    }
  }

  static List<AIUrlCitation> decodeCitationsJson(String? raw) {
    final String text = (raw ?? '').trim();
    if (text.isEmpty) return const <AIUrlCitation>[];
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! List) return const <AIUrlCitation>[];
      return decoded
          .whereType<Map>()
          .map((Map e) => AIUrlCitation.fromJson(Map<String, dynamic>.from(e)))
          .where((AIUrlCitation e) => e.url.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <AIUrlCitation>[];
    }
  }

  static String? encodeWebSearchCallsJson(List<AIWebSearchCall> calls) {
    final List<Map<String, dynamic>> data = calls
        .where((AIWebSearchCall e) => !e.isEmpty)
        .map((AIWebSearchCall e) => e.toJson())
        .where((Map<String, dynamic> e) => e.isNotEmpty)
        .toList(growable: false);
    return data.isEmpty ? null : jsonEncode(data);
  }

  static String? encodeCitationsJson(List<AIUrlCitation> citations) {
    final List<Map<String, dynamic>> data = citations
        .where((AIUrlCitation e) => e.url.trim().isNotEmpty)
        .map((AIUrlCitation e) => e.toJson())
        .toList(growable: false);
    return data.isEmpty ? null : jsonEncode(data);
  }

  String get providerContent => sanitizeEvidenceRefsForProvider(content);

  static bool _looksLikeAbsoluteEvidencePath(String value) {
    final String v = value.trim();
    if (v.isEmpty) return false;
    return v.startsWith('/') ||
        v.startsWith('\\\\') ||
        _windowsAbsolutePathPattern.hasMatch(v);
  }

  static bool isAbsoluteEvidencePath(String value) {
    return _looksLikeAbsoluteEvidencePath(value);
  }

  static String _basenameFromPathLike(String value) {
    String v = value.trim();
    while (v.length > 1 && (v.endsWith('/') || v.endsWith('\\'))) {
      v = v.substring(0, v.length - 1);
    }
    final int slash = v.lastIndexOf('/');
    final int backslash = v.lastIndexOf('\\');
    final int idx = slash > backslash ? slash : backslash;
    if (idx < 0 || idx >= v.length - 1) return v;
    return v.substring(idx + 1);
  }

  static String sanitizeEvidenceRefsForProvider(String text) {
    if (text.isEmpty ||
        text.startsWith('data:') ||
        !text.contains('[') ||
        !_evidenceRefPattern.hasMatch(text)) {
      return text;
    }
    return text.replaceAllMapped(_evidenceRefPattern, (Match match) {
      final String original = match.group(0) ?? '';
      final String raw = (match.group(1) ?? '').trim();
      if (!_looksLikeAbsoluteEvidencePath(raw)) return original;
      final String basename = _basenameFromPathLike(raw).trim();
      if (basename.isEmpty) return original;
      return '[evidence: $basename]';
    });
  }

  static Object? sanitizeProviderContent(Object? value) {
    if (value is String) return sanitizeEvidenceRefsForProvider(value);
    if (value is List) {
      return value
          .map<Object?>((Object? item) => sanitizeProviderContent(item))
          .toList(growable: false);
    }
    if (value is Map) {
      final Map<String, dynamic> out = <String, dynamic>{};
      value.forEach((Object? key, Object? raw) {
        out[key.toString()] = sanitizeProviderContent(raw);
      });
      return out;
    }
    return value;
  }

  static List<String> _splitEvidenceTokenList(String raw) {
    final String normalized = raw.replaceAll(RegExp(r'[，、;；]+'), ',');
    return normalized
        .split(RegExp(r'[\s,]+'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .map((String s) => s.replaceAll(RegExp(r'^[,，、;；。\.]+'), ''))
        .map((String s) => s.replaceAll(RegExp(r'[,，、;；。\.]+$'), ''))
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static String resolveEvidenceRefsToLocalPaths(
    String text,
    Map<String, String> resolvedPaths,
  ) {
    if (text.isEmpty ||
        resolvedPaths.isEmpty ||
        !text.contains('[') ||
        !_evidenceRefPattern.hasMatch(text)) {
      return text;
    }
    return text.replaceAllMapped(_evidenceRefPattern, (Match match) {
      final String original = match.group(0) ?? '';
      final String raw = (match.group(1) ?? '').trim();
      if (raw.isEmpty || _looksLikeAbsoluteEvidencePath(raw)) {
        return original;
      }
      final String? resolved = resolvedPaths[raw];
      if (resolved != null && resolved.trim().isNotEmpty) {
        return '[evidence: ${resolved.trim()}]';
      }
      final List<String> tokens = _splitEvidenceTokenList(raw);
      if (tokens.length <= 1) return original;
      bool changed = false;
      final List<String> refs = <String>[];
      for (final String token in tokens) {
        final String? path = resolvedPaths[token];
        if (path != null && path.trim().isNotEmpty) {
          changed = true;
          refs.add('[evidence: ${path.trim()}]');
        } else {
          refs.add('[evidence: $token]');
        }
      }
      return changed ? refs.join(' ') : original;
    });
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{'role': role};

    Object? effectiveContent = apiContent ?? content;
    if (role == 'assistant' &&
        apiContent == null &&
        (toolCalls != null && toolCalls!.isNotEmpty) &&
        content.trim().isEmpty) {
      effectiveContent = null;
    }
    effectiveContent = sanitizeProviderContent(effectiveContent);
    m['content'] = effectiveContent;

    if (toolCalls != null && toolCalls!.isNotEmpty) m['tool_calls'] = toolCalls;
    if ((reasoningContent ?? '').trim().isNotEmpty) {
      m['reasoning_content'] = sanitizeEvidenceRefsForProvider(
        reasoningContent!.trim(),
      );
    }
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

  AIMessage copyWith({
    String? role,
    String? content,
    DateTime? createdAt,
    String? reasoningContent,
    Duration? reasoningDuration,
    String? uiThinkingJson,
    int? usagePromptTokens,
    int? usageCompletionTokens,
    int? usageTotalTokens,
    int? usageCacheHitTokens,
    int? usageCacheMissTokens,
    Duration? responseDuration,
    List<AIWebSearchCall>? webSearchCalls,
    List<AIUrlCitation>? citations,
    Object? apiContent,
    List<Map<String, dynamic>>? toolCalls,
    String? toolCallId,
  }) {
    return AIMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      reasoningDuration: reasoningDuration ?? this.reasoningDuration,
      uiThinkingJson: uiThinkingJson ?? this.uiThinkingJson,
      usagePromptTokens: usagePromptTokens ?? this.usagePromptTokens,
      usageCompletionTokens:
          usageCompletionTokens ?? this.usageCompletionTokens,
      usageTotalTokens: usageTotalTokens ?? this.usageTotalTokens,
      usageCacheHitTokens: usageCacheHitTokens ?? this.usageCacheHitTokens,
      usageCacheMissTokens: usageCacheMissTokens ?? this.usageCacheMissTokens,
      responseDuration: responseDuration ?? this.responseDuration,
      webSearchCalls: webSearchCalls ?? this.webSearchCalls,
      citations: citations ?? this.citations,
      apiContent: apiContent ?? this.apiContent,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_action_menu.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/ai/application/ai_chat_service.dart';
import 'package:screen_memo/features/ai/application/ai_image_generation_service.dart';
import 'package:screen_memo/features/ai/application/chat_context_service.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/core/widgets/ui_select_field.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/markdown_math.dart';
import 'package:screen_memo/app/navigation/widgets/app_side_drawer.dart';
import 'package:screen_memo/features/gallery/presentation/widgets/screenshot_image_widget.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/features/ai/application/intent_analysis_service.dart';
import 'package:screen_memo/features/ai/application/query_context_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/data/platform/path_service.dart';
import 'package:screen_memo/features/nsfw/application/nsfw_preference_service.dart';
import 'package:screen_memo/features/search/application/ocr_search_service.dart';
import 'package:screen_memo/core/performance/ui_perf_logger.dart';
import 'package:screen_memo/features/timeline/application/dynamic_entry_perf_service.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/chat_context_sheet.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_request_logs_action.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_request_logs_viewer.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_request_logs_sheet.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_image_generation_menu_button.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_provider_model_picker.dart';
import 'package:screen_memo/core/widgets/ui_perf_overlay.dart';

part 'ai_settings/ai_settings_page_state_core.dart';
part 'ai_settings/ai_settings_page_state_send_message.dart';
part 'ai_settings/ai_settings_page_state_thinking_codec.dart';
part 'ai_settings/ai_settings_page_state_chat_list.dart';
part 'ai_settings/ai_settings_page_widgets.dart';

// Thinking/Reasoning content should be visually distinct from the final answer.
const Color _thinkingTextColor = Color(0xFF71717A);
// Warm "platinum/white-gold" shimmer highlight used while thinking.
const Color _thinkingShimmerHighlightColor = Color(0xFFFFFBEB);
const int _maxComposerImages = 16;
const double _composerInputRowHeight = 40.0;
const int _composerInputMaxLines = 10;

enum _ClarifyReason { missingTime, tooBroad }

enum _ClarifyStage { ask, pickCandidate }

enum _ProbeKind { segments, ocr, none }

class _ProbeCandidate {
  final int index; // 1-based
  final int startMs;
  final int endMs;
  final _ProbeKind kind;
  final String title;
  final String subtitle;

  const _ProbeCandidate({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.kind,
    required this.title,
    required this.subtitle,
  });
}

class _ComposerImageAttachment {
  const _ComposerImageAttachment({
    required this.path,
    required this.name,
    required this.mimeType,
  });

  final String path;
  final String name;
  final String mimeType;
}

class _ClarifyState {
  _ClarifyState({
    required this.originalQuestion,
    required this.reason,
    this.hintStartMs,
    this.hintEndMs,
  });

  final String originalQuestion;
  final _ClarifyReason reason;
  final int? hintStartMs;
  final int? hintEndMs;

  final List<String> supplements = <String>[];
  int askRounds = 0;
  _ClarifyStage stage = _ClarifyStage.ask;
  _ProbeKind lastProbeKind = _ProbeKind.none;
  final List<_ProbeCandidate> candidates = <_ProbeCandidate>[];
}

enum _ThinkingEventType {
  status,
  intent,
  reasoning,
  tools,
  plan,
  todo,
  subagents,
}

class _AgentStatusItem {
  _AgentStatusItem({
    required this.id,
    required this.text,
    required this.status,
  });

  final String id;
  String text;
  String status;
}

class _SubagentStatusItem {
  _SubagentStatusItem({
    required this.id,
    required this.name,
    required this.status,
    this.role,
    this.summary,
    this.model,
    this.conversationCid,
    this.contextTokensEstimate,
    this.contextCapTokens,
    this.contextPercent,
    this.durationMs,
  });

  final String id;
  String name;
  String status;
  String? role;
  String? summary;
  String? model;
  String? conversationCid;
  int? contextTokensEstimate;
  int? contextCapTokens;
  int? contextPercent;
  int? durationMs;
}

class _ReadOnlyConversationMeta {
  const _ReadOnlyConversationMeta({
    required this.providerName,
    required this.model,
    required this.contextTokens,
    required this.contextCapTokens,
  });

  final String providerName;
  final String model;
  final int contextTokens;
  final int contextCapTokens;

  int get percent {
    if (contextTokens <= 0 || contextCapTokens <= 0) return 0;
    return ((contextTokens * 100) / contextCapTokens).round().clamp(0, 999);
  }

  String get percentLabel {
    if (contextTokens <= 0 || contextCapTokens <= 0) return '-';
    final double value = contextTokens * 100.0 / contextCapTokens;
    if (value > 0 && value < 0.1) return '<0.1%';
    if (value < 10) return '${value.toStringAsFixed(1)}%';
    return '${value.round().clamp(0, 999)}%';
  }
}

class _ReadOnlyConversationUsageBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _ReadOnlyConversationUsageBar({required this.metaFuture});

  final Future<_ReadOnlyConversationMeta>? metaFuture;

  static const double _barHeight = 6.0;

  @override
  Size get preferredSize => const Size.fromHeight(0);

  static bool _isZhContext(BuildContext context) => Localizations.localeOf(
    context,
  ).languageCode.toLowerCase().startsWith('zh');

  static String _fmtCompactInt(int value) {
    final int v = value.clamp(0, 1 << 62).toInt();
    if (v < 1000) return v.toString();
    if (v < 10000) {
      final String s = (v / 1000).toStringAsFixed(1);
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}k';
    }
    if (v < 1000000) return '${(v / 1000).round()}k';
    final String s = (v / 1000000).toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}m';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReadOnlyConversationMeta>(
      future: metaFuture,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final _ReadOnlyConversationMeta? meta = snapshot.data;
        final int tokens = meta?.contextTokens ?? 0;
        final int cap = meta?.contextCapTokens ?? 0;
        final double ratio = cap > 0
            ? (tokens / cap).clamp(0.0, 1.0).toDouble()
            : 0.0;
        final String usedText = tokens > 0 ? _fmtCompactInt(tokens) : '-';
        final String capText = cap > 0 ? _fmtCompactInt(cap) : '-';
        final String percentText = meta?.percentLabel ?? '-';
        final String tooltip = _isZhContext(context)
            ? '子代理上下文 · $usedText/$capText · $percentText'
            : 'Subagent context · $usedText/$capText · $percentText';

        return SizedBox(
          height: 0,
          child: OverflowBox(
            alignment: Alignment.bottomLeft,
            minHeight: _barHeight,
            maxHeight: _barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
              ),
              child: Tooltip(
                message: tooltip,
                child: Transform.translate(
                  offset: const Offset(0, -AppTheme.spacing2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: _barHeight,
                      value: ratio,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThinkingToolChip {
  _ThinkingToolChip({
    required this.callId,
    required this.toolName,
    required this.label,
    this.appNames = const <String>[],
    this.appPackageNames = const <String>[],
    this.active = true,
    this.resultSummary,
    this.durationMs,
    this.detailRef,
  });

  final String callId;
  final String toolName;
  final String label;
  List<String> appNames;
  List<String> appPackageNames;
  bool active;
  String? resultSummary;
  int? durationMs;
  String? detailRef;
}

class _ThinkingEvent {
  _ThinkingEvent({
    required this.type,
    required this.title,
    this.subtitle,
    this.icon,
    this.active = false,
    this.transient = false,
    this.tools = const <_ThinkingToolChip>[],
    this.items = const <_AgentStatusItem>[],
    this.subagents = const <_SubagentStatusItem>[],
    this.reasoningStart,
    this.reasoningLength,
  });

  final _ThinkingEventType type;
  String title;
  String? subtitle;
  IconData? icon;
  bool active; // shimmer when active=true
  bool transient; // 只用于当前请求的临时加载提示，不持久化
  final List<_ThinkingToolChip> tools;
  final List<_AgentStatusItem> items;
  final List<_SubagentStatusItem> subagents;
  int? reasoningStart;
  int? reasoningLength;
}

class _ThinkingBlock {
  _ThinkingBlock({required this.createdAt});

  final DateTime createdAt;
  DateTime? finishedAt;
  final List<_ThinkingEvent> events = <_ThinkingEvent>[];

  bool get isLoading => finishedAt == null;
}

/// Writes chat request/response logs to a dedicated file while streaming.
///
/// This is intentionally lightweight (best-effort) so logging can't break the
/// UI flow when storage is unavailable.
class _GatewayLogFileWriter {
  _GatewayLogFileWriter(this.file) {
    _sink = file.openWrite(mode: FileMode.append);
  }

  final File file;
  late final IOSink _sink;
  Timer? _flushTimer;
  bool _closed = false;

  void write(String text) {
    if (_closed || text.isEmpty) return;
    try {
      _sink.write(text);
      _scheduleFlush();
    } catch (_) {}
  }

  void writeLine(String line) {
    if (line.isEmpty) return;
    write(line.endsWith('\n') ? line : (line + '\n'));
  }

  void _scheduleFlush() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(milliseconds: 250), () {
      _flushTimer = null;
      try {
        unawaited(_sink.flush().catchError((_) {}));
      } catch (_) {}
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      await _sink.flush();
    } catch (_) {}
    try {
      await _sink.close();
    } catch (_) {}
  }
}

/// AI 设置与测试页面：配置 OpenAI 兼容接口并进行多轮聊天测试
class AISettingsPage extends StatefulWidget {
  final bool embedded;
  final String? conversationCid;
  final bool readOnly;
  const AISettingsPage({
    super.key,
    this.embedded = false,
    this.conversationCid,
    this.readOnly = false,
  });

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage>
    with SingleTickerProviderStateMixin {
  final AISettingsService _settings = AISettingsService.instance;
  final AIChatService _chat = AIChatService.instance;

  // In-page perf timeline for troubleshooting slow image render on chat page.
  final UiPerfLogger _uiPerf = UiPerfLogger(scope: 'AIChat');
  // Controlled by Settings > Advanced. Defaults to hidden to avoid noisy UI.
  bool _showPerfOverlay = false;
  final Set<String> _perfLoggedMarkdownMsgKeys = <String>{};
  final Set<String> _usageStatsUiLoggedKeys = <String>{};
  Map<String, Uint8List?> _chatAppIconByPackage = <String, Uint8List?>{};
  Map<String, Uint8List?> _chatAppIconByNameLower = <String, Uint8List?>{};
  Map<String, String> _chatAppNameByPackage = <String, String>{};
  bool _chatAppIconCacheLoaded = false;
  bool _chatAppIconCacheLoading = false;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _inputController = TextEditingController();

  // 聊天列表滚动控制器
  final ScrollController _chatScrollController = ScrollController();
  // 折叠思考预览的滚动（底部面板）
  final ScrollController _reasoningPanelScrollController = ScrollController();

  // 动态省略号（思考中）状态
  Timer? _dotsTimer;
  String _thinkingDots = '';

  Timer? _inFlightSaveTimer;
  bool _inFlightHistoryDirty = false;
  // 从首页重新进入 AI 页时，正在后台完成的请求没有前台 stream 订阅。
  // 用这个标记区分“真实前台发送中”和“从持久化占位恢复的后台进行中”。
  bool _restoredBackgroundInFlight = false;
  // Serialize history persistence so a slow in-flight save can't overwrite the
  // final post-processed content after streaming finishes.
  Future<void> _chatHistorySaveChain = Future<void>.value();
  // Monotonic token to invalidate queued history writes (e.g. when the UI is
  // detached on conversation/page switch).
  int _chatHistoryWriteEpoch = 0;

  List<AIMessage> _messages = <AIMessage>[];

  // —— Full transcript paging (UI) ——
  static const int _fullHistoryPageSize = 200;
  int? _olderBeforeId;
  bool _olderHasMore = false;
  bool _olderLoading = false;
  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  bool _streamEnabled = true;
  StreamSubscription<AIStreamEvent>? _streamSubscription;
  // Conversation CID captured at the moment a streaming turn starts.
  // Used to prevent persistence/UI updates from "jumping" after a conversation switch.
  String? _inFlightConversationCid;
  // The active conversation CID that the chat list currently represents.
  // Used to make "send" stable even if the user switches conversations mid-request.
  String? _activeConversationCid;
  Future<_ReadOnlyConversationMeta>? _readOnlyConversationMetaFuture;
  // Monotonic token for the currently active send/stream loop. Changing this
  // detaches the UI from an in-flight background request.
  int _sendEpoch = 0;
  int _activeSendEpoch = 0;
  Completer<void>? _streamLoopCompleter;
  bool _connExpanded = false;
  bool _groupSelectorVisible = true;
  bool _promptExpanded = false;

  // ——— AI 交互样式与流式状态（仅影响本页 UI，不改动全局样式） ———
  AIReasoningLevel _reasoningLevel = AIReasoningLevel.auto;
  bool _webSearch = false; // "联网搜索"开关（先做样式，后续可接搜索参数）
  bool _imageDrawMode = false;
  bool _composerHasText = false;
  bool _composerTodoExpanded = false;
  bool _pickingComposerImages = false;
  bool _processingComposerImages = false;
  int _composerImageSkeletonCount = 0;
  List<_ComposerImageAttachment> _composerImages = <_ComposerImageAttachment>[];
  final Set<String> _sentComposerImagePaths = <String>{};
  bool _inStreaming = false; // 当前是否处于助手流式回复中（驱动"思考中"可视化）
  // 实时"思考过程"内容（仅当前流式过程显示）
  String _thinkingText = '';
  bool _showThinkingContent = false;
  // Hide internal stage/progress logs in chat UI by default.
  final bool _showAgentProgressLogs = false;
  // 每条助手消息的思考内容缓存（索引 -> 文本）
  final Map<int, String> _reasoningByIndex = <int, String>{};
  // 每条助手消息的网关请求/响应调试日志（索引 -> 文本，便于复制排查流式协议/解析问题）
  final Map<int, String> _gatewayLogsByIndex = <int, String>{};
  // 可选：将网关日志实时镜像到文件（索引 -> writer/path）。
  // 主要用于排查 SSE/字段兼容问题（例如仅有 reasoning_content 而无 content）。
  final Map<int, _GatewayLogFileWriter> _gatewayLogWritersByIndex =
      <int, _GatewayLogFileWriter>{};
  final Map<int, String> _gatewayLogFilePathByIndex = <int, String>{};
  // 每条助手消息的最终思考耗时（索引 -> 时长）
  final Map<int, Duration> _reasoningDurationByIndex = <int, Duration>{};
  // 当前流式助手消息的索引
  int? _currentAssistantIndex;
  // 是否在下一条 content token 到来时，清空占位内容（用于"阶段状态" -> 最终回答的替换）
  bool _replaceAssistantContentOnNextToken = false;
  // 每条助手消息的思考块（索引 -> blocks）
  final Map<int, List<_ThinkingBlock>> _thinkingBlocksByIndex =
      <int, List<_ThinkingBlock>>{};
  final ValueNotifier<int> _subagentListVersion = ValueNotifier<int>(0);
  List<Map<String, dynamic>> _subagentConversationRows =
      const <Map<String, dynamic>>[];
  // 每条助手消息的正文缓存。思考过程统一显示在正文之前，正文只保留连续文本。
  final Map<int, List<String>> _contentSegmentsByIndex = <int, List<String>>{};
  // 每条助手消息附带的证据图片（索引 -> 附件列表）
  final Map<int, List<EvidenceImageAttachment>> _attachmentsByIndex =
      <int, List<EvidenceImageAttachment>>{};
  // 证据缩略图需要同步显示 NSFW 遮罩；这里缓存 filePath -> ScreenshotRecord，避免重复扫库。
  final Map<String, ScreenshotRecord?> _evidenceScreenshotByPath =
      <String, ScreenshotRecord?>{};
  // 防止滚动/重建触发重复的 NSFW 批量预加载。
  final Set<String> _evidenceNsfwRequestedPaths = <String>{};
  Future<void>? _evidenceNsfwPreloadFuture;
  // 证据图片解析缓存：避免退出/重进或页面重建时重复扫库/扫盘导致“解析中一直不出图”
  final Map<String, Map<String, String>> _evidenceResolvedByMsgKey =
      <String, Map<String, String>>{};
  // 工具执行阶段直接拿到的本地路径映射（助手消息索引 -> filename/path）。
  // 只在本地 UI 中使用，不进入 provider payload 或 ui_thinking_json。
  final Map<int, Map<String, String>> _evidenceResolvedByAssistantIndex =
      <int, Map<String, String>>{};
  final Map<String, Future<Map<String, String>>> _evidenceResolveFutures =
      <String, Future<Map<String, String>>>{};
  final Set<String> _evidenceAbsolutePersistScheduledKeys = <String>{};
  bool _evidenceRebuildScheduled = false;
  // 上一轮意图结果（用于为下一轮提供 prev hint）
  IntentResult? _lastIntent;
  final Set<String> _intentAnalyzedConversationCids = <String>{};
  // 澄清推进：当时间缺失/范围过大时，先温和追问 + 再做探测检索候选
  _ClarifyState? _clarifyState;
  // 提示词管理
  String? _promptSegment;
  String? _promptMerge;
  String? _promptDaily;
  final TextEditingController _promptSegmentController =
      TextEditingController();
  final TextEditingController _promptMergeController = TextEditingController();
  final TextEditingController _promptDailyController = TextEditingController();
  bool _editingPromptSegment = false;
  bool _editingPromptMerge = false;
  bool _editingPromptDaily = false;
  bool _savingPromptSegment = false;
  bool _savingPromptMerge = false;
  bool _savingPromptDaily = false;

  // 渲染设置：是否在流式期间实时渲染图片（可能影响性能）
  bool _renderImagesDuringStreaming = false;

  // —— 全屏横向滑动呼出 Drawer ——
  double _drawerGestureAccumDx = 0.0;
  bool _drawerGestureTriggered = false;

  //（页面级渐变已移除，应用户要求）

  // —— 基于提供商表的对话上下文（chat 专用） ——
  AIProvider? _ctxChatProvider;
  String? _ctxChatModel;
  bool _ctxLoading = true;
  StreamSubscription<String>? _ctxChangedSub;
  Timer? _ctxDebounceTimer;
  bool _loadingAllInFlight = false;
  bool _loadAllQueued = false;
  // 底部弹窗查询输入持久化，避免键盘开合导致重建清空
  String _providerQueryText = '';
  String _modelQueryText = '';
  // 默认提示词模板内容仅在系统内部维护，不在前端暴露。
  String get _defaultSegmentPromptPreview => '';

  String get _defaultMergePromptPreview => '';

  String get _defaultDailyPromptPreview => '';

  // 分组相关状态
  List<AISiteGroup> _groups = <AISiteGroup>[];
  int? _activeGroupId;

  // 流式进行中时，延迟执行的 chat 上下文刷新（避免打断 UI 追加）
  bool _pendingChatReload = false;
  // _loadAll() 的批量追加任务防串台标记
  int _loadAllEpoch = 0;
  bool _trackDynamicEntryPerf = false;

  void _setState(VoidCallback fn) => setState(fn);

  void _handleComposerInputChanged() {
    final bool nextHasText = _inputController.text.trim().isNotEmpty;
    if (_composerHasText == nextHasText) return;
    if (!mounted) {
      _composerHasText = nextHasText;
      return;
    }
    _setState(() {
      _composerHasText = nextHasText;
    });
  }

  void _logChatPerf(String name, {String? detail, Stopwatch? stopwatch}) {
    final String d0 = (detail ?? '').trim();
    final String d = [
      if (stopwatch != null) 'ms=${stopwatch.elapsedMilliseconds}',
      if (d0.isNotEmpty) d0,
    ].join(' ');
    _uiPerf.log(name, detail: d.isEmpty ? null : d);
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_CHAT_PERF',
        d.isEmpty ? 'AIChat.$name' : 'AIChat.$name $d',
      ).catchError((_) {}),
    );
  }

  Future<void> _loadPerfOverlayEnabled() async {
    try {
      final bool enabled = await _settings.getAiChatPerfOverlayEnabled();
      if (!mounted) return;
      setState(() => _showPerfOverlay = enabled);
    } catch (_) {}
  }

  void _refreshReadOnlyConversationMetaFuture() {
    _readOnlyConversationMetaFuture = _loadReadOnlyConversationMeta();
  }

  int _safeMetaInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim()) ?? 0;
  }

  Future<_ReadOnlyConversationMeta> _loadReadOnlyConversationMeta() async {
    final String cid = (widget.conversationCid ?? '').trim();
    Map<String, dynamic>? row;
    if (cid.isNotEmpty) {
      try {
        row = await ScreenshotDatabase.instance.getAiConversationByCid(cid);
      } catch (_) {
        row = null;
      }
    }

    int providerId = _safeMetaInt(row?['provider_id']);
    String model = ((row?['model'] as String?) ?? '').trim();
    final int contextTokens = _safeMetaInt(row?['subagent_context_tokens']);
    final int contextCapTokens = _safeMetaInt(
      row?['subagent_context_cap_tokens'],
    );

    if (providerId <= 0 || model.isEmpty) {
      try {
        final Map<String, dynamic>? ctx = await ScreenshotDatabase.instance
            .getAIContext('chat');
        if (providerId <= 0) providerId = _safeMetaInt(ctx?['provider_id']);
        if (model.isEmpty) {
          model = ((ctx?['model'] as String?) ?? '').trim();
        }
      } catch (_) {}
    }

    String providerName = '';
    if (providerId > 0) {
      try {
        final AIProvider? provider = await AIProvidersService.instance
            .getProvider(providerId);
        providerName = (provider?.name ?? '').trim();
      } catch (_) {
        providerName = '';
      }
    }
    if (model.isEmpty) {
      try {
        model = (await _settings.getModel()).trim();
      } catch (_) {
        model = '';
      }
    }

    return _ReadOnlyConversationMeta(
      providerName: providerName,
      model: model,
      contextTokens: contextTokens,
      contextCapTokens: contextCapTokens,
    );
  }

  Widget _buildReadOnlyAppBarTitle(BuildContext context) {
    final theme = Theme.of(context);
    final String title = _isZhLocale() ? '子代理' : 'Subagent';
    return FutureBuilder<_ReadOnlyConversationMeta>(
      future: _readOnlyConversationMetaFuture,
      builder: (context, snapshot) {
        final _ReadOnlyConversationMeta? meta = snapshot.data;
        final List<String> parts = <String>[
          if ((meta?.providerName ?? '').trim().isNotEmpty)
            meta!.providerName.trim(),
          if ((meta?.model ?? '').trim().isNotEmpty) meta!.model.trim(),
        ];
        final String subtitle = parts.join(' · ');
        if (subtitle.isEmpty) {
          return Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
        }
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: title),
              TextSpan(
                text: ' · $subtitle',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  void _markDynamicEntryPerf(
    String step, {
    String? detail,
    bool finish = false,
  }) {
    if (!_trackDynamicEntryPerf || !widget.embedded) return;
    DynamicEntryPerfService.instance.ensureSession(
      source: 'AISettingsPage.embedded',
    );
    if (finish) {
      DynamicEntryPerfService.instance.finish(step, detail: detail);
      _trackDynamicEntryPerf = false;
      return;
    }
    DynamicEntryPerfService.instance.mark(step, detail: detail);
  }

  @override
  void initState() {
    super.initState();
    if (widget.embedded) {
      _trackDynamicEntryPerf = true;
      DynamicEntryPerfService.instance.ensureSession(
        source: 'AISettingsPage.embedded.initState',
      );
      _markDynamicEntryPerf('chatPage.initState');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _markDynamicEntryPerf('chatPage.shell.firstFrame');
      });
    }
    _uiPerf.clear(restart: true);
    _uiPerf.log('page.initState');
    _composerHasText = _inputController.text.trim().isNotEmpty;
    _inputController.addListener(_handleComposerInputChanged);
    unawaited(_loadPerfOverlayEnabled());
    if (widget.readOnly) {
      _refreshReadOnlyConversationMetaFuture();
    }
    _loadAll();
    _loadChatContextSelection();
    _warmChatAppIconCache();
    _ctxChangedSub = AISettingsService.instance.onContextChanged.listen((ctx) {
      if (!mounted) return;
      final String fixedWidgetCid = (widget.conversationCid ?? '').trim();
      if (fixedWidgetCid.isNotEmpty &&
          ctx != 'chat:history:$fixedWidgetCid' &&
          ctx != 'chat:deleted' &&
          ctx != 'chat:cleared') {
        return;
      }
      if (ctx == 'chat:history' || ctx.startsWith('chat:history:')) {
        final String activeCid = (_activeConversationCid ?? '').trim();
        if (ctx.startsWith('chat:history:')) {
          final String cid = ctx.substring('chat:history:'.length).trim();
          // If the update is for a different conversation than what we're
          // currently showing, ignore it to avoid unnecessary reloads.
          if (cid.isNotEmpty && activeCid.isNotEmpty && cid != activeCid) {
            return;
          }
        }
        // Background completion may persist into DB after the chat UI was
        // detached (conversation/page switch). Reload the active conversation so
        // the final answer + thinking timeline shows up without a manual refresh.
        if ((_sending || _inStreaming) && !_restoredBackgroundInFlight) return;
        _ctxDebounceTimer?.cancel();
        _ctxDebounceTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          _loadAll();
        });
        return;
      }
      if (ctx == 'chat') {
        // 模型/提供商切换也会广播 chat；只有会话 CID 变化时才重载消息。
        _ctxDebounceTimer?.cancel();
        _ctxDebounceTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          unawaited(_handleChatContextChanged());
        });
        return;
      }
      if (ctx == 'chat:deleted' || ctx == 'chat:cleared') {
        // 去抖 250ms 合并多次事件，避免重复重载
        _ctxDebounceTimer?.cancel();
        _ctxDebounceTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          unawaited(_handleChatDeletedOrCleared());
        });
      }
    });
  }

  Future<void> _handleChatDeletedOrCleared() async {
    final Stopwatch sw = Stopwatch()..start();
    _logChatPerf('deletedOrCleared.start');

    String nextCid = '';
    try {
      nextCid = (await _settings.getActiveConversationCid()).trim();
    } catch (e) {
      _logChatPerf(
        'deletedOrCleared.cid.error',
        stopwatch: sw,
        detail: 'err=$e',
      );
    }
    if (!mounted) return;

    // 删除/清空当前会话时，先让进行中的请求转入后台，避免后续增量继续写入已清空 UI。
    if (_sending || _inStreaming) {
      _detachStreamingUiForBackground(
        persistUiState: false,
        // 保留持久化里的思考块为 loading，方便回到会话时仍能看到后台请求状态。
        finishThinkingBlock: false,
      );
    }

    // 若是删除事件，先立即清空当前对话 UI，避免等待重载造成的"空白延迟"。
    // 同步写入新的 active cid，避免 _loadAll() 的防串台检查把新会话加载结果丢弃。
    final String clearedCid = (_activeConversationCid ?? '').trim();
    if (clearedCid.isNotEmpty) {
      _intentAnalyzedConversationCids.remove(clearedCid);
    }
    _clearChatUiForConversationReload(
      activeConversationCid: nextCid,
      clearImageCaches: true,
    );
    await _loadChatContextSelection();
    await _loadAll();
    _logChatPerf('deletedOrCleared.done', stopwatch: sw);
  }

  Future<void> _handleChatContextChanged() async {
    final Stopwatch sw = Stopwatch()..start();
    _logChatPerf('contextChanged.start');
    String newCid = '';
    try {
      newCid = (await _settings.getActiveConversationCid()).trim();
    } catch (_) {
      newCid = '';
    }
    if (!mounted) return;

    final String oldCid = (_activeConversationCid ?? '').trim();
    final bool hasLoadedConversation = oldCid.isNotEmpty;
    final bool conversationChanged =
        hasLoadedConversation && newCid.isNotEmpty && newCid != oldCid;
    _logChatPerf(
      'contextChanged.cid.done',
      stopwatch: sw,
      detail:
          'oldHash=${oldCid.hashCode} newHash=${newCid.hashCode} hasLoaded=$hasLoadedConversation changed=$conversationChanged',
    );

    if (!conversationChanged && hasLoadedConversation) {
      _logChatPerf('contextChanged.sameConversation.start', stopwatch: sw);
      await _loadChatContextSelection();
      await _loadChatConfigOnly();
      _logChatPerf('contextChanged.sameConversation.done', stopwatch: sw);
      return;
    }

    if (conversationChanged) {
      _logChatPerf(
        'contextChanged.conversationChanged.start',
        stopwatch: sw,
        detail: 'streaming=$_inStreaming sending=$_sending',
      );
      if (_sending || _inStreaming) {
        _detachStreamingUiForBackground(
          persistUiState: true,
          finishThinkingBlock: false,
        );
      }
      _clearChatUiForConversationReload(activeConversationCid: newCid);
      _logChatPerf('contextChanged.uiCleared.done', stopwatch: sw);
    }

    await _loadChatContextSelection();
    _logChatPerf('contextChanged.selection.done', stopwatch: sw);
    await _loadAll();
    _logChatPerf('contextChanged.loadAll.done', stopwatch: sw);
  }

  Future<void> _loadChatConfigOnly() async {
    final Stopwatch sw = Stopwatch()..start();
    _logChatPerf('configOnly.start');
    try {
      final Future<int?> fActiveId = _settings.getActiveGroupId();
      final Future<String> fBaseUrl = _settings.getBaseUrl();
      final Future<String?> fApiKey = _settings.getApiKey().timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );
      final Future<String> fModel = _settings.getModel();

      final int? activeId = await fActiveId;
      final String baseUrl = await fBaseUrl;
      final String? apiKey = await fApiKey;
      final String model = await fModel;
      if (!mounted) return;
      _logChatPerf(
        'configOnly.futures.done',
        stopwatch: sw,
        detail:
            'activeId=${activeId ?? -1} hasKey=${apiKey != null} model=$model',
      );

      final String nextBaseUrl =
          activeId == null && baseUrl == 'https://api.openai.com'
          ? ''
          : baseUrl;
      final String nextApiKey = apiKey ?? '';
      final String nextModel = activeId == null && model == 'gpt-4o-mini'
          ? ''
          : model;
      final bool stateChanged = _activeGroupId != activeId;
      final bool textChanged =
          _baseUrlController.text != nextBaseUrl ||
          _apiKeyController.text != nextApiKey ||
          _modelController.text != nextModel;
      if (!stateChanged && !textChanged) {
        _logChatPerf('configOnly.noChange', stopwatch: sw);
        return;
      }

      void updateText(TextEditingController controller, String value) {
        if (controller.text == value) return;
        controller.text = value;
      }

      _setState(() {
        _activeGroupId = activeId;
        updateText(_baseUrlController, nextBaseUrl);
        updateText(_apiKeyController, nextApiKey);
        updateText(_modelController, nextModel);
      });
      _logChatPerf(
        'configOnly.setState.done',
        stopwatch: sw,
        detail: 'stateChanged=$stateChanged textChanged=$textChanged',
      );
    } catch (e) {
      _logChatPerf('configOnly.error', stopwatch: sw, detail: 'err=$e');
    }
  }

  void _clearChatUiForConversationReload({
    String? activeConversationCid,
    bool clearImageCaches = false,
  }) {
    final Stopwatch sw = Stopwatch()..start();
    // 清空 UI 前先尽力关闭日志写入器，避免文件句柄泄漏。
    try {
      final writers = List<_GatewayLogFileWriter>.from(
        _gatewayLogWritersByIndex.values,
      );
      _gatewayLogWritersByIndex.clear();
      _gatewayLogFilePathByIndex.clear();
      for (final w in writers) {
        unawaited(w.close());
      }
    } catch (_) {}
    _setState(() {
      final String cid = (activeConversationCid ?? '').trim();
      if (cid.isNotEmpty) {
        _activeConversationCid = cid;
      }
      _loading = true;
      _messages = <AIMessage>[];
      _olderBeforeId = null;
      _olderHasMore = false;
      _olderLoading = false;
      _attachmentsByIndex.clear();
      _evidenceResolvedByAssistantIndex.clear();
      if (clearImageCaches) {
        _evidenceResolvedByMsgKey.clear();
        _evidenceResolveFutures.clear();
        _evidenceScreenshotByPath.clear();
        _evidenceNsfwRequestedPaths.clear();
        _evidenceNsfwPreloadFuture = null;
      }
      _reasoningByIndex.clear();
      _gatewayLogsByIndex.clear();
      _reasoningDurationByIndex.clear();
      _thinkingBlocksByIndex.clear();
      _subagentConversationRows = const <Map<String, dynamic>>[];
      _contentSegmentsByIndex.clear();
      _currentAssistantIndex = null;
      _inStreaming = false;
      _sending = false;
      _restoredBackgroundInFlight = false;
      _lastIntent = null;
      _clarifyState = null;
    });
    _stopInFlightHistoryPersistence();
    _stopDots();
    _logChatPerf(
      'clearChatUi.done',
      stopwatch: sw,
      detail: 'clearImageCaches=$clearImageCaches',
    );
  }

  @override
  void dispose() {
    // If we are leaving the page mid-stream, detach the UI and persist a
    // snapshot so background completion can still land in DB. Keep the thinking
    // block "loading" so restoring the conversation doesn't look stuck.
    if (_sending || _inStreaming) {
      _detachStreamingUiForBackground(
        persistUiState: true,
        setUiStopped: false,
        finishThinkingBlock: false,
      );
    }
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _inputController.removeListener(_handleComposerInputChanged);
    _inputController.dispose();
    _promptSegmentController.dispose();
    _promptMergeController.dispose();
    _promptDailyController.dispose();
    for (final _ComposerImageAttachment image in _composerImages) {
      unawaited(File(image.path).delete().catchError((_) => File(image.path)));
    }
    _composerImages = <_ComposerImageAttachment>[];
    _sentComposerImagePaths.clear();
    _chatScrollController.dispose();
    _reasoningPanelScrollController.dispose();
    _dotsTimer?.cancel();
    _inFlightSaveTimer?.cancel();
    _ctxDebounceTimer?.cancel();
    _ctxChangedSub?.cancel();
    _streamSubscription?.cancel();
    _streamSubscription = null;
    try {
      final writers = List<_GatewayLogFileWriter>.from(
        _gatewayLogWritersByIndex.values,
      );
      _gatewayLogWritersByIndex.clear();
      for (final w in writers) {
        unawaited(w.close());
      }
    } catch (_) {}
    _gatewayLogFilePathByIndex.clear();
    _subagentListVersion.dispose();
    _uiPerf.dispose();
    super.dispose();
  }

  void _cancelStreamUiSubscription() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    final c = _streamLoopCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _streamLoopCompleter = null;
  }

  void _detachStreamingUiForBackground({
    required bool persistUiState,
    bool setUiStopped = true,
    bool finishThinkingBlock = true,
  }) {
    // Bump the epoch so any in-flight stream callbacks are ignored.
    _activeSendEpoch = 0;
    // Invalidate any queued UI history writes from this request so they can't
    // overwrite later service-level persistence after a conversation/page switch.
    _chatHistoryWriteEpoch++;
    final int? idx = _currentAssistantIndex;
    final String cid = (_inFlightConversationCid ?? '').trim();

    // Stop UI stream consumption; the underlying request may continue.
    _cancelStreamUiSubscription();
    _stopDots();
    _stopInFlightHistoryPersistence();
    // Stop mirroring gateway logs to file once the UI detaches.
    try {
      final writers = List<_GatewayLogFileWriter>.from(
        _gatewayLogWritersByIndex.values,
      );
      _gatewayLogWritersByIndex.clear();
      for (final w in writers) {
        unawaited(w.close());
      }
    } catch (_) {}

    // Optionally mark the active thinking block finished. When detaching due to
    // a page/conversation switch we keep it "loading" so restore can still
    // reflect in-progress background generation.
    if (finishThinkingBlock &&
        idx != null &&
        idx >= 0 &&
        idx < _messages.length) {
      _finishActiveThinkingBlock(idx);
    }

    // Snapshot the current UI messages immediately. The caller may clear/replace
    // `_messages` right after detaching (e.g. conversation switch), so the
    // async persistence task must not read live mutable state.
    final List<AIMessage>? snapshotForPersist =
        (persistUiState && cid.isNotEmpty)
        ? _mergeReasoningForPersistence(List<AIMessage>.from(_messages))
        : null;

    if (snapshotForPersist != null) {
      // Avoid resurrecting deleted conversations: only persist if the row exists.
      final List<AIMessage> snapshot = snapshotForPersist;
      unawaited(() async {
        try {
          final row = await ScreenshotDatabase.instance.getAiConversationByCid(
            cid,
          );
          if (row == null) return;
          await _enqueueChatHistorySaveByCid(cid, snapshot);
        } catch (_) {}
      }());
    }

    // Clear local streaming flags so the UI isn't stuck in "thinking" state.
    if (mounted && setUiStopped) {
      setState(() {
        _sending = false;
        _inStreaming = false;
        _currentAssistantIndex = null;
        _restoredBackgroundInFlight = false;
      });
    } else {
      _sending = false;
      _inStreaming = false;
      _currentAssistantIndex = null;
      _restoredBackgroundInFlight = false;
    }
    _inFlightConversationCid = null;
  }

  _ThinkingBlock _ensureThinkingBlock(int assistantIdx) {
    final List<_ThinkingBlock> blocks = _thinkingBlocksByIndex.putIfAbsent(
      assistantIdx,
      () => <_ThinkingBlock>[],
    );
    if (blocks.isEmpty || !blocks.last.isLoading) {
      blocks.add(_ThinkingBlock(createdAt: DateTime.now()));
    }
    return blocks.last;
  }

  @override
  Widget build(BuildContext context) {
    final Widget bodyCore = _loading
        ? const Center(child: CircularProgressIndicator())
        : NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(child: SizedBox.shrink()),
            ],
            body: Column(
              children: [
                const SizedBox(height: AppTheme.spacing1),
                Expanded(child: _buildChatList()),
                _buildComposerBar(),
              ],
            ),
          );

    // 包裹全屏横向滑动手势（嵌入/独立模式均生效）
    final Widget body = _withDrawerSwipe(bodyCore);
    final Widget bodyWithPerf = Stack(
      children: [
        body,
        if (_showPerfOverlay)
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              bottom: false,
              child: UiPerfOverlay(
                logger: _uiPerf,
                onClear: () => _uiPerf.clear(restart: true),
                onClose: () {
                  _setState(() => _showPerfOverlay = false);
                  unawaited(_settings.setAiChatPerfOverlayEnabled(false));
                },
              ),
            ),
          ),
      ],
    );
    if (widget.embedded) return bodyWithPerf;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: widget.readOnly ? 56 : 96,
        leading: widget.readOnly
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : Builder(
                builder: (ctx) => Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu),
                      tooltip: AppLocalizations.of(context).actionMenu,
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                    const AIImageGenerationMenuButton(),
                  ],
                ),
              ),
        title: widget.readOnly
            ? _buildReadOnlyAppBarTitle(context)
            : Text(AppLocalizations.of(context).aiSettingsTitle),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        bottom: widget.readOnly
            ? _ReadOnlyConversationUsageBar(
                metaFuture: _readOnlyConversationMetaFuture,
              )
            : const ChatContextAppBarUsageBar(),
        actions: widget.readOnly
            ? const <Widget>[]
            : [
                const ChatContextAppBarAction(),
                IconButton(
                  tooltip: _showPerfOverlay
                      ? 'Hide perf overlay'
                      : 'Show perf overlay',
                  onPressed: () {
                    _setState(() => _showPerfOverlay = !_showPerfOverlay);
                    _uiPerf.log(
                      _showPerfOverlay
                          ? 'perfOverlay.show'
                          : 'perfOverlay.hide',
                    );
                    unawaited(
                      _settings.setAiChatPerfOverlayEnabled(_showPerfOverlay),
                    );
                  },
                  icon: Icon(
                    _showPerfOverlay
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                  ),
                ),
              ],
      ),
      drawer: widget.readOnly ? null : const AppSideDrawer(),
      drawerEnableOpenDragGesture: false, // 关闭默认边缘拖拽，改用自定义"任意位置"滑动
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: bodyWithPerf,
    );
  }
}

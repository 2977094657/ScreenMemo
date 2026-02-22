import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/ai_settings_service.dart';
import '../services/ai_chat_service.dart';
import '../services/chat_context_service.dart';
import '../widgets/ui_dialog.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/ai_providers_service.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/markdown_math.dart';
import '../widgets/app_side_drawer.dart';
import '../widgets/screenshot_image_widget.dart';
import '../services/app_selection_service.dart';
import '../services/intent_analysis_service.dart';
import '../services/query_context_service.dart';
import '../services/prompt_budget.dart';
import '../services/flutter_logger.dart';
import '../services/screenshot_database.dart';
import '../services/nsfw_preference_service.dart';
import '../services/ui_perf_logger.dart';
import '../widgets/chat_context_sheet.dart';
import '../widgets/ai_request_logs_action.dart';
import '../widgets/ai_request_logs_viewer.dart';
import '../widgets/ai_request_logs_sheet.dart';
import '../widgets/ui_perf_overlay.dart';

part 'ai_settings/ai_settings_page_state_core.dart';
part 'ai_settings/ai_settings_page_state_send_message.dart';
part 'ai_settings/ai_settings_page_state_thinking_codec.dart';
part 'ai_settings/ai_settings_page_state_chat_list.dart';
part 'ai_settings/ai_settings_page_widgets.dart';

// Thinking/Reasoning content should be visually distinct from the final answer.
const Color _thinkingTextColor = Color(0xFF71717A);
// Warm "platinum/white-gold" shimmer highlight used while thinking.
const Color _thinkingShimmerHighlightColor = Color(0xFFFFFBEB);

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

enum _ThinkingEventType { status, intent, tools }

class _ThinkingToolChip {
  _ThinkingToolChip({
    required this.callId,
    required this.toolName,
    required this.label,
    this.appNames = const <String>[],
    this.appPackageNames = const <String>[],
    this.active = true,
    this.resultSummary,
  });

  final String callId;
  final String toolName;
  final String label;
  List<String> appNames;
  List<String> appPackageNames;
  bool active;
  String? resultSummary;
}

class _ThinkingEvent {
  _ThinkingEvent({
    required this.type,
    required this.title,
    this.subtitle,
    this.icon,
    this.active = false,
    this.tools = const <_ThinkingToolChip>[],
  });

  final _ThinkingEventType type;
  String title;
  String? subtitle;
  IconData? icon;
  bool active; // shimmer when active=true
  final List<_ThinkingToolChip> tools;
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
  const AISettingsPage({super.key, this.embedded = false});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage>
    with SingleTickerProviderStateMixin {
  static const double _inputRowHeight = 40.0;
  final AISettingsService _settings = AISettingsService.instance;
  final AIChatService _chat = AIChatService.instance;

  // In-page perf timeline for troubleshooting slow image render on chat page.
  final UiPerfLogger _uiPerf = UiPerfLogger(scope: 'AIChat');
  // Controlled by Settings > Advanced. Defaults to hidden to avoid noisy UI.
  bool _showPerfOverlay = false;
  final Set<String> _perfLoggedMarkdownMsgKeys = <String>{};

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _inputController = TextEditingController();

  // 聊天列表滚动控制器（用于自动滚动到底部）
  final ScrollController _chatScrollController = ScrollController();
  // 折叠思考预览的滚动（底部面板）
  final ScrollController _reasoningPanelScrollController = ScrollController();

  // —— 粘底自动滚动策略 ——
  // 当距离底部在该阈值内，才会触发自动滚动（避免与用户滚动竞争）
  static const double _autoScrollProximity = 120.0;
  // 当前是否应粘在底部（由滚动通知动态维护）
  bool _stickToBottom = true;
  // 自动滚动节流：在短时间内合并多次请求，减少 jumpTo 频次
  static const int _autoScrollThrottleMs = 120;
  DateTime? _lastAutoScrollTime;
  bool _autoScrollPending = false;

  // 动态省略号（思考中）状态
  Timer? _dotsTimer;
  String _thinkingDots = '';

  Timer? _inFlightSaveTimer;
  bool _inFlightHistoryDirty = false;
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
  // Monotonic token for the currently active send/stream loop. Changing this
  // detaches the UI from an in-flight background request.
  int _sendEpoch = 0;
  int _activeSendEpoch = 0;
  Completer<void>? _streamLoopCompleter;
  bool _connExpanded = false;
  bool _groupSelectorVisible = true;
  bool _promptExpanded = false;

  // ——— AI 交互样式与流式状态（仅影响本页 UI，不改动全局样式） ———
  bool _deepThinking = false; // "深度思考"开关（先做样式，后续可接推理参数）
  bool _webSearch = false; // "联网搜索"开关（先做样式，后续可接搜索参数）
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
  // 每条助手消息的正文分段（用于 思考块/正文 交替展示）
  final Map<int, List<String>> _contentSegmentsByIndex = <int, List<String>>{};
  // 标记下一次 content 增量是否需要开启一个新分段
  final Map<int, bool> _nextContentStartsNewSegmentByIndex = <int, bool>{};
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
  final Map<String, Future<Map<String, String>>> _evidenceResolveFutures =
      <String, Future<Map<String, String>>>{};
  bool _evidenceRebuildScheduled = false;
  // 上一轮意图结果（用于为下一轮提供 prev hint）
  IntentResult? _lastIntent;
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
  // 输入框展开状态（默认单行，自适应随内容增高）
  bool _inputExpanded = false;

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

  void _setState(VoidCallback fn) => setState(fn);

  Future<void> _loadPerfOverlayEnabled() async {
    try {
      final bool enabled = await _settings.getAiChatPerfOverlayEnabled();
      if (!mounted) return;
      setState(() => _showPerfOverlay = enabled);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _uiPerf.clear(restart: true);
    _uiPerf.log('page.initState');
    unawaited(_loadPerfOverlayEnabled());
    // 预加载图标清单，确保首屏动态图标匹配生效
    ModelIconUtils.preload();
    _loadAll();
    _loadChatContextSelection();
    _ctxChangedSub = AISettingsService.instance.onContextChanged.listen((ctx) {
      if (!mounted) return;
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
        if (_sending || _inStreaming) return;
        _ctxDebounceTimer?.cancel();
        _ctxDebounceTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          _loadAll();
        });
        return;
      }
      if (ctx == 'chat' || ctx == 'chat:deleted' || ctx == 'chat:cleared') {
        final bool isDeletedOrCleared =
            (ctx == 'chat:deleted' || ctx == 'chat:cleared');
        // When the active conversation changes mid-stream, detach the UI from the
        // in-flight request and immediately reload the new conversation.
        if (_sending || _inStreaming) {
          _detachStreamingUiForBackground(
            persistUiState: !isDeletedOrCleared,
            // Keep the persisted thinking block "loading" so returning to the
            // conversation can still show it as in-progress while the request
            // completes in background.
            finishThinkingBlock: false,
          );
        }
        // When switching conversations (normal 'chat' event), clear the chat UI
        // immediately so we don't keep showing the old conversation while the
        // async reload is still in flight. (`chat` is also emitted for model
        // changes, so we only clear if the active CID actually changed.)
        if (ctx == 'chat') {
          unawaited(() async {
            String newCid = '';
            try {
              newCid = (await _settings.getActiveConversationCid()).trim();
            } catch (_) {
              newCid = '';
            }
            if (!mounted) return;
            final String oldCid = (_activeConversationCid ?? '').trim();
            if (newCid.isNotEmpty && newCid != oldCid) {
              // Best-effort: close any in-flight gateway log writers before
              // wiping UI state so file descriptors are not leaked.
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
                _activeConversationCid = newCid;
                _loading = true;
                _messages = <AIMessage>[];
                _olderBeforeId = null;
                _olderHasMore = false;
                _olderLoading = false;
                _attachmentsByIndex.clear();
                _evidenceResolvedByMsgKey.clear();
                _evidenceResolveFutures.clear();
                _evidenceScreenshotByPath.clear();
                _evidenceNsfwRequestedPaths.clear();
                _evidenceNsfwPreloadFuture = null;
                _reasoningByIndex.clear();
                _gatewayLogsByIndex.clear();
                _reasoningDurationByIndex.clear();
                _thinkingBlocksByIndex.clear();
                _contentSegmentsByIndex.clear();
                _nextContentStartsNewSegmentByIndex.clear();
                _currentAssistantIndex = null;
                _inStreaming = false;
                _sending = false;
                _clarifyState = null;
              });
              _stopInFlightHistoryPersistence();
              _stopDots();
            } else if (oldCid.isEmpty && newCid.isNotEmpty) {
              // Keep the cached CID in sync for stable "send" semantics.
              _activeConversationCid = newCid;
            }
          }());
        }
        // 若是删除事件，先立即清空当前对话UI，避免等待重载造成的"空白延迟"
        if (ctx == 'chat:deleted' || ctx == 'chat:cleared') {
          // Close any open log writers tied to the previous conversation.
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
          setState(() {
            _messages = <AIMessage>[];
            _olderBeforeId = null;
            _olderHasMore = false;
            _olderLoading = false;
            _attachmentsByIndex.clear();
            _evidenceResolvedByMsgKey.clear();
            _evidenceResolveFutures.clear();
            _evidenceScreenshotByPath.clear();
            _evidenceNsfwRequestedPaths.clear();
            _evidenceNsfwPreloadFuture = null;
            _reasoningByIndex.clear();
            _gatewayLogsByIndex.clear();
            _reasoningDurationByIndex.clear();
            _thinkingBlocksByIndex.clear();
            _contentSegmentsByIndex.clear();
            _nextContentStartsNewSegmentByIndex.clear();
            _currentAssistantIndex = null;
            _inStreaming = false;
            _sending = false;
            _clarifyState = null;
          });
          _stopInFlightHistoryPersistence();
          _stopDots();
        }
        // 去抖 250ms 合并多次事件，避免重复重载
        _ctxDebounceTimer?.cancel();
        _ctxDebounceTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          _loadChatContextSelection();
          _loadAll();
        });
      }
    });
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
    _inputController.dispose();
    _promptSegmentController.dispose();
    _promptMergeController.dispose();
    _promptDailyController.dispose();
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
      });
    } else {
      _sending = false;
      _inStreaming = false;
      _currentAssistantIndex = null;
    }
    _inFlightConversationCid = null;
  }

  _ThinkingEvent? _findEvent(
    _ThinkingBlock block,
    _ThinkingEventType type,
    String title,
  ) {
    for (final e in block.events) {
      if (e.type == type && e.title == title) return e;
    }
    return null;
  }

  _ThinkingEvent _upsertEvent(
    _ThinkingBlock block, {
    required _ThinkingEventType type,
    required String title,
    IconData? icon,
    bool active = false,
    String? subtitle,
    List<_ThinkingToolChip>? tools,
  }) {
    final _ThinkingEvent? existing = _findEvent(block, type, title);
    if (existing != null) {
      existing.icon = icon ?? existing.icon;
      existing.active = active;
      existing.subtitle = subtitle;
      return existing;
    }
    final _ThinkingEvent created = _ThinkingEvent(
      type: type,
      title: title,
      subtitle: subtitle,
      icon: icon,
      active: active,
      tools: tools ?? const <_ThinkingToolChip>[],
    );
    block.events.add(created);
    return created;
  }

  _ThinkingBlock _ensureThinkingBlock(int assistantIdx) {
    final List<_ThinkingBlock> blocks = _thinkingBlocksByIndex.putIfAbsent(
      assistantIdx,
      () => <_ThinkingBlock>[],
    );
    if (blocks.isEmpty || !blocks.last.isLoading) {
      final DateTime createdAt = DateTime.now();
      blocks.add(_ThinkingBlock(createdAt: createdAt));
      // 新思考块开启后，下一次 content 应当进入一个新分段（用于 思考块/正文 交替）
      _nextContentStartsNewSegmentByIndex[assistantIdx] = true;
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacing4,
                    AppTheme.spacing2,
                    AppTheme.spacing4,
                    AppTheme.spacing4,
                  ),
                  child: _buildComposerBar(),
                ),
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
    if (widget.embedded) {
      return bodyWithPerf;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).aiSettingsTitle),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        bottom: const ChatContextAppBarUsageBar(),
        actions: [
          const ChatContextAppBarAction(),
          IconButton(
            tooltip: _showPerfOverlay
                ? 'Hide perf overlay'
                : 'Show perf overlay',
            onPressed: () {
              _setState(() => _showPerfOverlay = !_showPerfOverlay);
              _uiPerf.log(
                _showPerfOverlay ? 'perfOverlay.show' : 'perfOverlay.hide',
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
      drawer: const AppSideDrawer(),
      drawerEnableOpenDragGesture: false, // 关闭默认边缘拖拽，改用自定义"任意位置"滑动
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: bodyWithPerf,
    );
  }
}

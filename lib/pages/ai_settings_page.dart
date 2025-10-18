import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/ai_settings_service.dart';
import '../services/ai_chat_service.dart';
import '../widgets/ui_dialog.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/ai_providers_service.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/markdown_math.dart';
import '../widgets/reasoning_card.dart';
import '../widgets/app_side_drawer.dart';
import '../widgets/screenshot_image_widget.dart';
import '../services/intent_analysis_service.dart';
import '../services/query_context_service.dart';
import '../services/flutter_logger.dart';
import '../services/screenshot_database.dart';

/// AI 设置与测试页面：配置 OpenAI 兼容接口并进行多轮聊天测试
class AISettingsPage extends StatefulWidget {
  final bool embedded;
  const AISettingsPage({super.key, this.embedded = false});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> with SingleTickerProviderStateMixin {
  static const double _inputRowHeight = 40.0;
  final AISettingsService _settings = AISettingsService.instance;
  final AIChatService _chat = AIChatService.instance;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _inputController = TextEditingController();

  // 聊天列表滚动控制器（用于自动滚动到底部）
  final ScrollController _chatScrollController = ScrollController();
  // 折叠思考预览的滚动（底部面板）
  final ScrollController _reasoningPanelScrollController = ScrollController();

  // 动态省略号（思考中）状态
  Timer? _dotsTimer;
  String _thinkingDots = '';

  List<AIMessage> _messages = <AIMessage>[];
  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  bool _streamEnabled = true;
  StreamSubscription<AIStreamEvent>? _streamSubscription;
  bool _connExpanded = false;
  bool _groupSelectorVisible = true;
  bool _promptExpanded = false;

  // ——— AI 交互样式与流式状态（仅影响本页 UI，不改动全局样式） ———
  // 自我模式：开启后走意图分析+上下文检索流程；关闭则为普通对话
  bool _selfMode = false;
  bool _deepThinking = false; // "深度思考"开关（先做样式，后续可接推理参数）
  bool _webSearch = false;    // "联网搜索"开关（先做样式，后续可接搜索参数）
  bool _inStreaming = false;  // 当前是否处于助手流式回复中（驱动"思考中"可视化）
  // 实时"思考过程"内容（仅当前流式过程显示）
  String _thinkingText = '';
  bool _showThinkingContent = false;
  // 每条助手消息的思考内容缓存（索引 -> 文本）
  final Map<int, String> _reasoningByIndex = <int, String>{};
  // 每条助手消息的最终思考耗时（索引 -> 时长）
  final Map<int, Duration> _reasoningDurationByIndex = <int, Duration>{};
  // 当前流式助手消息的索引
  int? _currentAssistantIndex;
  // 是否在下一条 content token 到来时，清空占位内容（用于"阶段状态" -> 最终回答的替换）
  bool _replaceAssistantContentOnNextToken = false;
  // 每条助手消息附带的证据图片（索引 -> 附件列表）
  final Map<int, List<EvidenceImageAttachment>> _attachmentsByIndex = <int, List<EvidenceImageAttachment>>{};
  // 上一轮自我模式使用的上下文包（用于后续消息在 AI 判定时可复用）
  QueryContextPack? _lastCtxPack;
  // 上一轮意图结果（用于为下一轮提供 prev hint）
  IntentResult? _lastIntent;
  // 提示词管理
  String? _promptSegment;
  String? _promptMerge;
  String? _promptDaily;
  final TextEditingController _promptSegmentController = TextEditingController();
  final TextEditingController _promptMergeController = TextEditingController();
  final TextEditingController _promptDailyController = TextEditingController();
  bool _editingPromptSegment = false;
  bool _editingPromptMerge = false;
  bool _editingPromptDaily = false;
  bool _savingPromptSegment = false;
  bool _savingPromptMerge = false;
  bool _savingPromptDaily = false;

  // —— 全屏横向滑动呼出 Drawer ——
  double _drawerGestureAccumDx = 0.0;
  bool _drawerGestureTriggered = false;
  Widget _withDrawerSwipe(Widget child) {
    // 在任意位置从左向右滑动达到一定阈值后，打开上层 Scaffold 的 Drawer
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _drawerGestureAccumDx = 0.0;
        _drawerGestureTriggered = false;
      },
      onHorizontalDragUpdate: (details) {
        if (_drawerGestureTriggered) return;
        final double dx = (details.primaryDelta ?? details.delta.dx);
        if (dx > 0) {
          _drawerGestureAccumDx += dx;
        } else {
          // 向左滑动重置累计，避免误触
          _drawerGestureAccumDx = 0.0;
        }
        // 触发阈值（约 56 像素），避免轻微抖动误开
        if (_drawerGestureAccumDx >= 56.0) {
          final scaffold = Scaffold.maybeOf(context);
          if (scaffold != null && !scaffold.isDrawerOpen) {
            FocusScope.of(context).unfocus();
            scaffold.openDrawer();
          }
          _drawerGestureTriggered = true;
        }
      },
      onHorizontalDragEnd: (_) {
        _drawerGestureAccumDx = 0.0;
        _drawerGestureTriggered = false;
      },
      onHorizontalDragCancel: () {
        _drawerGestureAccumDx = 0.0;
        _drawerGestureTriggered = false;
      },
      child: child,
    );
  }

  // —— 基于提供商表的对话上下文（chat 专用） ——
  AIProvider? _ctxChatProvider;
  String? _ctxChatModel;
  bool _ctxLoading = true;
  StreamSubscription<String>? _ctxChangedSub;
  Timer? _ctxDebounceTimer;
  bool _loadingAllInFlight = false;
  // 底部弹窗查询输入持久化，避免键盘开合导致重建清空
  String _providerQueryText = '';
  String _modelQueryText = '';
  // 输入框展开状态（默认单行，自适应随内容增高）
  bool _inputExpanded = false;

  // 提供近期“仅用户消息”的文本，用于意图分析器判断是否续问
  List<String> _extractPreviousUserQueries({int maxCount = 3}) {
    if (_messages.isEmpty) return const <String>[];
    final List<String> out = <String>[];
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'user') {
        final c = m.content.trim();
        if (c.isNotEmpty) out.add(c);
        if (out.length >= maxCount) break;
      }
    }
    return out;
  }

  // 默认提示词预览（按当前语言返回）
  String get _defaultSegmentPromptPreview {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final isZh = code.startsWith('zh');
    if (isZh) {
      return '''
请基于以下多张屏幕图片进行中文总结，并输出结构化结果；必须严格遵循：
- 禁止使用OCR文本；直接理解图片内容；
- 不要逐图描述；按应用/主题整合用户在该时间段的'行为总结'（浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等）；
- 对视频标题、作者、品牌等独特信息，按屏幕原样在输出中保留；
- 对同一文章/视频/页面的连续图片，归为同一 content_group 做整体总结；
- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现"## 概览"或"## 总结"等）；随后再使用 Markdown 小节呈现后续内容；
- Markdown 要求：所有"用于展示的文本字段"须使用 Markdown（overall_summary 与 content_groups[].summary；timeline[].summary 可用简短 Markdown；key_actions[].detail 可用精简 Markdown）；禁止使用代码块围栏（例如 ```），仅输出纯 Markdown 文本；
- 后续小节建议包含："## 关键操作"（按时间的要点清单）、"## 主要活动"（按应用/主题的要点清单）、"## 重点内容"（可保留的标题/作者/品牌等）；
- 在"## 关键操作"中，将相邻/连续同类行为合并为区间，格式"HH:mm:ss-HH:mm:ss：行为描述"（例如"08:16:41-08:27:21：浏览视频评论"）；仅在行为中断或切换时新起一条；控制 3-8 条精要；
- content_groups[].summary 使用 1-3 条 Markdown 要点呈现该组主题/代表性标题/阅读或观看意图；
以 JSON 输出以下字段（不要省略字段名）：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary；
- 仅输出一个 JSON 对象，不要附加解释或 JSON 外的 Markdown；所有展示性内容（含后续小节）请写入 overall_summary 字段的 Markdown；
字段约定（示例说明格式，非固定内容）：
- key_actions[]: [{ "type": "...", "app": "应用名", "ref_image": "文件名", "ref_time": "HH:mm:ss", "detail": "(Markdown) 精简说明", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "可为空", "app": "应用名", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["文件名1"], "summary": "(Markdown) 本组内容要点" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "应用名", "action": "浏览|观看|聊天|购物|搜索|编辑|游戏|设置|下载|分享|其他", "summary": "(Markdown) 一句话行为（可简短强调）" }]
- overall_summary: "(Markdown) 开头是一段无标题的总结段落，随后使用小节与要点，避免流水账并尽可能保留信息"
''';
    } else {
      return '''
Please summarize multiple screenshots in English and output structured results. STRICT rules:
- Do NOT use OCR text; understand images directly.
- Do not describe image-by-image; integrate a "behavior summary" over the time window by app/topic (browse/watch/chat/shop/work/settings/download/share/game, etc.).
- Preserve unique on-screen info like video titles, authors, brands as-is.
- Consecutive images from the same article/video/page should be merged into one content_group for a holistic summary.
- Start with one plain paragraph (no heading) summarizing the time window; then present later content with Markdown subsections.
- Markdown requirements: all display texts must use Markdown (overall_summary and content_groups[].summary; timeline[].summary may use brief Markdown; key_actions[].detail may use concise Markdown). NO code fences (```), only pure Markdown.
- overall_summary MUST include exactly these three second-level sections in this fixed order:
  "## Key Actions"
  "## Main Activities"
  "## Key Content"
  Each section MUST contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet. Do not omit or rename sections.
- In "## Key Actions", merge adjacent/continuous same-type actions as a time range "HH:mm:ss-HH:mm:ss: description"; only start a new item when action breaks/changes; keep 3–8 concise items.
- content_groups[].summary: 1–3 Markdown bullets describing group topic/representative titles/intent.
JSON fields to output (do not omit field names): apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.
- Output exactly ONE JSON object; no explanations or Markdown outside JSON. Put all display content (including sections) in overall_summary (Markdown).
Field conventions (examples, not fixed):
- key_actions[]: [{ "type": "...", "app": "App", "ref_image": "file", "ref_time": "HH:mm:ss", "detail": "(Markdown) brief", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "optional", "app": "App", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["file1"], "summary": "(Markdown) group highlights" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "App", "action": "browse|watch|chat|shop|search|edit|game|settings|download|share|other", "summary": "(Markdown) one-liner (may emphasize briefly)" }]
- overall_summary: "(Markdown) start with a single untitled paragraph; then sections with bullets; avoid narration; retain key info"
''';
    }
  }

  String get _defaultMergePromptPreview {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final isZh = code.startsWith('zh');
    if (isZh) {
      return '''
请基于以下图片产出合并后的总结；必须遵循以下规则（中文输出，结构化JSON，行为导向，禁止逐图/禁止OCR）：
- 禁止使用OCR文本，直接理解图片内容；
- 不要对每张图片逐条描述；请产出用户在该时间段的'行为总结'，如 浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等，按应用或主题整合；
- 对包含视频标题、作者、品牌等独特信息，按屏幕原样保留；
- 对同一文章/视频/页面的连续图片，归为同一 content_group，做整体总结；
- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现"## 概览"或"## 总结"等）；随后再使用 Markdown 小节呈现后续内容；
- Markdown 要求：所有"用于展示的文本字段"须使用 Markdown（overall_summary 与 content_groups[].summary），用小标题与项目符号清晰呈现；禁止输出 Markdown 代码块标记（如 ```），仅纯 Markdown 文本；
- 后续小节建议包含："## 关键操作"、"## 主要活动"、"## 重点内容"；
- 在"## 关键操作"中，将相邻/连续同类行为合并为区间，格式"HH:mm:ss-HH:mm:ss：行为描述"（例如"08:16:41-08:27:21：浏览视频评论"）；仅在行为中断或切换时新起一条；控制 3-8 条精要；
- content_groups[].summary 为 Markdown，使用 1-3 条要点列出该组主题/代表性标题/阅读或观看意图；
- 为尽可能保留信息，可在 Markdown 中使用无序/有序列表、加粗/斜体与内联代码高亮（但不要使用代码块）；
以 JSON 输出以下字段（与普通事件保持一致，不要省略字段名）：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary；
- 仅输出一个 JSON 对象，不要附加解释或 JSON 外的 Markdown；所有展示性内容（含后续小节）请写入 overall_summary 字段的 Markdown；
字段约定（示例说明格式，非固定内容）：
- key_actions[]: [{ "type": "...", "app": "应用名", "ref_image": "文件名", "ref_time": "HH:mm:ss", "detail": "简要说明（避免敏感信息）", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "可为空", "app": "应用名", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["文件名1"], "summary": "本组内容的Markdown要点" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "应用名", "action": "浏览|观看|聊天|购物|搜索|编辑|游戏|设置|下载|分享|其他", "summary": "一句话行为（可用简短Markdown强调）" }]
- overall_summary: "开头为无标题的一段总结，随后使用Markdown小节与要点，保留多事件合并后的关键信息"
''';
    } else {
      return '''
Please produce a merged summary for the following images. MUST follow (English output, structured JSON, behavior-focused, no per-image narration / no OCR):
- Do NOT use OCR; understand images directly.
- Do not describe each image; output a "behavior summary" over the period (browse/watch/chat/shop/work/settings/download/share/game, etc.), grouped by app/topic.
- Preserve unique on-screen info (video titles/authors/brands) as seen.
- Merge consecutive images from the same article/video/page into one content_group and summarize holistically.
- Start with one plain paragraph (no headings) summarizing the period; then present details using Markdown sections.
- Markdown requirements: all display texts use Markdown (overall_summary and content_groups[].summary); headings and bullet points for clarity; NO code fences (```), only pure Markdown.
- overall_summary MUST include exactly these three second-level sections in this fixed order:
  "## Key Actions"
  "## Main Activities"
  "## Key Content"
  Each section MUST contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet. Do not omit or rename sections.
- In "## Key Actions", merge adjacent same-type actions into ranges "HH:mm:ss-HH:mm:ss: description" (e.g., "08:16:41-08:27:21: reading video comments"); only new item when action breaks; keep 3–8 concise lines.
- content_groups[].summary uses 1–3 Markdown bullets for group topic/representative titles/intent.
- To retain info, you may use lists/bold/italic/inline code in Markdown (but NOT code blocks).
Output JSON fields (same as normal event): apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.
- Output exactly ONE JSON object; no explanations or Markdown outside JSON; all display content belongs to overall_summary (Markdown).
Field conventions (examples, not fixed):
- key_actions[]: [{ "type": "...", "app": "App", "ref_image": "file", "ref_time": "HH:mm:ss", "detail": "brief (avoid sensitive info)", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "optional", "app": "App", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["file1"], "summary": "Markdown bullets" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "App", "action": "browse|watch|chat|shop|search|edit|game|settings|download|share|other", "summary": "one-liner (may emphasize briefly)" }]
- overall_summary: "Untitled opening paragraph, then Markdown sections with bullets; keep merged multi-event highlights"
''';
    }
  }

  String get _defaultDailyPromptPreview {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final isZh = code.startsWith('zh');
    if (isZh) {
      return '''
请从今日采集的多段屏幕图片生成"每日总结"（中文输出）。必须严格遵循：
- 忽略输入/上下文语言，严格使用当前应用语言输出；本次为中文。
- 禁止使用 OCR 文本；直接从图片语义推断。
- 先输出一段无标题的总览段落；随后用 Markdown 小节呈现细节。
- Markdown 要求：展示类文本必须用 Markdown；禁止代码块围栏（如 ```）；仅输出纯 Markdown。
- 概览后必须按固定顺序包含以下二级小节：
  "## 关键操作"
  "## 主要活动"
  "## 重点内容"
  每个小节至少 3 条以 "- " 开头的要点；信息不足也要保留小节并给出有意义的占位要点。
- 将相邻/连续同类行为合并为时间区间 "HH:mm:ss-HH:mm:ss：描述"；仅在行为中断/切换时新起一条；控制 5–12 条精要。
- content_groups[].summary 使用 1–3 条要点，概述主题/代表性标题/意图。
仅输出一个 JSON 对象，包含字段：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary。
- 不要添加解释或 JSON 之外的 Markdown；所有展示性内容（含小节）写入 overall_summary 的 Markdown。
''';
    } else {
      return '''
Please generate a "daily summary" in English from multiple screenshot segments captured today. STRICT rules:
- Ignore the language used in inputs/context and always respond in the app's current language; for this run, use English.
- Do NOT use OCR text; infer directly from image semantics.
- Start with one plain paragraph (no heading) as an overview; then present details with Markdown subsections.
- Markdown requirements: all display texts must be Markdown; NO code fences (```), only pure Markdown.
- After the overview, include exactly these second-level sections in the fixed order:
  "## Key Actions"
  "## Main Activities"
  "## Key Content"
  Each section must contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet.
- Merge adjacent/continuous same-type actions into ranges "HH:mm:ss-HH:mm:ss: description"; only start a new item when action breaks/changes; keep 5–12 concise items.
- content_groups[].summary uses 1–3 Markdown bullets to describe group topic/representative titles/intent.
Output exactly ONE JSON object with fields: apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.
- Do not add explanations or any Markdown outside JSON; put all display content (including sections) into overall_summary (Markdown).
''';
    }
  }
  // 分组相关状态
  List<AISiteGroup> _groups = <AISiteGroup>[];
  int? _activeGroupId;

  @override
  void initState() {
    super.initState();
    // 预加载图标清单，确保首屏动态图标匹配生效
    ModelIconUtils.preload();
    _loadAll();
    _loadChatContextSelection();
    _ctxChangedSub = AISettingsService.instance.onContextChanged.listen((ctx) {
      if (!mounted) return;
      if (ctx == 'chat' || ctx == 'chat:deleted') {
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
    _ctxDebounceTimer?.cancel();
    _ctxChangedSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final sw = Stopwatch()..start();
    try {
      if (_loadingAllInFlight) return; // 防止重入触发的重复加载
      _loadingAllInFlight = true;
      // 并行预取，避免串行等待造成的累计时延
      final Future<List<AISiteGroup>> fGroups = _settings.listSiteGroups();
      final Future<int?> fActiveId = _settings.getActiveGroupId();
      final Future<List<AIMessage>> fHistory = _settings.getChatHistory();
      final Future<bool> fStreamEnabled = _settings.getStreamEnabled();
      final Future<String?> fSegPrompt = _settings.getPromptSegment();
      final Future<String?> fMergePrompt = _settings.getPromptMerge();
      final Future<String?> fDailyPrompt = _settings.getPromptDaily();
      final Future<String> fBaseUrl = _settings.getBaseUrl();
      // 读取密钥设置超时，避免拖慢首屏（超时则稍后用户手动查看/编辑）
      final Future<String?> fApiKey = _settings.getApiKey().timeout(const Duration(milliseconds: 600), onTimeout: () => null);
      final Future<String> fModel = _settings.getModel();

      // 先拿到分组与激活ID
      final List<AISiteGroup> groups = await fGroups;
      final int? activeId = await fActiveId;

      // 基础配置：若存在激活分组，则优先使用分组中的值；否则使用未分组键值
      String baseUrl;
      String? apiKey;
      String model;
      if (activeId != null) {
        final g = await _settings.getSiteGroupById(activeId);
        baseUrl = g?.baseUrl ?? await fBaseUrl;
        apiKey = g?.apiKey ?? await fApiKey;
        model = g?.model ?? await fModel;
      } else {
        baseUrl = await fBaseUrl;
        apiKey = await fApiKey;
        model = await fModel;
      }

      // 收集其余预取结果
      final List<AIMessage> history = await fHistory;
      final bool streamEnabled = await fStreamEnabled;
      final String? segPrompt = await fSegPrompt;
      final String? mergePrompt = await fMergePrompt;
      final String? dailyPrompt = await fDailyPrompt;

      // 回填历史消息的深度思考内容与耗时（索引映射到消息）
      final Map<int, String> rb = <int, String>{};
      final Map<int, Duration> rd = <int, Duration>{};
      for (int i = 0; i < history.length; i++) {
        final m = history[i];
        if (m.role != 'user') {
          final String? rc = m.reasoningContent;
          if (rc != null && rc.trim().isNotEmpty) rb[i] = rc;
          final Duration? dur = m.reasoningDuration;
          if (dur != null && dur.inMilliseconds > 0) rd[i] = dur;
        }
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _activeGroupId = activeId;

        // 未分组：默认值隐藏；分组：直接填充实际值
        if (activeId == null) {
          _baseUrlController.text = (baseUrl == 'https://api.openai.com') ? '' : baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = (model == 'gpt-4o-mini') ? '' : model;
        } else {
          _baseUrlController.text = baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = model;
        }

        // 分批填充消息，降低单帧构建压力
        _messages = <AIMessage>[];
        _reasoningByIndex
          ..clear()
          ..addAll(rb);
        _reasoningDurationByIndex
          ..clear()
          ..addAll(rd);
        _streamEnabled = streamEnabled;
        _promptSegment = segPrompt;
        _promptMerge = mergePrompt;
        _promptDaily = dailyPrompt;
        // 预填编辑器（若无自定义，按当前语言填充默认预览，方便直接修改）
        _promptSegmentController.text = (_promptSegment == null || _promptSegment!.trim().isEmpty)
            ? _defaultSegmentPromptPreview
            : _promptSegment!;
        _promptMergeController.text = (_promptMerge == null || _promptMerge!.trim().isEmpty)
            ? _defaultMergePromptPreview
            : _promptMerge!;
        _promptDailyController.text = (_promptDaily == null || _promptDaily!.trim().isEmpty)
            ? _defaultDailyPromptPreview
            : _promptDaily!;
        _loading = false;
      });
      if (mounted) {
        // 将消息分批追加到列表，避免一次性构建大量 Markdown
        const int batch = 24;
        for (int i = 0; i < history.length; i += batch) {
          final int end = (i + batch > history.length) ? history.length : (i + batch);
          final List<AIMessage> slice = history.sublist(i, end);
          final bool isLast = end >= history.length;
          // 逐批在微任务中追加，释放主帧
          scheduleMicrotask(() {
            if (!mounted) return;
            setState(() {
              _messages.addAll(slice);
            });
            if (isLast) {
              _scrollToBottom(animated: true);
            }
          });
        }
      }
      // 记录 UI 填充耗时（数据到状态）
      try { await FlutterLogger.nativeInfo('UI', 'AISettings._loadAll setState ms='+sw.elapsedMilliseconds.toString()); } catch (_) {}
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    } finally {
      _loadingAllInFlight = false;
    }
    // 首帧绘制完成耗时（状态更新到绘制）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try { await FlutterLogger.nativeInfo('UI', 'AISettings._loadAll first-frame ms='+sw.elapsedMilliseconds.toString()); } catch (_) {}
    });
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    setState(() { _saving = true; });
    try {
      final base = _baseUrlController.text.trim();
      final key = _apiKeyController.text.trim();
      final model = _modelController.text.trim();

      final gid = _activeGroupId;
      if (gid != null) {
        // 更新当前分组
        final g = await _settings.getSiteGroupById(gid);
        if (g == null) {
          UINotifier.error(context, AppLocalizations.of(context).groupNotFound);
        } else {
          final updated = g.copyWith(
            baseUrl: base.isEmpty ? g.baseUrl : base,
            apiKey: key.isEmpty ? null : key,
            model: model.isEmpty ? g.model : model,
          );
          await _settings.updateSiteGroup(updated);
          UINotifier.success(context, AppLocalizations.of(context).savedCurrentGroupToast);
        }
      } else {
        // 未分组：保存到键值
        await _settings.setBaseUrl(base);
        await _settings.setApiKey(key.isEmpty ? null : key);
        await _settings.setModel(model);
        UINotifier.success(context, AppLocalizations.of(context).saveSuccess);
      }
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  // ======= 提示词管理 =======
  Widget _buildPromptManagerCard() {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    Widget buildSection({
      required String label,
      required String currentMarkdown,
      required bool editing,
      required TextEditingController controller,
      required VoidCallback onEditToggle,
      required Future<void> Function() onSave,
      required Future<void> Function() onReset,
      required bool saving,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: titleStyle),
              const Spacer(),
              if (!editing)
                TextButton(
                  onPressed: onEditToggle,
                  child: Text(AppLocalizations.of(context).actionEdit),
                )
              else ...[
                TextButton(
                  onPressed: saving ? null : onSave,
                  child: Text(saving ? AppLocalizations.of(context).savingLabel : AppLocalizations.of(context).actionSave),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onReset,
                  child: Text(AppLocalizations.of(context).resetToDefault),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onEditToggle,
                  child: Text(AppLocalizations.of(context).dialogCancel),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          if (!editing)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              padding: const EdgeInsets.all(AppTheme.spacing3),
              child: MarkdownBody(
                data: currentMarkdown,
                styleSheet: _mdStyle(context),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: TextField(
                controller: controller,
                minLines: 6,
                maxLines: 24,
                style: Theme.of(context).textTheme.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(AppTheme.spacing2),
                ),
              ),
            ),
          const SizedBox(height: AppTheme.spacing3),
        ],
      );
    }

   final segMarkdown = (_promptSegment == null || _promptSegment!.trim().isEmpty)
       ? _defaultSegmentPromptPreview
       : _promptSegment!;
   final mergeMarkdown = (_promptMerge == null || _promptMerge!.trim().isEmpty)
       ? _defaultMergePromptPreview
       : _promptMerge!;
   final dailyMarkdown = (_promptDaily == null || _promptDaily!.trim().isEmpty)
       ? _defaultDailyPromptPreview
       : _promptDaily!;

    return UICard(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 折叠标题（点击展开/收起）
          GestureDetector(
            onTap: () => setState(() { _promptExpanded = !_promptExpanded; }),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context).promptManagerTitle, style: titleStyle),
                      const SizedBox(height: 2),
                      Text(
                        _buildPromptSummary(),
                        style: hintStyle,
                      ),
                    ],
                  ),
                ),
                Icon(_promptExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (_promptExpanded) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(AppLocalizations.of(context).promptManagerHint, style: hintStyle),
            const SizedBox(height: AppTheme.spacing3),

            // 普通事件提示词
            buildSection(
              label: AppLocalizations.of(context).normalEventPromptLabel,
              currentMarkdown: segMarkdown,
              editing: _editingPromptSegment,
              controller: _promptSegmentController,
              onEditToggle: () => setState(() => _editingPromptSegment = !_editingPromptSegment),
              onSave: _savePromptSegment,
              onReset: _resetPromptSegment,
              saving: _savingPromptSegment,
            ),

            // 合并事件提示词
            buildSection(
              label: AppLocalizations.of(context).mergeEventPromptLabel,
              currentMarkdown: mergeMarkdown,
              editing: _editingPromptMerge,
              controller: _promptMergeController,
              onEditToggle: () => setState(() => _editingPromptMerge = !_editingPromptMerge),
              onSave: _savePromptMerge,
              onReset: _resetPromptMerge,
              saving: _savingPromptMerge,
            ),
         // 每日总结提示词
         buildSection(
           label: AppLocalizations.of(context).dailySummaryPromptLabel,
           currentMarkdown: dailyMarkdown,
           editing: _editingPromptDaily,
           controller: _promptDailyController,
           onEditToggle: () => setState(() => _editingPromptDaily = !_editingPromptDaily),
           onSave: _savePromptDaily,
           onReset: _resetPromptDaily,
           saving: _savingPromptDaily,
         ),
       ],
     ],
   ),
 );
}

 Future<void> _savePromptSegment() async {
    if (_savingPromptSegment) return;
    setState(() => _savingPromptSegment = true);
    try {
      final v = _promptSegmentController.text.trim();
      await _settings.setPromptSegment(v.isEmpty ? null : v);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptSegment = false);
        UINotifier.success(context, AppLocalizations.of(context).savedNormalPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _resetPromptSegment() async {
    if (_savingPromptSegment) return;
    setState(() => _savingPromptSegment = true);
    try {
      await _settings.setPromptSegment(null);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptSegment = false);
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _savePromptMerge() async {
    if (_savingPromptMerge) return;
    setState(() => _savingPromptMerge = true);
    try {
      final v = _promptMergeController.text.trim();
      await _settings.setPromptMerge(v.isEmpty ? null : v);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptMerge = false);
        UINotifier.success(context, AppLocalizations.of(context).savedMergePromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptMerge = false);
    }
  }

  Future<void> _resetPromptMerge() async {
    if (_savingPromptMerge) return;
    setState(() => _savingPromptMerge = true);
    try {
      await _settings.setPromptMerge(null);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptMerge = false);
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptMerge = false);
    }
  }

 Future<void> _savePromptDaily() async {
   if (_savingPromptDaily) return;
   setState(() => _savingPromptDaily = true);
   try {
     final v = _promptDailyController.text.trim();
     await _settings.setPromptDaily(v.isEmpty ? null : v);
     await _loadAll();
     if (mounted) {
       setState(() => _editingPromptDaily = false);
       UINotifier.success(context, AppLocalizations.of(context).savedDailyPromptToast);
     }
   } catch (e) {
     if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
   } finally {
     if (mounted) setState(() => _savingPromptDaily = false);
   }
 }

 Future<void> _resetPromptDaily() async {
   if (_savingPromptDaily) return;
   setState(() => _savingPromptDaily = true);
   try {
     await _settings.setPromptDaily(null);
     await _loadAll();
     if (mounted) {
       setState(() => _editingPromptDaily = false);
       UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
     }
   } catch (e) {
     if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
   } finally {
     if (mounted) setState(() => _savingPromptDaily = false);
   }
 }

 Future<void> _clearHistory() async {
    try {
      await _chat.clearConversation();
      if (!mounted) return;
      setState(() { _messages = <AIMessage>[]; });
      UINotifier.success(context, AppLocalizations.of(context).clearSuccess);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).clearFailedWithError(e.toString()));
    }
  }

 // 自动滚动到底部（在下一帧执行，避免布局未完成）
 void _scrollToBottom({bool animated = true}) {
   final c = _chatScrollController;
   if (!c.hasClients) return;
   final pos = c.position.maxScrollExtent;
   if (animated) {
     c.animateTo(
       pos,
       duration: const Duration(milliseconds: 180),
       curve: Curves.easeOutCubic,
     );
   } else {
     c.jumpTo(pos);
   }
 }

 void _scheduleAutoScroll() {
   WidgetsBinding.instance.addPostFrameCallback((_) {
     if (!mounted) return;
     _scrollToBottom(animated: false);
   });
 }

 void _scheduleReasoningPreviewScroll() {
   // 仅处理底部思考面板的自动滚动，气泡内的滚动由 ReasoningCard 自己处理
   WidgetsBinding.instance.addPostFrameCallback((_) {
     if (!mounted) return;
     if (_reasoningPanelScrollController.hasClients) {
       _reasoningPanelScrollController.animateTo(
         _reasoningPanelScrollController.position.maxScrollExtent,
         duration: const Duration(milliseconds: 200),
         curve: Curves.easeOutCubic,
       );
     }
   });
 }

 void _startDots() {
   _dotsTimer?.cancel();
   const states = ['', '.', '..', '...'];
   var i = 0;
   _dotsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
     if (!mounted) return;
     i = (i + 1) % states.length;
     setState(() {
       _thinkingDots = states[i];
     });
   });
 }

 void _stopDots() {
   _dotsTimer?.cancel();
   _dotsTimer = null;
   if (mounted) {
     setState(() {
       _thinkingDots = '';
     });
   }
 }

 Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).messageCannotBeEmpty);
      return;
    }
    setState(() { _sending = true; });
    try {
      // 先本地追加用户消息，提升即时反馈
      setState(() {
        _messages = List<AIMessage>.from(_messages)
          ..add(AIMessage(role: 'user', content: text));
      });
      _inputController.clear();
      _scheduleAutoScroll();

      // 模式分支：普通对话 -> 直接发送，不做意图/上下文；自我模式 -> 原有阶段流程
      if (!_selfMode) {
        if (_streamEnabled) {
          // 直接走流式对话（不含推理内容），仅展示助手内容
          final int assistantIdx = _messages.length;
          setState(() {
            _inStreaming = true;
            _thinkingText = '';
            _showThinkingContent = false;
            _messages = List<AIMessage>.from(_messages)
              ..add(AIMessage(role: 'assistant', content: '', createdAt: DateTime.now()));
            _currentAssistantIndex = assistantIdx;
            _reasoningByIndex[assistantIdx] = '';
            _reasoningDurationByIndex.remove(assistantIdx);
          });
          _startDots();
          _scheduleAutoScroll();

          try {
            final stream = _chat.sendMessageStreamedV2(text);
            await for (final evt in stream) {
              if (!mounted) return;
              if (evt.kind == 'reasoning') {
                // 普通模式：也展示推理内容到当前助手消息的 Reasoning 卡片
                setState(() {
                  _thinkingText += evt.data;
                  final idx = _currentAssistantIndex;
                  if (idx != null) {
                    _reasoningByIndex[idx] = (_reasoningByIndex[idx] ?? '') + evt.data;
                  }
                });
                _scheduleAutoScroll();
                continue;
              }
              setState(() {
                final lastIdx = _messages.length - 1;
                final last = _messages[lastIdx];
                if (last.role == 'assistant') {
                  final updated = AIMessage(
                    role: 'assistant',
                    content: last.content + evt.data,
                    createdAt: last.createdAt,
                  );
                  final newList = List<AIMessage>.from(_messages);
                  newList[lastIdx] = updated;
                  _messages = newList;
                }
              });
              _scheduleAutoScroll();
            }
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _inStreaming = false;
              if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
                final newList = List<AIMessage>.from(_messages);
                newList[_messages.length - 1] = AIMessage(role: 'error', content: e.toString());
                _messages = newList;
              } else {
                _messages = List<AIMessage>.from(_messages)..add(AIMessage(role: 'error', content: e.toString()));
              }
            });
            _stopDots();
            _scheduleAutoScroll();
            rethrow;
          }

          if (mounted) {
            setState(() {
              _inStreaming = false;
              final idx = _currentAssistantIndex;
              if (idx != null && idx >= 0 && idx < _messages.length) {
                _reasoningDurationByIndex[idx] = DateTime.now().difference(_messages[idx].createdAt);
              }
              _currentAssistantIndex = null;
            });
            _stopDots();
            _scheduleAutoScroll();
          }
        } else {
          // 非流式：直接发送并一次性替换
          final int assistantIdx = _messages.length;
          setState(() {
            _messages = List<AIMessage>.from(_messages)
              ..add(AIMessage(role: 'assistant', content: '', createdAt: DateTime.now()));
          });
          try {
            final assistant = await _chat.sendMessage(text);
            if (!mounted) return;
            setState(() {
              final lastIdx = _messages.length - 1;
              // 非流式普通模式：尝试从正文提取 <think> 思考内容并在 UI 中展示
              final String original = assistant.content;
              final RegExp thinkRe = RegExp(r'<think>([\s\S]*?)(?:</think>|$)', dotAll: true);
              String reasoning = '';
              for (final m in thinkRe.allMatches(original)) {
                final seg = (m.group(1) ?? '').trim();
                if (seg.isNotEmpty) {
                  if (reasoning.isNotEmpty) reasoning += '\n\n';
                  reasoning += seg;
                }
              }
              final cleaned = original.replaceAll(thinkRe, '');
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: cleaned,
                createdAt: _messages[lastIdx].createdAt,
              );
              if (reasoning.isNotEmpty) {
                _reasoningByIndex[lastIdx] = reasoning;
              }
            });
          } catch (e) {
            if (!mounted) return;
            setState(() {
              final lastIdx = _messages.length - 1;
              _messages[lastIdx] = AIMessage(role: 'error', content: e.toString());
            });
          }
        }
        return; // 普通模式流程结束
      }

      if (_streamEnabled) {
        // 追加一个空的助手消息作为占位，并进入"思考中"可视化状态
        final int assistantIdx = _messages.length;
        setState(() {
          _inStreaming = true;
          _thinkingText = '';
          _showThinkingContent = false; // 默认折叠
          // 使用当前时刻作为占位消息的 createdAt，用于正确计算思考耗时
          _messages = List<AIMessage>.from(_messages)
            ..add(AIMessage(role: 'assistant', content: '', createdAt: DateTime.now()));
          _currentAssistantIndex = assistantIdx;
          _reasoningByIndex[assistantIdx] = '';
          _reasoningDurationByIndex.remove(assistantIdx);
        });
        _startDots();
        _scheduleAutoScroll();
        _scheduleReasoningPreviewScroll();

        // 阶段 1/4：意图分析
        try {
          await FlutterLogger.nativeInfo('ChatFlow', 'phase1 intent begin text="${text.length > 200 ? (text.substring(0,200) + '…') : text}"');
          setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            if (last.role == 'assistant') {
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: '1/4 分析用户意图…',
                createdAt: last.createdAt,
              );
            }
          });
          final intent = await IntentAnalysisService.instance.analyze(
            text,
            previous: _lastIntent == null
                ? null
                : IntentPrevHint(
                    startMs: _lastIntent!.startMs,
                    endMs: _lastIntent!.endMs,
                    apps: _lastIntent!.apps,
                    summary: _lastIntent!.intentSummary,
                  ),
            previousUserQueries: _extractPreviousUserQueries(maxCount: 3),
          );
          await FlutterLogger.nativeInfo('ChatFlow', 'phase1 intent ok range=[${intent.startMs}-${intent.endMs}] summary=${intent.intentSummary} apps=${intent.apps.length}');

          // 显示意图摘要与时间窗
          setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            if (last.role == 'assistant') {
              final start = DateTime.fromMillisecondsSinceEpoch(intent.startMs);
              final end = DateTime.fromMillisecondsSinceEpoch(intent.endMs);
              String two(int v) => v.toString().padLeft(2, '0');
              final String range = '${two(start.hour)}:${two(start.minute)}-${two(end.hour)}:${two(end.minute)}';
              final updated = '1/4 意图: ${intent.intentSummary}\n时间: $range (${intent.timezone})\n\n2/4 查找上下文…';
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: updated,
                createdAt: last.createdAt,
              );
            }
          });

          // 阶段 2/4：查找上下文（若 AI 判定可复用上一轮上下文，则跳过新的检索）
          await FlutterLogger.nativeInfo('ChatFlow', 'phase2 context begin');
          final bool reuse = intent.skipContext && (_lastCtxPack != null || QueryContextService.instance.lastPack != null);
          final QueryContextPack ctxPack = reuse
              ? (_lastCtxPack ?? QueryContextService.instance.lastPack!)
              : await QueryContextService.instance.buildContext(
                  startMs: intent.startMs,
                  endMs: intent.endMs,
                );
          await FlutterLogger.nativeInfo('ChatFlow', 'phase2 context ok events=${ctxPack.events.length} reuse=${reuse ? 1 : 0}');
          // 缓存上下文（页面内缓存与服务级缓存），便于紧邻多轮对话复用
          _lastCtxPack = ctxPack;
          try { QueryContextService.instance.setLastPack(ctxPack); } catch (_) {}
          // 组装证据附件（扁平化且去重）
          final List<EvidenceImageAttachment> attachments = <EvidenceImageAttachment>[];
          final Set<String> seen = <String>{};
          for (final ev in ctxPack.events) {
            for (final img in ev.keyImages) {
              if (seen.add(img.path)) {
                attachments.add(img);
              }
            }
          }
          setState(() {
            _attachmentsByIndex[assistantIdx] = attachments;
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            if (last.role == 'assistant') {
              final updated = '2/4 查找上下文完成${reuse ? '（复用上一轮）' : ''}：事件 ${ctxPack.events.length}，图片 ${attachments.length}\n\n3/4 生成回答…';
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: updated,
                createdAt: last.createdAt,
              );
            }
          });

          // 生成最终提示词（包含上下文包的精简文本）
          final String finalQuery = _buildFinalQuestion(text, ctxPack);
          await FlutterLogger.nativeDebug('ChatFlow', 'phase3 finalQueryLen=${finalQuery.length}');
          _replaceAssistantContentOnNextToken = true; // 首个 token 到来时清空阶段状态

          // 使用"显示内容与实际发送内容分离"的新流式接口：
          final stream = _chat.sendMessageStreamedV2WithDisplayOverride(text, finalQuery);
          await for (final evt in stream) {
          if (!mounted) return;
          // 优先消费"思考内容"
          if (evt.kind == 'reasoning') {
            setState(() {
              _thinkingText += evt.data;
              final idx = _currentAssistantIndex;
              if (idx != null) {
                _reasoningByIndex[idx] = (_reasoningByIndex[idx] ?? '') + evt.data;
              }
            });
            _scheduleAutoScroll();
            _scheduleReasoningPreviewScroll();
            continue;
          }
          // 正文增量（首 token 到来时先清空阶段状态，再开始写入最终答案），并将证据文件名替换为绝对路径
          setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            if (last.role == 'assistant') {
              final String base = _replaceAssistantContentOnNextToken ? '' : last.content;
              // 将 [evidence: name] 替换为绝对路径形式，避免后续反查
              String incoming = evt.data;
              if (incoming.contains('[evidence:')) {
                final Map<String, String> map = <String, String>{};
                final atts2 = _attachmentsByIndex[lastIdx] ?? const <EvidenceImageAttachment>[];
                for (final a in atts2) {
                  final p = a.path;
                  final int j1 = p.lastIndexOf('/');
                  final int j2 = p.lastIndexOf('\\');
                  final int j = j1 > j2 ? j1 : j2;
                  final n = j >= 0 ? p.substring(j + 1) : p;
                  if (n.isNotEmpty) map[n] = p;
                }
                if (map.isNotEmpty) {
                  incoming = incoming.replaceAllMapped(
                    RegExp(r'\[evidence:\s*([^\]\s]+)\s*\]'),
                    (m2) {
                      final key = (m2.group(1) ?? '').trim();
                      final abs = map[key];
                      return abs != null && abs.isNotEmpty ? '[evidence: ' + abs + ']' : m2.group(0) ?? '';
                    },
                  );
                }
              }
              // 在首个 token 写入前插入“已复用上一轮上下文”提示（仅一次）
              if (_replaceAssistantContentOnNextToken && reuse) {
                incoming = '（已复用上一轮上下文）\n\n' + incoming;
              }
              final updated = AIMessage(
                role: 'assistant',
                content: base + incoming,
                createdAt: last.createdAt, // 保留初始创建时间以准确计算思考耗时
              );
              final newList = List<AIMessage>.from(_messages);
              newList[lastIdx] = updated;
              _messages = newList;
              _replaceAssistantContentOnNextToken = false;
            }
          });
          _scheduleAutoScroll();
          }
          // 成功路径：更新“上一轮”缓存
          _lastCtxPack = ctxPack;
          _lastIntent = intent;
        } catch (e) {
          try { await FlutterLogger.nativeError('ChatFlow', 'error ' + e.toString()); } catch (_) {}
          if (!mounted) return;
          setState(() {
            _inStreaming = false;
            if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
              final newList = List<AIMessage>.from(_messages);
              newList[_messages.length - 1] = AIMessage(role: 'error', content: e.toString());
              _messages = newList;
            } else {
              _messages = List<AIMessage>.from(_messages)..add(AIMessage(role: 'error', content: e.toString()));
            }
          });
          _stopDots();
          _scheduleAutoScroll();
          rethrow;
        }
        if (mounted) {
          setState(() {
            _inStreaming = false;
            // 记录本条消息最终思考耗时
            final idx = _currentAssistantIndex;
            if (idx != null && idx >= 0 && idx < _messages.length) {
              _reasoningDurationByIndex[idx] = DateTime.now().difference(_messages[idx].createdAt);
            }
            _currentAssistantIndex = null;
          });
          _stopDots();
          _scheduleAutoScroll();
          // 结束后做一次最终替换（处理流式分片造成的跨分片 token 未被替换的情况）
          try {
            final List<AIMessage> finalized = _finalizeEvidenceAbsolutePaths(_messages);
            if (mounted) {
              setState(() {
                _messages = finalized;
              });
            }
            // 覆写历史：使用最终替换后的版本
            await _settings.saveChatHistoryActive(finalized);
          } catch (_) {
            try {
              final List<AIMessage> toSave = List<AIMessage>.from(_messages);
              await _settings.saveChatHistoryActive(toSave);
            } catch (_) {}
          }
        }
      } else {
        // 非流式：仍按阶段流程，最后一次性替换为最终答案
        final int assistantIdx = _messages.length;
        setState(() {
          _messages = List<AIMessage>.from(_messages)
            ..add(AIMessage(role: 'assistant', content: '1/4 分析用户意图…', createdAt: DateTime.now()));
        });

        try {
          await FlutterLogger.nativeInfo('ChatFlow', 'phase1 intent(begin, non-stream)');
          final intent = await IntentAnalysisService.instance.analyze(
            text,
            previous: _lastIntent == null
                ? null
                : IntentPrevHint(
                    startMs: _lastIntent!.startMs,
                    endMs: _lastIntent!.endMs,
                    apps: _lastIntent!.apps,
                    summary: _lastIntent!.intentSummary,
                  ),
            previousUserQueries: _extractPreviousUserQueries(maxCount: 3),
          );
          await FlutterLogger.nativeInfo('ChatFlow', 'phase1 intent ok range=[${intent.startMs}-${intent.endMs}] summary=${intent.intentSummary}');
          final start = DateTime.fromMillisecondsSinceEpoch(intent.startMs);
          final end = DateTime.fromMillisecondsSinceEpoch(intent.endMs);
          String two(int v) => v.toString().padLeft(2, '0');
          final String range = '${two(start.hour)}:${two(start.minute)}-${two(end.hour)}:${two(end.minute)}';
          setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content: '1/4 意图: ${intent.intentSummary}\n时间: $range (${intent.timezone})\n\n2/4 查找上下文…',
              createdAt: last.createdAt,
            );
          });

          await FlutterLogger.nativeInfo('ChatFlow', 'phase2 context(begin, non-stream)');
          final bool reuse = intent.skipContext && (_lastCtxPack != null || QueryContextService.instance.lastPack != null);
          final QueryContextPack ctxPack = reuse
              ? (_lastCtxPack ?? QueryContextService.instance.lastPack!)
              : await QueryContextService.instance.buildContext(startMs: intent.startMs, endMs: intent.endMs);
          await FlutterLogger.nativeInfo('ChatFlow', 'phase2 context ok events=${ctxPack.events.length} reuse=${reuse ? 1 : 0}');
          // 缓存上下文，便于下一轮复用
          _lastCtxPack = ctxPack;
          try { QueryContextService.instance.setLastPack(ctxPack); } catch (_) {}
          final List<EvidenceImageAttachment> attachments = <EvidenceImageAttachment>[];
          final Set<String> seen = <String>{};
          for (final ev in ctxPack.events) {
            for (final img in ev.keyImages) {
              if (seen.add(img.path)) attachments.add(img);
            }
          }
          setState(() {
            _attachmentsByIndex[assistantIdx] = attachments;
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content: '2/4 查找上下文完成' + (reuse ? '（复用上一轮）' : '') + '：事件 ${ctxPack.events.length}，图片 ${attachments.length}\n\n3/4 生成回答…',
              createdAt: last.createdAt,
            );
          });

          final finalQuery = _buildFinalQuestion(text, ctxPack);
          await FlutterLogger.nativeDebug('ChatFlow', 'phase3 finalQueryLen=${finalQuery.length} (non-stream)');
          // 非流式：拿到回复后将证据名替换为绝对路径
          final assistant = await _chat.sendMessageWithDisplayOverride(text, finalQuery);
          // 替换 evidence 名称为绝对路径（基于当前 attachments）
          String content = assistant.content;
          if (content.contains('[evidence:')) {
            final Map<String, String> map = <String, String>{};
            final atts2 = _attachmentsByIndex[assistantIdx] ?? const <EvidenceImageAttachment>[];
            for (final a in atts2) {
              final p = a.path;
              final int j1 = p.lastIndexOf('/');
              final int j2 = p.lastIndexOf('\\');
              final int j = j1 > j2 ? j1 : j2;
              final n = j >= 0 ? p.substring(j + 1) : p;
              if (n.isNotEmpty) map[n] = p;
            }
            if (map.isNotEmpty) {
              content = content.replaceAllMapped(
                RegExp(r'\[evidence:\s*([^\]\s]+)\s*\]'),
                (m2) {
                  final key = (m2.group(1) ?? '').trim();
                  final abs = map[key];
                  return abs != null && abs.isNotEmpty ? '[evidence: ' + abs + ']' : m2.group(0) ?? '';
                },
              );
            }
          }
          if (!mounted) return;
          setState(() {
            // 用最终答案替换占位
            final lastIdx = _messages.length - 1;
            // 如复用上一轮上下文，则在正文前加一行提示
            final String finalContent = (reuse ? '（已复用上一轮上下文）\n\n' : '') + content;
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content: finalContent,
              createdAt: _messages[lastIdx].createdAt,
            );
            _inStreaming = false;
          });
          // 覆写历史：使用 UI 中的版本（已替换绝对路径）
          try {
            final List<AIMessage> toSave = List<AIMessage>.from(_messages);
            await _settings.saveChatHistoryActive(toSave);
          } catch (_) {}
          // 成功路径：更新“上一轮”缓存
          _lastCtxPack = ctxPack;
          _lastIntent = intent;
        } catch (e) {
          try { await FlutterLogger.nativeError('ChatFlow', 'error(non-stream) ' + e.toString()); } catch (_) {}
          if (!mounted) return;
          setState(() {
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = AIMessage(role: 'error', content: e.toString());
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      // 将错误显示为一条"错误"气泡，便于区分样式
      setState(() {
        _inStreaming = false;
        if (_streamEnabled && _messages.isNotEmpty && _messages.last.role == 'assistant') {
          final newList = List<AIMessage>.from(_messages);
          newList[_messages.length - 1] = AIMessage(role: 'error', content: e.toString());
          _messages = newList;
        } else {
          _messages = List<AIMessage>.from(_messages)
            ..add(AIMessage(role: 'error', content: e.toString()));
        }
      });
      _stopDots();
      UINotifier.error(context, AppLocalizations.of(context).sendFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  /// 对当前会话内所有助手消息进行一次"证据名 -> 绝对路径"的最终替换。
  /// 解决流式增量写入中，evidence 标记可能被分片拆开，导致在线替换不完全的问题。
  List<AIMessage> _finalizeEvidenceAbsolutePaths(List<AIMessage> input) {
    String _basename(String path) {
      final int j1 = path.lastIndexOf('/');
      final int j2 = path.lastIndexOf('\\');
      final int j = j1 > j2 ? j1 : j2;
      return j >= 0 ? path.substring(j + 1) : path;
    }

    final List<AIMessage> out = List<AIMessage>.from(input);
    for (int i = 0; i < out.length; i++) {
      final m = out[i];
      if (m.role != 'assistant') continue;
      String content = m.content;
      if (!content.contains('[evidence:')) continue;
      final atts = _attachmentsByIndex[i] ?? const <EvidenceImageAttachment>[];
      if (atts.isEmpty) continue;
      final Map<String, String> map = <String, String>{};
      for (final a in atts) {
        final base = _basename(a.path);
        if (base.isNotEmpty) map[base] = a.path;
      }
      if (map.isEmpty) continue;
      content = content.replaceAllMapped(
        RegExp(r'\[evidence:\s*([^\]\s]+)\s*\]'),
        (mm) {
          final key = (mm.group(1) ?? '').trim();
          final abs = map[key];
          return abs != null && abs.isNotEmpty ? '[evidence: ' + abs + ']' : (mm.group(0) ?? '');
        },
      );
      if (content != m.content) {
        out[i] = AIMessage(
          role: m.role,
          content: content,
          createdAt: m.createdAt,
          reasoningContent: m.reasoningContent,
          reasoningDuration: m.reasoningDuration,
        );
      }
    }
    return out;
  }

  String _buildFinalQuestion(String userText, QueryContextPack ctx) {
    // 将上下文包格式化为提示词，并明确禁止图片注入，要求仅引用文件名作为证据
    String _basename(String path) {
      // 同时兼容 Windows \\ 与 POSIX /
      final int idx1 = path.lastIndexOf('/');
      final int idx2 = path.lastIndexOf('\\');
      final int idx = idx1 > idx2 ? idx1 : idx2;
      return idx >= 0 ? path.substring(idx + 1) : path;
    }

    final Set<String> evidenceFiles = <String>{};

    final sb = StringBuffer();
    sb.writeln('请严格依据以下上下文回答用户问题。');
    sb.writeln('禁止访问或假设任何图片内容（我们不会向你发送图片数据）。');
    sb.writeln('引用规范（唯一合法格式）：仅使用 [evidence: FILENAME.EXT] 来引用下方"证据文件"清单中的文件名（必须包含扩展名）。');
    sb.writeln('多个引用：每个事件可以引用多个相关截图，请按需要列出多个 [evidence: ...]，以空格分隔，例如：[evidence: 20251014_093112_AppA.png] [evidence: 20251014_101245_AppB.jpg]');
    sb.writeln('禁止使用以下任何形式： [图1]、[file: ...]、URL、HTML、Markdown 图片/链接语法（如 ![](x) 或 [](x)）。');
    sb.writeln('重要：不得将 [evidence: ...] 放入代码块或行内代码中，否则将无法识别与渲染。');
    sb.writeln('不得引用未在本提示词出现的任何文件名，不得臆测图片内容。');
    sb.writeln('若上下文不足以回答，请明确说明不确定之处。');
    sb.writeln('');
    sb.writeln('【上下文】');
    String two(int v) => v.toString().padLeft(2, '0');
    final ds = DateTime.fromMillisecondsSinceEpoch(ctx.startMs);
    final de = DateTime.fromMillisecondsSinceEpoch(ctx.endMs);
    sb.writeln('时间范围: ${two(ds.hour)}:${two(ds.minute)}–${two(de.hour)}:${two(de.minute)}');
    int imgNo = 0;
    for (final ev in ctx.events) {
      sb.writeln('- ${ev.window} ${ev.apps.isNotEmpty ? ev.apps.join('/') : ''}');
      // 优先送入 structured_json（完整），否则送入 output_text；如果两者都无，再送入 summary
      if ((ev.structuredJson != null && ev.structuredJson!.trim().isNotEmpty)) {
        sb.writeln('  structured_json:');
        sb.writeln(ev.structuredJson!.trim());
      } else if (ev.outputText != null && ev.outputText!.trim().isNotEmpty) {
        sb.writeln('  output_text:');
        sb.writeln(ev.outputText!.trim());
      } else if (ev.summary.trim().isNotEmpty) {
        sb.writeln('  摘要:');
        sb.writeln(ev.summary.trim());
      }
      if (ev.keyImages.isNotEmpty) {
        final pairs = <String>[];
        for (final img in ev.keyImages) {
          imgNo += 1;
          final name = _basename(img.path);
          evidenceFiles.add(name);
          // 每个事件条目下列出文件名与简短标签，供引用
          pairs.add('$name（${img.label}）');
        }
        sb.writeln('  证据文件: ' + pairs.join('；'));
      }
    }
    sb.writeln('');
    // 汇总证据文件清单（仅名称，不含任何图片内容）
    if (evidenceFiles.isNotEmpty) {
      sb.writeln('【证据文件（仅名称，不含内容）】');
      for (final f in evidenceFiles) {
        sb.writeln('- ' + f);
      }
      sb.writeln('');
    }
    sb.writeln('【用户问题】');
    sb.writeln(userText);
    return sb.toString();
  }

  void _cancelRequest() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    if (mounted) {
      setState(() {
        _sending = false;
        _inStreaming = false;
        _currentAssistantIndex = null;
      });
      _stopDots();
      UINotifier.info(context, AppLocalizations.of(context).requestStoppedInfo);
    }
  }

  /// 重试指定索引处的助手消息：
  /// - 不新增一条相同的用户消息；
  /// - 直接重算并覆盖该助手消息内容（保留其 createdAt 以维持耗时统计准确）。
  Future<void> _retryAssistantAt(int assistantIndex) async {
    if (_sending) return;
    if (assistantIndex < 0 || assistantIndex >= _messages.length) return;
    final msg = _messages[assistantIndex];
    if (msg.role != 'assistant' && msg.role != 'error') return;

    // 找到与该助手消息对应的上一条用户消息
    final prevUserIndex = assistantIndex > 0
        ? _messages.sublist(0, assistantIndex).lastIndexWhere((e) => e.role == 'user')
        : -1;
    if (prevUserIndex < 0) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    final userText = _messages[prevUserIndex].content;

    setState(() { _sending = true; });
    try {
      // 完全重试：清空当前会话历史，让这次重试成为第一条消息
      await _settings.clearChatHistory();

      if (_streamEnabled) {
        // 进入流式重试：视觉与数据均从零开始，仅保留这条用户消息
        setState(() {
          _inStreaming = true;
          _thinkingText = '';
          _showThinkingContent = false;
          _reasoningByIndex
            ..clear();
          _reasoningDurationByIndex
            ..clear();
          _messages = <AIMessage>[
            AIMessage(role: 'user', content: userText),
            AIMessage(role: 'assistant', content: '', createdAt: DateTime.now()),
          ];
          _currentAssistantIndex = 1; // 新的第一条助手消息索引
        });
        _startDots();
        _scheduleAutoScroll();
        _scheduleReasoningPreviewScroll();

        final stream = _chat.sendMessageStreamedV2(userText);
        await for (final evt in stream) {
          if (!mounted) return;
          if (evt.kind == 'reasoning') {
            setState(() {
              _thinkingText += evt.data;
              final idx = _currentAssistantIndex;
              if (idx != null) {
                _reasoningByIndex[idx] = (_reasoningByIndex[idx] ?? '') + evt.data;
              }
            });
            _scheduleAutoScroll();
            _scheduleReasoningPreviewScroll();
            continue;
          }
          setState(() {
            final lastIdx = _currentAssistantIndex ?? 1;
            final cur = _messages[lastIdx];
            if (cur.role == 'assistant') {
              final updated = AIMessage(
                role: 'assistant',
                content: cur.content + evt.data,
                createdAt: cur.createdAt,
              );
              final newList = List<AIMessage>.from(_messages);
              newList[lastIdx] = updated;
              _messages = newList;
            }
          });
          _scheduleAutoScroll();
        }
        if (mounted) {
          setState(() {
            _inStreaming = false;
            final idx = _currentAssistantIndex ?? 1;
            if (idx >= 0 && idx < _messages.length) {
              // 重试时思考时间从0开始，因此这里记录从新的 createdAt 开始的耗时
              _reasoningDurationByIndex[idx] = DateTime.now().difference(_messages[idx].createdAt);
            }
            _currentAssistantIndex = null;
          });
          _stopDots();
          _scheduleAutoScroll();
        }
      } else {
        final assistant = await _chat.sendMessage(userText);
        if (!mounted) return;
        setState(() {
          _messages = <AIMessage>[
            AIMessage(role: 'user', content: userText),
            AIMessage(role: 'assistant', content: assistant.content, createdAt: DateTime.now()),
          ];
          _inStreaming = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inStreaming = false;
        _messages = <AIMessage>[
          AIMessage(role: 'user', content: userText),
          AIMessage(role: 'error', content: e.toString(), createdAt: DateTime.now()),
        ];
      });
      _stopDots();
      UINotifier.error(context, AppLocalizations.of(context).sendFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  // 载入"对话页(chat)"的提供商/模型选择（独立于动态页）
  Future<void> _loadChatContextSelection() async {
    try {
      final svc = AIProvidersService.instance;
      final providers = await svc.listProviders();
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _ctxChatProvider = null;
            _ctxChatModel = null;
            _ctxLoading = false;
          });
        }
        return;
      }
      final ctxRow = await _settings.getAIContextRow('chat');
      AIProvider? sel;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        sel = await svc.getProvider(ctxRow['provider_id'] as int);
      }
      sel ??= await svc.getDefaultProvider();
      sel ??= providers.first;

      String model = (ctxRow != null && (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel).toString().trim();
      // 如果上下文中的模型不属于新提供商，回退到"提供商页选择的模型/默认/首个"
      if (model.isEmpty || (sel.models.isNotEmpty && !sel.models.contains(model))) {
        final String fallback = ((sel.extra['active_model'] as String?) ?? sel.defaultModel).toString().trim();
        model = fallback.isNotEmpty ? fallback : (sel.models.isNotEmpty ? sel.models.first : model);
      }

      if (mounted) {
        setState(() {
          _ctxChatProvider = sel;
          _ctxChatModel = model;
          _ctxLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ctxLoading = false);
    }
  }

  Future<void> _showProviderSheetChat() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final currentId = _ctxChatProvider?.id ?? -1;
        // 控制器与文本持久化，避免键盘折叠时内容丢失
        final TextEditingController queryCtrl = TextEditingController(text: _providerQueryText);
        return StatefulBuilder(
          builder: (c, setModalState) {
            final String q = queryCtrl.text.trim().toLowerCase();
            final List<AIProvider> items = q.isEmpty
                ? list
                : list.where((p) {
                    final name = p.name.toLowerCase();
                    final type = p.type.toLowerCase();
                    final base = (p.baseUrl ?? '').toString().toLowerCase();
                    return name.contains(q) || type.contains(q) || base.contains(q);
                  }).toList();
            // 选中的提供商置顶展示
            final selIdx = items.indexWhere((e) => e.id == currentId);
            if (selIdx > 0) {
              final sel = items.removeAt(selIdx);
              items.insert(0, sel);
            }
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: queryCtrl,
                        autofocus: true,
                        onChanged: (_) {
                          _providerQueryText = queryCtrl.text;
                          setModalState(() {});
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: AppLocalizations.of(context).searchProviderPlaceholder,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(c).colorScheme.outline.withOpacity(0.6),
                        ),
                        itemBuilder: (c, i) {
                          final p = items[i];
                          final selected = p.id == currentId;
                          return ListTile(
                            leading: SvgPicture.asset(
                              ModelIconUtils.getProviderIconPath(p.type),
                              width: 20, height: 20,
                            ),
                            title: Text(p.name, style: Theme.of(c).textTheme.bodyMedium),
                            trailing: selected ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.primary) : null,
                            onTap: () async {
                              String model = (_ctxChatModel ?? '').trim();
                              final List<String> available = p.models;
                              if (model.isEmpty || (available.isNotEmpty && !available.contains(model))) {
                                String fb = (p.extra['active_model'] as String? ?? p.defaultModel).toString().trim();
                                if (fb.isEmpty && available.isNotEmpty) fb = available.first;
                                model = fb;
                              }
                              await _settings.setAIContextSelection(context: 'chat', providerId: p.id!, model: model);
                              if (mounted) {
                                setState(() {
                                  _ctxChatProvider = p;
                                  _ctxChatModel = model;
                                });
                                Navigator.of(ctx).pop();
                                UINotifier.success(context, AppLocalizations.of(context).providerSelectedToast(p.name));
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showModelSheetChat() async {
    final p = _ctxChatProvider;
    if (p == null) {
      UINotifier.info(context, AppLocalizations.of(context).pleaseSelectProviderFirst);
      return;
    }
    final models = p.models;
    if (models.isEmpty) {
      UINotifier.info(context, AppLocalizations.of(context).noModelsForProviderHint);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final active = (_ctxChatModel ?? '').trim();
        // 控制器与文本持久化，避免键盘折叠时内容丢失
        final TextEditingController queryCtrl = TextEditingController(text: _modelQueryText);
        return StatefulBuilder(
          builder: (c, setModalState) {
            final String q = queryCtrl.text.trim().toLowerCase();
            final List<String> items = q.isEmpty
                ? List<String>.from(models)
                : models.where((mm) => mm.toLowerCase().contains(q)).toList();
            if (active.isNotEmpty && items.contains(active)) {
              items.remove(active);
              items.insert(0, active);
            }
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: queryCtrl,
                        autofocus: true,
                        onChanged: (_) {
                          _modelQueryText = queryCtrl.text;
                          setModalState(() {});
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: AppLocalizations.of(context).searchModelPlaceholder,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(c).colorScheme.outline.withOpacity(0.6),
                        ),
                        itemBuilder: (c, i) {
                          final m = items[i];
                          final selected = m == active;
                          return ListTile(
                            leading: SvgPicture.asset(
                              ModelIconUtils.getIconPath(m),
                              width: 20, height: 20,
                            ),
                            title: Text(m, style: Theme.of(c).textTheme.bodyMedium),
                            trailing: selected ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.primary) : null,
                            onTap: () async {
                              await _settings.setAIContextSelection(context: 'chat', providerId: p.id!, model: m);
                              if (mounted) {
                                setState(() => _ctxChatModel = m);
                                Navigator.of(ctx).pop();
                                UINotifier.success(context, AppLocalizations.of(context).modelSwitchedToast(m));
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 顶部"提供商 / 模型"极小字号、可点击切换
  Widget _buildProviderModelHeader() {
    final theme = Theme.of(context);
    final String providerLabel = AppLocalizations.of(context).providerLabel;
    final String providerName = _ctxChatProvider?.name ?? '—';
    final String modelName = _ctxChatModel ?? '—';
    final TextStyle? underlined = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withOpacity(0.6),
      color: theme.colorScheme.primary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showProviderSheetChat,
            behavior: HitTestBehavior.opaque,
            child: Text(providerLabel, style: underlined),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              providerName,
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          GestureDetector(
            onTap: _showModelSheetChat,
            behavior: HitTestBehavior.opaque,
            child: Text(
              modelName,
              style: underlined,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing4,
                    ),
                    child: _buildChatList(),
                  ),
                ),
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

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).aiSettingsTitle),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      drawer: const AppSideDrawer(),
      drawerEnableOpenDragGesture: false, // 关闭默认边缘拖拽，改用自定义"任意位置"滑动
      body: body,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    // 紧凑型输入框（更小的字体与内边距）
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onTap: () {
          // 点击连接设置里的输入框时，自动收起上方分组下拉区域
          if (_groupSelectorVisible) {
            setState(() { _groupSelectorVisible = false; });
          }
        },
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing2,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: Theme.of(context).textTheme.bodySmall,
          hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          filled: false,
        ),
      ),
    );
  }

  /// 折叠头部摘要：展示当前分组 + baseUrl + model（截断显示）
  String _buildConnSummary() {
    final gid = _activeGroupId;
    String groupName;
    if (gid == null) {
      groupName = AppLocalizations.of(context).ungroupedSingleConfig;
    } else {
      final g = _groups.where((e) => e.id == gid).toList();
      groupName = g.isNotEmpty ? g.first.name : AppLocalizations.of(context).siteGroupDefaultName(gid);
    }
    final base = _baseUrlController.text.trim().isEmpty
        ? 'https://api.openai.com'
        : _baseUrlController.text.trim();
    final model = _modelController.text.trim().isEmpty
        ? 'gpt-4o-mini'
        : _modelController.text.trim();

    String brief(String s, int max) => s.length > max ? (s.substring(0, max) + '…') : s;

    return '$groupName · ${brief(base, 36)} · ${brief(model, 24)}';
  }

  /// 折叠头部摘要：提示词管理当前状态
 String _buildPromptSummary() {
   final l10n = AppLocalizations.of(context);
   final seg = (_promptSegment == null || _promptSegment!.trim().isEmpty)
       ? l10n.defaultLabel
       : l10n.customLabel;
   final mer = (_promptMerge == null || _promptMerge!.trim().isEmpty)
       ? l10n.defaultLabel
       : l10n.customLabel;
   final day = (_promptDaily == null || _promptDaily!.trim().isEmpty)
       ? l10n.defaultLabel
       : l10n.customLabel;
   return '${l10n.normalShortLabel} $seg · ${l10n.mergeShortLabel} $mer · ${l10n.dailyShortLabel} $day';
 }

  Future<void> _onGroupChanged(int? newId) async {
    await _settings.setActiveGroupId(newId);
    await _loadAll();
    if (!mounted) return;
    UINotifier.success(
      context,
      newId == null
          ? AppLocalizations.of(context).groupSwitchedToUngrouped
          : AppLocalizations.of(context).groupSwitched,
    );
  }

  Future<void> _addGroup() async {
    try {
      final name = AppLocalizations.of(context).siteGroupDefaultName(_groups.length + 1);
      final base = _baseUrlController.text.trim().isEmpty ? 'https://api.openai.com' : _baseUrlController.text.trim();
      final key = _apiKeyController.text.trim();
      final model = _modelController.text.trim().isEmpty ? 'gpt-4o-mini' : _modelController.text.trim();
      final id = await _settings.addSiteGroup(
        name: name,
        baseUrl: base,
        apiKey: key.isEmpty ? null : key,
        model: model,
      );
      await _settings.setActiveGroupId(id);
      await _loadAll();
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).groupAddedToast);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).addGroupFailedWithError(e.toString()));
    }
  }

  Future<void> _renameActiveGroup() async {
    final gid = _activeGroupId;
    if (gid == null) {
      if (mounted) UINotifier.info(context, AppLocalizations.of(context).groupNotSelected);
      return;
    }
    try {
      final g = await _settings.getSiteGroupById(gid);
      if (g == null) {
        if (mounted) UINotifier.error(context, AppLocalizations.of(context).groupNotFound);
        return;
      }
      final controller = TextEditingController(text: g.name);
      await showUIDialog<void>(
        context: context,
        title: AppLocalizations.of(context).renameGroupTitle,
        content: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: TextField(
            controller: controller,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).groupNameLabel,
              hintText: AppLocalizations.of(context).groupNameHint,
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing2,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ),
        actions: [
          UIDialogAction(
            text: AppLocalizations.of(context).dialogCancel,
          ),
          UIDialogAction(
            text: AppLocalizations.of(context).dialogOk,
            style: UIDialogActionStyle.primary,
            closeOnPress: false,
            onPressed: (ctx) async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                UINotifier.error(ctx, AppLocalizations.of(ctx).nameCannotBeEmpty);
                return;
              }
              try {
                final updated = g.copyWith(name: newName);
                await _settings.updateSiteGroup(updated);
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _loadAll();
                if (mounted) UINotifier.success(context, AppLocalizations.of(context).renameSuccess);
              } catch (e) {
                if (ctx.mounted) UINotifier.error(ctx, AppLocalizations.of(ctx).renameFailedWithError(e.toString()));
              }
            },
          ),
        ],
      );
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).loadGroupFailedWithError(e.toString()));
    }
  }

  Future<void> _deleteActiveGroup() async {
    final gid = _activeGroupId;
    if (gid == null) {
      UINotifier.info(context, AppLocalizations.of(context).groupNotSelected);
      return;
    }
    try {
      await _settings.deleteSiteGroup(gid);
      await _settings.setActiveGroupId(null);
      await _loadAll();
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).groupDeletedToast);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).deleteGroupFailedWithError(e.toString()));
    }
  }

  Widget _buildGroupSelector() {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(AppLocalizations.of(context).ungroupedSingleConfig),
      ),
      ..._groups.map((g) => DropdownMenuItem<int?>(
        value: g.id,
        child: Text(g.name),
      )),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).siteGroupsTitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          AppLocalizations.of(context).siteGroupsHint,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppTheme.spacing2),
        if (_groupSelectorVisible)
          Row(
            children: [
              DropdownButton<int?>(
                value: _activeGroupId,
                items: items,
                isDense: true,
                style: Theme.of(context).textTheme.bodySmall,
                onChanged: (v) => _onGroupChanged(v),
              ),
              const SizedBox(width: AppTheme.spacing2),
              UIButton(
                text: AppLocalizations.of(context).rename,
                variant: UIButtonVariant.outline,
                size: UIButtonSize.small,
                onPressed: (_activeGroupId == null) ? null : _renameActiveGroup,
              ),
              const SizedBox(width: AppTheme.spacing2),
              UIButton(
                text: AppLocalizations.of(context).addGroup,
                variant: UIButtonVariant.outline,
                size: UIButtonSize.small,
                onPressed: _addGroup,
              ),
            ],
          )
        else
          TextButton(
            onPressed: () => setState(() { _groupSelectorVisible = true; }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2, vertical: AppTheme.spacing1),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              AppLocalizations.of(context).showGroupSelector,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _inputController,
        textAlignVertical: TextAlignVertical.center,
        onTap: () {
          // 点击底部输入框时收起整个"连接设置"折叠区，避免遮挡内容
          setState(() { _connExpanded = false; });
        },
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).inputMessageHint,
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing2,
          ),
          filled: false,
        ),
        minLines: 1,
        maxLines: null,
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _chatScrollController,
      itemCount: _messages.length,
      reverse: false,
      padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
      itemBuilder: (context, index) {
        final m = _messages[index];
        final isUser = m.role == 'user';
        final isError = m.role == 'error' ||
            m.content.contains('"error"') ||
            m.content.toLowerCase().contains('server_error') ||
            m.content.toLowerCase().contains('request failed') ||
            m.content.toLowerCase().contains('no candidates returned');
        final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
        final bg = isUser
            ? Theme.of(context).colorScheme.primary
            : isError
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceVariant;
        final fg = isUser
            ? Theme.of(context).colorScheme.onPrimary
            : isError
                ? Theme.of(context).colorScheme.onErrorContainer
                : Theme.of(context).colorScheme.onSurfaceVariant;

        final List<Widget> bubbleChildren = [];

        // 在助手消息气泡内显示"思考内容"（靠左无图标），并在等待首字时显示占位
        if (!isUser) {
          final r = _reasoningByIndex[index] ?? '';
          final isCurrentStreaming = _inStreaming && (_currentAssistantIndex == index);
          final finishedDur = _reasoningDurationByIndex[index];
          if (isCurrentStreaming && r.isEmpty) {
            bubbleChildren.add(
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                child: ReasoningCard(
                  reasoning: '',
                  isLoading: true,
                  createdAt: _messages[index].createdAt,
                  finishedAt: null,
                  textColor: fg,
                  accentColor: Theme.of(context).colorScheme.secondary,
                  autoCloseOnFinish: false,
                  dots: _thinkingDots,
                ),
              ),
            );
          } else if (r.isNotEmpty || finishedDur != null) {
            bubbleChildren.add(
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                child: ReasoningCard(
                  reasoning: r,
                  isLoading: isCurrentStreaming,
                  createdAt: _messages[index].createdAt,
                  finishedAt: finishedDur != null
                      ? _messages[index].createdAt.add(finishedDur)
                      : null,
                  textColor: fg,
                  accentColor: Theme.of(context).colorScheme.secondary,
                  autoCloseOnFinish: false,
                  dots: _thinkingDots,
                ),
              ),
            );
          }
        }

        // 正文 Markdown（接入 LaTeX 预处理 + 渲染）
        String preprocessedMd = preprocessForChatMarkdown(m.content);
        // 构建 evidence 文件名到绝对路径的映射，供 Markdown 渲染时内嵌图片
        final Map<String, String> evidenceNameToPath = <String, String>{};
        final atts = _attachmentsByIndex[index] ?? const <EvidenceImageAttachment>[];
        for (final a in atts) {
          final path = a.path;
          final int idx1 = path.lastIndexOf('/');
          final int idx2 = path.lastIndexOf('\\');
          final int i = idx1 > idx2 ? idx1 : idx2;
          final name = i >= 0 ? path.substring(i + 1) : path;
          if (name.isNotEmpty) evidenceNameToPath[name] = a.path;
        }
        // 预构建 Markdown 配置（若需要异步兜底，会在 FutureBuilder 中重建）
        final mathConfig = MarkdownMathConfig(
          inlineTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
          blockTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
          evidenceNameToPath: evidenceNameToPath,
          orderedEvidencePaths: atts.map((e) => e.path).toList(),
        );
        // 隐藏 system 消息（用于保存最终提示但不显示）
        final bool isSystem = m.role == 'system';
        if (isSystem) {
          return const SizedBox.shrink();
        }
        // 解析正文中的证据文件名集合；若存在，则进行异步解析（无论是否已有部分附件映射）
        final Set<String> evidenceNames = RegExp(r'\[evidence:\s*([^\]\s]+)\s*\]')
            .allMatches(preprocessedMd)
            .map((mm) => (mm.group(1) ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toSet();
        final bool needAsyncResolve = evidenceNames.isNotEmpty;
        final Widget mdWidget = needAsyncResolve
            ? FutureBuilder<Map<String, String>>(
                future: (() async {
                  try {
                    if (evidenceNames.isEmpty) return const <String, String>{};
                    return await ScreenshotDatabase.instance.findPathsByBasenames(evidenceNames);
                  } catch (_) {
                    return const <String, String>{};
                  }
                })(),
                builder: (context, snap) {
                  final Map<String, String> map = snap.data ?? const <String, String>{};
                  // 合并：已有附件映射 + 数据库解析结果
                  final merged = <String, String>{...evidenceNameToPath, ...map};
                  final resolved = MarkdownMathConfig(
                    inlineTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
                    blockTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
                    evidenceNameToPath: merged,
                    orderedEvidencePaths: atts.map((e) => e.path).toList(),
                  );
                  return MarkdownBody(
                    data: preprocessedMd,
                    builders: resolved.builders,
                    inlineSyntaxes: resolved.inlineSyntaxes,
                    styleSheet: _mdStyle(context).copyWith(
                      p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                      }
                    },
                  );
                },
              )
            : MarkdownBody(
                data: preprocessedMd,
                builders: mathConfig.builders,
                inlineSyntaxes: mathConfig.inlineSyntaxes,
                styleSheet: _mdStyle(context).copyWith(
                  p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
                ),
                onTapLink: (text, href, title) async {
                  if (href == null) return;
                  final uri = Uri.tryParse(href);
                  if (uri != null) {
                    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                  }
                },
              );

        bubbleChildren.add(mdWidget);

        // 取消底部缩略图展示：图片仅通过正文中的 [evidence: FILENAME.EXT] 内联渲染

        // 组合：上方时间，中间消息气泡，下方操作区
        return Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 上方：时间（HH:mm:ss）
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: Text(
                DateFormat('HH:mm:ss').format(
                  (m.role == 'assistant' && _reasoningDurationByIndex[index] != null)
                      ? m.createdAt.add(_reasoningDurationByIndex[index]!)
                      : m.createdAt
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
              ),
            ),
            Align(
              alignment: align,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing3,
                  vertical: AppTheme.spacing2,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bubbleChildren,
                ),
              ),
            ),
            // 下方：操作区（复制、重新生成）——与气泡边缘对齐（左对齐助手，右对齐用户）
            Align(
              alignment: align,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // 复制（Material Icon）
                  IconButton(
                    onPressed: () async {
                      try {
                        // 若为助手消息并存在"深度思考"内容，则一并复制
                        String textToCopy = m.content;
                        if (!isUser) {
                          final reasoning = _reasoningByIndex[index] ?? '';
                          if (reasoning.trim().isNotEmpty) {
                            final t = AppLocalizations.of(context);
                            textToCopy = t.reasoningLabel + '\n' + reasoning.trim() + '\n\n' + t.answerLabel + '\n' + textToCopy;
                          }
                        }
                        await Clipboard.setData(ClipboardData(text: textToCopy));
                        if (mounted) UINotifier.success(context, AppLocalizations.of(context).copySuccess);
                      } catch (_) {}
                    },
                    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                    padding: const EdgeInsets.all(0),
                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                    splashRadius: 16,
                    iconSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: AppLocalizations.of(context).actionCopy,
                  ),
                  const SizedBox(width: 4),
                  // 重新生成（仅对助手消息提供）
                  if (!isUser)
                    IconButton(
                      onPressed: _sending ? null : () async {
                        await _retryAssistantAt(index);
                      },
                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                      padding: const EdgeInsets.all(0),
                      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                      splashRadius: 16,
                      iconSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: AppLocalizations.of(context).actionRegenerate,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttachmentThumb(EvidenceImageAttachment att, int index, Color fg) {
    final file = File(att.path);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ScreenshotImageWidget(
              file: file,
              privacyMode: true,
              width: 88,
              height: 158,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(8),
              targetWidth: 176,
            ),
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('[图$index]', style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 88,
          child: Text(
            att.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg.withOpacity(0.9), fontSize: 10),
          ),
        ),
      ],
    );
  }

  // "思考过程"面板：显示 reasoning 实时内容（流式期间展示，可折叠）
  Widget _buildThinkingRow() {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing2,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRect(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: SvgPicture.asset(
                      'assets/icons/think.svg',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      colorFilter: ColorFilter.mode(theme.colorScheme.onSurfaceVariant, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context).deepThinkingLabel + (_inStreaming ? _thinkingDots : ''),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Builder(
                      builder: (ctx) {
                        if (!_inStreaming || _currentAssistantIndex == null) return const SizedBox.shrink();
                        final idx = _currentAssistantIndex!;
                        if (idx < 0 || idx >= _messages.length) return const SizedBox.shrink();
                        final dur = DateTime.now().difference(_messages[idx].createdAt);
                        if (dur.inMilliseconds <= 0) return const SizedBox.shrink();
                        final secs = (dur.inMilliseconds / 1000.0).toStringAsFixed(1);
                        return Text(
                          '($secs s)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: _showThinkingContent ? AppLocalizations.of(context).collapse : AppLocalizations.of(context).expandMore,
                  onPressed: () => setState(() => _showThinkingContent = !_showThinkingContent),
                  splashRadius: 16,
                  icon: Icon(
                    _showThinkingContent ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (_showThinkingContent) ...[
              const SizedBox(height: 6),
              if (_thinkingText.isEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context).thinkingInProgress,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              else if (_inStreaming)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: _ScrollMaskWrapper(
                    controller: _reasoningPanelScrollController,
                    maskColor: theme.colorScheme.surfaceVariant,
                    child: Scrollbar(
                      child: ListView.builder(
                        controller: _reasoningPanelScrollController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: _thinkingText.replaceAll('\r\n', '\n').split('\n').length,
                        itemBuilder: (context, i) {
                          final parts = _thinkingText.replaceAll('\r\n', '\n').split('\n');
                          return Text(
                            parts[i],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                              height: 1.20,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: _ScrollMaskWrapper(
                    controller: _reasoningPanelScrollController,
                    maskColor: theme.colorScheme.surfaceVariant,
                    child: Scrollbar(
                      child: ListView.builder(
                        controller: _reasoningPanelScrollController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: _thinkingText.replaceAll('\r\n', '\n').split('\n').length,
                        itemBuilder: (context, i) {
                          final parts = _thinkingText.replaceAll('\r\n', '\n').split('\n');
                          return Text(
                            parts[i],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                              height: 1.20,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // 新的底部输入栏（现代化圆角胶囊样式，带流光边框效果和展开按钮）
  Widget _buildComposerBar() {
    final theme = Theme.of(context);
    String _middleEllipsis(String s, int maxChars) {
      if (s.length <= maxChars) return s;
      if (maxChars <= 3) return s.substring(0, maxChars);
      final keep = maxChars - 1; // one char for ellipsis
      final head = (keep / 2).floor();
      final tail = keep - head;
      return s.substring(0, head) + '…' + s.substring(s.length - tail);
    }

    final String modelLabel = (() {
      final mctx = (_ctxChatModel ?? '').trim();
      if (mctx.isNotEmpty) return _middleEllipsis(mctx, 18);
      final legacy = _modelController.text.trim();
      return legacy.isEmpty ? 'AI' : _middleEllipsis(legacy, 18);
    })();
    final placeholder = AppLocalizations.of(context).sendMessageToModelPlaceholder(modelLabel);
    
    Widget barInner = Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24), // 胶囊形状
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 左侧圆形模式切换按钮（普通 <-> 自我）
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _selfMode
                    ? theme.colorScheme.primary.withOpacity(0.12)
                    : theme.colorScheme.surfaceVariant,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    setState(() {
                      _selfMode = !_selfMode;
                    });
                    if (mounted) {
                      final t = AppLocalizations.of(context);
                      UINotifier.center(
                        context,
                        _selfMode
                            ? t.aiSelfModeEnabledToast
                            : t.aiDirectChatModeEnabledToast,
                      );
                    }
                  },
                  child: Center(
                    child: Icon(
                      _selfMode ? Icons.person_rounded : Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: _selfMode ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing1),
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: _inputExpanded ? 3 : 1,
                maxLines: null,
                textAlignVertical: TextAlignVertical.center,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintMaxLines: 1,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: AppTheme.spacing2,
                  ),
                  filled: false,
                ),
                onTap: () {
                  setState(() {
                    _connExpanded = false; // 点击输入收起连接设置
                  });
                },
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            // 圆形发送/停止按钮（保持触达安全但略微更紧凑）
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _sending
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.error,
                          theme.colorScheme.error.withOpacity(0.8),
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withOpacity(0.8),
                        ],
                      ),
                boxShadow: [
                  BoxShadow(
                    color: (_sending ? theme.colorScheme.error : theme.colorScheme.primary).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _sending ? _cancelRequest : _sendMessage,
                  child: Center(
                    child: Icon(
                      _sending ? Icons.close_rounded : Icons.arrow_upward_rounded,
                      color: theme.colorScheme.onPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

    // 自我模式：使用渐变边框与流光；普通模式：不使用渐变框
    if (_selfMode) {
      return _ShimmerBorder(
        active: _inStreaming,
        child: barInner,
      );
    } else {
      return barInner;
    }
  }
   
  
  // 统一的小型选项芯片
  Widget _buildChip(String label, IconData icon, bool selected, VoidCallback onTap) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withOpacity(0.10)
        : theme.colorScheme.surfaceVariant;
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final bd = selected ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing1,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: bd, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 滚动遮罩组件：当列表不在顶部或底部时显示白色渐变遮罩
class _ScrollMaskWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final Color maskColor;
  
  const _ScrollMaskWrapper({
    required this.child,
    required this.controller,
    this.maskColor = Colors.white,
  });

  @override
  State<_ScrollMaskWrapper> createState() => _ScrollMaskWrapperState();
}

class _ScrollMaskWrapperState extends State<_ScrollMaskWrapper> {
  bool _showTopMask = false;
  bool _showBottomMask = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateMasks);
    // 延迟检查初始状态，确保列表已渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateMasks();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateMasks);
    super.dispose();
  }

  void _updateMasks() {
    if (!widget.controller.hasClients) return;
    
    final position = widget.controller.position;
    final atTop = position.pixels <= 0;
    final atBottom = position.pixels >= position.maxScrollExtent;
    
    setState(() {
      _showTopMask = !atTop;
      _showBottomMask = !atBottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // 顶部遮罩
        if (_showTopMask)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 24,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.maskColor.withOpacity(0.9),
                      widget.maskColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // 底部遮罩
        if (_showBottomMask)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 24,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      widget.maskColor.withOpacity(0.9),
                      widget.maskColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// 流光边框效果组件（输入框边框流光 - Gemini AI 风格）
class _ShimmerBorder extends StatefulWidget {
  final Widget child;
  final bool active; // 是否显示流光动画
  const _ShimmerBorder({super.key, required this.child, this.active = false});

  @override
  State<_ShimmerBorder> createState() => _ShimmerBorderState();
}

class _ShimmerBorderState extends State<_ShimmerBorder> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _kBorderRadius = 24.0;
  static const double _kBorderWidth = 2.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_ShimmerBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 根据 active 状态控制动画
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 普通状态的静态彩色渐变
    final staticGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        Color(0xFF4285F4), // Gemini 蓝
        Color(0xFF9B72F2), // 紫色
        Color(0xFFD946EF), // 品红
        Color(0xFFFF6B9D), // 粉红
        Color(0xFFFBBC04), // 金色
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    if (!widget.active) {
      // 静态彩色渐变边框（无动画）
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kBorderRadius),
          gradient: staticGradient,
        ),
        padding: const EdgeInsets.all(_kBorderWidth),
        child: widget.child,
      );
    }

    // 流光动画边框（叠加高亮，不替换静态渐变）
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * 6.283185307179586; // 2π

        // 流光高亮（透明度较高，作为叠加层）
        final sweep = SweepGradient(
          center: Alignment.center,
          colors: const [
            Color(0x004285F4),
            Color(0x334285F4),
            Color(0x6600BCD4),
            Color(0xAA00E5FF),
            Color(0xFF4285F4),
            Color(0xFF9B72F2),
            Color(0xFFD946EF),
            Color(0xFFFF6B9D),
            Color(0xFFFBBC04),
            Color(0xAAFFA726),
            Color(0x334285F4),
            Color(0x004285F4),
          ],
          stops: const [0.00, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 1.00],
          transform: GradientRotation(angle),
        );

        // 底层：静态渐变边框；顶层：仅在边框区域绘制的流光高亮
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kBorderRadius),
                gradient: staticGradient,
              ),
              padding: const EdgeInsets.all(_kBorderWidth),
              child: widget.child,
            ),
            // 仅裁剪到"边框环形区域"的流光叠加层
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RingSweepPainter(
                    gradient: sweep,
                    borderRadius: _kBorderRadius,
                    borderWidth: _kBorderWidth,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// 仅绘制在"边框环形区域"的流光高亮画笔
class _RingSweepPainter extends CustomPainter {
  final Gradient gradient;
  final double borderRadius;
  final double borderWidth;

  _RingSweepPainter({
    required this.gradient,
    required this.borderRadius,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 与 _ShimmerBorder 的圆角一致的外边界
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 画笔设置为描边，仅覆盖边框区域；2x 线宽让内侧可见宽度≈borderWidth
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth * 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path()..addRRect(outer);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RingSweepPainter oldDelegate) {
    return oldDelegate.gradient != gradient ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth;
  }
}
 
// Shimmer widget for flowing white highlight (思考时白色流高亮从左到右移动)
class _Shimmer extends StatefulWidget {
  final Widget child;
  final bool active;
  const _Shimmer({super.key, required this.child, required this.active});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        final value = _ctrl.value; // 0..1
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + 2.0 * value, 0),
              end: Alignment(1.0 + 2.0 * value, 0),
              colors: [
                Colors.transparent,
                Colors.white.withOpacity(0.75),
                Colors.transparent,
              ],
              stops: const [0.43, 0.50, 0.57],
            ).createShader(bounds);
          },
          blendMode: BlendMode.screen,
          child: child!,
        );
      },
    );
  }
}

MarkdownStyleSheet? _cachedMdStyle;
MarkdownStyleSheet _mdStyle(BuildContext context) {
  final s = _cachedMdStyle;
  if (s != null) return s;
  final ns = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: Theme.of(context).textTheme.bodyMedium,
  );
  _cachedMdStyle = ns;
  return ns;
}


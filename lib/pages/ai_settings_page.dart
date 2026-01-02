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
  bool _deepThinking = false; // "深度思考"开关（先做样式，后续可接推理参数）
  bool _webSearch = false; // "联网搜索"开关（先做样式，后续可接搜索参数）
  bool _inStreaming = false; // 当前是否处于助手流式回复中（驱动"思考中"可视化）
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
  final Map<int, List<EvidenceImageAttachment>> _attachmentsByIndex =
      <int, List<EvidenceImageAttachment>>{};
  // 证据图片解析缓存：避免退出/重进或页面重建时重复扫库/扫盘导致“解析中一直不出图”
  final Map<String, Map<String, String>> _evidenceResolvedByMsgKey =
      <String, Map<String, String>>{};
  final Map<String, Future<Map<String, String>>> _evidenceResolveFutures =
      <String, Future<Map<String, String>>>{};
  bool _evidenceRebuildScheduled = false;
  // 上一轮个人助手使用的上下文包（用于后续消息在 AI 判定时可复用）
  QueryContextPack? _lastCtxPack;
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

  // —— Gemini 风蓝色系颜色（供图标/弥散光使用；明暗自适应） ——
  List<Color> _geminiGradientColors(Brightness brightness) {
    // 进一步提亮与增饱和：按"至少值"提升，避免乘法带来的变暗
    Color tune(
      Color c, {
      double sMinLight = 0.98,
      double sMinDark = 0.96,
      double lMinLight = 0.80,
      double lMinDark = 0.72,
    }) {
      final h = HSLColor.fromColor(c);
      final double sTarget = brightness == Brightness.dark
          ? sMinDark
          : sMinLight;
      final double lTarget = brightness == Brightness.dark
          ? lMinDark
          : lMinLight;
      final double s = (h.saturation < sTarget) ? sTarget : h.saturation;
      final double l = (h.lightness < lTarget) ? lTarget : h.lightness;
      return h.withSaturation(s).withLightness(l).toColor();
    }

    // 蓝色主调 + 黄色（去掉青色）
    final Color c1 = tune(const Color(0xFF1F6FEB)); // 深蓝
    final Color c2 = tune(const Color(0xFF3B82F6)); // 标准蓝
    final Color c3 = tune(const Color(0xFF60A5FA)); // 浅蓝
    final Color c4 = tune(const Color(0xFF7C83FF)); // 蓝紫
    // 黄色单独进一步提亮，确保更"亮"更显眼
    final Color cY = tune(
      const Color(0xFFF59E0B),
      lMinLight: 0.86,
      lMinDark: 0.76,
    );
    return [
      c1,
      Color.lerp(c1, c2, 0.5)!,
      c2,
      Color.lerp(c2, c3, 0.5)!,
      c3,
      Color.lerp(c3, c4, 0.5)!,
      c4,
      Color.lerp(c4, cY, 0.45)!,
      cY,
    ];
  }

  //（页面级渐变已移除，应用户要求）

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

  // 提供近期"仅用户消息"的文本，用于意图分析器判断是否续问
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

  // 默认提示词模板内容仅在系统内部维护，不在前端暴露。
  String get _defaultSegmentPromptPreview => '';

  String get _defaultMergePromptPreview => '';

  String get _defaultDailyPromptPreview => '';

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
        // 若是删除事件，先立即清空当前对话UI，避免等待重载造成的"空白延迟"
        if (ctx == 'chat:deleted') {
          setState(() {
            _messages = <AIMessage>[];
            _attachmentsByIndex.clear();
            _reasoningByIndex.clear();
            _reasoningDurationByIndex.clear();
            _currentAssistantIndex = null;
            _inStreaming = false;
            _clarifyState = null;
          });
          _stopInFlightHistoryPersistence();
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
      final Future<String?> fApiKey = _settings.getApiKey().timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );
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
      final bool renderImgs = await _settings.getRenderImagesDuringStreaming();
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
          _baseUrlController.text = (baseUrl == 'https://api.openai.com')
              ? ''
              : baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = (model == 'gpt-4o-mini') ? '' : model;
        } else {
          _baseUrlController.text = baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = model;
        }

        // 分批填充消息，降低单帧构建压力
        _messages = <AIMessage>[];
        _clarifyState = null;
        _attachmentsByIndex.clear();
        _evidenceResolvedByMsgKey.clear();
        _evidenceResolveFutures.clear();
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
        _renderImagesDuringStreaming = renderImgs;
        // 预填编辑器：仅填充用户补充说明，避免暴露系统默认模板
        _promptSegmentController.text = _promptSegment?.trim() ?? '';
        _promptMergeController.text = _promptMerge?.trim() ?? '';
        _promptDailyController.text = _promptDaily?.trim() ?? '';
        _loading = false;
      });
      if (mounted) {
        // 将消息分批追加到列表，避免一次性构建大量 Markdown
        const int batch = 24;
        for (int i = 0; i < history.length; i += batch) {
          final int end = (i + batch > history.length)
              ? history.length
              : (i + batch);
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
      try {
        await FlutterLogger.nativeInfo(
          'UI',
          'AISettings._loadAll setState ms=' +
              sw.elapsedMilliseconds.toString(),
        );
      } catch (_) {}
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
        });
    } finally {
      _loadingAllInFlight = false;
    }
    // 首帧绘制完成耗时（状态更新到绘制）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await FlutterLogger.nativeInfo(
          'UI',
          'AISettings._loadAll first-frame ms=' +
              sw.elapsedMilliseconds.toString(),
        );
      } catch (_) {}
    });
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
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
          UINotifier.success(
            context,
            AppLocalizations.of(context).savedCurrentGroupToast,
          );
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
      UINotifier.error(
        context,
        AppLocalizations.of(context).saveFailedError(e.toString()),
      );
    } finally {
      if (mounted)
        setState(() {
          _saving = false;
        });
    }
  }

  // ======= 提示词管理 =======
  Widget _buildPromptManagerCard() {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    const int maxAddonLength = 2000;

    Widget buildSection({
      required String label,
      required String currentAddon,
      required String infoText,
      required String suggestion,
      required bool editing,
      required TextEditingController controller,
      required VoidCallback onEditToggle,
      required Future<void> Function() onSave,
      required Future<void> Function() onReset,
      required bool saving,
    }) {
      final theme = Theme.of(context);
      final placeholderStyle = theme.textTheme.bodySmall?.copyWith(
        color: theme.hintColor,
      );
      final hasAddon = currentAddon.trim().isNotEmpty;
      final displayText = hasAddon ? currentAddon.trim() : suggestion;
      final displayStyle = hasAddon
          ? theme.textTheme.bodySmall
          : placeholderStyle;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: titleStyle),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: editing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: saving ? null : onSave,
                            child: Text(
                              saving
                                  ? AppLocalizations.of(context).savingLabel
                                  : AppLocalizations.of(context).actionSave,
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          TextButton(
                            onPressed: saving ? null : onReset,
                            child: Text(
                              AppLocalizations.of(context).resetToDefault,
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          TextButton(
                            onPressed: saving ? null : onEditToggle,
                            child: Text(
                              AppLocalizations.of(context).dialogCancel,
                            ),
                          ),
                        ],
                      )
                    : TextButton(
                        onPressed: onEditToggle,
                        child: Text(AppLocalizations.of(context).actionEdit),
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(infoText, style: hintStyle),
          const SizedBox(height: AppTheme.spacing1),
          if (!editing)
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                child: SelectableText(displayText, style: displayStyle),
              ),
            )
          else
            TextField(
              controller: controller,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 10,
              maxLines: null,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: suggestion,
                hintMaxLines: 16,
                contentPadding: const EdgeInsets.all(AppTheme.spacing3),
              ),
            ),
          const SizedBox(height: AppTheme.spacing3),
        ],
      );
    }

    final segAddon = _promptSegment?.trim() ?? '';
    final mergeAddon = _promptMerge?.trim() ?? '';
    final dailyAddon = _promptDaily?.trim() ?? '';
    final addonInfo = AppLocalizations.of(context).promptAddonGeneralInfo;
    final suggestionSegment = AppLocalizations.of(
      context,
    ).promptAddonSuggestionSegment;
    final suggestionMerge = AppLocalizations.of(
      context,
    ).promptAddonSuggestionMerge;
    final suggestionDaily = AppLocalizations.of(
      context,
    ).promptAddonSuggestionDaily;

    return UICard(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 折叠标题（点击展开/收起）
          GestureDetector(
            onTap: () => setState(() {
              _promptExpanded = !_promptExpanded;
            }),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).promptManagerTitle,
                        style: titleStyle,
                      ),
                      const SizedBox(height: 2),
                      Text(_buildPromptSummary(), style: hintStyle),
                    ],
                  ),
                ),
                Icon(_promptExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (_promptExpanded) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              AppLocalizations.of(context).promptManagerHint,
              style: hintStyle,
            ),
            const SizedBox(height: AppTheme.spacing3),

            // 普通事件提示词
            buildSection(
              label: AppLocalizations.of(context).normalEventPromptLabel,
              currentAddon: segAddon,
              infoText: addonInfo,
              suggestion: suggestionSegment,
              editing: _editingPromptSegment,
              controller: _promptSegmentController,
              onEditToggle: () => setState(
                () => _editingPromptSegment = !_editingPromptSegment,
              ),
              onSave: _savePromptSegment,
              onReset: _resetPromptSegment,
              saving: _savingPromptSegment,
            ),

            // 合并事件提示词
            buildSection(
              label: AppLocalizations.of(context).mergeEventPromptLabel,
              currentAddon: mergeAddon,
              infoText: addonInfo,
              suggestion: suggestionMerge,
              editing: _editingPromptMerge,
              controller: _promptMergeController,
              onEditToggle: () =>
                  setState(() => _editingPromptMerge = !_editingPromptMerge),
              onSave: _savePromptMerge,
              onReset: _resetPromptMerge,
              saving: _savingPromptMerge,
            ),
            // 每日总结提示词
            buildSection(
              label: AppLocalizations.of(context).dailySummaryPromptLabel,
              currentAddon: dailyAddon,
              infoText: addonInfo,
              suggestion: suggestionDaily,
              editing: _editingPromptDaily,
              controller: _promptDailyController,
              onEditToggle: () =>
                  setState(() => _editingPromptDaily = !_editingPromptDaily),
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
      final text = _promptSegmentController.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptSegment(normalized);
      if (mounted) {
        setState(() {
          _promptSegment = normalized;
          _promptSegmentController.text = normalized ?? '';
          _editingPromptSegment = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedNormalPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
    } finally {
      if (mounted) setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _resetPromptSegment() async {
    if (_savingPromptSegment) return;
    setState(() => _savingPromptSegment = true);
    try {
      await _settings.setPromptSegment(null);
      if (mounted) {
        setState(() {
          _promptSegment = null;
          _promptSegmentController.text = '';
          _editingPromptSegment = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
    } finally {
      if (mounted) setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _savePromptMerge() async {
    if (_savingPromptMerge) return;
    setState(() => _savingPromptMerge = true);
    try {
      final text = _promptMergeController.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptMerge(normalized);
      if (mounted) {
        setState(() {
          _promptMerge = normalized;
          _promptMergeController.text = normalized ?? '';
          _editingPromptMerge = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedMergePromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
    } finally {
      if (mounted) setState(() => _savingPromptMerge = false);
    }
  }

  Future<void> _resetPromptMerge() async {
    if (_savingPromptMerge) return;
    setState(() => _savingPromptMerge = true);
    try {
      await _settings.setPromptMerge(null);
      if (mounted) {
        setState(() {
          _promptMerge = null;
          _promptMergeController.text = '';
          _editingPromptMerge = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
    } finally {
      if (mounted) setState(() => _savingPromptMerge = false);
    }
  }

  Future<void> _savePromptDaily() async {
    if (_savingPromptDaily) return;
    setState(() => _savingPromptDaily = true);
    try {
      final text = _promptDailyController.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptDaily(normalized);
      if (mounted) {
        setState(() {
          _promptDaily = normalized;
          _promptDailyController.text = normalized ?? '';
          _editingPromptDaily = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedDailyPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
    } finally {
      if (mounted) setState(() => _savingPromptDaily = false);
    }
  }

  Future<void> _resetPromptDaily() async {
    if (_savingPromptDaily) return;
    setState(() => _savingPromptDaily = true);
    try {
      await _settings.setPromptDaily(null);
      if (mounted) {
        setState(() {
          _promptDaily = null;
          _promptDailyController.text = '';
          _editingPromptDaily = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
    } finally {
      if (mounted) setState(() => _savingPromptDaily = false);
    }
  }

  Future<void> _clearHistory() async {
    try {
      await _chat.clearConversation();
      if (!mounted) return;
      setState(() {
        _messages = <AIMessage>[];
        _attachmentsByIndex.clear();
        _evidenceResolvedByMsgKey.clear();
        _evidenceResolveFutures.clear();
        _reasoningByIndex.clear();
        _reasoningDurationByIndex.clear();
        _currentAssistantIndex = null;
        _inStreaming = false;
        _clarifyState = null;
      });
      UINotifier.success(context, AppLocalizations.of(context).clearSuccess);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).clearFailedWithError(e.toString()),
      );
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
    // 仅当粘在底部时，才允许自动滚动；用户上滑后暂停
    if (!_stickToBottom) return;

    final now = DateTime.now();
    final last = _lastAutoScrollTime;
    final elapsed = (last == null)
        ? const Duration(days: 1)
        : now.difference(last);
    if (elapsed.inMilliseconds >= _autoScrollThrottleMs) {
      _lastAutoScrollTime = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_stickToBottom) return;
        _scrollToBottom(animated: false);
      });
    } else if (!_autoScrollPending) {
      _autoScrollPending = true;
      final delay = Duration(
        milliseconds: _autoScrollThrottleMs - elapsed.inMilliseconds,
      );
      Future.delayed(delay, () {
        _autoScrollPending = false;
        if (!mounted || !_stickToBottom) return;
        _lastAutoScrollTime = DateTime.now();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_stickToBottom) return;
          _scrollToBottom(animated: false);
        });
      });
    }
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
    // 迁移为 ReasoningCard 内部自管理省略号动画，避免整页 setState 重建
    // 这里不再执行任何刷新逻辑，仅确保先前计时器被取消
    _dotsTimer?.cancel();
    _dotsTimer = null;
  }

  void _stopDots() {
    _dotsTimer?.cancel();
    _dotsTimer = null;
  }

  void _markInFlightHistoryDirty() {
    if (!_inStreaming) return;
    _inFlightHistoryDirty = true;
    if (_inFlightSaveTimer != null) return;

    // Throttle: write at most once per 2s while streaming/tool-loop is in flight.
    _inFlightSaveTimer = Timer(const Duration(seconds: 2), () {
      _inFlightSaveTimer = null;
      if (!_inStreaming || !_inFlightHistoryDirty) return;
      _inFlightHistoryDirty = false;
      unawaited(() async {
        try {
          final List<AIMessage> merged = _mergeReasoningForPersistence(
            List<AIMessage>.from(_messages),
          );
          await _settings.saveChatHistoryActive(merged);
        } catch (_) {}
        if (_inStreaming && _inFlightHistoryDirty) {
          _markInFlightHistoryDirty();
        }
      }());
    });
  }

  void _stopInFlightHistoryPersistence() {
    _inFlightSaveTimer?.cancel();
    _inFlightSaveTimer = null;
    _inFlightHistoryDirty = false;
  }

  bool _isZhLocale() {
    try {
      return Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
    } catch (_) {
      return true;
    }
  }

  String _clipOneLine(String s, int maxLen) {
    final String t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return '';
    return t.length <= maxLen ? t : (t.substring(0, maxLen) + '…');
  }

  void _appendAgentLog(
    String message, {
    int? assistantIndex,
    bool bullet = true,
  }) {
    if (!mounted) return;
    final int? idx = assistantIndex ?? _currentAssistantIndex;
    if (idx == null || idx < 0 || idx >= _messages.length) return;
    final String t = message.trim();
    if (t.isEmpty) return;
    final String line = (bullet ? '- ' : '') + t;
    setState(() {
      _thinkingText += line + '\n';
      _reasoningByIndex[idx] = (_reasoningByIndex[idx] ?? '') + line + '\n';
    });
    _scheduleAutoScroll();
    _scheduleReasoningPreviewScroll();
    _markInFlightHistoryDirty();
  }

  String _stripMarkdownCodeFences(String text) {
    String t = text.trim();
    if (!t.startsWith('```')) return t;
    t = t.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*```$'), '');
    return t.trim();
  }

  Map<String, dynamic>? _tryParseJsonMap(String text) {
    String t = _stripMarkdownCodeFences(text);
    if (t.isEmpty) return null;
    try {
      final dynamic v = jsonDecode(t);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    final int s = t.indexOf('{');
    final int e = t.lastIndexOf('}');
    if (s >= 0 && e > s) {
      final String sub = t.substring(s, e + 1);
      try {
        final dynamic v = jsonDecode(sub);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return null;
  }

  bool _isCancelMessage(String text) {
    final String t = text.trim();
    if (t.isEmpty) return false;
    const List<String> keys = <String>[
      '取消',
      '算了',
      '不用了',
      '停止',
      '结束',
      '退出',
      '不查了',
      'cancel',
      'stop',
      'quit',
    ];
    final String low = t.toLowerCase();
    for (final k in keys) {
      if (k.length <= 3) {
        if (t == k || low == k) return true;
      } else {
        if (t.contains(k) || low.contains(k)) return true;
      }
    }
    return false;
  }

  String _fmtWindowShort(int startMs, int endMs) {
    if (startMs <= 0 || endMs <= 0) return '';
    final DateTime ds = DateTime.fromMillisecondsSinceEpoch(startMs);
    final DateTime de = DateTime.fromMillisecondsSinceEpoch(endMs);
    final bool sameDay =
        ds.year == de.year && ds.month == de.month && ds.day == de.day;
    if (sameDay) {
      return '${DateFormat('MM-dd HH:mm').format(ds)}–${DateFormat('HH:mm').format(de)}';
    }
    return '${DateFormat('MM-dd HH:mm').format(ds)}–${DateFormat('MM-dd HH:mm').format(de)}';
  }

  String _buildClarifyPromptFallback(_ClarifyState state) {
    final bool zh = _isZhLocale();
    final String q = _clipOneLine(state.originalQuestion, 40);
    final int round = state.askRounds + 1;

    if (zh) {
      final String head = q.isEmpty
          ? '我想帮你尽快定位到对应记录，不过目前线索还不够。'
          : '我明白你想查「$q」，我想帮你尽快定位到对应记录，不过目前线索还不够。';
      if (round <= 1) {
        if (state.reason == _ClarifyReason.tooBroad) {
          return [
            head,
            '这个时间范围可能有点大。你更希望我先从下面两点里补齐哪一个？',
            '1) 更小的时间段（例如：哪一天/上午-下午-晚上/大概几点）',
            '2) 线索关键词/场景（例如：App 名、页面标题里的词、人物/群名、一个数字）',
            '你也可以回复「就查这段时间」，我会先给你一个候选概览再逐步缩小。',
          ].join('\n');
        }
        return [
          head,
          '你可以补充两点线索（想到哪条说哪条就行）：',
          '1) 大概是哪个日期/时间段？（例如：昨天晚上/上周末/10月10日/最近两三天）',
          '2) 更可能发生在什么 App 或场景？（例如：微信/浏览器/B站/抖音/相册）',
          '如果只能给一个模糊范围也没关系，比如「最近一周/最近一个月」。',
        ].join('\n');
      }

      // round 2+
      return [
        '谢谢！我再确认其中一条就能开始查：',
        '1) 更具体的时间范围（哪一天/大概几点/上午-下午-晚上）',
        '2) 一个你记得的关键词或特征（标题/人名/群名/数字/页面元素）',
        '你任选其一补充即可；如果你想直接让我先试着找候选，也可以回复「直接查」。',
      ].join('\n');
    }

    // English fallback
    if (round <= 1) {
      if (state.reason == _ClarifyReason.tooBroad) {
        return [
          (q.isEmpty
              ? 'I can help, but I need a bit more context.'
              : 'I understand you want to find \"$q\". I can help, but I need a bit more context.'),
          'This time range may be too broad. Please reply with ONE of:',
          '1) A narrower time window (date / morning-afternoon-evening / approx. time)',
          '2) A clue keyword or app (app name / title words / person / a number)',
          'If you prefer, reply \"proceed\" and I will try a quick scan first.',
        ].join('\n');
      }
      return [
        (q.isEmpty
            ? 'I can help, but I need a bit more context.'
            : 'I understand you want to find \"$q\". I can help, but I need a bit more context.'),
        'Please reply with any you remember:',
        '1) Approx. time range (e.g. last night / last weekend / a specific date)',
        '2) App or scenario (e.g. WeChat / browser / YouTube)',
      ].join('\n');
    }
    return [
      'Thanks! Just one more clue is enough:',
      '1) A more specific time window, OR',
      '2) A keyword / title word / person / number',
      'You can also reply \"proceed\" to let me try a quick scan.',
    ].join('\n');
  }

  String _composeClarifyAskLlmPrompt(_ClarifyState state) {
    final bool zh = _isZhLocale();
    final int round = state.askRounds + 1;
    final String reason = state.reason == _ClarifyReason.missingTime
        ? 'missing_time'
        : 'too_broad';
    final String timeHint =
        (state.hintStartMs != null && state.hintEndMs != null)
        ? _fmtWindowShort(state.hintStartMs!, state.hintEndMs!)
        : '';
    final String q = state.originalQuestion.trim();
    final String supplements = state.supplements
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => '- $s')
        .join('\n');

    if (zh) {
      return [
        '你是 Screen Memo 的对话助手，正在帮助用户在截图/屏幕记录里定位信息。',
        '现在你需要先向用户做“澄清追问”，以便我能继续检索并给出答案。',
        '',
        '硬性要求：',
        '- 只输出要发给用户的消息正文（不要标题/JSON/代码块/协议说明）',
        '- 语气温和自然，不使用反问句，不阴阳怪气，不责备用户',
        '- 不要使用固定模板套话，尽量结合用户提问自然表达',
        '- 不要输出最终答案，不要编造查找结果',
        '- 最多提出 2 个问题（可以在一句里给出多个可选项）',
        '- 结合用户原话与已补充线索，避免重复询问用户已经回答过的信息',
        '- 给用户一些示例帮助回忆（时间范围、App/场景、关键词/标题词/人物/数字等）',
        '- 如果用户无法给精确时间，也允许给模糊范围（例如：最近一周/最近一个月）',
        '- 可以给一个快捷选项：用户也可以用自然表达告诉你“先用现有线索帮我找找看/先查一下”等，表示希望你先做一次快速检索并给出候选（不要要求用户使用固定关键词）。',
        '',
        '上下文：',
        '- 用户原问题：${q.isEmpty ? '（空）' : q}',
        '- 已补充线索：${supplements.isEmpty ? '（无）' : '\n$supplements'}',
        '- 澄清原因：$reason',
        if (timeHint.isNotEmpty) '- 提示时间窗：$timeHint',
        '- 当前第 $round/2 轮澄清',
      ].join('\n');
    }

    return [
      'You are a Screen Memo assistant helping users locate info from screenshots/records.',
      'Generate ONE clarification message to ask the user for missing details so that you can continue retrieval.',
      '',
      'Hard requirements:',
      '- Output ONLY the message text to the user (no title/JSON/code fences/protocol text).',
      '- Keep a warm, polite tone; no rhetorical questions, no sarcasm, no blame.',
      '- Avoid canned/template-like phrasing; make it feel specific to the user question.',
      '- Do NOT answer the user yet; do NOT fabricate results.',
      '- Ask at most 2 questions.',
      '- Use the user question + collected clues; do not repeat what is already answered.',
      '- Offer examples to help recall (time window, app/scenario, keyword/title/person/number).',
      '- If the user cannot provide an exact time, accept a rough range (e.g., last week / last month).',
      '- Optionally offer a shortcut: the user can reply in natural language to indicate “please proceed with a quick scan using current clues” (do NOT require an exact keyword).',
      '',
      'Context:',
      '- User question: ${q.isEmpty ? '(empty)' : q}',
      '- Collected clues: ${supplements.isEmpty ? '(none)' : '\n$supplements'}',
      '- Reason: $reason',
      if (timeHint.isNotEmpty) '- Hint window: $timeHint',
      '- Clarification round: $round/2',
    ].join('\n');
  }

  Future<String> _buildClarifyPrompt(_ClarifyState state) async {
    try {
      final String prompt = _composeClarifyAskLlmPrompt(state);
      final AIMessage resp = await _chat.sendMessageOneShot(
        prompt,
        context: 'chat',
        timeout: const Duration(seconds: 25),
      );
      final String t = resp.content.trim();
      if (t.isNotEmpty) return t;
    } catch (_) {}
    return _buildClarifyPromptFallback(state);
  }

  String _composeClarifyIntentInput(_ClarifyState state) {
    final String q = state.originalQuestion.trim();
    if (state.supplements.isEmpty) return q;
    final StringBuffer sb = StringBuffer();
    if (q.isNotEmpty) sb.writeln(q);
    sb.writeln();
    sb.writeln('用户补充信息：');
    for (final s in state.supplements) {
      final String t = s.trim();
      if (t.isEmpty) continue;
      sb.writeln('- ' + t);
    }
    return sb.toString().trim();
  }

  String _composeFinalUserQuestionFromClarify(_ClarifyState state) {
    final String q = state.originalQuestion.trim();
    if (state.supplements.isEmpty) return q.isEmpty ? '' : q;
    final StringBuffer sb = StringBuffer();
    if (q.isNotEmpty) sb.writeln(q);
    sb.writeln();
    sb.writeln('补充信息：');
    for (final s in state.supplements) {
      final String t = s.trim();
      if (t.isEmpty) continue;
      sb.writeln('- ' + t);
    }
    return sb.toString().trim();
  }

  bool _isOverlyBroadQuery(
    IntentResult intent,
    String userText, {
    _ClarifyState? clarify,
  }) {
    if (!intent.hasValidRange) return false;
    if (intent.apps.isNotEmpty) return false;
    final int spanMs = intent.endMs - intent.startMs;
    if (spanMs <= 0) return false;
    final Duration span = Duration(milliseconds: spanMs);
    if (span <= const Duration(days: 7)) return false;

    const List<String> summaryHints = <String>[
      '总结',
      '回顾',
      '概览',
      '汇总',
      '统计',
      '复盘',
      '周总结',
      '月总结',
      '时间线',
    ];
    for (final k in summaryHints) {
      if (userText.contains(k)) return false;
    }

    // 语句较长且细节多，允许直接查
    if (userText.trim().length >= 28) return false;

    return true;
  }

  Future<List<_ProbeCandidate>> _probeCandidates({
    required String query,
    _ClarifyState? state,
    int limit = 6,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return const <_ProbeCandidate>[];

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int endMs = state?.hintEndMs ?? now;
    final int fetchLimit = (limit <= 0 || limit > 12) ? 6 : limit;

    Future<List<_ProbeCandidate>?> searchInRange(int startMs, int endMs) async {
      // 1) 优先在 segment_results_fts 中找候选
      try {
        final List<Map<String, dynamic>> segHits = await ScreenshotDatabase
            .instance
            .searchSegmentsByText(
              q,
              limit: fetchLimit,
              offset: 0,
              startMillis: startMs,
              endMillis: endMs,
            );
        if (segHits.isNotEmpty) {
          int idx = 0;
          return segHits
              .map((m) {
                idx += 1;
                final int s = (m['start_time'] as int?) ?? 0;
                final int e = (m['end_time'] as int?) ?? 0;
                final String window = _fmtWindowShort(s, e);
                final String raw =
                    (m['output_text'] as String?)?.trim().isNotEmpty == true
                    ? (m['output_text'] as String).trim()
                    : ((m['structured_json'] as String?)?.trim() ?? '');
                final String summary = _clipOneLine(raw, 80);
                return _ProbeCandidate(
                  index: idx,
                  startMs: s,
                  endMs: e,
                  kind: _ProbeKind.segments,
                  title: window.isEmpty ? '候选 $idx' : window,
                  subtitle: summary.isEmpty ? '（匹配到段落，但缺少摘要文本）' : summary,
                );
              })
              .toList(growable: false);
        }
      } catch (_) {}

      // 2) 回退 OCR 搜索（按 capture_time 取附近时间窗）
      try {
        final List<ScreenshotRecord> shots = await ScreenshotDatabase.instance
            .searchScreenshotsByOcr(
              q,
              limit: fetchLimit,
              offset: 0,
              startMillis: startMs,
              endMillis: endMs,
            );
        if (shots.isNotEmpty) {
          int idx = 0;
          return shots
              .map((r) {
                idx += 1;
                final int t = r.captureTime.millisecondsSinceEpoch;
                final int s = (t - const Duration(minutes: 10).inMilliseconds);
                final int e = (t + const Duration(minutes: 10).inMilliseconds);
                final String title =
                    '${DateFormat('MM-dd HH:mm').format(r.captureTime)} ${r.appName}';
                final String subtitle = _clipOneLine(
                  r.ocrText ?? r.pageUrl ?? '',
                  80,
                );
                return _ProbeCandidate(
                  index: idx,
                  startMs: s < 0 ? 0 : s,
                  endMs: e,
                  kind: _ProbeKind.ocr,
                  title: title,
                  subtitle: subtitle.isEmpty ? '（OCR 命中）' : subtitle,
                );
              })
              .toList(growable: false);
        }
      } catch (_) {}

      return null;
    }

    // 缺时间时：允许逐步扩大窗口，提高“先找找看”的命中率
    if (state?.hintStartMs != null) {
      final int startMs = state!.hintStartMs!;
      final List<_ProbeCandidate>? res = await searchInRange(startMs, endMs);
      return res ?? const <_ProbeCandidate>[];
    }

    final List<int> windowsDays = state?.reason == _ClarifyReason.missingTime
        ? const <int>[30, 180, 365]
        : const <int>[30];
    for (final days in windowsDays) {
      final int startMsRaw = endMs - Duration(days: days).inMilliseconds;
      final int startMs = startMsRaw < 0 ? 0 : startMsRaw;
      final List<_ProbeCandidate>? res = await searchInRange(startMs, endMs);
      if (res != null && res.isNotEmpty) return res;
    }

    return const <_ProbeCandidate>[];
  }

  int? _parsePickIndex(String text, int max) {
    final String t = text.trim();
    if (t.isEmpty) return null;
    final RegExp m = RegExp(r'^(\d{1,2})$');
    final Match? mm = m.firstMatch(t);
    if (mm == null) return null;
    final int n = int.tryParse(mm.group(1) ?? '') ?? 0;
    if (n <= 0 || n > max) return null;
    return n;
  }

  String _composeProbePickLlmPrompt(
    _ClarifyState state,
    List<_ProbeCandidate> cands,
  ) {
    final bool zh = _isZhLocale();
    final String q = state.originalQuestion.trim();
    final String supplements = state.supplements
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => '- $s')
        .join('\n');
    if (cands.isEmpty) {
      if (zh) {
        return [
          '你是 Screen Memo 的对话助手，正在帮助用户在截图/屏幕记录里定位信息。',
          '你刚做了一次快速检索，但没有找到明显候选。',
          '',
          '上下文：',
          '- 用户原问题：${q.isEmpty ? '（空）' : q}',
          '- 已补充线索：${supplements.isEmpty ? '（无）' : '\n$supplements'}',
          '',
          '请生成一条要发给用户的消息：',
          '- 语气温和自然，不反问、不阴阳怪气、不责备',
          '- 不要使用固定模板套话，尽量结合用户提问自然表达',
          '- 不要说“现在开始搜索/正在深度搜索”等；你已经做完快速检索，只需说明“没找到明显候选”',
          '- 不要编造查找结果，不要给最终答案',
          '- 引导用户只补充 1 条最关键线索（时间范围 或 关键词/应用/场景）',
          '- 允许用户回复「取消」结束本次查找',
          '- 只输出消息正文（不要标题/JSON/代码块）',
        ].join('\n');
      }
      return [
        'You are a Screen Memo assistant helping users locate info from screenshots/records.',
        'You just ran a quick scan but found no strong candidates.',
        '',
        'Context:',
        '- User question: ${q.isEmpty ? '(empty)' : q}',
        '- Collected clues: ${supplements.isEmpty ? '(none)' : '\n$supplements'}',
        '',
        'Write ONE message to the user:',
        '- Warm, polite; no rhetorical questions, no sarcasm, no blame.',
        '- Avoid canned/template-like phrasing; make it feel specific to the user question.',
        '- Do NOT say you are \"starting a search now\"; you already finished a quick scan and found no strong candidates.',
        '- Do not fabricate results; do not answer yet.',
        '- Ask the user for ONE key clue (time window OR keyword/app/scenario).',
        '- Allow user to reply \"cancel\" to stop.',
        '- Output only the message text (no title/JSON/code fences).',
      ].join('\n');
    }

    if (zh) {
      final List<Map<String, String>> candList = cands
          .map(
            (c) => <String, String>{
              'index': c.index.toString(),
              'time': _fmtWindowShort(c.startMs, c.endMs),
              'kind': c.kind.name,
              'title': _clipOneLine(c.title, 80),
              'subtitle': _clipOneLine(c.subtitle, 120),
            },
          )
          .toList();
      return [
        '你是 Screen Memo 的对话助手，正在帮助用户在截图/屏幕记录里定位信息。',
        '你已经做了快速检索，下面给你“候选输入”（顺序固定，不要增删改，不要虚构信息）：',
        '',
        '上下文：',
        '- 用户原问题：${q.isEmpty ? '（空）' : q}',
        '- 已补充线索：${supplements.isEmpty ? '（无）' : '\n$supplements'}',
        '- 候选数量：${cands.length}（items 必须同样数量）',
        '',
        '候选输入(JSON)：',
        jsonEncode(candList),
        '',
        '请只输出一个 JSON 对象（不要标题/解释/代码块），结构如下：',
        '{"intro":"...","items":["..."],"outro":"..."}',
        '',
        '要求：',
        '- items 必须是数组，长度必须等于候选数量，并且顺序与候选输入一致',
        '- items 里每个元素是一条候选描述（不要带序号；序号由 App 自动添加）',
        '- intro/outro 是面向用户的自然表达：温和、不反问、不阴阳怪气、不责备，不要使用固定模板套话',
        '- 不要编造候选信息，不要给最终答案',
        '- outro 里引导用户回复序号选择（如 2），或回复「都不是」并补充 1 条新线索；也允许回复「取消」结束',
        '- 整体语言使用中文',
        '',
      ].join('\n');
    }

    final List<Map<String, String>> candList = cands
        .map(
          (c) => <String, String>{
            'index': c.index.toString(),
            'time': _fmtWindowShort(c.startMs, c.endMs),
            'kind': c.kind.name,
            'title': _clipOneLine(c.title, 80),
            'subtitle': _clipOneLine(c.subtitle, 120),
          },
        )
        .toList();
    return [
      'You are a Screen Memo assistant helping users locate info from screenshots/records.',
      'You already ran a quick scan. Here are the candidates input (fixed order; do not add/remove; do not invent).',
      '',
      'Context:',
      '- User question: ${q.isEmpty ? '(empty)' : q}',
      '- Collected clues: ${supplements.isEmpty ? '(none)' : '\n$supplements'}',
      '- Candidate count: ${cands.length} (items must match this count)',
      '',
      'Candidates input (JSON):',
      jsonEncode(candList),
      '',
      'Output ONLY one JSON object (no title/explanations/code fences) with this structure:',
      '{"intro":"...","items":["..."],"outro":"..."}',
      '',
      'Requirements:',
      '- items must be an array with EXACTLY the same length as the candidate count and in the same order.',
      '- Each items[i] is a user-facing description for candidate i (do NOT include numbering; the app will add numbers).',
      '- intro/outro should be warm and natural (no rhetorical questions, no sarcasm, no blame; avoid canned phrasing).',
      '- Do not fabricate candidate info; do not answer yet.',
      '- In outro, ask the user to reply with the number (e.g., 2), or reply \"none\" with ONE more clue; allow \"cancel\" to stop.',
      '- Use English.',
      '',
    ].join('\n');
  }

  String _buildProbePickMessageFallback(
    _ClarifyState state,
    List<_ProbeCandidate> cands,
  ) {
    final bool zh = _isZhLocale();
    if (cands.isEmpty) {
      if (zh) {
        return [
          '我先根据现有线索做了一次小范围查找，但没有找到明显候选。',
          '你可以再补充其中一条线索：',
          '1) 更具体的日期/时间段',
          '2) App 名 / 关键词 / 标题里的词',
          '（也可以回复「取消」结束本次查找）',
        ].join('\n');
      }
      return [
        'I tried a quick scan but found no strong candidates.',
        'Please add ONE clue: time window OR app/keyword.',
        '(Or reply \"cancel\" to stop.)',
      ].join('\n');
    }

    final List<String> lines = <String>[];
    if (zh) {
      lines.add('我先根据你给的线索做了一次小范围查找，找到了这些可能的候选：');
      for (final c in cands) {
        lines.add('${c.index}) ${c.title}');
        if (c.subtitle.trim().isNotEmpty) {
          lines.add('   - ${c.subtitle}');
        }
      }
      lines.add('');
      lines.add('你可以回复序号（如 2），或回复「都不是」并补充一条新线索。');
      lines.add('（也可以回复「取消」结束本次查找）');
      return lines.join('\n');
    }

    lines.add('I did a quick scan and found these candidates:');
    for (final c in cands) {
      lines.add('${c.index}) ${c.title}');
      if (c.subtitle.trim().isNotEmpty) lines.add('   - ${c.subtitle}');
    }
    lines.add('');
    lines.add(
      'Reply with the number (e.g., 2), or reply \"none\" with one more clue.',
    );
    lines.add('(Or reply \"cancel\" to stop.)');
    return lines.join('\n');
  }

  Future<String> _buildProbePickMessage(
    _ClarifyState state,
    List<_ProbeCandidate> cands,
  ) async {
    if (cands.isEmpty) {
      try {
        final String prompt = _composeProbePickLlmPrompt(state, cands);
        final AIMessage resp = await _chat.sendMessageOneShot(
          prompt,
          context: 'chat',
          timeout: const Duration(seconds: 25),
        );
        final String t = resp.content.trim();
        if (t.isNotEmpty) return t;
      } catch (_) {}
      return _buildProbePickMessageFallback(state, cands);
    }

    String lastRaw = '';
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final bool zh = _isZhLocale();
        final String retryHint = zh
            ? '上一条输出不符合要求（必须是严格 JSON，且 items 数量匹配）。请你只输出符合结构的 JSON，不要任何多余文字。'
            : 'Your previous output is invalid (must be strict JSON and items length must match). Please output ONLY valid JSON with the required structure. No extra text.';
        final String prevLabel = zh
            ? '上次输出(供参考)：'
            : 'Previous output (for reference):';
        final String prompt = attempt == 0
            ? _composeProbePickLlmPrompt(state, cands)
            : [
                _composeProbePickLlmPrompt(state, cands),
                '',
                retryHint,
                prevLabel,
                _clipOneLine(lastRaw, 800),
              ].join('\n');
        final AIMessage resp = await _chat.sendMessageOneShot(
          prompt,
          context: 'chat',
          timeout: const Duration(seconds: 25),
        );
        final String raw = resp.content.trim();
        lastRaw = raw;
        if (raw.isEmpty) continue;

        final Map<String, dynamic>? obj = _tryParseJsonMap(raw);
        if (obj == null) continue;
        final dynamic itemsDyn = obj['items'];
        if (itemsDyn is! List || itemsDyn.length != cands.length) continue;

        final String intro = (obj['intro'] as String? ?? '').trim();
        final String outro = (obj['outro'] as String? ?? '').trim();
        final List<String> items = itemsDyn
            .map((e) => e.toString().trim())
            .toList();

        final List<String> lines = <String>[];
        if (intro.isNotEmpty) lines.add(intro);
        for (int i = 0; i < items.length; i++) {
          final String it = items[i].trim();
          final String fallback = _clipOneLine(
            [
              cands[i].title,
              cands[i].subtitle,
            ].where((s) => s.trim().isNotEmpty).join(' · '),
            120,
          );
          lines.add('${i + 1}) ${it.isEmpty ? fallback : it}');
        }
        if (outro.isNotEmpty) {
          lines.add('');
          lines.add(outro);
        }
        final String msg = lines.join('\n').trim();
        if (msg.isNotEmpty) return msg;
      } catch (_) {
        continue;
      }
    }

    return _buildProbePickMessageFallback(state, cands);
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).messageCannotBeEmpty,
      );
      return;
    }
    setState(() {
      _sending = true;
    });
    try {
      // 先本地追加用户消息，提升即时反馈
      setState(() {
        _messages = List<AIMessage>.from(_messages)
          ..add(AIMessage(role: 'user', content: text));
      });
      _inputController.clear();
      _scheduleAutoScroll();

      if (_streamEnabled) {
        // 追加一个空的助手消息作为占位，并进入"思考中"可视化状态
        final int assistantIdx = _messages.length;
        QueryContextPack? ctxPackForRewrite;
        setState(() {
          _inStreaming = true;
          _thinkingText = '';
          _showThinkingContent = false; // 默认折叠
          // 使用当前时刻作为占位消息的 createdAt，用于正确计算思考耗时
          _messages = List<AIMessage>.from(_messages)
            ..add(
              AIMessage(
                role: 'assistant',
                content: '',
                createdAt: DateTime.now(),
              ),
            );
          _currentAssistantIndex = assistantIdx;
          _reasoningByIndex[assistantIdx] = '';
          _reasoningDurationByIndex.remove(assistantIdx);
        });
        _markInFlightHistoryDirty();
        _startDots();
        _scheduleAutoScroll();
        _scheduleReasoningPreviewScroll();
        _appendAgentLog(
          _isZhLocale() ? '开始处理本次请求' : 'Start handling request',
          bullet: false,
        );

        // 阶段 1/4：意图分析
        try {
          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase1 intent begin text="${text.length > 200 ? (text.substring(0, 200) + '…') : text}"',
          );
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
          _appendAgentLog(
            _isZhLocale() ? '阶段 1/4：意图分析' : 'Phase 1/4: intent analysis',
            bullet: false,
          );

          IntentResult? intent;
          String userQuestionForFinal = text;
          bool localOnlyResponse = false;
          String localAssistantText = '';
          AIStreamingSession? session;
          late QueryContextPack ctxPack;
          bool reuse = false;

          // 0) 如果处于澄清流程且用户选择取消，则结束本次查找
          if (_clarifyState != null && _isCancelMessage(text)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '检测到取消指令：本次查找结束（不发起网络请求）'
                  : 'Cancel detected: stop (no network request)',
            );
            _clarifyState = null;
            localOnlyResponse = true;
            localAssistantText = _isZhLocale()
                ? '好的，已取消本次查找。你可以随时再问我。'
                : 'Ok, canceled. You can ask again anytime.';
          }

          // 1) 若正在等待“候选选择”，优先处理用户选择（回复序号）
          final _ClarifyState? clarify0 = _clarifyState;
          if (!localOnlyResponse &&
              clarify0 != null &&
              clarify0.stage == _ClarifyStage.pickCandidate) {
            _appendAgentLog(
              _isZhLocale()
                  ? '澄清流程：解析候选选择…'
                  : 'Clarification: parsing candidate selection…',
            );
            final int? pick = _parsePickIndex(text, clarify0.candidates.length);
            if (pick != null) {
              final _ProbeCandidate c = clarify0.candidates[pick - 1];
              _appendAgentLog(
                _isZhLocale()
                    ? '已选择候选 #$pick，定位时间窗…'
                    : 'Picked candidate #$pick, using its time window…',
              );
              String tzReadable() {
                final Duration off = DateTime.now().timeZoneOffset;
                final int mins = off.inMinutes;
                final String sign = mins >= 0 ? '+' : '-';
                final int abs = mins.abs();
                final String hh = (abs ~/ 60).toString().padLeft(2, '0');
                final String mm = (abs % 60).toString().padLeft(2, '0');
                return 'UTC$sign$hh:$mm';
              }

              intent = IntentResult(
                intent: 'pick_candidate',
                intentSummary: _isZhLocale() ? '根据候选定位' : 'Locate by candidate',
                startMs: c.startMs,
                endMs: c.endMs,
                timezone: tzReadable(),
                apps: const <String>[],
                sqlFill: const <String, dynamic>{},
                skipContext: false,
                contextAction: 'refresh',
              );
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarify0,
              );
              _clarifyState = null;
            } else {
              // 不是序号：视为“都不是/补充线索”，直接根据新线索再跑一次探测检索
              if (!_isCancelMessage(text)) {
                clarify0.supplements.add(text);
              }
              final String probeQ = _clipOneLine(
                _composeFinalUserQuestionFromClarify(clarify0),
                80,
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '未识别到序号：基于补充线索做一次探测检索…'
                    : 'No pick index: probing candidates from supplemental hints…',
              );
              final Stopwatch swProbe = Stopwatch()..start();
              final List<_ProbeCandidate> cands = await _probeCandidates(
                query: probeQ.isEmpty ? _clipOneLine(text, 80) : probeQ,
                state: clarify0,
                limit: 6,
              );
              swProbe.stop();
              _appendAgentLog(
                _isZhLocale()
                    ? '探测检索完成：候选 ${cands.length}（${swProbe.elapsedMilliseconds}ms）'
                    : 'Probe done: ${cands.length} candidates (${swProbe.elapsedMilliseconds}ms)',
              );
              clarify0.candidates
                ..clear()
                ..addAll(cands);
              clarify0.stage = _ClarifyStage.pickCandidate;
              clarify0.lastProbeKind = cands.isNotEmpty
                  ? cands.first.kind
                  : _ProbeKind.none;
              localAssistantText = await _buildProbePickMessage(
                clarify0,
                cands,
              );
              localOnlyResponse = true;
            }
          }

          // 2) 正常意图分析（或澄清补充阶段：将补充信息合并进分析输入）
          if (!localOnlyResponse && intent == null) {
            String analyzeInput = text;
            final _ClarifyState? clarifyAsk = _clarifyState;
            if (clarifyAsk != null && clarifyAsk.stage == _ClarifyStage.ask) {
              // 将本轮用户输入作为补充信息
              if (!_isCancelMessage(text)) clarifyAsk.supplements.add(text);
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarifyAsk,
              );
              analyzeInput = _composeClarifyIntentInput(clarifyAsk);
            }

            if (!localOnlyResponse) {
              final String preview = _clipOneLine(analyzeInput, 80);
              _appendAgentLog(
                _isZhLocale()
                    ? '调用意图分析模型…${preview.isEmpty ? '' : ' input="' + preview + '"'}'
                    : 'Calling intent model…${preview.isEmpty ? '' : ' input=\"' + preview + '\"'}',
              );
              final Stopwatch swIntent = Stopwatch()..start();
              intent = await IntentAnalysisService.instance.analyze(
                analyzeInput,
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
              swIntent.stop();
              final String range = intent!.hasValidRange
                  ? '[${intent!.startMs}-${intent!.endMs}]'
                  : '<invalid>';
              final String err = (intent!.errorCode ?? '').trim();
              _appendAgentLog(
                _isZhLocale()
                    ? '意图解析完成：${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err}（${swIntent.elapsedMilliseconds}ms）'
                    : 'Intent done: ${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err} (${swIntent.elapsedMilliseconds}ms)',
              );
            }
          }

          // 3) 缺少有效时间窗：优先在“续问”场景复用上一轮，否则进入温和澄清
          if (!localOnlyResponse && intent != null && !intent!.hasValidRange) {
            _appendAgentLog(
              _isZhLocale()
                  ? '未解析到有效时间窗：尝试复用上一轮或进入澄清…'
                  : 'No valid time range: try reuse previous or ask to clarify…',
            );
            final bool hasPreviousWindow =
                (_lastIntent != null && _lastIntent!.hasValidRange) ||
                (_lastCtxPack != null) ||
                (QueryContextService.instance.lastPack != null);
            final bool canReusePrevious =
                hasPreviousWindow && intent!.skipContext;
            if (canReusePrevious) {
              _appendAgentLog(
                _isZhLocale()
                    ? '尝试复用上一轮时间窗…'
                    : 'Trying to reuse previous time window…',
              );
              int? fbStart;
              int? fbEnd;
              if (_lastIntent != null && _lastIntent!.hasValidRange) {
                fbStart = _lastIntent!.startMs;
                fbEnd = _lastIntent!.endMs;
              } else if (_lastCtxPack != null) {
                fbStart = _lastCtxPack!.startMs;
                fbEnd = _lastCtxPack!.endMs;
              } else if (QueryContextService.instance.lastPack != null) {
                final p = QueryContextService.instance.lastPack!;
                fbStart = p.startMs;
                fbEnd = p.endMs;
              }
              if (fbStart != null && fbEnd != null && fbEnd >= fbStart) {
                _appendAgentLog(
                  _isZhLocale()
                      ? '已复用上一轮时间窗：[$fbStart-$fbEnd]'
                      : 'Reused previous window: [$fbStart-$fbEnd]',
                );
                intent = IntentResult(
                  intent: intent!.intent,
                  intentSummary: intent!.intentSummary.isNotEmpty
                      ? intent!.intentSummary
                      : '复用上一轮时间窗',
                  startMs: fbStart,
                  endMs: fbEnd,
                  timezone: intent!.timezone,
                  apps: intent!.apps,
                  sqlFill: intent!.sqlFill,
                  skipContext: true,
                  errorCode: intent!.errorCode,
                  errorMessage: intent!.errorMessage,
                );
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '复用失败：没有可用的上一轮范围，转入澄清'
                      : 'Reuse failed: no previous window, switching to clarification',
                );
                localOnlyResponse = true;
                localAssistantText = _isZhLocale()
                    ? '我想沿用上一轮时间窗来继续查找，但没有找到可复用的上一轮范围。你可以补充一下大概的日期/时间段吗？'
                    : 'I tried to reuse the previous time window, but none is available. Could you provide an approximate time range?';
                _clarifyState = _ClarifyState(
                  originalQuestion: userQuestionForFinal,
                  reason: _ClarifyReason.missingTime,
                );
              }
            } else {
              _appendAgentLog(
                _isZhLocale()
                    ? '进入澄清流程：需要用户补充时间线索'
                    : 'Entering clarification: need more time hints from user',
              );
              // 进入澄清流程：最多两轮温和追问，之后给出候选让用户选择
              _ClarifyState st;
              if (_clarifyState == null) {
                st = _ClarifyState(
                  originalQuestion: userQuestionForFinal,
                  reason: _ClarifyReason.missingTime,
                );
                _clarifyState = st;
              } else {
                final old = _clarifyState!;
                if (old.reason == _ClarifyReason.missingTime) {
                  st = old;
                } else {
                  st = _ClarifyState(
                    originalQuestion: old.originalQuestion,
                    reason: _ClarifyReason.missingTime,
                    hintStartMs: old.hintStartMs,
                    hintEndMs: old.hintEndMs,
                  );
                  st
                    ..supplements.addAll(old.supplements)
                    ..askRounds = old.askRounds
                    ..stage = old.stage;
                  _clarifyState = st;
                }
              }

              final bool userWantsProceed = intent!.userWantsProceed;
              if (st.askRounds < 2 && !userWantsProceed) {
                st.stage = _ClarifyStage.ask;
                st.candidates.clear();
                localAssistantText = await _buildClarifyPrompt(st);
                st.askRounds += 1;
                localOnlyResponse = true;
              } else {
                st.askRounds = 2;
                final String probeQuery = intent!.keywords.isNotEmpty
                    ? intent!.keywords.join(' ')
                    : _composeFinalUserQuestionFromClarify(st);
                final String probeQ = _clipOneLine(probeQuery, 80);
                final List<_ProbeCandidate> cands = await _probeCandidates(
                  query: probeQ.isEmpty
                      ? _clipOneLine(userQuestionForFinal, 80)
                      : probeQ,
                  state: st,
                  limit: 6,
                );
                st.candidates
                  ..clear()
                  ..addAll(cands);
                st.stage = _ClarifyStage.pickCandidate;
                st.lastProbeKind = cands.isNotEmpty
                    ? cands.first.kind
                    : _ProbeKind.none;
                localAssistantText = await _buildProbePickMessage(st, cands);
                localOnlyResponse = true;
              }
            }
          }

          // 4) 时间范围过大且缺少线索：先温和引导缩小范围（允许用户回复“就查/直接查”跳过）
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.userWantsProceed &&
              _isOverlyBroadQuery(
                intent!,
                userQuestionForFinal,
                clarify: _clarifyState,
              )) {
            _ClarifyState st;
            if (_clarifyState != null &&
                _clarifyState!.reason == _ClarifyReason.tooBroad) {
              st = _clarifyState!;
            } else {
              st = _ClarifyState(
                originalQuestion: userQuestionForFinal,
                reason: _ClarifyReason.tooBroad,
                hintStartMs: intent!.startMs,
                hintEndMs: intent!.endMs,
              );
              _clarifyState = st;
            }

            if (st.askRounds < 2) {
              st.stage = _ClarifyStage.ask;
              st.candidates.clear();
              localAssistantText = await _buildClarifyPrompt(st);
              st.askRounds += 1;
              _appendAgentLog(
                _isZhLocale()
                    ? '向用户追问时间范围（第 ${st.askRounds}/2 轮）'
                    : 'Asking for time range (round ${st.askRounds}/2)',
              );
              localOnlyResponse = true;
            } else {
              st.askRounds = 2;
              final String probeQuery = intent!.keywords.isNotEmpty
                  ? intent!.keywords.join(' ')
                  : _composeFinalUserQuestionFromClarify(st);
              final String probeQ = _clipOneLine(probeQuery, 80);
              _appendAgentLog(
                _isZhLocale()
                    ? '仍无法确定时间：基于关键词/问题做探测检索，生成候选…'
                    : 'Still ambiguous: probing candidates by keywords/question…',
              );
              final Stopwatch swProbe2 = Stopwatch()..start();
              final List<_ProbeCandidate> cands = await _probeCandidates(
                query: probeQ.isEmpty ? _clipOneLine(text, 80) : probeQ,
                state: st,
                limit: 6,
              );
              swProbe2.stop();
              _appendAgentLog(
                _isZhLocale()
                    ? '候选生成完成：${cands.length}（${swProbe2.elapsedMilliseconds}ms）'
                    : 'Candidates ready: ${cands.length} (${swProbe2.elapsedMilliseconds}ms)',
              );
              st.candidates
                ..clear()
                ..addAll(cands);
              st.stage = _ClarifyStage.pickCandidate;
              st.lastProbeKind = cands.isNotEmpty
                  ? cands.first.kind
                  : _ProbeKind.none;
              localAssistantText = await _buildProbePickMessage(st, cands);
              localOnlyResponse = true;
            }
          }

          if (localOnlyResponse) {
            _appendAgentLog(
              _isZhLocale()
                  ? '本轮进入本地澄清/候选回复：不进行上下文检索与回答生成'
                  : 'Local clarification/candidates: skip context retrieval and answering',
            );
            setState(() {
              final lastIdx = _messages.length - 1;
              final last = _messages[lastIdx];
              if (last.role == 'assistant') {
                _messages[lastIdx] = AIMessage(
                  role: 'assistant',
                  content: localAssistantText,
                  createdAt: last.createdAt,
                );
              }
            });
            // 本地澄清/候选不走流式网络请求
            _stopDots();
            session = null;
          } else {
            // 已收集到足够线索：进入正常检索与回答流程
            if (_clarifyState != null &&
                intent != null &&
                intent!.hasValidRange) {
              // 清理澄清状态，避免污染下一轮
              _clarifyState = null;
            }

            final IntentResult resolvedIntent = intent!;
            await FlutterLogger.nativeInfo(
              'ChatFlow',
              'phase1 intent ok range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}] summary=${resolvedIntent.intentSummary} apps=${resolvedIntent.apps.length}',
            );
            _appendAgentLog(
              _isZhLocale()
                  ? '意图已确认：${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]'
                  : 'Intent confirmed: ${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]',
            );

            // 显示意图摘要与时间窗
            setState(() {
              final lastIdx = _messages.length - 1;
              final last = _messages[lastIdx];
              if (last.role == 'assistant') {
                final start = DateTime.fromMillisecondsSinceEpoch(
                  resolvedIntent.startMs,
                );
                final end = DateTime.fromMillisecondsSinceEpoch(
                  resolvedIntent.endMs,
                );
                String two(int v) => v.toString().padLeft(2, '0');
                String ymd(DateTime d) =>
                    '${d.year}-${two(d.month)}-${two(d.day)}';
                final String dateLine =
                    (start.year == end.year &&
                        start.month == end.month &&
                        start.day == end.day)
                    ? '日期: ' + ymd(start)
                    : '日期: ' + ymd(start) + ' → ' + ymd(end);
                final String range =
                    '${two(start.hour)}:${two(start.minute)}-${two(end.hour)}:${two(end.minute)}';
                final updated =
                    '1/4 意图: ${resolvedIntent.intentSummary}\n' +
                    dateLine +
                    '\n时间: ' +
                    range +
                    ' (' +
                    resolvedIntent.timezone +
                    ')\n\n2/4 查找上下文…';
                _messages[lastIdx] = AIMessage(
                  role: 'assistant',
                  content: updated,
                  createdAt: last.createdAt,
                );
              }
            });

            // 阶段 2/4：查找上下文（若 AI 判定可复用上一轮上下文，则跳过新的检索）
            await FlutterLogger.nativeInfo('ChatFlow', '阶段2 上下文开始');
            _appendAgentLog(
              _isZhLocale() ? '阶段 2/4：查找上下文' : 'Phase 2/4: building context',
              bullet: false,
            );
            final String ctxAction = (resolvedIntent.contextAction)
                .trim()
                .toLowerCase();
            reuse =
                resolvedIntent.skipContext &&
                ctxAction == 'reuse' &&
                (_lastCtxPack != null ||
                    QueryContextService.instance.lastPack != null);
            _appendAgentLog(
              _isZhLocale()
                  ? '复用上一轮上下文：' + (reuse ? '是' : '否')
                  : 'Reuse previous context: ' + (reuse ? 'yes' : 'no'),
            );
            _appendAgentLog(
              _isZhLocale()
                  ? '上下文策略：' + ctxAction
                  : 'Context action: ' + ctxAction,
            );
            if (resolvedIntent.skipContext && !reuse) {
              _appendAgentLog(
                _isZhLocale()
                    ? '意图模型建议不复用缓存上下文，将重新检索/翻页以获取更多证据。'
                    : 'Intent model suggests not reusing cached context; will refresh/page for more evidence.',
              );
            }

            // 不限制上下文事件数量；预加载少量证据图片“文件名/路径”（不预加载像素）。
            // 目的：让模型可以直接引用 filename（而不是臆造），从而在 UI 中稳定渲染图片证据。
            const int maxEvents = 0;
            // 证据图片：预加载文件名/路径（不预加载像素）；段内最多 15 张，总计最多 360 张（并尽量在段落间均匀分配）。
            const int maxImagesTotal = 360;
            const int maxImagesPerEvent = 15;

            // 当范围超过 7 天时，按周预加载（避免提示词过大导致超时/输入上限）。
            final int fullStartMs = resolvedIntent.startMs;
            final int fullEndMs = resolvedIntent.endMs;
            int preloadStartMs = fullStartMs;
            int preloadEndMs = fullEndMs;
            final bool windowed =
                (fullEndMs - fullStartMs) > AIChatService.maxToolTimeSpanMs;
            if (windowed) {
              preloadEndMs = fullEndMs;
              preloadStartMs = fullEndMs - AIChatService.maxToolTimeSpanMs;
              if (preloadStartMs < fullStartMs) preloadStartMs = fullStartMs;
              _appendAgentLog(
                _isZhLocale()
                    ? '时间范围较大：上下文按周分页，本次预加载 7 天窗口 range=[$preloadStartMs-$preloadEndMs]'
                    : 'Large time range: paging context by week; preloading a 7-day window range=[$preloadStartMs-$preloadEndMs]',
              );
            }

            // When the intent model asks to page within a multi-week range, move the
            // 7-day preload window accordingly instead of repeatedly using the same week.
            if (windowed &&
                !reuse &&
                (ctxAction == 'page_prev' || ctxAction == 'page_next')) {
              final QueryContextPack? prevPack =
                  (_lastCtxPack ?? QueryContextService.instance.lastPack);
              if (prevPack != null &&
                  prevPack.startMs >= fullStartMs &&
                  prevPack.endMs <= fullEndMs) {
                if (ctxAction == 'page_prev' &&
                    prevPack.startMs > fullStartMs) {
                  final int prevEnd0 = prevPack.startMs - 1;
                  int nextEndMs = prevEnd0;
                  if (nextEndMs < fullStartMs) nextEndMs = fullStartMs;
                  int nextStartMs = nextEndMs - AIChatService.maxToolTimeSpanMs;
                  if (nextStartMs < fullStartMs) nextStartMs = fullStartMs;
                  if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                  preloadStartMs = nextStartMs;
                  preloadEndMs = nextEndMs;
                  _appendAgentLog(
                    _isZhLocale()
                        ? '自动翻页：加载上一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                        : 'Auto paging: load previous week range=[$preloadStartMs-$preloadEndMs]',
                  );
                } else if (ctxAction == 'page_next' &&
                    prevPack.endMs < fullEndMs) {
                  final int nextStart0 = prevPack.endMs + 1;
                  int nextStartMs = nextStart0;
                  if (nextStartMs > fullEndMs) nextStartMs = fullEndMs;
                  int nextEndMs = nextStartMs + AIChatService.maxToolTimeSpanMs;
                  if (nextEndMs > fullEndMs) nextEndMs = fullEndMs;
                  if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                  preloadStartMs = nextStartMs;
                  preloadEndMs = nextEndMs;
                  _appendAgentLog(
                    _isZhLocale()
                        ? '自动翻页：加载下一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                        : 'Auto paging: load next week range=[$preloadStartMs-$preloadEndMs]',
                  );
                } else {
                  _appendAgentLog(
                    _isZhLocale()
                        ? '已到达可翻页边界（或窗口无变化），将按当前周继续检索。'
                        : 'Reached paging boundary (or no window change); continue with current window.',
                  );
                }
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '无可用缓存窗口用于翻页，将按当前周继续检索。'
                      : 'No cached window for paging; continue with current window.',
                );
              }
            }

            if (reuse) {
              _appendAgentLog(
                _isZhLocale() ? '使用缓存上下文包' : 'Using cached context pack',
              );
              ctxPack =
                  (_lastCtxPack ?? QueryContextService.instance.lastPack!);
              ctxPackForRewrite = ctxPack;
            } else {
              _appendAgentLog(
                _isZhLocale()
                    ? '查询本地数据库并组装上下文…'
                    : 'Querying local DB and assembling context…',
              );
              final Stopwatch swCtx = Stopwatch()..start();
              ctxPack = await QueryContextService.instance.buildContext(
                startMs: preloadStartMs,
                endMs: preloadEndMs,
                maxEvents: maxEvents,
                maxImagesTotal: maxImagesTotal,
                maxImagesPerEvent: maxImagesPerEvent,
                includeImages: true,
              );
              ctxPackForRewrite = ctxPack;
              swCtx.stop();
              _appendAgentLog(
                _isZhLocale()
                    ? '上下文组装完成：events=${ctxPack.events.length}（${swCtx.elapsedMilliseconds}ms）'
                    : 'Context ready: events=${ctxPack.events.length} (${swCtx.elapsedMilliseconds}ms)',
              );
            }
            await FlutterLogger.nativeInfo(
              'ChatFlow',
              'phase2 context ok events=${ctxPack.events.length} reuse=${reuse ? 1 : 0}',
            );
            // 缓存上下文（页面内缓存与服务级缓存），便于紧邻多轮对话复用
            _lastCtxPack = ctxPack;
            try {
              QueryContextService.instance.setLastPack(ctxPack);
            } catch (_) {}
            // 证据图片像素不预加载；仅预加载少量文件名/路径，供 UI 渲染与模型引用。
            final List<EvidenceImageAttachment> attachments = (() {
              final Set<String> seen = <String>{};
              final List<EvidenceImageAttachment> out =
                  <EvidenceImageAttachment>[];
              for (final ev in ctxPack.events) {
                for (final a in ev.keyImages) {
                  if (a.path.isEmpty) continue;
                  if (seen.add(a.path)) out.add(a);
                }
              }
              return out;
            })();
            _appendAgentLog(
              _isZhLocale()
                  ? '证据图片：预加载文件名/路径 ${attachments.length} 条（不预加载像素；需要看原图像素再用 get_images）'
                  : 'Evidence images: preloaded filenames/paths ${attachments.length} (pixels not preloaded; use get_images when you must see pixels)',
            );
            setState(() {
              _attachmentsByIndex[assistantIdx] = attachments;
              final lastIdx = _messages.length - 1;
              final last = _messages[lastIdx];
              if (last.role == 'assistant') {
                final updated =
                    '2/4 查找上下文完成${reuse ? '（复用上一轮）' : ''}：事件 ${ctxPack.events.length}${windowed ? '（预加载 7 天窗口）' : ''}\n\n3/4 生成回答…';
                _messages[lastIdx] = AIMessage(
                  role: 'assistant',
                  content: updated,
                  createdAt: last.createdAt,
                );
              }
            });

            // 生成最终提示词（包含上下文包的精简文本）
            final String finalQuery = _buildFinalQuestion(
              userQuestionForFinal,
              ctxPack,
              fullStartMs: fullStartMs,
              fullEndMs: fullEndMs,
            );
            await FlutterLogger.nativeDebug(
              'ChatFlow',
              'phase3 finalQueryLen=${finalQuery.length}',
            );
            _appendAgentLog(
              _isZhLocale() ? '阶段 3/4：生成回答' : 'Phase 3/4: generating answer',
              bullet: false,
            );
            _appendAgentLog(
              _isZhLocale()
                  ? '生成最终提示词：len=${finalQuery.length}'
                  : 'Final prompt: len=${finalQuery.length}',
            );
            _replaceAssistantContentOnNextToken = true; // 首个 token 到来时清空阶段状态

            // 使用"显示内容与实际发送内容分离"的新流式接口：
            final String sysDateGuard = _buildDateGuardSystemMessage(
              startMs: fullStartMs,
              endMs: fullEndMs,
            );
            final List<Map<String, dynamic>> chatTools =
                AIChatService.defaultChatTools();
            final bool forceToolFirstIfNoToolCalls =
                ctxPack.events.isEmpty ||
                resolvedIntent.intent == 'keyword_lookup' ||
                resolvedIntent.keywords.isNotEmpty;
            _appendAgentLog(
              _isZhLocale()
                  ? '调用模型并启用工具：tools=${chatTools.length} tool_choice=auto'
                  : 'Calling model with tools: tools=${chatTools.length} tool_choice=auto',
            );
            session = await _chat.sendMessageStreamedV2WithDisplayOverride(
              text,
              finalQuery,
              includeHistory: resolvedIntent.skipContext,
              extraSystemMessages: <String>[sysDateGuard],
              tools: chatTools,
              toolChoice: 'auto',
              toolStartMs: resolvedIntent.startMs,
              toolEndMs: resolvedIntent.endMs,
              forceToolFirstIfNoToolCalls: forceToolFirstIfNoToolCalls,
            );
          }

          if (session != null) {
            await for (final AIStreamEvent evt in session!.stream) {
              if (!mounted) return;
              // 优先消费"思考内容"
              if (evt.kind == 'reasoning') {
                setState(() {
                  _thinkingText += evt.data;
                  final idx = _currentAssistantIndex;
                  if (idx != null) {
                    _reasoningByIndex[idx] =
                        (_reasoningByIndex[idx] ?? '') + evt.data;
                  }
                });
                _scheduleAutoScroll();
                _scheduleReasoningPreviewScroll();
                _markInFlightHistoryDirty();
                continue;
              }
              // 正文增量（首 token 到来时先清空阶段状态，再开始写入最终答案）
              setState(() {
                final lastIdx = _messages.length - 1;
                final last = _messages[lastIdx];
                if (last.role == 'assistant') {
                  final String base = _replaceAssistantContentOnNextToken
                      ? ''
                      : last.content;
                  String incoming = evt.data;
                  // 在首个 token 写入前插入"已复用上一轮上下文"提示（仅一次）
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
              _markInFlightHistoryDirty();
            }
            await session!.completed;
            // 成功路径：更新"上一轮"缓存
            _lastCtxPack = ctxPack;
            _lastIntent = intent;
          }
        } catch (e) {
          try {
            await FlutterLogger.nativeError(
              'ChatFlow',
              'error ' + e.toString(),
            );
          } catch (_) {}
          if (!mounted) return;
          final String errorMessage;
          if (e is InvalidResponseStartException) {
            final String preview = e.receivedPreview.isEmpty
                ? '<empty>'
                : e.receivedPreview;
            final String truncated = preview.length > 800
                ? '${preview.substring(0, 800)}…'
                : preview;
            errorMessage =
                'Invalid response start marker. Raw preview:\n$truncated';
          } else if (e is InvalidEndpointConfigurationException) {
            errorMessage = 'Invalid endpoint configuration: ${e.message}';
          } else {
            errorMessage = e.toString();
          }
          setState(() {
            _inStreaming = false;
            if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
              final newList = List<AIMessage>.from(_messages);
              newList[_messages.length - 1] = AIMessage(
                role: 'error',
                content: errorMessage,
              );
              _messages = newList;
            } else {
              _messages = List<AIMessage>.from(_messages)
                ..add(AIMessage(role: 'error', content: errorMessage));
            }
          });
          _stopInFlightHistoryPersistence();
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
              _reasoningDurationByIndex[idx] = DateTime.now().difference(
                _messages[idx].createdAt,
              );
            }
            _currentAssistantIndex = null;
          });
          _stopInFlightHistoryPersistence();
          _stopDots();
          _scheduleAutoScroll();
          // 结束后合并深度思考内容并持久化
          try {
            List<AIMessage> merged = _mergeReasoningForPersistence(
              List<AIMessage>.from(_messages),
            );
            final QueryContextPack? pack = ctxPackForRewrite;
            if (pack != null &&
                assistantIdx >= 0 &&
                assistantIdx < merged.length &&
                merged[assistantIdx].role == 'assistant') {
              final AIMessage m = merged[assistantIdx];
              String rewritten = await _rewriteNumericEvidenceTagsToFilenames(
                m.content,
                ctxPack: pack,
              );
              rewritten = _forceAppendEvidenceSamplesIfMissing(
                rewritten,
                ctxPack: pack,
              );
              if (rewritten != m.content) {
                merged = List<AIMessage>.from(merged);
                merged[assistantIdx] = AIMessage(
                  role: m.role,
                  content: rewritten,
                  createdAt: m.createdAt,
                  reasoningContent: m.reasoningContent,
                  reasoningDuration: m.reasoningDuration,
                );
              }
            }
            if (mounted) {
              setState(() {
                _messages = merged;
              });
            }
            await _settings.saveChatHistoryActive(merged);
          } catch (_) {
            try {
              List<AIMessage> toSave = _mergeReasoningForPersistence(
                List<AIMessage>.from(_messages),
              );
              final QueryContextPack? pack = ctxPackForRewrite;
              if (pack != null &&
                  assistantIdx >= 0 &&
                  assistantIdx < toSave.length &&
                  toSave[assistantIdx].role == 'assistant') {
                final AIMessage m = toSave[assistantIdx];
                String rewritten = await _rewriteNumericEvidenceTagsToFilenames(
                  m.content,
                  ctxPack: pack,
                );
                rewritten = _forceAppendEvidenceSamplesIfMissing(
                  rewritten,
                  ctxPack: pack,
                );
                if (rewritten != m.content) {
                  toSave = List<AIMessage>.from(toSave);
                  toSave[assistantIdx] = AIMessage(
                    role: m.role,
                    content: rewritten,
                    createdAt: m.createdAt,
                    reasoningContent: m.reasoningContent,
                    reasoningDuration: m.reasoningDuration,
                  );
                }
              }
              await _settings.saveChatHistoryActive(toSave);
            } catch (_) {}
          }
        }
      } else {
        // 非流式：仍按阶段流程，最后一次性替换为最终答案
        final int assistantIdx = _messages.length;
        setState(() {
          _thinkingText = '';
          _reasoningByIndex[assistantIdx] = '';
          _reasoningDurationByIndex.remove(assistantIdx);
          _messages = List<AIMessage>.from(_messages)
            ..add(
              AIMessage(
                role: 'assistant',
                content: '1/4 分析用户意图…',
                createdAt: DateTime.now(),
              ),
            );
        });
        _appendAgentLog(
          _isZhLocale() ? '开始处理本次请求' : 'Start handling request',
          assistantIndex: assistantIdx,
          bullet: false,
        );
        _appendAgentLog(
          _isZhLocale() ? '阶段 1/4：意图分析' : 'Phase 1/4: intent analysis',
          assistantIndex: assistantIdx,
          bullet: false,
        );

        try {
          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase1 intent(begin, non-stream)',
          );

          IntentResult? intent;
          String userQuestionForFinal = text;
          bool localOnlyResponse = false;
          String localAssistantText = '';

          // 0) 如果处于澄清流程且用户选择取消，则结束本次查找
          if (_clarifyState != null && _isCancelMessage(text)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '检测到取消指令：本次查找结束（不发起网络请求）'
                  : 'Cancel detected: stop (no network request)',
              assistantIndex: assistantIdx,
            );
            _clarifyState = null;
            localOnlyResponse = true;
            localAssistantText = _isZhLocale()
                ? '好的，已取消本次查找。你可以随时再问我。'
                : 'Ok, canceled. You can ask again anytime.';
          }

          // 1) 若正在等待“候选选择”，优先处理用户选择（回复序号）
          final _ClarifyState? clarify0 = _clarifyState;
          if (!localOnlyResponse &&
              clarify0 != null &&
              clarify0.stage == _ClarifyStage.pickCandidate) {
            _appendAgentLog(
              _isZhLocale()
                  ? '澄清流程：解析候选选择…'
                  : 'Clarification: parsing candidate selection…',
              assistantIndex: assistantIdx,
            );
            final int? pick = _parsePickIndex(text, clarify0.candidates.length);
            if (pick != null) {
              final _ProbeCandidate c = clarify0.candidates[pick - 1];
              _appendAgentLog(
                _isZhLocale()
                    ? '已选择候选 #$pick，定位时间窗…'
                    : 'Picked candidate #$pick, using its time window…',
                assistantIndex: assistantIdx,
              );
              String tzReadable() {
                final Duration off = DateTime.now().timeZoneOffset;
                final int mins = off.inMinutes;
                final String sign = mins >= 0 ? '+' : '-';
                final int abs = mins.abs();
                final String hh = (abs ~/ 60).toString().padLeft(2, '0');
                final String mm = (abs % 60).toString().padLeft(2, '0');
                return 'UTC$sign$hh:$mm';
              }

              intent = IntentResult(
                intent: 'pick_candidate',
                intentSummary: _isZhLocale() ? '根据候选定位' : 'Locate by candidate',
                startMs: c.startMs,
                endMs: c.endMs,
                timezone: tzReadable(),
                apps: const <String>[],
                sqlFill: const <String, dynamic>{},
                skipContext: false,
                contextAction: 'refresh',
              );
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarify0,
              );
              _clarifyState = null;
            } else {
              // 不是序号：视为“都不是/补充线索”，直接根据新线索再跑一次探测检索
              if (!_isCancelMessage(text)) clarify0.supplements.add(text);
              final String probeQ = _clipOneLine(
                _composeFinalUserQuestionFromClarify(clarify0),
                80,
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '未识别到序号：基于补充线索做一次探测检索…'
                    : 'No pick index: probing candidates from supplemental hints…',
                assistantIndex: assistantIdx,
              );
              final Stopwatch swProbe = Stopwatch()..start();
              final List<_ProbeCandidate> cands = await _probeCandidates(
                query: probeQ.isEmpty ? _clipOneLine(text, 80) : probeQ,
                state: clarify0,
                limit: 6,
              );
              swProbe.stop();
              _appendAgentLog(
                _isZhLocale()
                    ? '探测检索完成：候选 ${cands.length}（${swProbe.elapsedMilliseconds}ms）'
                    : 'Probe done: ${cands.length} candidates (${swProbe.elapsedMilliseconds}ms)',
                assistantIndex: assistantIdx,
              );
              clarify0.candidates
                ..clear()
                ..addAll(cands);
              clarify0.stage = _ClarifyStage.pickCandidate;
              clarify0.lastProbeKind = cands.isNotEmpty
                  ? cands.first.kind
                  : _ProbeKind.none;
              localAssistantText = await _buildProbePickMessage(
                clarify0,
                cands,
              );
              localOnlyResponse = true;
            }
          }

          // 2) 正常意图分析（或澄清补充阶段：将补充信息合并进分析输入）
          if (!localOnlyResponse && intent == null) {
            String analyzeInput = text;
            final _ClarifyState? clarifyAsk = _clarifyState;
            if (clarifyAsk != null && clarifyAsk.stage == _ClarifyStage.ask) {
              if (!_isCancelMessage(text)) clarifyAsk.supplements.add(text);
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarifyAsk,
              );
              analyzeInput = _composeClarifyIntentInput(clarifyAsk);
            }

            if (!localOnlyResponse) {
              final String preview = _clipOneLine(analyzeInput, 80);
              _appendAgentLog(
                _isZhLocale()
                    ? '调用意图分析模型…${preview.isEmpty ? '' : ' input="' + preview + '"'}'
                    : 'Calling intent model…${preview.isEmpty ? '' : ' input=\"' + preview + '\"'}',
                assistantIndex: assistantIdx,
              );
              final Stopwatch swIntent = Stopwatch()..start();
              intent = await IntentAnalysisService.instance.analyze(
                analyzeInput,
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
              swIntent.stop();
              final String range = intent!.hasValidRange
                  ? '[${intent!.startMs}-${intent!.endMs}]'
                  : '<invalid>';
              final String err = (intent!.errorCode ?? '').trim();
              _appendAgentLog(
                _isZhLocale()
                    ? '意图解析完成：${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err}（${swIntent.elapsedMilliseconds}ms）'
                    : 'Intent done: ${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err} (${swIntent.elapsedMilliseconds}ms)',
                assistantIndex: assistantIdx,
              );
            }
          }

          // 3) 缺少有效时间窗：优先在“续问”场景复用上一轮，否则进入温和澄清
          if (!localOnlyResponse && intent != null && !intent!.hasValidRange) {
            _appendAgentLog(
              _isZhLocale()
                  ? '未解析到有效时间窗：尝试复用上一轮或进入澄清…'
                  : 'No valid time range: try reuse previous or ask to clarify…',
              assistantIndex: assistantIdx,
            );
            final bool hasPreviousWindow =
                (_lastIntent != null && _lastIntent!.hasValidRange) ||
                (_lastCtxPack != null) ||
                (QueryContextService.instance.lastPack != null);
            final bool canReusePrevious =
                hasPreviousWindow && intent!.skipContext;
            if (canReusePrevious) {
              _appendAgentLog(
                _isZhLocale()
                    ? '尝试复用上一轮时间窗…'
                    : 'Trying to reuse previous time window…',
                assistantIndex: assistantIdx,
              );
              int? fbStart;
              int? fbEnd;
              if (_lastIntent != null && _lastIntent!.hasValidRange) {
                fbStart = _lastIntent!.startMs;
                fbEnd = _lastIntent!.endMs;
              } else if (_lastCtxPack != null) {
                fbStart = _lastCtxPack!.startMs;
                fbEnd = _lastCtxPack!.endMs;
              } else if (QueryContextService.instance.lastPack != null) {
                final p = QueryContextService.instance.lastPack!;
                fbStart = p.startMs;
                fbEnd = p.endMs;
              }
              if (fbStart != null && fbEnd != null && fbEnd >= fbStart) {
                _appendAgentLog(
                  _isZhLocale()
                      ? '已复用上一轮时间窗：[$fbStart-$fbEnd]'
                      : 'Reused previous window: [$fbStart-$fbEnd]',
                  assistantIndex: assistantIdx,
                );
                intent = IntentResult(
                  intent: intent!.intent,
                  intentSummary: intent!.intentSummary.isNotEmpty
                      ? intent!.intentSummary
                      : '复用上一轮时间窗',
                  startMs: fbStart,
                  endMs: fbEnd,
                  timezone: intent!.timezone,
                  apps: intent!.apps,
                  sqlFill: intent!.sqlFill,
                  skipContext: true,
                  errorCode: intent!.errorCode,
                  errorMessage: intent!.errorMessage,
                );
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '复用失败：没有可用的上一轮范围，转入澄清'
                      : 'Reuse failed: no previous window, switching to clarification',
                  assistantIndex: assistantIdx,
                );
                localOnlyResponse = true;
                localAssistantText = _isZhLocale()
                    ? '我想沿用上一轮时间窗来继续查找，但没有找到可复用的上一轮范围。你可以补充一下大概的日期/时间段吗？'
                    : 'I tried to reuse the previous time window, but none is available. Could you provide an approximate time range?';
                _clarifyState = _ClarifyState(
                  originalQuestion: userQuestionForFinal,
                  reason: _ClarifyReason.missingTime,
                );
              }
            } else {
              _appendAgentLog(
                _isZhLocale()
                    ? '进入澄清流程：需要用户补充时间线索'
                    : 'Entering clarification: need more time hints from user',
                assistantIndex: assistantIdx,
              );
              _ClarifyState st;
              if (_clarifyState == null) {
                st = _ClarifyState(
                  originalQuestion: userQuestionForFinal,
                  reason: _ClarifyReason.missingTime,
                );
                _clarifyState = st;
              } else {
                final old = _clarifyState!;
                if (old.reason == _ClarifyReason.missingTime) {
                  st = old;
                } else {
                  st = _ClarifyState(
                    originalQuestion: old.originalQuestion,
                    reason: _ClarifyReason.missingTime,
                    hintStartMs: old.hintStartMs,
                    hintEndMs: old.hintEndMs,
                  );
                  st
                    ..supplements.addAll(old.supplements)
                    ..askRounds = old.askRounds
                    ..stage = old.stage;
                  _clarifyState = st;
                }
              }

              final bool userWantsProceed = intent!.userWantsProceed;
              if (st.askRounds < 2 && !userWantsProceed) {
                st.stage = _ClarifyStage.ask;
                st.candidates.clear();
                localAssistantText = await _buildClarifyPrompt(st);
                st.askRounds += 1;
                _appendAgentLog(
                  _isZhLocale()
                      ? '向用户追问时间范围（第 ${st.askRounds}/2 轮）'
                      : 'Asking for time range (round ${st.askRounds}/2)',
                  assistantIndex: assistantIdx,
                );
                localOnlyResponse = true;
              } else {
                st.askRounds = 2;
                final String probeQuery = intent!.keywords.isNotEmpty
                    ? intent!.keywords.join(' ')
                    : _composeFinalUserQuestionFromClarify(st);
                final String probeQ = _clipOneLine(probeQuery, 80);
                _appendAgentLog(
                  _isZhLocale()
                      ? '仍无法确定时间：基于关键词/问题做探测检索，生成候选…'
                      : 'Still ambiguous: probing candidates by keywords/question…',
                  assistantIndex: assistantIdx,
                );
                final Stopwatch swProbe2 = Stopwatch()..start();
                final List<_ProbeCandidate> cands = await _probeCandidates(
                  query: probeQ.isEmpty
                      ? _clipOneLine(userQuestionForFinal, 80)
                      : probeQ,
                  state: st,
                  limit: 6,
                );
                swProbe2.stop();
                _appendAgentLog(
                  _isZhLocale()
                      ? '候选生成完成：${cands.length}（${swProbe2.elapsedMilliseconds}ms）'
                      : 'Candidates ready: ${cands.length} (${swProbe2.elapsedMilliseconds}ms)',
                  assistantIndex: assistantIdx,
                );
                st.candidates
                  ..clear()
                  ..addAll(cands);
                st.stage = _ClarifyStage.pickCandidate;
                st.lastProbeKind = cands.isNotEmpty
                    ? cands.first.kind
                    : _ProbeKind.none;
                localAssistantText = await _buildProbePickMessage(st, cands);
                localOnlyResponse = true;
              }
            }
          }

          // 4) 时间范围过大且缺少线索：先温和引导缩小范围
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.userWantsProceed &&
              _isOverlyBroadQuery(
                intent!,
                userQuestionForFinal,
                clarify: _clarifyState,
              )) {
            _ClarifyState st;
            if (_clarifyState != null &&
                _clarifyState!.reason == _ClarifyReason.tooBroad) {
              st = _clarifyState!;
            } else {
              st = _ClarifyState(
                originalQuestion: userQuestionForFinal,
                reason: _ClarifyReason.tooBroad,
                hintStartMs: intent!.startMs,
                hintEndMs: intent!.endMs,
              );
              _clarifyState = st;
            }

            if (st.askRounds < 2) {
              st.stage = _ClarifyStage.ask;
              st.candidates.clear();
              localAssistantText = await _buildClarifyPrompt(st);
              st.askRounds += 1;
              localOnlyResponse = true;
            } else {
              st.askRounds = 2;
              final String probeQuery = intent!.keywords.isNotEmpty
                  ? intent!.keywords.join(' ')
                  : _composeFinalUserQuestionFromClarify(st);
              final String probeQ = _clipOneLine(probeQuery, 80);
              final List<_ProbeCandidate> cands = await _probeCandidates(
                query: probeQ.isEmpty ? _clipOneLine(text, 80) : probeQ,
                state: st,
                limit: 6,
              );
              st.candidates
                ..clear()
                ..addAll(cands);
              st.stage = _ClarifyStage.pickCandidate;
              st.lastProbeKind = cands.isNotEmpty
                  ? cands.first.kind
                  : _ProbeKind.none;
              localAssistantText = await _buildProbePickMessage(st, cands);
              localOnlyResponse = true;
            }
          }

          if (localOnlyResponse) {
            _appendAgentLog(
              _isZhLocale()
                  ? '本轮进入本地澄清/候选回复：不进行上下文检索与回答生成'
                  : 'Local clarification/candidates: skip context retrieval and answering',
              assistantIndex: assistantIdx,
            );
            setState(() {
              final lastIdx = _messages.length - 1;
              final last = _messages[lastIdx];
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: localAssistantText,
                createdAt: last.createdAt,
              );
            });
            _scheduleAutoScroll();
            try {
              final List<AIMessage> toSave = _mergeReasoningForPersistence(
                List<AIMessage>.from(_messages),
              );
              await _settings.saveChatHistoryActive(toSave);
            } catch (_) {}
            return;
          }

          if (_clarifyState != null &&
              intent != null &&
              intent!.hasValidRange) {
            _clarifyState = null;
          }

          final IntentResult resolvedIntent = intent!;
          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase1 intent ok range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}] summary=${resolvedIntent.intentSummary}',
          );
          _appendAgentLog(
            _isZhLocale()
                ? '意图已确认：${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]'
                : 'Intent confirmed: ${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]',
            assistantIndex: assistantIdx,
          );
          final start = DateTime.fromMillisecondsSinceEpoch(
            resolvedIntent.startMs,
          );
          final end = DateTime.fromMillisecondsSinceEpoch(resolvedIntent.endMs);
          String two(int v) => v.toString().padLeft(2, '0');
          final String range =
              '${two(start.hour)}:${two(start.minute)}-${two(end.hour)}:${two(end.minute)}';
          setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content:
                  '1/4 意图: ${resolvedIntent.intentSummary}\n时间: $range (${resolvedIntent.timezone})\n\n2/4 查找上下文…',
              createdAt: last.createdAt,
            );
          });

          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase2 context(begin, non-stream)',
          );
          _appendAgentLog(
            _isZhLocale() ? '阶段 2/4：查找上下文' : 'Phase 2/4: building context',
            assistantIndex: assistantIdx,
            bullet: false,
          );
          final String ctxAction = (resolvedIntent.contextAction)
              .trim()
              .toLowerCase();
          final bool reuse =
              resolvedIntent.skipContext &&
              ctxAction == 'reuse' &&
              (_lastCtxPack != null ||
                  QueryContextService.instance.lastPack != null);
          _appendAgentLog(
            _isZhLocale()
                ? '复用上一轮上下文：' + (reuse ? '是' : '否')
                : 'Reuse previous context: ' + (reuse ? 'yes' : 'no'),
            assistantIndex: assistantIdx,
          );
          _appendAgentLog(
            _isZhLocale()
                ? '上下文策略：' + ctxAction
                : 'Context action: ' + ctxAction,
            assistantIndex: assistantIdx,
          );
          if (resolvedIntent.skipContext && !reuse) {
            _appendAgentLog(
              _isZhLocale()
                  ? '意图模型建议不复用缓存上下文，将重新检索/翻页以获取更多证据。'
                  : 'Intent model suggests not reusing cached context; will refresh/page for more evidence.',
              assistantIndex: assistantIdx,
            );
          }

          // 不限制上下文事件数量；预加载少量证据图片“文件名/路径”（不预加载像素）。
          // 目的：让模型可以直接引用 filename（而不是臆造），从而在 UI 中稳定渲染图片证据。
          const int maxEvents = 0;
          // 证据图片：预加载文件名/路径（不预加载像素）；段内最多 15 张，总计最多 360 张（并尽量在段落间均匀分配）。
          const int maxImagesTotal = 360;
          const int maxImagesPerEvent = 15;

          // 当范围超过 7 天时，按周预加载（避免提示词过大导致超时/输入上限）。
          final int fullStartMs = resolvedIntent.startMs;
          final int fullEndMs = resolvedIntent.endMs;
          int preloadStartMs = fullStartMs;
          int preloadEndMs = fullEndMs;
          final bool windowed =
              (fullEndMs - fullStartMs) > AIChatService.maxToolTimeSpanMs;
          if (windowed) {
            preloadEndMs = fullEndMs;
            preloadStartMs = fullEndMs - AIChatService.maxToolTimeSpanMs;
            if (preloadStartMs < fullStartMs) preloadStartMs = fullStartMs;
            _appendAgentLog(
              _isZhLocale()
                  ? '时间范围较大：上下文按周分页，本次预加载 7 天窗口 range=[$preloadStartMs-$preloadEndMs]'
                  : 'Large time range: paging context by week; preloading a 7-day window range=[$preloadStartMs-$preloadEndMs]',
              assistantIndex: assistantIdx,
            );
          }

          if (windowed &&
              !reuse &&
              (ctxAction == 'page_prev' || ctxAction == 'page_next')) {
            final QueryContextPack? prevPack =
                (_lastCtxPack ?? QueryContextService.instance.lastPack);
            if (prevPack != null &&
                prevPack.startMs >= fullStartMs &&
                prevPack.endMs <= fullEndMs) {
              if (ctxAction == 'page_prev' && prevPack.startMs > fullStartMs) {
                final int prevEnd0 = prevPack.startMs - 1;
                int nextEndMs = prevEnd0;
                if (nextEndMs < fullStartMs) nextEndMs = fullStartMs;
                int nextStartMs = nextEndMs - AIChatService.maxToolTimeSpanMs;
                if (nextStartMs < fullStartMs) nextStartMs = fullStartMs;
                if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                preloadStartMs = nextStartMs;
                preloadEndMs = nextEndMs;
                _appendAgentLog(
                  _isZhLocale()
                      ? '自动翻页：加载上一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                      : 'Auto paging: load previous week range=[$preloadStartMs-$preloadEndMs]',
                  assistantIndex: assistantIdx,
                );
              } else if (ctxAction == 'page_next' &&
                  prevPack.endMs < fullEndMs) {
                final int nextStart0 = prevPack.endMs + 1;
                int nextStartMs = nextStart0;
                if (nextStartMs > fullEndMs) nextStartMs = fullEndMs;
                int nextEndMs = nextStartMs + AIChatService.maxToolTimeSpanMs;
                if (nextEndMs > fullEndMs) nextEndMs = fullEndMs;
                if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                preloadStartMs = nextStartMs;
                preloadEndMs = nextEndMs;
                _appendAgentLog(
                  _isZhLocale()
                      ? '自动翻页：加载下一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                      : 'Auto paging: load next week range=[$preloadStartMs-$preloadEndMs]',
                  assistantIndex: assistantIdx,
                );
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '已到达可翻页边界（或窗口无变化），将按当前周继续检索。'
                      : 'Reached paging boundary (or no window change); continue with current window.',
                  assistantIndex: assistantIdx,
                );
              }
            } else {
              _appendAgentLog(
                _isZhLocale()
                    ? '无可用缓存窗口用于翻页，将按当前周继续检索。'
                    : 'No cached window for paging; continue with current window.',
                assistantIndex: assistantIdx,
              );
            }
          }

          final QueryContextPack ctxPack;
          if (reuse) {
            _appendAgentLog(
              _isZhLocale() ? '使用缓存上下文包' : 'Using cached context pack',
              assistantIndex: assistantIdx,
            );
            ctxPack = (_lastCtxPack ?? QueryContextService.instance.lastPack!);
          } else {
            _appendAgentLog(
              _isZhLocale()
                  ? '查询本地数据库并组装上下文…'
                  : 'Querying local DB and assembling context…',
              assistantIndex: assistantIdx,
            );
            final Stopwatch swCtx = Stopwatch()..start();
            ctxPack = await QueryContextService.instance.buildContext(
              startMs: preloadStartMs,
              endMs: preloadEndMs,
              maxEvents: maxEvents,
              maxImagesTotal: maxImagesTotal,
              maxImagesPerEvent: maxImagesPerEvent,
              includeImages: true,
            );
            swCtx.stop();
            _appendAgentLog(
              _isZhLocale()
                  ? '上下文组装完成：events=${ctxPack.events.length}（${swCtx.elapsedMilliseconds}ms）'
                  : 'Context ready: events=${ctxPack.events.length} (${swCtx.elapsedMilliseconds}ms)',
              assistantIndex: assistantIdx,
            );
          }
          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase2 context ok events=${ctxPack.events.length} reuse=${reuse ? 1 : 0}',
          );
          // 缓存上下文，便于下一轮复用
          _lastCtxPack = ctxPack;
          try {
            QueryContextService.instance.setLastPack(ctxPack);
          } catch (_) {}
          final List<EvidenceImageAttachment> attachments = (() {
            final Set<String> seen = <String>{};
            final List<EvidenceImageAttachment> out =
                <EvidenceImageAttachment>[];
            for (final ev in ctxPack.events) {
              for (final a in ev.keyImages) {
                if (a.path.isEmpty) continue;
                if (seen.add(a.path)) out.add(a);
              }
            }
            return out;
          })();
          _appendAgentLog(
            _isZhLocale()
                ? '证据图片：预加载文件名/路径 ${attachments.length} 条（不预加载像素；需要看原图像素再用 get_images）'
                : 'Evidence images: preloaded filenames/paths ${attachments.length} (pixels not preloaded; use get_images when you must see pixels)',
            assistantIndex: assistantIdx,
          );
          setState(() {
            _attachmentsByIndex[assistantIdx] = attachments;
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content:
                  '2/4 查找上下文完成' +
                  (reuse ? '（复用上一轮）' : '') +
                  '：事件 ${ctxPack.events.length}' +
                  (windowed ? '（预加载 7 天窗口）' : '') +
                  '\n\n3/4 生成回答…',
              createdAt: last.createdAt,
            );
          });

          final finalQuery = _buildFinalQuestion(
            userQuestionForFinal,
            ctxPack,
            fullStartMs: fullStartMs,
            fullEndMs: fullEndMs,
          );
          await FlutterLogger.nativeDebug(
            'ChatFlow',
            'phase3 finalQueryLen=${finalQuery.length} (non-stream)',
          );
          _appendAgentLog(
            _isZhLocale() ? '阶段 3/4：生成回答' : 'Phase 3/4: generating answer',
            assistantIndex: assistantIdx,
            bullet: false,
          );
          _appendAgentLog(
            _isZhLocale()
                ? '生成最终提示词：len=${finalQuery.length}'
                : 'Final prompt: len=${finalQuery.length}',
            assistantIndex: assistantIdx,
          );
          // 非流式：拿到回复后直接写入最终答案（证据图片在渲染时按 basename 解析）
          final String sysDateGuard = _buildDateGuardSystemMessage(
            startMs: fullStartMs,
            endMs: fullEndMs,
          );
          final List<Map<String, dynamic>> chatTools =
              AIChatService.defaultChatTools();
          final bool forceToolFirstIfNoToolCalls =
              ctxPack.events.isEmpty ||
              resolvedIntent.intent == 'keyword_lookup' ||
              resolvedIntent.keywords.isNotEmpty;
          _appendAgentLog(
            _isZhLocale()
                ? '调用模型并启用工具：tools=${chatTools.length} tool_choice=auto'
                : 'Calling model with tools: tools=${chatTools.length} tool_choice=auto',
            assistantIndex: assistantIdx,
          );
          final Stopwatch swAnswer = Stopwatch()..start();
          final assistant = await _chat.sendMessageWithDisplayOverride(
            text,
            finalQuery,
            includeHistory: resolvedIntent.skipContext,
            extraSystemMessages: <String>[sysDateGuard],
            tools: chatTools,
            toolChoice: 'auto',
            toolStartMs: resolvedIntent.startMs,
            toolEndMs: resolvedIntent.endMs,
            forceToolFirstIfNoToolCalls: forceToolFirstIfNoToolCalls,
            emitEvent: (evt) {
              if (!mounted) return;
              if (evt.kind != 'reasoning') return;
              setState(() {
                _thinkingText += evt.data;
                _reasoningByIndex[assistantIdx] =
                    (_reasoningByIndex[assistantIdx] ?? '') + evt.data;
              });
              _scheduleAutoScroll();
              _scheduleReasoningPreviewScroll();
            },
          );
          swAnswer.stop();
          _appendAgentLog(
            _isZhLocale()
                ? '模型已响应（${swAnswer.elapsedMilliseconds}ms）'
                : 'Model responded (${swAnswer.elapsedMilliseconds}ms)',
            assistantIndex: assistantIdx,
          );
          final String content = assistant.content;
          if (!mounted) return;
          setState(() {
            // 用最终答案替换占位
            final lastIdx = _messages.length - 1;
            // 如复用上一轮上下文，则在正文前加一行提示
            final String finalContent =
                (reuse ? '（已复用上一轮上下文）\n\n' : '') + content;
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content: finalContent,
              createdAt: _messages[lastIdx].createdAt,
            );
            _inStreaming = false;
          });
          // 覆写历史：合并深度思考内容
          try {
            List<AIMessage> toSave = _mergeReasoningForPersistence(
              List<AIMessage>.from(_messages),
            );
            if (assistantIdx >= 0 &&
                assistantIdx < toSave.length &&
                toSave[assistantIdx].role == 'assistant') {
              final AIMessage m = toSave[assistantIdx];
              String rewritten = await _rewriteNumericEvidenceTagsToFilenames(
                m.content,
                ctxPack: ctxPack,
              );
              rewritten = _forceAppendEvidenceSamplesIfMissing(
                rewritten,
                ctxPack: ctxPack,
              );
              if (rewritten != m.content) {
                toSave = List<AIMessage>.from(toSave);
                toSave[assistantIdx] = AIMessage(
                  role: m.role,
                  content: rewritten,
                  createdAt: m.createdAt,
                  reasoningContent: m.reasoningContent,
                  reasoningDuration: m.reasoningDuration,
                );
                if (mounted) setState(() => _messages = toSave);
              }
            }
            await _settings.saveChatHistoryActive(toSave);
          } catch (_) {}
          // 成功路径：更新"上一轮"缓存
          _lastCtxPack = ctxPack;
          _lastIntent = resolvedIntent;
        } catch (e) {
          try {
            await FlutterLogger.nativeError(
              'ChatFlow',
              'error(non-stream) ' + e.toString(),
            );
          } catch (_) {}
          if (!mounted) return;
          setState(() {
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = AIMessage(
              role: 'error',
              content: e.toString(),
            );
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      // 将错误显示为一条"错误"气泡，便于区分样式
      setState(() {
        _inStreaming = false;
        if (_streamEnabled &&
            _messages.isNotEmpty &&
            _messages.last.role == 'assistant') {
          final newList = List<AIMessage>.from(_messages);
          newList[_messages.length - 1] = AIMessage(
            role: 'error',
            content: e.toString(),
          );
          _messages = newList;
        } else {
          _messages = List<AIMessage>.from(_messages)
            ..add(AIMessage(role: 'error', content: e.toString()));
        }
      });
      _stopDots();
      UINotifier.error(
        context,
        AppLocalizations.of(context).sendFailedWithError(e.toString()),
      );
    } finally {
      if (mounted)
        setState(() {
          _sending = false;
        });
    }
  }

  List<AIMessage> _mergeReasoningForPersistence(List<AIMessage> input) {
    final List<AIMessage> out = List<AIMessage>.from(input);
    for (int i = 0; i < out.length; i++) {
      final AIMessage m = out[i];
      if (m.role == 'user' || m.role == 'system') continue;
      final String? r = _reasoningByIndex[i];
      final Duration? d = _reasoningDurationByIndex[i];
      final String? existingR = m.reasoningContent;
      final Duration? existingD = m.reasoningDuration;
      final String? mergedR = (r != null && r.trim().isNotEmpty)
          ? r
          : existingR;
      final Duration? mergedD = d ?? existingD;
      if (mergedR == existingR && mergedD == existingD) continue;
      out[i] = AIMessage(
        role: m.role,
        content: m.content,
        createdAt: m.createdAt,
        reasoningContent: mergedR,
        reasoningDuration: mergedD,
      );
    }
    return out;
  }

  String _buildFinalQuestion(
    String userText,
    QueryContextPack ctx, {
    required int fullStartMs,
    required int fullEndMs,
  }) {
    // 将上下文包格式化为提示词，避免一次性灌入过多上下文：
    // - 预加载仅展示摘要（必要时由模型通过工具拉取详情）
    // - 证据图片文件名仅通过工具获取（get_segment_samples / search_screenshots_ocr）
    final sb = StringBuffer();
    sb.writeln('请严格依据以下上下文回答用户问题。');
    sb.writeln('你默认只会收到文本上下文，不会自动看到图片像素内容。');
    sb.writeln('当且仅当仅凭文本无法确认关键细节时，才允许调用工具 get_images 查看原图。');
    sb.writeln(
      '若用户问题属于“查找/定位/确认某个对象”的类型（例如：找某个UP主/视频/页面/内容），请优先调用检索类工具（search_segments / search_screenshots_ocr）获取证据，避免草率结论或臆测。',
    );
    sb.writeln(
      '获取图片文件名的方式：优先使用预加载上下文中的 evidence_samples；若仍需更多图片，可调用 search_screenshots_ocr（或先 search_segments 再 get_segment_samples）获得 filename，然后再用 get_images 请求查看（每次最多 15 张，总大小最多 10MB）。',
    );
    sb.writeln(
      '本次预加载上下文可能包含 evidence_samples（截图文件名 basenames，不含路径/像素）；当需要引用图片证据时，请优先使用这些 filename 作为 X。',
    );
    sb.writeln(
      '若引用 filename：必须完全匹配 evidence_samples 中的一项（含扩展名），禁止添加路径/前缀/后缀，禁止省略扩展名。',
    );
    sb.writeln(
      '时间范围工具（search_segments / search_screenshots_ocr）单次最多查询 7 天；若请求超过 7 天，工具会裁剪并在返回中加入 warnings + paging（prev/next），你可以按周继续查询上一周/下一周。',
    );
    sb.writeln('引用规范（唯一合法格式）：仅使用 [evidence: X]。');
    sb.writeln(
      'X 只能是：工具返回的 filename（推荐，最精确），或预加载上下文中的 evidence_samples 里的 filename。',
    );
    sb.writeln('禁止使用 segment_id/纯数字作为 X；禁止编造或猜测 filename。');
    sb.writeln(
      '多证据引用规则：每个 [evidence: X] 只能包含一个 X；需要多个证据时请重复引用，例如：[evidence: a.png] [evidence: b.png]。',
    );
    sb.writeln(
      '错误示例（会导致图片无法渲染）：[evidence: a.png, b.png] / [evidence: a.png，b.png] / [evidence: a.png、b.png]。',
    );
    sb.writeln('禁止臆造 X；未查看图片前禁止臆测像素内容。');
    sb.writeln(
      '禁止使用以下任何形式： [图1]、[file: ...]、URL、HTML、Markdown 图片/链接语法（如 ![](x) 或 [](x)）。',
    );
    sb.writeln('重要：不得将 [evidence: ...] 放入代码块或行内代码中，否则将无法识别与渲染。');
    sb.writeln(
      '重要：只要预加载上下文中存在 evidence_samples（非空），你的最终回答就必须至少引用 1 张相关图片证据：在正文中插入 [evidence: X]（X 为对应 filename）。'
      '若你不确定哪张最相关，请在回答末尾添加一行“相关截图：”并列出 1–5 个 [evidence: X]。',
    );
    sb.writeln('若上下文不足以回答，请明确说明不确定之处。');
    if (AIChatService.responseStartMarker.trim().isNotEmpty) {
      sb.writeln(
        '回答格式要求：当输出“最终回答文本”时，第一行必须仅输出 ${AIChatService.responseStartMarker}，随后换行开始正文，禁止省略或改动该标记。若需要调用工具（如 get_images），请先调用工具且不要输出该标记，等工具结果返回后再按上述格式输出最终回答。',
      );
    } else {
      sb.writeln('回答格式要求：如需工具（如 get_images）先调用工具；工具结果返回后再输出最终回答文本。');
    }
    sb.writeln('');
    sb.writeln('【查询范围】');
    String two(int v) => v.toString().padLeft(2, '0');
    String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    final DateTime dsFull = DateTime.fromMillisecondsSinceEpoch(fullStartMs);
    final DateTime deFull = DateTime.fromMillisecondsSinceEpoch(fullEndMs);
    final String fullDateLine =
        (dsFull.year == deFull.year &&
            dsFull.month == deFull.month &&
            dsFull.day == deFull.day)
        ? ('日期: ' + ymd(dsFull))
        : ('日期范围: ' + ymd(dsFull) + ' → ' + ymd(deFull));
    sb.writeln(fullDateLine);
    sb.writeln(
      '时间范围: ${two(dsFull.hour)}:${two(dsFull.minute)}–${two(deFull.hour)}:${two(deFull.minute)}',
    );
    sb.writeln('Epoch 毫秒: start_ms=$fullStartMs, end_ms=$fullEndMs');
    sb.writeln(
      '工具约束：所有带 start_ms/end_ms 的工具调用必须落在上述范围内；单次跨度 <= ${AIChatService.maxToolTimeSpanMs}ms（7 天）。',
    );
    sb.writeln('');
    sb.writeln('【预加载上下文（摘要）】');
    sb.writeln(
      '本次仅预加载窗口: start_ms=${ctx.startMs}, end_ms=${ctx.endMs}, events=${ctx.events.length}。',
    );
    sb.writeln('注意：预加载上下文可能仅覆盖查询范围的一部分；如需其他周，请使用工具按周分页检索。');
    sb.writeln(
      '提示：如需更多细节或更多图片文件名，请用检索类工具（search_segments / search_screenshots_ocr），必要时再调用 get_segment_result / get_segment_samples；最终引用证据时必须使用 filename。',
    );
    if (ctx.events.isNotEmpty) {
      for (final ev in ctx.events) {
        final String apps = ev.apps.isNotEmpty ? ev.apps.join('/') : '';
        final String sum = ev.summary.trim();
        final String clipped = sum.length > 600
            ? (sum.substring(0, 600) + '…')
            : sum;
        sb.writeln('- ${ev.window} ${apps.isEmpty ? '' : apps}');
        if (clipped.isNotEmpty) {
          sb.writeln('  summary: ' + clipped);
        }
        if (ev.keyImages.isNotEmpty) {
          String basename(String path) {
            final int idx1 = path.lastIndexOf('/');
            final int idx2 = path.lastIndexOf('\\');
            final int i = idx1 > idx2 ? idx1 : idx2;
            return i >= 0 ? path.substring(i + 1) : path;
          }

          final List<String> names = ev.keyImages
              .map((a) => basename(a.path).trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (names.isNotEmpty) {
            sb.writeln('  evidence_samples: ' + names.join(' '));
          }
        }
      }
    } else {
      sb.writeln('- （无预加载事件；请用工具检索）');
    }
    sb.writeln('');
    sb.writeln('【用户问题】');
    sb.writeln(userText);
    return sb.toString();
  }

  String _basenameFromPath(String path) {
    final int idx1 = path.lastIndexOf('/');
    final int idx2 = path.lastIndexOf('\\');
    final int i = idx1 > idx2 ? idx1 : idx2;
    return i >= 0 ? path.substring(i + 1) : path;
  }

  String _stripMarkdownCodeForEvidence(String content) {
    final List<String> lines = content.replaceAll('\r\n', '\n').split('\n');
    final StringBuffer sb = StringBuffer();
    bool inFence = false;
    for (final String line in lines) {
      final String tl = line.trimLeft();
      if (tl.startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      sb.writeln(line);
    }
    return sb.toString().replaceAll(RegExp(r'`[^`\n]*`'), '');
  }

  bool _hasEvidenceTagsOutsideCode(String content) {
    final String t = _stripMarkdownCodeForEvidence(content);
    return RegExp(
      r'\[\s*evidence\s*[:：]\s*[^\]\s]+\s*\]',
      caseSensitive: false,
    ).hasMatch(t);
  }

  List<String> _collectPreloadedEvidenceSamples(
    QueryContextPack ctxPack, {
    int maxCount = 6,
  }) {
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final ev in ctxPack.events) {
      for (final a in ev.keyImages) {
        final String name = _basenameFromPath(a.path).trim();
        if (name.isEmpty) continue;
        if (seen.add(name)) out.add(name);
        if (maxCount > 0 && out.length >= maxCount) return out;
      }
    }
    return out;
  }

  String _forceAppendEvidenceSamplesIfMissing(
    String content, {
    required QueryContextPack ctxPack,
    int maxAppend = 6,
  }) {
    if (_hasEvidenceTagsOutsideCode(content)) return content;

    final List<String> names = _collectPreloadedEvidenceSamples(
      ctxPack,
      maxCount: maxAppend,
    );
    if (names.isEmpty) return content;

    final String label = _isZhLocale() ? '相关截图：' : 'Relevant screenshots:';
    final String refs = names.map((n) => '[evidence: $n]').join(' ');

    final String base = content.trimRight();
    final String sep = base.isEmpty ? '' : '\n\n';
    return base + sep + label + '\n' + refs;
  }

  String _evidenceMsgKey(AIMessage m) {
    // createdAt 足够稳定；叠加 role/content hash 避免同秒多条消息冲突
    return '${m.createdAt.millisecondsSinceEpoch}|${m.role}|${m.content.hashCode}';
  }

  void _scheduleEvidenceRebuild() {
    if (_evidenceRebuildScheduled) return;
    _evidenceRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evidenceRebuildScheduled = false;
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<Map<String, String>> _resolveEvidencePathsCached({
    required String msgKey,
    required Set<String> missingNames,
  }) {
    if (missingNames.isEmpty) return Future.value(const <String, String>{});
    final List<String> sorted = missingNames.toList()..sort();
    final String lookupKey = '$msgKey|${sorted.join("|")}';
    return _evidenceResolveFutures.putIfAbsent(lookupKey, () async {
      Map<String, String> map = const <String, String>{};
      try {
        map = await ScreenshotDatabase.instance.findPathsByBasenames(
          missingNames,
        );
      } catch (_) {
        map = const <String, String>{};
      }
      if (!mounted) return map;
      if (map.isNotEmpty) {
        final Map<String, String> existing =
            _evidenceResolvedByMsgKey[msgKey] ?? const <String, String>{};
        bool changed = false;
        for (final e in map.entries) {
          if (existing[e.key] != e.value) {
            changed = true;
            break;
          }
        }
        if (changed) {
          _evidenceResolvedByMsgKey[msgKey] = <String, String>{
            ...existing,
            ...map,
          };
          // 关键：证据路径缓存更新后，主动触发一次页面重建；
          // 否则在“退出→进入”场景里可能要等到 Drawer/键盘等外部 UI 事件触发 rebuild 才会显示图片。
          _scheduleEvidenceRebuild();
        }
      }
      return map;
    });
  }

  Future<String> _rewriteNumericEvidenceTagsToFilenames(
    String content, {
    required QueryContextPack ctxPack,
  }) async {
    final RegExp re = RegExp(
      r'\[\s*evidence\s*[:：]\s*(\d{1,12})\s*\]',
      caseSensitive: false,
    );
    final List<RegExpMatch> matches = re.allMatches(content).toList();
    if (matches.isEmpty) return content;

    // Prefer filenames we already preloaded for this ctxPack.
    final Map<String, String> idToFilename = <String, String>{};
    for (final ev in ctxPack.events) {
      if (ev.keyImages.isEmpty) continue;
      final String name = _basenameFromPath(ev.keyImages.first.path).trim();
      if (name.isEmpty) continue;
      idToFilename[ev.segmentId.toString()] = name;
    }

    // Resolve any remaining ids via DB fallback, then convert to basenames.
    final Set<String> ids = matches
        .map((m) => (m.group(1) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final id in ids) {
      if (idToFilename.containsKey(id)) continue;
      try {
        final String? path = await ScreenshotDatabase.instance
            .findScreenshotPathByBasename(id);
        if (path == null || path.trim().isEmpty) continue;
        final String name = _basenameFromPath(path).trim();
        if (name.isEmpty) continue;
        idToFilename[id] = name;
      } catch (_) {}
    }

    final String rewritten = content.replaceAllMapped(re, (m) {
      final String id = (m.group(1) ?? '').trim();
      if (id.isEmpty) return m.group(0) ?? '';
      final String? name = idToFilename[id];
      if (name == null || name.trim().isEmpty) return m.group(0) ?? '';
      return '[evidence: ${name.trim()}]';
    });
    return rewritten;
  }

  String _buildDateGuardSystemMessage({
    required int startMs,
    required int endMs,
  }) {
    String two(int v) => v.toString().padLeft(2, '0');
    final DateTime ds = DateTime.fromMillisecondsSinceEpoch(startMs);
    final DateTime de = DateTime.fromMillisecondsSinceEpoch(endMs);
    String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    final String window =
        (ds.year == de.year && ds.month == de.month && ds.day == de.day)
        ? ('${ymd(ds)} ${two(ds.hour)}:${two(ds.minute)}–${two(de.hour)}:${two(de.minute)}')
        : ('${ymd(ds)} ${two(ds.hour)}:${two(ds.minute)}–${ymd(de)} ${two(de.hour)}:${two(de.minute)}');
    return '系统约束（必须遵守）: 仅围绕本地时区的指定日期/时间窗口回答：' +
        window +
        '。禁止将日期泛化为"今天/昨天/本周"等，也禁止引用当前日期。严禁回答超出该时间窗口的内容。' +
        '若需要查找证据，请优先调用工具，并确保 start_ms/end_ms 落在该窗口内（单次跨度<=7天；可按 paging.prev/paging.next 逐周翻页）。' +
        '若检索结果为空，不要直接下结论；应先向用户确认关键词/平台/时间范围是否可能记错，并询问是否继续扩大检索（翻页/换关键词/换工具）。' +
        '只有在用户确认并且已尝试多组关键词+多周翻页仍为空时，才可以回答“在该时间窗口内没有找到相关记录”。';
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

      String model =
          (ctxRow != null &&
              (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString()
                .trim();
      // 如果上下文中的模型不属于新提供商，回退到"提供商页选择的模型/默认/首个"
      if (model.isEmpty ||
          (sel.models.isNotEmpty && !sel.models.contains(model))) {
        final String fallback =
            ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString()
                .trim();
        model = fallback.isNotEmpty
            ? fallback
            : (sel.models.isNotEmpty ? sel.models.first : model);
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
        final TextEditingController queryCtrl = TextEditingController(
          text: _providerQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            final String q = queryCtrl.text.trim().toLowerCase();
            final List<AIProvider> items = q.isEmpty
                ? list
                : list.where((p) {
                    final name = p.name.toLowerCase();
                    final type = p.type.toLowerCase();
                    final base = (p.baseUrl ?? '').toString().toLowerCase();
                    return name.contains(q) ||
                        type.contains(q) ||
                        base.contains(q);
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
                          hintText: AppLocalizations.of(
                            context,
                          ).searchProviderPlaceholder,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(
                            c,
                          ).colorScheme.outline.withOpacity(0.6),
                        ),
                        itemBuilder: (c, i) {
                          final p = items[i];
                          final selected = p.id == currentId;
                          return ListTile(
                            leading: SvgPicture.asset(
                              ModelIconUtils.getProviderIconPath(p.type),
                              width: 20,
                              height: 20,
                            ),
                            title: Text(
                              p.name,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (selected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(c).colorScheme.onSurface,
                                  ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: AppLocalizations.of(
                                    context,
                                  ).actionDelete,
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Theme.of(c).colorScheme.error,
                                  ),
                                  onPressed: () async {
                                    final t = AppLocalizations.of(context);
                                    final confirmed =
                                        await showUIDialog<bool>(
                                          context: context,
                                          title: t.deleteGroup,
                                          message: t
                                              .confirmDeleteProviderMessage(
                                                p.name,
                                              ),
                                          actions: [
                                            UIDialogAction<bool>(
                                              text: t.dialogCancel,
                                              result: false,
                                            ),
                                            UIDialogAction<bool>(
                                              text: t.actionDelete,
                                              style: UIDialogActionStyle
                                                  .destructive,
                                              result: true,
                                            ),
                                          ],
                                        ) ??
                                        false;
                                    if (!confirmed) return;
                                    final ok = await svc.deleteProvider(p.id!);
                                    if (!ok) {
                                      // 二次校验：若已删除则按成功处理
                                      final still = await svc.getProvider(
                                        p.id!,
                                      );
                                      if (still != null) {
                                        UINotifier.error(
                                          context,
                                          t.deleteFailed,
                                        );
                                        return;
                                      }
                                    }
                                    // 如果删除的是当前选中提供商，清空上下文并提示
                                    if (selected) {
                                      if (mounted) {
                                        setState(() {
                                          _ctxChatProvider = null;
                                          _ctxChatModel = null;
                                        });
                                      }
                                    }
                                    // 刷新底部列表
                                    final refreshed = await svc.listProviders();
                                    items
                                      ..clear()
                                      ..addAll(
                                        q.isEmpty
                                            ? refreshed
                                            : refreshed.where((pp) {
                                                final name = pp.name
                                                    .toLowerCase();
                                                final type = pp.type
                                                    .toLowerCase();
                                                final base = (pp.baseUrl ?? '')
                                                    .toString()
                                                    .toLowerCase();
                                                return name.contains(q) ||
                                                    type.contains(q) ||
                                                    base.contains(q);
                                              }),
                                      );
                                    setModalState(() {});
                                    UINotifier.success(context, t.deletedToast);
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              String model = (_ctxChatModel ?? '').trim();
                              final List<String> available = p.models;
                              if (model.isEmpty ||
                                  (available.isNotEmpty &&
                                      !available.contains(model))) {
                                String fb =
                                    (p.extra['active_model'] as String? ??
                                            p.defaultModel)
                                        .toString()
                                        .trim();
                                if (fb.isEmpty && available.isNotEmpty)
                                  fb = available.first;
                                model = fb;
                              }
                              await _settings.setAIContextSelection(
                                context: 'chat',
                                providerId: p.id!,
                                model: model,
                              );
                              if (mounted) {
                                setState(() {
                                  _ctxChatProvider = p;
                                  _ctxChatModel = model;
                                });
                                Navigator.of(ctx).pop();
                                UINotifier.success(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  ).providerSelectedToast(p.name),
                                );
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
      UINotifier.info(
        context,
        AppLocalizations.of(context).pleaseSelectProviderFirst,
      );
      return;
    }
    final models = p.models;
    if (models.isEmpty) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).noModelsForProviderHint,
      );
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
        final TextEditingController queryCtrl = TextEditingController(
          text: _modelQueryText,
        );
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
                          hintText: AppLocalizations.of(
                            context,
                          ).searchModelPlaceholder,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(
                            c,
                          ).colorScheme.outline.withOpacity(0.6),
                        ),
                        itemBuilder: (c, i) {
                          final m = items[i];
                          final selected = m == active;
                          return ListTile(
                            leading: SvgPicture.asset(
                              ModelIconUtils.getIconPath(m),
                              width: 20,
                              height: 20,
                            ),
                            title: Text(
                              m,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle,
                                    color: Theme.of(c).colorScheme.onSurface,
                                  )
                                : null,
                            onTap: () async {
                              await _settings.setAIContextSelection(
                                context: 'chat',
                                providerId: p.id!,
                                model: m,
                              );
                              if (mounted) {
                                setState(() => _ctxChatModel = m);
                                Navigator.of(ctx).pop();
                                UINotifier.success(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  ).modelSwitchedToast(m),
                                );
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
      decorationColor: theme.colorScheme.onSurface.withOpacity(0.6),
      color: theme.colorScheme.onSurface,
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
            setState(() {
              _groupSelectorVisible = false;
            });
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
      groupName = g.isNotEmpty
          ? g.first.name
          : AppLocalizations.of(context).siteGroupDefaultName(gid);
    }
    final base = _baseUrlController.text.trim().isEmpty
        ? 'https://api.openai.com'
        : _baseUrlController.text.trim();
    final model = _modelController.text.trim().isEmpty
        ? 'gpt-4o-mini'
        : _modelController.text.trim();

    String brief(String s, int max) =>
        s.length > max ? (s.substring(0, max) + '…') : s;

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
      final name = AppLocalizations.of(
        context,
      ).siteGroupDefaultName(_groups.length + 1);
      final base = _baseUrlController.text.trim().isEmpty
          ? 'https://api.openai.com'
          : _baseUrlController.text.trim();
      final key = _apiKeyController.text.trim();
      final model = _modelController.text.trim().isEmpty
          ? 'gpt-4o-mini'
          : _modelController.text.trim();
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
      UINotifier.error(
        context,
        AppLocalizations.of(context).addGroupFailedWithError(e.toString()),
      );
    }
  }

  Future<void> _renameActiveGroup() async {
    final gid = _activeGroupId;
    if (gid == null) {
      if (mounted)
        UINotifier.info(context, AppLocalizations.of(context).groupNotSelected);
      return;
    }
    try {
      final g = await _settings.getSiteGroupById(gid);
      if (g == null) {
        if (mounted)
          UINotifier.error(context, AppLocalizations.of(context).groupNotFound);
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
          UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
          UIDialogAction(
            text: AppLocalizations.of(context).dialogOk,
            style: UIDialogActionStyle.primary,
            closeOnPress: false,
            onPressed: (ctx) async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(ctx).nameCannotBeEmpty,
                );
                return;
              }
              try {
                final updated = g.copyWith(name: newName);
                await _settings.updateSiteGroup(updated);
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _loadAll();
                if (mounted)
                  UINotifier.success(
                    context,
                    AppLocalizations.of(context).renameSuccess,
                  );
              } catch (e) {
                if (ctx.mounted)
                  UINotifier.error(
                    ctx,
                    AppLocalizations.of(
                      ctx,
                    ).renameFailedWithError(e.toString()),
                  );
              }
            },
          ),
        ],
      );
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).loadGroupFailedWithError(e.toString()),
        );
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
      UINotifier.success(
        context,
        AppLocalizations.of(context).groupDeletedToast,
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).deleteGroupFailedWithError(e.toString()),
      );
    }
  }

  Widget _buildGroupSelector() {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(AppLocalizations.of(context).ungroupedSingleConfig),
      ),
      ..._groups.map(
        (g) => DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).siteGroupsTitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          AppLocalizations.of(context).siteGroupsHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
            onPressed: () => setState(() {
              _groupSelectorVisible = true;
            }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing1,
              ),
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
          setState(() {
            _connExpanded = false;
          });
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

  // 魔法渐变图标（auto_awesome）
  // withGlow=true 时在图标背后叠加弥散光（主色/次色）
  Widget _buildMagicIcon({double size = 18, bool withGlow = false}) {
    // 不使用主题主/次色，改为 Gemini 风蓝色系（避免主题色影响视觉）
    final br = Theme.of(context).brightness;
    LinearGradient _maskGradient(Rect bounds) {
      final colors = _geminiGradientColors(br);
      // 蓝 -> 黄，提升黄端占比与亮度感（通过倾斜 stops）
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors[2], colors[8]],
        stops: const [0.0, 0.75],
      );
    }

    Widget _buildGradientGlowBackground(double iconSize) {
      // 使用蓝色系圆形渐变，叠加模糊形成柔和弥散光，确保为圆形而非矩形
      final double glowDiameter = iconSize * 3.0;
      return SizedBox(
        width: glowDiameter,
        height: glowDiameter,
        child: ClipOval(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: iconSize * 0.9,
              sigmaY: iconSize * 0.9,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    _geminiGradientColors(
                      br,
                    )[2].withOpacity(br == Brightness.dark ? 0.42 : 0.52),
                    _geminiGradientColors(br)[5].withOpacity(0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 使用蓝色系 ShaderMask 渐变方案，显式设置白色避免 IconTheme 重新上色
    final Widget gradientIcon = ShaderMask(
      shaderCallback: (Rect bounds) =>
          _maskGradient(bounds).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Icon(Icons.auto_awesome, size: size, color: Colors.white),
    );
    if (!withGlow) return gradientIcon;
    // 使用渐变+模糊的柔光背景，替代主题色 BoxShadow，确保与菜单第三项一致的渐变观感
    return Stack(
      alignment: Alignment.center,
      children: [_buildGradientGlowBackground(size), gradientIcon],
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty) {
      final l10n = AppLocalizations.of(context);
      try {
        FlutterLogger.nativeInfo(
          'UI',
          'ChatEmpty: assistant=1 useGradientGlow=1',
        );
      } catch (_) {}
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMagicIcon(size: 40, withGlow: false),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              l10n.aiEmptySelfTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              l10n.aiEmptySelfSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final Widget list = ListView.builder(
      controller: _chatScrollController,
      itemCount: _messages.length,
      reverse: false,
      // 仅渲染视口上下各一屏，减少离屏图片的构建与解码
      cacheExtent: MediaQuery.of(context).size.height,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
      itemBuilder: (context, index) {
        final m = _messages[index];
        final isUser = m.role == 'user';
        final isError =
            m.role == 'error' ||
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
          final isCurrentStreaming =
              _inStreaming && (_currentAssistantIndex == index);
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
                ),
              ),
            );
          }
        }

        // 正文渲染：流式期间对当前消息使用轻量文本，完成后再进行 Markdown 解析
        final bool isCurrentStreaming =
            _inStreaming && (_currentAssistantIndex == index);
        // 隐藏 system 消息（用于保存最终提示但不显示）
        final bool isSystem = m.role == 'system';
        if (isSystem) {
          return const SizedBox.shrink();
        }

        final Widget mdWidget =
            (isCurrentStreaming && !_renderImagesDuringStreaming)
            // 流式期间渲染轻量文本，避免高频 Markdown 重建
            ? SelectableText(
                m.content,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: fg),
              )
            : (() {
                // 非流式：构建 Markdown 与 evidence 解析
                final String preprocessedMd = preprocessForChatMarkdown(
                  m.content,
                );
                final Map<String, String> evidenceNameToPath =
                    <String, String>{};
                final List<EvidenceImageAttachment> atts =
                    _attachmentsByIndex[index] ??
                    const <EvidenceImageAttachment>[];
                for (final a in atts) {
                  final String name = _basenameFromPath(a.path).trim();
                  if (name.isNotEmpty) evidenceNameToPath[name] = a.path;
                }
                final List<String> orderedEvidencePathsFromAtts = (() {
                  final List<String> out = <String>[];
                  final Set<String> seen = <String>{};
                  for (final a in atts) {
                    final String p = a.path.trim();
                    if (p.isEmpty) continue;
                    if (seen.add(p)) out.add(p);
                  }
                  return out;
                })();
                final mathConfig = MarkdownMathConfig(
                  inlineTextStyle: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: fg),
                  blockTextStyle: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: fg),
                  evidenceNameToPath: evidenceNameToPath,
                  orderedEvidencePaths: orderedEvidencePathsFromAtts,
                );
                // 提取 evidence 引用（保留顺序，便于为查看器构建稳定的 gallery 顺序）
                final List<String> evidenceNamesInOrder = <String>[];
                final Set<String> evidenceNames = <String>{};
                for (final mm in RegExp(
                  r'\[evidence:\s*([^\]\s]+)\s*\]',
                ).allMatches(preprocessedMd)) {
                  final String name = (mm.group(1) ?? '').trim();
                  if (name.isEmpty) continue;
                  if (evidenceNames.add(name)) evidenceNamesInOrder.add(name);
                }

                // 流式期间（且允许渲染图片）尽量只用预加载附件映射，避免高频重建触发扫库
                if (isCurrentStreaming) {
                  return MarkdownBody(
                    data: preprocessedMd,
                    builders: mathConfig.builders,
                    inlineSyntaxes: mathConfig.inlineSyntaxes,
                    styleSheet: _mdStyle(context).copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      }
                    },
                  );
                }

                if (evidenceNames.isEmpty) {
                  return MarkdownBody(
                    data: preprocessedMd,
                    builders: mathConfig.builders,
                    inlineSyntaxes: mathConfig.inlineSyntaxes,
                    styleSheet: _mdStyle(context).copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      }
                    },
                  );
                }

                final String msgKey = _evidenceMsgKey(m);
                final Map<String, String> cached =
                    _evidenceResolvedByMsgKey[msgKey] ??
                    const <String, String>{};
                final Map<String, String> baseMap = <String, String>{
                  ...evidenceNameToPath,
                  ...cached,
                };
                final Set<String> missing = evidenceNames
                    .where((n) => !baseMap.containsKey(n))
                    .toSet();

                List<String> orderedEvidencePathsFromMap(
                  Map<String, String> map,
                ) {
                  if (orderedEvidencePathsFromAtts.isNotEmpty) {
                    return orderedEvidencePathsFromAtts;
                  }
                  final List<String> out = <String>[];
                  final Set<String> seen = <String>{};
                  for (final n in evidenceNamesInOrder) {
                    final String? p = map[n];
                    if (p == null || p.trim().isEmpty) continue;
                    if (seen.add(p)) out.add(p);
                  }
                  return out;
                }

                if (missing.isEmpty) {
                  final resolved = MarkdownMathConfig(
                    inlineTextStyle: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: fg),
                    blockTextStyle: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: fg),
                    evidenceNameToPath: baseMap,
                    orderedEvidencePaths: orderedEvidencePathsFromMap(baseMap),
                  );
                  return MarkdownBody(
                    data: preprocessedMd,
                    builders: resolved.builders,
                    inlineSyntaxes: resolved.inlineSyntaxes,
                    styleSheet: _mdStyle(context).copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      }
                    },
                  );
                }

                return FutureBuilder<Map<String, String>>(
                  future: _resolveEvidencePathsCached(
                    msgKey: msgKey,
                    missingNames: missing,
                  ),
                  builder: (context, snap) {
                    final Map<String, String> map =
                        snap.data ?? const <String, String>{};
                    final merged = <String, String>{...baseMap, ...map};
                    final resolved = MarkdownMathConfig(
                      inlineTextStyle: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                      blockTextStyle: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                      evidenceNameToPath: merged,
                      orderedEvidencePaths: orderedEvidencePathsFromMap(merged),
                    );
                    return MarkdownBody(
                      data: preprocessedMd,
                      builders: resolved.builders,
                      inlineSyntaxes: resolved.inlineSyntaxes,
                      styleSheet: _mdStyle(context).copyWith(
                        p: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: fg),
                      ),
                      onTapLink: (text, href, title) async {
                        if (href == null) return;
                        final uri = Uri.tryParse(href);
                        if (uri != null) {
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (_) {}
                        }
                      },
                    );
                  },
                );
              })();

        bubbleChildren.add(mdWidget);

        // 取消底部缩略图展示：图片仅通过正文中的 [evidence: FILENAME.EXT] 内联渲染

        // 组合：上方时间，中间消息气泡，下方操作区
        return Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // 上方：时间（HH:mm:ss）
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: Text(
                DateFormat('HH:mm:ss').format(
                  (m.role == 'assistant' &&
                          _reasoningDurationByIndex[index] != null)
                      ? m.createdAt.add(_reasoningDurationByIndex[index]!)
                      : m.createdAt,
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
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
                              textToCopy =
                                  t.reasoningLabel +
                                  '\n' +
                                  reasoning.trim() +
                                  '\n\n' +
                                  t.answerLabel +
                                  '\n' +
                                  textToCopy;
                            }
                          }
                          await Clipboard.setData(
                            ClipboardData(text: textToCopy),
                          );
                          if (mounted)
                            UINotifier.success(
                              context,
                              AppLocalizations.of(context).copySuccess,
                            );
                        } catch (_) {}
                      },
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      padding: const EdgeInsets.all(0),
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      splashRadius: 16,
                      iconSize: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: AppLocalizations.of(context).actionCopy,
                    ),
                    const SizedBox(width: 4),
                    // 重新生成（仅对助手消息提供）
                    // 移除"重试/重新生成"功能
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            // 根据位置更新粘底标志：仅在接近底部时视为粘底
            final double distanceToBottom =
                (metrics.maxScrollExtent - metrics.pixels).clamp(
                  0.0,
                  double.infinity,
                );
            _stickToBottom = distanceToBottom <= _autoScrollProximity;
            return false;
          },
          child: list,
        ),
        if (!_stickToBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Material(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
                elevation: 2,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    _stickToBottom = true;
                    _scrollToBottom(animated: true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAttachmentThumb(
    EvidenceImageAttachment att,
    int index,
    Color fg,
  ) {
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
                child: Text(
                  '[图$index]',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
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
                      colorFilter: ColorFilter.mode(
                        theme.colorScheme.onSurfaceVariant,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context).deepThinkingLabel +
                          (_inStreaming ? _thinkingDots : ''),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Builder(
                      builder: (ctx) {
                        if (!_inStreaming || _currentAssistantIndex == null)
                          return const SizedBox.shrink();
                        final idx = _currentAssistantIndex!;
                        if (idx < 0 || idx >= _messages.length)
                          return const SizedBox.shrink();
                        final dur = DateTime.now().difference(
                          _messages[idx].createdAt,
                        );
                        if (dur.inMilliseconds <= 0)
                          return const SizedBox.shrink();
                        final secs = (dur.inMilliseconds / 1000.0)
                            .toStringAsFixed(1);
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
                  tooltip: _showThinkingContent
                      ? AppLocalizations.of(context).collapse
                      : AppLocalizations.of(context).expandMore,
                  onPressed: () => setState(
                    () => _showThinkingContent = !_showThinkingContent,
                  ),
                  splashRadius: 16,
                  icon: Icon(
                    _showThinkingContent
                        ? Icons.expand_less
                        : Icons.expand_more,
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
                        itemCount: _thinkingText
                            .replaceAll('\r\n', '\n')
                            .split('\n')
                            .length,
                        itemBuilder: (context, i) {
                          final parts = _thinkingText
                              .replaceAll('\r\n', '\n')
                              .split('\n');
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
                        itemCount: _thinkingText
                            .replaceAll('\r\n', '\n')
                            .split('\n')
                            .length,
                        itemBuilder: (context, i) {
                          final parts = _thinkingText
                              .replaceAll('\r\n', '\n')
                              .split('\n');
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
    final placeholder = AppLocalizations.of(
      context,
    ).sendMessageToModelPlaceholder(modelLabel);

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
          // 左侧个人助手状态提示
          Tooltip(
            message: AppLocalizations.of(context).aiSelfModeEnabledToast,
            preferBelow: false,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(child: _buildMagicIcon(size: 18, withGlow: true)),
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
                  color:
                      (_sending
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary)
                          .withOpacity(0.3),
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

    // 个人助手：在流式时叠加"流光"效果
    return _ShimmerBorder(active: _inStreaming, child: barInner);
  }

  // 统一的小型选项芯片
  Widget _buildChip(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
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

class _ShimmerBorderState extends State<_ShimmerBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _kBorderRadius = 24.0;
  static const double _kBorderWidth =
      1.25; // 视觉宽度≈1.5（strokeWidth = 1.25 * 1.2）

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

    // 非激活态：不再包一层渐变容器，避免尺寸变化；仅返回 child
    if (!widget.active) return widget.child;

    // 流光动画边框（叠加高亮，不替换静态渐变）
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * 6.283185307179586; // 2π

        // 流光高亮：去掉灰色拖尾，仅保留彩色高亮，并以透明-彩色-透明的方式过渡
        final sweep = SweepGradient(
          center: Alignment.center,
          colors: const [
            Color(0x00FFFFFF), // 完全透明开始（透明白，避免黑色伪影）
            Color(0x00FFFFFF),
            Color(0xFF4285F4), // 蓝
            Color(0xFF9B72F2), // 紫
            Color(0xFFD946EF), // 品红
            Color(0xFFFF6B9D), // 粉
            Color(0xFFFBBC04), // 金
            Color(0x00FFFFFF), // 透明收尾（透明白）
            Color(0x00FFFFFF),
          ],
          stops: const [0.00, 0.30, 0.40, 0.50, 0.58, 0.66, 0.74, 0.85, 1.00],
          transform: GradientRotation(angle),
        );

        // 仅作为叠加层绘制流光高亮，不改变 child 尺寸
        return Stack(
          children: [
            // 底层直接是 child
            widget.child,
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

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
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
  final ns = MarkdownStyleSheet.fromTheme(
    Theme.of(context),
  ).copyWith(p: Theme.of(context).textTheme.bodyMedium);
  _cachedMdStyle = ns;
  return ns;
}

// 自绘渐变 Icon，避免被主题色覆盖
class _GradientIconPainter extends CustomPainter {
  final List<Color> colors;
  final IconData icon;
  _GradientIconPainter({required this.colors, required this.icon});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size.height,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final offset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect)
      ..blendMode = BlendMode.srcIn;

    // 先绘制到图层，随后用渐变混合
    canvas.saveLayer(rect, Paint());
    textPainter.paint(canvas, offset);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GradientIconPainter oldDelegate) {
    return oldDelegate.colors != colors || oldDelegate.icon != icon;
  }
}

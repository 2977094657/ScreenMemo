import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../models/models_dev_limits.dart';
import '../models/prompt_token_breakdown.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_context_budgets.dart';
import '../services/ai_model_prompt_caps_service.dart';
import '../services/ai_settings_service.dart';
import '../services/chat_context_service.dart';
import '../services/locale_service.dart';
import '../services/prompt_budget.dart';
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';
import 'segmented_token_bar.dart';
import 'ui_dialog.dart';
import 'ui_components.dart';

class ChatContextSheet {
  static bool _isZh(BuildContext context) => Localizations.localeOf(
    context,
  ).languageCode.toLowerCase().startsWith('zh');

  static String _loc(BuildContext context, String zh, String en) =>
      _isZh(context) ? zh : en;

  static String _fmtTs(int? ms) {
    if (ms == null || ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  static String _prettyJson(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    try {
      final dynamic v = jsonDecode(t);
      return const JsonEncoder.withIndent('  ').convert(v);
    } catch (_) {
      return t;
    }
  }

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ChatContextPanel(
        presentation: ChatContextPanelPresentation.bottomSheet,
      ),
    );
  }
}

enum ChatContextPanelPresentation { bottomSheet, drawer }

/// A right-side drawer wrapper that shows [ChatContextPanel].
class ChatContextDrawer extends StatelessWidget {
  const ChatContextDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Drawer(
      child: ChatContextPanel(
        presentation: ChatContextPanelPresentation.drawer,
      ),
    );
  }
}

/// AppBar action that opens the conversation-context bottom sheet when tapped.
///
/// The prompt/context usage indicator is shown as a bar under the AppBar (see
/// [ChatContextAppBarUsageBar]) instead of being overlaid on this icon.
class ChatContextAppBarAction extends StatelessWidget {
  const ChatContextAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: ChatContextSheet._loc(context, '对话上下文', 'Conversation context'),
      onPressed: () => ChatContextSheet.show(context),
      icon: const Icon(Icons.memory_outlined),
    );
  }
}

/// A thin progress bar shown under the AppBar to visualize the approximate
/// prompt/context usage (tokens).
class ChatContextAppBarUsageBar extends StatefulWidget
    implements PreferredSizeWidget {
  const ChatContextAppBarUsageBar({super.key});

  // Match the panel token bars for visual consistency.
  static const double _barHeight = 6.0;

  @override
  // Do not increase the AppBar height; we paint this bar by overflowing upward
  // into the toolbar area (so it visually sits "inside" the AppBar).
  Size get preferredSize => const Size.fromHeight(0);

  @override
  State<ChatContextAppBarUsageBar> createState() =>
      _ChatContextAppBarUsageBarState();
}

class _ChatContextAppBarUsageBarState extends State<ChatContextAppBarUsageBar> {
  StreamSubscription<String>? _sub;

  bool _refreshInFlight = false;
  int _tokens = 0;
  int _capTokens = 0;
  Map<String, int> _parts = const <String, int>{};

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = AISettingsService.instance.onContextChanged.listen((_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static String _fmtCompactInt(int value) {
    final int v = value.clamp(0, 1 << 62).toInt();
    if (v < 1000) return v.toString();
    if (v < 10000) {
      final String s = (v / 1000).toStringAsFixed(1);
      return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s) + 'k';
    }
    if (v < 1000000) {
      return '${(v / 1000).round()}k';
    }
    final String s = (v / 1000000).toStringAsFixed(1);
    return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s) + 'm';
  }

  Future<void> _refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final String cid = await AISettingsService.instance
          .getActiveConversationCid();
      final Map<String, dynamic>? row = await ScreenshotDatabase.instance
          .getAiConversationByCid(cid);

      int tokens = _toInt(row?['last_prompt_tokens']);
      String model = (row?['model'] as String?)?.trim() ?? '';
      final String raw =
          (row?['last_prompt_breakdown_json'] as String?)?.trim() ?? '';
      final Map<String, int> parts = <String, int>{};
      if (raw.isNotEmpty) {
        try {
          final dynamic decoded = jsonDecode(raw);
          if (decoded is Map) {
            final String m = (decoded['model'] ?? '').toString().trim();
            if (m.isNotEmpty) model = m;
            final dynamic total = decoded['total_tokens'];
            if (total is num) tokens = total.toInt();
            final dynamic p = decoded['parts'];
            if (p is Map) {
              for (final entry in p.entries) {
                final String k = entry.key.toString();
                final dynamic v = entry.value;
                if (v is! num) continue;
                final int t = v.toInt();
                if (t <= 0) continue;
                parts[k] = t;
              }
            }
          }
        } catch (_) {}
      }

      if (model.trim().isEmpty) {
        try {
          model = (await AISettingsService.instance.getModel()).trim();
        } catch (_) {
          model = '';
        }
      }

      String activeModel = '';
      try {
        activeModel = (await AISettingsService.instance.getModel()).trim();
      } catch (_) {
        activeModel = '';
      }

      final int fallbackCapTokens = AIContextBudgets.forModel(
        '__unknown__',
      ).promptCapTokens;
      final int activeCapTokens = activeModel.isEmpty
          ? 0
          : (await AIContextBudgets.forModelWithOverrides(
              activeModel,
            )).promptCapTokens;
      final int promptModelCapTokens = model.trim().isEmpty
          ? 0
          : (await AIContextBudgets.forModelWithOverrides(
              model,
            )).promptCapTokens;
      final int? promptModelOverride = model.trim().isEmpty
          ? null
          : await AIModelPromptCapsService.instance.getOverride(model);
      final bool sameModel =
          model.trim().toLowerCase() == activeModel.trim().toLowerCase();
      final bool promptLooksFallback =
          promptModelCapTokens == fallbackCapTokens;

      final int capTokens = (promptModelCapTokens <= 0)
          ? activeCapTokens
          : (promptModelOverride != null ||
                sameModel ||
                !promptLooksFallback ||
                activeCapTokens <= 0)
          ? promptModelCapTokens
          : activeCapTokens;

      if (!mounted) return;
      setState(() {
        _tokens = tokens.clamp(0, 1 << 62).toInt();
        _capTokens = capTokens.clamp(0, 1 << 30).toInt();
        _parts = parts;
      });
    } catch (_) {
      // Keep the last known values; the app bar should never crash due to a
      // transient DB/model lookup failure.
    } finally {
      _refreshInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String usedText = _fmtCompactInt(_tokens);
    final String capText = _capTokens > 0 ? _fmtCompactInt(_capTokens) : '—';
    final String tooltip = ChatContextSheet._loc(
      context,
      '对话上下文 · $usedText/$capText',
      'Conversation context · $usedText/$capText',
    );

    final int used = _tokens.clamp(0, 1 << 62).toInt();
    final int cap = _capTokens.clamp(0, 1 << 30).toInt();
    final int total = cap > 0 ? cap : (used > 0 ? used : 1);

    final List<PromptTokenPart> order = <PromptTokenPart>[
      PromptTokenPart.systemPrompt,
      PromptTokenPart.toolSchema,
      PromptTokenPart.toolInstruction,
      PromptTokenPart.conversationContext,
      PromptTokenPart.atomicMemory,
      PromptTokenPart.extraSystem,
      PromptTokenPart.historyUser,
      PromptTokenPart.historyAssistant,
      PromptTokenPart.historyTool,
      PromptTokenPart.userMessage,
    ];

    final int partsSum = order.fold<int>(
      0,
      (a, part) => a + (_parts[part.key] ?? 0),
    );
    final int remainder = (used - partsSum).clamp(0, 1 << 62).toInt();

    final List<SegmentedTokenBarSegment> segments = <SegmentedTokenBarSegment>[
      for (final part in order)
        if ((_parts[part.key] ?? 0) > 0)
          SegmentedTokenBarSegment(
            tokens: _parts[part.key]!,
            color: part.color(theme),
          ),
    ];
    if (segments.isEmpty) {
      if (used > 0) {
        segments.add(
          SegmentedTokenBarSegment(
            tokens: used,
            color: theme.colorScheme.primary,
          ),
        );
      }
    } else if (remainder > 0) {
      segments.add(
        SegmentedTokenBarSegment(
          tokens: remainder,
          color: theme.colorScheme.primary,
        ),
      );
    }

    // Fill the remaining capacity explicitly as a segment so only the right
    // side shows the track color (no border/track around the whole bar).
    final int remainCap = cap > 0 ? (cap - used).clamp(0, cap) : 0;
    final List<SegmentedTokenBarSegment> barSegments = remainCap > 0
        ? <SegmentedTokenBarSegment>[
            ...segments,
            SegmentedTokenBarSegment(
              tokens: remainCap,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
          ]
        : segments;

    return SizedBox(
      height: 0,
      child: OverflowBox(
        alignment: Alignment.bottomLeft,
        minHeight: ChatContextAppBarUsageBar._barHeight,
        maxHeight: ChatContextAppBarUsageBar._barHeight,
        child: Padding(
          // Keep symmetric gutters like the AppBar content.
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => ChatContextSheet.show(context),
              child: Transform.translate(
                // Lift it further into the toolbar area (reduce the large empty gap).
                offset: const Offset(0, -AppTheme.spacing2),
                child: SegmentedTokenBar(
                  totalTokens: total,
                  segments: barSegments,
                  height: ChatContextAppBarUsageBar._barHeight,
                  radius: 999,
                  backgroundColor: Colors.transparent,
                  borderColor: Colors.transparent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptUsageEstimate {
  const _PromptUsageEstimate({
    required this.model,
    required this.contextCapTokens,
    required this.outputCapTokens,
    required this.totalTokens,
    required this.parts,
  });

  final String model;
  final int? contextCapTokens;
  final int? outputCapTokens;
  final int totalTokens;
  final Map<String, int> parts;
}

class ChatContextPanel extends StatefulWidget {
  const ChatContextPanel({
    super.key,
    this.presentation = ChatContextPanelPresentation.bottomSheet,
  });

  final ChatContextPanelPresentation presentation;

  @override
  State<ChatContextPanel> createState() => _ChatContextPanelState();
}

class _ChatContextPanelState extends State<ChatContextPanel> {
  Future<ChatContextSnapshot>? _future;
  // Cache the last successful snapshot/token count so periodic refresh won't "flash"
  // the sheet by resetting FutureBuilder data to null.
  ChatContextSnapshot? _cachedSnapshot;
  Timer? _pollTimer;
  bool _refreshInFlight = false;
  bool _busy = false;
  String _activeModel = '';
  int? _activeModelContextTokens;
  int? _activeModelOutputTokens;
  String _lastPromptModelForCapOverride = '';
  bool _amEnabled = true;
  bool _amAutoExtract = false;
  int _amMaxTokens = 700;
  int _amMaxItems = 24;

  @override
  void initState() {
    super.initState();
    _reload();
    // Keep it "near real-time" while the sheet is open (e.g. tool-loop updates).
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted) return;
      if (_busy || _refreshInFlight) return;
      _refreshSnapshotOnly();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }

  void _refreshSnapshotOnly() {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    final Future<ChatContextSnapshot> snapFuture = ChatContextService.instance
        .getSnapshot();
    snapFuture
        .then((s) {
          _cachedSnapshot = s;
          try {
            final String raw = s.lastPromptBreakdownJson.trim();
            if (raw.isEmpty) return;
            final dynamic decoded = jsonDecode(raw);
            if (decoded is! Map) return;
            final String m = (decoded['model'] ?? '').toString().trim();
            if (m.isEmpty) return;
            if (m == _lastPromptModelForCapOverride) return;
            _lastPromptModelForCapOverride = m;
            unawaited(() async {
              final int? v = await AIModelPromptCapsService.instance
                  .getOverride(m);
              if (!mounted) return;
              // Only rebuild if we actually have a custom override (otherwise
              // the default inference stays the same).
              if (v != null) setState(() {});
            }());
          } catch (_) {}
        })
        .catchError((_) {});
    snapFuture.whenComplete(() {
      _refreshInFlight = false;
    });
    setState(() {
      _future = snapFuture;
    });
  }

  void _reload() {
    _refreshSnapshotOnly();
    _loadModelInfo();
    _loadAtomicMemorySettings();
  }

  Future<void> _loadModelInfo() async {
    try {
      final String model = await AISettingsService.instance.getModel();
      final int ctx = (await AIContextBudgets.forModelWithOverrides(
        model,
      )).promptCapTokens.clamp(256, 1 << 30).toInt();
      final int? out = ModelsDevModelLimits.outputTokens(model);
      if (!mounted) return;
      setState(() {
        _activeModel = model;
        _activeModelContextTokens = ctx;
        _activeModelOutputTokens = out;
      });
    } catch (_) {}
  }

  Locale _effectivePromptLocale() {
    final Locale? configured = LocaleService.instance.locale;
    final Locale device = WidgetsBinding.instance.platformDispatcher.locale;
    final Locale base = configured ?? device;
    final String code = base.languageCode.toLowerCase();
    if (code.startsWith('zh')) return const Locale('zh');
    if (code.startsWith('ja')) return const Locale('ja');
    if (code.startsWith('ko')) return const Locale('ko');
    return const Locale('en');
  }

  String _systemPromptForLocale() {
    final Locale locale = _effectivePromptLocale();
    return lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;
  }

  int _promptCapTokensForUi() {
    final String model = _activeModel.trim();
    return _activeModelContextTokens ??
        AIContextBudgets.forModel(model).promptCapTokens;
  }

  int _amMaxTokensCapForUi() {
    final int cap = _promptCapTokensForUi();
    // Keep it bounded while still scaling by model prompt cap.
    return (cap * 0.15).round().clamp(100, 8000);
  }

  int _approxToolSchemaTokens(List<Map<String, dynamic>> tools) {
    if (tools.isEmpty) return 0;
    try {
      return PromptBudget.approxTokensForText(jsonEncode(tools));
    } catch (_) {
      return PromptBudget.approxTokensForText('$tools');
    }
  }

  String _buildToolUsageInstructionForUi({
    required List<Map<String, dynamic>> tools,
  }) {
    if (tools.isEmpty) return '';

    final Locale locale = _effectivePromptLocale();
    final bool isZh = locale.languageCode.toLowerCase().startsWith('zh');
    String loc(String zh, String en) => isZh ? zh : en;

    final Set<String> names = <String>{};
    for (final Map<String, dynamic> t in tools) {
      final Object? fn0 = t['function'];
      if (fn0 is! Map) continue;
      final Map fn = fn0;
      final String name = (fn['name'] ?? '').toString().trim();
      if (name.isNotEmpty) names.add(name);
    }

    final StringBuffer sb = StringBuffer();
    sb.writeln(
      loc(
        '已启用工具调用。需要时可调用工具；不要编造工具结果。',
        'Tool calling is enabled. You MAY call tools when needed; do NOT fabricate tool results.',
      ),
    );
    sb.writeln(loc('可用工具：', 'Available tools:'));
    for (final Map<String, dynamic> t in tools) {
      final Object? fn0 = t['function'];
      if (fn0 is! Map) continue;
      final Map fn = fn0;
      final String name = (fn['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final String desc = (fn['description'] ?? '').toString().trim();
      sb.writeln(desc.isEmpty ? '- $name' : '- $name: $desc');
    }
    sb.writeln(loc('规则：', 'Rules:'));
    sb.writeln(loc('- 不要编造工具结果。', '- Do NOT fabricate tool results.'));
    sb.writeln(
      loc(
        '- 回答若涉及用户本地记录（聊天/转账/截图内容等），请在关键结论处附上证据引用 [evidence: X]（X 必须是工具返回或上下文提供的截图 filename）。',
        '- If your answer relies on the user’s local records, attach evidence references [evidence: X] for key claims (X must be a screenshot filename from tool outputs or provided context).',
      ),
    );

    final bool hasRetrievalTools =
        names.contains('search_segments') ||
        names.contains('search_screenshots_ocr') ||
        names.contains('search_ai_image_meta');
    if (hasRetrievalTools) {
      sb.writeln(
        loc(
          '- 对于“查找/定位用户历史记录”的问题，优先调用检索类工具，不要猜。',
          '- For lookup tasks, prefer calling retrieval tools first. Do not guess.',
        ),
      );
    }

    return sb.toString().trim();
  }

  Future<_PromptUsageEstimate> _estimateCurrentPromptUsage(
    ChatContextSnapshot s,
  ) async {
    final String model = _activeModel.trim().isNotEmpty
        ? _activeModel.trim()
        : (await AISettingsService.instance.getModel()).trim();
    final AIContextBudgets budgets = AIContextBudgets.forModel(model);
    final int capTokens = budgets.promptCapTokens;
    final int? outTokens = ModelsDevModelLimits.outputTokens(model);

    int msgTokens(String role, String content) {
      return PromptBudget.approxTokensForMessageJson(
        AIMessage(role: role, content: content),
      );
    }

    final Map<String, int> parts = <String, int>{};

    // System prompt is always included.
    final String systemPrompt = _systemPromptForLocale().trim();
    final int systemTokens = systemPrompt.isEmpty
        ? 0
        : msgTokens('system', systemPrompt);
    if (systemTokens > 0)
      parts[PromptTokenPart.systemPrompt.key] = systemTokens;

    // Tool schema is sent out-of-band (not in messages) for tool-enabled calls.
    // We approximate using default chat tools for a stable "global usage" view.
    final List<Map<String, dynamic>> tools = AIChatService.defaultChatTools();
    final int toolSchemaTokens = _approxToolSchemaTokens(tools);
    if (toolSchemaTokens > 0)
      parts[PromptTokenPart.toolSchema.key] = toolSchemaTokens;

    // Tool-usage instruction is a system message when tools are enabled.
    final String toolInstruction = _buildToolUsageInstructionForUi(
      tools: tools,
    );
    final int toolInstructionTokens = toolInstruction.trim().isEmpty
        ? 0
        : msgTokens('system', toolInstruction.trim());
    if (toolInstructionTokens > 0) {
      parts[PromptTokenPart.toolInstruction.key] = toolInstructionTokens;
    }

    // Conversation context (summary + tool memory) is injected as a system message.
    String ctxMsg = '';
    try {
      ctxMsg = await ChatContextService.instance.buildSystemContextMessage(
        cid: s.cid,
      );
    } catch (_) {}
    final int ctxTokens = ctxMsg.trim().isEmpty
        ? 0
        : msgTokens('system', ctxMsg.trim());
    if (ctxTokens > 0)
      parts[PromptTokenPart.conversationContext.key] = ctxTokens;

    // Use append-only transcript as primary history source; fall back to UI tail.
    List<AIMessage> history = const <AIMessage>[];
    try {
      history = await ChatContextService.instance.loadRecentMessagesForPrompt(
        cid: s.cid,
        maxTokens: budgets.historyPromptTokens,
      );
    } catch (_) {}
    List<AIMessage> uiHistory = const <AIMessage>[];
    try {
      uiHistory = await AISettingsService.instance.getChatHistory();
    } catch (_) {}

    List<AIMessage> filterHistory(List<AIMessage> src) {
      return src
          .where(
            (m) =>
                (m.role == 'user' ||
                    m.role == 'assistant' ||
                    m.role == 'tool') &&
                m.content.trim().isNotEmpty,
          )
          .toList();
    }

    final List<AIMessage> merged = <AIMessage>[...filterHistory(history)];
    if (merged.isEmpty) {
      merged.addAll(filterHistory(uiHistory));
    } else {
      final List<AIMessage> tail = filterHistory(uiHistory);
      final int take = tail.length.clamp(0, 6);
      final List<AIMessage> lastFew = take == 0
          ? const <AIMessage>[]
          : tail.sublist(tail.length - take);

      String sig(AIMessage m) => '${m.role}\n${m.content}';
      final int recentWindow = merged.length.clamp(0, 12);
      final Set<String> recentSigs = <String>{
        for (final m in merged.sublist(merged.length - recentWindow)) sig(m),
      };
      for (final AIMessage m in lastFew) {
        final String s0 = sig(m);
        if (recentSigs.contains(s0)) continue;
        merged.add(AIMessage(role: m.role, content: m.content));
        recentSigs.add(s0);
      }
    }

    final List<AIMessage> trimmedHistory = merged.isEmpty
        ? const <AIMessage>[]
        : PromptBudget.keepTailUnderTokenBudget(
            merged,
            maxTokens: budgets.historyPromptTokens,
          );

    int historyUser = 0;
    int historyAssistant = 0;
    int historyTool = 0;
    for (final AIMessage m in trimmedHistory) {
      final int t = msgTokens(m.role, m.content);
      if (m.role == 'assistant') {
        historyAssistant += t;
      } else if (m.role == 'tool') {
        historyTool += t;
      } else {
        historyUser += t;
      }
    }
    if (historyUser > 0) parts[PromptTokenPart.historyUser.key] = historyUser;
    if (historyAssistant > 0) {
      parts[PromptTokenPart.historyAssistant.key] = historyAssistant;
    }
    if (historyTool > 0) parts[PromptTokenPart.historyTool.key] = historyTool;

    final int total = parts.values.fold(0, (a, b) => a + b);
    return _PromptUsageEstimate(
      model: model,
      contextCapTokens: capTokens,
      outputCapTokens: outTokens,
      totalTokens: total,
      parts: parts,
    );
  }

  Future<void> _loadAtomicMemorySettings() async {
    try {
      final s = AISettingsService.instance;
      final bool enabled = await s.getAtomicMemoryInjectionEnabled();
      final bool autoExtract = await s.getAtomicMemoryAutoExtractEnabled();
      final int maxTokens = await s.getAtomicMemoryPromptTokens();
      final int maxItems = await s.getAtomicMemoryMaxItems();
      if (!mounted) return;
      setState(() {
        _amEnabled = enabled;
        _amAutoExtract = autoExtract;
        _amMaxTokens = maxTokens;
        _amMaxItems = maxItems;
      });
    } catch (_) {}
  }

  Future<void> _setAmEnabled(bool v) async {
    setState(() => _amEnabled = v);
    try {
      await AISettingsService.instance.setAtomicMemoryInjectionEnabled(v);
    } catch (_) {}
  }

  Future<void> _setAmAutoExtract(bool v) async {
    setState(() => _amAutoExtract = v);
    try {
      await AISettingsService.instance.setAtomicMemoryAutoExtractEnabled(v);
    } catch (_) {}
  }

  Future<void> _setAmMaxTokens(int v) async {
    final int next = v.clamp(100, _amMaxTokensCapForUi());
    setState(() => _amMaxTokens = next);
    try {
      await AISettingsService.instance.setAtomicMemoryPromptTokens(next);
    } catch (_) {}
  }

  Future<void> _setAmMaxItems(int v) async {
    final int next = v.clamp(5, 80);
    setState(() => _amMaxItems = next);
    try {
      await AISettingsService.instance.setAtomicMemoryMaxItems(next);
    } catch (_) {}
  }

  Future<void> _copy(String text) async {
    final String t = text.trim();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    UINotifier.success(
      context,
      ChatContextSheet._loc(context, '已复制', 'Copied'),
    );
  }

  Future<void> _editModelPromptCapDialog(
    BuildContext context, {
    required String model,
    required int fallbackPromptCapTokens,
  }) async {
    final String m = model.trim();
    if (m.isEmpty) return;

    final int? override0 = await AIModelPromptCapsService.instance.getOverride(
      m,
    );
    final bool hasOverride = override0 != null;
    final int cap0 = (override0 ?? fallbackPromptCapTokens)
        .clamp(256, 1 << 30)
        .toInt();

    final TextEditingController ctrl = TextEditingController(text: '$cap0');

    // Keep the dialog open on invalid input.
    Future<void> save(BuildContext ctx) async {
      final int? v = int.tryParse(ctrl.text.trim());
      if (v == null) {
        UINotifier.error(
          context,
          ChatContextSheet._loc(context, '请输入数字', 'Please enter a number.'),
        );
        return;
      }
      if (v < 256) {
        UINotifier.error(
          context,
          ChatContextSheet._loc(
            context,
            '值过小（至少 256）',
            'Value too small (min 256).',
          ),
        );
        return;
      }

      await AIModelPromptCapsService.instance.setOverride(m, v);
      if (mounted) setState(() {});
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, '已保存', 'Saved'),
      );
    }

    Future<void> clear(BuildContext ctx) async {
      await AIModelPromptCapsService.instance.clearOverride(m);
      if (mounted) setState(() {});
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, '已清除', 'Cleared'),
      );
    }

    await showUIDialog<void>(
      context: context,
      title: ChatContextSheet._loc(
        context,
        '设置模型最大 token',
        'Set model max tokens',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ChatContextSheet._loc(context, '模型', 'Model'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            m,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppTheme.spacing3),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: ChatContextSheet._loc(
                context,
                '最大 token（prompt）',
                'Max tokens (prompt)',
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            hasOverride
                ? ChatContextSheet._loc(
                    context,
                    '当前为自定义值（可清除恢复默认推断）',
                    'Custom value is set (you can clear to restore defaults).',
                  )
                : ChatContextSheet._loc(
                    context,
                    '未设置自定义值（当前为默认推断）',
                    'No custom value (using defaults).',
                  ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <UIDialogAction<void>>[
        UIDialogAction<void>(
          text: ChatContextSheet._loc(context, '取消', 'Cancel'),
        ),
        if (hasOverride)
          UIDialogAction<void>(
            text: ChatContextSheet._loc(context, '清除', 'Clear'),
            style: UIDialogActionStyle.destructive,
            closeOnPress: false,
            onPressed: clear,
          ),
        UIDialogAction<void>(
          text: ChatContextSheet._loc(context, '保存', 'Save'),
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: save,
        ),
      ],
    );
  }

  Future<void> _run({
    required Future<void> Function() action,
    required String okTextZh,
    required String okTextEn,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, okTextZh, okTextEn),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        ChatContextSheet._loc(context, '失败：$e', 'Failed: $e'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDrawer =
        widget.presentation == ChatContextPanelPresentation.drawer;
    return DraggableScrollableSheet(
      initialChildSize: isDrawer ? 1.0 : 0.75,
      minChildSize: isDrawer ? 1.0 : 0.45,
      maxChildSize: isDrawer ? 1.0 : 0.95,
      expand: isDrawer,
      builder: (sheetCtx, ctrl) {
        return UISheetSurface(
          safeAreaTop: isDrawer,
          child: Column(
            children: [
              if (!isDrawer) ...[
                const SizedBox(height: AppTheme.spacing3),
                const UISheetHandle(),
                const SizedBox(height: AppTheme.spacing2),
              ] else ...[
                const SizedBox(height: AppTheme.spacing2),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ChatContextSheet._loc(
                          context,
                          '对话上下文（压缩/记忆）',
                          'Conversation Context (Memory)',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: ChatContextSheet._loc(context, '刷新', 'Refresh'),
                      onPressed: _busy ? null : _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    if (isDrawer)
                      IconButton(
                        tooltip: ChatContextSheet._loc(context, '关闭', 'Close'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacing2),
              Expanded(
                child: FutureBuilder<ChatContextSnapshot>(
                  future: _future,
                  initialData: _cachedSnapshot,
                  builder: (c, snap) {
                    final ChatContextSnapshot? s = snap.data;
                    final bool loading =
                        snap.connectionState != ConnectionState.done;
                    if (s == null) {
                      // Avoid flashing the whole sheet during periodic refresh:
                      // keep showing the previous snapshot while a new one loads.
                      if (loading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Center(
                        child: Text(
                          ChatContextSheet._loc(
                            context,
                            '未获取到上下文信息',
                            'No context snapshot',
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }

                    final String summary = s.summary.trim();
                    final String toolMemPretty = ChatContextSheet._prettyJson(
                      s.toolMemoryJson,
                    );

                    return ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        0,
                        AppTheme.spacing4,
                        AppTheme.spacing4,
                      ),
                      children: [
                        _kvCard(
                          context,
                          title: ChatContextSheet._loc(context, '状态', 'Status'),
                          rows: <MapEntry<String, String>>[
                            MapEntry('cid', s.cid),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '全量消息数',
                                'Full messages',
                              ),
                              s.fullMessageCount.toString(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '摘要更新时间',
                                'Summary updated',
                              ),
                              ChatContextSheet._fmtTs(s.summaryUpdatedAtMs),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '压缩次数',
                                'Compactions',
                              ),
                              s.compactionCount.toString(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '上次压缩原因',
                                'Last reason',
                              ),
                              (s.lastCompactionReason ?? '').trim().isEmpty
                                  ? '-'
                                  : s.lastCompactionReason!.trim(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '工具记忆更新时间',
                                'Tool memory updated',
                              ),
                              ChatContextSheet._fmtTs(s.toolMemoryUpdatedAtMs),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '上次 prompt 时间',
                                'Last prompt time',
                              ),
                              ChatContextSheet._fmtTs(s.lastPromptAtMs),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        _conversationTokenUsageCard(context, s),
                        const SizedBox(height: AppTheme.spacing3),
                        _atomicMemoryCard(context),
                        const SizedBox(height: AppTheme.spacing3),
                        _actionRow(
                          context,
                          busy: _busy,
                          onCompact: () => _run(
                            action: () => ChatContextService.instance
                                .compactNow(reason: 'manual_ui'),
                            okTextZh: '压缩完成',
                            okTextEn: 'Compaction done',
                          ),
                          onClearMemory: () => _run(
                            action: () =>
                                ChatContextService.instance.clearContext(),
                            okTextZh: '已清空记忆',
                            okTextEn: 'Memory cleared',
                          ),
                          onClearChat: () => _run(
                            action: () =>
                                AISettingsService.instance.clearChatHistory(),
                            okTextZh: '已清空对话',
                            okTextEn: 'Conversation cleared',
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            ChatContextSheet._loc(
                              context,
                              '摘要（用于注入模型）',
                              'Summary (Injected to model)',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            summary.isEmpty
                                ? ChatContextSheet._loc(
                                    context,
                                    '暂无摘要（达到阈值后会自动生成，或手动点击“立即压缩”）',
                                    'No summary yet (auto after threshold, or tap “Compact now”).',
                                  )
                                : (summary.length > 80
                                      ? (summary.substring(0, 80) + '…')
                                      : summary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppTheme.spacing3),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                              ),
                              child: SelectableText(
                                summary.isEmpty ? '-' : summary,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            Align(
                              alignment: Alignment.centerRight,
                              child: UIButton(
                                text: ChatContextSheet._loc(
                                  context,
                                  '复制摘要',
                                  'Copy',
                                ),
                                onPressed: summary.isEmpty
                                    ? null
                                    : () => _copy(summary),
                                variant: UIButtonVariant.outline,
                                size: UIButtonSize.small,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            ChatContextSheet._loc(
                              context,
                              '工具记忆（摘要）',
                              'Tool memory (Digest)',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            toolMemPretty.isEmpty
                                ? ChatContextSheet._loc(
                                    context,
                                    '暂无工具记忆（模型调用检索工具后会自动写入）',
                                    'No tool memory yet (written after tool calls).',
                                  )
                                : (toolMemPretty.length > 80
                                      ? (toolMemPretty.substring(0, 80) + '…')
                                      : toolMemPretty),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppTheme.spacing3),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                              ),
                              child: SelectableText(
                                toolMemPretty.isEmpty ? '-' : toolMemPretty,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            Align(
                              alignment: Alignment.centerRight,
                              child: UIButton(
                                text: ChatContextSheet._loc(
                                  context,
                                  '复制',
                                  'Copy',
                                ),
                                onPressed: toolMemPretty.isEmpty
                                    ? null
                                    : () => _copy(toolMemPretty),
                                variant: UIButtonVariant.outline,
                                size: UIButtonSize.small,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _lastPromptUsageCard(BuildContext context, ChatContextSnapshot s) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();

    String model = _activeModel;
    int? maxTokens = _activeModelContextTokens;
    int? outTokens = _activeModelOutputTokens;

    final Map<String, int> parts = <String, int>{};
    int totalTokens = s.lastPromptTokens ?? 0;

    final String raw = s.lastPromptBreakdownJson.trim();
    if (raw.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          final String m = (decoded['model'] ?? '').toString().trim();
          if (m.isNotEmpty) {
            model = m;
            final int fallbackCap = AIContextBudgets.forModel(
              m,
            ).promptCapTokens;
            final int? override = AIModelPromptCapsService.instance
                .peekOverride(m);
            maxTokens = override ?? fallbackCap;
            outTokens = ModelsDevModelLimits.outputTokens(m);
          }
          final dynamic total = decoded['total_tokens'];
          if (total is num) totalTokens = total.toInt();
          final dynamic p = decoded['parts'];
          if (p is Map) {
            for (final entry in p.entries) {
              final String k = entry.key.toString();
              final dynamic v = entry.value;
              if (v is num) {
                final int t = v.toInt();
                if (t > 0) parts[k] = t;
              }
            }
          }
        }
      } catch (_) {}
    }

    final int used = parts.isNotEmpty
        ? parts.values.fold(0, (a, b) => a + b)
        : totalTokens;
    final int cap = (maxTokens ?? 0).clamp(0, 1 << 30);
    final double ratio = cap > 0 ? (used / cap).clamp(0.0, 999.0) : 0.0;

    final List<PromptTokenPart> order = <PromptTokenPart>[
      PromptTokenPart.systemPrompt,
      PromptTokenPart.toolSchema,
      PromptTokenPart.toolInstruction,
      PromptTokenPart.conversationContext,
      PromptTokenPart.atomicMemory,
      PromptTokenPart.extraSystem,
      PromptTokenPart.historyUser,
      PromptTokenPart.historyAssistant,
      PromptTokenPart.historyTool,
      PromptTokenPart.userMessage,
    ];

    final List<SegmentedTokenBarSegment> segments = <SegmentedTokenBarSegment>[
      for (final part in order)
        if ((parts[part.key] ?? 0) > 0)
          SegmentedTokenBarSegment(
            tokens: parts[part.key]!,
            color: part.color(theme),
          ),
      if (parts.isEmpty && used > 0)
        SegmentedTokenBarSegment(
          tokens: used,
          color: theme.colorScheme.primary,
        ),
    ];

    final String capText = cap > 0 ? nf.format(cap) : '-';
    final String usedText = used > 0 ? nf.format(used) : '-';
    final String pctText = cap > 0
        ? '${(ratio * 100).toStringAsFixed(1)}%'
        : '-';
    final String outText = outTokens == null
        ? ''
        : ' · out≈${nf.format(outTokens)}';

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ChatContextSheet._loc(
              context,
              '最近一次模型调用占用（≈）',
              'Last model call usage (≈)',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            ChatContextSheet._loc(
              context,
              '时间：${ChatContextSheet._fmtTs(s.lastPromptAtMs)}',
              'Time: ${ChatContextSheet._fmtTs(s.lastPromptAtMs)}',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(context, '模型：$model', 'Model: $model'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: ChatContextSheet._loc(context, '设置上限', 'Set cap'),
                onPressed: model.trim().isEmpty
                    ? null
                    : () => _editModelPromptCapDialog(
                        context,
                        model: model,
                        fallbackPromptCapTokens: AIContextBudgets.forModel(
                          model,
                        ).promptCapTokens,
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            ChatContextSheet._loc(
              context,
              '已用 $usedText / $capText（$pctText）$outText',
              'Used $usedText / $capText ($pctText)$outText',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          SegmentedTokenBar(
            totalTokens: cap > 0 ? cap : (used > 0 ? used : 1),
            segments: segments,
            height: 12,
          ),
          if (raw.isEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              ChatContextSheet._loc(
                context,
                '暂无记录（发送一次消息后会写入）',
                'No record yet (written after you send a message).',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (parts.isEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              ChatContextSheet._loc(
                context,
                '暂无细分数据',
                'No breakdown available.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppTheme.spacing2),
            Wrap(
              spacing: AppTheme.spacing2,
              runSpacing: AppTheme.spacing1,
              children: [
                for (final part in order)
                  if ((parts[part.key] ?? 0) > 0)
                    _legendItem(
                      context,
                      color: part.color(theme),
                      label: ChatContextSheet._isZh(context)
                          ? part.labelZh()
                          : part.labelEn(),
                      tokens: parts[part.key]!,
                      total: cap > 0 ? cap : used,
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendItem(
    BuildContext context, {
    required Color color,
    required String label,
    required int tokens,
    required int total,
  }) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();
    final double pct = total > 0 ? (tokens / total) : 0;
    final String pctText = '${(pct * 100).toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: AppTheme.spacing1),
          Text(
            '$label · ${nf.format(tokens)} ($pctText)',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _conversationTokenUsageCard(
    BuildContext context,
    ChatContextSnapshot s,
  ) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();

    String model = _activeModel;
    int fallbackCapTokens = (_activeModelContextTokens ?? 0)
        .clamp(0, 1 << 30)
        .toInt();

    final List<PromptTokenPart> order = <PromptTokenPart>[
      PromptTokenPart.systemPrompt,
      PromptTokenPart.toolSchema,
      PromptTokenPart.toolInstruction,
      PromptTokenPart.conversationContext,
      PromptTokenPart.atomicMemory,
      PromptTokenPart.extraSystem,
      PromptTokenPart.historyUser,
      PromptTokenPart.historyAssistant,
      PromptTokenPart.historyTool,
      PromptTokenPart.userMessage,
    ];

    final Map<String, int> parts = <String, int>{};
    int tokens = (s.lastPromptTokens ?? 0).clamp(0, 1 << 62).toInt();

    final String raw = s.lastPromptBreakdownJson.trim();
    if (raw.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          final String m = (decoded['model'] ?? '').toString().trim();
          if (m.isNotEmpty) {
            model = m;
            fallbackCapTokens = AIContextBudgets.forModel(m).promptCapTokens;
          }
          final dynamic total = decoded['total_tokens'];
          if (total is num) tokens = total.toInt();
          final dynamic p = decoded['parts'];
          if (p is Map) {
            for (final entry in p.entries) {
              final String k = entry.key.toString();
              final dynamic v = entry.value;
              if (v is! num) continue;
              final int t = v.toInt();
              if (t <= 0) continue;
              parts[k] = t;
            }
          }
        }
      } catch (_) {}
    }

    final int capTokens =
        (AIModelPromptCapsService.instance.peekOverride(model) ??
                fallbackCapTokens)
            .clamp(0, 1 << 30)
            .toInt();
    final double ratio = capTokens > 0
        ? (tokens / capTokens).clamp(0.0, 999.0)
        : 0.0;

    // No breakdown recorded (older rows / failures): keep totals consistent.
    if (parts.isEmpty && tokens > 0) {
      parts[PromptTokenPart.extraSystem.key] = tokens;
    }

    final int partsSum = order.fold<int>(
      0,
      (a, part) => a + (parts[part.key] ?? 0),
    );
    final int remainder = (tokens - partsSum).clamp(0, 1 << 62).toInt();

    final List<SegmentedTokenBarSegment> segments = <SegmentedTokenBarSegment>[
      for (final part in order)
        if ((parts[part.key] ?? 0) > 0)
          SegmentedTokenBarSegment(
            tokens: parts[part.key]!,
            color: part.color(theme),
          ),
    ];
    if (segments.isEmpty) {
      if (tokens > 0) {
        segments.add(
          SegmentedTokenBarSegment(
            tokens: tokens,
            color: theme.colorScheme.primary,
          ),
        );
      }
    } else if (remainder > 0) {
      segments.add(
        SegmentedTokenBarSegment(
          tokens: remainder,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(
                    context,
                    '当前对话 token（≈）',
                    'Current conversation tokens (≈)',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: ChatContextSheet._loc(context, '设置上限', 'Set cap'),
                onPressed: model.trim().isEmpty
                    ? null
                    : () => _editModelPromptCapDialog(
                        context,
                        model: model,
                        fallbackPromptCapTokens: AIContextBudgets.forModel(
                          model,
                        ).promptCapTokens,
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            nf.format(tokens),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (tokens > 0 && capTokens > 0) ...[
            const SizedBox(height: AppTheme.spacing1),
            Text(
              ChatContextSheet._loc(
                context,
                '已用 ${nf.format(tokens)} / ${nf.format(capTokens)}（${(ratio * 100).toStringAsFixed(1)}%） · 模型：$model',
                'Used ${nf.format(tokens)} / ${nf.format(capTokens)} (${(ratio * 100).toStringAsFixed(1)}%) · Model: $model',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (model.trim().isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing1),
            Text(
              ChatContextSheet._loc(context, '模型：$model', 'Model: $model'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (tokens <= 0) ...[
            const SizedBox(height: AppTheme.spacing1),
            Text(
              ChatContextSheet._loc(
                context,
                '暂无记录（发送一次消息后会写入）',
                'No record yet (written after you send a message).',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppTheme.spacing2),
            SegmentedTokenBar(
              totalTokens: capTokens > 0
                  ? capTokens
                  : (tokens > 0 ? tokens : 1),
              segments: segments,
              height: 12,
            ),
            if (parts.isNotEmpty || remainder > 0) ...[
              const SizedBox(height: AppTheme.spacing2),
              Wrap(
                spacing: AppTheme.spacing2,
                runSpacing: AppTheme.spacing1,
                children: [
                  for (final part in order)
                    if ((parts[part.key] ?? 0) > 0)
                      _legendItem(
                        context,
                        color: part.color(theme),
                        label: ChatContextSheet._isZh(context)
                            ? part.labelZh()
                            : part.labelEn(),
                        tokens: parts[part.key]!,
                        total: tokens,
                      ),
                  if (remainder > 0)
                    _legendItem(
                      context,
                      color: theme.colorScheme.primary,
                      label: ChatContextSheet._loc(context, '其他', 'Other'),
                      tokens: remainder,
                      total: tokens,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _atomicMemoryCard(BuildContext context) {
    final theme = Theme.of(context);
    final int amCap = _amMaxTokensCapForUi();
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ChatContextSheet._loc(
              context,
              '原子记忆注入（SimpleMem）',
              'Atomic memory injection (SimpleMem)',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(
                    context,
                    '启用 <atomic_memory> 系统消息（事实/规则）',
                    'Enable <atomic_memory> system message (facts/rules)',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(
                value: _amEnabled,
                onChanged: _busy ? null : (v) => _setAmEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(
                    context,
                    '自动抽取并写入（会触发 AI 调用）',
                    'Auto-extract & write (uses AI calls)',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(
                value: _amAutoExtract,
                onChanged: _busy ? null : (v) => _setAmAutoExtract(v),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          _stepperRow(
            context,
            label: ChatContextSheet._loc(
              context,
              'Token 预算（粗估）',
              'Token budget (approx)',
            ),
            valueText: _amMaxTokens.toString(),
            onMinus: _busy || _amMaxTokens <= 100
                ? null
                : () => _setAmMaxTokens(_amMaxTokens - 100),
            onPlus: _busy || _amMaxTokens >= amCap
                ? null
                : () => _setAmMaxTokens(_amMaxTokens + 100),
          ),
          const SizedBox(height: AppTheme.spacing1),
          _stepperRow(
            context,
            label: ChatContextSheet._loc(context, '条目上限', 'Max items'),
            valueText: _amMaxItems.toString(),
            onMinus: _busy || _amMaxItems <= 5
                ? null
                : () => _setAmMaxItems(_amMaxItems - 5),
            onPlus: _busy || _amMaxItems >= 80
                ? null
                : () => _setAmMaxItems(_amMaxItems + 5),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            ChatContextSheet._loc(
              context,
              '提示：原子记忆用于稳定保存“可复用的个人事实/偏好规则”。开启自动抽取会增加一次小的后台请求（已做节流）。',
              'Tip: atomic memory stores durable user facts/preferences. Auto-extract adds a small background request (throttled).',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperRow(
    BuildContext context, {
    required String label,
    required String valueText,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        IconButton(
          tooltip: ChatContextSheet._loc(context, '减少', 'Decrease'),
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 64,
          child: Center(
            child: Text(valueText, style: theme.textTheme.bodySmall),
          ),
        ),
        IconButton(
          tooltip: ChatContextSheet._loc(context, '增加', 'Increase'),
          onPressed: onPlus,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  Widget _kvCard(
    BuildContext context, {
    required String title,
    required List<MapEntry<String, String>> rows,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          ...rows.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      e.key,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      e.value,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required bool busy,
    required VoidCallback onCompact,
    required VoidCallback onClearMemory,
    required VoidCallback onClearChat,
  }) {
    return Row(
      children: [
        Expanded(
          child: UIButton(
            text: ChatContextSheet._loc(context, '立即压缩', 'Compact now'),
            onPressed: busy ? null : onCompact,
            variant: UIButtonVariant.primary,
            size: UIButtonSize.small,
            fullWidth: true,
          ),
        ),
        const SizedBox(width: AppTheme.spacing2),
        Expanded(
          child: UIButton(
            text: ChatContextSheet._loc(context, '清空记忆', 'Clear memory'),
            onPressed: busy ? null : onClearMemory,
            variant: UIButtonVariant.outline,
            size: UIButtonSize.small,
            fullWidth: true,
          ),
        ),
        const SizedBox(width: AppTheme.spacing2),
        Expanded(
          child: UIButton(
            text: ChatContextSheet._loc(context, '清空对话', 'Clear chat'),
            onPressed: busy ? null : onClearChat,
            variant: UIButtonVariant.destructive,
            size: UIButtonSize.small,
            fullWidth: true,
          ),
        ),
      ],
    );
  }
}

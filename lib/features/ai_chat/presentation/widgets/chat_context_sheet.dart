import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import 'package:screen_memo/models/models_dev_limits.dart';
import 'package:screen_memo/models/prompt_token_breakdown.dart';
import 'package:screen_memo/features/ai/application/ai_chat_service.dart';
import 'package:screen_memo/features/ai/application/ai_context_budgets.dart';
import 'package:screen_memo/features/ai/application/ai_model_prompt_caps_service.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/ai/application/chat_context_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/core/localization/locale_service.dart';
import 'package:screen_memo/features/ai/application/prompt_budget.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/segmented_token_bar.dart';
import 'package:screen_memo/core/widgets/ui_action_menu.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';

part 'chat_context_sheet_panel_state_part.dart';
part 'chat_context_sheet_panel_actions_part.dart';
part 'chat_context_sheet_panel_widgets_part.dart';

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

  static Future<void> showDrawerOrSheet(BuildContext context) async {
    await show(context);
  }
}

enum ChatContextPanelPresentation { bottomSheet, drawer }

enum _ConversationExportAction { copy, save }

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

/// AppBar action that opens the conversation-context bottom sheet.
///
/// The prompt/context usage indicator is shown as a bar under the AppBar (see
/// [ChatContextAppBarUsageBar]) instead of being overlaid on this icon.
class ChatContextAppBarAction extends StatelessWidget {
  const ChatContextAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => IconButton(
        tooltip: ChatContextSheet._loc(
          context,
          '对话上下文',
          'Conversation context',
        ),
        onPressed: () => ChatContextSheet.showDrawerOrSheet(ctx),
        icon: const Icon(Icons.memory_outlined),
      ),
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
      bool usedEvent = false;

      try {
        final List<PromptUsageEvent> events = await ChatContextService.instance
            .listPromptUsageEvents(cid: cid, limit: 1);
        if (events.isNotEmpty) {
          final PromptUsageEvent event = events.first;
          tokens = event.resolvedPromptTokens;
          model = event.model.trim().isNotEmpty ? event.model.trim() : model;
          final dynamic p = event.breakdown['parts'];
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
          usedEvent = true;
        }
      } catch (_) {}

      if (!usedEvent && raw.isNotEmpty) {
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
              onTap: () => ChatContextSheet.showDrawerOrSheet(context),
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

class _ConversationExportPayload {
  const _ConversationExportPayload({
    required this.snapshot,
    required this.messages,
    required this.trimEvents,
    required this.text,
  });

  final ChatContextSnapshot snapshot;
  final List<AIMessage> messages;
  final List<ChatContextEvent> trimEvents;
  final String text;
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
  static const int _trimEventsDefaultLimit = 50;
  static const int _trimEventsMaxLimit = 200;

  Future<ChatContextSnapshot>? _future;
  // Cache the last successful snapshot/token count so periodic refresh won't "flash"
  // the sheet by resetting FutureBuilder data to null.
  ChatContextSnapshot? _cachedSnapshot;
  List<ChatContextEvent> _cachedTrimEvents = const <ChatContextEvent>[];
  PromptUsageEvent? _cachedLatestUsage;
  Timer? _pollTimer;
  StreamSubscription<String>? _ctxSub;
  Timer? _ctxDebounce;
  bool _refreshInFlight = false;
  bool _busy = false;
  String _activeModel = '';
  int? _activeModelContextTokens;
  int? _activeModelOutputTokens;
  String _lastPromptModelForCapOverride = '';

  void _panelSetState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _reload();
    _ctxSub = AISettingsService.instance.onContextChanged.listen((String evt) {
      if (!mounted) return;
      // Fast-path: prompt usage is recorded per request (including tool-loop
      // iterations) and broadcasts `chat:prompt_tokens`.
      if (evt != 'chat:prompt_tokens') return;
      _ctxDebounce?.cancel();
      _ctxDebounce = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        if (_busy || _refreshInFlight) return;
        _refreshSnapshotOnly();
      });
    });
    // Fallback polling in case we miss a broadcast (keep overhead low).
    _pollTimer = Timer.periodic(const Duration(milliseconds: 5000), (_) {
      if (!mounted) return;
      if (_busy || _refreshInFlight) return;
      _refreshSnapshotOnly();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _ctxSub?.cancel();
    _ctxSub = null;
    _ctxDebounce?.cancel();
    _ctxDebounce = null;
    super.dispose();
  }

  Widget _buildPanelTitle(ThemeData theme) {
    final TextStyle titleStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    final l10n = AppLocalizations.of(context);

    return Text.rich(
      TextSpan(
        style: titleStyle,
        children: <InlineSpan>[
          TextSpan(text: l10n.chatContextTitlePrefix),
          TextSpan(text: l10n.chatContextTitleMemory),
          TextSpan(text: l10n.chatContextTitleSuffix),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
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
                    Expanded(child: _buildPanelTitle(theme)),
                    IconButton(
                      tooltip: ChatContextSheet._loc(context, '刷新', 'Refresh'),
                      onPressed: _busy ? null : _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    UIActionMenuButton<_ConversationExportAction>(
                      tooltip: ChatContextSheet._loc(
                        context,
                        '导出当前会话',
                        'Export conversation',
                      ),
                      enabled: !_busy,
                      onSelected: _onExportActionSelected,
                      showSelectedState: false,
                      items: [
                        UIActionMenuItem<_ConversationExportAction>(
                          value: _ConversationExportAction.copy,
                          label: ChatContextSheet._loc(
                            context,
                            '复制当前会话',
                            'Copy conversation',
                          ),
                        ),
                        UIActionMenuItem<_ConversationExportAction>(
                          value: _ConversationExportAction.save,
                          label: ChatContextSheet._loc(
                            context,
                            '保存到文件',
                            'Save to file',
                          ),
                        ),
                      ],
                      buttonIcon: const Icon(Icons.ios_share_outlined),
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
                    final List<ChatContextEvent> trimEvents = _cachedTrimEvents;
                    final PromptUsageEvent? latestUsage = _cachedLatestUsage;

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
                        _conversationTokenUsageCard(
                          context,
                          s,
                          latestUsage: latestUsage,
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        _trimEventsCard(context, trimEvents),
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
}

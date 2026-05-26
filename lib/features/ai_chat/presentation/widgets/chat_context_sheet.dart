import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import 'package:screen_memo/models/prompt_token_breakdown.dart';
import 'package:screen_memo/features/ai/application/ai_context_budgets.dart';
import 'package:screen_memo/features/ai/application/ai_model_prompt_caps_service.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/ai/application/chat_context_service.dart';
import 'package:screen_memo/features/ai/application/codex_style_token_usage.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/segmented_token_bar.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';

part 'chat_context_sheet_panel_state_part.dart';
part 'chat_context_sheet_panel_actions_part.dart';
part 'chat_context_sheet_panel_widgets_part.dart';

void _logAiChatPerf(String name, {String? detail, Stopwatch? stopwatch}) {
  final String d0 = (detail ?? '').trim();
  final String d = [
    if (stopwatch != null) 'ms=${stopwatch.elapsedMilliseconds}',
    if (d0.isNotEmpty) d0,
  ].join(' ');
  unawaited(
    FlutterLogger.nativeInfo(
      'AI_CHAT_PERF',
      d.isEmpty ? name : '$name $d',
    ).catchError((_) {}),
  );
}

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
  int _effectiveUsedTokens = 0;
  int _effectiveTotalTokens = 0;
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
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}k';
    }
    if (v < 1000000) {
      return '${(v / 1000).round()}k';
    }
    final String s = (v / 1000000).toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}m';
  }

  static Map<String, int> _partsFromBreakdown(Object? rawParts) {
    if (rawParts is! Map) return const <String, int>{};
    final Map<String, int> out = <String, int>{};
    for (final entry in rawParts.entries) {
      final int tokens = _toInt(entry.value);
      if (tokens <= 0) continue;
      out[entry.key.toString()] = tokens;
    }
    return out;
  }

  Future<void> _refresh() async {
    if (_refreshInFlight) {
      _logAiChatPerf('AppBarUsage.refresh.skip', detail: 'inFlight');
      return;
    }
    final Stopwatch sw = Stopwatch()..start();
    _logAiChatPerf('AppBarUsage.refresh.start');
    _refreshInFlight = true;
    try {
      final String cid = await AISettingsService.instance
          .getActiveConversationCid();
      _logAiChatPerf(
        'AppBarUsage.refresh.cid.done',
        stopwatch: sw,
        detail: 'cidHash=${cid.hashCode}',
      );
      final Map<String, dynamic>? row = await ScreenshotDatabase.instance
          .getAiConversationByCid(cid);
      _logAiChatPerf(
        'AppBarUsage.refresh.row.done',
        stopwatch: sw,
        detail: 'hasRow=${row != null}',
      );

      int tokens = _toInt(row?['last_prompt_tokens']);
      String model = (row?['model'] as String?)?.trim() ?? '';
      final String raw =
          (row?['last_prompt_breakdown_json'] as String?)?.trim() ?? '';
      Map<String, int> parts = const <String, int>{};

      try {
        final List<PromptUsageEvent> events = await ChatContextService.instance
            .listPromptUsageEvents(cid: cid, limit: 1);
        _logAiChatPerf(
          'AppBarUsage.refresh.usageEvents.done',
          stopwatch: sw,
          detail: 'events=${events.length}',
        );
        if (events.isNotEmpty) {
          final PromptUsageEvent event = events.first;
          tokens = event.codexStyleUsage.tokensInContextWindow;
          model = event.model.trim().isNotEmpty ? event.model.trim() : model;
          parts = _partsFromBreakdown(event.breakdown['parts']);
        }
      } catch (e) {
        _logAiChatPerf(
          'AppBarUsage.refresh.usageEvents.error',
          stopwatch: sw,
          detail: 'err=$e',
        );
      }

      if (raw.isNotEmpty) {
        try {
          final dynamic decoded = jsonDecode(raw);
          if (decoded is Map) {
            final String m = (decoded['model'] ?? '').toString().trim();
            if (m.isNotEmpty) model = m;
            final dynamic total = decoded['total_tokens'];
            if (total is num) tokens = total.toInt();
            if (parts.isEmpty) {
              parts = _partsFromBreakdown(decoded['parts']);
            }
          }
          _logAiChatPerf(
            'AppBarUsage.refresh.breakdown.done',
            stopwatch: sw,
            detail: 'rawLen=${raw.length} parts=${parts.length}',
          );
        } catch (e) {
          _logAiChatPerf(
            'AppBarUsage.refresh.breakdown.error',
            stopwatch: sw,
            detail: 'rawLen=${raw.length} err=$e',
          );
        }
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
      _logAiChatPerf(
        'AppBarUsage.refresh.models.done',
        stopwatch: sw,
        detail: 'model=$model activeModel=$activeModel',
      );

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
      _logAiChatPerf(
        'AppBarUsage.refresh.caps.done',
        stopwatch: sw,
        detail:
            'activeCap=$activeCapTokens promptCap=$promptModelCapTokens override=${promptModelOverride ?? -1}',
      );
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
      final CodexStyleTokenUsageInfo usageInfo = await ChatContextService
          .instance
          .getCodexStyleTokenUsageInfo(
            cid: cid,
            modelContextWindow: capTokens > 0 ? capTokens : null,
          );
      _logAiChatPerf(
        'AppBarUsage.refresh.codexUsage.done',
        stopwatch: sw,
        detail: 'cap=$capTokens',
      );
      final CodexStyleTokenUsage lastUsage = usageInfo.lastTokenUsage;
      tokens = lastUsage.tokensInContextWindow;
      int effectiveUsed = tokens.clamp(0, 1 << 62).toInt();
      int effectiveTotal = capTokens.clamp(0, 1 << 30).toInt();
      if (capTokens > CodexStyleTokenUsage.baselineTokens) {
        effectiveUsed = (tokens - CodexStyleTokenUsage.baselineTokens)
            .clamp(0, capTokens - CodexStyleTokenUsage.baselineTokens)
            .toInt();
        effectiveTotal = capTokens - CodexStyleTokenUsage.baselineTokens;
      }

      if (!mounted) return;
      setState(() {
        _tokens = tokens.clamp(0, 1 << 62).toInt();
        _capTokens = capTokens.clamp(0, 1 << 30).toInt();
        _effectiveUsedTokens = effectiveUsed;
        _effectiveTotalTokens = effectiveTotal;
        _parts = parts;
      });
      _logAiChatPerf(
        'AppBarUsage.refresh.setState.done',
        stopwatch: sw,
        detail:
            'tokens=$_tokens cap=$_capTokens effective=$_effectiveUsedTokens/$_effectiveTotalTokens parts=${_parts.length}',
      );
    } catch (e) {
      _logAiChatPerf(
        'AppBarUsage.refresh.error',
        stopwatch: sw,
        detail: 'err=$e',
      );
      // Keep the last known values; the app bar should never crash due to a
      // transient DB/model lookup failure.
    } finally {
      _refreshInFlight = false;
      _logAiChatPerf('AppBarUsage.refresh.done', stopwatch: sw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String usedText = _fmtCompactInt(_tokens);
    final String capText = _capTokens > 0 ? _fmtCompactInt(_capTokens) : '—';
    final double effectiveRatio = _effectiveTotalTokens > 0
        ? (_effectiveUsedTokens / _effectiveTotalTokens).clamp(0.0, 1.0)
        : 0.0;
    final String pctText = _capTokens > 0
        ? '${(effectiveRatio * 100).toStringAsFixed(1)}%'
        : '—';
    final String tooltip = ChatContextSheet._loc(
      context,
      '对话上下文 · $usedText/$capText · 有效占用 $pctText',
      'Conversation context · $usedText/$capText · effective used $pctText',
    );

    final int used = _tokens.clamp(0, 1 << 62).toInt();
    final int cap = _capTokens.clamp(0, 1 << 30).toInt();
    final int barUsed = _effectiveUsedTokens > 0 ? _effectiveUsedTokens : used;
    final int barTotal = _effectiveTotalTokens > 0
        ? _effectiveTotalTokens
        : (cap > 0 ? cap : (used > 0 ? used : 1));

    // Fill the remaining capacity explicitly as a segment so only the right
    // side shows the track color (no border/track around the whole bar).
    final int visibleUsed = barUsed.clamp(0, barTotal).toInt();
    final int remainCap = (barTotal - visibleUsed).clamp(0, barTotal).toInt();
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
      (total, part) => total + (_parts[part.key] ?? 0),
    );
    final double partScale = partsSum > 0 && visibleUsed > 0
        ? visibleUsed / partsSum
        : 0.0;
    final List<SegmentedTokenBarSegment> barSegments =
        <SegmentedTokenBarSegment>[];
    if (partScale > 0) {
      for (final part in order) {
        final int rawTokens = _parts[part.key] ?? 0;
        if (rawTokens <= 0) continue;
        barSegments.add(
          SegmentedTokenBarSegment(
            tokens: (rawTokens * partScale).round().clamp(1, visibleUsed),
            color: part.color(theme),
          ),
        );
      }
    } else if (visibleUsed > 0) {
      barSegments.add(
        SegmentedTokenBarSegment(
          tokens: visibleUsed,
          color: theme.colorScheme.primary,
        ),
      );
    }
    if (remainCap > 0) {
      barSegments.add(
        SegmentedTokenBarSegment(
          tokens: remainCap,
          color: theme.colorScheme.surfaceContainerHighest,
        ),
      );
    }

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
                  totalTokens: barTotal,
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
  CodexStyleTokenUsageInfo? _cachedCodexUsageInfo;
  Timer? _pollTimer;
  StreamSubscription<String>? _ctxSub;
  Timer? _ctxDebounce;
  bool _refreshInFlight = false;
  String _activeModel = '';
  int? _activeModelContextTokens;
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
        if (_refreshInFlight) return;
        _refreshSnapshotOnly();
      });
    });
    // Fallback polling in case we miss a broadcast (keep overhead low).
    _pollTimer = Timer.periodic(const Duration(milliseconds: 5000), (_) {
      if (!mounted) return;
      if (_refreshInFlight) return;
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
    return Text(
      ChatContextSheet._loc(context, 'Token 状态', 'Token status'),
      style: titleStyle,
      maxLines: 1,
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
                      onPressed: _reload,
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
                        _conversationTokenUsageCard(
                          context,
                          s,
                          latestUsage: latestUsage,
                          usageInfo: _cachedCodexUsageInfo,
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        _trimEventsCard(context, trimEvents),
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

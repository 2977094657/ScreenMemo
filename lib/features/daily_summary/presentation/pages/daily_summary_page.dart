import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/features/daily_summary/application/daily_summary_service.dart';
import 'package:screen_memo/features/timeline/application/dynamic_entry_perf_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/features/ai/application/ai_chat_service.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/utils/app_ref_markdown.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/markdown_math.dart';

class DailySummaryPage extends StatefulWidget {
  final String dateKey; // YYYY-MM-DD
  const DailySummaryPage({super.key, required this.dateKey});

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  final DailySummaryService _svc = DailySummaryService.instance;
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  bool _loading = false;
  Map<String, dynamic>? _daily; // daily_summaries row
  Map<String, dynamic>? _sj; // parsed structured_json of daily
  MorningInsights? _morningInsights;
  bool _morningLoading = false;
  StreamSubscription<AIStreamEvent>? _streamSub;
  bool _streaming = false;
  String _streamingText = '';
  String? _error;
  bool _trackEntryPerf = true;
  bool _entryPerfFinished = false;
  bool _streamFirstTokenLogged = false;
  Map<String, Uint8List?> _appIconByPackage = <String, Uint8List?>{};
  Map<String, Uint8List?> _appIconByNameLower = <String, Uint8List?>{};
  Map<String, String> _appNameByPackage = <String, String>{};
  bool _appIconCacheLoaded = false;
  bool _appIconCacheLoading = false;

  @override
  void initState() {
    super.initState();
    DynamicEntryPerfService.instance.beginSession(
      source: 'DailySummaryPage.initState',
      detail: 'dateKey=${widget.dateKey}',
    );
    _markEntryPerf('daily.initState', detail: 'dateKey=${widget.dateKey}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markEntryPerf('daily.shell.firstFrame');
    });
    _load(initial: true);
    _warmAppIconCache();
    if (_shouldRenderMorningInsights) {
      _refreshMorningInsights();
    }
  }

  @override
  void dispose() {
    _finishEntryPerf('daily.dispose', detail: 'disposedBeforeComplete');
    _streamSub?.cancel();
    super.dispose();
  }

  void _markEntryPerf(String step, {String? detail}) {
    if (!_trackEntryPerf || _entryPerfFinished) return;
    DynamicEntryPerfService.instance.mark(step, detail: detail);
  }

  void _finishEntryPerf(String step, {String? detail}) {
    if (!_trackEntryPerf || _entryPerfFinished) return;
    _entryPerfFinished = true;
    _trackEntryPerf = false;
    DynamicEntryPerfService.instance.finish(step, detail: detail);
  }

  void _finishEntryPerfAfterFrame(String step, {String? detail}) {
    if (!_trackEntryPerf || _entryPerfFinished) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _finishEntryPerf(step, detail: detail);
    });
  }

  void _warmAppIconCache() {
    if (_appIconCacheLoaded || _appIconCacheLoading) return;
    _appIconCacheLoading = true;
    unawaited(() async {
      try {
        final cachedApps = await AppSelectionService.instance
            .getCachedAppInfoByPackage();
        var apps = await AppSelectionService.instance.getSelectedApps();
        if (apps.isEmpty && Platform.isAndroid) {
          apps = await AppSelectionService.instance.getAllInstalledApps();
        }

        final Map<String, Uint8List?> byPkg = <String, Uint8List?>{};
        final Map<String, Uint8List?> byName = <String, Uint8List?>{};
        final Map<String, String> nameByPkg = <String, String>{};
        for (final app in cachedApps.values) {
          final String pkg = app.packageName.trim();
          final String name = app.appName.trim();
          if (pkg.isNotEmpty) {
            byPkg[pkg] = app.icon;
            if (name.isNotEmpty) nameByPkg[pkg] = name;
          }
          final String nameKey = name.toLowerCase();
          if (nameKey.isNotEmpty) byName[nameKey] = app.icon;
        }
        for (final app in apps) {
          final String pkg = app.packageName.trim();
          final String name = app.appName.trim();
          if (pkg.isNotEmpty) {
            byPkg[pkg] = app.icon;
            if (name.isNotEmpty) nameByPkg[pkg] = name;
          }
          final String nameKey = name.toLowerCase();
          if (nameKey.isNotEmpty) byName[nameKey] = app.icon;
        }
        if (!mounted) return;
        setState(() {
          _appIconByPackage = byPkg;
          _appIconByNameLower = byName;
          _appNameByPackage = nameByPkg;
          _appIconCacheLoaded = true;
          _appIconCacheLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _appIconCacheLoaded = true;
          _appIconCacheLoading = false;
        });
      }
    }());
  }

  Future<void> _load({bool initial = false}) async {
    final Stopwatch loadSw = Stopwatch()..start();
    final String phase = initial ? 'initial' : 'reload';
    bool startStreaming = false;
    _markEntryPerf('daily.load.start', detail: 'phase=$phase');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Stopwatch dbSw = Stopwatch()..start();
      final Map<String, dynamic>? daily = await _db.getDailySummary(
        widget.dateKey,
      );
      _markEntryPerf(
        'daily.db.getDailySummary.done',
        detail:
            'phase=$phase ms=${dbSw.elapsedMilliseconds} hit=${daily != null}',
      );
      Map<String, dynamic>? sj;
      if (daily != null) {
        final String raw = (daily['structured_json'] as String?) ?? '';
        if (raw.isNotEmpty) {
          final Stopwatch decodeSw = Stopwatch()..start();
          try {
            final dynamic j = jsonDecode(raw);
            if (j is Map<String, dynamic>) sj = j;
          } catch (_) {}
          _markEntryPerf(
            'daily.structuredJson.decode.done',
            detail:
                'phase=$phase ms=${decodeSw.elapsedMilliseconds} rawLen=${raw.length} parsed=${sj != null}',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _daily = daily;
        _sj = sj;
        _error = null;
      });
      _markEntryPerf(
        daily != null ? 'daily.cache.hit' : 'daily.cache.miss',
        detail: 'phase=$phase ms=${loadSw.elapsedMilliseconds}',
      );
      startStreaming = initial && daily == null && !_streaming;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
      _markEntryPerf(
        'daily.load.error',
        detail: 'phase=$phase ms=${loadSw.elapsedMilliseconds} error=$e',
      );
    } finally {
      if (mounted && !startStreaming) {
        setState(() => _loading = false);
      }
    }
    if (startStreaming) {
      _markEntryPerf(
        'daily.stream.autostart',
        detail: 'phase=$phase ms=${loadSw.elapsedMilliseconds}',
      );
      await _startStreaming(showSuccessSnack: false);
      return;
    }

    if (_trackEntryPerf && !_entryPerfFinished) {
      final String step;
      if (_error != null) {
        step = 'daily.error.firstFrame';
      } else if (_daily != null) {
        step = 'daily.content.firstFrame';
      } else {
        step = 'daily.empty.firstFrame';
      }
      _finishEntryPerfAfterFrame(
        step,
        detail: 'phase=$phase ms=${loadSw.elapsedMilliseconds}',
      );
    }
  }

  Future<void> _generate({bool force = true}) async {
    if (_loading || _streaming) return;
    await _startStreaming(showSuccessSnack: true);
  }

  Future<void> _startStreaming({bool showSuccessSnack = true}) async {
    await _streamSub?.cancel();
    if (!mounted) return;
    _streamFirstTokenLogged = false;
    final Stopwatch streamSw = Stopwatch()..start();
    _markEntryPerf(
      'daily.stream.start',
      detail: 'dateKey=${widget.dateKey} showSnack=$showSuccessSnack',
    );
    setState(() {
      _streaming = true;
      _streamingText = '';
      _daily = null;
      _sj = null;
      _loading = false;
      _error = null;
    });

    bool hadError = false;
    try {
      final Stopwatch sessionSw = Stopwatch()..start();
      final AIStreamingSession? session = await _svc.streamGenerateForDate(
        widget.dateKey,
      );
      _markEntryPerf(
        'daily.stream.session.ready',
        detail:
            'ms=${sessionSw.elapsedMilliseconds} hasSession=${session != null}',
      );
      if (session == null) {
        await _load(initial: false);
        if (showSuccessSnack && mounted) {
          UINotifier.success(
            context,
            AppLocalizations.of(context).generateSuccess,
          );
        }
        return;
      }

      _streamSub = session.stream.listen(
        (AIStreamEvent event) {
          if (!mounted) return;
          if (event.kind == 'content' && event.data.isNotEmpty) {
            if (!_streamFirstTokenLogged) {
              _streamFirstTokenLogged = true;
              _markEntryPerf(
                'daily.stream.firstToken',
                detail:
                    'ms=${streamSw.elapsedMilliseconds} chunkChars=${event.data.length}',
              );
            }
            setState(() {
              _streamingText += event.data;
            });
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          hadError = true;
          _markEntryPerf(
            'daily.stream.error',
            detail: 'ms=${streamSw.elapsedMilliseconds} error=$error',
          );
          if (!mounted) return;
          UINotifier.error(
            context,
            AppLocalizations.of(context).generateFailed,
          );
        },
      );

      await session.completed;
      _markEntryPerf(
        'daily.stream.completed',
        detail: 'ms=${streamSw.elapsedMilliseconds}',
      );
      if (hadError) return;

      await _load(initial: false);
      if (showSuccessSnack && mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).generateSuccess,
        );
      }
    } catch (_) {
      _markEntryPerf(
        'daily.stream.catch',
        detail: 'ms=${streamSw.elapsedMilliseconds}',
      );
      if (!mounted) return;
      if (!hadError) {
        UINotifier.error(context, AppLocalizations.of(context).generateFailed);
      }
    } finally {
      await _streamSub?.cancel();
      _streamSub = null;
      if (mounted) {
        setState(() {
          _streaming = false;
          _streamingText = '';
          _loading = false;
        });
      }
      if (hadError) {
        _finishEntryPerfAfterFrame(
          'daily.stream.error.firstFrame',
          detail: 'ms=${streamSw.elapsedMilliseconds}',
        );
      }
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}';
    return todayKey == widget.dateKey;
  }

  bool get _shouldRenderMorningInsights => false;

  Future<void> _refreshMorningInsights({bool regenerate = false}) async {
    if (!_shouldRenderMorningInsights) return;
    setState(() => _morningLoading = true);
    try {
      final MorningInsights? insights = regenerate
          ? await _svc.generateMorningInsights(widget.dateKey)
          : await _svc.loadMorningInsights(widget.dateKey);
      if (!mounted) return;
      if (insights != null || !regenerate) {
        setState(() => _morningInsights = insights);
      }
      if (regenerate) {
        UINotifier.info(
          context,
          insights != null
              ? AppLocalizations.of(context).homeMorningTipsUpdated
              : AppLocalizations.of(context).homeMorningTipsGenerateFailed,
        );
      }
    } catch (_) {
      if (!mounted) return;
      if (regenerate) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).homeMorningTipsGenerateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _morningLoading = false);
    }
  }

  Widget _buildMorningInsightsSection() {
    if (!_shouldRenderMorningInsights) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final MorningInsights? insights = _morningInsights;
    final bool allowRegenerate = _isToday;
    final String raw = insights?.rawResponse?.trim() ?? '';
    final bool hasRaw = raw.isNotEmpty;
    final bool hasParsedTips = insights?.tips.isNotEmpty ?? false;

    if (_morningLoading && insights == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing4,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Text(
                l10n.homeMorningTipsLoading,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    if (insights == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
        padding: const EdgeInsets.all(AppTheme.spacing4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeMorningTipsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(l10n.homeMorningTipsEmpty, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppTheme.spacing3),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: (!_morningLoading && allowRegenerate)
                    ? () => _refreshMorningInsights(regenerate: true)
                    : null,
                icon: const Icon(Icons.refresh_outlined, size: 18),
                label: Text(l10n.actionRegenerate),
              ),
            ),
          ],
        ),
      );
    }

    final tips = insights.tips;
    final List<Widget> tipWidgets = <Widget>[];
    if (hasParsedTips) {
      for (int i = 0; i < tips.length; i++) {
        tipWidgets.add(
          _buildMorningEntryItem(theme: theme, tip: tips[i], index: i),
        );
        if (i != tips.length - 1) {
          tipWidgets.add(const SizedBox(height: AppTheme.spacing3));
          tipWidgets.add(
            Divider(
              height: AppTheme.spacing4,
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
          );
          tipWidgets.add(const SizedBox(height: AppTheme.spacing2));
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                hasParsedTips
                    ? '${l10n.homeMorningTipsTitle} · ${tips.length}'
                    : l10n.homeMorningTipsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: l10n.actionRegenerate,
                onPressed: (!_morningLoading && allowRegenerate)
                    ? () => _refreshMorningInsights(regenerate: true)
                    : null,
                icon: const Icon(Icons.refresh_outlined),
              ),
            ],
          ),
          if (hasRaw)
            Padding(
              padding: const EdgeInsets.only(
                top: AppTheme.spacing3,
                bottom: AppTheme.spacing3,
              ),
              child: _buildMorningRawBlock(theme: theme, raw: raw),
            ),
          if (_morningLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing3),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppTheme.spacing2),
                  Text(
                    l10n.homeMorningTipsLoading,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (hasParsedTips) ...[
            const SizedBox(height: AppTheme.spacing2),
            ...tipWidgets,
          ] else ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(l10n.homeMorningTipsEmpty, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }

  Widget _buildMorningRawBlock({
    required ThemeData theme,
    required String raw,
  }) {
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.homeMorningTipsRawTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: raw));
                  if (!mounted) return;
                  UINotifier.success(context, l10n.articleCopySuccess);
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(l10n.actionCopy),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    raw,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.3,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMorningEntryItem({
    required ThemeData theme,
    required MorningInsightEntry tip,
    required int index,
  }) {
    final cs = theme.colorScheme;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurface,
      height: 1.4,
    );
    final secondaryStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
      height: 1.4,
    );

    final List<Widget> children = <Widget>[
      Text(
        AppLocalizations.of(
          context,
        ).homeMorningTipNumberedTitle(index + 1, tip.displayTitle),
        style: titleStyle,
      ),
    ];

    if (tip.hasSummary) {
      children.add(const SizedBox(height: AppTheme.spacing1));
      children.add(Text(tip.summary!, style: secondaryStyle));
    }

    if (tip.hasActions) {
      children.add(const SizedBox(height: AppTheme.spacing1));
      for (final action in tip.actions) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacing2),
                Expanded(child: Text(action, style: bodyStyle)),
              ],
            ),
          ),
        );
      }
      // Remove trailing spacing
      if (children.isNotEmpty && children.last is Padding) {
        children.removeLast();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _extractDailySummaryText() {
    // 优先 overall_summary（from structured_json），否则用 output_text
    final sj = _sj;
    if (sj != null) {
      final v = sj['overall_summary'];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final raw = (_daily?['output_text'] as String?)?.trim() ?? '';
    return raw.toLowerCase() == 'null' ? '' : raw;
  }

  // 规范 Markdown 段落与小标题：为“## …”以及以“**…**:”/“**…**：”开头的行
  // 自动补充必要的空行，以确保它们作为独立段落/小节渲染
  String _fixMarkdownLayout(String input) {
    if (input.trim().isEmpty) return input;
    // 将字面 "\n" 转换为真实换行，将字面 "\"" 还原为双引号，统一换行符
    final pre = normalizeCodeWrappedAppRefs(input)
        .replaceAll('\\r\\n', '\n')
        .replaceAll('\\r', '\n')
        .replaceAll('\\n', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\\"', '"');

    final lines = pre.split('\n');
    final out = <String>[];
    bool lastWasBlank = true;
    final headingRe = RegExp(r'^\s{0,3}#{1,6}\s');
    final boldSubtitleRe = RegExp(r'^\s*\*\*[^*\n]+\*\*[:：]');
    final listStartRe = RegExp(r'^\s*-\s+');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimRight();
      final isHeading = headingRe.hasMatch(trimmed);
      final isBoldSubtitle = boldSubtitleRe.hasMatch(trimmed);
      final isListStart = listStartRe.hasMatch(trimmed);

      // 确保在小节/标题/列表前有一个空行
      if ((isHeading || isBoldSubtitle || isListStart) &&
          !lastWasBlank &&
          out.isNotEmpty &&
          out.last.trim().isNotEmpty) {
        out.add('');
        lastWasBlank = true;
      }

      out.add(line);

      // 确保标题行后有空行（若下一行非空）
      if (isHeading) {
        final next = (i + 1 < lines.length) ? lines[i + 1] : null;
        if (next != null && next.trim().isNotEmpty) {
          out.add('');
          lastWasBlank = true;
          continue;
        }
      }

      lastWasBlank = line.trim().isEmpty;
    }

    // 规范连续空行（最多保留一行）
    final normalized = <String>[];
    for (final l in out) {
      if (l.trim().isEmpty) {
        if (normalized.isEmpty || normalized.last.trim().isEmpty) {
          // 若上一个也是空行则跳过，确保只保留一个
          if (normalized.isEmpty) normalized.add('');
        } else {
          normalized.add('');
        }
      } else {
        normalized.add(l);
      }
    }
    return normalized.join('\n');
  }

  MarkdownMathConfig _summaryMarkdownConfig(ThemeData theme) {
    return MarkdownMathConfig(
      inlineTextStyle: theme.textTheme.bodyMedium,
      blockTextStyle: theme.textTheme.bodyMedium,
      appIconByPackage: _appIconByPackage,
      appIconByNameLower: _appIconByNameLower,
      appNameByPackage: _appNameByPackage,
    );
  }

  Widget _buildSummaryMarkdown(
    BuildContext context,
    String markdown, {
    bool softLineBreak = false,
  }) {
    final ThemeData theme = Theme.of(context);
    final MarkdownMathConfig config = _summaryMarkdownConfig(theme);
    return MarkdownBody(
      data: preprocessForChatMarkdown(markdown),
      builders: config.builders,
      blockSyntaxes: config.blockSyntaxes,
      inlineSyntaxes: config.inlineSyntaxes,
      softLineBreak: softLineBreak,
      styleSheet: _summaryMarkdownStyle(theme),
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = widget.dateKey;
    final l10n = AppLocalizations.of(context);
    final title = l10n.dailySummaryTitle(dateKey);
    final md = _fixMarkdownLayout(_extractDailySummaryText());

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        title: Text(title),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).actionCopy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: (_loading || _streaming)
                ? null
                : () async {
                    final copySuccess = AppLocalizations.of(
                      context,
                    ).copySuccess;
                    final text = _extractDailySummaryText().trim();
                    if (text.isEmpty) return;
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    UINotifier.success(this.context, copySuccess);
                  },
          ),
          IconButton(
            tooltip: _daily == null
                ? AppLocalizations.of(context).actionGenerate
                : AppLocalizations.of(context).actionRegenerate,
            icon: (_loading || _streaming)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
            onPressed: (_loading || _streaming)
                ? null
                : () => _generate(force: true),
          ),
        ],
      ),
      body: _streaming
          ? _buildStreamingView()
          : _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
          ? _buildReadingShell(
              child: UIErrorState(
                title: l10n.operationFailed,
                message: _error!,
                actionLabel: l10n.actionRetry,
                onAction: _load,
                padding: EdgeInsets.zero,
              ),
            )
          : md.isEmpty
          ? _buildEmptySummaryPlaceholder()
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_shouldRenderMorningInsights && _isToday)
                    _buildMorningInsightsSection(),
                  _buildSummaryMarkdown(context, md),
                ],
              ),
            ),
    );
  }

  Widget _buildReadingShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.spacing4,
      vertical: AppTheme.spacing3,
    ),
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0;
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStreamingView() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    final String normalized = _fixMarkdownLayout(_streamingText);
    final bool hasContent = normalized.trim().isNotEmpty;
    return _buildReadingShell(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: cs.outlineVariant, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.dailySummaryGeneratingTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.dailySummaryGeneratingHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasContent) ...[
            const SizedBox(height: AppTheme.spacing3),
            _buildSummaryMarkdown(context, normalized, softLineBreak: true),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptySummaryPlaceholder() {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacing8),
      child: UIEmptyState(
        icon: Icons.event_note_outlined,
        title: AppLocalizations.of(context).noDailySummaryToday,
        actionLabel: AppLocalizations.of(context).generateDailySummary,
        onAction: () => _generate(force: true),
        padding: EdgeInsets.zero,
      ),
    );
  }

  MarkdownStyleSheet _summaryMarkdownStyle(ThemeData theme) {
    return MarkdownStyleSheet.fromTheme(
      theme,
    ).copyWith(p: theme.textTheme.bodyMedium);
  }
}

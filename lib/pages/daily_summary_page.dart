import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/daily_summary_service.dart';
import '../services/screenshot_database.dart';
import '../services/ai_chat_service.dart';
import '../theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    if (_shouldRenderMorningInsights) {
      _refreshMorningInsights();
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    bool startStreaming = false;
    setState(() => _loading = true);
    try {
      final Map<String, dynamic>? daily =
          await _db.getDailySummary(widget.dateKey);
      Map<String, dynamic>? sj;
      if (daily != null) {
        final String raw = (daily['structured_json'] as String?) ?? '';
        if (raw.isNotEmpty) {
          try {
            final dynamic j = jsonDecode(raw);
            if (j is Map<String, dynamic>) sj = j;
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _daily = daily;
        _sj = sj;
      });
      startStreaming = initial && daily == null && !_streaming;
    } finally {
      if (!mounted) return;
      if (!startStreaming) {
        setState(() => _loading = false);
      }
    }
    if (startStreaming) {
      await _startStreaming(showSuccessSnack: false);
    }
  }

  Future<void> _generate({bool force = true}) async {
    if (_loading || _streaming) return;
    await _startStreaming(showSuccessSnack: true);
  }

  Future<void> _startStreaming({bool showSuccessSnack = true}) async {
    await _streamSub?.cancel();
    if (!mounted) return;
    setState(() {
      _streaming = true;
      _streamingText = '';
      _daily = null;
      _sj = null;
      _loading = false;
    });

    bool hadError = false;
    try {
      final AIStreamingSession? session =
          await _svc.streamGenerateForDate(widget.dateKey);
      if (session == null) {
        await _load(initial: false);
        if (showSuccessSnack && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).generateSuccess),
            ),
          );
        }
        return;
      }

      _streamSub = session.stream.listen(
        (AIStreamEvent event) {
          if (!mounted) return;
          if (event.kind == 'content' && event.data.isNotEmpty) {
            setState(() {
              _streamingText += event.data;
            });
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          hadError = true;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).generateFailed,
              ),
            ),
          );
        },
      );

      await session.completed;
      if (hadError) return;

      await _load(initial: false);
      if (showSuccessSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).generateSuccess),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      if (!hadError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).generateFailed),
          ),
        );
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
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final todayKey = '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(insights != null ? '晨间提示已更新' : '晨间提示生成失败')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      if (regenerate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('晨间提示生成失败')),
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
          color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
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
          color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
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
            Text(
              l10n.homeMorningTipsEmpty,
              style: theme.textTheme.bodyMedium,
            ),
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
        tipWidgets.add(_buildMorningEntryItem(
          theme: theme,
          tip: tips[i],
          index: i,
        ));
        if (i != tips.length - 1) {
          tipWidgets.add(const SizedBox(height: AppTheme.spacing3));
          tipWidgets.add(Divider(
            height: AppTheme.spacing4,
            color: theme.dividerColor.withOpacity(0.4),
          ));
          tipWidgets.add(const SizedBox(height: AppTheme.spacing2));
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
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
            Text(
              l10n.homeMorningTipsEmpty,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMorningRawBlock({required ThemeData theme, required String raw}) {
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.surfaceVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${l10n.homeMorningTipsTitle} RAW',
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.articleCopySuccess)),
                  );
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
      Text('${index + 1}. ${tip.displayTitle}', style: titleStyle),
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
    final pre = input
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
      if ((isHeading || isBoldSubtitle || isListStart) && !lastWasBlank && out.isNotEmpty && out.last.trim().isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final dateKey = widget.dateKey;
    final title = AppLocalizations.of(context).dailySummaryTitle(dateKey);
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
                    final text = _extractDailySummaryText().trim();
                    if (text.isEmpty) return;
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(context).copySuccess)),
                    );
                  },
          ),
          IconButton(
            tooltip: _daily == null
                ? AppLocalizations.of(context).actionGenerate
                : AppLocalizations.of(context).actionRegenerate,
            icon: (_loading || _streaming)
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_outlined),
            onPressed: (_loading || _streaming) ? null : () => _generate(force: true),
          ),
        ],
      ),
      body: _streaming
          ? _buildStreamingView()
          : _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : LayoutBuilder(
              builder: (context, constraints) {
                final double minHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0;
                return SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                        vertical: AppTheme.spacing3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_shouldRenderMorningInsights && _isToday)
                            _buildMorningInsightsSection(),
                          if (md.isEmpty)
                            _buildEmptySummaryPlaceholder()
                          else
                            MarkdownBody(
                              data: md,
                              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                p: Theme.of(context).textTheme.bodyMedium,
                              ),
                              onTapLink: (text, href, title) async {
                                if (href == null) return;
                                final uri = Uri.tryParse(href);
                                if (uri != null) {
                                  try {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } catch (_) {}
                                }
                              },
                            ),
                          const SizedBox(height: AppTheme.spacing4),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStreamingView() {
    final theme = Theme.of(context);
    final String normalized = _fixMarkdownLayout(_streamingText);
    final bool hasContent = normalized.trim().isNotEmpty;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0;
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing3,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    Text(
                      '正在生成每日总结…',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    if (hasContent)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: MarkdownBody(
                          data: normalized,
                          softLineBreak: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: theme.textTheme.bodyMedium,
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
                        ),
                      )
                    else
                      Text(
                        '模型正在思考，请稍候…',
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptySummaryPlaceholder() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacing6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.event_note_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(AppLocalizations.of(context).noDailySummaryToday),
          const SizedBox(height: AppTheme.spacing3),
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              onPressed: () => _generate(force: true),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(AppLocalizations.of(context).generateDailySummary),
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/daily_summary_service.dart';
import '../services/screenshot_database.dart';
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

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    if (_isToday) {
      _refreshMorningInsights();
    }
  }

  Future<void> _load({bool initial = false}) async {
    setState(() => _loading = true);
    try {
      Map<String, dynamic>? daily = await _db.getDailySummary(widget.dateKey);
      Map<String, dynamic>? sj;
      if (daily != null) {
        final raw = (daily['structured_json'] as String?) ?? '';
        if (raw.isNotEmpty) {
          try {
            final j = jsonDecode(raw);
            if (j is Map<String, dynamic>) sj = j;
          } catch (_) {}
        }
      }

      // 若为首次进入且当前无记录，则自动触发一次生成，避免用户长时间等待无内容
      if (initial && daily == null) {
        try {
          await _svc.generateForDate(widget.dateKey);
        } catch (_) {}
        // 生成完成后重新读取
        daily = await _db.getDailySummary(widget.dateKey);
        sj = null;
        if (daily != null) {
          final raw2 = (daily['structured_json'] as String?) ?? '';
          if (raw2.isNotEmpty) {
            try {
              final j2 = jsonDecode(raw2);
              if (j2 is Map<String, dynamic>) sj = j2;
            } catch (_) {}
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _daily = daily;
        _sj = sj;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate({bool force = true}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _svc.generateForDate(widget.dateKey);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).generateSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).generateFailed)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final todayKey = '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}';
    return todayKey == widget.dateKey;
  }

  Future<void> _refreshMorningInsights({bool regenerate = false}) async {
    if (!_isToday) return;
    setState(() => _morningLoading = true);
    try {
      final MorningInsights? insights = regenerate
          ? await _svc.generateMorningInsights(widget.dateKey)
          : await _svc.loadMorningInsights(widget.dateKey);
      if (!mounted) return;
      final bool success = insights != null && insights.tips.isNotEmpty;
      if (success) {
        setState(() => _morningInsights = insights);
      } else if (!regenerate) {
        setState(() => _morningInsights = null);
      }
      if (regenerate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '晨间提示已更新' : '晨间提示生成失败')),
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
    if (!_isToday) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final MorningInsights? insights = _morningInsights;

    if (_morningLoading && (insights == null || insights.tips.isEmpty)) {
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

    if (insights == null || insights.tips.isEmpty) {
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
                onPressed: _morningLoading
                    ? null
                    : () => _refreshMorningInsights(regenerate: true),
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
                '${l10n.homeMorningTipsTitle} · ${tips.length}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: l10n.actionRegenerate,
                onPressed: _morningLoading
                    ? null
                    : () => _refreshMorningInsights(regenerate: true),
                icon: const Icon(Icons.refresh_outlined),
              ),
            ],
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
          const SizedBox(height: AppTheme.spacing2),
          ...tipWidgets,
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
            onPressed: _loading
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
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_outlined),
            onPressed: _loading ? null : () => _generate(force: true),
          ),
        ],
      ),
      body: _loading
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
                          if (_isToday) _buildMorningInsightsSection(),
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
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

  @override
  void initState() {
    super.initState();
    _load(initial: true);
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
          : md.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          size: 56,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
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
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing3),
                  child: MarkdownBody(
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
                ),
    );
  }
}
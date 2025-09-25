import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
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
      final daily = await _db.getDailySummary(widget.dateKey);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generate failed')));
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
    final lines = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final out = <String>[];
    bool lastWasBlank = true;
    final headingRe = RegExp(r'^\s{0,3}#{1,6}\s');
    final boldSubtitleRe = RegExp(r'^\s*\*\*[^*\n]+\*\*[:：]');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimRight();
      final isHeading = headingRe.hasMatch(trimmed);
      final isBoldSubtitle = boldSubtitleRe.hasMatch(trimmed);

      // 确保在小节/标题前有一个空行
      if ((isHeading || isBoldSubtitle) && !lastWasBlank && out.isNotEmpty && out.last.trim().isNotEmpty) {
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
          normalized.add('');
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
    final title = '每日总结 $dateKey';
    final md = _fixMarkdownLayout(_extractDailySummaryText());

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '复制',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _loading
                ? null
                : () async {
                    final text = _extractDailySummaryText().trim();
                    if (text.isEmpty) return;
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
                  },
          ),
          IconButton(
            tooltip: _daily == null ? '生成' : '重生成',
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
                        const Text('暂无今日总结'),
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
                            label: const Text('生成今日总结'),
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
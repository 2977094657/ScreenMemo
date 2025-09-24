import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
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
  List<Map<String, dynamic>> _segments = const <Map<String, dynamic>>[];

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
      final segs = await _svc.getSegmentsForDay(widget.dateKey);
      if (!mounted) return;
      setState(() {
        _daily = daily;
        _sj = sj;
        _segments = segs;
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

  List<Map<String, String>> _extractDailyTimeline() {
    // 优先从每日 structured_json.timeline 提取
    final sj = _sj;
    final out = <Map<String, String>>[];
    if (sj != null) {
      final tl = sj['timeline'];
      if (tl is List) {
        for (final it in tl) {
          if (it is Map) {
            final time = (it['time'] ?? '').toString().trim();
            final summary = (it['summary'] ?? '').toString().trim();
            if (time.isNotEmpty || summary.isNotEmpty) {
              out.add({'time': time, 'summary': summary});
            }
          }
        }
      }
    }
    if (out.isNotEmpty) return out;

    // 回退：从当天段落拼装
    for (final seg in _segments) {
      final start = _fmtHms((seg['start_time'] as int?) ?? 0);
      final end = _fmtHms((seg['end_time'] as int?) ?? 0);
      final sjRaw = (seg['structured_json'] as String?) ?? '';
      String summary = '';
      if (sjRaw.isNotEmpty) {
        try {
          final j = jsonDecode(sjRaw);
          if (j is Map) {
            // 先看 timeline 第一条 summary
            final tl = j['timeline'];
            if (tl is List && tl.isNotEmpty) {
              final first = tl.first;
              if (first is Map && first['summary'] is String) {
                summary = (first['summary'] as String).trim();
              }
            }
            // 不行则退回 overall_summary 的第一句
            if (summary.isEmpty && j['overall_summary'] is String) {
              summary = _firstSentence((j['overall_summary'] as String).trim());
            }
          }
        } catch (_) {}
      }
      if (summary.isEmpty) {
        final raw = (seg['output_text'] as String?)?.trim() ?? '';
        summary = _firstSentence(raw);
      }
      if (summary.isNotEmpty) {
        out.add({'time': '$start-$end', 'summary': summary});
      }
    }
    return out;
  }

  String _firstSentence(String s) {
    if (s.isEmpty) return s;
    final idx = s.indexOf(RegExp(r'[。.!?！？]'));
    if (idx > 0) return s.substring(0, idx + 1);
    return s.length > 120 ? (s.substring(0, 120) + '…') : s;
  }

  String _fmtHms(int ms) {
    if (ms <= 0) return '--:--:--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = widget.dateKey;
    final title = '每日总结 $dateKey';
    final md = _extractDailySummaryText();
    final timeline = _extractDailyTimeline();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        title: Text(title),
        actions: [
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
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing3),
              children: [
                // 总结卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: md.isEmpty
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('暂无今日总结'),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 36,
                                child: FilledButton.icon(
                                  onPressed: () => _generate(force: true),
                                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                                  label: const Text('生成今日总结'),
                                ),
                              ),
                            ],
                          )
                        : MarkdownBody(
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
                ),
                const SizedBox(height: 12),
                // 时间线
                Row(
                  children: [
                    const Text('时间线', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text('(${timeline.length})', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 8),
                if (timeline.isEmpty)
                  const Text('暂无'),
                if (timeline.isNotEmpty)
                  ...timeline.map((e) {
                    final time = e['time'] ?? '';
                    final summary = e['summary'] ?? '';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule, size: 18),
                      title: Text(summary),
                      subtitle: time.isEmpty ? null : Text(time),
                    );
                  }).toList(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
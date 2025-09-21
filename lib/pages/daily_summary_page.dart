import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_theme.dart';
import '../services/daily_summary_service.dart';

class DailySummaryPage extends StatefulWidget {
  const DailySummaryPage({super.key});

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  bool _inited = false;
  Future<DailySummaryResult>? _future;
  late int _startMillis;
  late int _endMillis;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final s = args['dateStartMillis'] as int?;
      final e = args['dateEndMillis'] as int?;
      if (s != null && e != null && e >= s) {
        _startMillis = s;
        _endMillis = e;
      } else {
        final now = DateTime.now();
        _startMillis = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
        _endMillis = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;
      }
    } else {
      final now = DateTime.now();
      _startMillis = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      _endMillis = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;
    }

    _future = DailySummaryService.instance.compute(
      startMillis: _startMillis,
      endMillis: _endMillis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final int _titleStartMs = _inited ? _startMillis : DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).millisecondsSinceEpoch;
final day = DateTime.fromMillisecondsSinceEpoch(_titleStartMs);
    final title = '每日总结 ${day.month}月${day.day}日';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: FutureBuilder<DailySummaryResult>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final res = snap.data!;
          if (res.totalDurationMs <= 0 || res.appUsages.isEmpty) {
            return _buildEmpty();
          }
          return _buildContent(res);
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 42, color: Theme.of(context).hintColor),
            const SizedBox(height: AppTheme.spacing3),
            Text(
              'No data for today',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(DailySummaryResult res) {
    final totalFmt = DailySummaryService.formatHm(res.totalDurationMs);
    final dateLabel = _fmtDateRange(res.startMillis, res.endMillis);

    final topList = res.topApps(topN: 5);
    final colors = _palette();
    final colorByPkg = <String, Color>{};
    for (int i = 0; i < topList.length; i++) {
      colorByPkg[topList[i].packageName] = colors[i % colors.length];
    }

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      children: [
        _metricCard(
          title: '总使用时长',
          trailing: totalFmt,
          subtitle: dateLabel,
          icon: Icons.timer_outlined,
        ),
        const SizedBox(height: AppTheme.spacing4),

        // 饼图（应用占比）
        _card(
          title: '应用占比',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 220, child: _buildDonut(res, colorByPkg)),
              const SizedBox(height: AppTheme.spacing2),
              _legend(topList, colorByPkg, res),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacing4),

        // 小时堆叠柱
        _card(
          title: '小时分布（Top 应用堆叠）',
          child: SizedBox(height: 240, child: _buildStackedHours(res, colorByPkg, topList)),
        ),
        const SizedBox(height: AppTheme.spacing4),

        // 重要操作
        _card(
          title: '重要操作',
          child: _buildHighlights(res),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String trailing,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.onSecondaryContainer, size: 18),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTheme.spacing3),
          child,
        ],
      ),
    );
  }

  Widget _buildDonut(DailySummaryResult res, Map<String, Color> colorByPkg) {
    final total = res.totalDurationMs.toDouble();
    final top = res.topApps(topN: 5);
    double topSum = 0;
    final sections = <PieChartSectionData>[];

    for (final a in top) {
      topSum += a.durationMs;
      final p = (a.durationMs / total) * 100;
      sections.add(
        PieChartSectionData(
          color: colorByPkg[a.packageName]!,
          value: a.durationMs.toDouble(),
          title: '${p.toStringAsFixed(0)}%',
          radius: 70,
          titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }
    final other = total - topSum;
    if (other > 0) {
      sections.add(
        PieChartSectionData(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
          value: other,
          title: '${(other / total * 100).toStringAsFixed(0)}%',
          radius: 70,
          titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  Widget _legend(List<AppUsage> top, Map<String, Color> colorByPkg, DailySummaryResult res) {
    return Wrap(
      spacing: AppTheme.spacing3,
      runSpacing: AppTheme.spacing2,
      children: top.map((a) {
        final color = colorByPkg[a.packageName]!;
        final text = '${a.appName} • ${DailySummaryService.formatHm(a.durationMs)}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildStackedHours(DailySummaryResult res, Map<String, Color> colorByPkg, List<AppUsage> top) {
    // 仅对 Top 应用堆叠，其余记为 Other
    final topPkgs = top.map((e) => e.packageName).toList();
    final colors = colorByPkg;
    final groups = <BarChartGroupData>[];

    // 纵轴单位：分钟
    double maxY = 0;

    for (int h = 0; h < 24; h++) {
      final map = res.hourAppDurationsMs[h] ?? {};
      final double totalMin = map.values.fold<double>(0, (p, v) => p + v / 60000.0);
      if (totalMin > maxY) maxY = totalMin;

      // 计算堆叠片段
      final List<BarChartRodStackItem> stacks = [];
      double running = 0;

      // Top
      for (final pkg in topPkgs) {
        final ms = (map[pkg] ?? 0);
        final minVal = ms / 60000.0;
        if (minVal <= 0) continue;
        final from = running;
        final to = running + minVal;
        stacks.add(BarChartRodStackItem(from, to, colors[pkg] ?? Colors.blue));
        running = to;
      }

      // Other
      final int otherMs = map.entries
          .where((e) => !topPkgs.contains(e.key))
          .fold(0, (p, e) => p + e.value);
      final double otherMin = otherMs / 60000.0;
      if (otherMin > 0) {
        stacks.add(BarChartRodStackItem(running, running + otherMin, Theme.of(context).colorScheme.outline.withOpacity(0.5)));
      }

      groups.add(
        BarChartGroupData(
          x: h,
          barRods: [
            BarChartRodData(
              toY: totalMin,
              width: 10,
              rodStackItems: stacks,
              borderRadius: BorderRadius.zero,
            )
          ],
        ),
      );
    }

    maxY = (maxY < 10 ? 10 : maxY) * 1.2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: FlGridData(show: true, horizontalInterval: maxY / 4),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: (maxY / 4).ceilToDouble(), getTitlesWidget: (v, meta) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text('${v.toStringAsFixed(0)}m', style: Theme.of(context).textTheme.bodySmall),
              );
            }),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 3,
              getTitlesWidget: (v, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${v.toInt()}', style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: groups,
        groupsSpace: 6,
      ),
    );
  }

  Widget _buildHighlights(DailySummaryResult res) {
    final items = <Widget>[];

    // 最长专注段
    final lb = res.longestBlock();
    if (lb != null) {
      final s = DateTime.fromMillisecondsSinceEpoch(lb.startMs);
      final e = DateTime.fromMillisecondsSinceEpoch(lb.endMs);
      final dur = DailySummaryService.formatHm(lb.durationMs);
      items.add(_highlightRow(Icons.center_focus_strong, '最长专注', '${lb.appName} • $dur • ${_fmtHm(s)} - ${_fmtHm(e)}'));
    }

    // 高频切换
    items.add(_highlightRow(Icons.swap_horiz, '切换次数', '${res.switchCount} 次'));

    // 深夜使用
    if (res.deepNightDurationMs > 0) {
      items.add(_highlightRow(Icons.nightlight_round, '深夜使用', DailySummaryService.formatHm(res.deepNightDurationMs)));
    }

    // Top 应用
    final top = res.topApps(topN: 3);
    if (top.isNotEmpty) {
      final text = top.map((a) => '${a.appName}(${DailySummaryService.formatHm(a.durationMs)})').join(' · ');
      items.add(_highlightRow(Icons.apps, 'Top 应用', text));
    }

    // 里程碑：最早/最晚活跃
    if (res.firstActive != null && res.lastActive != null) {
      items.add(_highlightRow(Icons.schedule, '活跃时间', '${_fmtHm(res.firstActive!)} - ${_fmtHm(res.lastActive!)}'));
    }

    if (items.isEmpty) {
      return Text('No highlights', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor));
    }
    return Column(children: items);
  }

  Widget _highlightRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).hintColor),
          const SizedBox(width: AppTheme.spacing2),
          Text('$title：', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }

  String _fmtDateRange(int sMs, int eMs) {
    final s = DateTime.fromMillisecondsSinceEpoch(sMs);
    final e = DateTime.fromMillisecondsSinceEpoch(eMs);
    return '${s.month}月${s.day}日 ${_fmtHm(s)} ~ ${_fmtHm(e)}';
    }

  String _fmtHm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  List<Color> _palette() {
    return [
      const Color(0xFF4F46E5), // indigo-600
      const Color(0xFF22C55E), // green-500
      const Color(0xFFF59E0B), // amber-500
      const Color(0xFFEF4444), // red-500
      const Color(0xFF06B6D4), // cyan-500
      const Color(0xFF8B5CF6), // violet-500
      const Color(0xFF10B981), // emerald-500
    ];
  }
}
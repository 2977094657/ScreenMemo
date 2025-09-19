import 'package:flutter/material.dart';

/// 事件时间轴组件（竖向）
/// - 不依赖第三方库，纯 Flutter 绘制
/// - 提供三种样式：简洁、节点图标、按天分组
enum TimelineVariant { minimal, icon, grouped }

typedef SegmentTapCallback = void Function(Map<String, dynamic> seg);

class EventTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> segments;
  final TimelineVariant variant;
  final SegmentTapCallback onTapSegment;

  const EventTimeline({
    super.key,
    required this.segments,
    required this.variant,
    required this.onTapSegment,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    switch (variant) {
      case TimelineVariant.minimal:
        return _buildLinear(context, showIcon: false);
      case TimelineVariant.icon:
        return _buildLinear(context, showIcon: true);
      case TimelineVariant.grouped:
        return _buildGrouped(context);
    }
  }

  /// 线性样式：左侧竖线 + 节点 + 右侧卡片
  Widget _buildLinear(BuildContext context, {required bool showIcon}) {
    return Column(
      children: List.generate(segments.length, (i) {
        final seg = segments[i];
        final bool isFirst = i == 0;
        final bool isLast = i == segments.length - 1;
        final bool hasSummary = ((seg['has_summary'] as int?) == 1);
        final String status = (seg['status'] as String?) ?? '';
        final bool merged = (seg['merged_flag'] as int?) == 1;
        final Color accent = hasSummary ? Colors.green : Colors.grey;
        final IconData nodeIcon = hasSummary ? Icons.check_circle : Icons.radio_button_unchecked;
        return _TimelineTile(
          isFirst: isFirst,
          isLast: isLast,
          accent: accent,
          showIcon: showIcon,
          icon: nodeIcon,
          child: _SegmentCard(
            seg: seg,
            status: status,
            merged: merged,
            hasSummary: hasSummary,
            onTap: () => onTapSegment(seg),
          ),
        );
      }),
    );
  }

  /// 分组样式：按天分组的时间轴（未启用吸附，便于轻量接入）
  Widget _buildGrouped(BuildContext context) {
    // 按天分组：yyyy-MM-dd
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final seg in segments) {
      final int start = (seg['start_time'] as int?) ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(start);
      final String key = _dateKey(dt);
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(seg);
    }
    final List<String> keys = groups.keys.toList()..sort((a, b) => a.compareTo(b));
    final List<String> ordered = keys.reversed.toList();

    final List<Widget> children = [];
    for (final key in ordered) {
      final list = groups[key]!;
      children.add(_GroupHeader(dateLabel: key));
      for (int i = 0; i < list.length; i++) {
        final seg = list[i];
        final bool isFirstOfGroup = i == 0;
        final bool isLastOfGroup = i == list.length - 1;
        final bool hasSummary = ((seg['has_summary'] as int?) == 1);
        final String status = (seg['status'] as String?) ?? '';
        final bool merged = (seg['merged_flag'] as int?) == 1;
        final Color accent = hasSummary ? Colors.green : Colors.grey;
        final IconData nodeIcon = hasSummary ? Icons.check_circle : Icons.fiber_manual_record;
        children.add(_TimelineTile(
          isFirst: isFirstOfGroup,
          isLast: isLastOfGroup,
          accent: accent,
          showIcon: true,
          icon: nodeIcon,
          child: _SegmentCard(
            seg: seg,
            status: status,
            merged: merged,
            hasSummary: hasSummary,
            onTap: () => onTapSegment(seg),
          ),
        ));
      }
    }
    return Column(children: children);
  }

  String _dateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _TimelineTile extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final bool showIcon;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _TimelineTile({
    required this.isFirst,
    required this.isLast,
    required this.showIcon,
    required this.icon,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final Color lineColor = Theme.of(context).dividerColor.withOpacity(0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    painter: _GutterPainter(
                      drawTop: !isFirst,
                      drawBottom: !isLast,
                      lineColor: lineColor,
                    ),
                  ),
                  _Node(accent: accent, showIcon: showIcon, icon: icon),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  final bool drawTop;
  final bool drawBottom;
  final Color lineColor;

  _GutterPainter({required this.drawTop, required this.drawBottom, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = lineColor
      ..strokeWidth = 2;
    final double cx = size.width / 2;
    final double top = 0;
    final double bottom = size.height;
    final double cy = size.height / 2;
    const double gap = 6;
    if (drawTop) {
      canvas.drawLine(Offset(cx, top), Offset(cx, cy - gap), p);
    }
    if (drawBottom) {
      canvas.drawLine(Offset(cx, cy + gap), Offset(cx, bottom), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter oldDelegate) {
    return drawTop != oldDelegate.drawTop ||
        drawBottom != oldDelegate.drawBottom ||
        lineColor != oldDelegate.lineColor;
  }
}

class _Node extends StatelessWidget {
  final Color accent;
  final bool showIcon;
  final IconData icon;
  const _Node({required this.accent, required this.showIcon, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.3),
            blurRadius: 4,
          ),
        ],
      ),
      child: showIcon
          ? Center(child: Icon(icon, size: 12, color: Colors.white))
          : null,
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final Map<String, dynamic> seg;
  final String status;
  final bool merged;
  final bool hasSummary;
  final VoidCallback onTap;

  const _SegmentCard({
    required this.seg,
    required this.status,
    required this.merged,
    required this.hasSummary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final start = (seg['start_time'] as int?) ?? 0;
    final end = (seg['end_time'] as int?) ?? 0;
    final title = '${_fmtTime(start)} - ${_fmtTime(end)}';
    final String summaryText = hasSummary ? '已有总结' : '暂无总结';
    final Color badgeColor = merged ? Colors.orange : Colors.transparent;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      '状态：$status · $summaryText',
                      style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                    ),
                  ],
                ),
              ),
              if (merged)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('已合并', style: TextStyle(fontSize: 11, color: Colors.orange)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _GroupHeader extends StatelessWidget {
  final String dateLabel;
  const _GroupHeader({required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Text(dateLabel, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }
}
part of '../ai_settings_page.dart';

// Extracted widgets/helpers from ai_settings_page.dart (kept in same library via part).

class _ThinkingTimelineCard extends StatefulWidget {
  const _ThinkingTimelineCard({
    super.key,
    required this.createdAt,
    required this.finishedAt,
    required this.events,
    this.fallbackReasoning,
    this.autoCloseOnFinish = true,
  });

  final DateTime createdAt;
  final DateTime? finishedAt;
  final List<_ThinkingEvent> events;
  final String? fallbackReasoning;
  final bool autoCloseOnFinish;

  bool get isLoading => finishedAt == null;

  @override
  State<_ThinkingTimelineCard> createState() => _ThinkingTimelineCardState();
}

class _ThinkingTimelineCardState extends State<_ThinkingTimelineCard> {
  bool _expanded = true;
  Timer? _elapsedTimer;
  final ScrollController _fallbackScrollController = ScrollController();

  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (widget.isLoading) {
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.isLoading;
    _syncElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant _ThinkingTimelineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading != widget.isLoading) {
      _syncElapsedTimer();
    }
    if (oldWidget.isLoading && !widget.isLoading && widget.autoCloseOnFinish) {
      if (mounted) setState(() => _expanded = false);
    }
    if (!oldWidget.isLoading && widget.isLoading) {
      if (mounted) setState(() => _expanded = true);
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _fallbackScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final Color titleColor = _thinkingTextColor;
    final Color subtle = _thinkingTextColor;
    final String titleText = l10n.deepThinkingLabel;
    final String fallback = (widget.fallbackReasoning ?? '').trim();

    final Duration elapsed = (widget.finishedAt ?? DateTime.now()).difference(
      widget.createdAt,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Expanded(
                child: _Shimmer(
                  active: widget.isLoading,
                  baseColor: titleColor,
                  child: Text(
                    titleText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(elapsed),
                style: theme.textTheme.labelSmall?.copyWith(color: subtle),
              ),
              const SizedBox(width: 6),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: titleColor,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: AppTheme.spacing2),
          if (widget.events.isEmpty)
            if (fallback.isNotEmpty)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Scrollbar(
                  controller: _fallbackScrollController,
                  child: SingleChildScrollView(
                    controller: _fallbackScrollController,
                    physics: const ClampingScrollPhysics(),
                    child: SelectableText(
                      fallback,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtle,
                        fontFamily: 'monospace',
                        height: 1.20,
                      ),
                    ),
                  ),
                ),
              )
            else
              Text(
                widget.isLoading ? '…' : '',
                style: theme.textTheme.bodySmall?.copyWith(color: subtle),
              )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < widget.events.length; i++)
                  _buildEventRow(
                    context,
                    widget.events[i],
                    isLast: i == widget.events.length - 1,
                  ),
              ],
            ),
        ],
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    if (d.inMilliseconds < 1000) {
      final double secs = d.inMilliseconds / 1000.0;
      return '${secs.toStringAsFixed(1)}s';
    }
    final int totalSeconds = d.inSeconds.clamp(0, 24 * 3600);
    final int h = totalSeconds ~/ 3600;
    final int m = (totalSeconds % 3600) ~/ 60;
    final int s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildEventRow(
    BuildContext context,
    _ThinkingEvent e, {
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final Color titleColor = _thinkingTextColor;
    final Color subtitleColor = _thinkingTextColor;

    Widget title = Text(
      e.title,
      style: theme.textTheme.bodySmall?.copyWith(
        color: titleColor,
        fontWeight: FontWeight.w600,
      ),
    );
    title = _Shimmer(active: e.active, baseColor: titleColor, child: title);

    final List<Widget> right = <Widget>[title];
    final String sub = (e.subtitle ?? '').trim();
    if (sub.isNotEmpty) {
      right.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            sub,
            style: theme.textTheme.bodySmall?.copyWith(
              color: subtitleColor,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    if (e.type == _ThinkingEventType.tools && e.tools.isNotEmpty) {
      right.add(const SizedBox(height: 8));
      right.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final chip in e.tools) _buildToolChip(context, chip)],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: right,
      ),
    );
  }

  Widget _buildToolChip(BuildContext context, _ThinkingToolChip chip) {
    final theme = Theme.of(context);
    final bool isSearch = chip.toolName.startsWith('search_');
    final Color bg =
        (isSearch
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.secondaryContainer)
            .withOpacity(0.65);
    final Color fg = isSearch
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSecondaryContainer;

    final String summary = (chip.resultSummary ?? '').trim();
    final String label = summary.isEmpty
        ? chip.label
        : '${chip.label} · $summary';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: _Shimmer(
        active: chip.active,
        baseColor: fg,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// 滚动遮罩组件：当列表不在顶部或底部时显示白色渐变遮罩
class _ScrollMaskWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final Color maskColor;

  const _ScrollMaskWrapper({
    required this.child,
    required this.controller,
    this.maskColor = Colors.white,
  });

  @override
  State<_ScrollMaskWrapper> createState() => _ScrollMaskWrapperState();
}

class _ScrollMaskWrapperState extends State<_ScrollMaskWrapper> {
  bool _showTopMask = false;
  bool _showBottomMask = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateMasks);
    // 延迟检查初始状态，确保列表已渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateMasks();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateMasks);
    super.dispose();
  }

  void _updateMasks() {
    if (!widget.controller.hasClients) return;

    final position = widget.controller.position;
    final atTop = position.pixels <= 0;
    final atBottom = position.pixels >= position.maxScrollExtent;

    setState(() {
      _showTopMask = !atTop;
      _showBottomMask = !atBottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // 顶部遮罩
        if (_showTopMask)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 24,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.maskColor.withOpacity(0.9),
                      widget.maskColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // 底部遮罩
        if (_showBottomMask)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 24,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      widget.maskColor.withOpacity(0.9),
                      widget.maskColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// 流光边框效果组件（输入框边框流光 - Gemini AI 风格）
class _ShimmerBorder extends StatefulWidget {
  final Widget child;
  final bool active; // 是否显示流光动画
  const _ShimmerBorder({super.key, required this.child, this.active = false});

  @override
  State<_ShimmerBorder> createState() => _ShimmerBorderState();
}

class _ShimmerBorderState extends State<_ShimmerBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _kBorderRadius = 24.0;
  static const double _kBorderWidth =
      1.25; // 视觉宽度≈1.5（strokeWidth = 1.25 * 1.2）

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_ShimmerBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 根据 active 状态控制动画
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 普通状态的静态彩色渐变
    final staticGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        Color(0xFF4285F4), // Gemini 蓝
        Color(0xFF9B72F2), // 紫色
        Color(0xFFD946EF), // 品红
        Color(0xFFFF6B9D), // 粉红
        Color(0xFFFBBC04), // 金色
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    // 非激活态：不再包一层渐变容器，避免尺寸变化；仅返回 child
    if (!widget.active) return widget.child;

    // 流光动画边框（叠加高亮，不替换静态渐变）
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * 6.283185307179586; // 2π

        // 流光高亮：去掉灰色拖尾，仅保留彩色高亮，并以透明-彩色-透明的方式过渡
        final sweep = SweepGradient(
          center: Alignment.center,
          colors: const [
            Color(0x00FFFFFF), // 完全透明开始（透明白，避免黑色伪影）
            Color(0x00FFFFFF),
            Color(0xFF4285F4), // 蓝
            Color(0xFF9B72F2), // 紫
            Color(0xFFD946EF), // 品红
            Color(0xFFFF6B9D), // 粉
            Color(0xFFFBBC04), // 金
            Color(0x00FFFFFF), // 透明收尾（透明白）
            Color(0x00FFFFFF),
          ],
          stops: const [0.00, 0.30, 0.40, 0.50, 0.58, 0.66, 0.74, 0.85, 1.00],
          transform: GradientRotation(angle),
        );

        // 仅作为叠加层绘制流光高亮，不改变 child 尺寸
        return Stack(
          children: [
            // 底层直接是 child
            widget.child,
            // 仅裁剪到"边框环形区域"的流光叠加层
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RingSweepPainter(
                    gradient: sweep,
                    borderRadius: _kBorderRadius,
                    borderWidth: _kBorderWidth,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// 仅绘制在"边框环形区域"的流光高亮画笔
class _RingSweepPainter extends CustomPainter {
  final Gradient gradient;
  final double borderRadius;
  final double borderWidth;

  _RingSweepPainter({
    required this.gradient,
    required this.borderRadius,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 与 _ShimmerBorder 的圆角一致的外边界
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 画笔设置为描边，仅覆盖边框区域；2x 线宽让内侧可见宽度≈borderWidth
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth * 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path()..addRRect(outer);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RingSweepPainter oldDelegate) {
    return oldDelegate.gradient != gradient ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth;
  }
}

class _Shimmer extends StatelessWidget {
  final Widget child;
  final bool active;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration period;

  const _Shimmer({
    super.key,
    required this.child,
    required this.active,
    this.baseColor,
    this.highlightColor,
    this.period = const Duration(milliseconds: 2200),
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;

    final Color base =
        baseColor ??
        DefaultTextStyle.of(context).style.color ??
        _thinkingTextColor;
    final Color highlight = highlightColor ?? _thinkingShimmerHighlightColor;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      direction: ShimmerDirection.ltr,
      period: period,
      child: child,
    );
  }
}

MarkdownStyleSheet? _cachedMdStyle;
MarkdownStyleSheet _mdStyle(BuildContext context) {
  final s = _cachedMdStyle;
  if (s != null) return s;
  final ns = MarkdownStyleSheet.fromTheme(
    Theme.of(context),
  ).copyWith(p: Theme.of(context).textTheme.bodyMedium);
  _cachedMdStyle = ns;
  return ns;
}

// 自绘渐变 Icon，避免被主题色覆盖
class _GradientIconPainter extends CustomPainter {
  final List<Color> colors;
  final IconData icon;
  _GradientIconPainter({required this.colors, required this.icon});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size.height,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final offset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect)
      ..blendMode = BlendMode.srcIn;

    // 先绘制到图层，随后用渐变混合
    canvas.saveLayer(rect, Paint());
    textPainter.paint(canvas, offset);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GradientIconPainter oldDelegate) {
    return oldDelegate.colors != colors || oldDelegate.icon != icon;
  }
}

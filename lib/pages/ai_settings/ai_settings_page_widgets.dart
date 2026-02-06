part of '../ai_settings_page.dart';

// Extracted widgets/helpers from ai_settings_page.dart (kept in same library via part).

bool _isZhLocaleUi(BuildContext context) {
  try {
    return Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
  } catch (_) {
    return true;
  }
}

String _coarsenToolLabelForDisplay(String label) {
  String s = label.trim();
  if (s.isEmpty) return '';

  // Drop time parts: keep YYYY-MM-DD only.
  s = s.replaceAllMapped(
    RegExp(r'(\d{4}-\d{2}-\d{2})[ T]\d{2}:\d{2}(?::\d{2})?'),
    (m) => m.group(1) ?? m.group(0) ?? '',
  );

  // Collapse date ranges like "2026-01-18–2026-01-18" to a single date.
  s = s.replaceAllMapped(
    RegExp(r'(\d{4}-\d{2}-\d{2})\s*[–-]\s*(\d{4}-\d{2}-\d{2})'),
    (m) {
      final String a = (m.group(1) ?? '').trim();
      final String b = (m.group(2) ?? '').trim();
      if (a.isEmpty || b.isEmpty) return m.group(0) ?? '';
      return a == b ? a : '$a–$b';
    },
  );

  return s;
}

String _normalizeToolSummaryForDisplay(
  BuildContext context, {
  required String toolName,
  required String summary,
}) {
  String s = summary.trim();
  if (s.isEmpty) return '';
  if (!_isZhLocaleUi(context)) return s;

  // If it's already Chinese, keep it.
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(s)) return s;

  final String low = s.toLowerCase();
  if (low.startsWith('skipped')) return '已跳过';
  if (low == 'ok') return '完成';
  if (low == 'retrieved') return '已获取';
  if (low == 'no images') return '无图片';
  if (low.startsWith('error=')) {
    final int i = s.indexOf('=');
    return i >= 0 ? '错误：${s.substring(i + 1)}' : '错误';
  }

  // "found 1944 (page 3)" / "found 3"
  final Match? mFound = RegExp(
    r'found\s+(\d+)(?:\s*\(page\s+(\d+)\))?',
    caseSensitive: false,
  ).firstMatch(s);
  if (mFound != null) {
    final int a = int.tryParse(mFound.group(1) ?? '') ?? -1;
    final int b = int.tryParse(mFound.group(2) ?? '') ?? -1;
    if (a >= 0 && b >= 0 && a != b) return '找到 $a 个（本页 $b）';
    if (a >= 0) return '找到 $a 个';
  }

  // "returned 10"
  final Match? mReturned = RegExp(
    r'returned\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(s);
  if (mReturned != null) {
    final int c = int.tryParse(mReturned.group(1) ?? '') ?? -1;
    if (c >= 0) return '返回 $c 条';
  }

  // "loaded 3 (missing 1, skipped 2)" / "loaded 3"
  final Match? mLoaded = RegExp(
    r'loaded\s+(\d+)(?:\s*\(([^)]*)\))?',
    caseSensitive: false,
  ).firstMatch(s);
  if (mLoaded != null) {
    final int provided = int.tryParse(mLoaded.group(1) ?? '') ?? -1;
    if (provided >= 0) {
      final String head = '已加载 $provided 张';
      final String extrasRaw = (mLoaded.group(2) ?? '').trim();
      if (extrasRaw.isEmpty) return head;
      final List<String> extras = <String>[];
      final Match? mMissing = RegExp(
        r'missing\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(extrasRaw);
      final Match? mSkipped = RegExp(
        r'skipped\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(extrasRaw);
      final int missing = int.tryParse(mMissing?.group(1) ?? '') ?? 0;
      final int skipped = int.tryParse(mSkipped?.group(1) ?? '') ?? 0;
      if (missing > 0) extras.add('缺失 $missing');
      if (skipped > 0) extras.add('跳过 $skipped');
      return extras.isEmpty ? head : '$head（${extras.join('，')}）';
    }
  }

  // Legacy summaries from older versions:
  // - count=3 / count=3 total=1944
  final Match? mCount = RegExp(
    r'count=(\d+)(?:\s+total=(\d+))?',
    caseSensitive: false,
  ).firstMatch(s);
  if (mCount != null) {
    final int c = int.tryParse(mCount.group(1) ?? '') ?? -1;
    final int t = int.tryParse(mCount.group(2) ?? '') ?? -1;
    if (c >= 0 && t >= 0 && t != c) return '找到 $t 个（本页 $c）';
    if (c >= 0) return '找到 $c 个';
  }

  // - provided=5 missing=1 skipped=2
  final Match? mImgs = RegExp(
    r'provided=(\d+)\s+missing=(\d+)\s+skipped=(\d+)',
    caseSensitive: false,
  ).firstMatch(s);
  if (mImgs != null) {
    final int provided = int.tryParse(mImgs.group(1) ?? '') ?? 0;
    final int missing = int.tryParse(mImgs.group(2) ?? '') ?? 0;
    final int skipped = int.tryParse(mImgs.group(3) ?? '') ?? 0;
    if (provided <= 0 && missing <= 0 && skipped <= 0) return '无图片';
    final String head = '已加载 $provided 张';
    final List<String> extras = <String>[];
    if (missing > 0) extras.add('缺失 $missing');
    if (skipped > 0) extras.add('跳过 $skipped');
    return extras.isEmpty ? head : '$head（${extras.join('，')}）';
  }

  // - segment_id=123 count=10 / segment_id=123
  if (toolName == 'get_segment_result') return '已获取';
  if (toolName == 'get_segment_samples') {
    final Match? mSegCount = RegExp(
      r'count=(\d+)',
      caseSensitive: false,
    ).firstMatch(s);
    final int c = int.tryParse(mSegCount?.group(1) ?? '') ?? -1;
    if (c >= 0) return '返回 $c 条';
    return '返回';
  }

  return s;
}

String _toolChipTextForDisplay(BuildContext context, _ThinkingToolChip chip) {
  final String rawSummary = (chip.resultSummary ?? '').trim();
  final String summary = _normalizeToolSummaryForDisplay(
    context,
    toolName: chip.toolName,
    summary: rawSummary,
  );
  final String baseLabel = chip.label.trim().isEmpty
      ? chip.toolName
      : chip.label.trim();
  final String normalizedLabel = _coarsenToolLabelForDisplay(baseLabel);
  return summary.isEmpty ? normalizedLabel : '$normalizedLabel · $summary';
}

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
  Map<String, Uint8List?> _appIconByPackage = <String, Uint8List?>{};
  Map<String, Uint8List?> _appIconByNameLower = <String, Uint8List?>{};
  bool _appIconCacheLoaded = false;

  void _warmAppIconCache() {
    if (_appIconCacheLoaded) return;
    unawaited(() async {
      try {
        var apps = await AppSelectionService.instance.getSelectedApps();
        // Selected apps carry cached icons (no platform plugin call). If empty,
        // fall back to installed app scan on Android only.
        if (apps.isEmpty && Platform.isAndroid) {
          apps = await AppSelectionService.instance.getAllInstalledApps();
        }

        final Map<String, Uint8List?> byPkg = <String, Uint8List?>{};
        final Map<String, Uint8List?> byName = <String, Uint8List?>{};
        for (final a in apps) {
          final String pkg = a.packageName.trim();
          if (pkg.isNotEmpty) byPkg[pkg] = a.icon;
          final String nameKey = a.appName.trim().toLowerCase();
          if (nameKey.isNotEmpty) byName[nameKey] = a.icon;
        }
        if (!mounted) return;
        setState(() {
          _appIconByPackage = byPkg;
          _appIconByNameLower = byName;
          _appIconCacheLoaded = true;
        });
      } catch (_) {
        // Best-effort; tool chips will fall back to generic icons.
        if (!mounted) return;
        setState(() => _appIconCacheLoaded = true);
      }
    }());
  }

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
    _warmAppIconCache();
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
    final String titleText = widget.isLoading
        ? l10n.thinkingInProgress
        : l10n.deepThinkingLabel;
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
          if (widget.events.isNotEmpty)
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
          if (fallback.isNotEmpty) ...[
            if (widget.events.isNotEmpty)
              const SizedBox(height: AppTheme.spacing2),
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
            ),
          ],
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
    // Only shimmer while the block is still loading; stale persisted `active`
    // flags (e.g. after background completion) should not keep shimmering.
    title = _Shimmer(
      active: widget.isLoading && e.active,
      baseColor: titleColor,
      child: title,
    );

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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < e.tools.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == e.tools.length - 1 ? 0 : 6,
                ),
                child: _buildToolChip(context, e.tools[i]),
              ),
          ],
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

  IconData _toolIconFor(String toolName) {
    switch (toolName) {
      case 'get_images':
        return Icons.image_rounded;
      case 'search_screenshots_ocr':
        return Icons.document_scanner_rounded;
      case 'search_ai_image_meta':
        return Icons.image_search_rounded;
      case 'search_segments':
        return Icons.manage_search_rounded;
      case 'search_segments_ocr':
        return Icons.text_snippet_rounded;
      case 'get_segment_result':
        return Icons.description_rounded;
      case 'get_segment_samples':
        return Icons.collections_rounded;
      default:
        if (toolName.startsWith('search_')) return Icons.search_rounded;
        if (toolName.startsWith('get_')) return Icons.download_rounded;
        return Icons.build_circle_outlined;
    }
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

    final String label = _toolChipTextForDisplay(context, chip);
    final IconData icon = _toolIconFor(chip.toolName);
    final Widget leading = _buildToolChipLeading(
      context,
      theme: theme,
      chip: chip,
      fg: fg,
      fallbackIcon: icon,
      isSearch: isSearch,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: _Shimmer(
        active: widget.isLoading && chip.active,
        baseColor: fg,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: leading),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                softWrap: true,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolChipLeading(
    BuildContext context, {
    required ThemeData theme,
    required _ThinkingToolChip chip,
    required Color fg,
    required IconData fallbackIcon,
    required bool isSearch,
  }) {
    final List<String> byName = chip.appNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final List<String> byPkg = chip.appPackageNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final List<String> keys = byName.isNotEmpty ? byName : byPkg;
    final bool showAppIcons = isSearch && keys.isNotEmpty;
    if (!showAppIcons) {
      return Icon(fallbackIcon, size: 16, color: fg.withOpacity(0.95));
    }

    const int maxIcons = 3;
    final List<String> shown = keys.take(maxIcons).toList(growable: false);
    final int extraCount = keys.length - shown.length;

    final List<Uint8List?> icons = <Uint8List?>[];
    if (byName.isNotEmpty) {
      for (final name in shown) {
        icons.add(_appIconByNameLower[name.toLowerCase()]);
      }
    } else {
      for (final pkg in shown) {
        icons.add(_appIconByPackage[pkg]);
      }
    }

    return _buildAppIconStack(
      context,
      theme: theme,
      fg: fg,
      icons: icons,
      extraCount: extraCount,
    );
  }

  Widget _buildAppIconStack(
    BuildContext context, {
    required ThemeData theme,
    required Color fg,
    required List<Uint8List?> icons,
    required int extraCount,
  }) {
    const double size = 18;
    const double overlap = 6;
    final double step = size - overlap;
    final int shownCount = icons.length;
    final double width =
        size +
        (shownCount <= 1 ? 0 : (shownCount - 1) * step) +
        (extraCount > 0 ? step : 0);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < shownCount; i++)
            Positioned(
              left: i * step,
              child: _buildSingleAppIcon(bytes: icons[i], fg: fg, size: size),
            ),
          if (extraCount > 0)
            Positioned(
              left: shownCount * step,
              child: _buildExtraCountBadge(
                theme,
                extraCount: extraCount,
                fg: fg,
                size: size,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleAppIcon({
    required Uint8List? bytes,
    required Color fg,
    required double size,
  }) {
    final Widget child = bytes != null
        ? Image.memory(bytes, width: size, height: size, fit: BoxFit.contain)
        : Icon(Icons.android, size: size * 0.75, color: fg.withOpacity(0.9));

    // Display the icon as-is; do not add a background behind it.
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: child),
    );
  }

  Widget _buildExtraCountBadge(
    ThemeData theme, {
    required int extraCount,
    required Color fg,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '+$extraCount',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg.withOpacity(0.9),
          fontWeight: FontWeight.w700,
          fontSize: 9,
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

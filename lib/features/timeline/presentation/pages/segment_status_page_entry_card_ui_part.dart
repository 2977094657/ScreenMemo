part of 'segment_status_page.dart';

// ========== 单条动态 UI 构建 ==========
extension _SegmentEntryCardUiPart on _SegmentEntryCardState {
  // 时间居中 + 下一行展示关键动作（不使用分割线）
  Widget _timeSeparator(
    BuildContext context, {
    required String label,
    String? keyActionDetail,
    bool aiRetried = false,
    bool aiRetryFailed = false,
    String? aiRetryMessage,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color actionColor = segmentMergedTagChipColors(context).foreground;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: Stack(
            children: [
              Center(
                child: Text(label, style: DefaultTextStyle.of(context).style),
              ),
              if (aiRetried)
                Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    message: (aiRetryMessage ?? '').trim().isNotEmpty
                        ? aiRetryMessage!
                        : (aiRetryFailed
                              ? AppLocalizations.of(
                                  context,
                                ).aiResultAutoRetryFailedHint
                              : AppLocalizations.of(
                                  context,
                                ).aiResultAutoRetriedHint),
                    child: Icon(
                      aiRetryFailed
                          ? Icons.error_outline_rounded
                          : Icons.info_outline_rounded,
                      size: 16,
                      color: aiRetryFailed ? colorScheme.error : actionColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (keyActionDetail != null && keyActionDetail.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Center(
              child: _buildMarkdownBody(
                context,
                keyActionDetail,
                DefaultTextStyle.of(context).style.copyWith(color: actionColor),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openMergedOriginalEventsDrawer(
    BuildContext context, {
    required List<String> originals,
  }) async {
    if (originals.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final TextStyle? bodyStyle = Theme.of(ctx).textTheme.bodyMedium;
        final cs = Theme.of(ctx).colorScheme;

        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusLg),
            topRight: Radius.circular(AppTheme.radiusLg),
          ),
          child: ColoredBox(
            color: cs.surface,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.78,
                child: DefaultTabController(
                  length: originals.length,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      ScreenshotStyleTabBar(
                        height: kTextTabBarHeight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing3,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        tabs: [
                          for (int i = 0; i < originals.length; i++)
                            Tab(text: l10n.mergedOriginalEventTitle(i + 1)),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Expanded(
                        child: TabBarView(
                          children: originals
                              .map((part) {
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppTheme.spacing4,
                                    0,
                                    AppTheme.spacing4,
                                    AppTheme.spacing6,
                                  ),
                                  child: _buildMarkdownBody(
                                    ctx,
                                    part,
                                    bodyStyle,
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeparator(BuildContext context) {
    final Color base =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      height: 1,
      color: base.withOpacity(0.2),
    );
  }

  Widget _buildAppIcon(BuildContext context, String package) {
    final app = widget.appInfoByPackage[package];
    if (app != null && app.icon != null && app.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          app.icon!,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.apps, size: 14),
    );
  }

  Widget _buildChip(BuildContext context, String text) {
    final SegmentTagChipColors colors = segmentCategoryTagChipColors(
      context,
      text,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: _buildTagChipLabel(
        text: text,
        style: TextStyle(
          fontSize: 12,
          color: colors.foreground,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  MarkdownBody _buildMarkdownBody(
    BuildContext context,
    String data,
    TextStyle? textStyle,
  ) {
    final String normalized = _normalizeMarkdownForUi(data);
    return MarkdownBody(
      data: normalized,
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(p: textStyle),
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

  Widget _buildMergeStatusDropdown(
    BuildContext context, {
    required int segmentId,
    required String state,
    required String reasonText,
    required TextStyle? titleStyle,
    required TextStyle? reasonStyle,
    required bool canForce,
    required List<String> originalSummaries,
  }) {
    final l10n = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color bg = cs.surfaceContainerHighest.withOpacity(0.28);
    final Color border = cs.outline.withOpacity(0.22);

    final bool canOpenOriginals = originalSummaries.isNotEmpty;
    final TextStyle titleLinkStyle = (titleStyle ?? const TextStyle()).copyWith(
      color: cs.primary,
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('seg:$segmentId:mergeStatus'),
          dense: true,
          minTileHeight: 34,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: 0,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTheme.spacing3,
            0,
            AppTheme.spacing3,
            AppTheme.spacing2,
          ),
          leading: Icon(Icons.merge_type, size: 16, color: cs.onSurfaceVariant),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: canOpenOriginals
                      ? () async => _openMergedOriginalEventsDrawer(
                          context,
                          originals: originalSummaries,
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: state),
                          if (canOpenOriginals) const TextSpan(text: ' · '),
                          if (canOpenOriginals)
                            TextSpan(
                              text: l10n.mergedOriginalEventsTitle(
                                originalSummaries.length,
                              ),
                            ),
                        ],
                      ),
                      style: canOpenOriginals ? titleLinkStyle : titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: const StrutStyle(
                        height: 1.15,
                        forceStrutHeight: true,
                      ),
                    ),
                  ),
                ),
              ),
              if (_forcingMerge)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (canForce)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -1,
                      vertical: -3,
                    ),
                  ),
                  onPressed: widget.dynamicRebuildActive
                      ? null
                      : () async => _forceMerge(),
                  child: Text(AppLocalizations.of(context).forceMerge),
                ),
            ],
          ),
          children: [
            if (reasonText.trim().isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(reasonText, style: reasonStyle),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    List<String> categories,
    bool merged,
  ) {
    final int total = categories.length + (merged ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();

    final List<Widget> chips = <Widget>[
      if (merged) _buildMergedTagChip(context),
      ...categories.map((c) => _buildChip(context, c)),
    ];

    final TextStyle measureStyle = const TextStyle(
      fontSize: 12,
      height: 1.0,
      fontWeight: FontWeight.w500,
    );
    final TextScaler textScaler = MediaQuery.textScalerOf(context);

    double estimateChipHeight() {
      final tp = TextPainter(
        text: TextSpan(text: '测试', style: measureStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      final double contentHeight =
          tp.height + _SegmentEntryCardState._tagChipVerticalPadding * 2;
      return math
          .max(_SegmentEntryCardState._tagChipMinHeight, contentHeight)
          .ceilToDouble();
    }

    double estimateChipWidth(String label, double maxWidth) {
      final double horizontalPadding = AppTheme.spacing2;
      final double maxTextWidth = math.max(0, maxWidth - horizontalPadding * 2);
      final tp = TextPainter(
        text: TextSpan(text: label, style: measureStyle),
        maxLines: 1,
        ellipsis: '…',
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout(maxWidth: maxTextWidth);
      final double w = tp.width + horizontalPadding * 2;
      return w.clamp(0, maxWidth);
    }

    int estimateRows(List<String> labels, double maxWidth) {
      if (labels.isEmpty) return 0;
      final double spacing = _SegmentEntryCardState._tagGridCrossAxisSpacing;
      int rows = 1;
      double rowWidth = 0;
      for (final label in labels) {
        final double w = estimateChipWidth(label, maxWidth);
        if (rowWidth == 0) {
          rowWidth = w;
          continue;
        }
        if (rowWidth + spacing + w <= maxWidth) {
          rowWidth += spacing + w;
        } else {
          rows += 1;
          rowWidth = w;
        }
      }
      return rows;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final List<String> labels = <String>[
          if (merged) AppLocalizations.of(context).mergedEventTag,
          ...categories,
        ];
        final int rows = estimateRows(labels, maxWidth);

        if (rows <= _SegmentEntryCardState._tagMaxVisibleRows) {
          return Wrap(
            spacing: _SegmentEntryCardState._tagGridCrossAxisSpacing,
            runSpacing: _SegmentEntryCardState._tagGridMainAxisSpacing,
            alignment: WrapAlignment.start,
            children: chips,
          );
        }

        final double chipHeight = estimateChipHeight();
        final double viewportHeight =
            chipHeight * _SegmentEntryCardState._tagMaxVisibleRows +
            _SegmentEntryCardState._tagGridMainAxisSpacing *
                (_SegmentEntryCardState._tagMaxVisibleRows - 1);
        final theme = Theme.of(context);
        final Color hintColor = theme.colorScheme.onSurfaceVariant.withOpacity(
          0.45,
        );

        // 最多显示两行，超过则在内部滚动（不撑爆卡片布局）。
        return SizedBox(
          height:
              viewportHeight + _SegmentEntryCardState._tagOverflowHintHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: viewportHeight,
                child: Scrollbar(
                  controller: _tagScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(3),
                  child: SingleChildScrollView(
                    controller: _tagScrollController,
                    primary: false,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    child: Wrap(
                      spacing: _SegmentEntryCardState._tagGridCrossAxisSpacing,
                      runSpacing:
                          _SegmentEntryCardState._tagGridMainAxisSpacing,
                      alignment: WrapAlignment.start,
                      children: chips,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  height: _SegmentEntryCardState._tagOverflowHintHeight,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: hintColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMergedTagChip(BuildContext context) {
    final SegmentTagChipColors colors = segmentMergedTagChipColors(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: _buildTagChipLabel(
        text: AppLocalizations.of(context).mergedEventTag,
        style: TextStyle(
          fontSize: 12,
          color: colors.foreground,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTagChipLabel({required String text, required TextStyle style}) {
    final double minLabelHeight =
        _SegmentEntryCardState._tagChipMinHeight -
        _SegmentEntryCardState._tagChipVerticalPadding * 2;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minLabelHeight),
      child: Align(
        alignment: const Alignment(0, -0.14),
        widthFactor: 1,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          strutStyle: const StrutStyle(height: 1.0, forceStrutHeight: true),
          style: style,
        ),
      ),
    );
  }

  Widget _buildThumbGrid(
    BuildContext context,
    List<Map<String, dynamic>> samples, {
    Set<String> aiNsfwFiles = const <String>{},
  }) {
    if (samples.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final double cellWidth =
            (availableWidth -
                _SegmentEntryCardState._thumbGridSpacing *
                    (_SegmentEntryCardState._thumbGridCrossAxisCount - 1)) /
            _SegmentEntryCardState._thumbGridCrossAxisCount;
        // childAspectRatio = width / height => height = width / ratio
        const double childAspectRatio = 9 / 16;
        final double cellHeight = cellWidth / childAspectRatio;

        final int rows =
            (samples.length / _SegmentEntryCardState._thumbGridCrossAxisCount)
                .ceil();
        final double naturalHeight =
            rows * cellHeight +
            math.max(0, rows - 1) * _SegmentEntryCardState._thumbGridSpacing;
        final double maxHeight = math.min(
          _SegmentEntryCardState._thumbVirtualGridMaxHeight,
          MediaQuery.of(context).size.height * 0.55,
        );
        final double viewportHeight = math.min(naturalHeight, maxHeight);

        final double dpr = MediaQuery.of(context).devicePixelRatio;
        final int targetWidthPx = (cellWidth * dpr).round().clamp(96, 1024);

        return SizedBox(
          height: viewportHeight,
          child: Scrollbar(
            thumbVisibility: naturalHeight > viewportHeight,
            child: GridView.builder(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: samples.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _SegmentEntryCardState._thumbGridCrossAxisCount,
                crossAxisSpacing: _SegmentEntryCardState._thumbGridSpacing,
                mainAxisSpacing: _SegmentEntryCardState._thumbGridSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (ctx, i) {
                final s = samples[i];
                final path = (s['file_path'] as String?) ?? '';
                final pageUrl = (s['page_url'] as String?) ?? '';

                if (path.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    ),
                  );
                }

                final String fileName = path
                    .replaceAll('\\', '/')
                    .split('/')
                    .last;
                final bool aiNsfw = aiNsfwFiles.contains(fileName);

                return ScreenshotImageWidget(
                  file: File(path),
                  privacyMode: widget.privacyMode,
                  extraNsfwMask: aiNsfw,
                  pageUrl: pageUrl.isNotEmpty ? pageUrl : null,
                  targetWidth: targetWidthPx,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.openGallery(samples, i),
                  showNsfwButton: true,
                  errorText: AppLocalizations.of(context).imageError,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

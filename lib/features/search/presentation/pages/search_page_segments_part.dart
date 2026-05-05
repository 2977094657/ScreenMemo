part of 'search_page.dart';

// ========== 动态结果解析与展示 ==========
extension _SearchPageSegmentsPart on _SearchPageState {
  /// 从 structured_json 解析 JSON
  Map<String, dynamic>? _tryParseJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return null;
  }

  /// 提取摘要：优先从 structured_json.overall_summary，否则回退到 output_text
  String _extractOverallSummary(
    Map<String, dynamic>? result,
    Map<String, dynamic>? sj,
  ) {
    final v = sj?['overall_summary'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    final out = (result?['output_text'] as String?)?.trim() ?? '';
    return out.toLowerCase() == 'null' ? '' : out;
  }

  /// 清理标签文本（移除 [""] 等无效字符）
  String _cleanTagText(String text) {
    String cleaned = text.trim();
    // 移除所有 [ ] " 字符
    cleaned = cleaned.replaceAll('[', '');
    cleaned = cleaned.replaceAll(']', '');
    cleaned = cleaned.replaceAll('"', '');
    cleaned = cleaned.replaceAll("'", '');
    return cleaned.trim();
  }

  /// 检查标签是否有效（过滤掉无效标签）
  bool _isValidTag(String tag) {
    final cleaned = tag.trim();
    if (cleaned.isEmpty) return false;
    // 过滤掉只包含符号的标签
    if (RegExp(r'^[\[\]"\s,]+$').hasMatch(cleaned)) return false;
    return true;
  }

  /// 提取标签列表：从 categories 字段（可能是 JSON array 或逗号分隔）和 structured_json.categories
  List<String> _extractCategories(
    Map<String, dynamic>? result,
    Map<String, dynamic>? sj,
  ) {
    final List<String> out = <String>[];
    // 1) result.categories 可能是 JSON 或逗号分隔
    final raw = result?['categories'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final obj = jsonDecode(raw);
        if (obj is List) {
          out.addAll(obj.map((e) => _cleanTagText(e.toString())));
        } else {
          out.addAll(raw.split(RegExp(r'[,\s]+')).map((e) => _cleanTagText(e)));
        }
      } catch (_) {
        out.addAll(raw.split(RegExp(r'[,\s]+')).map((e) => _cleanTagText(e)));
      }
    }
    // 2) structured_json.categories
    final sc = sj?['categories'];
    if (sc is List) {
      out.addAll(sc.map((e) => _cleanTagText(e.toString())));
    } else if (sc is String && sc.trim().isNotEmpty) {
      out.addAll(sc.split(RegExp(r'[,\s]+')).map((e) => _cleanTagText(e)));
    }
    // 去重并过滤无效标签
    final set = <String>{};
    final res = <String>[];
    for (final c in out) {
      final v = _cleanTagText(c);
      if (!_isValidTag(v)) continue;
      if (set.add(v)) res.add(v);
    }
    return res;
  }

  /// 构建单个标签 chip（与动态页面样式一致）
  Widget _buildTagChip(BuildContext context, String text) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = dark ? AppTheme.darkSelectedAccent : AppTheme.info;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: fg.withOpacity(0.35), width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: fg,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建应用图标
  Widget _buildAppIcon(String package) {
    final app = _appInfoByPackage[package];
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

  /// 构建动态卡片（与动态页面样式一致）
  Widget _buildSegmentCard(Map<String, dynamic> seg) {
    final int startMs = (seg['start_time'] as int?) ?? 0;
    final int endMs = (seg['end_time'] as int?) ?? 0;
    final String outputText = (seg['output_text'] as String?) ?? '';
    final String categoriesRaw = (seg['categories'] as String?) ?? '';
    final String structuredJson = (seg['structured_json'] as String?) ?? '';
    final int sampleCount = (seg['sample_count'] as int?) ?? 0;
    final bool merged = (seg['merged_flag'] as int?) == 1;

    // 解析 structured_json
    final Map<String, dynamic>? sj = _tryParseJson(structuredJson);

    // 提取摘要和标签
    final Map<String, dynamic> resultMeta = {
      'categories': categoriesRaw,
      'output_text': outputText,
    };
    final String summaryAll = _extractOverallSummary(resultMeta, sj);
    final List<String> mergedParts = merged
        ? splitMergedEventSummaryParts(summaryAll)
        : const <String>[];
    final String summary = mergedParts.isNotEmpty
        ? mergedParts.first
        : summaryAll;
    final List<String> tags = _extractCategories(resultMeta, sj);

    // 解析应用包名
    List<String> packages = <String>[];
    final String? appPkgsDisplay = seg['app_packages_display'] as String?;
    final String? appPkgsRaw = seg['app_packages'] as String?;
    final String? pkgSrc =
        (appPkgsDisplay != null && appPkgsDisplay.trim().isNotEmpty)
        ? appPkgsDisplay
        : appPkgsRaw;
    if (pkgSrc != null && pkgSrc.trim().isNotEmpty) {
      packages = pkgSrc
          .split(RegExp(r'[,\s]+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing1),
      child: InkWell(
        onTap: () => _showSegmentDetail(seg),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间行
            SizedBox(
              height: 22,
              child: Center(
                child: Text(
                  _formatSegmentTime(startMs, endMs),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // 应用图标
            if (packages.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: packages.map((pkg) => _buildAppIcon(pkg)).toList(),
              ),
              const SizedBox(height: 8),
            ],
            // 标签
            if (tags.isNotEmpty || merged) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (merged)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing2,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(minHeight: 20),
                      decoration: BoxDecoration(
                        color: AppTheme.mergedEventAccent.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(
                          color: AppTheme.mergedEventAccent.withValues(
                            alpha: 0.45,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context).mergedEventTag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.mergedEventAccent,
                          height: 1.0,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ...tags.map((tag) => _buildTagChip(context, tag)),
                ],
              ),
              const SizedBox(height: 6),
            ],
            // 摘要内容（高亮命中词，限制高度）
            if (summary.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final TextStyle? textStyle = Theme.of(
                    context,
                  ).textTheme.bodyMedium;
                  // 限制最多 5 行高度
                  final double lineHeight =
                      (textStyle?.height ?? 1.4) *
                      (textStyle?.fontSize ?? 14.0);
                  final double maxHeight = lineHeight * 5.0 + 8.0;

                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: ClipRect(
                      child: _buildHighlightedMarkdown(
                        context: context,
                        text: summary,
                        style: textStyle,
                      ),
                    ),
                  );
                },
              ),
            // 样本数量
            if (sampleCount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Spacer(),
                  Icon(
                    Icons.photo_library_outlined,
                    size: 14,
                    color: AppTheme.mutedForeground,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$sampleCount',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ],
            // 分割线
            const SizedBox(height: AppTheme.spacing2),
            Container(
              height: 1,
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示动态详情弹窗
  Future<void> _showSegmentDetail(Map<String, dynamic> seg) async {
    final int startMs = (seg['start_time'] as int?) ?? 0;
    final int endMs = (seg['end_time'] as int?) ?? 0;
    final String outputText = (seg['output_text'] as String?) ?? '';
    final String categoriesRaw = (seg['categories'] as String?) ?? '';
    final String structuredJson = (seg['structured_json'] as String?) ?? '';
    final int segmentId = (seg['id'] as int?) ?? 0;
    final bool merged = (seg['merged_flag'] as int?) == 1;

    // 解析 structured_json
    final Map<String, dynamic>? sj = _tryParseJson(structuredJson);
    final Map<String, dynamic> resultMeta = {
      'categories': categoriesRaw,
      'output_text': outputText,
    };
    final String summaryAll = _extractOverallSummary(resultMeta, sj);
    final List<String> mergedParts = merged
        ? splitMergedEventSummaryParts(summaryAll)
        : const <String>[];
    final String summary = mergedParts.isNotEmpty
        ? mergedParts.first
        : summaryAll;
    final List<String> originalSummaries = mergedParts.length > 1
        ? mergedParts.sublist(1)
        : const <String>[];
    final List<String> tags = _extractCategories(resultMeta, sj);

    // 解析应用包名
    List<String> packages = <String>[];
    final String? appPkgsDisplay = seg['app_packages_display'] as String?;
    final String? appPkgsRaw = seg['app_packages'] as String?;
    final String? pkgSrc =
        (appPkgsDisplay != null && appPkgsDisplay.trim().isNotEmpty)
        ? appPkgsDisplay
        : appPkgsRaw;
    if (pkgSrc != null && pkgSrc.trim().isNotEmpty) {
      packages = pkgSrc
          .split(RegExp(r'[,\s]+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    // 获取样本
    final samples = await ScreenshotDatabase.instance.listSegmentSamples(
      segmentId,
    );
    final sampleRecords = _mapSamplesToScreenshots(samples);
    // 预加载 AI NSFW，确保详情弹窗里的图片遮罩与动态一致
    try {
      final paths = sampleRecords
          .map((s) => s.filePath.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (paths.isNotEmpty) {
        await NsfwPreferenceService.instance.preloadAiNsfwFlags(
          filePaths: paths,
        );
        await NsfwPreferenceService.instance.preloadSegmentNsfwFlags(
          filePaths: paths,
        );
      }
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return UISheetSurface(
              child: Column(
                children: [
                  const SizedBox(height: AppTheme.spacing3),
                  const UISheetHandle(),
                  const SizedBox(height: AppTheme.spacing3),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        0,
                        AppTheme.spacing4,
                        AppTheme.spacing6,
                      ),
                      children: [
                        // 时间
                        Text(
                          _formatSegmentTime(startMs, endMs),
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        // 应用图标
                        if (packages.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: packages
                                .map((pkg) => _buildAppIcon(pkg))
                                .toList(),
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                        ],
                        // 标签
                        if (tags.isNotEmpty || merged) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (merged)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacing2,
                                    vertical: 2,
                                  ),
                                  constraints: const BoxConstraints(
                                    minHeight: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.mergedEventAccent
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusSm,
                                    ),
                                    border: Border.all(
                                      color: AppTheme.mergedEventAccent
                                          .withValues(alpha: 0.45),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    AppLocalizations.of(context).mergedEventTag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mergedEventAccent,
                                      height: 1.0,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ...tags.map((tag) => _buildTagChip(ctx, tag)),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                        ],
                        // 摘要（高亮命中词）
                        if (summary.isNotEmpty) ...[
                          _buildHighlightedMarkdown(
                            context: ctx,
                            text: summary,
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                        ],
                        if (merged && originalSummaries.isNotEmpty) ...[
                          Builder(
                            builder: (context) {
                              final cs = Theme.of(context).colorScheme;
                              return Container(
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withOpacity(
                                    0.28,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusSm,
                                  ),
                                  border: Border.all(
                                    color: cs.outline.withOpacity(0.22),
                                  ),
                                ),
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacing3,
                                  ),
                                  leading: Icon(
                                    Icons.view_carousel_outlined,
                                    size: 18,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  title: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).mergedOriginalEventsTitle(
                                      originalSummaries.length,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  trailing: Icon(
                                    Icons.chevron_right,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  onTap: () async {
                                    await _openMergedOriginalEventsDrawer(
                                      context,
                                      originals: originalSummaries,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                        ],
                        // 样本图片
                        if (samples.isNotEmpty) ...[
                          const Divider(),
                          const SizedBox(height: AppTheme.spacing2),
                          Text(
                            '${AppLocalizations.of(context).images} (${samples.length})',
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppTheme.spacing2),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                  childAspectRatio: 9 / 16,
                                ),
                            itemCount: sampleRecords.length,
                            itemBuilder: (c, i) {
                              final rec = sampleRecords[i];
                              final bool isNsfw = NsfwPreferenceService.instance
                                  .shouldMaskCached(rec);
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSm,
                                ),
                                child: ScreenshotItemWidget(
                                  screenshot: rec,
                                  baseDir: _baseDir,
                                  appInfoMap: _appInfoByPackage,
                                  privacyMode: _privacyMode,
                                  aiMetaBadgePlacement:
                                      AiMetaBadgePlacement.topRight,
                                  isNsfwFlagged: isNsfw,
                                  onTap: () =>
                                      _openSampleViewer(sampleRecords, i),
                                  showCheckbox: false,
                                  showFavoriteButton: false,
                                  showNsfwButton: false,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
                                  child: _buildHighlightedMarkdown(
                                    context: ctx,
                                    text: part,
                                    style: bodyStyle,
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

  /// 构建搜索空状态（简单提示，垂直居中）
  Widget _buildEmptyState(AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 48,
                    color: AppTheme.mutedForeground.withOpacity(0.5),
                  ),
                  const SizedBox(height: AppTheme.spacing3),
                  Text(
                    l10n.searchInputHintOcr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

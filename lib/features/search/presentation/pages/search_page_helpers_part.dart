part of 'search_page.dart';

// ========== 搜索页辅助方法与格式化 ==========
extension _SearchPageHelpersPart on _SearchPageState {
  int get _filteredSegmentCount {
    if (_selectedTags.isEmpty) return _segmentTotalCount;
    return _filteredSegments.length;
  }

  int get _filteredSemanticCount {
    if (_semanticSelectedTags.isEmpty) return _semanticTotalCount;
    return _filteredSemanticResults.length;
  }

  /// 将 segment 样本记录转换为 ScreenshotRecord 列表，便于复用统一渲染组件
  List<ScreenshotRecord> _mapSamplesToScreenshots(
    List<Map<String, dynamic>> samples,
  ) {
    return samples.map((s) {
      final int capture = (s['capture_time'] as int?) ?? 0;
      return ScreenshotRecord(
        id: s['id'] as int?,
        appPackageName: (s['app_package_name'] as String?) ?? '',
        appName: (s['app_name'] as String?) ?? '',
        filePath: (s['file_path'] as String?) ?? '',
        captureTime: DateTime.fromMillisecondsSinceEpoch(capture),
        fileSize: (s['file_size'] as int?) ?? 0,
        isDeleted: false,
        pageUrl: null,
        ocrText: null,
      );
    }).toList();
  }

  /// 将 ai_image_meta 搜索结果转换为 ScreenshotRecord 列表（用于复用统一渲染组件）。
  List<ScreenshotRecord> _mapAiImageMetaRowsToScreenshots(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return <ScreenshotRecord>[];
    final List<ScreenshotRecord> out = <ScreenshotRecord>[];
    for (final r in rows) {
      final String fp = (r['file_path'] as String?)?.trim() ?? '';
      if (fp.isEmpty) continue;
      final int capture = (r['capture_time'] as int?) ?? 0;
      out.add(
        ScreenshotRecord(
          id: null,
          appPackageName: (r['app_package_name'] as String?) ?? '',
          appName: (r['app_name'] as String?) ?? '',
          filePath: fp,
          captureTime: DateTime.fromMillisecondsSinceEpoch(
            capture > 0 ? capture : DateTime.now().millisecondsSinceEpoch,
          ),
          fileSize: 0,
          isDeleted: false,
          pageUrl: null,
          ocrText: null,
        ),
      );
    }
    return out;
  }

  Future<void> _preloadNsfwForScreenshots(
    List<ScreenshotRecord> data, {
    required int token,
  }) async {
    if (data.isEmpty) return;
    try {
      // 1) AI NSFW（按 file_path，全局复用）
      final paths = data
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

      // 2) 手动标记（按 app 分组）
      final Map<String, List<int>> idsByApp = <String, List<int>>{};
      for (final s in data) {
        final id = s.id;
        final pkg = s.appPackageName.trim();
        if (id == null || pkg.isEmpty) continue;
        idsByApp.putIfAbsent(pkg, () => <int>[]).add(id);
      }
      for (final entry in idsByApp.entries) {
        final ids = entry.value;
        if (ids.isEmpty) continue;
        await NsfwPreferenceService.instance.preloadManualFlags(
          appPackageName: entry.key,
          screenshotIds: ids,
        );
      }
    } catch (_) {}
    if (!mounted || token != _searchToken) return;
    _searchSetState(() {});
  }

  Future<List<ScreenshotRecord>> _searchFavoriteNoteScreenshots(
    String query, {
    required int limit,
    required int offset,
    int? startMillis,
    int? endMillis,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return <ScreenshotRecord>[];

    // 兜底：确保索引追赶（收藏由 Flutter 写入，但也可能来自旧数据回填）
    await ScreenshotDatabase.instance.syncSearchIndex(
      sources: const <String>{kSearchIndexSourceFavorites},
    );

    final docs = await ScreenshotDatabase.instance.searchSearchDocsByText(
      q,
      docTypes: const <String>{kSearchDocTypeFavoriteNote},
      limit: limit,
      offset: offset,
      startMillis: startMillis,
      endMillis: endMillis,
    );

    final List<ScreenshotRecord> out = <ScreenshotRecord>[];
    for (final d in docs) {
      final int? gid = d['screenshot_id'] as int?;
      final String? pkg = d['app_package_name'] as String?;
      if (gid == null || gid <= 0) continue;
      if (pkg == null || pkg.trim().isEmpty) continue;
      final rec = await ScreenshotDatabase.instance.getScreenshotById(gid, pkg);
      if (rec == null) continue;

      // 由于索引里无法直接存 capture_time，这里按真实截图时间做一次过滤
      final int capture = rec.captureTime.millisecondsSinceEpoch;
      if (startMillis != null && capture < startMillis) continue;
      if (endMillis != null && capture > endMillis) continue;

      out.add(rec);
    }
    return out;
  }

  /// 打开样本查看器（复用截图查看器样式）
  void _openSampleViewer(List<ScreenshotRecord> samples, int index) {
    if (samples.isEmpty) return;
    final record = samples[index.clamp(0, samples.length - 1)];
    final appInfo =
        _appInfoByPackage[record.appPackageName] ??
        AppInfo(
          packageName: record.appPackageName,
          appName: record.appName,
          icon: null,
          version: '',
          isSystemApp: false,
        );
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': samples,
        'initialIndex': index,
        'appName': record.appName,
        'appInfo': appInfo,
      },
    );
  }

  /// 高亮显示命中关键词的 Markdown 文本（橙色荧光笔效果，同时保留 Markdown 渲染）
  Widget _buildHighlightedMarkdown({
    required BuildContext context,
    required String text,
    TextStyle? style,
  }) {
    final String query = _lastQuery.trim();
    String data = text;
    if (query.isNotEmpty) {
      final reg = RegExp(RegExp.escape(query), caseSensitive: false);
      data = text.replaceAllMapped(reg, (m) => '<mark>${m[0]}</mark>');
    }

    return MarkdownBody(
      data: data,
      extensionSet: md.ExtensionSet.gitHubWeb,
      inlineSyntaxes: [MarkSyntax()],
      selectable: false,
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(p: style),
      builders: {
        'mark': MarkBuilder(SearchStyles.highlightTextDecoration(context)),
      },
      softLineBreak: true,
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

  /// 根据标签筛选后的动态列表
  List<Map<String, dynamic>> get _filteredSegments {
    if (_selectedTags.isEmpty) return _segmentResults;
    return _segmentResults.where((seg) {
      final tags = _extractCategories({
        'categories': seg['categories'],
      }, _tryParseJson(seg['structured_json'] as String?));
      // 检查是否包含所有选中的标签
      return _selectedTags.every((selected) => tags.contains(selected));
    }).toList();
  }

  Rect? _getGridViewportRect() {
    final ctx = _gridKey.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  void _updateVisibleRange() {
    if (_filteredResults.isEmpty || _itemKeys.isEmpty) {
      _visibleStartIndex = 0;
      _visibleEndIndex = -1;
      return;
    }
    final viewport = _getGridViewportRect();
    if (viewport == null) return;
    int? firstIdx;
    int? lastIdx;
    _itemKeys.forEach((index, key) {
      if (index < 0 || index >= _filteredResults.length) return;
      final context = key.currentContext;
      if (context == null) return;
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final rect = render.localToGlobal(Offset.zero) & render.size;
      final visible = rect.bottom > viewport.top && rect.top < viewport.bottom;
      if (!visible) return;
      if (firstIdx == null || index < firstIdx!) firstIdx = index;
      if (lastIdx == null || index > lastIdx!) lastIdx = index;
    });
    if (firstIdx != null && lastIdx != null) {
      _visibleStartIndex = firstIdx!;
      _visibleEndIndex = lastIdx!;
    }
  }

  bool _shouldLoadBoxesForIndex(int index) {
    if (_lastQuery.isEmpty) return false;
    // AI 元数据检索并非基于 OCR 命中词，不加载 OCR 标注框以减少开销
    if (_usingAiImageMeta || _usingFavoriteNotes) return false;
    // 初次构建不可见范围未就绪时，允许首屏附近少量请求
    if (_visibleEndIndex < 0) return index < 12;
    final int start = (_visibleStartIndex - 10) < 0
        ? 0
        : (_visibleStartIndex - 10);
    final int end = _visibleEndIndex + 10;
    return index >= start && index <= end;
  }
}

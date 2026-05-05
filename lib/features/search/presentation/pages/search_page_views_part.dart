part of 'search_page.dart';

// ========== 搜索结果 Tab 视图 ==========
extension _SearchPageViewsPart on _SearchPageState {
  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);

    if (_controller.text.trim().isEmpty) {
      return _buildEmptyState(l10n);
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: AppTheme.destructive),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Tab 切换栏（与截图列表一致：左对齐、可滚动、细下划线指示器）
        Padding(
          padding: const EdgeInsets.only(left: 0, right: AppTheme.spacing1),
          child: SizedBox(
            height: 32,
            child: ScreenshotStyleTabBar(
              controller: _tabController,
              isScrollable: false,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
              ),
              tabs: [
                Tab(
                  text: '截图 (${_countingTotal ? '...' : _totalResultsCount})',
                ),
                Tab(
                  text: _semanticSearching
                      ? '语义 (...)'
                      : (_semanticSearchFinished
                            ? '语义 (${_semanticCountingTotal ? '...' : _filteredSemanticCount})'
                            : '语义'),
                ),
                Tab(
                  text: _segmentSearching
                      ? '动态 (...)'
                      : (_segmentSearchFinished
                            ? '动态 (${_segmentCountingTotal ? '...' : _filteredSegmentCount})'
                            : '动态'),
                ),
                Tab(
                  text: _docSearching
                      ? '更多 (...)'
                      : (_docSearchFinished
                            ? '更多 (${_docCountingTotal ? '...' : _docTotalCount})'
                            : '更多'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 1),
        // TabBarView 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // 截图 Tab
              _buildScreenshotsView(),
              // 语义 Tab
              _buildSemanticView(),
              // 动态 Tab
              _buildSegmentsView(),
              // 更多 Tab
              _buildDocsView(),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建截图视图
  Widget _buildScreenshotsView() {
    if (_filteredResults.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noResultsForFilters,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    }

    return Column(
      children: [
        // 结果统计和筛选栏
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing2,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).searchResultsCount(
                          _countingTotal
                              ? '...'
                              : _totalResultsCount.toString(),
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_countingTotal) ...[
                      const SizedBox(width: AppTheme.spacing1),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              InkWell(
                onTap: _showFilterDialog,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: AppTheme.spacing1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: (_timeFilter != 'all' || _sizeFilter != 'all')
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_list,
                        size: 16,
                        color: (_timeFilter != 'all' || _sizeFilter != 'all')
                            ? Theme.of(context).colorScheme.primary
                            : AppTheme.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context).searchFiltersTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: (_timeFilter != 'all' || _sizeFilter != 'all')
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 图片网格
        Expanded(
          child: _filteredResults.isEmpty
              ? Center(
                  child: Text(
                    AppLocalizations.of(context).noResultsForFilters,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing1),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      // 更新可见范围
                      _updateVisibleRange();
                      // 滚动活跃态：暂停OCR叠加，滚动空闲后再恢复
                      bool shouldSetActive = false;
                      if (n is ScrollUpdateNotification ||
                          n is UserScrollNotification ||
                          n is OverscrollNotification) {
                        if (!_scrollActive) shouldSetActive = true;
                        _scrollIdleTimer?.cancel();
                        _scrollIdleTimer = Timer(
                          const Duration(milliseconds: 120),
                          () {
                            if (!mounted) return;
                            if (_scrollActive) {
                              _searchSetState(() {
                                _scrollActive = false;
                              });
                            }
                          },
                        );
                      }
                      if (shouldSetActive) {
                        _searchSetState(() {
                          _scrollActive = true;
                        });
                      }
                      // 接近底部时预取下一页
                      if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                        _onScroll();
                      }
                      return false;
                    },
                    child: GridView.builder(
                      key: _gridKey,
                      controller: _scrollController,
                      cacheExtent: MediaQuery.of(context).size.height,
                      addAutomaticKeepAlives: false,
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.of(context).padding.bottom +
                            AppTheme.spacing6,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppTheme.spacing1,
                            mainAxisSpacing: AppTheme.spacing1,
                            childAspectRatio: 0.45,
                          ),
                      itemCount:
                          _filteredResults.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_loadingMore && index == _filteredResults.length) {
                          return const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final s = _filteredResults[index];

                        // 构建 OCR 标注叠加层（仅可见附近范围才请求与绘制）
                        Widget? ocrOverlay;
                        if (!_scrollActive && _shouldLoadBoxesForIndex(index)) {
                          if (_boxesFutureCache.length > 40) {
                            _boxesFutureCache.remove(
                              _boxesFutureCache.keys.first,
                            );
                          }
                          ocrOverlay = SearchMatchBoxesOverlay(
                            boxesFuture: _ensureBoxes(s.filePath),
                          );
                        }

                        final bool isNsfw = NsfwPreferenceService.instance
                            .shouldMaskCached(s);

                        final GlobalKey itemKey = _itemKeys.putIfAbsent(
                          index,
                          () => GlobalKey(),
                        );
                        return KeyedSubtree(
                          key: itemKey,
                          child: RepaintBoundary(
                            child: ScreenshotItemWidget(
                              screenshot: s,
                              baseDir: _baseDir,
                              appInfoMap: _appInfoByPackage,
                              privacyMode: _privacyMode,
                              showNsfwButton: false,
                              isNsfwFlagged: isNsfw,
                              onTap: () => _openViewer(s, index),
                              showTimelineJumpButton: true,
                              customOverlay: ocrOverlay,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSemanticView() {
    final l10n = AppLocalizations.of(context);

    if (_lastQuery.trim().isNotEmpty && !_semanticSearchFinished) {
      if (_semanticSearching) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.semanticSearchNotStartedTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                l10n.semanticSearchNotStartedDesc,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing3),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _searchSemantic(_lastQuery),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(l10n.searchSemantic),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final List<ScreenshotRecord> data = _filteredSemanticResults;
    final bool hasTagFilter = _semanticSelectedTags.isNotEmpty;

    Widget grid;
    if (data.isEmpty) {
      grid = Center(
        child: Text(
          l10n.noResultsForFilters,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    } else {
      grid = Padding(
        padding: const EdgeInsets.all(AppTheme.spacing1),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
              _loadMoreSemantic();
            }
            return false;
          },
          child: GridView.builder(
            controller: _semanticScrollController,
            cacheExtent: MediaQuery.of(context).size.height,
            addAutomaticKeepAlives: false,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppTheme.spacing1,
              mainAxisSpacing: AppTheme.spacing1,
              childAspectRatio: 0.45,
            ),
            itemCount: data.length + (_semanticLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (_semanticLoadingMore && index == data.length) {
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final s = data[index];
              final bool isNsfw = NsfwPreferenceService.instance
                  .shouldMaskCached(s);

              return RepaintBoundary(
                child: ScreenshotItemWidget(
                  screenshot: s,
                  baseDir: _baseDir,
                  appInfoMap: _appInfoByPackage,
                  privacyMode: _privacyMode,
                  showNsfwButton: false,
                  isNsfwFlagged: isNsfw,
                  onTap: () => _openSemanticViewer(s, index),
                  showTimelineJumpButton: true,
                ),
              );
            },
          ),
        ),
      );
    }

    return Column(
      children: [
        // 筛选栏（与动态一致：标签筛选）
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing2,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.foundImagesCount(
                          _semanticCountingTotal
                              ? '...'
                              : _filteredSemanticCount,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_semanticCountingTotal) ...[
                      const SizedBox(width: AppTheme.spacing1),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              InkWell(
                onTap: _showSemanticTagFilterSheet,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: AppTheme.spacing1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: hasTagFilter
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_offer_outlined,
                        size: 16,
                        color: hasTagFilter
                            ? Theme.of(context).colorScheme.primary
                            : AppTheme.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _semanticSelectedTags.isEmpty
                            ? l10n.tagsLabel
                            : l10n.tagCount(_semanticSelectedTags.length),
                        style: TextStyle(
                          fontSize: 12,
                          color: hasTagFilter
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: grid),
      ],
    );
  }

  /// 构建动态视图
  Widget _buildSegmentsView() {
    final segments = _filteredSegments;
    final l10n = AppLocalizations.of(context);

    if (_lastQuery.trim().isNotEmpty && !_segmentSearchFinished) {
      if (_segmentSearching) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.segmentSearchNotStartedTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                l10n.segmentSearchNotStartedDesc,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing3),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _searchSegments(_lastQuery),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(l10n.searchDynamic),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 筛选栏（与截图样式一致）
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing2,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
            ),
          ),
          child: Row(
            children: [
              // 左边：结果数量
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '找到 ${_segmentCountingTotal ? '...' : segments.length} 条动态',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_segmentCountingTotal) ...[
                      const SizedBox(width: AppTheme.spacing1),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              // 右边：标签筛选按钮（与截图筛选按钮样式一致）
              InkWell(
                onTap: _showTagFilterSheet,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: AppTheme.spacing1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedTags.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_offer_outlined,
                        size: 16,
                        color: _selectedTags.isNotEmpty
                            ? Theme.of(context).colorScheme.primary
                            : AppTheme.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _selectedTags.isEmpty
                            ? '标签'
                            : '${_selectedTags.length}个标签',
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedTags.isNotEmpty
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 动态列表
        Expanded(
          child: segments.isEmpty
              ? Center(
                  child: Text(
                    l10n.noResultsForFilters,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                      _loadMoreSegments();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      left: AppTheme.spacing3,
                      right: AppTheme.spacing3,
                      top: AppTheme.spacing2,
                      bottom:
                          MediaQuery.of(context).padding.bottom +
                          AppTheme.spacing6,
                    ),
                    itemCount:
                        segments.length +
                        (_segmentLoadingMore && _selectedTags.isEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_segmentLoadingMore &&
                          _selectedTags.isEmpty &&
                          index == segments.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(AppTheme.spacing4),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return _buildSegmentCard(segments[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// 构建“更多”视图（SearchIndex：daily/morning/persona/favorite_note 等）。
  Widget _buildDocsView() {
    final l10n = AppLocalizations.of(context);

    if (_lastQuery.trim().isNotEmpty && !_docSearchFinished) {
      if (_docSearching) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '更多搜索未开始',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                '这里会搜索每日总结、早报、画像文章、应用事件、收藏备注等。为避免输入时卡顿，需要手动触发搜索。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing3),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _searchDocs(_lastQuery),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(AppLocalizations.of(context).searchMore),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Set<String> activeTypes = _docSelectedTypes.isEmpty
        ? _SearchPageState._docTabTypes
        : _docSelectedTypes;
    final bool hasTypeFilter =
        activeTypes.length != _SearchPageState._docTabTypes.length;

    Widget body;
    if (_docResults.isEmpty) {
      body = Center(
        child: Text(
          l10n.noResultsForFilters,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
            _loadMoreDocs();
          }
          return false;
        },
        child: ListView.builder(
          padding: EdgeInsets.only(
            left: AppTheme.spacing3,
            right: AppTheme.spacing3,
            top: AppTheme.spacing2,
            bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
          ),
          itemCount: _docResults.length + (_docLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (_docLoadingMore && index == _docResults.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.spacing4),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _buildDocCard(_docResults[index]);
          },
        ),
      );
    }

    return Column(
      children: [
        // 筛选栏（与截图/动态样式一致）
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing2,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '找到 ${_docCountingTotal ? '...' : _docTotalCount} 条内容',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_docCountingTotal) ...[
                      const SizedBox(width: AppTheme.spacing1),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              InkWell(
                onTap: _showDocTypeFilterSheet,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: AppTheme.spacing1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: hasTypeFilter
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune,
                        size: 16,
                        color: hasTypeFilter
                            ? Theme.of(context).colorScheme.primary
                            : AppTheme.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasTypeFilter ? '${activeTypes.length}类' : '类型',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasTypeFilter
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

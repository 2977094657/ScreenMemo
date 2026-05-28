part of 'screenshot_gallery_page.dart';

extension _ScreenshotGalleryGridPart on _ScreenshotGalleryPageState {
  Widget _buildBody() {
    // 搜索模式：优先显示搜索结果
    if (_searchQuery.isNotEmpty) {
      return _buildSearchResultGrid();
    }
    // 优先显示错误状态
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppTheme.destructive,
            ),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.destructive),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacing4),
            UIButton(
              text: AppLocalizations.of(context).actionRetry,
              onPressed: _loadInitialData,
              variant: UIButtonVariant.outline,
            ),
          ],
        ),
      );
    }

    // 如果有数据就直接显示网格+Tab栏，即使数据正在加载
    if (_screenshots.isNotEmpty || _isLoading) {
      return _buildTabsAndGrid();
    }

    // 只有在确实没有数据且不在加载时才显示空状态
    if (_screenshots.isEmpty && !_isLoading) {
      // 延迟显示空状态，给缓存加载一点时间
      return FutureBuilder(
        future: Future.delayed(const Duration(milliseconds: 300)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _screenshots.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: AppTheme.mutedForeground,
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    AppLocalizations.of(context).noScreenshotsTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  Text(
                    AppLocalizations.of(context).noScreenshotsSubtitle,
                    style: const TextStyle(color: AppTheme.mutedForeground),
                  ),
                ],
              ),
            );
          }
          // 加载中时显示空白，避免闪烁
          return const SizedBox.shrink();
        },
      );
    }

    return _buildTabsAndGrid();
  }

  Widget _buildSearchResultGrid() {
    final data = _searchResults;
    if (data.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context).noMatchingResults),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing1),
      child: RefreshIndicator(
        onRefresh: _loadScreenshots,
        child: GridView.builder(
          key: PageStorageKey<String>(
            'screenshot_gallery_search_${_packageName}',
          ),
          // 仅缓存当前视窗上下各一屏，超出即回收
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
          itemCount: data.length,
          itemBuilder: (context, index) {
            final s = data[index];
            return Stack(
              children: [
                _buildScreenshotItem(s, index),
                SearchMatchBoxesOverlay(boxesFuture: _ensureBoxes(s.filePath)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建顶部日期Tab栏 + 下方网格
  Widget _buildTabsAndGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 与 AppBar 内容左对齐：TabBar 自身通过 padding 控制左内边距
        Padding(
          padding: const EdgeInsets.only(left: 0, right: AppTheme.spacing1),
          child: _dayTabs.isEmpty || _tabController == null
              ? const SizedBox(height: 32)
              : SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: ScreenshotStyleTabBar(
                          controller: _tabController,
                          padding: const EdgeInsets.only(
                            left: AppTheme.spacing4,
                          ),
                          labelPadding: const EdgeInsets.only(
                            right: AppTheme.spacing6,
                          ),
                          tabs: _dayTabs
                              .map(
                                (t) => Tab(
                                  text: (() {
                                    final l = AppLocalizations.of(context);
                                    if (_DayTabInfo._isToday(t.day)) {
                                      return l.dayTabToday(t.count);
                                    }
                                    if (_DayTabInfo._isYesterday(t.day)) {
                                      return l.dayTabYesterday(t.count);
                                    }
                                    return l.dayTabMonthDayCount(
                                      t.day.month,
                                      t.day.day,
                                      t.count,
                                    );
                                  })(),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppTheme.spacing2,
                          right: AppTheme.spacing2,
                        ),
                        child: _buildDateCalendarButton(context),
                      ),
                    ],
                  ),
                ),
        ),
        // 日期Tab与内容之间增加1px底部外边距
        const SizedBox(height: 1),
        Expanded(
          child: _tabController == null
              ? _buildGalleryGrid()
              : TabBarView(
                  controller: _tabController,
                  physics: const ClampingScrollPhysics(),
                  children: _dayTabs.isEmpty
                      ? [_buildGalleryGridForIndex(0)]
                      : _dayTabs
                            .asMap()
                            .entries
                            .map(
                              (entry) => _buildGalleryGridForIndex(entry.key),
                            )
                            .toList(),
                ),
        ),
      ],
    );
  }

  /// 渲染指定索引Tab的网格：当前页使用主数据，非当前页使用缓存数据与独立控制器
  Widget _buildGalleryGridForIndex(int tabIndex) {
    final bool isCurrent = tabIndex == _currentTabIndex;
    final List<ScreenshotRecord> data = isCurrent
        ? _screenshots
        : List<ScreenshotRecord>.from(
            _tabCache[tabIndex] ?? const <ScreenshotRecord>[],
          );
    if (!isCurrent && data.isEmpty) {
      // 若缓存尚未就绪，展示轻量占位
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacing1),
          child: Container(
            key: isCurrent ? _gridKey : null,
            child: RefreshIndicator(
              onRefresh: _loadScreenshots,
              child: GridView.builder(
                key: PageStorageKey<String>(
                  'screenshot_gallery_grid_${_packageName}_tab_$tabIndex',
                ),
                controller: _controllerForTab(tabIndex),
                // 仅缓存当前视窗上下各一屏，超出即回收
                cacheExtent: MediaQuery.of(context).size.height,
                addAutomaticKeepAlives: false,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom:
                      MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppTheme.spacing1,
                  mainAxisSpacing: AppTheme.spacing1,
                  childAspectRatio: 0.45,
                ),
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final s = data[index];
                  return isCurrent
                      ? _buildScreenshotItem(s, index)
                      : _buildPreviewItem(s);
                },
              ),
            ),
          ),
        ),
        if (isCurrent && _dayTabs.length > 1) _buildTimelineOverlay(),
      ],
    );
  }

  /// 预览项：非交互，仅用于滑动时提前可见
  Widget _buildPreviewItem(ScreenshotRecord screenshot) {
    if (_baseDir == null) {
      return _buildErrorItem(AppLocalizations.of(context).appDirUninitialized);
    }

    return ScreenshotItemWidget(
      screenshot: screenshot,
      baseDir: _baseDir,
      appInfoMap: {_packageName: _appInfo},
      privacyMode: _privacyMode,
      // 预览项不可交互
      onTap: null,
    );
  }

  Widget _buildGalleryGrid() => _buildGalleryGridForIndex(_currentTabIndex);
}

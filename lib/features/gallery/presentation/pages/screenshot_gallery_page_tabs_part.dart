part of 'screenshot_gallery_page.dart';

extension _ScreenshotGalleryTabsPart on _ScreenshotGalleryPageState {
  ScrollController _controllerForTab(int index) {
    if (index < 0) index = 0;
    final existing = _tabControllers[index];
    if (existing != null) return existing;
    final initial = _tabScrollOffset[index] ?? 0.0;
    final ctrl = ScrollController(initialScrollOffset: initial);
    ctrl.addListener(() => _onScrollChangedForTab(ctrl, index));
    _tabControllers[index] = ctrl;
    return ctrl;
  }

  void _onScrollChangedForTab(ScrollController ctrl, int index) {
    // 刷新时间线位置（仅当前Tab）
    if (!_timelineActive && mounted && index == _currentTabIndex) {
      _gallerySetState(() {});
    }
    // 仅当前Tab触发加载更多
    if (index == _currentTabIndex &&
        _hasMore &&
        !_isLoadingMore &&
        ctrl.hasClients) {
      final maxScroll = ctrl.position.maxScrollExtent;
      final currentScroll = ctrl.position.pixels;
      final threshold = maxScroll * 0.8;
      if (currentScroll >= threshold) {
        _loadMoreScreenshots();
      }
    }
    // 记录滚动偏移
    try {
      if (ctrl.hasClients) {
        final double pos = ctrl.position.pixels;
        final double max = ctrl.position.hasPixels
            ? ctrl.position.maxScrollExtent
            : pos;
        final double clamped = pos.clamp(0.0, max);
        _tabScrollOffset[index] = clamped;
      }
    } catch (_) {}
  }

  Future<void> _prefetchFirstPageForTab(int index) async {
    if (!mounted) return;
    if (index < 0 || index >= _dayTabs.length) return;
    if ((_tabCache[index]?.isNotEmpty ?? false)) return;
    final day = _dayTabs[index];
    if (day.count <= 0) return;
    try {
      final batch = await ScreenshotService.instance.getScreenshotsByAppBetween(
        _packageName,
        startMillis: day.startMillis,
        endMillis: day.endMillis,
        limit: _ScreenshotGalleryPageState._initialPageSize,
        offset: 0,
      );
      // 二次过滤：严格限定同一天，且最多取 _ScreenshotGalleryPageState._initialPageSize
      final filtered = batch
          .where((r) => _DayTabInfo._isSameYMD(r.captureTime, day.day))
          .take(_ScreenshotGalleryPageState._initialPageSize)
          .toList();
      if (!mounted) return;
      _gallerySetState(() {
        _tabCache[index] = List<ScreenshotRecord>.from(filtered);
        _tabOffset[index] = filtered.length;
        _tabHasMore[index] = filtered.length < day.count;
        if (index == _currentTabIndex && _screenshots.isEmpty) {
          _screenshots = List<ScreenshotRecord>.from(filtered);
          _currentDisplayCount = _screenshots.length;
          _pageOffset = _tabOffset[index] ?? _screenshots.length;
          _hasMore = _tabHasMore[index] ?? false;
        }
      });
      // 预加载该批手动标记
      // ignore: unawaited_futures
      _preloadManualFlagsFor(filtered);
    } catch (_) {}
  }

  Future<void> _prefetchAllTabsFirst8() async {
    for (int i = 0; i < _dayTabs.length; i++) {
      // 顺序预取，避免并发压力
      await _prefetchFirstPageForTab(i);
    }
  }

  /// 当当前日期Tab被删空时，自动移除该Tab并跳转到上一可用日期
  Future<void> _switchAwayIfCurrentDayEmpty() async {
    if (!mounted) return;
    if (_tabController == null || _dayTabs.isEmpty) return;
    if (_currentTabIndex < 0 || _currentTabIndex >= _dayTabs.length) return;
    final int curCount = _dayTabs[_currentTabIndex].count;
    if (curCount > 0) return;

    // 清理当前Tab的缓存/滚动状态
    _tabCache.remove(_currentTabIndex);
    _tabOffset.remove(_currentTabIndex);
    _tabHasMore.remove(_currentTabIndex);
    _tabScrollOffset.remove(_currentTabIndex);

    final int oldIndex = _currentTabIndex;
    _tabController?.removeListener(_onTabControllerChanged);
    _tabController?.dispose();
    _tabController = null;

    _gallerySetState(() {
      // 移除当前已为空的日期Tab
      if (oldIndex >= 0 && oldIndex < _dayTabs.length) {
        _dayTabs.removeAt(oldIndex);
      }
      // 清空当前展示，等待切换
      _screenshots.clear();
      _currentDisplayCount = 0;
      _hasMore = true;
      _selectionMode = false;
      _isFullySelected = false;
      _selectedIds.clear();
    });

    if (_dayTabs.isNotEmpty) {
      final int newIndex = (oldIndex > 0) ? oldIndex - 1 : 0;
      final TabController ctrl = TabController(
        length: _dayTabs.length,
        vsync: this,
      );
      ctrl.addListener(_onTabControllerChanged);
      _gallerySetState(() {
        _tabController = ctrl;
        _currentTabIndex = (newIndex >= 0 && newIndex < _dayTabs.length)
            ? newIndex
            : 0;
        _tabController!.index = _currentTabIndex;
        _dateFilterStartMillis = _dayTabs[_currentTabIndex].startMillis;
        _dateFilterEndMillis = _dayTabs[_currentTabIndex].endMillis;
      });
      await _onTabIndexSelected(_currentTabIndex);
    } else {
      // 无任何日期Tab，允许显示空状态
      _gallerySetState(() {
        _tabController = null;
        _dateFilterStartMillis = null;
        _dateFilterEndMillis = null;
      });
    }
  }
}

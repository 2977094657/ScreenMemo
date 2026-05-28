part of 'screenshot_gallery_page.dart';

extension _ScreenshotGalleryDataPart on _ScreenshotGalleryPageState {
  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(text);
    });
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (!mounted) return;
    _gallerySetState(() {
      _searchQuery = q;
      _searchResults = <ScreenshotRecord>[];
    });
    if (q.isEmpty) return;
    try {
      final results = await ScreenshotService.instance
          .searchScreenshotsByOcrForApp(_packageName, q, limit: 400, offset: 0);
      if (!mounted) return;
      _gallerySetState(() {
        _searchResults = results;
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _ensureBoxes(String filePath) async {
    if (_searchQuery.isEmpty) return null;
    final key = '$filePath|$_searchQuery';
    final fut = _boxesFutureCache.putIfAbsent(key, () {
      return ScreenshotService.instance.getOcrMatchBoxes(
        filePath: filePath,
        query: _searchQuery,
      );
    });
    return fut;
  }

  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
      if (mounted)
        _gallerySetState(() {
          _privacyMode = enabled;
        });
    } catch (_) {}
  }

  String _dateKeyForDay(DateTime day) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
  }

  List<_DayTabInfo> _buildDayTabsFromRows(List<Map<String, dynamic>> rows) {
    final List<_DayTabInfo> tabs = <_DayTabInfo>[];
    for (final m in rows) {
      final String ds = (m['date'] as String?) ?? '';
      final int count = _readCount(m['count']);
      if (ds.isEmpty || count <= 0) continue;
      try {
        final parts = ds.split('-');
        if (parts.length != 3) continue;
        final int y = int.parse(parts[0]);
        final int mo = int.parse(parts[1]);
        final int d = int.parse(parts[2]);
        final DateTime day = DateTime(y, mo, d);
        final int start = DateTime(y, mo, d).millisecondsSinceEpoch;
        final int end = DateTime(y, mo, d, 23, 59, 59).millisecondsSinceEpoch;
        tabs.add(
          _DayTabInfo(
            day: day,
            startMillis: start,
            endMillis: end,
            count: count,
          ),
        );
      } catch (_) {}
    }
    tabs.sort((a, b) => b.startMillis.compareTo(a.startMillis));
    return tabs;
  }

  int _readCount(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// 基于“最新截图附近的有数据日期”生成 Tabs（倒序），默认仅展示最近14天，
  /// 当用户滑动/切换到最后一个可见日期时，再按批次追加更早日期。
  Future<void> _prepareDayTabs() async {
    if (!mounted) return;
    _gallerySetState(() {
      _isLoading = true;
    });
    List<_DayTabInfo> tabs = <_DayTabInfo>[];
    try {
      final int? latestMillis = await ScreenshotService.instance
          .getLatestCaptureTimeMillisForApp(_packageName);
      final DateTime base = (latestMillis == null || latestMillis <= 0)
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(latestMillis);
      final DateTime endDay = DateTime(base.year, base.month, base.day);
      final DateTime startDay = endDay.subtract(
        const Duration(
          days: _ScreenshotGalleryPageState._dayTabsLookbackDays - 1,
        ),
      );
      final rows = await ScreenshotService.instance
          .listAvailableDaysForAppRange(
            _packageName,
            startMillis: startDay.millisecondsSinceEpoch,
            endMillis: DateTime(
              endDay.year,
              endDay.month,
              endDay.day,
              23,
              59,
              59,
            ).millisecondsSinceEpoch,
          );
      tabs = _buildDayTabsFromRows(rows);

      // 旧库或异常统计下保底退回全量日期查询，避免误显示空列表。
      if (tabs.isEmpty) {
        final days = await ScreenshotService.instance.listAvailableDaysForApp(
          _packageName,
        );
        tabs = _buildDayTabsFromRows(days);
      }
    } catch (_) {}

    if (!mounted) return;
    _gallerySetState(() {
      _resetTabDataState();
      _allDayTabs
        ..clear()
        ..addAll(tabs);
      _hasMoreDayTabs = _allDayTabs.isNotEmpty;
      final int visibleCount = _allDayTabs.isEmpty
          ? 0
          : math.min(
              _ScreenshotGalleryPageState._initialVisibleDayTabs,
              _allDayTabs.length,
            );
      _dayTabs
        ..clear()
        ..addAll(_allDayTabs.take(visibleCount));

      _tabController?.removeListener(_onTabControllerChanged);
      _tabController?.dispose();
      if (_dayTabs.isNotEmpty) {
        _currentTabIndex = 0;
        _dateFilterStartMillis = _dayTabs[0].startMillis;
        _dateFilterEndMillis = _dayTabs[0].endMillis;
        _tabController = TabController(length: _dayTabs.length, vsync: this);
        _tabController!.addListener(_onTabControllerChanged);
      } else {
        _currentTabIndex = 0;
        _dateFilterStartMillis = null;
        _dateFilterEndMillis = null;
        _tabController = null;
      }
    });
    if (_dayTabs.isNotEmpty) {
      await _onTabIndexSelected(0);
      // ignore: unawaited_futures
      _prefetchAdjacentTabs(0);
    } else if (mounted) {
      _gallerySetState(() {
        _isLoading = false;
      });
    }
  }

  void _resetTabDataState() {
    _screenshots = <ScreenshotRecord>[];
    _currentDisplayCount = 0;
    _pageOffset = 0;
    _hasMore = true;
    _isLoadingMore = false;
    _tabCache.clear();
    _tabOffset.clear();
    _tabHasMore.clear();
    _tabScrollOffset.clear();
    _itemKeys.clear();
    for (final ScrollController controller in _tabControllers.values) {
      try {
        controller.dispose();
      } catch (_) {}
    }
    _tabControllers.clear();
  }

  void _onTabControllerChanged() {
    if (_tabController == null) return;
    if (_tabController!.indexIsChanging) return; // 避免重复
    final int idx = _tabController!.index;
    // 若当前已处于“最后一个可见日期Tab”，尝试向前扩展更多日期
    if (idx == _dayTabs.length - 1) {
      _expandDayTabsIfNeeded();
    }
    // 优先确保相邻Tab也有首屏缓存，提升滑动预览体验
    // ignore: unawaited_futures
    _prefetchAdjacentTabs(idx);
    _onTabIndexSelected(idx);
  }

  /// 当用户滑动到当前最后一个日期Tab附近时，尝试将可见窗口向前扩展14天
  void _expandDayTabsIfNeeded() {
    // ignore: discarded_futures
    _expandDayTabsIfNeededAsync();
  }

  Future<void> _expandDayTabsIfNeededAsync() async {
    if (!mounted) return;
    if (_isExpandingDayTabs) return;
    if (_dayTabs.isEmpty) return;

    _isExpandingDayTabs = true;
    try {
      if (_dayTabs.length >= _allDayTabs.length) {
        if (!_hasMoreDayTabs) return;
        final bool appended = await _appendOlderDayTabsToBuffer();
        if (!appended) return;
      }

      final int currentVisible = _dayTabs.length;
      final int targetVisible = math.min(
        _allDayTabs.length,
        currentVisible + _ScreenshotGalleryPageState._appendVisibleDayTabs,
      );
      if (targetVisible <= currentVisible) return;

      final int currentIndex = _tabController?.index ?? _currentTabIndex;

      _tabController?.removeListener(_onTabControllerChanged);
      _tabController?.dispose();

      _gallerySetState(() {
        _dayTabs
          ..clear()
          ..addAll(_allDayTabs.take(targetVisible));
      });

      _tabController = TabController(
        length: _dayTabs.length,
        vsync: this,
        initialIndex: currentIndex.clamp(0, _dayTabs.length - 1),
      );
      _tabController!.addListener(_onTabControllerChanged);
    } finally {
      _isExpandingDayTabs = false;
    }
  }

  Future<bool> _appendOlderDayTabsToBuffer() async {
    if (!mounted || _allDayTabs.isEmpty) return false;

    final DateTime oldest = _allDayTabs.last.day;
    final DateTime endDay = DateTime(
      oldest.year,
      oldest.month,
      oldest.day,
    ).subtract(const Duration(days: 1));
    final int endMillis = DateTime(
      endDay.year,
      endDay.month,
      endDay.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;

    int lookback = _ScreenshotGalleryPageState._dayTabsLookbackDays;
    for (int attempt = 0; attempt < 4; attempt += 1) {
      final int daysBack = lookback <= 0 ? 1 : lookback;
      final DateTime startDay = DateTime(
        endDay.year,
        endDay.month,
        endDay.day,
      ).subtract(Duration(days: daysBack - 1));
      final List<Map<String, dynamic>> rows = await ScreenshotService.instance
          .listAvailableDaysForAppRange(
            _packageName,
            startMillis: startDay.millisecondsSinceEpoch,
            endMillis: endMillis,
          );
      final List<_DayTabInfo> tabs = _buildDayTabsFromRows(rows);
      if (tabs.isNotEmpty) {
        final Set<String> existingKeys = _allDayTabs
            .map((tab) => _dateKeyForDay(tab.day))
            .toSet();
        final List<_DayTabInfo> append = tabs
            .where((tab) => !existingKeys.contains(_dateKeyForDay(tab.day)))
            .toList();
        if (append.isEmpty) return false;
        if (!mounted) return false;
        _gallerySetState(() {
          _allDayTabs.addAll(append);
          _allDayTabs.sort((a, b) => b.startMillis.compareTo(a.startMillis));
          _hasMoreDayTabs = true;
        });
        return true;
      }

      if (lookback >= 3650) break;
      lookback = math.min(3650, lookback * 3);
    }

    if (mounted) {
      _gallerySetState(() => _hasMoreDayTabs = false);
    }
    return false;
  }

  Future<void> _onTabIndexSelected(int index) async {
    if (index < 0 || index >= _dayTabs.length) return;
    if (_currentTabIndex == index && _screenshots.isNotEmpty) return;
    // 切换前保存旧Tab的滚动偏移
    try {
      if (_scrollController.hasClients) {
        _tabScrollOffset[_currentTabIndex] = _scrollController.position.pixels;
      }
    } catch (_) {}
    _gallerySetState(() {
      _currentTabIndex = index;
      _dateFilterStartMillis = _dayTabs[index].startMillis;
      _dateFilterEndMillis = _dayTabs[index].endMillis;
      // 切换时先从缓存展示，避免闪现上一页内容
      final cached = _tabCache[index];
      if (cached != null) {
        _screenshots = List<ScreenshotRecord>.from(cached);
        _currentDisplayCount = _screenshots.length;
        _hasMore = _tabHasMore[index] ?? false;
        _pageOffset = _tabOffset[index] ?? _screenshots.length;
      } else {
        _screenshots.clear();
        _currentDisplayCount = 0;
        _hasMore = true;
      }
      _selectedIds.clear();
      _isFullySelected = false;
    });
    // 预加载当前可见集的手动 NSFW 标记
    // ignore: unawaited_futures
    _preloadManualFlagsFor(_screenshots);
    await _refreshCurrentTabCount();
    // 若缺少首屏缓存，补一次加载；否则按需继续加载更多
    if ((_tabCache[index]?.isEmpty ?? true)) {
      await _loadScreenshots();
    } else if (_hasMore) {
      // 不阻塞UI，后台加载下一页
      // ignore: unawaited_futures
      _loadMoreScreenshots();
    }
    // 恢复新Tab的滚动偏移（若存在）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final ctrl = _controllerForTab(index);
        if (ctrl.hasClients) {
          final double restoreRaw = _tabScrollOffset[index] ?? 0.0;
          final double max = ctrl.position.maxScrollExtent;
          final double restore = restoreRaw.clamp(0.0, max);
          if (restore > 0) {
            ctrl.jumpTo(restore);
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _refreshCurrentTabCount() async {
    if (_currentTabIndex < 0 || _currentTabIndex >= _dayTabs.length) return;
    try {
      final c = await ScreenshotService.instance.getScreenshotCountByAppBetween(
        _packageName,
        startMillis: _dayTabs[_currentTabIndex].startMillis,
        endMillis: _dayTabs[_currentTabIndex].endMillis,
      );
      if (!mounted) return;
      _gallerySetState(() {
        _dayTabs[_currentTabIndex].count = c;
      });
    } catch (_) {}
  }

  void _onScrollChanged() {
    // 非交互状态下，同步刷新以更新时间线拇指位置
    if (!_timelineActive && mounted) {
      _gallerySetState(() {});
    }

    // 检查是否需要加载更多
    // 主控制器不再统一承载滚动监听（每Tab独立监听）
  }

  /// 加载更多截图到显示列表
  Future<void> _loadMoreScreenshots() async {
    if (_isLoadingMore || !_hasMore) return;
    if (!mounted) return;

    _gallerySetState(() {
      _isLoadingMore = true;
    });

    try {
      final int limit = _currentDisplayCount == 0
          ? _ScreenshotGalleryPageState._initialPageSize
          : _ScreenshotGalleryPageState._pageSize;
      List<ScreenshotRecord> batch = <ScreenshotRecord>[];
      if (_dateFilterStartMillis != null && _dateFilterEndMillis != null) {
        batch = await ScreenshotService.instance.getScreenshotsByAppBetween(
          _packageName,
          startMillis: _dateFilterStartMillis!,
          endMillis: _dateFilterEndMillis!,
          limit: limit,
          offset: _pageOffset,
        );
        // 二次过滤，避免跨日混入
        final day = _dayTabs[_currentTabIndex].day;
        batch = batch
            .where((r) => _DayTabInfo._isSameYMD(r.captureTime, day))
            .toList();
      } else {
        batch = await ScreenshotService.instance.getScreenshotsByApp(
          _packageName,
          limit: limit,
          offset: _pageOffset,
        );
      }

      if (!mounted) return;
      _gallerySetState(() {
        if (batch.isEmpty) {
          _hasMore = false;
        } else {
          // 追加并去重（按 id 去重）
          final existingIds = _screenshots
              .where((e) => e.id != null)
              .map((e) => e.id!)
              .toSet();
          for (final r in batch) {
            final id = r.id;
            if (id != null && existingIds.contains(id)) continue;
            _screenshots.add(r);
          }
          _pageOffset += batch.length;
          _currentDisplayCount = _screenshots.length;
          // 依据当前筛选（天）或全量决定是否还有更多
          int expectedTotal = _totalCount;
          if (_dateFilterStartMillis != null &&
              _dateFilterEndMillis != null &&
              _currentTabIndex >= 0 &&
              _currentTabIndex < _dayTabs.length) {
            expectedTotal = _dayTabs[_currentTabIndex].count;
          }
          _hasMore = _currentDisplayCount < expectedTotal;

          // 如果是全选状态，将新加载的项也加入选择
          if (_isFullySelected) {
            final newIds = _screenshots
                .where((s) => s.id != null && !_selectedIds.contains(s.id))
                .map((s) => s.id!)
                .toSet();
            _selectedIds.addAll(newIds);
          }

          // 缓存当前Tab内容，避免切换时回显旧页
          _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(
            _screenshots,
          );
          _tabOffset[_currentTabIndex] = _pageOffset;
          _tabHasMore[_currentTabIndex] = _hasMore;
          // 清理不在显示范围内的键
          _itemKeys.removeWhere((index, _) => index >= _screenshots.length);
        }
        _isLoadingMore = false;
      });
      // 预加载本批手动 NSFW 标记
      // ignore: unawaited_futures
      _preloadManualFlagsFor(batch);
    } catch (e) {
      if (!mounted) return;
      _gallerySetState(() {
        _isLoadingMore = false;
        _error = AppLocalizations.of(
          context,
        ).loadMoreFailedWithError(e.toString());
      });
    }
  }

  /// 构建标题栏右侧统计文本：X张 · Y.YYMB/GB/TB · 时间（本地化）
  String _buildHeaderStatsText() {
    final l10n = AppLocalizations.of(context);
    String timeStr = l10n.none;
    if (_latestTime != null) {
      timeStr = _formatDateTimeForStats(_latestTime!);
    }
    return '${l10n.imagesCountLabel(_totalCount)} · ${_formatTotalSizeMBGBTB(_totalSize)} · $timeStr';
  }

  /// 格式化时间（用于统计显示）
  String _formatDateTimeForStats(DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.daysAgo(diff.inDays);
    } else {
      final bool sameYear = now.year == dateTime.year;
      final String hh = dateTime.hour.toString().padLeft(2, '0');
      final String mm = dateTime.minute.toString().padLeft(2, '0');
      if (sameYear) {
        return l10n.monthDayTime(dateTime.month, dateTime.day, hh, mm);
      } else {
        return l10n.yearMonthDayTime(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          hh,
          mm,
        );
      }
    }
  }
}

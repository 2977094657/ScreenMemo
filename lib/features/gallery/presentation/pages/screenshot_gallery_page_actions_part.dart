part of 'screenshot_gallery_page.dart';

extension _ScreenshotGalleryActionsPart on _ScreenshotGalleryPageState {
  Future<void> _loadInitialData() async {
    try {
      // 使用PathService获取正确的外部文件目录
      final dir = await PathService.getInternalAppDir(null);

      if (dir == null) {
        throw Exception("无法获取应用目录");
      }

      print('路径服务返回的目录: ${dir.path}');

      _gallerySetState(() {
        _baseDir = dir;
      });
      await _loadScreenshots();
    } catch (e) {
      _gallerySetState(() {
        _error = AppLocalizations.of(context).initFailedWithError(e.toString());
      });
    }
  }

  Future<void> _loadScreenshots() async {
    try {
      print('=== 开始加载截图 ===');
      print('应用包名: $_packageName');
      print('基础目录: ${_baseDir?.path}');
      print('当前截图数量: ${_screenshots.length}');

      // 先设置加载状态，防止显示空状态
      if (_screenshots.isEmpty) {
        _gallerySetState(() {
          _isLoading = true;
        });
      }

      // 先获取统计，确定总量和最近时间、总大小
      try {
        final stats = await ScreenshotService.instance
            .getScreenshotStatsCachedFirst();
        final appStatsMap = stats['appStatistics'];
        if (appStatsMap is Map) {
          final dynamic raw = appStatsMap[_packageName];
          if (raw is Map) {
            _totalCount = (raw['totalCount'] as int?) ?? 0;
            final lc = raw['lastCaptureTime'];
            if (lc is DateTime) {
              _latestTime = lc;
            } else if (lc is int) {
              _latestTime = DateTime.fromMillisecondsSinceEpoch(lc);
            }
            _totalSize = (raw['totalSize'] as int?) ?? 0;
          }
        }
        if (_totalCount <= 0) {
          _totalCount = await ScreenshotService.instance
              .getScreenshotCountByApp(_packageName);
        }
      } catch (_) {
        // 统计失败不阻塞首屏，后续展示用默认值
      }

      // 重置分页并加载第一页
      _gallerySetState(() {
        _screenshots.clear();
        _currentDisplayCount = 0;
        _pageOffset = 0;
        _hasMore = _totalCount > 0;
      });

      await _loadMoreScreenshots();

      if (mounted) {
        _gallerySetState(() {
          _isLoading = false;
        });
      }
      // 预加载本页的手动 NSFW 标记缓存
      // ignore: unawaited_futures
      _preloadManualFlagsFor(_screenshots);
    } catch (e) {
      print('加载截图失败: $e');
      _gallerySetState(() {
        _error = '加载截图失败: $e';
        _isLoading = false;
      });
    }
  }

  // 旧的全量处理逻辑移除，统计在 _loadScreenshots 首次加载时已设置

  // 旧的“全量加载”函数已移除，改为真分页按需加载

  /// 从缓存加载截图数据
  Future<List<ScreenshotRecord>?> _loadScreenshotsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey =
          '${_ScreenshotGalleryPageState._screenshotsCacheKeyPrefix}$_packageName';
      final tsKey =
          '${_ScreenshotGalleryPageState._screenshotsCacheTsKeyPrefix}$_packageName';

      final cachedJson = prefs.getString(cacheKey);
      final ts = prefs.getInt(tsKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (cachedJson != null &&
          ts > 0 &&
          (now - ts) <=
              _ScreenshotGalleryPageState._screenshotsCacheTtlSeconds * 1000) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        return decoded.map((item) => ScreenshotRecord.fromMap(item)).toList();
      }
      return null;
    } catch (e) {
      print('从缓存加载截图失败: $e');
      return null;
    }
  }

  /// 保存截图数据到缓存
  Future<void> _saveScreenshotsToCache(
    List<ScreenshotRecord> screenshots,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey =
          '${_ScreenshotGalleryPageState._screenshotsCacheKeyPrefix}$_packageName';
      final tsKey =
          '${_ScreenshotGalleryPageState._screenshotsCacheTsKeyPrefix}$_packageName';

      final jsonList = screenshots.map((s) => s.toMap()).toList();
      await prefs.setString(cacheKey, jsonEncode(jsonList));
      await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('保存截图到缓存失败: $e');
    }
  }

  /// 后台刷新截图缓存
  Future<void> _refreshScreenshotsCache() async {
    try {
      // 分页场景：仅缓存当前已加载的前若干项，避免过大
      await _saveScreenshotsToCache(_screenshots);
    } catch (e) {
      print('后台刷新截图缓存失败: $e');
    }
  }

  /// 使截图缓存失效
  Future<void> _invalidateScreenshotsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey =
          '${_ScreenshotGalleryPageState._screenshotsCacheKeyPrefix}$_packageName';
      final tsKey =
          '${_ScreenshotGalleryPageState._screenshotsCacheTsKeyPrefix}$_packageName';

      await prefs.remove(cacheKey);
      await prefs.remove(tsKey);
      print('已使截图缓存失效: $cacheKey');
    } catch (e) {
      print('使截图缓存失效失败: $e');
    }
  }

  void _viewScreenshot(ScreenshotRecord screenshot, int index) {
    // 选择正确的数据集与索引（搜索模式使用搜索结果集）
    final List<ScreenshotRecord> data = _searchQuery.isNotEmpty
        ? _searchResults
        : _screenshots;
    int initialIndex = index;
    if (initialIndex < 0 ||
        initialIndex >= data.length ||
        (data[initialIndex].id != screenshot.id)) {
      final byId = data.indexWhere((s) => s.id == screenshot.id);
      if (byId >= 0) {
        initialIndex = byId;
      } else {
        final byPath = data.indexWhere(
          (s) => s.filePath == screenshot.filePath,
        );
        if (byPath >= 0) {
          initialIndex = byPath;
        } else {
          initialIndex = 0;
        }
      }
    }
    // 查看时使用全量数据，确保可以滑动查看所有图片
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        // 真分页：仅传当前已加载的截图集合
        'screenshots': data,
        'initialIndex': initialIndex,
        'appName': _appInfo.appName,
        'appInfo': _appInfo, // 传递完整的appInfo对象，包含图标
      },
    );
  }

  Future<void> _openAppScreenshotSettings() async {
    final Object? result = await Navigator.of(context).pushNamed(
      '/app_screenshot_settings',
      arguments: {'appInfo': _appInfo, 'packageName': _packageName},
    );
    if (!mounted || result is! int || result <= 0) return;
    _searchController.clear();
    _gallerySetState(() {
      _searchQuery = '';
      _searchResults.clear();
      _selectionMode = false;
      _selectedIds.clear();
      _isFullySelected = false;
      _screenshots.clear();
      _tabCache.clear();
      _tabOffset.clear();
      _tabHasMore.clear();
      _tabScrollOffset.clear();
      _itemKeys.clear();
    });
    await _invalidateScreenshotsCache();
    await _prepareDayTabs();
    await _loadScreenshots();
    if (!mounted) return;
    UINotifier.success(
      context,
      AppLocalizations.of(context).deletedCountToast(result),
    );
  }

  Future<void> _deleteScreenshot(ScreenshotRecord screenshot) async {
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: AppLocalizations.of(context).confirmDeleteTitle,
      message: AppLocalizations.of(context).confirmDeleteMessage,
      actions: [
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).dialogCancel,
          result: false,
        ),
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).actionDelete,
          style: UIDialogActionStyle.destructive,
          result: true,
        ),
      ],
      barrierDismissible: false,
    );

    if (confirmed == true && screenshot.id != null) {
      // 记录UI层删除请求日志（文件与原生）
      // ignore: unawaited_futures
      FlutterLogger.info(
        'UI.删除单图-发起 id=${screenshot.id} 包=${_appInfo.packageName} 路径=${screenshot.filePath}',
      );
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo(
        'UI',
        '删除截图 id=${screenshot.id} 包名=${_appInfo.packageName}',
      );
      try {
        final success = await ScreenshotService.instance.deleteScreenshot(
          screenshot.id!,
          _appInfo.packageName,
        );
        if (success) {
          // ignore: unawaited_futures
          FlutterLogger.info(
            'UI.删除单图-成功 id=${screenshot.id} 包=${_appInfo.packageName}',
          );
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo('UI', '删除截图成功 id=${screenshot.id}');
          _gallerySetState(() {
            _screenshots.removeWhere((s) => s.id == screenshot.id);
            _currentDisplayCount = _screenshots.length;
            if (_totalCount > 0) _totalCount -= 1;
            // 同步更新当前日期Tab计数
            if (_dayTabs.isNotEmpty &&
                _currentTabIndex >= 0 &&
                _currentTabIndex < _dayTabs.length) {
              final cur = _dayTabs[_currentTabIndex].count;
              _dayTabs[_currentTabIndex].count = (cur - 1).clamp(0, 1 << 31);
            }
          });
          // 删除后失效首页统计缓存
          await ScreenshotService.instance.invalidateStatsCache();
          // 删除后失效截图列表缓存
          await _invalidateScreenshotsCache();

          if (mounted) {
            UINotifier.success(
              context,
              AppLocalizations.of(context).screenshotDeletedToast,
            );
          }
        } else {
          // ignore: unawaited_futures
          FlutterLogger.warn(
            'UI.删除单图-失败 id=${screenshot.id} 包=${_appInfo.packageName}',
          );
          // ignore: unawaited_futures
          FlutterLogger.nativeWarn('UI', '删除截图失败 id=${screenshot.id}');
          if (mounted) {
            UINotifier.error(
              context,
              AppLocalizations.of(context).deleteFailed,
            );
          }
        }
      } catch (e) {
        // ignore: unawaited_futures
        FlutterLogger.error('UI.删除单图-异常: $e');
        // ignore: unawaited_futures
        FlutterLogger.nativeError('UI', '删除截图异常：$e');
        if (mounted) {
          UINotifier.error(
            context,
            AppLocalizations.of(context).deleteFailedWithError(e.toString()),
          );
        }
      }
    }
  }
}

part of 'screenshot_gallery_page.dart';

extension _ScreenshotGallerySelectionPart on _ScreenshotGalleryPageState {
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    // 检查是否选择了全部（基于当前筛选范围：当日或全量）
    int expectedTotal = _totalCount;
    if (_dateFilterStartMillis != null &&
        _dateFilterEndMillis != null &&
        _currentTabIndex >= 0 &&
        _currentTabIndex < _dayTabs.length) {
      expectedTotal = _dayTabs[_currentTabIndex].count;
    }
    final isSelectAll =
        _selectedIds.length >= expectedTotal && expectedTotal > 0;
    final int totalCount = expectedTotal;

    final String title = isSelectAll
        ? AppLocalizations.of(context).confirmDeleteAllTitle
        : AppLocalizations.of(context).confirmDeleteTitle;
    final String message = isSelectAll
        ? AppLocalizations.of(context).deleteAllMessage(expectedTotal)
        : AppLocalizations.of(
            context,
          ).deleteSelectedMessage(_selectedIds.length);

    final confirmed = await showUIDialog<bool>(
      context: context,
      title: title,
      message: message,
      actions: const [
        UIDialogAction<bool>(text: '取消', result: false),
        UIDialogAction<bool>(
          text: '删除',
          style: UIDialogActionStyle.destructive,
          result: true,
        ),
      ],
      barrierDismissible: false,
    );

    if (confirmed != true) return;

    // 记录UI层批量删除请求日志
    // ignore: unawaited_futures
    FlutterLogger.info(
      'UI.批量删除-发起 包=$_packageName 选择=${_selectedIds.length} 是否全删=$isSelectAll',
    );
    // ignore: unawaited_futures
    FlutterLogger.nativeInfo(
      'UI',
      '批量删除开始 数量=${_selectedIds.length} 是否全删=$isSelectAll',
    );

    final bool inDayScope =
        _dateFilterStartMillis != null &&
        _dateFilterEndMillis != null &&
        _currentTabIndex >= 0 &&
        _currentTabIndex < _dayTabs.length;

    if (isSelectAll && !inDayScope) {
      // 全删除模式：使用高效的文件夹删除
      final success = await ScreenshotService.instance
          .deleteAllScreenshotsForApp(_packageName);

      if (success) {
        // ignore: unawaited_futures
        FlutterLogger.info('UI.全删-成功 包=$_packageName 总数=$totalCount');
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('UI', '全删成功 总数=$totalCount');
        // 清空本地数据
        _gallerySetState(() {
          _screenshots.clear();
          _selectedIds.clear();
          _selectionMode = false;
          _isFullySelected = false; // 重置全选状态
          _totalCount = 0;
          _totalSize = 0;
          _latestTime = null;
          _currentDisplayCount = 0;
          _hasMore = false;
        });
        // 重新构建日期 Tabs（去除14天限制）
        await _prepareDayTabs();

        // 失效缓存
        await ScreenshotService.instance.invalidateStatsCache();
        await _invalidateScreenshotsCache();

        if (mounted) {
          UINotifier.success(
            context,
            AppLocalizations.of(context).deletedCountToast(totalCount),
          );
        }
      } else {
        // ignore: unawaited_futures
        FlutterLogger.warn('UI.全删-失败 包=$_packageName');
        // ignore: unawaited_futures
        FlutterLogger.nativeWarn('UI', '全删失败');
        if (mounted) {
          UINotifier.error(
            context,
            AppLocalizations.of(context).deleteFailedRetry,
          );
        }
      }
    } else {
      // 部分删除模式：根据保留比例触发“仅保留”快速删除
      final totalCount = _totalCount;
      final keepCount = totalCount - _selectedIds.length;
      final keepRatio = totalCount == 0 ? 1.0 : (keepCount / totalCount);

      // 阈值可后续做成设置项，这里先固定为10%
      const double thresholdKeepRatio = 0.1;

      bool usedFastKeepOnly = false;
      if (keepCount >= 0 && keepRatio <= thresholdKeepRatio) {
        // 选择删除大多数，仅保留极少数 -> 使用快速“仅保留”策略
        // 真分页模式无法可靠计算全量 keepIds，这里禁用快速“仅保留”路径
        final List<int> keepIds = const <int>[];

        // ignore: unawaited_futures
        FlutterLogger.info(
          'UI.fastDeleteKeepOnly start package=$_packageName keep=${keepIds.length} delete=${_selectedIds.length}',
        );
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('UI', '仅保留快速删除开始 保留=${keepIds.length}');
        usedFastKeepOnly = await ScreenshotService.instance.fastDeleteKeepOnly(
          packageName: _packageName,
          keepIds: keepIds,
          thresholdKeepRatio: thresholdKeepRatio,
        );
      }

      if (!usedFastKeepOnly) {
        // 使用批量删除API，显示进度
        final ids = List<int>.from(_selectedIds);
        // ignore: unawaited_futures
        FlutterLogger.info(
          'UI.批量删除-开始 包=${_appInfo.packageName} 数量=${ids.length}',
        );
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('UI', '批量删除开始 数量=${ids.length}');
        if (mounted) {
          UINotifier.showProgress(
            context,
            message: AppLocalizations.of(context).galleryDeleting,
            progress: null,
          );
        }

        // 为表现更流畅，这里分批提交给批量删除（数据库侧已分片），我们主要更新UI进度
        final successCount = await ScreenshotService.instance
            .deleteScreenshotsBatch(_appInfo.packageName, ids);
        if (mounted) {
          UINotifier.updateProgress(
            message: AppLocalizations.of(context).galleryCleaningCache,
            progress: 0.9,
          );
        }

        // 计算更准确的删除数量与日期Tab新计数（避免出现“删除0张”的提示）
        int deletedShown = successCount;
        int? newDayCount;
        if (_dayTabs.isNotEmpty &&
            _currentTabIndex >= 0 &&
            _currentTabIndex < _dayTabs.length &&
            _dateFilterStartMillis != null &&
            _dateFilterEndMillis != null) {
          final prev = _dayTabs[_currentTabIndex].count;
          try {
            final refreshed = await ScreenshotService.instance
                .getScreenshotCountByAppBetween(
                  _packageName,
                  startMillis: _dayTabs[_currentTabIndex].startMillis,
                  endMillis: _dayTabs[_currentTabIndex].endMillis,
                );
            newDayCount = refreshed;
            final delta = prev - refreshed;
            if (delta > 0) {
              deletedShown = delta;
            }
          } catch (_) {}
        }

        // 本地移除（从全量数据和显示数据中删除），并同步缓存与统计
        _gallerySetState(() {
          _screenshots.removeWhere(
            (s) => s.id != null && _selectedIds.contains(s.id),
          );
          final int minus = (newDayCount != null)
              ? ((_dayTabs[_currentTabIndex].count - newDayCount!).clamp(
                  0,
                  1 << 31,
                ))
              : _selectedIds.length;
          _totalCount = (_totalCount - minus).clamp(0, 1 << 31);
          _currentDisplayCount = _screenshots.length;
          _hasMore = _currentDisplayCount < _totalCount;
          _selectedIds.clear();
          _selectionMode = false;
          _isFullySelected = false; // 重置全选状态
          if (newDayCount != null) {
            _dayTabs[_currentTabIndex].count = newDayCount!;
          }
          // 同步当前Tab缓存，避免切换后才刷新
          _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(
            _screenshots,
          );
          _tabOffset[_currentTabIndex] = _currentDisplayCount;
          _tabHasMore[_currentTabIndex] = _hasMore;
        });

        // 若当前日期Tab已被删空，自动切换到上一可用日期
        await _switchAwayIfCurrentDayEmpty();

        // 缓存已在批量删除后统一刷新，这里只需失效本页面的截图缓存
        await _invalidateScreenshotsCache();
        if (mounted) {
          UINotifier.hideProgress();
        }
        if (mounted) {
          // ignore: unawaited_futures
          FlutterLogger.info('UI.批量删除-成功 删除数=' + deletedShown.toString());
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo(
            'UI',
            '批量删除成功 删除数=' + deletedShown.toString(),
          );
          UINotifier.success(
            context,
            AppLocalizations.of(context).deletedCountToast(deletedShown),
          );
        }
      } else {
        // 使用了“仅保留”快速删除：直接重载数据
        await ScreenshotService.instance.invalidateStatsCache();
        await _invalidateScreenshotsCache();

        // 重新加载当前应用截图（真分页）
        await _loadScreenshots();
        _gallerySetState(() {
          _selectedIds.clear();
          _selectionMode = false;
          _isFullySelected = false;
        });

        if (mounted) {
          // ignore: unawaited_futures
          FlutterLogger.info(
            'UI.仅保留-完成 保留=$keepCount 删除=${totalCount - keepCount}',
          );
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo('UI', '仅保留快速删除完成');
          UINotifier.success(
            context,
            AppLocalizations.of(
              context,
            ).keptAndDeletedSummary(keepCount, totalCount - keepCount),
          );
        }
      }
    }
  }

  Widget _buildErrorItem(String message) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.muted,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppTheme.destructive,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: AppTheme.destructive, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// 将字节格式化为最小MB，然后GB/TB
  String _formatTotalSizeMBGBTB(int bytes) {
    const double kb = 1024;
    const double mb = kb * 1024;
    const double gb = mb * 1024;
    const double tb = gb * 1024;

    if (bytes >= tb) {
      return (bytes / tb).toStringAsFixed(2) + 'TB';
    } else if (bytes >= gb) {
      return (bytes / gb).toStringAsFixed(2) + 'GB';
    } else {
      // 最小单位MB（包含 <1MB 的情况）
      return (bytes / mb).toStringAsFixed(2) + 'MB';
    }
  }

  /// 加载当前截图列表的收藏状态
  Future<void> _loadFavoriteStatus() async {
    if (_screenshots.isEmpty) return;

    try {
      final ids = _screenshots
          .where((s) => s.id != null)
          .map((s) => s.id!)
          .toList();

      if (ids.isEmpty) return;

      final statusMap = await FavoriteService.instance.checkFavorites(
        screenshotIds: ids,
        appPackageName: _packageName,
      );

      if (!mounted) return;
      _gallerySetState(() {
        _favoriteStatus.clear();
        _favoriteStatus.addAll(statusMap);
      });
    } catch (e) {
      print('加载收藏状态失败: $e');
    }
  }

  /// 切换收藏状态
  Future<void> _toggleFavorite(ScreenshotRecord screenshot) async {
    if (screenshot.id == null) return;

    try {
      final currentStatus = _favoriteStatus[screenshot.id] ?? false;
      final success = await FavoriteService.instance.toggleFavorite(
        screenshotId: screenshot.id!,
        appPackageName: screenshot.appPackageName,
      );

      if (success) {
        _gallerySetState(() {
          _favoriteStatus[screenshot.id!] = !currentStatus;
        });

        if (mounted) {
          UINotifier.success(
            context,
            currentStatus
                ? AppLocalizations.of(context).favoriteRemoved
                : AppLocalizations.of(context).favoriteAdded,
          );
        }
      } else if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      }
    } catch (e) {
      print('切换收藏状态失败: $e');
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).operationFailedWithError(e.toString()),
        );
      }
    }
  }

  // （测试截图生成功能已移除）

  Future<void> _preloadManualFlagsFor(List<ScreenshotRecord> data) async {
    try {
      final ids = data.where((s) => s.id != null).map((s) => s.id!).toList();
      // 1) 手动标记（按 app）
      if (ids.isNotEmpty) {
        await NsfwPreferenceService.instance.preloadManualFlags(
          appPackageName: _packageName,
          screenshotIds: ids,
        );
      }

      // 2) AI NSFW（按 file_path，全局复用）
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
    } catch (_) {}
    if (mounted) _gallerySetState(() {});
  }
}

part of 'screenshot_gallery_page.dart';

extension _ScreenshotGalleryItemPart on _ScreenshotGalleryPageState {
  Widget _buildScreenshotItem(ScreenshotRecord screenshot, int index) {
    if (_baseDir == null) {
      return _buildErrorItem(AppLocalizations.of(context).appDirUninitialized);
    }

    final isSelected =
        _selectionMode &&
        screenshot.id != null &&
        _selectedIds.contains(screenshot.id);
    final GlobalKey itemKey = _itemKeys.putIfAbsent(index, () => GlobalKey());
    final bool isNsfw = NsfwPreferenceService.instance.shouldMaskCached(
      screenshot,
    );
    final bool nsfwMasked = _privacyMode && isNsfw;
    // 手动标记状态（仅 DB）
    final bool isManualNsfw =
        screenshot.id != null &&
        NsfwPreferenceService.instance.isManuallyFlaggedCached(
          screenshotId: screenshot.id!,
          appPackageName: screenshot.appPackageName,
        );
    // UI 显示状态：全局统一展示（不依赖隐私模式开关）
    final bool isNsfwDisplay = isNsfw;

    final itemContent = ScreenshotItemWidget(
      screenshot: screenshot,
      baseDir: _baseDir,
      appInfoMap: {_packageName: _appInfo},
      privacyMode: _privacyMode,
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(index);
        } else {
          if (nsfwMasked) {
            _confirmRevealAndOpen(screenshot, index);
          } else {
            _viewScreenshot(screenshot, index);
          }
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          _gallerySetState(() => _selectionMode = true);
          _loadFavoriteStatus();
        }
        _toggleSelect(index);
      },
      onLinkTap: (url) => _showLinkDialogFromGrid(url),
      showCheckbox: _selectionMode,
      isSelected: isSelected,
      showFavoriteButton: _selectionMode && screenshot.id != null,
      isFavorited: _favoriteStatus[screenshot.id] ?? false,
      onFavoriteToggle: () => _toggleFavorite(screenshot),
      showNsfwButton: _selectionMode && screenshot.id != null,
      isNsfwFlagged: isNsfwDisplay,
      onNsfwToggle: () async {
        if (screenshot.id == null) return;
        // 若当前因域名规则/自动识别被遮罩，但未手动标记，则提示在设置中管理域名规则
        if (!isManualNsfw && isNsfw) {
          if (!mounted) return;
          UINotifier.info(
            context,
            AppLocalizations.of(context).nsfwBlockedByRulesHint,
          );
          return;
        }
        final newFlag = !isManualNsfw;
        final ok = await NsfwPreferenceService.instance.setManualFlag(
          screenshotId: screenshot.id!,
          appPackageName: screenshot.appPackageName,
          flag: newFlag,
        );
        if (!mounted) return;
        if (ok) {
          _gallerySetState(() {});
          final l10n = AppLocalizations.of(context);
          UINotifier.success(
            context,
            newFlag ? l10n.manualMarkSuccess : l10n.manualUnmarkSuccess,
          );
        } else {
          UINotifier.error(
            context,
            AppLocalizations.of(context).manualMarkFailed,
          );
        }
      },
    );

    return KeyedSubtree(key: itemKey, child: itemContent);
  }

  Future<void> _confirmRevealAndOpen(
    ScreenshotRecord screenshot,
    int index,
  ) async {
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: AppLocalizations.of(context).nsfwWarningTitle,
      message: AppLocalizations.of(context).nsfwWarningSubtitle,
      actions: [
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).dialogCancel,
          result: false,
        ),
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).actionContinue,
          style: UIDialogActionStyle.primary,
          result: true,
        ),
      ],
      barrierDismissible: true,
    );
    if (confirmed == true) {
      _viewScreenshot(screenshot, index);
    }
  }

  Future<void> _showLinkDialogFromGrid(String url) async {
    await showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).linkTitle,
      content: SelectableText(url, textAlign: TextAlign.center),
      barrierDismissible: true,
      actions: [
        UIDialogAction<void>(
          text: AppLocalizations.of(context).actionCopy,
          style: UIDialogActionStyle.primary,
          closeOnPress: true,
          onPressed: (ctx) async {
            try {
              await Clipboard.setData(ClipboardData(text: url));
              // ignore: unawaited_futures
              FlutterLogger.info('UI.网格-复制链接 成功');
              // ignore: unawaited_futures
              FlutterLogger.nativeInfo('UI', '网格复制链接成功');
              if (mounted) {
                UINotifier.success(
                  context,
                  AppLocalizations.of(context).copySuccess,
                );
              }
            } catch (e) {
              // ignore: unawaited_futures
              FlutterLogger.error('UI.网格-复制链接 失败: ' + e.toString());
              // ignore: unawaited_futures
              FlutterLogger.nativeError('UI', '网格复制链接失败：' + e.toString());
              if (mounted) {
                UINotifier.error(
                  context,
                  AppLocalizations.of(context).copyFailed,
                );
              }
            }
          },
        ),
        UIDialogAction<void>(
          text: AppLocalizations.of(context).actionOpen,
          style: UIDialogActionStyle.normal,
          closeOnPress: true,
          onPressed: (ctx) async {
            try {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (_) {}
          },
        ),
        UIDialogAction<void>(
          text: AppLocalizations.of(context).dialogCancel,
          style: UIDialogActionStyle.normal,
          closeOnPress: true,
        ),
      ],
    );
  }

  // 构建右侧时间线滚动条与时间提示
  Widget _buildTimelineOverlay() {
    if (_screenshots.isEmpty || _screenshots.length < 2) {
      return const SizedBox.shrink();
    }

    const double gestureWidth = 44; // 右侧可交互区域宽度
    const double trackWidth = 3; // 可见轨道宽度
    const double thumbHeight = 32; // 拇指高度
    const double labelHeight = 28; // 时间标签高度（用于定位）

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double viewHeight = constraints.maxHeight;
          // 与网格保持一致的底部边距：外层 Padding + GridView 的 bottom padding
          final double bottomMargin =
              MediaQuery.of(context).padding.bottom +
              AppTheme.spacing6 +
              AppTheme.spacing1;
          final double trackHeight = (viewHeight - bottomMargin).clamp(
            0,
            viewHeight,
          );

          // 增加安全检查，避免异常计算（使用当前Tab的controller）
          final ctrl = _controllerForTab(_currentTabIndex);
          if (trackHeight <= 0 || !ctrl.hasClients) {
            return const SizedBox.shrink();
          }

          final double currentFraction = _timelineActive
              ? _timelineFraction
              : _currentScrollFraction();
          final double clampedFraction = currentFraction.clamp(0.0, 1.0);
          final double thumbTop =
              clampedFraction *
              (trackHeight - thumbHeight).clamp(0, trackHeight);

          final int firstVisibleIndex = _timelineActive
              ? _approxIndexFromFraction()
              : _getFirstVisibleIndex();
          final String timeLabel =
              (firstVisibleIndex >= 0 &&
                  firstVisibleIndex < _screenshots.length)
              ? _formatTimelineTime(_screenshots[firstVisibleIndex].captureTime)
              : '';

          return Stack(
            children: [
              // 交互区域 - 只占右侧44像素，避免影响主要内容区域
              Positioned(
                right: 0,
                top: 0,
                bottom: bottomMargin,
                width: gestureWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // 防止手势冲突，增加边界检查
                  onVerticalDragStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onVerticalDragEnd: (_) {
                    if (mounted) {
                      _gallerySetState(() {
                        _timelineActive = false;
                      });
                    }
                    _maybeLoadAfterScrub();
                  },
                  onLongPressStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onLongPressMoveUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onLongPressEnd: (_) {
                    if (mounted) {
                      _gallerySetState(() {
                        _timelineActive = false;
                      });
                    }
                    _maybeLoadAfterScrub();
                  },
                  child: Stack(
                    children: [
                      // 轨道
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: trackWidth,
                          margin: EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // 拇指（与轨道右对齐）
                      Positioned(
                        right: 0,
                        top: thumbTop,
                        child: Container(
                          width: trackWidth,
                          height: thumbHeight,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade600,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_timelineActive)
                Positioned(
                  right: gestureWidth + 8,
                  top: (clampedFraction * (trackHeight - labelHeight)).clamp(
                    0,
                    trackHeight - labelHeight,
                  ),
                  child: Container(
                    height: labelHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6), // 小圆角，无阴影
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // 激活时间线并根据手指位置滚动
  void _activateTimelineWithLocalY(double localY, double viewHeight) {
    // 增加安全检查
    final ctrl = _controllerForTab(_currentTabIndex);
    if (viewHeight <= 0 || !ctrl.hasClients || !mounted) return;

    final double raw = localY / viewHeight;
    final double fraction = raw.clamp(0.0, 1.0);

    _gallerySetState(() {
      _timelineActive = true;
      _timelineFraction = fraction;
    });
    _scheduleScrubJump();
  }

  // 当前滚动位置归一化 [0,1]
  double _currentScrollFraction() {
    final ctrl = _controllerForTab(_currentTabIndex);
    if (!ctrl.hasClients) return 0.0;
    final maxExtent = ctrl.position.maxScrollExtent;
    if (maxExtent <= 0) return 0.0;
    final pixels = ctrl.position.pixels;
    final double f = pixels / maxExtent;
    return f.clamp(0.0, 1.0);
  }

  // 滚动到对应归一化位置
  void _scrollToFraction(double fraction) {
    final ctrl = _controllerForTab(_currentTabIndex);
    if (!ctrl.hasClients || !mounted) return;
    final maxExtent = ctrl.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final target = fraction.clamp(0.0, 1.0) * maxExtent;
    ctrl.jumpTo(target);
  }

  // 拖动时用 fraction 近似当前索引，避免在大量 GlobalKey 上做布局查询
  int _approxIndexFromFraction() {
    if (_screenshots.isEmpty) return 0;
    final double f = _timelineFraction.clamp(0.0, 1.0);
    final int last = _screenshots.length - 1;
    final int idx = (f * last).round();
    return idx.clamp(0, last);
  }

  // 将 jumpTo 合并到每帧一次，降低拖动过程中的重排与抖动
  void _scheduleScrubJump() {
    if (_scrubJumpScheduled) return;
    _scrubJumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrubJumpScheduled = false;
      if (!mounted) return;
      final ctrl = _controllerForTab(_currentTabIndex);
      if (!ctrl.hasClients) return;
      final maxExtent = ctrl.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      final double f = _timelineFraction.clamp(0.0, 1.0);
      final double target = f * maxExtent;
      if ((ctrl.position.pixels - target).abs() > 0.5) {
        ctrl.jumpTo(target);
      }
    });
  }

  // 拖动结束后按需加载一批，避免在拖动过程中频繁 setState 卡顿
  void _maybeLoadAfterScrub() {
    if (!mounted) return;
    if (_hasMore && !_isLoadingMore && _timelineFraction >= 0.98) {
      // ignore: unawaited_futures
      _loadMoreScreenshots();
    }
  }

  Rect? _getGridViewportRect() {
    if (!mounted) return null;
    final ctx = _gridKey.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  // 计算当前视口内第一张可见截图的索引
  int _getFirstVisibleIndex() {
    if (!mounted || _screenshots.isEmpty || _itemKeys.isEmpty) return 0;

    final viewport = _getGridViewportRect();
    if (viewport == null) return 0;

    int? firstIdx;
    double? minTop;

    _itemKeys.forEach((index, key) {
      // 增加边界检查
      if (index >= _screenshots.length) return;

      final context = key.currentContext;
      if (context == null) return;

      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;

      try {
        final rect = render.localToGlobal(Offset.zero) & render.size;
        final bool visible =
            rect.bottom > viewport.top && rect.top < viewport.bottom;
        if (!visible) return;

        if (minTop == null || rect.top < minTop!) {
          minTop = rect.top;
          firstIdx = index;
        }
      } catch (e) {
        // 忽略布局异常，继续处理其他项
        return;
      }
    });

    return (firstIdx != null && firstIdx! < _screenshots.length)
        ? firstIdx!
        : 0;
  }

  // 时间线标签格式化（当天/本年/跨年）
  String _formatTimelineTime(DateTime dateTime) {
    final now = DateTime.now();
    final t = AppLocalizations.of(context);
    final bool sameDay =
        now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;
    final bool sameYear = now.year == dateTime.year;
    final String hh = dateTime.hour.toString().padLeft(2, '0');
    final String mm = dateTime.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$hh:$mm';
    } else if (sameYear) {
      return t.monthDayTime(dateTime.month, dateTime.day, hh, mm);
    } else {
      return t.yearMonthDayTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        hh,
        mm,
      );
    }
  }

  /// 获取全选按钮文本
  String _getSelectAllButtonText() {
    return _isFullySelected
        ? AppLocalizations.of(context).clearAll
        : AppLocalizations.of(context).selectAll;
  }

  void _toggleSelect(int index) {
    if (index < 0 || index >= _screenshots.length) return;
    final id = _screenshots[index].id;
    if (id == null) return;
    _gallerySetState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
        // 如果取消选择了某项，就不再是全选状态
        _isFullySelected = false;
      } else {
        _selectedIds.add(id);
        // 基于当前筛选范围（当日或全量）判断是否达到“全选”
        int expectedTotal = _totalCount;
        if (_dateFilterStartMillis != null &&
            _dateFilterEndMillis != null &&
            _currentTabIndex >= 0 &&
            _currentTabIndex < _dayTabs.length) {
          expectedTotal = _dayTabs[_currentTabIndex].count;
        }
        _isFullySelected =
            expectedTotal > 0 && _selectedIds.length >= expectedTotal;
      }
    });
  }

  void _hitSelectAtPosition(Offset globalPosition) {
    // 命中检测：遍历可见项，若指针在其区域内则选中
    _itemKeys.forEach((index, key) {
      final context = key.currentContext;
      if (context == null) return;
      final render = context.findRenderObject();
      if (render is! RenderBox) return;
      final topLeft = render.localToGlobal(Offset.zero);
      final rect = topLeft & render.size;
      if (rect.contains(globalPosition)) {
        _toggleSelect(index);
      }
    });
  }
}

part of 'home_page.dart';

extension _HomePageContentPart on _HomePageState {
  String _themeModeTooltip(BuildContext context) {
    final mode = widget.themeService.themeMode;
    final t = AppLocalizations.of(context);
    switch (mode) {
      case ThemeMode.system:
        return t.themeModeAuto;
      case ThemeMode.light:
        return t.themeModeLight;
      case ThemeMode.dark:
        return t.themeModeDark;
    }
  }

  /// 构建副导航栏：统计信息 + 排序菜单
  Widget _buildSubNavigation() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appCount = _totals['app_count'] as int? ?? 0;
    final screenshotCount = _totals['screenshot_count'] as int? ?? 0;
    final totalSizeBytes = _totals['total_size_bytes'] as int? ?? 0;
    final dayCount = _totals['day_count'] as int? ?? 0;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing6,
        vertical: AppTheme.spacing2,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 左侧：统计信息
          Expanded(
            child: Row(
              children: [
                // 监测天数
                Text(
                  '$dayCount${l10n.days}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                // 应用数量
                Text(
                  '${appCount}${l10n.apps}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                // 截图数量
                Text(
                  '${screenshotCount}${l10n.images}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                // 文件大小
                Text(
                  _formatFileSize(totalSizeBytes),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // 右侧：排序菜单
          InkWell(
            onTap: _cycleSortField,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getSortFieldLabel(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: _toggleSortOrder,
                  child: Icon(
                    _sortOrderAsc ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 获取当前排序字段的显示标签
  String _getSortFieldLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_sortMode) {
      case 'time':
      case 'timeAsc':
      case 'timeDesc':
        return l10n.sortFieldTime;
      case 'count':
      case 'countAsc':
      case 'countDesc':
        return l10n.sortFieldCount;
      case 'size':
      case 'sizeAsc':
      case 'sizeDesc':
        return l10n.sortFieldSize;
      default:
        return l10n.sortFieldTime;
    }
  }

  Widget _buildSearchBar(BuildContext context) {
    final Color fillColor = SearchStyles.fieldFillColor(context);
    // Keep border style consistent with Screenshot Gallery search box.
    final Color borderColor = SearchStyles.fieldBorderColor(context);
    return InkWell(
      borderRadius: SearchStyles.fieldBorderRadius,
      onTap: () => Navigator.pushNamed(context, '/search'),
      child: Container(
        height: SearchStyles.fieldHeight,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: SearchStyles.fieldBorderRadius,
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(
              Icons.search,
              color: SearchStyles.placeholderColor(context),
              size: 18,
            ),
            const SizedBox(width: 2),
            Text(
              AppLocalizations.of(context).searchPlaceholder,
              style: SearchStyles.hintTextStyle(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppsList(ScrollPhysics physics) {
    final bool hasApps = _selectedApps.isNotEmpty;
    final bool showInitialLoading = _isLoading && !hasApps;
    return CustomScrollView(
      physics: physics,
      slivers: [
        if (hasApps)
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing2,
              vertical: AppTheme.spacing1,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final app = _selectedApps[index];
                return _buildAppListItem(app, index);
              }, childCount: _selectedApps.length),
            ),
          )
        else if (showInitialLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: UILoadingState(
              compact: true,
              showIndicatorBackground: false,
            ),
          )
        else
          SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
        if (hasApps)
          SliverToBoxAdapter(child: SizedBox(height: AppTheme.spacing4)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.apps,
          size: 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: AppTheme.spacing4),
        Text(
          AppLocalizations.of(context).homeEmptyTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacing2),
        Text(
          AppLocalizations.of(context).homeEmptySubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _resolveMorningTipText(AppLocalizations l10n) {
    if (_morningCooldownMessage != null) {
      if (_morningCooldownUntil != null &&
          DateTime.now().isBefore(_morningCooldownUntil!)) {
        return _morningCooldownMessage!;
      } else {
        _morningCooldownMessage = null;
        _morningCooldownUntil = null;
      }
    }
    final MorningInsightEntry? tip =
        _currentMorningTip ??
        ((_morningInsights?.tips.isNotEmpty ?? false)
            ? _morningInsights!.tips.first
            : null);
    if (tip == null) {
      final bool hasInsights = _morningInsights?.tips.isNotEmpty ?? false;
      return hasInsights
          ? l10n.homeMorningTipsPullHint
          : l10n.homeMorningTipsEmpty;
    }
    if (tip.hasSummary) return tip.summary!;
    if (tip.actions.isNotEmpty) return tip.actions.first;
    if (tip.displayTitle.isNotEmpty) return tip.displayTitle;
    return l10n.homeMorningTipsPullHint;
  }

  bool _isMorningInsightsAvailable(DateTime now) {
    if (now.hour > _HomePageState._morningAvailableHour) {
      return true;
    }
    if (now.hour < _HomePageState._morningAvailableHour) {
      return false;
    }
    return true;
  }

  Header _buildMorningHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return BuilderHeader(
      position: IndicatorPosition.above,
      triggerOffset: _HomePageState._morningRevealMaxHeight,
      clamping: false,
      builder: (context, state) {
        double visibleHeight = state.offset.clamp(
          0.0,
          _HomePageState._morningRevealMaxHeight,
        );
        final bool isProcessing =
            state.mode == IndicatorMode.processing ||
            state.mode == IndicatorMode.ready;
        if (isProcessing) {
          visibleHeight = _HomePageState._morningRevealMaxHeight;
        }
        if (visibleHeight <= 0) {
          return const SizedBox.shrink();
        }

        final double progress =
            (visibleHeight / _HomePageState._morningRevealMaxHeight).clamp(
              0.0,
              1.0,
            );
        final bool readyToRelease = state.mode == IndicatorMode.armed;
        final colorScheme = theme.colorScheme;
        final bool inCooldown =
            _morningCooldownUntil != null &&
            DateTime.now().isBefore(_morningCooldownUntil!);
        final bool suppressHint = !_isMorningInsightsAvailable(DateTime.now());

        final Widget icon = AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isProcessing
              ? SizedBox(
                  key: const ValueKey('loading_icon'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onSurface,
                  ),
                )
              : AnimatedRotation(
                  key: ValueKey(readyToRelease ? 'arrow_up' : 'arrow_down'),
                  turns: readyToRelease ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color: colorScheme.onSurface,
                  ),
                ),
        );

        final String hint = readyToRelease
            ? l10n.homeMorningTipsReleaseHint
            : (inCooldown
                  ? l10n.homeMorningTipsCooldownHint
                  : (isProcessing
                        ? l10n.homeMorningTipsLoading
                        : l10n.homeMorningTipsPullHint));

        final String message = _resolveMorningTipText(l10n);

        return SizedBox(
          height: visibleHeight,
          child: ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Opacity(
                opacity: isProcessing ? 1.0 : progress,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: AppTheme.spacing1),
                    if (!suppressHint) ...[
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing1),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                      ),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  BorderRadius _buildAppListItemRadius(AppInfo app, int index) {
    if (app.isInstalled) {
      return BorderRadius.circular(AppTheme.radiusMd);
    }
    final bool hasPrevUninstalled =
        index > 0 && !_selectedApps[index - 1].isInstalled;
    final bool hasNextUninstalled =
        index + 1 < _selectedApps.length &&
        !_selectedApps[index + 1].isInstalled;
    final Radius topRadius = Radius.circular(
      hasPrevUninstalled ? 0 : AppTheme.radiusMd,
    );
    final Radius bottomRadius = Radius.circular(
      hasNextUninstalled ? 0 : AppTheme.radiusMd,
    );
    return BorderRadius.only(
      topLeft: topRadius,
      topRight: topRadius,
      bottomLeft: bottomRadius,
      bottomRight: bottomRadius,
    );
  }

  Widget _buildAppListItem(AppInfo app, int index) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool selectable = _isAppSelectable(app);
    final bool isSelected =
        selectable &&
        _selectionMode &&
        _selectedPackages.contains(app.packageName);
    final BorderRadius itemRadius = _buildAppListItemRadius(app, index);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_selectionMode && selectable) {
            _toggleSelect(app.packageName);
          } else {
            _onAppTap(app);
          }
        },
        onLongPress: selectable
            ? () {
                if (!_selectionMode) {
                  _homeSetState(() => _selectionMode = true);
                }
                _toggleSelect(app.packageName);
              }
            : null,
        borderRadius: itemRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing4,
            vertical: AppTheme.spacing2,
          ),
          decoration: BoxDecoration(
            color: app.isInstalled
                ? Colors.transparent
                : cs.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: itemRadius,
          ),
          child: Row(
            children: [
              // 应用图标 + 自定义标记徽章
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: app.icon != null
                          ? Image.memory(
                              app.icon!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: app.isInstalled
                                    ? cs.surfaceContainerHighest
                                    : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: app.isInstalled
                                  ? Icon(
                                      Icons.android,
                                      color: cs.onSurfaceVariant,
                                      size: 32,
                                    )
                                  : Text(
                                      _appInitial(app),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                            ),
                    ),
                    if (_customEnabledPackages.contains(app.packageName))
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Tooltip(
                          message: AppLocalizations.of(context).customLabel,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.surface,
                                width: 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.tune,
                              size: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: AppTheme.spacing3),

              // 应用信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.appName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: app.isInstalled ? null : cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _getAppStatText(app.packageName),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: app.isInstalled
                            ? cs.onSurfaceVariant
                            : cs.onSurfaceVariant.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),

              if (!app.isInstalled) ...[
                const SizedBox(width: AppTheme.spacing2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade500.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Text(
                    '未安装',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              if (!_selectionMode || !selectable)
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
              else
                SelectionCheckbox(selected: isSelected),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取应用统计文本
  String _getAppStatText(String packageName) {
    final l10n = AppLocalizations.of(context);
    final appStats =
        _screenshotStats['appStatistics']
            as Map<String, Map<String, dynamic>>? ??
        {};
    final stat = appStats[packageName];

    if (stat == null) {
      return '${l10n.imagesCountLabel(0)} · ${_formatTotalSizeMBGBTB(0)} · ${l10n.none}';
    }

    final count = stat['totalCount'] as int? ?? 0;
    final lastTime = stat['lastCaptureTime'] as DateTime?;
    final totalBytes = stat['totalSize'] as int? ?? 0;

    String timeStr = l10n.none;
    if (lastTime != null) {
      final now = DateTime.now();
      final diff = now.difference(lastTime);

      if (diff.inMinutes < 1) {
        timeStr = l10n.justNow;
      } else if (diff.inHours < 1) {
        timeStr = l10n.minutesAgo(diff.inMinutes);
      } else if (diff.inDays < 1) {
        timeStr = l10n.hoursAgo(diff.inHours);
      } else {
        timeStr = l10n.daysAgo(diff.inDays);
      }
    }

    return '${l10n.imagesCountLabel(count)} · ${_formatTotalSizeMBGBTB(totalBytes)} · $timeStr';
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

  /// 格式化文件大小，支持B/KB/MB/GB单位，保留两位小数
  String _formatFileSize(int bytes) {
    const double kb = 1024;
    const double mb = kb * 1024;
    const double gb = mb * 1024;
    const double tb = gb * 1024;

    if (bytes >= tb) {
      return '${(bytes / tb).toStringAsFixed(2)}TB';
    } else if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)}GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)}MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(2)}KB';
    } else {
      return '${bytes}B';
    }
  }
}

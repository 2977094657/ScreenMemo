part of 'home_page.dart';

extension _HomePageDataPart on _HomePageState {
  Future<void> _loadStats() async {
    StartupProfiler.begin('HomePage._loadStats');
    // 首页允许首帧走统计缓存
    final stats = await ScreenshotService.instance
        .getScreenshotStatsCachedFirst();
    // 日志：记录缓存签名与缓存来源
    // ignore: unawaited_futures
    FlutterLogger.log(
      'home.loadStats 缓存优先 -> 总数=${stats['totalScreenshots']}，今日=${stats['todayScreenshots']}',
    );
    if (mounted) {
      _homeSetState(() {
        _screenshotStats = stats;
      });
      _sortApps();
      // 首帧后立刻做一次数据库对比校验，若不一致则自动刷新
      // 不依赖统计缓存，也不受同步节流影响
      // ignore: unawaited_futures
      _verifyAndRefreshStatsIfStale();
    }
    StartupProfiler.end('HomePage._loadStats');
  }

  /// 强制从数据库计算并刷新缓存，然后更新UI
  Future<void> _loadStatsFresh() async {
    StartupProfiler.begin('HomePage._loadStatsFresh');
    // 不再依赖统计缓存，也不受文件同步节流影响
    final stats = await ScreenshotService.instance.getScreenshotStatsFresh();
    if (mounted) {
      _homeSetState(() {
        _screenshotStats = stats;
      });
      _sortApps();
      // 刷新后同步更新首页统计缓存
      // ignore: unawaited_futures
      ScreenshotService.instance.updateStatsCache(stats);
    }
    StartupProfiler.end('HomePage._loadStatsFresh');
  }

  /// 加载汇总统计
  Future<void> _loadTotals() async {
    try {
      final totals = await ScreenshotService.instance.getTotals();
      final prevDayCount = _totals['day_count'] as int? ?? 0;
      if (mounted) {
        _homeSetState(() {
          _totals = Map<String, dynamic>.from(totals)
            ..['day_count'] = prevDayCount;
        });
      }
      _updateDayCount();
    } catch (e) {
      print('加载汇总统计失败: $e');
      _updateDayCount();
    }
  }

  void _updateDayCount({bool forceRefresh = false}) {
    // ignore: discarded_futures
    ScreenshotService.instance
        .getAvailableDayCountCachedFirst(forceRefresh: forceRefresh)
        .then((count) {
          if (!mounted) return;
          _homeSetState(() {
            _totals = Map<String, dynamic>.from(_totals)..['day_count'] = count;
          });
        })
        .catchError((_) {
          // 忽略缓存更新失败，保持现有值
        });
  }

  /// 计算当前统计数据的签名，用于快速判断是否需要刷新UI
  String _computeStatsSignature(Map<String, dynamic> stats) {
    final int total = (stats['totalScreenshots'] as int?) ?? 0;
    final int lastTs = (stats['lastScreenshotTime'] as int?) ?? 0;
    final appStats =
        stats['appStatistics'] as Map<String, Map<String, dynamic>>? ?? {};

    int appsCount = appStats.length;
    int sumCount = 0;
    int sumSize = 0;
    int maxLast = 0;

    for (final entry in appStats.entries) {
      final map = entry.value;
      final int c = (map['totalCount'] as int?) ?? 0;
      final int s = (map['totalSize'] as int?) ?? 0;
      final DateTime? t = map['lastCaptureTime'] as DateTime?;
      final int ts = t?.millisecondsSinceEpoch ?? 0;
      sumCount += c;
      sumSize += s;
      if (ts > maxLast) maxLast = ts;
    }

    return '$total|$lastTs|$appsCount|$sumCount|$sumSize|$maxLast';
  }

  /// 校验当前展示与数据库最新统计是否一致，不一致则用最新统计刷新
  Future<void> _verifyAndRefreshStatsIfStale() async {
    try {
      final String currentSig = _computeStatsSignature(_screenshotStats);
      final fresh = await ScreenshotService.instance.getScreenshotStatsFresh();
      final String freshSig = _computeStatsSignature(fresh);
      if (currentSig != freshSig && mounted) {
        _homeSetState(() {
          _screenshotStats = fresh;
        });
        _sortApps();
        // 同步更新首页统计缓存，避免下次冷启动或返回时先看到旧缓存
        // ignore: unawaited_futures
        ScreenshotService.instance.updateStatsCache(fresh);
      }
    } catch (e) {
      // 静默失败，不打断首帧体验
    }
  }

  Future<void> _loadData({bool soft = true}) async {
    StartupProfiler.begin('HomePage._loadData');
    // 始终走软刷新：不触发全屏加载动画
    if (mounted && _selectedApps.isEmpty) {
      _homeSetState(() {
        _isLoading = true;
      });
    }

    try {
      // 统计信息与应用安装列表互不依赖，先并发启动，避免首页顶部长时间显示 0。
      final Future<void> earlyTotalsFuture = _loadTotals();
      final Future<void> earlyStatsFuture = _loadStats();

      // 先加载用户设置和已保存的监控应用，避免已安装应用扫描拖慢首屏列表。
      final selectedApps = await _appService.getSelectedApps();
      final cachedAppsByPackage = await _appService.getCachedAppInfoByPackage();
      final sortMode = await _appService.getSortMode();
      final screenshotEnabled = await _appService.getScreenshotEnabled();
      final screenshotInterval = await _appService.getScreenshotInterval();

      if (mounted) {
        _homeSetState(() {
          _savedSelectedApps = List<AppInfo>.from(selectedApps);
          _cachedAppsByPackage = cachedAppsByPackage;
          _selectedApps = List<AppInfo>.from(selectedApps);
          _sortMode = sortMode;
          _screenshotEnabled = screenshotEnabled;
          _screenshotInterval = screenshotInterval;
          _sortApps();
          _isLoading = false;
        });
      }

      // 根据当前选中应用刷新每应用自定义标记
      // ignore: unawaited_futures
      _loadPerAppCustomFlags(selectedApps);

      final installedApps = await _appService.getAllInstalledApps();

      if (mounted) {
        _homeSetState(() {
          _installedPackages = installedApps
              .map((app) => app.packageName)
              .where((pkg) => pkg.trim().isNotEmpty)
              .toSet();
          _installedAppsByPackage = <String, AppInfo>{
            for (final AppInfo app in installedApps)
              if (app.packageName.trim().isNotEmpty) app.packageName: app,
          };
          _installedAppsLoaded = true;
          _sortApps();
        });
      }

      // 等首批缓存/快速统计完成，再用 app_stats 快速刷新一次，修正旧缓存。
      await Future.wait([earlyTotalsFuture, earlyStatsFuture]);
      await _loadStatsFresh();
      await _loadTotals();

      // 根据排序模式排序应用
      _sortApps();

      // 检查权限状态
      _checkPermissionIssues();

      // 检查截屏开关状态是否需要自动关闭
      _checkScreenshotToggleState();
    } catch (e) {
      print('加载数据失败: $e');
      if (mounted) {
        _homeSetState(() {
          _isLoading = false;
        });
      }
    }
    StartupProfiler.end('HomePage._loadData');
  }

  /// 加载“每应用自定义设置(use_custom)”开启状态集合
  Future<void> _loadPerAppCustomFlags([List<AppInfo>? apps]) async {
    try {
      final list = apps ?? _selectedApps;
      if (list.isEmpty) {
        if (mounted) {
          _homeSetState(() => _customEnabledPackages.clear());
        }
        return;
      }
      final service = PerAppScreenshotSettingsService.instance;
      final futures = list.map((a) async {
        final enabled = await service.getUseCustom(a.packageName);
        return MapEntry(a.packageName, enabled);
      }).toList();
      final results = await Future.wait(futures);
      if (!mounted) return;
      _homeSetState(() {
        _customEnabledPackages
          ..clear()
          ..addAll(results.where((e) => e.value).map((e) => e.key));
      });
    } catch (_) {
      // 静默失败，避免影响首页
    }
  }

  void _sortApps() {
    final appStats =
        _screenshotStats['appStatistics']
            as Map<String, Map<String, dynamic>>? ??
        {};
    final List<AppInfo> visibleApps = _buildVisibleApps(appStats);

    // 兼容旧排序键
    String mode = _sortMode;
    if (mode == 'lastScreenshot') mode = 'timeDesc';
    if (mode == 'screenshotCount') mode = 'countDesc';

    // 仅对“有截图的应用”排序，无截图的应用保持在后面，且内部按应用名升序稳定显示
    final List<AppInfo> appsWithShots = [];
    final List<AppInfo> appsWithoutShots = [];
    for (final app in visibleApps) {
      final stat = appStats[app.packageName];
      final hasAny =
          (stat != null) && (((stat['totalCount'] as int?) ?? 0) > 0);
      if (hasAny) {
        appsWithShots.add(app);
      } else {
        appsWithoutShots.add(app);
      }
    }

    int compareByTime(AppInfo a, AppInfo b, {required bool desc}) {
      final aLast = appStats[a.packageName]?['lastCaptureTime'] as DateTime?;
      final bLast = appStats[b.packageName]?['lastCaptureTime'] as DateTime?;
      int c;
      if (aLast == null && bLast == null) {
        c = 0;
      } else if (aLast == null) {
        c = 1;
      } else if (bLast == null) {
        c = -1;
      } else {
        c = aLast.compareTo(bLast);
      }
      if (desc) c = -c;
      if (c != 0) return c;
      final c2 = a.appName.compareTo(b.appName);
      if (c2 != 0) return c2;
      return a.packageName.compareTo(b.packageName);
    }

    int compareByCount(AppInfo a, AppInfo b, {required bool desc}) {
      final aCount = appStats[a.packageName]?['totalCount'] as int? ?? 0;
      final bCount = appStats[b.packageName]?['totalCount'] as int? ?? 0;
      int c = aCount.compareTo(bCount);
      if (desc) c = -c;
      if (c != 0) return c;
      final c2 = a.appName.compareTo(b.appName);
      if (c2 != 0) return c2;
      return a.packageName.compareTo(b.packageName);
    }

    int compareBySize(AppInfo a, AppInfo b, {required bool desc}) {
      final aSize = appStats[a.packageName]?['totalSize'] as int? ?? 0;
      final bSize = appStats[b.packageName]?['totalSize'] as int? ?? 0;
      int c = aSize.compareTo(bSize);
      if (desc) c = -c;
      if (c != 0) return c;
      final c2 = a.appName.compareTo(b.appName);
      if (c2 != 0) return c2;
      return a.packageName.compareTo(b.packageName);
    }

    // 根据当前排序模式和顺序进行排序
    switch (mode) {
      case 'time':
        appsWithShots.sort((a, b) => compareByTime(a, b, desc: !_sortOrderAsc));
        break;
      case 'timeAsc':
        appsWithShots.sort((a, b) => compareByTime(a, b, desc: false));
        break;
      case 'timeDesc':
        appsWithShots.sort((a, b) => compareByTime(a, b, desc: true));
        break;
      case 'count':
        appsWithShots.sort(
          (a, b) => compareByCount(a, b, desc: !_sortOrderAsc),
        );
        break;
      case 'countAsc':
        appsWithShots.sort((a, b) => compareByCount(a, b, desc: false));
        break;
      case 'countDesc':
        appsWithShots.sort((a, b) => compareByCount(a, b, desc: true));
        break;
      case 'size':
        appsWithShots.sort((a, b) => compareBySize(a, b, desc: !_sortOrderAsc));
        break;
      case 'sizeAsc':
        appsWithShots.sort((a, b) => compareBySize(a, b, desc: false));
        break;
      case 'sizeDesc':
        appsWithShots.sort((a, b) => compareBySize(a, b, desc: true));
        break;
      default:
        appsWithShots.sort((a, b) => compareByTime(a, b, desc: true));
        break;
    }

    // 无截图应用按应用名升序，固定排在后面
    appsWithoutShots.sort((a, b) => a.appName.compareTo(b.appName));

    _selectedApps = [...appsWithShots, ...appsWithoutShots];
  }

  List<AppInfo> _buildVisibleApps(Map<String, Map<String, dynamic>> appStats) {
    final Map<String, AppInfo> visible = <String, AppInfo>{};
    final Set<String> savedPackages = _savedSelectedApps
        .map((app) => app.packageName)
        .where((pkg) => pkg.trim().isNotEmpty)
        .toSet();

    for (final app in _savedSelectedApps) {
      final Map<String, dynamic>? stat = appStats[app.packageName];
      final String statName = (stat?['appName'] as String?)?.trim() ?? '';
      final AppInfo? cachedApp = _cachedAppsByPackage[app.packageName];
      final String displayName = _resolvePreferredAppName(
        packageName: app.packageName,
        installedName: _installedAppsByPackage[app.packageName]?.appName,
        savedName: app.appName,
        cachedName: cachedApp?.appName,
        statName: statName,
      );
      final bool isInstalled =
          !_installedAppsLoaded || _installedPackages.contains(app.packageName);
      final AppInfo? installedApp = _installedAppsByPackage[app.packageName];
      visible[app.packageName] = AppInfo(
        packageName: app.packageName,
        appName: displayName,
        icon: isInstalled
            ? (installedApp?.icon ?? app.icon ?? cachedApp?.icon)
            : (app.icon ?? cachedApp?.icon),
        version: isInstalled
            ? (installedApp?.version ?? app.version)
            : app.version,
        isSystemApp: isInstalled
            ? (installedApp?.isSystemApp ?? app.isSystemApp)
            : app.isSystemApp,
        isInstalled: isInstalled,
        isSelected: app.isSelected,
      );
    }

    if (_installedAppsLoaded) {
      for (final MapEntry<String, Map<String, dynamic>> entry
          in appStats.entries) {
        final String packageName = entry.key.trim();
        if (packageName.isEmpty) continue;
        if (savedPackages.contains(packageName)) continue;
        if (_installedPackages.contains(packageName)) continue;
        final Map<String, dynamic> stat = entry.value;
        final String rawName = (stat['appName'] as String?)?.trim() ?? '';
        final AppInfo? cachedApp = _cachedAppsByPackage[packageName];
        visible[packageName] = AppInfo(
          packageName: packageName,
          appName: _resolvePreferredAppName(
            packageName: packageName,
            cachedName: cachedApp?.appName,
            statName: rawName,
          ),
          icon: cachedApp?.icon,
          version: '',
          isSystemApp: false,
          isInstalled: false,
        );
      }
    }

    return visible.values.toList();
  }

  String _resolvePreferredAppName({
    required String packageName,
    String? installedName,
    String? savedName,
    String? cachedName,
    String? statName,
  }) {
    final List<String?> candidates = <String?>[
      installedName,
      savedName,
      cachedName,
      statName,
    ];

    for (final String? candidate in candidates) {
      final String value = candidate?.trim() ?? '';
      if (value.isEmpty) continue;
      if (!_looksLikePackageFallback(value, packageName)) {
        return value;
      }
    }

    for (final String? candidate in candidates) {
      final String value = candidate?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    return packageName;
  }

  bool _looksLikePackageFallback(String value, String packageName) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed == packageName) return true;
    if (trimmed.contains(' ') ||
        trimmed.contains('-') ||
        trimmed.contains('_')) {
      return false;
    }
    return RegExp(r'^[a-zA-Z0-9]+(\.[a-zA-Z0-9_]+)+$').hasMatch(trimmed);
  }

  bool _isAppSelectable(AppInfo app) {
    for (final saved in _savedSelectedApps) {
      if (saved.packageName == app.packageName) return true;
    }
    return false;
  }

  String _appInitial(AppInfo app) {
    final String raw = app.appName.trim().isNotEmpty
        ? app.appName.trim()
        : app.packageName.trim();
    if (raw.isEmpty) return '?';
    return raw.characters.first.toUpperCase();
  }

  void _onSelectSort(String mode) async {
    await _appService.saveSortMode(mode);
    if (mounted) {
      _homeSetState(() {
        _sortMode = mode;
      });
      _sortApps();
    }
  }

  // 新增：切换排序字段
  void _cycleSortField() {
    final fields = ['time', 'count', 'size'];
    final currentIndex = fields.indexOf(_sortMode);
    final nextIndex = (currentIndex + 1) % fields.length;
    _onSelectSort(fields[nextIndex]);
  }

  // 新增：切换排序顺序
  void _toggleSortOrder() {
    _homeSetState(() {
      _sortOrderAsc = !_sortOrderAsc;
    });
    _sortApps();
  }

  Future<void> _toggleScreenshotEnabled() async {
    final newValue = !_screenshotEnabled;

    // 控制截屏服务
    final screenshotService = ScreenshotService.instance;

    if (newValue) {
      // 显示启动提示
      if (mounted) {
        UINotifier.info(
          context,
          AppLocalizations.of(context).startingScreenshotServiceInfo,
        );
      }

      // 启动定时截屏
      try {
        // 为避免初始值竞争，启用前总是读取一次持久化的间隔
        final persistedInterval = await _appService.getScreenshotInterval();
        if (mounted) {
          _homeSetState(() {
            _screenshotInterval = persistedInterval;
          });
        }
        final success = await screenshotService.startScreenshotService(
          persistedInterval,
        );
        if (!success) {
          if (mounted) {
            UINotifier.error(
              context,
              AppLocalizations.of(context).startServiceFailedCheckPermissions,
              duration: const Duration(seconds: 3),
            );
          }
          return;
        }

        // 成功开启后，主动刷新一次统计并更新缓存，稳定列表排序
        try {
          final stats = await ScreenshotService.instance
              .getScreenshotStatsFresh();
          await ScreenshotService.instance.updateStatsCache(stats);
          if (mounted) {
            _homeSetState(() {
              _screenshotStats = stats;
            });
            _sortApps();
          }
        } catch (_) {}
      } catch (e) {
        String errorMessage = AppLocalizations.of(context).startFailedUnknown;

        // 根据错误类型提供更具体的提示
        if (e.toString().contains('无障碍服务未启用')) {
          errorMessage = AppLocalizations.of(
            context,
          ).accessibilityNotEnabledDetail;
        } else if (e.toString().contains('存储权限未授予')) {
          errorMessage = AppLocalizations.of(
            context,
          ).storagePermissionNotGrantedDetail;
        } else if (e.toString().contains('服务未运行')) {
          errorMessage = AppLocalizations.of(context).serviceNotRunningDetail;
        } else if (e.toString().contains('Android版本')) {
          errorMessage = AppLocalizations.of(
            context,
          ).androidVersionNotSupportedDetail;
        } else {
          errorMessage = e.toString();
        }

        if (mounted) {
          // 统一风格错误对话框
          await showUIDialog<void>(
            context: context,
            barrierDismissible: false,
            title: AppLocalizations.of(context).startFailedTitle,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errorMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.info.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                  ),
                  child: Text(
                    AppLocalizations.of(context).tipIfProblemPersists,
                    style: TextStyle(fontSize: 12, color: AppTheme.info),
                  ),
                ),
              ],
            ),
            actions: const [UIDialogAction(text: '确定')],
          );
        }
        return;
      }
    } else {
      // 停止定时截屏
      await screenshotService.stopScreenshotService();
      // 手动刷新统计数据
      await _loadStats();
    }

    // 保存状态
    await _appService.saveScreenshotEnabled(newValue);
    if (mounted) {
      _homeSetState(() {
        _screenshotEnabled = newValue;
      });
      if (newValue) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).screenshotEnabledToast,
        );
      } else {
        UINotifier.info(
          context,
          AppLocalizations.of(context).screenshotDisabledToast,
        );
      }
    }
  }

  Future<void> _updateScreenshotInterval(int interval) async {
    await _appService.saveScreenshotInterval(interval);
    _homeSetState(() {
      _screenshotInterval = interval;
    });

    // 如果截屏正在运行，更新间隔
    if (_screenshotEnabled) {
      final screenshotService = ScreenshotService.instance;
      await screenshotService.updateInterval(interval);
    }
  }

  void _showIntervalDialog() {
    final TextEditingController controller = TextEditingController(
      text: _screenshotInterval.toString(),
    );

    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).intervalSettingTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).intervalLabel,
                hintText: AppLocalizations.of(context).intervalHint,
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              AppLocalizations.of(context).intervalRangeNote,
              style: TextStyle(fontSize: 12, color: AppTheme.info),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final interval = int.tryParse(input);
            if (interval == null || interval < 5 || interval > 60) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidInput,
              );
              return;
            }
            await _updateScreenshotInterval(interval);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).intervalSavedToast(interval),
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _onAppTap(AppInfo app) async {
    // TODO: 进入应用详情页面，显示截图历史
    // 在导航之前，统一取消焦点，避免其他标签页的 TextField 焦点残留
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.pushNamed(
      context,
      '/screenshot_gallery',
      arguments: {'appInfo': app, 'packageName': app.packageName},
    );
    // 返回后强制获取最新统计（不走缓存，不受节流影响）
    await _loadStatsFresh();
    // 返回后也刷新每应用自定义标记（用户可能在子页修改了设置）
    // ignore: unawaited_futures
    _loadPerAppCustomFlags();
  }
}

import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/app_info.dart';
import '../services/app_selection_service.dart';
import '../services/screenshot_service.dart';
import '../services/permission_service.dart';
import '../services/theme_service.dart';
import '../services/locale_service.dart';
import '../services/startup_profiler.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../services/ime_exclusion_service.dart';
import '../widgets/app_selection_widget.dart';
import '../services/per_app_screenshot_settings_service.dart';
import 'exclusion_help_page.dart';
import 'settings_page.dart';
import '../services/flutter_logger.dart';
import 'dart:async';

/// 主应用界面
class HomePage extends StatefulWidget {
  final ThemeService themeService;
  
  const HomePage({super.key, required this.themeService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final AppSelectionService _appService = AppSelectionService.instance;

  List<AppInfo> _selectedApps = AppSelectionService.instance.selectedApps;
  String _sortMode = 'timeDesc';
  bool _sortOrderAsc = false; // 新增：排序顺序，false为降序，true为升序
  bool _screenshotEnabled = false;
  int _screenshotInterval = 5;
  bool _isLoading = false; // 不显示全屏加载动画
  bool _initialized = true; // 直接认为已初始化，避免首屏Loading
  bool _hasPermissionIssues = false; // 权限问题状态
  Map<String, dynamic> _screenshotStats = {}; // 截图统计数据
  Map<String, dynamic> _totals = {}; // 新增：汇总统计数据
  bool _selectionMode = false;
  final Set<String> _selectedPackages = <String>{};
  // 记录已开启“每应用自定义设置”的应用包名集合
  final Set<String> _customEnabledPackages = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StartupProfiler.begin('HomePage.initState+loadData');
    // 将数据加载与权限检查延后到首帧之后，避免阻塞首帧
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadData();
      // 首次进入时加载每应用自定义开关
      // ignore: unawaited_futures
      _loadPerAppCustomFlags();
      // 首帧后后台刷新应用列表（如缓存过期）
      // ignore: unawaited_futures
      AppSelectionService.instance.refreshAppsInBackgroundIfStale();
      // 权限相关检查稍后执行，避免与首帧竞争
      Future.delayed(const Duration(milliseconds: 600), () {
        PermissionService.instance.startMonitoring();
        _checkPermissionIssues();
        _checkScreenshotToggleState();
      });
    });
    ScreenshotService.instance.onScreenshotSaved.listen((_) {
      // 收到新增/删除事件，直接拉取最新统计（不走缓存）
      _loadStatsFresh();
      _loadTotals(); // 同时刷新汇总统计
    });

    // 订阅排序模式变更，自动刷新排序
    AppSelectionService.instance.onSortModeChanged.listen((mode) {
      if (!mounted) return;
      setState(() {
        _sortMode = mode;
      });
      _sortApps();
    });

    // 设置权限状态监听
    final permissionService = PermissionService.instance;
    permissionService.onPermissionsUpdated = () async {
      if (mounted) {
        // 立即检查权限问题并更新UI
        await _checkPermissionIssues();

        // 检查截屏开关状态是否需要自动关闭
        await _checkScreenshotToggleState();
      }
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台：强制同步文件到数据库并刷新统计，避免节流导致读到旧数据
      Future.delayed(const Duration(milliseconds: 300), () async {
        await _loadStatsFresh();
        // 回到前台后同步刷新自定义标记
        // ignore: unawaited_futures
        _loadPerAppCustomFlags();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadStats() async {
    StartupProfiler.begin('HomePage._loadStats');
    // 首页允许首帧走统计缓存
    final stats = await ScreenshotService.instance.getScreenshotStatsCachedFirst();
    // 日志：记录缓存签名与缓存来源
    // ignore: unawaited_futures
    FlutterLogger.log('home.loadStats cachedFirst -> total=${stats['totalScreenshots']}, today=${stats['todayScreenshots']}');
    if (mounted) {
      setState(() {
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
      setState(() {
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
      if (mounted) {
        setState(() {
          _totals = totals;
        });
      }
    } catch (e) {
      print('加载汇总统计失败: $e');
    }
  }

  /// 计算当前统计数据的签名，用于快速判断是否需要刷新UI
  String _computeStatsSignature(Map<String, dynamic> stats) {
    final int total = (stats['totalScreenshots'] as int?) ?? 0;
    final int today = (stats['todayScreenshots'] as int?) ?? 0;
    final int lastTs = (stats['lastScreenshotTime'] as int?) ?? 0;
    final appStats = stats['appStatistics'] as Map<String, Map<String, dynamic>>? ?? {};

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

    return '$total|$today|$lastTs|$appsCount|$sumCount|$sumSize|$maxLast';
  }

  /// 校验当前展示与数据库最新统计是否一致，不一致则用最新统计刷新
  Future<void> _verifyAndRefreshStatsIfStale() async {
    try {
      final String currentSig = _computeStatsSignature(_screenshotStats);
      final fresh = await ScreenshotService.instance.getScreenshotStatsFresh();
      final String freshSig = _computeStatsSignature(fresh);
      if (currentSig != freshSig && mounted) {
        setState(() {
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

    try {
      // 加载用户设置
      final selectedApps = await _appService.getSelectedApps();
      final sortMode = await _appService.getSortMode();
      final screenshotEnabled = await _appService.getScreenshotEnabled();
      final screenshotInterval = await _appService.getScreenshotInterval();

      // 先更新轻量数据，避免出现短暂空状态
      if (mounted) {
        setState(() {
          _selectedApps = selectedApps;
          _sortMode = sortMode;
          _screenshotEnabled = screenshotEnabled;
          _screenshotInterval = screenshotInterval;
          _isLoading = false;
        });
      }

      // 根据当前选中应用刷新每应用自定义标记
      // ignore: unawaited_futures
      _loadPerAppCustomFlags(selectedApps);

      // 再加载统计数据（缓存优先），不阻塞应用列表
      await _loadStats();

      // 首次加载时重新计算汇总统计（确保数据完整性）
      await ScreenshotService.instance.recalculateTotals();
      await _loadTotals(); // 同时加载汇总统计

      // 根据排序模式排序应用
      _sortApps();

      // 检查权限状态
      _checkPermissionIssues();

      // 检查截屏开关状态是否需要自动关闭
      _checkScreenshotToggleState();
    } catch (e) {
      print('加载数据失败: $e');
      // 出错也不显示全屏加载
    }
    StartupProfiler.end('HomePage._loadData');
  }

  /// 加载“每应用自定义设置(use_custom)”开启状态集合
  Future<void> _loadPerAppCustomFlags([List<AppInfo>? apps]) async {
    try {
      final list = apps ?? _selectedApps;
      if (list.isEmpty) {
        if (mounted) {
          setState(() => _customEnabledPackages.clear());
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
      setState(() {
        _customEnabledPackages
          ..clear()
          ..addAll(results.where((e) => e.value).map((e) => e.key));
      });
    } catch (_) {
      // 静默失败，避免影响首页
    }
  }

  void _sortApps() {
    final appStats = _screenshotStats['appStatistics'] as Map<String, Map<String, dynamic>>? ?? {};

    // 兼容旧排序键
    String mode = _sortMode;
    if (mode == 'lastScreenshot') mode = 'timeDesc';
    if (mode == 'screenshotCount') mode = 'countDesc';

    // 仅对“有截图的应用”排序，无截图的应用保持在后面，且内部按应用名升序稳定显示
    final List<AppInfo> appsWithShots = [];
    final List<AppInfo> appsWithoutShots = [];
    for (final app in _selectedApps) {
      final stat = appStats[app.packageName];
      final hasAny = (stat != null) && (((stat['totalCount'] as int?) ?? 0) > 0);
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
        appsWithShots.sort((a, b) => compareByCount(a, b, desc: !_sortOrderAsc));
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

    _selectedApps = [
      ...appsWithShots,
      ...appsWithoutShots,
    ];
  }

  void _onSelectSort(String mode) async {
    await _appService.saveSortMode(mode);
    if (mounted) {
      setState(() {
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
    setState(() {
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
        UINotifier.info(context, AppLocalizations.of(context).startingScreenshotServiceInfo);
      }

      // 启动定时截屏
      try {
        // 为避免初始值竞争，启用前总是读取一次持久化的间隔
        final persistedInterval = await _appService.getScreenshotInterval();
        if (mounted) {
          setState(() {
            _screenshotInterval = persistedInterval;
          });
        }
        final success = await screenshotService.startScreenshotService(persistedInterval);
        if (!success) {
          if (mounted) {
            UINotifier.error(context, AppLocalizations.of(context).startServiceFailedCheckPermissions, duration: const Duration(seconds: 3));
          }
          return;
        }

        // 成功开启后，主动刷新一次统计并更新缓存，稳定列表排序
        try {
          final stats = await ScreenshotService.instance.getScreenshotStatsFresh();
          await ScreenshotService.instance.updateStatsCache(stats);
          if (mounted) {
            setState(() {
              _screenshotStats = stats;
            });
            _sortApps();
          }
        } catch (_) {}
      } catch (e) {
        String errorMessage = AppLocalizations.of(context).startFailedUnknown;
        
        // 根据错误类型提供更具体的提示
        if (e.toString().contains('无障碍服务未启用')) {
          errorMessage = AppLocalizations.of(context).accessibilityNotEnabledDetail;
        } else if (e.toString().contains('存储权限未授予')) {
          errorMessage = AppLocalizations.of(context).storagePermissionNotGrantedDetail;
        } else if (e.toString().contains('服务未运行')) {
          errorMessage = AppLocalizations.of(context).serviceNotRunningDetail;
        } else if (e.toString().contains('Android版本')) {
          errorMessage = AppLocalizations.of(context).androidVersionNotSupportedDetail;
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
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.info,
                    ),
                  ),
                ),
              ],
            ),
            actions: const [
              UIDialogAction(text: '确定'),
            ],
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
      setState(() {
        _screenshotEnabled = newValue;
      });
      if (newValue) {
        UINotifier.success(context, AppLocalizations.of(context).screenshotEnabledToast);
      } else {
        UINotifier.info(context, AppLocalizations.of(context).screenshotDisabledToast);
      }
    }
  }

  Future<void> _updateScreenshotInterval(int interval) async {
    await _appService.saveScreenshotInterval(interval);
    setState(() {
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
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.info,
              ),
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
              UINotifier.error(ctx, AppLocalizations.of(ctx).intervalInvalidInput);
              return;
            }
            await _updateScreenshotInterval(interval);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).intervalSavedToast(interval));
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
      arguments: {
        'appInfo': app,
        'packageName': app.packageName,
      },
    );
    // 返回后强制获取最新统计（不走缓存，不受节流影响）
    await _loadStatsFresh();
    // 返回后也刷新每应用自定义标记（用户可能在子页修改了设置）
    // ignore: unawaited_futures
    _loadPerAppCustomFlags();
  }


  /// 检查是否有权限缺失
  Future<void> _checkPermissionIssues() async {
    try {
      final permissionService = PermissionService.instance;
      final permissions = await permissionService.checkAllPermissions();

      // 检查所有关键权限
      final storageGranted = permissions['storage'] ?? false;
      final notificationGranted = permissions['notification'] ?? false;
      final accessibilityEnabled = permissions['accessibility'] ?? false;
      final usageStatsGranted = permissions['usage_stats'] ?? false;

      final hasIssues = !storageGranted || !notificationGranted || !accessibilityEnabled || !usageStatsGranted;

      if (mounted) {
        setState(() {
          _hasPermissionIssues = hasIssues;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasPermissionIssues = true; // 如果检查失败，认为有问题
        });
      }
    }
  }

  /// 检查截屏开关状态是否需要自动关闭
  Future<void> _checkScreenshotToggleState() async {
    // 如果截屏开关是关闭状态，无需检查
    if (!_screenshotEnabled) return;

    try {
      // 实时检查权限状态
      final permissionService = PermissionService.instance;
      final permissions = await permissionService.checkAllPermissions();

      // 检查所有关键权限
      final storageGranted = permissions['storage'] ?? false;
      final notificationGranted = permissions['notification'] ?? false;
      final accessibilityEnabled = permissions['accessibility'] ?? false;
      final usageStatsGranted = permissions['usage_stats'] ?? false;

      final hasPermissionIssues = !storageGranted || !notificationGranted || !accessibilityEnabled || !usageStatsGranted;

      // 如果有权限问题，自动关闭截屏开关
      if (hasPermissionIssues) {
        await _appService.saveScreenshotEnabled(false);
        if (mounted) {
          setState(() {
            _screenshotEnabled = false;
          });

          UINotifier.info(context, AppLocalizations.of(context).autoDisabledDueToPermissions, duration: const Duration(seconds: 3));
        }
      }
    } catch (e) {
      print('检查截屏开关状态失败: $e');
    }
  }

  /// 刷新权限状态
  Future<void> _refreshPermissions() async {
    try {
      final permissionService = PermissionService.instance;

      // 显示加载提示
      if (mounted) {
        UINotifier.info(context, AppLocalizations.of(context).refreshingPermissionsInfo, duration: const Duration(seconds: 1));
      }

      // 强制刷新权限状态
      await permissionService.forceRefreshPermissions();

      // 失效统计缓存，确保后续读取为最新
      await ScreenshotService.instance.invalidateStatsCache();
      // 立即重新加载统计
      await _loadStats();

      // 重新检查权限问题
      await _checkPermissionIssues();

      if (mounted) {
        UINotifier.success(context, AppLocalizations.of(context).permissionsRefreshed, duration: const Duration(seconds: 1));
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).refreshPermissionsFailed('$e'));
      }
    }
  }

  /// 显示权限状态
  Future<void> _showPermissionStatus() async {
    try {
      final permissionService = PermissionService.instance;
      final permissions = await permissionService.checkAllPermissions();

      if (mounted) {
        final action = await showUIDialog<String>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).permissionStatusTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPermissionStatusItem(AppLocalizations.of(context).storagePermissionTitle, permissions['storage'] ?? false),
              _buildPermissionStatusItem(AppLocalizations.of(context).notificationPermissionTitle, permissions['notification'] ?? false),
              _buildPermissionStatusItem(AppLocalizations.of(context).accessibilityPermissionTitle, permissions['accessibility'] ?? false),
              _buildPermissionStatusItem(AppLocalizations.of(context).screenRecordingPermissionTitle, true),
            ],
          ),
          actions: [
            UIDialogAction<String>(text: AppLocalizations.of(context).goToSettings, result: 'go_settings'),
            UIDialogAction<String>(text: AppLocalizations.of(context).dialogOk, style: UIDialogActionStyle.primary, result: 'ok'),
          ],
        );
        if (!mounted) return;
        if (action == 'go_settings') {
          // 使用页面上下文进行导航，避免在对话框上下文已销毁时导航卡住
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsPage(themeService: widget.themeService),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).checkPermissionStatusFailed('$e'));
      }
    }
  }

  Widget _buildPermissionStatusItem(String name, bool granted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          granted
              ? Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 14,
                    color: AppTheme.successForeground,
                  ),
                )
              : const Icon(
                  Icons.cancel,
                  color: AppTheme.destructive,
                  size: 20,
                ),
          const SizedBox(width: 8),
          Text(name),
          const Spacer(),
          Text(
            granted ? AppLocalizations.of(context).grantedLabel : AppLocalizations.of(context).notGrantedLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: granted
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : AppTheme.destructive,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 构建 AppBar 的 actions（选择模式时显示批量操作）
    final List<Widget>? appBarActions = _selectionMode
        ? <Widget>[
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedPackages.clear();
                });
              },
              child: Text(AppLocalizations.of(context).dialogCancel),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedPackages.length == _selectedApps.length) {
                    _selectedPackages.clear();
                  } else {
                    _selectedPackages
                      ..clear()
                      ..addAll(_selectedApps.map((a) => a.packageName));
                  }
                });
              },
              child: Text(AppLocalizations.of(context).selectAll),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: AppLocalizations.of(context).removeMonitoring,
              onPressed: _selectedPackages.isEmpty ? null : _removeSelectedApps,
            ),
          ]
        : null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        toolbarHeight: 48,
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        titleSpacing: 0,
        actions: appBarActions,
        title: _selectionMode
          ? Padding(
              padding: const EdgeInsets.only(left: AppTheme.spacing4),
              child: Text(
                AppLocalizations.of(context).selectedItemsCount(_selectedPackages.length),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
              child: Row(
              children: [
                // 左侧:语言切换图标
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 24, height: 36),
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  icon: const Icon(Icons.language, size: 20, weight: 300),
                  tooltip: AppLocalizations.of(context).languageSettingTitle,
                  onPressed: _showLanguageBottomSheet,
                ),
                
                // 加号按钮
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 24, height: 36),
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  icon: const Icon(Icons.add, size: 20, weight: 300),
                  tooltip: AppLocalizations.of(context).navSelectApps,
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: Text(AppLocalizations.of(context).navSelectApps),
                            actions: [
                              IconButton(
                                tooltip: AppLocalizations.of(context).whySomeAppsHidden,
                                icon: const Icon(Icons.help_outline),
                                onPressed: () async {
                                  // 收集已启用输入法及默认输入法
                                  final imeList = await ImeExclusionService.getEnabledImeList();
                                  final defaultIme = await ImeExclusionService.getDefaultImeInfo();

                                  final lines = <Widget>[];
                                  lines.add(Text(
                                    AppLocalizations.of(context).excludedAppsIntro,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ));
                                  lines.add(const SizedBox(height: 8));
                                  // 本应用
                                  lines.add(Text(AppLocalizations.of(context).excludedThisApp));
                                  // 输入法应用
                                  if (imeList.isNotEmpty) {
                                    lines.add(const SizedBox(height: 8));
                                    lines.add(Text(AppLocalizations.of(context).excludedImeApps));
                                    for (final m in imeList) {
                                      final name = m['appName'] ?? '';
                                      final pkg = m['packageName'] ?? '';
                                      lines.add(Text('  - ${name.isNotEmpty ? name : AppLocalizations.of(context).unknownIme}'));
                                    }
                                  } else {
                                    lines.add(const SizedBox(height: 8));
                                    lines.add(Text(AppLocalizations.of(context).excludedImeAppsFiltered));
                                  }
                                  if (defaultIme != null && (defaultIme['packageName']?.isNotEmpty ?? false)) {
                                    lines.add(const SizedBox(height: 8));
                                    lines.add(Text(AppLocalizations.of(context).currentDefaultIme((defaultIme['appName'] ?? '') as String, (defaultIme['packageName'] ?? '') as String)));
                                  }
                                  lines.add(const SizedBox(height: 12));
                                  lines.add(Text(
                                    AppLocalizations.of(context).imeExplainText,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ));

                                  await showUIDialog<void>(
                                    context: context,
                                    title: AppLocalizations.of(context).excludedAppsTitle,
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: lines,
                                    ),
                                    actions: [UIDialogAction(text: AppLocalizations.of(context).gotIt)],
                                  );
                                },
                              ),
                              TextButton(
                                onPressed: () async {
                                  await _appService.saveSelectedApps(_selectedApps);
                                  if (mounted) Navigator.of(context).pop();
                                  await _loadData(soft: true);
                                },
                                child: Text(AppLocalizations.of(context).dialogDone),
                              ),
                            ],
                          ),
                          body: AppSelectionWidget(
                            displayAsList: true,
                            onSelectionChanged: (apps) {
                              _selectedApps = apps;
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // 首页不再显示排序图标，排序在设置页调整

                const SizedBox(width: 2),
                
                // 搜索框 - 大幅增加flex权重
                Expanded(flex: 7, child: _buildSearchBar(context)),
                
                const SizedBox(width: 2),
                
                // 搜索框右侧：权限提示 或 开关
                _hasPermissionIssues
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 24, height: 36),
                        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                        icon: const Icon(
                          Icons.warning,
                          size: 20,
                          weight: 300,
                          color: AppTheme.destructive,
                        ),
                        onPressed: _showPermissionStatus,
                        tooltip: AppLocalizations.of(context).permissionMissing,
                      )
                   : IconButton(
                       padding: EdgeInsets.zero,
                       constraints: const BoxConstraints.tightFor(width: 24, height: 36),
                       visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                       tooltip: _screenshotEnabled ? AppLocalizations.of(context).stopScreenshot : AppLocalizations.of(context).startScreenshot,
                       iconSize: 22,
                       onPressed: _toggleScreenshotEnabled,
                       icon: _screenshotEnabled
                           ? const Icon(
                               Icons.camera_alt_outlined,
                               size: 22,
                               weight: 300,
                             )
                           : const Icon(
                               Icons.no_photography_outlined,
                               size: 22,
                               weight: 300,
                               color: AppTheme.destructive,
                             ),
                     ),
               
                // 右侧:主题切换图标
               IconButton(
                 padding: EdgeInsets.zero,
                 constraints: const BoxConstraints.tightFor(width: 24, height: 36),
                 visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                 icon: Icon(widget.themeService.themeModeIcon, size: 20, weight: 300),
                 tooltip: _themeModeTooltip(context),
                 onPressed: () async {
                   await widget.themeService.toggleTheme();
                 },
               ),
              ],
            ),
          ),
      ),
      body: Column(
        children: [
          // 新增：副导航栏
          _buildSubNavigation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadData(soft: true),
              child: _buildAppsList(),
            ),
          ),
        ],
      ),
    );
  }
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
    final appCount = _totals['app_count'] as int? ?? 0;
    final screenshotCount = _totals['screenshot_count'] as int? ?? 0;
    final totalSizeBytes = _totals['total_size_bytes'] as int? ?? 0;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing6, vertical: AppTheme.spacing2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 左侧：统计信息
          Expanded(
            child: Row(
              children: [
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
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(8.0)),
      onTap: () => Navigator.pushNamed(context, '/search'),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.6),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(
              Icons.search,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              size: 18,
            ),
            const SizedBox(width: 2),
            Text(
              AppLocalizations.of(context).searchPlaceholder,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppsList() {
    // 不显示全屏加载动画，直接展示当前数据

    // 加载完成后，如果没有选中的应用，显示空状态
    if (_selectedApps.isEmpty) {
      return Center(
        child: Column(
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
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              AppLocalizations.of(context).homeEmptySubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return _buildListView();
  }

  Widget _buildListView() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2, // 减少水平内边距
        vertical: AppTheme.spacing1,   // 减少垂直内边距
      ),
      itemCount: _selectedApps.length,
      itemBuilder: (context, index) {
        final app = _selectedApps[index];
        return _buildAppListItem(app);
      },
    );
  }

  Widget _buildAppListItem(AppInfo app) {
    final bool isSelected = _selectionMode && _selectedPackages.contains(app.packageName);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            _toggleSelect(app.packageName);
          } else {
            _onAppTap(app);
          }
        },
        onLongPress: () {
          if (!_selectionMode) {
            setState(() => _selectionMode = true);
          }
          _toggleSelect(app.packageName);
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing4,
            vertical: AppTheme.spacing2,
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
                        : Icon(
                            Icons.android,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 32,
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
                            color: Theme.of(context).colorScheme.secondaryContainer,
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
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _getAppStatText(app.packageName),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            if (!_selectionMode)
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )
            else
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: const BorderRadius.all(Radius.circular(4.0)),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? Icon(Icons.check, size: 14, color: Theme.of(context).colorScheme.onPrimary)
                    : null,
              ),
          ],
          ),
        ),
      ),
    );
  }

  /// 获取应用统计文本
  String _getAppStatText(String packageName) {
    final l10n = AppLocalizations.of(context);
    final appStats = _screenshotStats['appStatistics'] as Map<String, Map<String, dynamic>>? ?? {};
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

  @override
  bool get wantKeepAlive => true;

  void _toggleSelect(String packageName) {
    setState(() {
      if (_selectedPackages.contains(packageName)) {
        _selectedPackages.remove(packageName);
        if (_selectedPackages.isEmpty) _selectionMode = false;
      } else {
        _selectedPackages.add(packageName);
      }
    });
  }

  Future<void> _removeSelectedApps() async {
    final count = _selectedPackages.length;
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: AppLocalizations.of(context).removeMonitoring,
      message: AppLocalizations.of(context).removeMonitoringMessage,
      actions: [
        UIDialogAction<bool>(text: AppLocalizations.of(context).dialogCancel, result: false),
        UIDialogAction<bool>(text: AppLocalizations.of(context).remove, style: UIDialogActionStyle.destructive, result: true),
      ],
      barrierDismissible: false,
    );
    if (confirmed != true) return;

    final remaining = _selectedApps.where((a) => !_selectedPackages.contains(a.packageName)).toList();
    await _appService.saveSelectedApps(remaining);
    if (!mounted) return;
    setState(() {
      _selectedApps = remaining;
      _selectionMode = false;
      _selectedPackages.clear();
    });
    UINotifier.info(context, AppLocalizations.of(context).removedMonitoringToast(count));
  }

  /// 显示语言选择底部弹窗
  void _showLanguageBottomSheet() {
    final t = AppLocalizations.of(context);
    final currentOption = LocaleService.instance.option;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusLg),
            topRight: Radius.circular(AppTheme.radiusLg),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部指示器
              Container(
                margin: const EdgeInsets.only(top: AppTheme.spacing3),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // 标题
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: Text(
                  t.languageSettingTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              // 语言选项列表
              _buildLanguageOption(
                context: context,
                title: t.languageSystem,
                value: 'system',
                currentValue: currentOption,
                onTap: () async {
                  await LocaleService.instance.setOption('system');
                  if (mounted) {
                    Navigator.of(context).pop();
                    UINotifier.success(context, t.languageChangedToast(t.languageSystem));
                  }
                },
              ),
              
              _buildLanguageOption(
                context: context,
                title: t.languageChinese,
                value: 'zh',
                currentValue: currentOption,
                onTap: () async {
                  await LocaleService.instance.setOption('zh');
                  if (mounted) {
                    Navigator.of(context).pop();
                    UINotifier.success(context, t.languageChangedToast(t.languageChinese));
                  }
                },
              ),
              
              _buildLanguageOption(
                context: context,
                title: t.languageEnglish,
                value: 'en',
                currentValue: currentOption,
                onTap: () async {
                  await LocaleService.instance.setOption('en');
                  if (mounted) {
                    Navigator.of(context).pop();
                    UINotifier.success(context, t.languageChangedToast(t.languageEnglish));
                  }
                },
              ),
              
              const SizedBox(height: AppTheme.spacing4),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建语言选项行
  Widget _buildLanguageOption({
    required BuildContext context,
    required String title,
    required String value,
    required String currentValue,
    required VoidCallback onTap,
  }) {
    final isSelected = value == currentValue;
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

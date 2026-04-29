import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/selection_checkbox.dart';
import '../services/ime_exclusion_service.dart';
import '../widgets/app_selection_widget.dart';
import '../services/per_app_screenshot_settings_service.dart';
import '../services/daily_summary_service.dart';
import 'daily_summary_page.dart';
import 'exclusion_help_page.dart';
import 'settings_page.dart';
import '../services/flutter_logger.dart';
import 'dart:async';
import 'dart:math';

class _HomeRuntimeDiagnostic {
  final String id;
  final String title;
  final String summary;
  final List<String> details;
  final String copyText;
  final String? filePath;
  final String? nativeIssueId;
  final bool showSettingsAction;

  const _HomeRuntimeDiagnostic({
    required this.id,
    required this.title,
    required this.summary,
    required this.details,
    required this.copyText,
    this.filePath,
    this.nativeIssueId,
    this.showSettingsAction = false,
  });
}

/// 主应用界面
class HomePage extends StatefulWidget {
  final ThemeService themeService;

  const HomePage({super.key, required this.themeService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final AppSelectionService _appService = AppSelectionService.instance;

  List<AppInfo> _selectedApps = AppSelectionService.instance.selectedApps;
  List<AppInfo> _savedSelectedApps = AppSelectionService.instance.selectedApps;
  Set<String> _installedPackages = <String>{};
  Map<String, AppInfo> _installedAppsByPackage = <String, AppInfo>{};
  Map<String, AppInfo> _cachedAppsByPackage = <String, AppInfo>{};
  bool _installedAppsLoaded = false;
  String _sortMode = 'timeDesc';
  bool _sortOrderAsc = false; // 新增：排序顺序，false为降序，true为升序
  bool _screenshotEnabled = false;
  int _screenshotInterval = 5;
  bool _isLoading = false; // 不显示全屏加载动画
  bool _initialized = true; // 直接认为已初始化，避免首屏Loading
  bool _hasPermissionIssues = false; // 权限问题状态
  _HomeRuntimeDiagnostic? _runtimeDiagnostic;
  bool _runtimeDiagnosticExpanded = false;
  String? _lastAutoOpenedDiagnosticId;
  final Set<String> _dismissedDiagnosticIds = <String>{};
  Map<String, dynamic> _screenshotStats = {}; // 截图统计数据
  Map<String, dynamic> _totals = {}; // 新增：汇总统计数据
  bool _selectionMode = false;
  final Set<String> _selectedPackages = <String>{};
  // 记录已开启“每应用自定义设置”的应用包名集合
  final Set<String> _customEnabledPackages = <String>{};
  final DailySummaryService _dailySummaryService = DailySummaryService.instance;
  late final EasyRefreshController _refreshController;
  static const double _morningRevealMaxHeight = 72;
  MorningInsights? _morningInsights;
  int _morningTipIndex = -1;
  MorningInsightEntry? _currentMorningTip;
  final Random _random = Random();
  List<int> _morningTipDeck = <int>[];
  String? _morningTipDeckSignature;
  int? _lastMorningTipIndex;
  final List<DateTime> _morningRefreshHistory = <DateTime>[];
  DateTime? _morningCooldownUntil;
  String? _morningCooldownMessage;
  static const int _morningMaxRefreshInWindow = 10;
  static const Duration _morningRefreshWindow = Duration(minutes: 1);
  static const Duration _morningCooldownDuration = Duration(minutes: 3);
  static const int _morningAvailableHour = 8;
  bool _morningGenerationRunning = false;

  @override
  void initState() {
    super.initState();
    _refreshController = EasyRefreshController(controlFinishRefresh: true);
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
        _checkPermissionIssues(autoOpenDiagnostic: true);
        _checkScreenshotToggleState();
      });
      // 预加载晨间建议，首次展示时可快速切换
      // ignore: unawaited_futures
      _preloadMorningInsights();
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
        await _checkPermissionIssues(autoOpenDiagnostic: true);

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
        await _checkPermissionIssues(autoOpenDiagnostic: true);
        await _checkScreenshotToggleState();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshController.dispose();
    super.dispose();
  }

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
      final prevDayCount = _totals['day_count'] as int? ?? 0;
      if (mounted) {
        setState(() {
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
          setState(() {
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
    final int today = (stats['todayScreenshots'] as int?) ?? 0;
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
      final installedApps = await _appService.getAllInstalledApps();
      final cachedAppsByPackage = await _appService.getCachedAppInfoByPackage();
      final sortMode = await _appService.getSortMode();
      final screenshotEnabled = await _appService.getScreenshotEnabled();
      final screenshotInterval = await _appService.getScreenshotInterval();

      // 先更新轻量数据，避免出现短暂空状态
      if (mounted) {
        setState(() {
          _savedSelectedApps = List<AppInfo>.from(selectedApps);
          _installedPackages = installedApps
              .map((app) => app.packageName)
              .where((pkg) => pkg.trim().isNotEmpty)
              .toSet();
          _installedAppsByPackage = <String, AppInfo>{
            for (final AppInfo app in installedApps)
              if (app.packageName.trim().isNotEmpty) app.packageName: app,
          };
          _cachedAppsByPackage = cachedAppsByPackage;
          _installedAppsLoaded = true;
          _selectedApps = List<AppInfo>.from(selectedApps);
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
          setState(() {
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
      setState(() {
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

  /// 检查是否有权限缺失
  Future<void> _checkPermissionIssues({bool autoOpenDiagnostic = false}) async {
    try {
      final permissionService = PermissionService.instance;
      final permissions = await permissionService.checkAllPermissions();
      final hasIssues = _hasPermissionIssuesFrom(permissions);

      if (mounted) {
        setState(() {
          _hasPermissionIssues = hasIssues;
        });
      }
      await _refreshRuntimeDiagnosticDrawer(
        permissions: permissions,
        autoOpen: autoOpenDiagnostic,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasPermissionIssues = true; // 如果检查失败，认为有问题
        });
      }
      await _refreshRuntimeDiagnosticDrawer(autoOpen: autoOpenDiagnostic);
    }
  }

  bool _hasPermissionIssuesFrom(Map<String, bool> permissions) {
    final storageGranted = permissions['storage'] ?? false;
    final notificationGranted = permissions['notification'] ?? false;
    final accessibilityEnabled = permissions['accessibility'] ?? false;
    final usageStatsGranted = permissions['usage_stats'] ?? false;
    return !storageGranted ||
        !notificationGranted ||
        !accessibilityEnabled ||
        !usageStatsGranted;
  }

  List<String> _missingPermissionLabels(Map<String, bool> permissions) {
    final missing = <String>[];
    if (!(permissions['notification'] ?? false)) {
      missing.add('通知权限');
    }
    if (!(permissions['accessibility'] ?? false)) {
      missing.add('无障碍服务');
    }
    if (!(permissions['usage_stats'] ?? false)) {
      missing.add('使用情况访问');
    }
    if (!(permissions['storage'] ?? true)) {
      missing.add('存储权限');
    }
    return missing;
  }

  Future<void> _refreshRuntimeDiagnosticDrawer({
    Map<String, bool>? permissions,
    bool autoOpen = false,
  }) async {
    final permissionService = PermissionService.instance;
    Map<String, bool>? resolvedPermissions = permissions;
    if (resolvedPermissions == null) {
      try {
        resolvedPermissions = await permissionService.checkAllPermissions();
      } catch (_) {
        resolvedPermissions = null;
      }
    }

    final nativeDiagnostic = await permissionService
        .getPendingRuntimeDiagnostic();
    final diagnostic = await _buildRuntimeDiagnosticData(
      permissions: resolvedPermissions,
      nativeDiagnostic: nativeDiagnostic,
    );

    if (!mounted) return;

    if (diagnostic == null) {
      setState(() {
        _runtimeDiagnostic = null;
        _runtimeDiagnosticExpanded = false;
      });
      return;
    }

    if (_dismissedDiagnosticIds.contains(diagnostic.id)) {
      setState(() {
        _runtimeDiagnostic = null;
        _runtimeDiagnosticExpanded = false;
      });
      return;
    }

    final shouldAutoOpen =
        autoOpen && diagnostic.id != _lastAutoOpenedDiagnosticId;

    setState(() {
      _runtimeDiagnostic = diagnostic;
      if (shouldAutoOpen) {
        _runtimeDiagnosticExpanded = true;
        _lastAutoOpenedDiagnosticId = diagnostic.id;
      }
    });
  }

  Future<_HomeRuntimeDiagnostic?> _buildRuntimeDiagnosticData({
    required Map<String, bool>? permissions,
    required Map<String, dynamic>? nativeDiagnostic,
  }) async {
    final resolvedPermissions = permissions ?? const <String, bool>{};
    final missingPermissions = permissions == null
        ? const <String>[]
        : _missingPermissionLabels(resolvedPermissions);
    final hasPermissionIssues = missingPermissions.isNotEmpty;
    if (!hasPermissionIssues && nativeDiagnostic == null) {
      return null;
    }

    final permissionService = PermissionService.instance;
    final fallbackLogFile =
        nativeDiagnostic?['logFilePath']?.toString().trim().isNotEmpty == true
        ? nativeDiagnostic!['logFilePath'].toString()
        : await _getTodayInfoLogPath();
    final nativeCopyText = nativeDiagnostic?['copyText']?.toString().trim();
    final nativeSummary = nativeDiagnostic?['summary']?.toString().trim();
    final nativeDetectedAt = _formatDiagnosticTime(
      nativeDiagnostic?['detectedAt'],
    );

    if (hasPermissionIssues) {
      final permissionReport = await permissionService.getPermissionReport();
      final details = <String>[
        '缺失权限：${missingPermissions.join('、')}',
        if (nativeSummary != null && nativeSummary.isNotEmpty)
          '最近异常：$nativeSummary',
        if (nativeDetectedAt != null) '诊断记录时间：$nativeDetectedAt',
        if (fallbackLogFile != null && fallbackLogFile.isNotEmpty)
          '日志文件：$fallbackLogFile',
      ];
      final summary = nativeSummary != null && nativeSummary.isNotEmpty
          ? '检测到权限异常，同时存在最近一次运行异常记录。'
          : '检测到权限状态异常，可能导致通知还在但无法正常截屏。';
      final buffer = StringBuffer()
        ..writeln('首页运行诊断')
        ..writeln('================')
        ..writeln('诊断类型: permission_issue')
        ..writeln('缺失权限: ${missingPermissions.join(', ')}');
      if (permissionReport != null && permissionReport.trim().isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(permissionReport.trim());
      }
      if (nativeCopyText != null && nativeCopyText.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('最近一次运行异常')
          ..writeln(nativeCopyText);
      }
      if (fallbackLogFile != null && fallbackLogFile.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('建议打开日志文件: $fallbackLogFile');
      }
      return _HomeRuntimeDiagnostic(
        id: 'permission:${missingPermissions.join('|')}:${nativeDiagnostic?['id'] ?? '-'}',
        title: '检测到权限或运行异常',
        summary: summary,
        details: details,
        copyText: buffer.toString().trim(),
        filePath: fallbackLogFile,
        nativeIssueId: nativeDiagnostic?['id']?.toString(),
        showSettingsAction: true,
      );
    }

    final details = <String>[
      if (nativeDetectedAt != null) '诊断记录时间：$nativeDetectedAt',
      if (nativeDiagnostic?['summary'] != null &&
          nativeDiagnostic!['summary'].toString().trim().isNotEmpty)
        '异常摘要：${nativeDiagnostic['summary']}',
      if (fallbackLogFile != null && fallbackLogFile.isNotEmpty)
        '日志文件：$fallbackLogFile',
    ];
    return _HomeRuntimeDiagnostic(
      id:
          nativeDiagnostic?['id']?.toString() ??
          'runtime:${DateTime.now().millisecondsSinceEpoch}',
      title: nativeDiagnostic?['title']?.toString() ?? '检测到运行异常',
      summary: nativeDiagnostic?['summary']?.toString() ?? '检测到最近一次运行异常。',
      details: details,
      copyText: nativeCopyText?.isNotEmpty == true
          ? nativeCopyText!
          : [
              '首页运行诊断',
              '================',
              '诊断类型: ${nativeDiagnostic?['type'] ?? 'runtime_issue'}',
              if (nativeSummary != null && nativeSummary.isNotEmpty)
                '摘要: $nativeSummary',
              if (nativeDetectedAt != null) '诊断记录时间: $nativeDetectedAt',
              if (fallbackLogFile != null && fallbackLogFile.isNotEmpty)
                '日志文件: $fallbackLogFile',
            ].join('\n'),
      filePath: fallbackLogFile,
      nativeIssueId: nativeDiagnostic?['id']?.toString(),
    );
  }

  String? _formatDiagnosticTime(dynamic rawValue) {
    final millis = rawValue is num
        ? rawValue.toInt()
        : int.tryParse(rawValue?.toString() ?? '');
    if (millis == null || millis <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<String?> _getTodayInfoLogPath() async {
    final dir = await FlutterLogger.getTodayLogsDir();
    if (dir == null || dir.trim().isEmpty) return null;
    final normalized = dir.replaceAll('\\', '/');
    final segments = normalized.split('/');
    final day = segments.isEmpty ? '' : segments.last;
    if (day.isEmpty) return null;
    final separator = dir.contains('\\') ? '\\' : '/';
    return '$dir$separator${day}_info.log';
  }

  Future<void> _copyRuntimeDiagnostic() async {
    final diagnostic = _runtimeDiagnostic;
    if (diagnostic == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: diagnostic.copyText));
      if (!mounted) return;
      UINotifier.success(context, '诊断信息已复制');
    } catch (_) {
      if (!mounted) return;
      UINotifier.error(context, '复制诊断信息失败');
    }
  }

  Future<void> _openRuntimeDiagnosticFile() async {
    final diagnostic = _runtimeDiagnostic;
    final filePath = diagnostic?.filePath;
    if (diagnostic == null || filePath == null || filePath.trim().isEmpty) {
      if (!mounted) return;
      UINotifier.error(context, '当前没有可打开的诊断文件');
      return;
    }

    final opened = await PermissionService.instance.openDiagnosticFile(
      filePath,
    );
    if (!mounted) return;
    if (opened) {
      UINotifier.info(context, '已尝试打开诊断文件');
    } else {
      await Clipboard.setData(ClipboardData(text: filePath));
      if (!mounted) return;
      UINotifier.warning(context, '无法直接打开，已复制日志路径');
    }
  }

  Future<void> _dismissRuntimeDiagnosticDrawer() async {
    final diagnostic = _runtimeDiagnostic;
    if (diagnostic == null) return;
    _dismissedDiagnosticIds.add(diagnostic.id);
    final nativeIssueId = diagnostic.nativeIssueId;
    if (nativeIssueId != null && nativeIssueId.isNotEmpty) {
      await PermissionService.instance.markRuntimeDiagnosticHandled(
        nativeIssueId,
      );
    }
    if (!mounted) return;
    setState(() {
      _runtimeDiagnostic = null;
      _runtimeDiagnosticExpanded = false;
    });
  }

  Future<void> _openSettingsFromDiagnostic() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(themeService: widget.themeService),
      ),
    );
    if (!mounted) return;
    await _checkPermissionIssues(autoOpenDiagnostic: true);
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

      final hasPermissionIssues =
          !storageGranted ||
          !notificationGranted ||
          !accessibilityEnabled ||
          !usageStatsGranted;

      // 如果有权限问题，自动关闭截屏开关
      if (hasPermissionIssues) {
        await _appService.saveScreenshotEnabled(false);
        if (mounted) {
          setState(() {
            _screenshotEnabled = false;
          });

          UINotifier.info(
            context,
            AppLocalizations.of(context).autoDisabledDueToPermissions,
            duration: const Duration(seconds: 3),
          );
        }
      }
    } catch (e) {
      print('检查截屏开关状态失败: $e');
    }
  }

  String get _todayKey {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}';
  }

  Future<void> _preloadMorningInsights() async {
    try {
      final insights = await _dailySummaryService.loadMorningInsights(
        _todayKey,
      );
      if (!mounted) return;
      if (insights != null && insights.tips.isNotEmpty) {
        setState(() {
          _resetMorningDeckForInsights(insights);
          _morningInsights = insights;
          if (_morningTipIndex >= insights.tips.length) {
            _morningTipIndex = -1;
            _currentMorningTip = null;
          }
        });
      } else {
        setState(() {
          _morningInsights = null;
          _morningTipIndex = -1;
          _currentMorningTip = null;
          _clearMorningDeck();
        });
      }
    } catch (_) {
      // 静默忽略，避免影响首屏加载
    }
  }

  Future<void> _cycleMorningTip({bool ensureGenerate = false}) async {
    if (ensureGenerate && _morningGenerationRunning) {
      if (!mounted) return;
      setState(() {
        _morningInsights = null;
        _morningTipIndex = -1;
        _currentMorningTip = null;
        _clearMorningDeck();
      });
      return;
    }

    try {
      MorningInsights? insights;

      if (ensureGenerate) {
        insights = await _dailySummaryService.loadMorningInsights(_todayKey);
        if (!mounted) return;

        final bool missing = insights == null || insights.tips.isEmpty;
        if (missing) {
          if (_morningGenerationRunning) {
            setState(() {
              _morningInsights = null;
              _morningTipIndex = -1;
              _currentMorningTip = null;
              _clearMorningDeck();
            });
            return;
          }

          setState(() {
            _morningGenerationRunning = true;
            _morningInsights = null;
            _morningTipIndex = -1;
            _currentMorningTip = null;
            _clearMorningDeck();
          });
          MorningInsights? generated;
          try {
            generated = await _dailySummaryService.generateMorningInsights(
              _todayKey,
            );
            if (!mounted) return;
            if (generated == null || generated.tips.isEmpty) {
              setState(() {
                _morningInsights = null;
                _morningTipIndex = -1;
                _currentMorningTip = null;
                _clearMorningDeck();
              });
            } else {
              _applyMorningInsights(generated);
            }
          } catch (_) {
            if (!mounted) return;
            setState(() {
              _morningInsights = null;
              _morningTipIndex = -1;
              _currentMorningTip = null;
              _clearMorningDeck();
            });
          } finally {
            if (mounted) {
              setState(() {
                _morningGenerationRunning = false;
              });
            } else {
              _morningGenerationRunning = false;
            }
          }
          return;
        }
      }

      insights ??= await _dailySummaryService.fetchOrGenerateMorningInsights(
        _todayKey,
      );
      if (!mounted) return;
      if (insights == null || insights.tips.isEmpty) {
        setState(() {
          _morningInsights = insights;
          _morningTipIndex = -1;
          _currentMorningTip = null;
          _clearMorningDeck();
        });
        return;
      }

      _applyMorningInsights(insights);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _morningTipIndex = -1;
        _currentMorningTip = null;
        _clearMorningDeck();
      });
    }
  }

  void _clearMorningDeck() {
    _morningTipDeck = <int>[];
    _morningTipDeckSignature = null;
    _lastMorningTipIndex = null;
  }

  void _resetMorningDeckForInsights(MorningInsights insights) {
    final String signature = _buildMorningDeckSignature(insights);
    if (_morningTipDeckSignature != signature) {
      _morningTipDeckSignature = signature;
      _morningTipDeck = <int>[];
      _lastMorningTipIndex = null;
    }
  }

  String _buildMorningDeckSignature(MorningInsights insights) {
    return '${insights.dateKey}|${insights.sourceDateKey}|${insights.tips.length}|${insights.createdAt}';
  }

  void _rebuildMorningDeck(int total, {int? exclude}) {
    if (total <= 0) {
      _morningTipDeck = <int>[];
      return;
    }
    final List<int> indices = List<int>.generate(total, (index) => index);
    indices.shuffle(_random);
    if (exclude != null &&
        total > 1 &&
        indices.isNotEmpty &&
        indices.first == exclude) {
      final int swapIndex = indices.indexWhere((value) => value != exclude, 1);
      if (swapIndex != -1) {
        final int temp = indices[0];
        indices[0] = indices[swapIndex];
        indices[swapIndex] = temp;
      }
    }
    _morningTipDeck = indices;
  }

  void _applyMorningInsights(MorningInsights insights) {
    if (!mounted) return;
    final List<MorningInsightEntry> tips = insights.tips;
    _resetMorningDeckForInsights(insights);
    if (_morningTipDeck.isEmpty) {
      _rebuildMorningDeck(tips.length, exclude: _lastMorningTipIndex);
    }
    int nextIndex;
    if (_morningTipDeck.isNotEmpty) {
      nextIndex = _morningTipDeck.removeAt(0);
    } else {
      nextIndex = tips.length <= 1 ? 0 : _random.nextInt(tips.length);
      if (_lastMorningTipIndex != null &&
          tips.length > 1 &&
          nextIndex == _lastMorningTipIndex) {
        nextIndex = (nextIndex + 1) % tips.length;
      }
    }
    setState(() {
      _morningInsights = insights;
      _morningTipIndex = nextIndex;
      _currentMorningTip = tips[nextIndex];
    });
    _lastMorningTipIndex = nextIndex;
  }

  Future<void> _openMorningSummary() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailySummaryPage(dateKey: _todayKey)),
    );
  }

  Future<void> _handleHomeRefresh() async {
    IndicatorResult result = IndicatorResult.success;
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context);

    if (!_isMorningInsightsAvailable(now)) {
      setState(() {
        _morningCooldownMessage = null;
        _morningCooldownUntil = null;
        _morningInsights = null;
        _morningTipIndex = -1;
        _currentMorningTip = null;
        _clearMorningDeck();
      });
      _refreshController.finishRefresh(result);
      return;
    }

    if (_morningCooldownUntil != null && now.isBefore(_morningCooldownUntil!)) {
      setState(() {
        _morningCooldownMessage = l10n.homeMorningTipsCooldownMessage;
      });
      _refreshController.finishRefresh(result);
      return;
    }

    _morningRefreshHistory.removeWhere(
      (ts) => now.difference(ts) > _morningRefreshWindow,
    );
    if (_morningRefreshHistory.length >= _morningMaxRefreshInWindow) {
      setState(() {
        _morningCooldownUntil = now.add(_morningCooldownDuration);
        _morningCooldownMessage = l10n.homeMorningTipsCooldownMessage;
      });
      _refreshController.finishRefresh(result);
      return;
    }

    try {
      _morningRefreshHistory.add(now);
      await _loadData(soft: true);
      await _cycleMorningTip(ensureGenerate: true);
      if (mounted) {
        setState(() {
          _morningCooldownMessage = null;
        });
      }
    } catch (_) {
      result = IndicatorResult.fail;
    } finally {
      if (mounted) {
        _refreshController.finishRefresh(result);
      }
    }
  }

  /// 刷新权限状态
  Future<void> _refreshPermissions() async {
    try {
      final permissionService = PermissionService.instance;

      // 显示加载提示
      if (mounted) {
        UINotifier.info(
          context,
          AppLocalizations.of(context).refreshingPermissionsInfo,
          duration: const Duration(seconds: 1),
        );
      }

      // 强制刷新权限状态
      await permissionService.forceRefreshPermissions();

      // 失效统计缓存，确保后续读取为最新
      await ScreenshotService.instance.invalidateStatsCache();
      // 立即重新加载统计
      await _loadStats();

      // 重新检查权限问题
      await _checkPermissionIssues(autoOpenDiagnostic: true);

      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).permissionsRefreshed,
          duration: const Duration(seconds: 1),
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).refreshPermissionsFailed('$e'),
        );
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
              _buildPermissionStatusItem(
                AppLocalizations.of(context).storagePermissionTitle,
                permissions['storage'] ?? false,
              ),
              _buildPermissionStatusItem(
                AppLocalizations.of(context).notificationPermissionTitle,
                permissions['notification'] ?? false,
              ),
              _buildPermissionStatusItem(
                AppLocalizations.of(context).accessibilityPermissionTitle,
                permissions['accessibility'] ?? false,
              ),
              _buildPermissionStatusItem(
                AppLocalizations.of(context).screenRecordingPermissionTitle,
                true,
              ),
            ],
          ),
          actions: [
            UIDialogAction<String>(
              text: AppLocalizations.of(context).goToSettings,
              result: 'go_settings',
            ),
            UIDialogAction<String>(
              text: AppLocalizations.of(context).dialogOk,
              style: UIDialogActionStyle.primary,
              result: 'ok',
            ),
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
        UINotifier.error(
          context,
          AppLocalizations.of(context).checkPermissionStatusFailed('$e'),
        );
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
              : const Icon(Icons.cancel, color: AppTheme.destructive, size: 20),
          const SizedBox(width: 8),
          Text(name),
          const Spacer(),
          Text(
            granted
                ? AppLocalizations.of(context).grantedLabel
                : AppLocalizations.of(context).notGrantedLabel,
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

  Widget _buildToolbarActionButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          splashRadius: 20,
          iconSize: 22,
          visualDensity: VisualDensity.compact,
          icon: icon,
        ),
      ),
    );
  }

  Widget _buildRuntimeDiagnosticDrawer() {
    final diagnostic = _runtimeDiagnostic;
    if (diagnostic == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final expanded = _runtimeDiagnosticExpanded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing4,
        AppTheme.spacing3,
        AppTheme.spacing4,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: AppTheme.destructive.withValues(alpha: 0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              onTap: () {
                setState(() {
                  _runtimeDiagnosticExpanded = !_runtimeDiagnosticExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.destructive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.destructive,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            diagnostic.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing1),
                          Text(
                            diagnostic.summary,
                            maxLines: expanded ? null : 2,
                            overflow: expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭诊断面板',
                      onPressed: _dismissRuntimeDiagnosticDrawer,
                      icon: const Icon(Icons.close),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacing4,
                  0,
                  AppTheme.spacing4,
                  AppTheme.spacing4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final detail in diagnostic.details)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTheme.spacing2,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppTheme.destructive,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacing2),
                            Expanded(
                              child: Text(
                                detail,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppTheme.spacing2),
                    Wrap(
                      spacing: AppTheme.spacing2,
                      runSpacing: AppTheme.spacing2,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copyRuntimeDiagnostic,
                          icon: const Icon(
                            Icons.content_copy_outlined,
                            size: 18,
                          ),
                          label: const Text('复制信息'),
                        ),
                        OutlinedButton.icon(
                          onPressed: diagnostic.filePath == null
                              ? null
                              : _openRuntimeDiagnosticFile,
                          icon: const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 18,
                          ),
                          label: const Text('打开此文件'),
                        ),
                        if (diagnostic.showSettingsAction)
                          TextButton.icon(
                            onPressed: _openSettingsFromDiagnostic,
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            label: const Text('打开设置'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeToolbarIcon(IconData icon, {Color? color}) {
    return Icon(icon, size: 22, weight: 300, color: color);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 构建 AppBar 的 actions（选择模式时显示批量操作）
    final List<String> selectablePackages = _selectedApps
        .where(_isAppSelectable)
        .map((app) => app.packageName)
        .toList();
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
                  if (selectablePackages.isNotEmpty &&
                      _selectedPackages.length == selectablePackages.length) {
                    _selectedPackages.clear();
                  } else {
                    _selectedPackages
                      ..clear()
                      ..addAll(selectablePackages);
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
        // Keep the same background when content scrolls under the AppBar (Material 3).
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 48,
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        titleSpacing: 0,
        actions: appBarActions,
        title: _selectionMode
            ? Padding(
                padding: const EdgeInsets.only(left: AppTheme.spacing4),
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).selectedItemsCount(_selectedPackages.length),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing4,
                ),
                child: Row(
                  children: [
                    // 左侧:语言切换图标
                    _buildToolbarActionButton(
                      icon: _buildHomeToolbarIcon(Icons.language),
                      tooltip: AppLocalizations.of(
                        context,
                      ).languageSettingTitle,
                      onPressed: _showLanguageBottomSheet,
                    ),

                    // 加号按钮
                    const SizedBox(width: AppTheme.spacing2),
                    _buildToolbarActionButton(
                      icon: _buildHomeToolbarIcon(Icons.add),
                      tooltip: AppLocalizations.of(context).navSelectApps,
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                  AppLocalizations.of(context).navSelectApps,
                                ),
                                actions: [
                                  IconButton(
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).whySomeAppsHidden,
                                    icon: const Icon(Icons.help_outline),
                                    onPressed: () async {
                                      // 收集已启用输入法及默认输入法
                                      final imeList =
                                          await ImeExclusionService.getEnabledImeList();
                                      final defaultIme =
                                          await ImeExclusionService.getDefaultImeInfo();

                                      final lines = <Widget>[];
                                      lines.add(
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).excludedAppsIntro,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      );
                                      lines.add(const SizedBox(height: 8));
                                      // 本应用
                                      lines.add(
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).excludedThisApp,
                                        ),
                                      );
                                      lines.add(
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).excludedAutomationApps,
                                        ),
                                      );
                                      // 输入法应用
                                      if (imeList.isNotEmpty) {
                                        lines.add(const SizedBox(height: 8));
                                        lines.add(
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).excludedImeApps,
                                          ),
                                        );
                                        for (final m in imeList) {
                                          final name = m['appName'] ?? '';
                                          lines.add(
                                            Text(
                                              '  - ${name.isNotEmpty ? name : AppLocalizations.of(context).unknownIme}',
                                            ),
                                          );
                                        }
                                      } else {
                                        lines.add(const SizedBox(height: 8));
                                        lines.add(
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).excludedImeAppsFiltered,
                                          ),
                                        );
                                      }
                                      if (defaultIme != null &&
                                          (defaultIme['packageName']
                                                  ?.isNotEmpty ??
                                              false)) {
                                        lines.add(const SizedBox(height: 8));
                                        lines.add(
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).currentDefaultIme(
                                              defaultIme['appName'] ?? '',
                                              defaultIme['packageName'] ?? '',
                                            ),
                                          ),
                                        );
                                      }
                                      await showUIDialog<void>(
                                        context: context,
                                        title: AppLocalizations.of(
                                          context,
                                        ).excludedAppsTitle,
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: lines,
                                        ),
                                        actions: [
                                          UIDialogAction(
                                            text: AppLocalizations.of(
                                              context,
                                            ).gotIt,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await _appService.saveSelectedApps(
                                        _savedSelectedApps,
                                      );
                                      if (mounted) Navigator.of(context).pop();
                                      await _loadData(soft: true);
                                    },
                                    child: Text(
                                      AppLocalizations.of(context).dialogDone,
                                    ),
                                  ),
                                ],
                              ),
                              body: AppSelectionWidget(
                                displayAsList: true,
                                onSelectionChanged: (apps) {
                                  _savedSelectedApps = apps;
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // 首页不再显示排序图标，排序在设置页调整
                    const SizedBox(width: AppTheme.spacing2),

                    // 搜索框 - 大幅增加flex权重
                    Expanded(flex: 7, child: _buildSearchBar(context)),

                    const SizedBox(width: AppTheme.spacing2),

                    // 搜索框右侧：权限提示 或 开关
                    _hasPermissionIssues
                        ? _buildToolbarActionButton(
                            icon: _buildHomeToolbarIcon(
                              Icons.warning,
                              color: AppTheme.destructive,
                            ),
                            tooltip: AppLocalizations.of(
                              context,
                            ).permissionMissing,
                            onPressed: _showPermissionStatus,
                          )
                        : _buildToolbarActionButton(
                            tooltip: _screenshotEnabled
                                ? AppLocalizations.of(context).stopScreenshot
                                : AppLocalizations.of(context).startScreenshot,
                            onPressed: _toggleScreenshotEnabled,
                            icon: _screenshotEnabled
                                ? _buildHomeToolbarIcon(
                                    Icons.camera_alt_outlined,
                                  )
                                : _buildHomeToolbarIcon(
                                    Icons.no_photography_outlined,
                                    color: AppTheme.destructive,
                                  ),
                          ),

                    // 右侧:主题切换图标
                    const SizedBox(width: AppTheme.spacing2),
                    _buildToolbarActionButton(
                      icon: _buildHomeToolbarIcon(
                        widget.themeService.themeModeIcon,
                      ),
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
          if (_runtimeDiagnostic != null) _buildRuntimeDiagnosticDrawer(),
          Expanded(
            child: EasyRefresh.builder(
              controller: _refreshController,
              header: _buildMorningHeader(context),
              onRefresh: _handleHomeRefresh,
              childBuilder: (context, physics) => _buildAppsList(physics),
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
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fillColor = isDark
        ? theme.colorScheme.surface
        : theme.scaffoldBackgroundColor;
    // Keep border style consistent with Screenshot Gallery search box.
    final Color borderColor = Colors.grey.withValues(alpha: 0.5);
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(8.0)),
      onTap: () => Navigator.pushNamed(context, '/search'),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(
              Icons.search,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              size: 18,
            ),
            const SizedBox(width: 2),
            Text(
              AppLocalizations.of(context).searchPlaceholder,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppsList(ScrollPhysics physics) {
    final bool hasApps = _selectedApps.isNotEmpty;
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
    if (now.hour > _morningAvailableHour) {
      return true;
    }
    if (now.hour < _morningAvailableHour) {
      return false;
    }
    return true;
  }

  Header _buildMorningHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return BuilderHeader(
      position: IndicatorPosition.above,
      triggerOffset: _morningRevealMaxHeight,
      clamping: false,
      builder: (context, state) {
        double visibleHeight = state.offset.clamp(0.0, _morningRevealMaxHeight);
        final bool isProcessing =
            state.mode == IndicatorMode.processing ||
            state.mode == IndicatorMode.ready;
        if (isProcessing) {
          visibleHeight = _morningRevealMaxHeight;
        }
        if (visibleHeight <= 0) {
          return const SizedBox.shrink();
        }

        final double progress = (visibleHeight / _morningRevealMaxHeight).clamp(
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
                  setState(() => _selectionMode = true);
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
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).dialogCancel,
          result: false,
        ),
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).remove,
          style: UIDialogActionStyle.destructive,
          result: true,
        ),
      ],
      barrierDismissible: false,
    );
    if (confirmed != true) return;

    final remaining = _savedSelectedApps
        .where((a) => !_selectedPackages.contains(a.packageName))
        .toList();
    await _appService.saveSelectedApps(remaining);
    if (!mounted) return;
    setState(() {
      _savedSelectedApps = remaining;
      _sortApps();
      _selectionMode = false;
      _selectedPackages.clear();
    });
    UINotifier.info(
      context,
      AppLocalizations.of(context).removedMonitoringToast(count),
    );
  }

  /// 显示语言选择底部弹窗
  void _showLanguageBottomSheet() {
    final t = AppLocalizations.of(context);
    final currentOption = LocaleService.instance.option;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => UISheetSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppTheme.spacing3),
            const UISheetHandle(),
            // 标题
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              child: Text(
                t.languageSettingTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            // 语言选项列表
            _buildLanguageOption(
              context: context,
              title: t.languageSystem,
              value: 'system',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'system',
                  toastLanguageName: t.languageSystem,
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: '中文',
              value: 'zh',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'zh',
                  toastLocale: const Locale('zh'),
                  toastLanguageName: '中文',
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: 'English',
              value: 'en',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'en',
                  toastLocale: const Locale('en'),
                  toastLanguageName: 'English',
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: '日本語',
              value: 'ja',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'ja',
                  toastLocale: const Locale('ja'),
                  toastLanguageName: '日本語',
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: '한국어',
              value: 'ko',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'ko',
                  toastLocale: const Locale('ko'),
                  toastLanguageName: '한국어',
                );
              },
            ),
            const SizedBox(height: AppTheme.spacing4),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLanguageSelection({
    required BuildContext sheetContext,
    required String option,
    Locale? toastLocale,
    required String toastLanguageName,
  }) async {
    await LocaleService.instance.setOption(option);
    if (!mounted) return;
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    final localization = await _loadToastLocalization(toastLocale);
    if (!mounted || localization == null) return;
    UINotifier.success(
      context,
      localization.languageChangedToast(toastLanguageName),
    );
  }

  Future<AppLocalizations?> _loadToastLocalization(Locale? locale) async {
    if (locale == null) {
      return AppLocalizations.of(context);
    }
    try {
      return await AppLocalizations.delegate.load(locale);
    } catch (_) {
      return AppLocalizations.of(context);
    }
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

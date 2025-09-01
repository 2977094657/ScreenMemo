import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_info.dart';
import '../services/app_selection_service.dart';
import '../services/screenshot_service.dart';
import '../services/permission_service.dart';
import '../services/theme_service.dart';
import '../services/startup_profiler.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../widgets/app_selection_widget.dart';
import 'settings_page.dart';
import '../services/flutter_logger.dart';

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
  bool _screenshotEnabled = false;
  int _screenshotInterval = 5;
  bool _isLoading = false; // 不显示全屏加载动画
  bool _initialized = true; // 直接认为已初始化，避免首屏Loading
  bool _hasPermissionIssues = false; // 权限问题状态
  Map<String, dynamic> _screenshotStats = {}; // 截图统计数据
  bool _selectionMode = false;
  final Set<String> _selectedPackages = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StartupProfiler.begin('HomePage.initState+loadData');
    // 将数据加载与权限检查延后到首帧之后，避免阻塞首帧
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadData();
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

      // 再加载统计数据（缓存优先），不阻塞应用列表
      await _loadStats();

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

    switch (mode) {
      case 'timeAsc':
        appsWithShots.sort((a, b) => compareByTime(a, b, desc: false));
        break;
      case 'timeDesc':
        appsWithShots.sort((a, b) => compareByTime(a, b, desc: true));
        break;
      case 'countAsc':
        appsWithShots.sort((a, b) => compareByCount(a, b, desc: false));
        break;
      case 'countDesc':
        appsWithShots.sort((a, b) => compareByCount(a, b, desc: true));
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

  Future<void> _toggleScreenshotEnabled() async {
    final newValue = !_screenshotEnabled;

    // 控制截屏服务
    final screenshotService = ScreenshotService.instance;

    if (newValue) {
      // 显示启动提示
      if (mounted) {
        UINotifier.info(context, '正在启动截屏服务...');
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
            UINotifier.error(context, '启动截屏服务失败，请检查权限设置', duration: const Duration(seconds: 3));
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
        String errorMessage = '启动失败: 未知错误';
        
        // 根据错误类型提供更具体的提示
        if (e.toString().contains('无障碍服务未启用')) {
          errorMessage = '无障碍服务未启用\n请前往设置页面启用无障碍服务';
        } else if (e.toString().contains('存储权限未授予')) {
          errorMessage = '存储权限未授予\n请前往设置页面授予存储权限';
        } else if (e.toString().contains('服务未运行')) {
          errorMessage = '服务未正常运行\n请尝试重新启动应用';
        } else if (e.toString().contains('Android版本')) {
          errorMessage = '系统版本不支持\n需要Android 11.0或以上版本';
        } else {
          errorMessage = e.toString();
        }

        if (mounted) {
          // 统一风格错误对话框
          await showUIDialog<void>(
            context: context,
            barrierDismissible: false,
            title: '启动失败',
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '提示：如果问题持续，请尝试重新启动应用或重新配置权限',
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
        UINotifier.success(context, '截屏已启用');
      } else {
        UINotifier.info(context, '截屏已停用');
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
      title: '设置截屏间隔',
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
                labelText: '间隔时间（秒）',
                hintText: '请输入5-60的整数',
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
            child: const Text(
              '范围：5-60秒，默认值：5秒。',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.info,
              ),
            ),
          ),
        ],
      ),
      actions: [
        const UIDialogAction(text: '取消'),
        UIDialogAction(
          text: '确定',
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final interval = int.tryParse(input);
            if (interval == null || interval < 5 || interval > 60) {
              UINotifier.error(ctx, '请输入5-60的有效整数');
              return;
            }
            await _updateScreenshotInterval(interval);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, '截屏间隔已设置为 $interval秒');
            }
          },
        ),
      ],
    );
  }

  Future<void> _onAppTap(AppInfo app) async {
    // TODO: 进入应用详情页面，显示截图历史
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

          UINotifier.info(context, '由于权限不足，截屏功能已自动关闭', duration: const Duration(seconds: 3));
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
        UINotifier.info(context, '正在刷新权限状态...', duration: const Duration(seconds: 1));
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
        UINotifier.success(context, '权限状态已刷新', duration: const Duration(seconds: 1));
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, '刷新权限状态失败: $e');
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
          title: '权限状态检查',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPermissionStatusItem('存储权限', permissions['storage'] ?? false),
              _buildPermissionStatusItem('通知权限', permissions['notification'] ?? false),
              _buildPermissionStatusItem('无障碍服务', permissions['accessibility'] ?? false),
              _buildPermissionStatusItem('屏幕录制权限', true),
            ],
          ),
          actions: const [
            UIDialogAction<String>(text: '前往设置', result: 'go_settings'),
            UIDialogAction<String>(text: '确定', style: UIDialogActionStyle.primary, result: 'ok'),
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
        UINotifier.error(context, '检查权限状态失败: $e');
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
            granted ? '已授权' : '未授权',
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        toolbarHeight: 48,
        title: _selectionMode
          ? Text(
              '已选择 ${_selectedPackages.length} 项',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            )
          : Row(
              children: [
                // 左侧：加号 与 排序
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: '选择监控应用',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('选择监控应用'),
                            actions: [
                              TextButton(
                                onPressed: () async {
                                  await _appService.saveSelectedApps(_selectedApps);
                                  if (mounted) Navigator.of(context).pop();
                                  await _loadData(soft: true);
                                },
                                child: const Text('完成'),
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

                // 搜索框
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.5), // 使用更明显的灰色边框
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05), // 添加轻微阴影使边框更明显
                          blurRadius: 1,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Icon(
                          Icons.search,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '搜索截图...',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // 搜索框右侧：权限提示 或 开关（与搜索框保持间距且同高）
                if (_hasPermissionIssues)
                  IconButton(
                    icon: const Icon(
                      Icons.warning,
                      color: AppTheme.destructive,
                    ),
                    onPressed: _showPermissionStatus,
                    tooltip: '权限缺失',
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: IconButton(
                      tooltip: _screenshotEnabled ? '停止截屏' : '开始截屏',
                      iconSize: 22,
                      onPressed: _toggleScreenshotEnabled,
                      icon: _screenshotEnabled
                          ? Icon(
                              Icons.camera_alt,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : const Icon(
                              Icons.no_photography_outlined,
                              color: AppTheme.destructive,
                            ),
                    ),
                  ),
              ],
            ),
        actions: _selectionMode ? [
          TextButton(
            onPressed: () {
              setState(() {
                _selectionMode = false;
                _selectedPackages.clear();
              });
            },
            child: const Text('取消'),
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
            child: const Text('全选'),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: '移除监测',
            onPressed: _selectedPackages.isEmpty ? null : _removeSelectedApps,
          ),
        ] : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(soft: true),
        child: _buildAppsList(),
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
            const Icon(
              Icons.apps,
              size: 64,
              color: AppTheme.mutedForeground,
            ),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              '暂无监控应用',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.mutedForeground,
              ),
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              '请在设置中选择要监控的应用',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mutedForeground,
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
            // 应用图标 - 直接显示，无容器背景
            SizedBox(
              width: 48,
              height: 48,
              child: app.icon != null
                  ? Image.memory(
                      app.icon!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    )
                  : const Icon(
                      Icons.android,
                      color: AppTheme.mutedForeground,
                      size: 32,
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
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),

            if (!_selectionMode)
              const Icon(
                Icons.chevron_right,
                color: AppTheme.mutedForeground,
              )
            else
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isSelected ? Colors.black : Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
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
    final appStats = _screenshotStats['appStatistics'] as Map<String, Map<String, dynamic>>? ?? {};
    final stat = appStats[packageName];
    
    if (stat == null) {
      return '0张 · 0.00MB · 暂无';
    }
    
    final count = stat['totalCount'] as int? ?? 0;
    final lastTime = stat['lastCaptureTime'] as DateTime?;
    final totalBytes = stat['totalSize'] as int? ?? 0;
    
    String timeStr = '暂无';
    if (lastTime != null) {
      final now = DateTime.now();
      final diff = now.difference(lastTime);
      
      if (diff.inMinutes < 1) {
        timeStr = '刚刚';
      } else if (diff.inHours < 1) {
        timeStr = '${diff.inMinutes}分钟前';
      } else if (diff.inDays < 1) {
        timeStr = '${diff.inHours}小时前';
      } else {
        timeStr = '${diff.inDays}天前';
      }
    }
    
    return '$count张 · ${_formatTotalSizeMBGBTB(totalBytes)} · $timeStr';
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
      title: '移除监测',
      message: '仅移除监测，不会删除对应图片。是否继续？',
      actions: const [
        UIDialogAction<bool>(text: '取消', result: false),
        UIDialogAction<bool>(text: '移除', style: UIDialogActionStyle.destructive, result: true),
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
    UINotifier.info(context, '已移除监测 $count 个应用（不删除图片）');
  }
}

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_info.dart';
import '../services/app_selection_service.dart';
import '../services/screenshot_service.dart';
import '../services/permission_service.dart';
import '../services/theme_service.dart';
import '../services/startup_profiler.dart';
import '../widgets/ui_components.dart';
import '../widgets/app_selection_widget.dart';
import 'settings_page.dart';

/// 主应用界面
class HomePage extends StatefulWidget {
  final ThemeService themeService;
  
  const HomePage({super.key, required this.themeService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  final AppSelectionService _appService = AppSelectionService.instance;

  List<AppInfo> _selectedApps = AppSelectionService.instance.selectedApps;
  String _sortMode = 'lastScreenshot';
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

  Future<void> _loadStats() async {
    StartupProfiler.begin('HomePage._loadStats');
    // 刷新时强制失效缓存，首帧仍可走缓存
    final stats = await ScreenshotService.instance.getScreenshotStatsCachedFirst();
    if (mounted) {
      setState(() {
        _screenshotStats = stats;
      });
      _sortApps();
    }
    StartupProfiler.end('HomePage._loadStats');
  }

  /// 强制从数据库计算并刷新缓存，然后更新UI
  Future<void> _loadStatsFresh() async {
    StartupProfiler.begin('HomePage._loadStatsFresh');
    // 清除缓存，强制走计算
    await ScreenshotService.instance.invalidateStatsCache();
    final stats = await ScreenshotService.instance.getScreenshotStats();
    if (mounted) {
      setState(() {
        _screenshotStats = stats;
      });
      _sortApps();
    }
    StartupProfiler.end('HomePage._loadStatsFresh');
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
      
      // 加载截图统计数据
      await _loadStats();

      if (mounted) {
        setState(() {
          _selectedApps = selectedApps;
          _sortMode = sortMode;
          _screenshotEnabled = screenshotEnabled;
          _screenshotInterval = screenshotInterval;
          _isLoading = false;
        });

        // 根据排序模式排序应用
        _sortApps();

        // 检查权限状态
        _checkPermissionIssues();

        // 检查截屏开关状态是否需要自动关闭
        _checkScreenshotToggleState();
      }
    } catch (e) {
      print('加载数据失败: $e');
      // 出错也不显示全屏加载
    }
    StartupProfiler.end('HomePage._loadData');
  }

  void _sortApps() {
    final appStats = _screenshotStats['appStatistics'] as Map<String, Map<String, dynamic>>? ?? {};
    
    switch (_sortMode) {
      case 'lastScreenshot':
        _selectedApps.sort((a, b) {
          final aLastTime = appStats[a.packageName]?['lastCaptureTime'] as DateTime?;
          final bLastTime = appStats[b.packageName]?['lastCaptureTime'] as DateTime?;
          
          // 没有截图的排在后面
          if (aLastTime == null && bLastTime == null) return 0;
          if (aLastTime == null) return 1;
          if (bLastTime == null) return -1;
          
          return bLastTime.compareTo(aLastTime); // 最近的在前面
        });
        break;
      case 'screenshotCount':
        _selectedApps.sort((a, b) {
          final aCount = appStats[a.packageName]?['totalCount'] as int? ?? 0;
          final bCount = appStats[b.packageName]?['totalCount'] as int? ?? 0;
          return bCount.compareTo(aCount); // 数量多的在前面
        });
        break;
    }
  }

  Future<void> _toggleScreenshotEnabled() async {
    final newValue = !_screenshotEnabled;

    // 控制截屏服务
    final screenshotService = ScreenshotService.instance;

    if (newValue) {
      // 显示启动提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在启动截屏服务...'),
            backgroundColor: AppTheme.info,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // 启动定时截屏
      try {
        final success = await screenshotService.startScreenshotService(_screenshotInterval);
        if (!success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('启动截屏服务失败，请检查权限设置'),
                backgroundColor: AppTheme.destructive,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
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
          // 显示详细错误对话框
          showDialog(
            context: context,
            barrierDismissible: false,
              builder: (context) => AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppTheme.destructive,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text('启动失败'),
                ],
              ),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确定'),
                ),
              ],
            ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? '截屏已启用' : '截屏已停用'),
          backgroundColor: newValue ? AppTheme.success : AppTheme.info,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacing6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: const Icon(
                      Icons.timer,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Text(
                    '设置截屏间隔',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacing4),

              // 输入框
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
                    hintText: '请输入大于等于1的数字',
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

              // 提示信息
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppTheme.info,
                      size: 16,
                    ),
                    const SizedBox(width: AppTheme.spacing2),
                    const Expanded(
                      child: Text(
                        '最小值为1秒，无最大值限制',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacing5),

              // 按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UIButton(
                    text: '取消',
                    variant: UIButtonVariant.outline,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  UIButton(
                    text: '确定',
                    onPressed: () async {
                      final input = controller.text.trim();
                      final interval = int.tryParse(input);

                      if (interval == null || interval < 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('请输入大于等于1的有效数字'),
                            backgroundColor: AppTheme.destructive,
                          ),
                        );
                        return;
                      }

                      await _updateScreenshotInterval(interval);
                      if (mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('截屏间隔已设置为 $interval秒'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    // 返回后刷新统计，确保首页数字最新
    await ScreenshotService.instance.invalidateStatsCache();
    await _loadStats();
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

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('由于权限不足，截屏功能已自动关闭'),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在刷新权限状态...'),
            backgroundColor: AppTheme.info,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('权限状态已刷新'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新权限状态失败: $e'),
            backgroundColor: AppTheme.destructive,
            behavior: SnackBarBehavior.floating,
          ),
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
        showDialog(
          context: context,
          barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacing6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                        child: const Icon(
                          Icons.security,
                          color: AppTheme.info,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing3),
                      Text(
                        '权限状态检查',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppTheme.spacing4),

                  // 权限列表
                  _buildPermissionStatusItem('存储权限', permissions['storage'] ?? false),
                  _buildPermissionStatusItem('通知权限', permissions['notification'] ?? false),
                  _buildPermissionStatusItem('无障碍服务', permissions['accessibility'] ?? false),
                  _buildPermissionStatusItem('屏幕录制权限', true), // 总是显示为已授权

                  const SizedBox(height: AppTheme.spacing4),

                  // 按钮
                  Row(
                    children: [
                      Expanded(
                        child: UIButton(
                          text: '前往设置',
                          onPressed: () {
                            Navigator.of(context).pop();
                            // 直接切换到底部导航的“设置”页
                            // 通过通知上层Tab切换（使用Navigator推到MainNavigationPage时可传参，这里直接push一个到设置页的路由）
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SettingsPage(themeService: widget.themeService),
                              ),
                            );
                          },
                          variant: UIButtonVariant.ghost,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing3),
                      Expanded(
                        child: UIButton(
                          text: '确定',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查权限状态失败: $e'),
            backgroundColor: AppTheme.destructive,
            behavior: SnackBarBehavior.floating,
          ),
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
            style: TextStyle(
              color: granted
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : AppTheme.destructive,
              fontWeight: FontWeight.bold,
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_selectionMode) ...[
              GestureDetector(
                onTap: _showIntervalDialog,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '$_screenshotInterval秒',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: 1,
                      width: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing4),
              Switch(
                value: _screenshotEnabled,
                onChanged: (value) => _toggleScreenshotEnabled(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ] else ...[
              Text(
                '已选择 ${_selectedPackages.length} 项',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.add),
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
            if (_hasPermissionIssues)
              IconButton(
                icon: const Icon(
                  Icons.warning,
                  color: AppTheme.destructive,
                ),
                onPressed: _showPermissionStatus,
                tooltip: '权限缺失',
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _refreshPermissions();
                await _loadData(soft: true);
              },
              tooltip: '刷新数据和权限状态',
            ),
            IconButton(
              icon: Icon(widget.themeService.themeModeIcon),
              onPressed: () async {
                await widget.themeService.toggleTheme();
              },
              tooltip: widget.themeService.themeModeDescription,
            ),
          ] else ...[
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
          ],
        ],
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        title: const Text('移除监测'),
        content: const Text('仅移除监测，不会删除对应图片。是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('移除')),
        ],
      ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已移除监测 $count 个应用（不删除图片）'),
        backgroundColor: AppTheme.info,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

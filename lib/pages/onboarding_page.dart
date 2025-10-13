import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../widgets/ui_dialog.dart';
import '../widgets/ui_components.dart';
import '../widgets/app_selection_widget.dart';
import '../models/app_state.dart';
import '../models/app_info.dart';
import '../services/permission_service.dart';
import '../services/app_selection_service.dart';
import '../services/theme_service.dart';
import 'main_navigation_page.dart';

/// 引导页面
class OnboardingPage extends StatefulWidget {
  final ThemeService themeService;
  
  const OnboardingPage({super.key, required this.themeService});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final AppState _appState = AppState.instance;
  final PermissionService _permissionService = PermissionService.instance;
  final AppSelectionService _appSelectionService = AppSelectionService.instance;
  List<AppInfo> _selectedApps = [];

  // 保活权限状态
  Map<String, dynamic> _keepAlivePermissions = {};
  String _deviceInfo = '';
  bool _isLoadingKeepAlive = true;

  // 电池权限检查定时器
  Timer? _batteryPermissionTimer;
  int _batteryCheckCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupPermissionCallbacks();
    _checkInitialPermissions();
    _loadKeepAlivePermissions();
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('应用生命周期状态变化: $state');
    if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台时，刷新权限状态
      print('应用恢复前台，开始刷新权限状态...');
      // 延迟一点时间，确保系统状态已经稳定
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          print('执行权限状态刷新');
          _loadKeepAlivePermissions();
        }
      });
    }
  }

  Future<void> _loadKeepAlivePermissions() async {
    print('开始加载保活权限状态...');
    try {
      // 显示加载状态
      if (mounted) {
        setState(() {
          _isLoadingKeepAlive = true;
        });
      }

      print('调用 Android 端获取权限状态...');
      // 获取权限状态
      final permissionStatus = await platform.invokeMethod('getPermissionStatus');
      final deviceInfo = await platform.invokeMethod('getDeviceInfo');

      print('Android 端返回权限状态: $permissionStatus');
      print('设备信息: $deviceInfo');

      // 更新状态
      if (mounted) {
        setState(() {
          final oldStatus = Map<String, dynamic>.from(_keepAlivePermissions);
          _keepAlivePermissions = Map<String, dynamic>.from(permissionStatus ?? {});
          _deviceInfo = deviceInfo ?? '未知设备';
          _isLoadingKeepAlive = false;

          print('旧权限状态: $oldStatus');
          print('新权限状态: $_keepAlivePermissions');

          // 检查电池优化状态是否变化
          final oldBatteryStatus = oldStatus['battery_optimization'] ?? false;
          final newBatteryStatus = _keepAlivePermissions['battery_optimization'] ?? false;

          print('电池优化状态变化: $oldBatteryStatus -> $newBatteryStatus');

          if (oldBatteryStatus != newBatteryStatus) {
            if (newBatteryStatus) {
              // 授权完成后不再显示底部通知
            } else {
              // 状态变更为未授权时也不弹出通知，交由页面状态体现
            }
          }
        });
      }
      print('权限状态更新完成');
    } catch (e) {
      print('加载保活权限失败: $e');
      if (mounted) {
        setState(() {
          _keepAlivePermissions = {
            'battery_optimization': false,
            'autostart': false,
            'background': false,
            'battery_whitelist_actual': false,
          };
          _isLoadingKeepAlive = false;
        });

        // 显示错误提示
          UINotifier.error(context, '加载权限状态失败: $e', duration: const Duration(seconds: 3));
      }
    }
  }

  /// 启动电池权限检查定时器
  void _startBatteryPermissionCheck() {
    print('启动电池权限定时检查...');
    _batteryCheckCount = 0;
    _batteryPermissionTimer?.cancel(); // 取消之前的定时器

    _batteryPermissionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      _batteryCheckCount++;
      print('电池权限检查第 $_batteryCheckCount 次');

      // 检查权限状态
      try {
        final permissionStatus = await platform.invokeMethod('getPermissionStatus');
        final newBatteryStatus = permissionStatus?['battery_optimization'] ?? false;
        final oldBatteryStatus = _keepAlivePermissions['battery_optimization'] ?? false;

        print('定时检查 - 旧状态: $oldBatteryStatus, 新状态: $newBatteryStatus');

        if (newBatteryStatus != oldBatteryStatus) {
          print('检测到电池权限状态变化，更新UI');
          await _loadKeepAlivePermissions();
          if (newBatteryStatus) {
            // 权限已授权，停止检查
            print('电池权限已授权，停止定时检查');
            timer.cancel();
          }
        }
      } catch (e) {
        print('定时检查电池权限失败: $e');
      }
    });
  }

  /// 停止电池权限检查定时器
  void _stopBatteryPermissionCheck() {
    _batteryPermissionTimer?.cancel();
    _batteryPermissionTimer = null;
    _batteryCheckCount = 0;
  }

  /// 显示自启动权限确认对话框
  Future<bool> _showAutoStartConfirmDialog() async {
    return await showUIDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: AppLocalizations.of(context).confirmPermissionSettingsTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).confirmAutostartQuestion,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
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
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).autostartPermissionNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.info,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction<bool>(text: AppLocalizations.of(context).notYet, result: false),
        UIDialogAction<bool>(text: AppLocalizations.of(context).done, style: UIDialogActionStyle.primary, result: true),
      ],
    ) ?? false;
  }

  void _setupPermissionCallbacks() {
    _permissionService.onAccessibilityChanged = (enabled) {
      _appState.setAccessibilityEnabled(enabled);
      // 不要在单个权限授权后立即跳转，让用户手动控制流程
    };

    _permissionService.onMediaProjectionChanged = (granted) {
      _appState.setMediaProjectionGranted(granted);
      // 不要在单个权限授权后立即跳转，让用户手动控制流程
    };

    // 添加权限更新回调
    _permissionService.onPermissionsUpdated = () {
      _checkInitialPermissions();
      // 强制UI重建
      if (mounted) {
        setState(() {});
      }
    };
  }
  
  Future<void> _checkInitialPermissions() async {
    final permissions = await _permissionService.checkAllPermissions();
    _appState.updatePermissions(
      accessibility: permissions['accessibility'],
      mediaProjection: permissions['mediaProjection'],
      storage: permissions['storage'],
      notification: permissions['notification'],
      usageStats: permissions['usage_stats'],
    );
  }
  
  // 移除自动跳转逻辑，让用户通过按钮控制流程
  
  void _navigateToHome() async {
    // 标记引导已完成
    try {
      await PermissionService.instance.setOnboardingCompleted(true);
      await PermissionService.instance.setFirstLaunch(false);
    } catch (e) {
      print('保存引导完成状态失败: $e');
    }

    // 检查mounted状态，避免异步操作后使用已销毁的context
    if (!mounted) return;

    // 立即跳转到首页，使用无动画的路由切换以获得最快的响应
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MainNavigationPage(themeService: widget.themeService),
        transitionDuration: Duration.zero, // 无动画，立即跳转
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onAppSelectionChanged(List<AppInfo> selectedApps) {
    setState(() {
      _selectedApps = selectedApps;
    });
  }

  /// 异步保存选中的应用，不阻塞UI
  void _saveSelectedAppsAsync() {
    // 使用 Future.microtask 确保在下一个事件循环中执行，不阻塞当前UI
    Future.microtask(() async {
      try {
        print('开始异步保存选中的应用，数量: ${_selectedApps.length}');
        await _appSelectionService.saveSelectedApps(_selectedApps);
        print('应用选择保存完成');
      } catch (e) {
        print('保存选中应用失败: $e');
      }
    });
  }
  
  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部进度指示器
            _buildProgressIndicator(),
            
            // 页面内容
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // 禁用滑动
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildWelcomePage(),
                  _buildPermissionsPage(),
                  _buildAppSelectionPage(),
                  _buildCompletePage(),
                ],
              ),
            ),
            
            // 底部导航按钮
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      child: Column(
        children: [
          Row(
            children: List.generate(4, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: index < 3 ? AppTheme.spacing2 : 0,
                  ),
                  child: UIProgress(
                    value: index <= _currentPage ? 1.0 : 0.0,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            AppLocalizations.of(context).stepProgress(_currentPage + 1, 4),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
  
  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 顶部使用应用Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            child: Image.asset(
              'logo.png',
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),

          const SizedBox(height: AppTheme.spacing4),
          
          // 标题
          Text(
            AppLocalizations.of(context).onboardingWelcomeTitle,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppTheme.spacing3),

          // 描述
          Text(
            AppLocalizations.of(context).onboardingWelcomeDesc,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppTheme.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppTheme.spacing4),
          
          // 功能特点
          UICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).onboardingKeyFeaturesTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTheme.spacing4),
                _buildFeatureItem(Icons.memory, AppLocalizations.of(context).featureSmartNotes),
                _buildFeatureItem(Icons.search, AppLocalizations.of(context).featureQuickSearch),
                _buildFeatureItem(Icons.privacy_tip, AppLocalizations.of(context).featureLocalStorage),
                // 移除“使用习惯分析”展示
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing1),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: AppTheme.primary,
          ),
          const SizedBox(width: AppTheme.spacing2),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
  
  Widget _buildPermissionsPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing2,
      ),
      child: Column(
        children: [
          // 顶部间距
          const SizedBox(height: AppTheme.spacing8),

          // 标题和刷新按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).onboardingPermissionsTitle,
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: _isLoadingKeepAlive ? null : () {
                  setState(() {
                    _isLoadingKeepAlive = true;
                  });
                  _loadKeepAlivePermissions();
                },
                icon: _isLoadingKeepAlive
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
                  tooltip: AppLocalizations.of(context).refreshPermissionStatus,
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacing1),

          Text(
            AppLocalizations.of(context).onboardingPermissionsDesc,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppTheme.spacing4),

          // 权限列表
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildPermissionCard(
                  icon: Icons.storage,
                  title: AppLocalizations.of(context).storagePermissionTitle,
                  description: AppLocalizations.of(context).storagePermissionDesc,
                  isGranted: _appState.storagePermissionGranted,
                  onRequest: () async {
                    await _permissionService.requestStoragePermission();
                    final permissions = await _permissionService.checkAllPermissions();
                    _appState.updatePermissions(
                      storage: permissions['storage'],
                    );
                    // 强制UI重建
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),

                const SizedBox(height: AppTheme.spacing5),

                _buildPermissionCard(
                  icon: Icons.notifications,
                  title: AppLocalizations.of(context).notificationPermissionTitle,
                  description: AppLocalizations.of(context).notificationPermissionDesc,
                  isGranted: _appState.notificationPermissionGranted,
                  onRequest: () async {
                    await _permissionService.requestNotificationPermission();
                    // 给系统权限弹窗/页面一些时间，避免立刻重建导致跳页
                    await Future.delayed(const Duration(milliseconds: 500));
                    final permissions = await _permissionService.checkAllPermissions();
                    _appState.updatePermissions(
                      notification: permissions['notification'],
                    );
                    if (!mounted) return;
                    // 仅在当前页时刷新，避免页面重置
                    setState(() {});
                  },
                ),

                const SizedBox(height: AppTheme.spacing5),

                _buildPermissionCard(
                  icon: Icons.accessibility,
                  title: AppLocalizations.of(context).accessibilityPermissionTitle,
                  description: AppLocalizations.of(context).accessibilityPermissionDesc,
                  isGranted: _appState.accessibilityEnabled,
                  onRequest: () async {
                    _permissionService.requestAccessibilityPermission();
                    // 延迟检查权限状态，因为用户需要在设置中手动开启
                    await Future.delayed(const Duration(milliseconds: 500));
                    final permissions = await _permissionService.checkAllPermissions();
                    _appState.updatePermissions(
                      accessibility: permissions['accessibility'],
                    );
                    // 强制UI重建
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),

                const SizedBox(height: AppTheme.spacing5),

                _buildPermissionCard(
                  icon: Icons.analytics,
                  title: AppLocalizations.of(context).usageStatsPermissionTitle,
                  description: AppLocalizations.of(context).usageStatsPermissionDesc,
                  isGranted: _appState.usageStatsPermissionGranted,
                  onRequest: () async {
                    await _permissionService.requestUsageStatsPermission();
                    // 延迟检查权限状态，因为用户需要在设置中手动开启
                    await Future.delayed(const Duration(milliseconds: 500));
                    final permissions = await _permissionService.checkAllPermissions();
                    _appState.updatePermissions(
                      usageStats: permissions['usage_stats'],
                    );
                    // 强制UI重建
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),

                const SizedBox(height: AppTheme.spacing5),

                _buildPermissionCard(
                  icon: Icons.battery_saver,
                  title: AppLocalizations.of(context).batteryOptimizationTitle,
                  description: AppLocalizations.of(context).batteryOptimizationDesc,
                  isGranted: _keepAlivePermissions['battery_optimization'] ?? false,
                  onRequest: () async {
                    // 先显示提示
                    if (mounted) {
                      UINotifier.info(context, AppLocalizations.of(context).pleaseCompleteInSystemSettings, duration: const Duration(seconds: 2));
                    }

                    // 打开设置页面
                    await platform.invokeMethod('openBatteryOptimizationSettings');

                    // 启动定时检查，每0.5秒检查一次权限状态，直到成功
                    _startBatteryPermissionCheck();
                  },
                ),

                const SizedBox(height: AppTheme.spacing5),

                _buildPermissionCard(
                  icon: Icons.power_settings_new,
                  title: AppLocalizations.of(context).autostartPermissionTitle,
                  description: AppLocalizations.of(context).autostartPermissionDesc,
                  isGranted: _keepAlivePermissions['autostart'] ?? false,
                  onRequest: () async {
                    // 打开设置页面
                    await platform.invokeMethod('openAutoStartSettings');

                    // 延迟后显示确认对话框
                    await Future.delayed(const Duration(seconds: 1));
                    if (mounted) {
                      final confirmed = await _showAutoStartConfirmDialog();
                      if (confirmed) {
                        // 用户确认已完成设置，标记权限为已授权
                        await platform.invokeMethod('markPermissionConfigured', {'type': 'autostart'});
                        await _loadKeepAlivePermissions();

                        if (mounted) {
                          // 授权完成后不再显示底部通知
                        }
                      }
                    }
                  },
                ),

                const SizedBox(height: AppTheme.spacing3),
              ],
            ),
          ),
          
          // 权限说明（使用主题色，避免硬编码浅色）
          Container(
            margin: const EdgeInsets.only(top: AppTheme.spacing2),
            padding: const EdgeInsets.all(AppTheme.spacing2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppTheme.info,
                ),
                const SizedBox(width: AppTheme.spacing1),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).permissionsFooterNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return UICard(
      showBorder: false,
      padding: const EdgeInsets.all(AppTheme.spacing2), // 大幅缩小内边距
      child: Row(
        children: [
          Container(
            width: 36, // 缩小图标容器
            height: 36,
            decoration: BoxDecoration(
              color: isGranted
                  ? AppTheme.success.withValues(alpha: 0.25)
                  : Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              isGranted ? Icons.check : icon,
              color: isGranted
                  ? AppTheme.successForeground
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18, // 缩小图标大小
            ),
          ),

          const SizedBox(width: AppTheme.spacing2), // 缩小间距

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith( // 缩小标题字体
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppTheme.spacing2), // 缩小间距

          if (isGranted)
            Text(
              AppLocalizations.of(context).grantedLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            UIButton(
              text: AppLocalizations.of(context).authorizeAction,
              onPressed: onRequest,
              size: UIButtonSize.small,
            ),
        ],
      ),
    );
  }

  Widget _buildAppSelectionPage() {
    return Column(
      children: [
        // 标题区域
        Container(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            children: [
              Text(
                AppLocalizations.of(context).onboardingSelectAppsTitle,
                style: Theme.of(context).textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                AppLocalizations.of(context).onboardingSelectAppsDesc,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        // 应用选择组件 - 列表显示（与首页风格一致）
        Expanded(
          child: AppSelectionWidget(
            displayAsList: true,
            onSelectionChanged: _onAppSelectionChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletePage() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 成功图标（白天模式与第一页一致：primary 背景；夜间保持柔和容器色）
          Builder(builder: (context) {
            final isLight = Theme.of(context).brightness == Brightness.light;
            return Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: isLight
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              ),
              child: Icon(
                Icons.check,
                size: 60,
                color: isLight
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            );
          }),
          
          const SizedBox(height: AppTheme.spacing8),
          
          Text(
            AppLocalizations.of(context).onboardingDoneTitle,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: AppTheme.spacing4),
          
          Text(
            AppLocalizations.of(context).onboardingDoneDesc,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppTheme.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: AppTheme.spacing8),
          
          UICard(
            child: Column(
              children: [
                Text(
                  AppLocalizations.of(context).nextStepTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  AppLocalizations.of(context).onboardingNextStepDesc,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      child: Row(
        children: [
          if (_currentPage > 0)
            Expanded(
              child: UIButton(
                text: AppLocalizations.of(context).prevStep,
                onPressed: _previousPage,
                variant: UIButtonVariant.outline,
                fullWidth: true,
              ),
            ),
          
          if (_currentPage > 0) const SizedBox(width: AppTheme.spacing4),
          
          Expanded(
            child: UIButton(
              text: _currentPage == 3 ? AppLocalizations.of(context).startUsing : (_currentPage == 2 ? AppLocalizations.of(context).finishSelection : AppLocalizations.of(context).nextStep),
              onPressed: _currentPage == 3
                  ? () {
                      // 立即触发跳转，不等待任何操作
                      _navigateToHome();
                    }
                  : _currentPage == 2
                      ? (_selectedApps.isNotEmpty ? () {
                          // 立即跳转到下一页，不等待保存完成
                          _nextPage();
                          // 在后台异步保存选中的应用
                          _saveSelectedAppsAsync();
                        } : null)
                      : _nextPage,
              fullWidth: true,
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _stopBatteryPermissionCheck();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


}

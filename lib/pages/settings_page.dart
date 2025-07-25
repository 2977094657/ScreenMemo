import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/permission_service.dart';
import '../services/theme_service.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  final ThemeService themeService;
  
  const SettingsPage({super.key, required this.themeService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  final PermissionService _permissionService = PermissionService.instance;

  Map<String, bool> _permissions = {};
  Map<String, bool> _keepAlivePermissions = {};
  bool _isLoading = true;
  bool _isLoadingKeepAlive = true;

  // 电池权限检查定时器
  Timer? _batteryPermissionTimer;
  int _batteryCheckCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllPermissions();
  }

  @override
  void dispose() {
    _stopBatteryPermissionCheck();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台时，刷新权限状态
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _loadAllPermissions();
        }
      });
    }
  }

  Future<void> _loadAllPermissions() async {
    await Future.wait([
      _loadPermissions(),
      _loadKeepAlivePermissions(),
    ]);
  }

  Future<void> _loadPermissions() async {
    try {
      final permissions = await _permissionService.checkAllPermissions();
      if (mounted) {
        setState(() {
          _permissions = permissions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadKeepAlivePermissions() async {
    try {
      if (mounted) {
        setState(() {
          _isLoadingKeepAlive = true;
        });
      }

      // 使用与引导页面相同的权限检测方法和通道
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final result = await platform.invokeMethod('getPermissionStatus');

      if (mounted) {
        setState(() {
          _keepAlivePermissions = Map<String, bool>.from(result ?? {});
          _isLoadingKeepAlive = false;
        });
      }
      print('保活权限状态更新完成: $_keepAlivePermissions');
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
      }
    }
  }

  /// 启动电池权限检查定时器
  void _startBatteryPermissionCheck() {
    print('启动电池权限定时检查...');
    _batteryCheckCount = 0;
    _batteryPermissionTimer?.cancel();

    _batteryPermissionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      _batteryCheckCount++;
      print('电池权限检查第 $_batteryCheckCount 次');

      try {
        const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
        final permissionStatus = await platform.invokeMethod('getPermissionStatus');
        final newBatteryStatus = permissionStatus?['battery_optimization'] ?? false;
        final oldBatteryStatus = _keepAlivePermissions['battery_optimization'] ?? false;

        print('定时检查 - 旧状态: $oldBatteryStatus, 新状态: $newBatteryStatus');

        if (newBatteryStatus != oldBatteryStatus) {
          print('检测到电池权限状态变化，更新UI');
          await _loadKeepAlivePermissions();
          if (newBatteryStatus) {
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
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            side: const BorderSide(color: AppTheme.border, width: 1),
          ),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacing6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        Icons.help_outline,
                        color: AppTheme.info,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Text(
                      '确认权限设置',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  '请确认您已在系统设置中完成自启动权限的配置。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppTheme.spacing4),
                Row(
                  children: [
                    Expanded(
                      child: UIButton(
                        text: '未完成',
                        onPressed: () => Navigator.of(context).pop(false),
                        variant: UIButtonVariant.outline,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Expanded(
                      child: UIButton(
                        text: '已完成',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ) ?? false;
  }

  Future<void> _requestPermission(String permissionType) async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');

      switch (permissionType) {
        case 'storage':
          await _permissionService.requestStoragePermission();
          break;
        case 'notification':
          await _permissionService.requestNotificationPermission();
          break;
        case 'accessibility':
          await _permissionService.requestAccessibilityPermission();
          break;
        case 'usage_stats':
          await _permissionService.requestUsageStatsPermission();
          break;
        case 'mediaProjection':
          // 不再需要MediaProjection权限
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已使用无障碍服务截屏，无需屏幕录制权限'),
              backgroundColor: AppTheme.success,
            ),
          );
          break;
        case 'battery_optimization':
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请在系统设置中完成授权，然后返回应用'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          await platform.invokeMethod('openBatteryOptimizationSettings');
          _startBatteryPermissionCheck();
          break;
        case 'autostart':
          await platform.invokeMethod('openAutoStartSettings');
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            final confirmed = await _showAutoStartConfirmDialog();
            if (confirmed) {
              await platform.invokeMethod('markPermissionConfigured', {'type': 'autostart'});
              await _loadKeepAlivePermissions();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('自启动权限已标记为已授权'),
                    backgroundColor: AppTheme.success,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          }
          break;
      }

      // 延迟刷新权限状态
      await Future.delayed(const Duration(seconds: 1));
      if (permissionType == 'storage' || permissionType == 'notification' || permissionType == 'accessibility' || permissionType == 'mediaProjection') {
        _loadPermissions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请求权限失败: $e'),
            backgroundColor: AppTheme.destructive,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPermissions,
            tooltip: '刷新权限状态',
          ),
          
          // 主题切换按钮
          IconButton(
            icon: Icon(widget.themeService.themeModeIcon),
            onPressed: () async {
              await widget.themeService.toggleTheme();
            },
            tooltip: widget.themeService.themeModeDescription,
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: (_isLoading || _isLoadingKeepAlive)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              children: [
                // 基础权限
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.security, color: AppTheme.primary),
                        const SizedBox(width: AppTheme.spacing2),
                        Text(
                          '基础权限',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    _buildPermissionCard(
                      icon: Icons.folder,
                      title: '存储权限',
                      description: '保存截图文件到设备存储',
                      isGranted: _permissions['storage'] ?? false,
                      onRequest: () => _requestPermission('storage'),
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    _buildPermissionCard(
                      icon: Icons.notifications,
                      title: '通知权限',
                      description: '显示服务状态通知',
                      isGranted: _permissions['notification'] ?? false,
                      onRequest: () => _requestPermission('notification'),
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    _buildPermissionCard(
                      icon: Icons.accessibility,
                      title: '无障碍服务',
                      description: '检测应用切换和执行截屏',
                      isGranted: _permissions['accessibility'] ?? false,
                      onRequest: () => _requestPermission('accessibility'),
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    _buildPermissionCard(
                      icon: Icons.analytics,
                      title: '使用统计权限',
                      description: '准确检测前台应用',
                      isGranted: _permissions['usage_stats'] ?? false,
                      onRequest: () => _requestPermission('usage_stats'),
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    // 屏幕录制权限已移除 - 使用无障碍服务截屏
                  ],
                ),

                const SizedBox(height: AppTheme.spacing4),

                // 保活权限
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.battery_saver, color: AppTheme.primary),
                        const SizedBox(width: AppTheme.spacing2),
                        Text(
                          '保活权限',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    _buildPermissionCard(
                      icon: Icons.battery_saver,
                      title: '电池优化白名单',
                      description: '确保截屏服务稳定运行',
                      isGranted: _keepAlivePermissions['battery_optimization'] ?? false,
                      onRequest: () => _requestPermission('battery_optimization'),
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    _buildPermissionCard(
                      icon: Icons.power_settings_new,
                      title: '自启动权限',
                      description: '允许应用在后台自动重启',
                      isGranted: _keepAlivePermissions['autostart'] ?? false,
                      onRequest: () => _requestPermission('autostart'),
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.spacing4),

                // 权限说明
                UICard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppTheme.info),
                          const SizedBox(width: AppTheme.spacing2),
                          Text(
                            '权限说明',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Text(
                        '基础权限：\n'
                        '• 存储权限：用于保存截图文件到设备存储空间\n'
                        '• 通知权限：用于显示截屏服务运行状态\n'
                        '• 无障碍服务：用于检测应用切换和执行自动截屏\n'
                        '• 屏幕录制权限：用于截取屏幕画面\n\n'
                        '保活权限：\n'
                        '• 电池优化白名单：防止系统杀死截屏服务\n'
                        '• 自启动权限：允许应用在后台自动重启',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedForeground,
                          height: 1.5,
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
      padding: const EdgeInsets.all(AppTheme.spacing2), // 大幅缩小内边距
      child: Row(
        children: [
          Container(
            width: 36, // 缩小图标容器
            height: 36,
            decoration: BoxDecoration(
              color: isGranted ? AppTheme.success : AppTheme.secondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              isGranted ? Icons.check : icon,
              color: isGranted ? AppTheme.successForeground : AppTheme.foreground,
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
            const UIBadge(
              text: '已授权',
              variant: UIBadgeVariant.success,
            )
          else
            UIButton(
              text: '授权',
              onPressed: onRequest,
              size: UIButtonSize.small,
            ),
        ],
      ),
    );
  }
}

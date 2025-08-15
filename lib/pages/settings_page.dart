import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/permission_service.dart';
import '../services/theme_service.dart';
import '../services/screenshot_database.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  final ThemeService themeService;
  
  const SettingsPage({super.key, required this.themeService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  final PermissionService _permissionService = PermissionService.instance;
  final ScreenshotDatabase _screenshotDatabase = ScreenshotDatabase.instance;

  Map<String, bool> _permissions = {};
  Map<String, bool> _keepAlivePermissions = {};
  bool _isLoading = true;
  bool _isLoadingKeepAlive = true;

  // 电池权限检查定时器
  Timer? _batteryPermissionTimer;
  int _batteryCheckCount = 0;
  bool _exportingDb = false;

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

  /// 导出数据库到下载目录
  Future<void> _exportDatabase() async {
    if (_exportingDb) return;
    setState(() { _exportingDb = true; });

    try {
      final result = await _screenshotDatabase.exportDatabaseToDownloads();
      if (!mounted) return;
      if (result != null) {
        final displayPath = (result['humanPath'] as String?) ?? (result['absolutePath'] as String?) ?? (result['displayPath'] as String?) ?? 'Download/ScreenMemo/screenshot_memo.db';

        // 成功对话框：中文提示 + 可复制路径
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return Dialog(
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
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          child: const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
                        ),
                        const SizedBox(width: AppTheme.spacing3),
                        Text(
                          '导出完成',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Text('文件已导出至：'),
                    const SizedBox(height: AppTheme.spacing2),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppTheme.spacing3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Text(
                        displayPath,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Row(
                      children: [
                        UIButton(
                          text: '复制路径',
                          variant: UIButtonVariant.outline,
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: displayPath));
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制路径')),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: AppTheme.spacing3),
                        UIButton(
                          text: '确定',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      } else {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
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
                          color: AppTheme.destructive.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                        child: const Icon(Icons.error_outline, color: AppTheme.destructive, size: 18),
                      ),
                      const SizedBox(width: AppTheme.spacing3),
                      Text('导出失败', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  const Text('请稍后重试'),
                  const SizedBox(height: AppTheme.spacing4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: UIButton(text: '确定', onPressed: () => Navigator.of(context).pop()),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
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
                        color: AppTheme.destructive.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: const Icon(Icons.error_outline, color: AppTheme.destructive, size: 18),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Text('导出失败', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text('$e'),
                const SizedBox(height: AppTheme.spacing4),
                Align(
                  alignment: Alignment.centerRight,
                  child: UIButton(text: '确定', onPressed: () => Navigator.of(context).pop()),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() { _exportingDb = false; });
      }
    }
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
                _buildSection(
                  context: context,
                  title: '基础权限',
                  children: [
                    _buildPermissionItem(
                      context: context,
                      icon: Icons.folder_outlined,
                      title: '存储权限',
                      description: '保存截图文件到设备存储',
                      isGranted: _permissions['storage'] ?? false,
                      onRequest: () => _requestPermission('storage'),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    _buildPermissionItem(
                      context: context,
                      icon: Icons.notifications_outlined,
                      title: '通知权限',
                      description: '显示服务状态通知',
                      isGranted: _permissions['notification'] ?? false,
                      onRequest: () => _requestPermission('notification'),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    _buildPermissionItem(
                      context: context,
                      icon: Icons.accessibility_new_outlined,
                      title: '无障碍服务',
                      description: '检测应用切换和执行截屏',
                      isGranted: _permissions['accessibility'] ?? false,
                      onRequest: () => _requestPermission('accessibility'),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    _buildPermissionItem(
                      context: context,
                      icon: Icons.analytics_outlined,
                      title: '使用统计权限',
                      description: '准确检测前台应用',
                      isGranted: _permissions['usage_stats'] ?? false,
                      onRequest: () => _requestPermission('usage_stats'),
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.spacing6),

                // 保活权限
                _buildSection(
                  context: context,
                  title: '保活权限',
                  children: [
                    _buildPermissionItem(
                      context: context,
                      icon: Icons.battery_saver_outlined,
                      title: '电池优化白名单',
                      description: '确保截屏服务稳定运行',
                      isGranted: _keepAlivePermissions['battery_optimization'] ?? false,
                      onRequest: () => _requestPermission('battery_optimization'),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    _buildPermissionItem(
                      context: context,
                      icon: Icons.power_settings_new_outlined,
                      title: '自启动权限',
                      description: '允许应用在后台自动重启',
                      isGranted: _keepAlivePermissions['autostart'] ?? false,
                      onRequest: () => _requestPermission('autostart'),
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.spacing6),

                // 数据与备份
                _buildSection(
                  context: context,
                  title: '数据与备份',
                  children: [
                    _buildExportItem(context),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppTheme.spacing1, bottom: AppTheme.spacing3),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.8),
              width: 1,
            ),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.6),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isGranted
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              isGranted ? Icons.check : icon,
              color: isGranted
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          if (isGranted)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing1,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Text(
                '已授权',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeXs,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            )
          else
            TextButton(
              onPressed: onRequest,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing3,
                  vertical: AppTheme.spacing1,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero,
              ),
              child: const Text('授权'),
            ),
        ],
      ),
    );
  }

  Widget _buildExportItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.file_download_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导出数据库',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '导出到 Download/ScreenMemory',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _exportingDb ? null : _exportDatabase,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: _exportingDb
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Text('导出'),
          ),
        ],
      ),
    );
  }



}

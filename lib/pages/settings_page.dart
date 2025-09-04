import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../services/permission_service.dart';
import '../services/theme_service.dart';
import '../services/screenshot_database.dart';
import '../services/app_selection_service.dart';

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
  final AppSelectionService _appService = AppSelectionService.instance;

  Map<String, bool> _permissions = {};
  Map<String, bool> _keepAlivePermissions = {};
  bool _isLoading = true;
  bool _isLoadingKeepAlive = true;
  bool _permissionsExpanded = true; // 权限下拉菜单展开状态：默认展开，全部授权后自动收起
  int _screenshotInterval = 5;
  String _sortMode = 'timeDesc';

  // 截图质量设置（仅通过编码压缩，不修改分辨率）
  String _imageFormat = 'webp_lossy'; // jpeg | png | webp_lossy | webp_lossless
  int _imageQuality = 90; // 预留（隐藏），由目标大小策略接管
  bool _useTargetSize = false; // 默认不开启
  int _targetSizeKb = 50; // 默认50KB（最低50KB，上不封顶）
  bool _grayscale = false; // 已移除，保持固定为 false

  // 电池权限检查定时器
  Timer? _batteryPermissionTimer;
  int _batteryCheckCount = 0;
  bool _exportingDb = false;

  bool _allPermissionsGranted() {
    try {
      final basicKeys = ['storage', 'notification', 'accessibility', 'usage_stats'];
      final keepKeys = ['battery_optimization', 'autostart'];
      for (final k in basicKeys) {
        if (!(_permissions[k] ?? false)) return false;
      }
      for (final k in keepKeys) {
        if (!(_keepAlivePermissions[k] ?? false)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _buildPermissionsDropdown(BuildContext context) {
    final basicItems = [
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
    ];

    final keepAliveItems = [
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
    ];

    int missingCount = 0;
    final allPairs = <bool>[];
    allPairs.add(_permissions['storage'] ?? false);
    allPairs.add(_permissions['notification'] ?? false);
    allPairs.add(_permissions['accessibility'] ?? false);
    allPairs.add(_permissions['usage_stats'] ?? false);
    allPairs.add(_keepAlivePermissions['battery_optimization'] ?? false);
    allPairs.add(_keepAlivePermissions['autostart'] ?? false);
    for (final g in allPairs) {
      if (!g) missingCount++;
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() { _permissionsExpanded = !_permissionsExpanded; });
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Icon(
                    _allPermissionsGranted() ? Icons.verified_user : Icons.lock_open,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '权限设置',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _allPermissionsGranted() ? '已全部授权' : '尚缺少 $missingCount 项权限',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.spacing2),
                Icon(_permissionsExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (_permissionsExpanded) ...[
            const SizedBox(height: AppTheme.spacing3),
            // 基础权限
            ...basicItems,
            const SizedBox(height: AppTheme.spacing3),
            // 保活权限
            ...keepAliveItems,
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllPermissions();
    _loadScreenshotInterval();
    _loadSortMode();
    _loadScreenshotQualitySettings();
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
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: '导出完成',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('文件已导出至：'),
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
            ],
          ),
          actions: [
            UIDialogAction(
              text: '复制路径',
              style: UIDialogActionStyle.normal,
              closeOnPress: false,
              onPressed: (ctx) async {
                await Clipboard.setData(ClipboardData(text: displayPath));
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                  UINotifier.success(ctx, '已复制路径');
                }
              },
            ),
            const UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
          ],
        );
      } else {
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: '导出失败',
          message: '请稍后重试',
          actions: const [UIDialogAction(text: '确定', style: UIDialogActionStyle.primary)],
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: '导出失败',
        content: Text('$e'),
        actions: const [UIDialogAction(text: '确定', style: UIDialogActionStyle.primary)],
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
    if (mounted) {
      setState(() {
        _permissionsExpanded = !_allPermissionsGranted();
      });
    }
  }

  Future<void> _loadPermissions() async {
    try {
      final permissions = await _permissionService.checkAllPermissions();
      if (mounted) {
        setState(() {
          _permissions = permissions;
          _isLoading = false;
        });
        // 全部授权后自动收起
        setState(() {
          _permissionsExpanded = !_allPermissionsGranted();
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
        // 全部授权后自动收起
        setState(() {
          _permissionsExpanded = !_allPermissionsGranted();
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
        setState(() {
          _permissionsExpanded = !_allPermissionsGranted();
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
    return await showUIDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: '确认权限设置',
      message: '请确认您已在系统设置中完成自启动权限的配置。',
      actions: const [
        UIDialogAction<bool>(text: '未完成', result: false),
        UIDialogAction<bool>(text: '已完成', style: UIDialogActionStyle.primary, result: true),
      ],
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
          UINotifier.info(context, '已使用无障碍服务截屏，无需屏幕录制权限');
          break;
        case 'battery_optimization':
          if (mounted) {
            UINotifier.info(context, '请在系统设置中完成授权，然后返回应用', duration: const Duration(seconds: 2));
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
                UINotifier.success(context, '自启动权限已标记为已授权', duration: const Duration(seconds: 2));
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
        UINotifier.error(context, '请求权限失败: $e');
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
                // 统一权限下拉菜单
                _buildSection(
                  context: context,
                  title: '权限设置',
                  children: [
                    _buildPermissionsDropdown(context),
                  ],
                ),

                const SizedBox(height: AppTheme.spacing4),

                // 显示与排序
                _buildSection(
                  context: context,
                  title: '显示与排序',
                  children: [
                    _buildSortModeItem(context),
                  ],
                ),

                const SizedBox(height: AppTheme.spacing4),

                // 截屏设置
                _buildSection(
                  context: context,
                  title: '截屏设置',
                  children: [
                    _buildScreenshotIntervalItem(context),
                    _buildScreenshotQualityItem(context),
                  ],
                ),

                const SizedBox(height: AppTheme.spacing4),

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
            Text(
              '已授权',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _buildSortModeItem(BuildContext context) {
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
              Icons.sort,
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
                  '首页排序',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _sortModeLabel(_sortMode),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSortModeDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotIntervalItem(BuildContext context) {
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
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.timer,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '截屏间隔',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '当前间隔：$_screenshotInterval秒',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showIntervalDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotQualityItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.image_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Stack(
                  children: [
                    // 文本区域右侧预留空间，避免与右上角开关重叠
                    Padding(
                      padding: const EdgeInsets.only(right: 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '截图质量',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // 说明行（根据开关禁用/启用与灰化）
                          IgnorePointer(
                            ignoring: !_useTargetSize,
                            child: Opacity(
                              opacity: _useTargetSize ? 1.0 : 0.5,
                              child: Row(
                                children: [
                                  Text(
                                    '当前大小：',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  GestureDetector(
                                    onTap: _useTargetSize ? _showTargetSizeDialog : null,
                                    child: Text(
                                      '${_targetSizeKb}KB',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: _useTargetSize
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                        decoration: _useTargetSize ? TextDecoration.underline : TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  Flexible(
                                    child: Text(
                                      '（点击数字可修改）',
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 右上角悬浮圆形开关（不占据垂直排布空间）
                    Positioned(
                      top: -1,
                      right: 0,
                      child: Transform.scale(
                        scale: 0.9,
                        child: Switch(
                          value: _useTargetSize,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) async {
                            setState(() { _useTargetSize = v; });
                            await _saveScreenshotQualitySettings();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 与“截屏间隔”项保持一致的内边距与间距（去除多余的底部空隙）
        ],
      ),
    );
  }

  Future<void> _loadScreenshotInterval() async {
    final interval = await _appService.getScreenshotInterval();
    if (mounted) {
      setState(() {
        _screenshotInterval = interval;
      });
    }
  }

  Future<void> _updateScreenshotInterval(int interval) async {
    await _appService.saveScreenshotInterval(interval);
    setState(() {
      _screenshotInterval = interval;
    });
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

  void _showTargetSizeDialog() {
    final TextEditingController controller = TextEditingController(
      text: _targetSizeKb.toString(),
    );

    showUIDialog<void>(
      context: context,
      title: '设置目标大小(单位KB)',
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '目标大小（KB）',
                hintText: '请输入 >= 50 的整数',
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
              '为保证 OCR 质量，最低仅支持 50KB；系统会在不改变分辨率的情况下尽量逼近该大小。',
              style: TextStyle(fontSize: 12, color: AppTheme.info),
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
            final kb = int.tryParse(input);
            if (kb == null || kb < 50) {
              UINotifier.error(ctx, '请输入 >= 50 的有效整数');
              return;
            }
            setState(() {
              _useTargetSize = true;
              _targetSizeKb = kb;
            });
            await _saveScreenshotQualitySettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, '目标大小已设置为 $kb KB');
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadSortMode() async {
    final mode = await _appService.getSortMode();
    if (mounted) {
      setState(() {
        _sortMode = mode;
      });
    }
  }

  Future<void> _loadScreenshotQualitySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _imageFormat = prefs.getString('image_format') ?? 'webp_lossless';
        _imageQuality = (prefs.getInt('image_quality') ?? 90).clamp(1, 100);
        _useTargetSize = prefs.getBool('use_target_size') ?? false;
        final tkb = prefs.getInt('target_size_kb') ?? 50;
        _targetSizeKb = tkb < 50 ? 50 : tkb;
        _grayscale = false; // 灰度已移除
      });
    } catch (_) {}
  }

  Future<void> _saveScreenshotQualitySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 根据是否启用目标大小自动设置格式：启用->webp_lossy；关闭->webp_lossless（原画质）
      await prefs.setString('image_format', _useTargetSize ? 'webp_lossy' : 'webp_lossless');
      await prefs.setInt('image_quality', _imageQuality);
      await prefs.setBool('use_target_size', _useTargetSize);
      await prefs.setInt('target_size_kb', _targetSizeKb < 50 ? 50 : _targetSizeKb);
      // 不再保存灰度
      if (mounted) {
        UINotifier.success(context, '截图质量设置已保存');
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, '保存失败: $e');
      }
    }
  }

  String _sortModeLabel(String mode) {
    switch (mode) {
      case 'timeAsc':
        return '时间(旧→新)';
      case 'timeDesc':
        return '时间(新→旧)';
      case 'sizeAsc':
        return '大小(小→大)';
      case 'sizeDesc':
        return '大小(大→小)';
      case 'countAsc':
        return '数量(少→多)';
      case 'countDesc':
        return '数量(多→少)';
      case 'lastScreenshot':
        return '时间(新→旧)';
      case 'screenshotCount':
        return '数量(多→少)';
      default:
        return '时间(新→旧)';
    }
  }

  Future<void> _updateSortMode(String mode) async {
    await _appService.saveSortMode(mode);
    if (mounted) {
      setState(() {
        _sortMode = mode;
      });
      UINotifier.success(context, '首页排序已设置为 ${_sortModeLabel(mode)}');
    }
  }

  void _showSortModeDialog() async {
    final selected = await showUIDialog<String>(
      context: context,
      barrierDismissible: true,
      title: '选择首页排序',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前：${_sortModeLabel(_sortMode)}'),
        ],
      ),
      actions: const [
        UIDialogAction<String>(text: '时间(新→旧)', result: 'timeDesc', style: UIDialogActionStyle.primary),
        UIDialogAction<String>(text: '时间(旧→新)', result: 'timeAsc'),
        UIDialogAction<String>(text: '大小(大→小)', result: 'sizeDesc'),
        UIDialogAction<String>(text: '大小(小→大)', result: 'sizeAsc'),
        UIDialogAction<String>(text: '数量(多→少)', result: 'countDesc'),
        UIDialogAction<String>(text: '数量(少→多)', result: 'countAsc'),
        UIDialogAction<String>(text: '取消', result: 'cancel'),
      ],
    );

    if (!mounted) return;
    if (selected != null && selected != 'cancel') {
      await _updateSortMode(selected);
    }
  }
}

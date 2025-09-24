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
import '../services/screenshot_service.dart';
import '../services/app_selection_service.dart';
import '../services/flutter_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'ai_settings_page.dart';
import '../services/daily_summary_service.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  final ThemeService themeService;

  const SettingsPage({super.key, required this.themeService});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
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
  bool _privacyMode = true; // 隐私模式，默认开启
  // 段落采样设置
  int _segmentSampleIntervalSec = 20; // 最小5秒
  int _segmentDurationMin = 5; // 以分钟显示，最小1分钟
  // AI 请求最小间隔（秒）
  int _aiRequestIntervalSec = 3; // 默认3秒，最低1秒
  // 截图质量设置（仅通过编码压缩，不修改分辨率）
  String _imageFormat = 'webp_lossy'; // jpeg | png | webp_lossy | webp_lossless
  int _imageQuality = 90; // 备用项，已被“目标大小”策略覆盖
  bool _useTargetSize = false; // 默认关闭
  int _targetSizeKb = 50; // 默认 50KB（最低仅支持 50KB）
  bool _grayscale = false; // 已移除，保持为 false
  // 电池权限检查定时器
  Timer? _batteryPermissionTimer;
  int _batteryCheckCount = 0;
  bool _exportingDb = false;
  bool _importingData = false;
  // 截图过期清理设置
  bool _expireEnabled = false; // 是否启用过期自动删除
  int _expireDays = 30; // 过期天数，下限 1
  // 每日总结提醒设置
  bool _dailyNotifyEnabled = true;
  int _dailyNotifyHour = 22;
  int _dailyNotifyMinute = 0;
  bool _allPermissionsGranted() {
    try {
      final basicKeys = [
        'storage',
        'notification',
        'accessibility',
        'usage_stats',
      ];
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
        description: '监听应用切换并执行截图',
        isGranted: _permissions['accessibility'] ?? false,
        onRequest: () => _requestPermission('accessibility'),
      ),
      const SizedBox(height: AppTheme.spacing2),
      _buildPermissionItem(
        context: context,
        icon: Icons.analytics_outlined,
        title: '使用统计权限',
        description: '确保检测前台应用',
        isGranted: _permissions['usage_stats'] ?? false,
        onRequest: () => _requestPermission('usage_stats'),
      ),
    ];
    final keepAliveItems = [
      _buildPermissionItem(
        context: context,
        icon: Icons.battery_saver_outlined,
        title: '电池优化白名单',
        description: '确保截图服务常驻运行',
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
              setState(() {
                _permissionsExpanded = !_permissionsExpanded;
              });
            },
            behavior: HitTestBehavior.opaque,
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
                    _allPermissionsGranted()
                        ? Icons.verified_user_outlined
                        : Icons.lock_open_outlined,
                    color:
                        Theme.of(context).colorScheme.onSecondaryContainer,
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
                        _allPermissionsGranted()
                            ? '已全部授权'
                            : '尚有 $missingCount 项权限未授权',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.spacing2),
                Icon(
                  _permissionsExpanded ? Icons.expand_less : Icons.expand_more,
                ),
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
    _loadPrivacyMode();
    _loadScreenshotQualitySettings();
    _loadScreenshotExpireSettings();
    _loadSegmentSettings();
    _loadAiRequestInterval();
    _loadDailyNotifySettings();
   }

  @override
  void dispose() {
    _stopBatteryPermissionCheck();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 导出数据到下载目录
  Future<void> _exportDatabase() async {
    if (_exportingDb) return;
    setState(() {
      _exportingDb = true;
    });
    try {
      await FlutterLogger.nativeInfo('UI_EXPORT', 'begin export');
      final result = await _screenshotDatabase.exportDatabaseToDownloads();
      if (!mounted) return;
      if (result != null) {
        await FlutterLogger.nativeInfo('UI_EXPORT', 'success -> ' + ((result['humanPath'] as String?) ?? ''));
        final displayPath =
            (result['humanPath'] as String?) ??
            (result['absolutePath'] as String?) ??
            (result['displayPath'] as String?) ??
            'Download/ScreenMemory/output_export.zip';
        // 成功弹窗：中文提示 + 可复制路径
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
            const UIDialogAction(
              text: '确定',
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      } else {
        await FlutterLogger.nativeWarn('UI_EXPORT', 'export returned null');
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: '导出失败',
          message: '请稍后重试',
          actions: const [
            UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
          ],
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: '导出失败',
        content: Text('$e'),
        actions: const [
          UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
        ],
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingDb = false;
        });
      }
    }

  }

  // 从用户选择的ZIP文件导入数据并解压到应用存储
  Future<void> _importData() async {
    if (_importingData) return;
    setState(() {
      _importingData = true;
    });
    try {
      await FlutterLogger.nativeInfo('UI_IMPORT', 'open file picker');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: false,
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        await FlutterLogger.nativeWarn('UI_IMPORT', 'user cancelled');
        setState(() { _importingData = false; });
        return; // 用户取消
      }

      final file = result.files.first; 
      final bytes = file.bytes; 
      final path = file.path; 
      Map<String, dynamic>? importRes;  
      await FlutterLogger.nativeInfo('UI_IMPORT', 'selected name=' + file.name + ' size=' + ((bytes?.length ?? 0).toString()) + ' path=' + (path ?? '')); 
      // 停止截图服务以避免导入过程中的DB/FS冲突
      final bool wasRunning = ScreenshotService.instance.isRunning;
      if (wasRunning) {
        await FlutterLogger.nativeInfo('UI_IMPORT', 'stopping service before import');
        try { await ScreenshotService.instance.stopScreenshotService(); } catch (_) {}
      }
      if (bytes != null && bytes.isNotEmpty && (path == null || path.isEmpty)) {  
        // 仅作为备选方案；优先使用文件路径流式传输
        importRes = await _screenshotDatabase.importDataFromZipStreaming(zipBytes: bytes); 
      } else if (path != null && path.isNotEmpty) { 
        importRes = await _screenshotDatabase.importDataFromZipStreaming(zipPath: path); 
      }  

      if (!mounted) return;
      if (importRes != null) { 
        await FlutterLogger.nativeInfo('UI_IMPORT', 'success extracted=' + (importRes['extracted']?.toString() ?? 'null') + ' target=' + (importRes['targetDir']?.toString() ?? ''));
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: '导入完成',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('数据已解压到:'),
              const SizedBox(height: AppTheme.spacing2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Text(
                  (importRes['targetDir'] as String?) ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          actions: const [
            UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
          ],
        );
        // 使统计缓存失效，以便下次刷新UI
        // ignore: unawaited_futures
        ScreenshotService.instance.invalidateStatsCache();
      } else { 
        await FlutterLogger.nativeWarn('UI_IMPORT', 'import returned null');
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: '导入失败',
          message: '请检查ZIP文件并重试。',
          actions: const [
            UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
          ],
        );
      }
    } catch (e) { 
      if (!mounted) return; 
      await FlutterLogger.nativeError('UI_IMPORT', 'exception: ' + e.toString());
      await showUIDialog<void>( 
        context: context,
        barrierDismissible: false,
        title: '导入失败',
        content: Text('$e'),
        actions: const [
          UIDialogAction(text: 'OK', style: UIDialogActionStyle.primary),
        ],
      );
    } finally { 
      try {
        // 尽力而为：不自动重启服务以避免意外。
        await FlutterLogger.nativeInfo('UI_IMPORT', 'import flow finished');
      } catch (_) {}
      if (mounted) { 
        setState(() { _importingData = false; }); 
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
    await Future.wait([_loadPermissions(), _loadKeepAlivePermissions()]);
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
      print('保活权限状态更新完成: ' + _keepAlivePermissions.toString());
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

  /// 启动电池权限定时检查
  void _startBatteryPermissionCheck() {
    print('启动电池权限定时检查...');
    _batteryCheckCount = 0;
    _batteryPermissionTimer?.cancel();
    _batteryPermissionTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) async {
        _batteryCheckCount++;
        print('电池权限检查第 ' + _batteryCheckCount.toString() + ' 次');
        try {
          const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
          final permissionStatus = await platform.invokeMethod(
            'getPermissionStatus',
          );
          final newBatteryStatus =
              permissionStatus?['battery_optimization'] ?? false;
          final oldBatteryStatus =
              _keepAlivePermissions['battery_optimization'] ?? false;
          print(
            '定时检查 - 旧状态: ' +
                oldBatteryStatus.toString() +
                ', 新状态: ' +
                newBatteryStatus.toString(),
          );
          if (newBatteryStatus != oldBatteryStatus) {
            print('检测到电池权限状态变化，更新UI');
            await _loadKeepAlivePermissions();
            if (newBatteryStatus) {
              print('电池权限已授权，停止定时检查');
              timer.cancel();
            }
          }
        } catch (e) {
          print('定时检查权限失败: ' + e.toString());
        }
      },
    );
  }

  /// 停止电池权限定时检查
  void _stopBatteryPermissionCheck() {
    _batteryPermissionTimer?.cancel();
    _batteryPermissionTimer = null;
    _batteryCheckCount = 0;
  }

  /// 显示自启动权限确认弹窗
  Future<bool> _showAutoStartConfirmDialog() async {
    return await showUIDialog<bool>(
          context: context,
          barrierDismissible: false,
          title: '确认权限设置',
          message: '请确认您已在系统设置中完成自启动权限的配置。',
          actions: const [
            UIDialogAction<bool>(text: '尚未完成', result: false),
            UIDialogAction<bool>(
              text: '已完成',
              style: UIDialogActionStyle.primary,
              result: true,
            ),
          ],
        ) ??
        false;
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
          // 不再需要 MediaProjection 权限
          UINotifier.info(context, '已使用无障碍服务截图，无需屏幕录制权限');
          break;
        case 'battery_optimization':
          if (mounted) {
            UINotifier.info(
              context,
              '请在系统设置中完成授权，然后返回应用',
              duration: const Duration(seconds: 2),
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
              await platform.invokeMethod('markPermissionConfigured', {
                'type': 'autostart',
              });
              await _loadKeepAlivePermissions();
              if (mounted) {
                UINotifier.success(
                  context,
                  '自启动权限已标记为已授权',
                  duration: const Duration(seconds: 2),
                );
              }
            }
          }
          break;
      }

      // 延迟刷新权限状态
      await Future.delayed(const Duration(seconds: 1));
      if (permissionType == 'storage' ||
          permissionType == 'notification' ||
          permissionType == 'accessibility' ||
          permissionType == 'mediaProjection') {
        _loadPermissions();
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, '请求权限失败: ' + e.toString());
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
                  children: [_buildPermissionsDropdown(context)],
                ),
                const SizedBox(height: AppTheme.spacing4),
                // 显示与排序
                _buildSection(
                  context: context,
                  title: '显示与排序',
                  children: [
                    _buildPrivacyModeItem(context),
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
                    _buildScreenshotExpireItem(context),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),
                // 时间段总结设置
                _buildSection(
                  context: context,
                  title: '时间段总结',
                  children: [
                    _buildSegmentSampleItem(context),
                    _buildSegmentDurationItem(context),
                    _buildAiRequestIntervalItem(context),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),

                // 每日总结提醒
                _buildSection(
                  context: context,
                  title: '每日总结提醒',
                  children: [
                    _buildDailyNotifyItem(context),
                    _buildDailyNotifyBannerItem(context),
                    _buildDailyNotifyTestItem(context),
                  ],
                ),

                const SizedBox(height: AppTheme.spacing4),
                // AI 助手
                _buildSection(
                  context: context,
                  title: 'AI 助手',
                  children: [
                    _buildAIEntryItem(context),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),
                // 数据与备份
                _buildSection(
                  context: context,
                  title: '数据与备份',
                  children: [
                    _buildExportItem(context),
                    _buildImportItem(context),
                  ],
                ),
              ],
            ),
    );
  }

  // ===== 时间段总结设置 UI =====
  Widget _buildSegmentSampleItem(BuildContext context) {
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.photo_library_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('采样间隔（秒）', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('当前：${_segmentSampleIntervalSec} 秒', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentSampleDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3, vertical: AppTheme.spacing1),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentDurationItem(BuildContext context) {
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
              Icons.schedule_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('时间段时长（分钟）', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('当前：${_segmentDurationMin} 分钟', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentDurationDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3, vertical: AppTheme.spacing1),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }

  // ===== AI请求间隔设置 UI =====
  Widget _buildAiRequestIntervalItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.speed_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 请求最小间隔（秒）', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('当前：${_aiRequestIntervalSec} 秒（最低1秒）', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showAiRequestIntervalDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3, vertical: AppTheme.spacing1),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }



  void _showAiRequestIntervalDialog() {
    final TextEditingController controller = TextEditingController(text: _aiRequestIntervalSec.toString());
    showUIDialog<void>(
      context: context,
      title: '设置AI请求最小间隔（秒）',
      content: _numberField(controller, hint: '请输入 ≥1 的整数'),
      actions: [
        const UIDialogAction(text: '取消'),
        UIDialogAction(
          text: '确定',
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 1) { UINotifier.error(ctx, '请输入 ≥1 的有效整数'); return; }
            final v = parsed.clamp(1, 60);
            try {
              const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
              await platform.invokeMethod('setAiRequestIntervalSec', {'seconds': v});
              if (mounted) setState(() { _aiRequestIntervalSec = v; });
              if (ctx.mounted) { Navigator.of(ctx).pop(); UINotifier.success(ctx, '已设置为 $v 秒'); }
            } catch (e) {
              if (ctx.mounted) UINotifier.error(ctx, '保存失败: ' + e.toString());
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadSegmentSettings() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final res = await platform.invokeMethod('getSegmentSettings');
      final map = Map<String, dynamic>.from(res ?? {});
      if (mounted) {
        setState(() {
          _segmentSampleIntervalSec = ((map['sampleIntervalSec'] as int?) ?? 20).clamp(5, 3600);
          final durSec = ((map['segmentDurationSec'] as int?) ?? 300).clamp(60, 24*3600);
          _segmentDurationMin = (durSec / 60).round();
        });
      }
    } catch (_) {}
  }

  // 读取AI请求最小间隔（秒），默认3，最低1
  Future<void> _loadAiRequestInterval() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final sec = await platform.invokeMethod('getAiRequestIntervalSec');
      final v = (sec as int?) ?? 3;
      if (mounted) {
        setState(() { _aiRequestIntervalSec = v.clamp(1, 60); });
      }
    } catch (_) {
      if (mounted) setState(() { _aiRequestIntervalSec = 3; });
    }
  }




  void _showSegmentSampleDialog() {
    final TextEditingController controller = TextEditingController(text: _segmentSampleIntervalSec.toString());
    showUIDialog<void>(
      context: context,
      title: '设置采样间隔（秒）',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _numberField(controller, hint: '请输入 >=5 的整数'),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Text(
              '说明：采样仅基于已保存的截图进行分析，不会重新触发截图或影响后台行为。',
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
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 5) { UINotifier.error(ctx, '请输入 >=5 的有效整数'); return; }
            await _saveSegmentSettings(sample: v, durationMin: _segmentDurationMin);
            if (ctx.mounted) { Navigator.of(ctx).pop(); UINotifier.success(ctx, '已设置为 $v 秒'); }
          },
        ),
      ],
    );
  }

  void _showSegmentDurationDialog() {
    final TextEditingController controller = TextEditingController(text: _segmentDurationMin.toString());
    showUIDialog<void>(
      context: context,
      title: '设置时间段时长（分钟）',
      content: _numberField(controller, hint: '请输入 >=1 的整数'),
      actions: [
        const UIDialogAction(text: '取消'),
        UIDialogAction(
          text: '确定',
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 1) { UINotifier.error(ctx, '请输入 >=1 的有效整数'); return; }
            await _saveSegmentSettings(sample: _segmentSampleIntervalSec, durationMin: v);
            if (ctx.mounted) { Navigator.of(ctx).pop(); UINotifier.success(ctx, '已设置为 $v 分钟'); }
          },
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController c, {required String hint}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: hint,
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(AppTheme.spacing3),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  Future<void> _saveSegmentSettings({required int sample, required int durationMin}) async {
    final sampleClamped = sample < 5 ? 5 : sample;
    final durationSec = (durationMin <= 0 ? 1 : durationMin) * 60;
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('setSegmentSettings', {
        'sampleIntervalSec': sampleClamped,
        'segmentDurationSec': durationSec,
      });
      setState(() { _segmentSampleIntervalSec = sampleClamped; _segmentDurationMin = durationMin; });
    } catch (e) {
      if (mounted) UINotifier.error(context, '保存失败: ' + e.toString());
    }
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
          padding: const EdgeInsets.only(
            left: AppTheme.spacing1,
            bottom: AppTheme.spacing3,
          ),
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
          child: Column(children: children),
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              isGranted ? Icons.check : icon,
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
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
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
              child: const Text('去授权'),
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
                  '导出数据',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '导出 ZIP 至 Download/ScreenMemory',
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('导出'),
          ),
        ],
      ),
    );
  }

  Widget _buildImportItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.file_upload_outlined,
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
                  '导入数据',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '将ZIP文件导入到应用存储',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _importingData ? null : _importData,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: _importingData
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('导入'),
          ),
        ],
      ),
    );
  }

  Widget _buildAIEntryItem(BuildContext context) {
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
              Icons.smart_toy_outlined,
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
                  'AI 助手',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '配置 AI 接口与模型，并进行多轮对话测试',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AISettingsPage(),
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('进入'),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
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

  Widget _buildPrivacyModeItem(BuildContext context) {
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.privacy_tip_outlined,
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
                  '隐私模式',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '对敏感内容自动模糊遮挡',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _privacyMode,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _updatePrivacyMode(v),
            ),
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.timer_outlined,
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
                  '截屏间隔',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '当前间隔：' + _screenshotInterval.toString() + ' 秒',
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
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.image_outlined,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
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
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  GestureDetector(
                                    onTap: _useTargetSize
                                        ? _showTargetSizeDialog
                                        : null,
                                    child: Text(
                                      '${_targetSizeKb}KB',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: _useTargetSize
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                            decoration: _useTargetSize
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  Flexible(
                                    child: Text(
                                      '（点击数字可修改）',
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
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
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) async {
                            setState(() {
                              _useTargetSize = v;
                            });
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
          // 与“截屏间隔”项保持一致的内边距与间距（去除多余的底部空白）
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
                hintText: '请输入 5-60 的整数',
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
              '范围：5-60 秒，默认 5 秒',
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
            final interval = int.tryParse(input);
            if (interval == null || interval < 5 || interval > 60) {
              UINotifier.error(ctx, '请输入 5-60 的有效整数');
              return;
            }
            await _updateScreenshotInterval(interval);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, '截屏间隔已设置为 ' + interval.toString() + ' 秒');
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
      title: '设置目标大小（单位KB）',
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
              UINotifier.success(ctx, '目标大小已设置为 ' + kb.toString() + ' KB');
            }
          },
        ),
      ],
    );

  }

  Widget _buildScreenshotExpireItem(BuildContext context) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacing3),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
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
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                Icons.auto_delete_outlined,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                size: 18,
              ),
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 72),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '截图过期清理',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        IgnorePointer(
                          ignoring: !_expireEnabled,
                          child: Opacity(
                            opacity: _expireEnabled ? 1.0 : 0.5,
                            child: Row(
                              children: [
                                Text(
                                  '当前过期天数:',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(width: AppTheme.spacing1),
                                GestureDetector(
                                  onTap: _expireEnabled
                                      ? _showExpireDaysDialog
                                      : null,
                                  child: Text(
                                    '${_expireDays}天',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: _expireEnabled
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                          decoration: _expireEnabled
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppTheme.spacing1),
                                Flexible(
                                  child: Text(
                                    '（点击数字可修改）',
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
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
                  Positioned(
                    top: -1,
                    right: 0,
                    child: Transform.scale(
                      scale: 0.9,
                      child: Switch(
                        value: _expireEnabled,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) async {
                          setState(() {
                            _expireEnabled = v;
                          });
                          await _saveScreenshotExpireSettings();
                          // 开启或修改后立即尝试清理一次（后台节流保护）
                          // ignore: unawaited_futures
                          ScreenshotService.instance
                              .cleanupExpiredScreenshotsIfNeeded(force: v);
                        },
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

    void _showExpireDaysDialog() {
      final TextEditingController controller = TextEditingController(
        text: _expireDays.toString(),
      );
      showUIDialog<void>(
        context: context,
        title: '设置截图过期天数',
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
                  labelText: '过期天数',
                  hintText: '请输入 >= 1 的整数',
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
                '下限为 1 天；开启后，应用会在启动和每次截图后按周期自动清理过期文件（12小时节流保护）。',
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
              final d = int.tryParse(input);
              if (d == null || d < 1) {
                UINotifier.error(ctx, '请输入 >= 1 的有效整数');
                return;
              }
              setState(() {
                _expireEnabled = true;
                _expireDays = d;
              });
              await _saveScreenshotExpireSettings();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(ctx, '已设置为 ' + d.toString() + ' 天');
              }
              // ignore: unawaited_futures
              ScreenshotService.instance.cleanupExpiredScreenshotsIfNeeded(
                force: true,
              );
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

    Future<void> _loadScreenshotExpireSettings() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _expireEnabled = prefs.getBool('screenshot_expire_enabled') ?? false;
          final d = prefs.getInt('screenshot_expire_days') ?? 30;
          _expireDays = d < 1 ? 1 : d;
        });
      } catch (_) {}
    }

    Future<void> _saveScreenshotExpireSettings() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('screenshot_expire_enabled', _expireEnabled);
        await prefs.setInt(
          'screenshot_expire_days',
          _expireDays < 1 ? 1 : _expireDays,
        );
        if (mounted) {
          UINotifier.success(context, '过期清理设置已保存');
        }
      } catch (e) {
        if (mounted) {
          UINotifier.error(context, '保存失败: ' + e.toString() + e.toString());
        }
      }
    }

    Future<void> _loadPrivacyMode() async {
      try {
        final enabled = await _appService.getPrivacyModeEnabled();
        if (mounted) {
          setState(() {
            _privacyMode = enabled;
          });
        }
      } catch (_) {}
    }

    Future<void> _updatePrivacyMode(bool enabled) async {
      await _appService.savePrivacyModeEnabled(enabled);
      if (mounted) {
        setState(() {
          _privacyMode = enabled;
        });
        UINotifier.success(context, enabled ? '已开启隐私模式' : '已关闭隐私模式');
      }
    }

    Future<void> _saveScreenshotQualitySettings() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        // 根据是否启用目标大小自动设置格式：启用->webp_lossy；关闭->webp_lossless（原画质）
        await prefs.setString(
          'image_format',
          _useTargetSize ? 'webp_lossy' : 'webp_lossless',
        );
        await prefs.setInt('image_quality', _imageQuality);
        await prefs.setBool('use_target_size', _useTargetSize);
        await prefs.setInt(
          'target_size_kb',
          _targetSizeKb < 50 ? 50 : _targetSizeKb,
        );
        // 不再保存灰度
        if (mounted) {
          UINotifier.success(context, '截图质量设置已保存');
        }
      } catch (e) {
        if (mounted) {
          UINotifier.error(context, '保存失败: ' + e.toString());
        }
      }
    }

    String _sortModeLabel(String mode) {
      switch (mode) {
        case 'timeAsc':
          return '时间（旧→新）';
        case 'timeDesc':
          return '时间（新→旧）';
        case 'sizeAsc':
          return '大小（小→大）';
        case 'sizeDesc':
          return '大小（大→小）';
        case 'countAsc':
          return '数量（少→多）';
        case 'countDesc':
          return '数量（多→少）';
        case 'lastScreenshot':
          return '时间（新→旧）';
        case 'screenshotCount':
          return '数量（多→少）';
        default:
          return '时间（新→旧）';
      }
    }

  Future<void> _updateSortMode(String mode) async {
    await _appService.saveSortMode(mode);
    if (mounted) {
      setState(() {
        _sortMode = mode;
      });
      UINotifier.success(context, '首页排序已设置为 ' + _sortModeLabel(mode));
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
        children: [Text('当前：' + _sortModeLabel(_sortMode))],
      ),
      actions: const [
        UIDialogAction<String>(
          text: '时间（新→旧）',
          result: 'timeDesc',
          style: UIDialogActionStyle.primary,
        ),
        UIDialogAction<String>(text: '时间（旧→新）', result: 'timeAsc'),
        UIDialogAction<String>(text: '大小（大→小）', result: 'sizeDesc'),
        UIDialogAction<String>(text: '大小（小→大）', result: 'sizeAsc'),
        UIDialogAction<String>(text: '数量（多→少）', result: 'countDesc'),
        UIDialogAction<String>(text: '数量（少→多）', result: 'countAsc'),
        UIDialogAction<String>(text: '取消', result: 'cancel'),
      ],
    );
    if (!mounted) return;
    if (selected != null && selected != 'cancel') {
      await _updateSortMode(selected);
    }
  }
}


// ========== 扩展：每日总结提醒设置（提示时间 + 测试按钮） ==========
extension _DailySummaryNotifyExt on _SettingsPageState {
  Future<void> _loadDailyNotifySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _dailyNotifyEnabled = prefs.getBool('daily_notify_enabled') ?? true;
        _dailyNotifyHour = (prefs.getInt('daily_notify_hour') ?? 22).clamp(0, 23);
        _dailyNotifyMinute = (prefs.getInt('daily_notify_minute') ?? 0).clamp(0, 59);
      });
      await FlutterLogger.nativeInfo(
        'DailySummaryUI',
        'load settings: enabled=${_dailyNotifyEnabled} time=${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)}',
      );
      final ok = await DailySummaryService.instance.scheduleDailyNotification(
        hour: _dailyNotifyHour,
        minute: _dailyNotifyMinute,
        enabled: _dailyNotifyEnabled,
      );
      await FlutterLogger.nativeInfo('DailySummaryUI', 'restore schedule on load result=$ok');
    } catch (e) {
      await FlutterLogger.nativeWarn('DailySummaryUI', 'load settings failed: $e');
    }
  }

  Future<void> _saveDailyNotifySettings({
    bool? enabled,
    int? hour,
    int? minute,
    bool toast = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newEnabled = enabled ?? _dailyNotifyEnabled;
      final newHour = (hour ?? _dailyNotifyHour).clamp(0, 23);
      final newMinute = (minute ?? _dailyNotifyMinute).clamp(0, 59);

      await prefs.setBool('daily_notify_enabled', newEnabled);
      await prefs.setInt('daily_notify_hour', newHour);
      await prefs.setInt('daily_notify_minute', newMinute);

      if (mounted) {
        setState(() {
          _dailyNotifyEnabled = newEnabled;
          _dailyNotifyHour = newHour;
          _dailyNotifyMinute = newMinute;
        });
      }

      final ok = await DailySummaryService.instance.scheduleDailyNotification(
        hour: newHour,
        minute: newMinute,
        enabled: newEnabled,
      );
      if (toast && mounted) {
        if (ok) {
          UINotifier.success(
            context,
            newEnabled
                ? '已设置每日提醒时间为 ${_two(newHour)}:${_two(newMinute)}'
                : '已关闭每日提醒',
          );
        } else {
          UINotifier.warning(context, '调度每日提醒失败（可能平台不支持）');
        }
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, '保存提醒设置失败: $e');
    }
  }

  Future<void> _pickDailyNotifyTime() async {
    final initial = TimeOfDay(hour: _dailyNotifyHour, minute: _dailyNotifyMinute);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    await _saveDailyNotifySettings(hour: picked.hour, minute: picked.minute);
  }

  Widget _buildDailyNotifyItem(BuildContext context) {
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.schedule_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('每日总结提醒时间',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  _dailyNotifyEnabled
                      ? '当前：${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)} · 已开启'
                      : '当前：${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)} · 已关闭',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _pickDailyNotifyTime,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('设置时间'),
          ),
          const SizedBox(width: AppTheme.spacing2),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _dailyNotifyEnabled,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) async {
                await _saveDailyNotifySettings(enabled: v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyNotifyTestItem(BuildContext context) {
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
              Icons.notifications_active_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('测试通知',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  '立即触发“今日总结”通知（若无当日总结会尽量生成后再发送）',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () async {
              // 尽量生成/获取当日总结（包含 notification_brief）
              final key = _todayKey();
              try {
                await DailySummaryService.instance.getOrGenerate(key, force: false);
              } catch (_) {}
              final ok = await DailySummaryService.instance.triggerNotificationNow(key);
              if (!mounted) return;
              if (ok) {
                UINotifier.success(context, '已触发通知');
              } else {
                UINotifier.warning(context, '触发通知失败或内容为空');
              }
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('触发'),
          ),
        ],
      ),
    );
  }

  // 打开“每日总结提醒”渠道设置（开启横幅/悬浮通知等）
  Future<void> _openDailyChannelSettings() async {
    try {
      await FlutterLogger.nativeInfo('DailySummaryUI', 'open channel settings');
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('openDailySummaryNotificationSettings');
    } catch (e) {
      if (mounted) UINotifier.error(context, 'Open channel settings failed: $e');
    }
  }

  // 打开“应用通知”总设置（可选）
  Future<void> _openAppNotificationSettings() async {
    try {
      await FlutterLogger.nativeInfo('DailySummaryUI', 'open app notification settings');
      const platform = MethodChannel('com.fqyw/screen_memo/accessibility');
      // 兼容：统一使用正确通道名
    } catch (_) {}
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('openAppNotificationSettings');
    } catch (e) {
      if (mounted) UINotifier.error(context, 'Open app notification settings failed: $e');
    }
  }


  // 行项：开启横幅/悬浮通知
  Widget _buildDailyNotifyBannerItem(BuildContext context) {
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
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.notification_important_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('开启横幅/悬浮通知', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  '允许在屏幕顶部弹出通知（横幅/悬浮）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _openDailyChannelSettings,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3, vertical: AppTheme.spacing1),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: const Text('去开启'),
          ),
        ],
      ),
    );
  }


  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${_two(now.month)}-${_two(now.day)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}
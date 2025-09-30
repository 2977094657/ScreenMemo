import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
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
import '../services/locale_service.dart';

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
        title: AppLocalizations.of(context).storagePermissionTitle,
        description: AppLocalizations.of(context).storagePermissionDesc,
        isGranted: _permissions['storage'] ?? false,
        onRequest: () => _requestPermission('storage'),
      ),
      const SizedBox(height: AppTheme.spacing2),
      _buildPermissionItem(
        context: context,
        icon: Icons.notifications_outlined,
        title: AppLocalizations.of(context).notificationPermissionTitle,
        description: AppLocalizations.of(context).notificationPermissionDesc,
        isGranted: _permissions['notification'] ?? false,
        onRequest: () => _requestPermission('notification'),
      ),
      const SizedBox(height: AppTheme.spacing2),
      _buildPermissionItem(
        context: context,
        icon: Icons.accessibility_new_outlined,
        title: AppLocalizations.of(context).accessibilityPermissionTitle,
        description: AppLocalizations.of(context).accessibilityPermissionDesc,
        isGranted: _permissions['accessibility'] ?? false,
        onRequest: () => _requestPermission('accessibility'),
      ),
      const SizedBox(height: AppTheme.spacing2),
      _buildPermissionItem(
        context: context,
        icon: Icons.analytics_outlined,
        title: AppLocalizations.of(context).usageStatsPermissionTitle,
        description: AppLocalizations.of(context).usageStatsPermissionDesc,
        isGranted: _permissions['usage_stats'] ?? false,
        onRequest: () => _requestPermission('usage_stats'),
      ),
    ];
    final keepAliveItems = [
      _buildPermissionItem(
        context: context,
        icon: Icons.battery_saver_outlined,
        title: AppLocalizations.of(context).batteryOptimizationTitle,
        description: AppLocalizations.of(context).batteryOptimizationDesc,
        isGranted: _keepAlivePermissions['battery_optimization'] ?? false,
        onRequest: () => _requestPermission('battery_optimization'),
      ),
      const SizedBox(height: AppTheme.spacing2),
      _buildPermissionItem(
        context: context,
        icon: Icons.power_settings_new_outlined,
        title: AppLocalizations.of(context).autostartPermissionTitle,
        description: AppLocalizations.of(context).autostartPermissionDesc,
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
                        AppLocalizations.of(context).permissionsSectionTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _allPermissionsGranted()
                            ? AppLocalizations.of(context).allPermissionsGranted
                            : AppLocalizations.of(context).permissionsMissingCount(missingCount),
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
          title: AppLocalizations.of(context).exportSuccessTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).exportFileExportedTo),
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
              text: AppLocalizations.of(context).actionCopyPath,
              style: UIDialogActionStyle.normal,
              closeOnPress: false,
              onPressed: (ctx) async {
                await Clipboard.setData(ClipboardData(text: displayPath));
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                  UINotifier.success(ctx, AppLocalizations.of(ctx).pathCopiedToast);
                }
              },
            ),
            UIDialogAction(
              text: AppLocalizations.of(context).dialogOk,
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      } else {
        await FlutterLogger.nativeWarn('UI_EXPORT', 'export returned null');
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).exportFailedTitle,
          message: AppLocalizations.of(context).pleaseTryAgain,
          actions: [
            UIDialogAction(text: AppLocalizations.of(context).dialogOk, style: UIDialogActionStyle.primary),
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
          title: AppLocalizations.of(context).importCompleteTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).dataExtractedTo),
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
          actions: [
            UIDialogAction(text: AppLocalizations.of(context).dialogOk, style: UIDialogActionStyle.primary),
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
          title: AppLocalizations.of(context).importFailedTitle,
          message: AppLocalizations.of(context).importFailedCheckZip,
          actions: [
            UIDialogAction(text: AppLocalizations.of(context).dialogOk, style: UIDialogActionStyle.primary),
          ],
        );
      }
    } catch (e) { 
      if (!mounted) return; 
      await FlutterLogger.nativeError('UI_IMPORT', 'exception: ' + e.toString());
      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: AppLocalizations.of(context).importFailedTitle,
        content: Text('$e'),
        actions: [
          UIDialogAction(text: AppLocalizations.of(context).dialogOk, style: UIDialogActionStyle.primary),
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
          title: AppLocalizations.of(context).confirmPermissionSettingsTitle,
          message: AppLocalizations.of(context).confirmAutostartQuestion,
          actions: [
            UIDialogAction<bool>(text: AppLocalizations.of(context).notYet, result: false),
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).done,
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
          UINotifier.info(context, AppLocalizations.of(context).noMediaProjectionNeeded);
          break;
        case 'battery_optimization':
          if (mounted) {
            UINotifier.info(
              context,
              AppLocalizations.of(context).pleaseCompleteInSystemSettings,
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
                  AppLocalizations.of(context).autostartPermissionMarked,
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
        UINotifier.error(context, AppLocalizations.of(context).requestPermissionFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).settingsTitle),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPermissions,
            tooltip: AppLocalizations.of(context).refreshPermissionStatus,
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
                  title: AppLocalizations.of(context).permissionsSectionTitle,
                  children: [_buildPermissionsDropdown(context)],
                ),
                const SizedBox(height: AppTheme.spacing4),
                // 显示与排序（加入语言设置）
                _buildSection(
                  context: context,
                  title: AppLocalizations.of(context).displayAndSortSectionTitle,
                  children: [
                    _buildLanguageItem(context),
                    _buildPrivacyModeItem(context),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),

                // 截屏设置
                _buildSection(
                  context: context,
                  title: AppLocalizations.of(context).screenshotSectionTitle,
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
                  title: AppLocalizations.of(context).segmentSummarySectionTitle,
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
                  title: AppLocalizations.of(context).dailyReminderSectionTitle,
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
                  title: AppLocalizations.of(context).aiAssistantSectionTitle,
                  children: [
                    _buildAIEntryItem(context),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),
                // 数据与备份
                _buildSection(
                  context: context,
                  title: AppLocalizations.of(context).dataBackupSectionTitle,
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
                Text(AppLocalizations.of(context).segmentSampleIntervalTitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(AppLocalizations.of(context).segmentSampleIntervalDesc(_segmentSampleIntervalSec), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            child: Text(AppLocalizations.of(context).actionSet),
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
                Text(AppLocalizations.of(context).segmentDurationTitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(AppLocalizations.of(context).segmentDurationDesc(_segmentDurationMin), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            child: Text(AppLocalizations.of(context).actionSet),
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
                Text(AppLocalizations.of(context).aiRequestIntervalTitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(AppLocalizations.of(context).aiRequestIntervalDesc(_aiRequestIntervalSec), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }



  void _showAiRequestIntervalDialog() {
    final TextEditingController controller = TextEditingController(text: _aiRequestIntervalSec.toString());
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).aiRequestIntervalTitle,
      content: _numberField(controller, hint: AppLocalizations.of(context).intervalInputHint),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 1) { UINotifier.error(ctx, AppLocalizations.of(ctx).intervalInvalidError); return; }
            final v = parsed.clamp(1, 60);
            try {
              const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
              await platform.invokeMethod('setAiRequestIntervalSec', {'seconds': v});
              if (mounted) setState(() { _aiRequestIntervalSec = v; });
              if (ctx.mounted) { Navigator.of(ctx).pop(); UINotifier.success(ctx, AppLocalizations.of(ctx).intervalSavedSuccess(v)); }
            } catch (e) {
              if (ctx.mounted) UINotifier.error(ctx, AppLocalizations.of(ctx).requestPermissionFailed(e.toString()));
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
      title: AppLocalizations.of(context).segmentSampleIntervalTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _numberField(controller, hint: AppLocalizations.of(context).intervalInputHint),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              AppLocalizations.of(context).targetSizeHint,
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
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 5) { UINotifier.error(ctx, AppLocalizations.of(ctx).intervalInvalidError); return; }
            await _saveSegmentSettings(sample: v, durationMin: _segmentDurationMin);
            if (ctx.mounted) { Navigator.of(ctx).pop(); UINotifier.success(ctx, AppLocalizations.of(ctx).intervalSavedSuccess(v)); }
          },
        ),
      ],
    );
  }

  void _showSegmentDurationDialog() {
    final TextEditingController controller = TextEditingController(text: _segmentDurationMin.toString());
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).segmentDurationTitle,
      content: _numberField(controller, hint: AppLocalizations.of(context).intervalInputHint),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 1) { UINotifier.error(ctx, AppLocalizations.of(ctx).intervalInvalidError); return; }
            await _saveSegmentSettings(sample: _segmentSampleIntervalSec, durationMin: v);
            if (ctx.mounted) { Navigator.of(ctx).pop(); UINotifier.success(ctx, AppLocalizations.of(ctx).expireDaysSavedSuccess(v)); }
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
              AppLocalizations.of(context).grantedLabel,
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
              child: Text(AppLocalizations.of(context).authorizeAction),
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
                  AppLocalizations.of(context).exportDataTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).exportDataDesc,
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
                : Text(AppLocalizations.of(context).actionExport),
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
                  AppLocalizations.of(context).importDataTitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).importDataDesc,
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
                : Text(AppLocalizations.of(context).actionImport),
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
                  AppLocalizations.of(context).aiAssistantTitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).aiAssistantDesc,
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
            child: Text(AppLocalizations.of(context).actionEnter),
          ),
        ],
      ),
    );
  }


  // 语言设置
  Widget _buildLanguageItem(BuildContext context) {
    final t = AppLocalizations.of(context);
    final opt = LocaleService.instance.option;
    String currentLabel;
    switch (opt) {
      case 'zh':
        currentLabel = t.languageChinese;
        break;
      case 'en':
        currentLabel = t.languageEnglish;
        break;
      default:
        currentLabel = t.languageSystem;
        break;
    }
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
              Icons.language,
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
                  t.languageSettingTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  currentLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () async {
              final selected = await showUIDialog<String>(
                context: context,
                barrierDismissible: true,
                title: t.languageSettingTitle,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text('${t.currentTimeLabel}$currentLabel')],
                ),
                actions: [
                  UIDialogAction<String>(
                    text: t.languageSystem,
                    result: 'system',
                  ),
                  UIDialogAction<String>(
                    text: t.languageChinese,
                    result: 'zh',
                  ),
                  UIDialogAction<String>(
                    text: t.languageEnglish,
                    result: 'en',
                  ),
                  UIDialogAction<String>(text: t.dialogCancel, result: 'cancel'),
                ],
              );
              if (!mounted) return;
              if (selected == null || selected == 'cancel') return;

              await LocaleService.instance.setOption(selected);
              if (mounted) {
                setState(() {});
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final tt = AppLocalizations.of(context);
                String newLabel2;
                switch (LocaleService.instance.option) {
                  case 'zh':
                    newLabel2 = tt.languageChinese;
                    break;
                  case 'en':
                    newLabel2 = tt.languageEnglish;
                    break;
                  default:
                    newLabel2 = tt.languageSystem;
                    break;
                }
                UINotifier.success(context, tt.languageChangedToast(newLabel2));
              });
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
            child: Text(t.actionSet),
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
                  AppLocalizations.of(context).privacyModeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).privacyModeDesc,
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
                  AppLocalizations.of(context).screenshotIntervalTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).screenshotIntervalDesc(_screenshotInterval),
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
            child: Text(AppLocalizations.of(context).actionSet),
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
                            AppLocalizations.of(context).screenshotQualityTitle,
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
                                    AppLocalizations.of(context).currentTimeLabel,
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
                                      AppLocalizations.of(context).clickToModifyHint,
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
      title: AppLocalizations.of(context).setIntervalDialogTitle,
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
                labelText: AppLocalizations.of(context).intervalSecondsLabel,
                hintText: AppLocalizations.of(context).intervalInputHint,
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
              AppLocalizations.of(context).intervalRangeHint,
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
              UINotifier.error(ctx, AppLocalizations.of(ctx).intervalInvalidError);
              return;
            }
            await _updateScreenshotInterval(interval);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).intervalSavedSuccess(interval));
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
      title: AppLocalizations.of(context).setTargetSizeDialogTitle,
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
                labelText: AppLocalizations.of(context).targetSizeKbLabel,
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
              AppLocalizations.of(context).targetSizeHint,
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
            final kb = int.tryParse(input);
            if (kb == null || kb < 50) {
              UINotifier.error(ctx, AppLocalizations.of(ctx).targetSizeInvalidError);
              return;
            }
            setState(() {
              _useTargetSize = true;
              _targetSizeKb = kb;
            });
            await _saveScreenshotQualitySettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).targetSizeSavedSuccess(kb));
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
                          AppLocalizations.of(context).screenshotExpireTitle,
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
                                  AppLocalizations.of(context).currentTimeLabel,
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
                                    AppLocalizations.of(context).expireDaysUnit(_expireDays),
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
                                    AppLocalizations.of(context).clickToModifyHint,
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
        title: AppLocalizations.of(context).setExpireDaysDialogTitle,
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
                  labelText: AppLocalizations.of(context).expireDaysLabel,
                  hintText: AppLocalizations.of(context).expireDaysInputHint,
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
                AppLocalizations.of(context).expireDaysHint,
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
              final d = int.tryParse(input);
              if (d == null || d < 1) {
                UINotifier.error(ctx, AppLocalizations.of(ctx).expireDaysInvalidError);
                return;
              }
              setState(() {
                _expireEnabled = true;
                _expireDays = d;
              });
              await _saveScreenshotExpireSettings();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(ctx, AppLocalizations.of(ctx).expireDaysSavedSuccess(d));
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
          UINotifier.success(context, AppLocalizations.of(context).expireCleanupSaved);
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
        UINotifier.success(context, enabled ? AppLocalizations.of(context).privacyModeEnabledToast : AppLocalizations.of(context).privacyModeDisabledToast);
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
          UINotifier.success(context, AppLocalizations.of(context).screenshotQualitySettingsSaved);
        }
      } catch (e) {
        if (mounted) {
          UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
        }
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
      // 启动一次“自动预生成”调度
      await DailySummaryService.instance.refreshAutoRefreshSchedule();
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
      // 刷新“预生成”定时器，使得在提醒前1分钟自动刷新当日总结
      await DailySummaryService.instance.refreshAutoRefreshSchedule();
      if (toast && mounted) {
        if (ok) {
          UINotifier.success(
            context,
            newEnabled
                ? AppLocalizations.of(context).reminderScheduleSuccess(_two(newHour), _two(newMinute))
                : AppLocalizations.of(context).reminderDisabledSuccess,
          );
        } else {
          UINotifier.warning(context, AppLocalizations.of(context).reminderScheduleFailed);
        }
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveReminderSettingsFailed(e.toString()));
    }
  }

  Future<void> _pickDailyNotifyTime() async {
    // 数字输入方式：点击时间数字后弹出输入框，类似“截图质量”的交互
    final TextEditingController hourController =
        TextEditingController(text: _two(_dailyNotifyHour));
    final TextEditingController minuteController =
        TextEditingController(text: _two(_dailyNotifyMinute));

    await showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setReminderTimeTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: TextField(
                    controller: hourController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).hourLabel,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(AppTheme.spacing3),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: TextField(
                    controller: minuteController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).minuteLabel,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(AppTheme.spacing3),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              AppLocalizations.of(context).timeInputHint,
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
            final h = int.tryParse(hourController.text.trim());
            final m = int.tryParse(minuteController.text.trim());
            if (h == null || h < 0 || h > 23) {
              UINotifier.error(ctx, AppLocalizations.of(ctx).invalidHourError);
              return;
            }
            if (m == null || m < 0 || m > 59) {
              UINotifier.error(ctx, AppLocalizations.of(ctx).invalidMinuteError);
              return;
            }
            await _saveDailyNotifySettings(hour: h, minute: m);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).timeSetSuccess(_two(h), _two(m)));
            }
          },
        ),
      ],
    );
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
                Text(AppLocalizations.of(context).dailyReminderTimeTitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                IgnorePointer(
                  ignoring: !_dailyNotifyEnabled,
                  child: Opacity(
                    opacity: _dailyNotifyEnabled ? 1.0 : 0.5,
                    child: Row(
                      children: [
                        Text(
                          AppLocalizations.of(context).currentTimeLabel,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        GestureDetector(
                          onTap: _dailyNotifyEnabled ? _pickDailyNotifyTime : null,
                          child: Text(
                            '${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: _dailyNotifyEnabled
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                  decoration: _dailyNotifyEnabled
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing1),
                        Flexible(
                          child: Text(
                            AppLocalizations.of(context).clickToModifyHint,
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
                Text(AppLocalizations.of(context).testNotificationTitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).testNotificationDesc,
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
              // 先强制重新生成当日总结，确保通知内容新鲜
              final key = _todayKey();
              try {
                await DailySummaryService.instance.getOrGenerate(key, force: true);
              } catch (_) {}
              final ok = await DailySummaryService.instance.triggerNotificationNow(key);
              if (!mounted) return;
              if (ok) {
                UINotifier.success(context, AppLocalizations.of(context).dailyNotifyTriggered);
              } else {
                UINotifier.warning(context, AppLocalizations.of(context).dailyNotifyTriggerFailed);
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
            child: Text(AppLocalizations.of(context).actionTrigger),
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
                Text(AppLocalizations.of(context).enableBannerNotificationTitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).enableBannerNotificationDesc,
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
            child: Text(AppLocalizations.of(context).actionOpen),
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
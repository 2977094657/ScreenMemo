part of 'settings_page.dart';

// ========== 权限检查与权限引导 UI ==========
extension _SettingsPermissionsPart on _SettingsPageState {
  Widget _buildPermissionsDropdown(BuildContext context) {
    return Column(
      children: [
        _buildPermissionItem(
          context: context,
          icon: Icons.folder_outlined,
          title: AppLocalizations.of(context).storagePermissionTitle,
          description: AppLocalizations.of(context).storagePermissionDesc,
          isGranted: _permissions['storage'] ?? false,
          onRequest: () => _requestPermission('storage'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.notifications_outlined,
          title: AppLocalizations.of(context).notificationPermissionTitle,
          description: AppLocalizations.of(context).notificationPermissionDesc,
          isGranted: _permissions['notification'] ?? false,
          onRequest: () => _requestPermission('notification'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.accessibility_new_outlined,
          title: AppLocalizations.of(context).accessibilityPermissionTitle,
          description: AppLocalizations.of(context).accessibilityPermissionDesc,
          isGranted: _permissions['accessibility'] ?? false,
          onRequest: () => _requestPermission('accessibility'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.analytics_outlined,
          title: AppLocalizations.of(context).usageStatsPermissionTitle,
          description: AppLocalizations.of(context).usageStatsPermissionDesc,
          isGranted: _permissions['usage_stats'] ?? false,
          onRequest: () => _requestPermission('usage_stats'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.battery_saver_outlined,
          title: AppLocalizations.of(context).batteryOptimizationTitle,
          description: AppLocalizations.of(context).batteryOptimizationDesc,
          isGranted: _keepAlivePermissions['battery_optimization'] ?? false,
          onRequest: () => _requestPermission('battery_optimization'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.power_settings_new_outlined,
          title: AppLocalizations.of(context).autostartPermissionTitle,
          description: AppLocalizations.of(context).autostartPermissionDesc,
          isGranted: _keepAlivePermissions['autostart'] ?? false,
          onRequest: () => _requestPermission('autostart'),
          showBottomBorder: false,
        ),
      ],
    );
  }

  Future<void> _loadAllPermissions() async {
    await Future.wait([_loadPermissions(), _loadKeepAlivePermissions()]);
  }

  Future<void> _loadPermissions() async {
    try {
      final permissions = await _permissionService.checkAllPermissions();
      if (mounted) {
        _settingsSetState(() {
          _permissions = permissions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _settingsSetState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadKeepAlivePermissions() async {
    try {
      if (mounted) {
        _settingsSetState(() {
          _isLoadingKeepAlive = true;
        });
      }

      // 使用与引导页面相同的权限检测方法和通道
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final result = await platform.invokeMethod('getPermissionStatus');
      if (mounted) {
        _settingsSetState(() {
          _keepAlivePermissions = Map<String, bool>.from(result ?? {});
          _isLoadingKeepAlive = false;
        });
      }
      print('保活权限状态更新完成: ' + _keepAlivePermissions.toString());
    } catch (e) {
      print('加载保活权限失败: $e');
      if (mounted) {
        _settingsSetState(() {
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
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).notYet,
              result: false,
            ),
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
          UINotifier.info(
            context,
            AppLocalizations.of(context).noMediaProjectionNeeded,
          );
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
        UINotifier.error(
          context,
          AppLocalizations.of(context).requestPermissionFailed(e.toString()),
        );
      }
    }
  }

  Widget _buildPermissionItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
    bool showBottomBorder = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBottomBorder
              ? _settingsDividerSide(context)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(
            context,
            isGranted ? Icons.check : icon,
            color: isGranted ? AppTheme.success : null,
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
                  vertical: AppTheme.spacing1 - 1,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(AppLocalizations.of(context).authorizeAction),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../widgets/ui_components.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  static const platform = MethodChannel('com.fqyw.screen_memo/accessibility');

  String _guideText = '';
  String _deviceInfo = '';
  Map<String, dynamic> _permissionStatus = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPermissionInfo();
  }

  Future<void> _loadPermissionInfo() async {
    try {
      final guideText = await platform.invokeMethod('getPermissionGuideText');
      final deviceInfo = await platform.invokeMethod('getDeviceInfo');
      final permissionStatus = await platform.invokeMethod(
        'getPermissionStatus',
      );
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);

      setState(() {
        _guideText = guideText ?? l10n.permissionGuideUnavailable;
        _deviceInfo = deviceInfo ?? l10n.permissionGuideUnknownDevice;
        _permissionStatus = Map<String, dynamic>.from(permissionStatus ?? {});
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _guideText = l10n.permissionGuideLoadFailed(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _openAppDetailsSettings() async {
    try {
      await platform.invokeMethod('openAppDetailsSettings');
      UINotifier.info(
        context,
        AppLocalizations.of(context).permissionGuideSettingsOpened,
      );
    } catch (e) {
      UINotifier.error(
        context,
        AppLocalizations.of(
          context,
        ).permissionGuideOpenSettingsFailed(e.toString()),
      );
    }
  }

  Future<void> _openBatteryOptimizationSettings() async {
    try {
      await platform.invokeMethod('openBatteryOptimizationSettings');
      UINotifier.info(
        context,
        AppLocalizations.of(context).permissionGuideBatteryOpened,
      );
    } catch (e) {
      UINotifier.error(
        context,
        AppLocalizations.of(
          context,
        ).permissionGuideOpenBatteryFailed(e.toString()),
      );
    }
  }

  Future<void> _openAutoStartSettings() async {
    try {
      await platform.invokeMethod('openAutoStartSettings');
      UINotifier.info(
        context,
        AppLocalizations.of(context).permissionGuideAutostartOpened,
      );
    } catch (e) {
      UINotifier.error(
        context,
        AppLocalizations.of(
          context,
        ).permissionGuideOpenAutostartFailed(e.toString()),
      );
    }
  }

  Future<void> _markPermissionConfigured() async {
    try {
      await platform.invokeMethod('markPermissionConfigured', {'type': 'all'});
      UINotifier.success(
        context,
        AppLocalizations.of(context).permissionGuideCompleted,
      );
      Navigator.of(context).pop();
    } catch (e) {
      UINotifier.error(
        context,
        AppLocalizations.of(
          context,
        ).permissionGuideCompleteFailed(e.toString()),
      );
    }
  }

  Widget _buildPermissionStatusCard() {
    if (_permissionStatus.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.permissionStatusTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatusItem(
              l10n.batteryOptimizationTitle,
              _permissionStatus['battery_optimization'] ?? false,
            ),
            _buildStatusItem(
              l10n.autostartPermissionTitle,
              _permissionStatus['autostart'] ?? false,
            ),
            _buildStatusItem(
              l10n.backgroundPermissionTitle,
              _permissionStatus['background'] ?? false,
            ),
            _buildStatusItem(
              l10n.actualBatteryOptimizationStatusTitle,
              _permissionStatus['battery_whitelist_actual'] ?? false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String title, bool isConfigured) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isConfigured ? Icons.check_circle : Icons.cancel,
            color: isConfigured ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(title),
          const Spacer(),
          Text(
            isConfigured
                ? l10n.permissionConfiguredStatus
                : l10n.permissionNeedsConfigurationStatus,
            style: TextStyle(
              color: isConfigured ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.permissionGuideTitle),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 设备信息卡片
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.deviceInfoTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_deviceInfo),
                        ],
                      ),
                    ),
                  ),

                  // 权限状态卡片
                  _buildPermissionStatusCard(),

                  // 设置指南卡片
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.setupGuideTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _guideText.isEmpty
                                ? l10n.permissionGuideLoading
                                : _guideText,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 操作按钮
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openAppDetailsSettings,
                            icon: const Icon(Icons.settings),
                            label: Text(l10n.permissionGuideOpenAppSettings),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openBatteryOptimizationSettings,
                            icon: const Icon(Icons.battery_saver),
                            label: Text(
                              l10n.permissionGuideOpenBatterySettings,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openAutoStartSettings,
                            icon: const Icon(Icons.power_settings_new),
                            label: Text(
                              l10n.permissionGuideOpenAutostartSettings,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _markPermissionConfigured,
                            icon: const Icon(Icons.check),
                            label: Text(l10n.permissionGuideAllDone),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  static const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
  
  String _guideText = '正在加载权限设置指南...';
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
      final permissionStatus = await platform.invokeMethod('getPermissionStatus');
      
      setState(() {
        _guideText = guideText ?? '无法获取权限设置指南';
        _deviceInfo = deviceInfo ?? '未知设备';
        _permissionStatus = Map<String, dynamic>.from(permissionStatus ?? {});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _guideText = '加载权限设置指南失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openAppDetailsSettings() async {
    try {
      await platform.invokeMethod('openAppDetailsSettings');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开应用设置页面，请按照指南进行设置')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开设置页面失败: $e')),
      );
    }
  }

  Future<void> _openBatteryOptimizationSettings() async {
    try {
      await platform.invokeMethod('openBatteryOptimizationSettings');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开电池优化设置页面')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开电池优化设置失败: $e')),
      );
    }
  }

  Future<void> _openAutoStartSettings() async {
    try {
      await platform.invokeMethod('openAutoStartSettings');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开自启动设置页面')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开自启动设置失败: $e')),
      );
    }
  }

  Future<void> _markPermissionConfigured() async {
    try {
      await platform.invokeMethod('markPermissionConfigured', {'type': 'all'});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('权限设置已标记为完成')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记权限设置失败: $e')),
      );
    }
  }

  Widget _buildPermissionStatusCard() {
    if (_permissionStatus.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '权限状态检查',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatusItem('电池优化白名单', _permissionStatus['battery_optimization'] ?? false),
            _buildStatusItem('自启动权限', _permissionStatus['autostart'] ?? false),
            _buildStatusItem('后台运行权限', _permissionStatus['background'] ?? false),
            _buildStatusItem('实际电池优化状态', _permissionStatus['battery_whitelist_actual'] ?? false),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String title, bool isConfigured) {
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
            isConfigured ? '已配置' : '需要配置',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限设置指南'),
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
                          const Text(
                            '设备信息',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                          const Text(
                            '设置指南',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _guideText,
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
                            label: const Text('打开应用设置页面'),
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
                            label: const Text('打开电池优化设置'),
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
                            label: const Text('打开自启动设置'),
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
                            label: const Text('我已完成所有设置'),
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

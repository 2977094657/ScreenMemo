import 'dart:typed_data';
import 'dart:convert';

/// 应用信息模型
class AppInfo {
  final String packageName;
  final String appName;
  final Uint8List? icon;
  final String version;
  final bool isSystemApp;
  bool isSelected;

  AppInfo({
    required this.packageName,
    required this.appName,
    this.icon,
    required this.version,
    required this.isSystemApp,
    this.isSelected = false,
  });

  /// 从installed_apps包的AppInfo对象创建AppInfo
  factory AppInfo.fromInstalledApp(dynamic app) {
    return AppInfo(
      packageName: app.packageName ?? '',
      appName: app.name ?? '',
      icon: app.icon,
      version: app.versionName ?? '',
      isSystemApp: false, // installed_apps包默认排除系统应用
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'appName': appName,
      'version': version,
      'isSystemApp': isSystemApp,
      'isSelected': isSelected,
      'icon': icon != null ? base64Encode(icon!) : null,
    };
  }

  /// 从JSON创建AppInfo
  factory AppInfo.fromJson(Map<String, dynamic> json) {
    Uint8List? iconData;
    if (json['icon'] != null) {
      try {
        iconData = base64Decode(json['icon']);
      } catch (e) {
        iconData = null;
      }
    }

    return AppInfo(
      packageName: json['packageName'] ?? '',
      appName: json['appName'] ?? '',
      icon: iconData,
      version: json['version'] ?? '',
      isSystemApp: json['isSystemApp'] ?? false,
      isSelected: json['isSelected'] ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppInfo && other.packageName == packageName;
  }

  @override
  int get hashCode => packageName.hashCode;

  @override
  String toString() {
    return 'AppInfo(packageName: $packageName, appName: $appName, isSelected: $isSelected)';
  }
}

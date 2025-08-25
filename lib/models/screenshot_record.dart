/// 截屏记录数据模型
class ScreenshotRecord {
  final int? id;
  final String appPackageName;
  final String appName;
  final String filePath; // 存储绝对路径；兼容旧数据时可能为相对路径
  final DateTime captureTime;
  final int fileSize; // 文件大小（字节）
  final bool isDeleted; // 软删除标记

  const ScreenshotRecord({
    this.id,
    required this.appPackageName,
    required this.appName,
    required this.filePath,
    required this.captureTime,
    required this.fileSize,
    this.isDeleted = false,
  });

  /// 从数据库映射创建实例
  factory ScreenshotRecord.fromMap(Map<String, dynamic> map) {
    return ScreenshotRecord(
      id: map['id'] as int?,
      appPackageName: map['app_package_name'] as String,
      appName: map['app_name'] as String,
      filePath: map['file_path'] as String,
      captureTime: DateTime.fromMillisecondsSinceEpoch(map['capture_time'] as int),
      fileSize: map['file_size'] as int,
      isDeleted: (map['is_deleted'] as int) == 1,
    );
  }

  /// 转换为数据库映射
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'app_package_name': appPackageName,
      'app_name': appName,
      'file_path': filePath,
      'capture_time': captureTime.millisecondsSinceEpoch,
      'file_size': fileSize,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// 创建副本
  ScreenshotRecord copyWith({
    int? id,
    String? appPackageName,
    String? appName,
    String? filePath,
    DateTime? captureTime,
    int? fileSize,
    bool? isDeleted,
  }) {
    return ScreenshotRecord(
      id: id ?? this.id,
      appPackageName: appPackageName ?? this.appPackageName,
      appName: appName ?? this.appName,
      filePath: filePath ?? this.filePath,
      captureTime: captureTime ?? this.captureTime,
      fileSize: fileSize ?? this.fileSize,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  String toString() {
    return 'ScreenshotRecord{id: $id, appName: $appName, filePath: $filePath, captureTime: $captureTime}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScreenshotRecord &&
        other.id == id &&
        other.appPackageName == appPackageName &&
        other.appName == appName &&
        other.filePath == filePath &&
        other.captureTime == captureTime &&
        other.fileSize == fileSize &&
        other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        appPackageName.hashCode ^
        appName.hashCode ^
        filePath.hashCode ^
        captureTime.hashCode ^
        fileSize.hashCode ^
        isDeleted.hashCode;
  }
}

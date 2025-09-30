/// 收藏记录数据模型
class FavoriteRecord {
  final int? id;
  final int screenshotId; // 关联的截图ID
  final String appPackageName; // 关联的应用包名
  final DateTime favoriteTime; // 收藏时间
  final String? note; // 备注内容
  
  const FavoriteRecord({
    this.id,
    required this.screenshotId,
    required this.appPackageName,
    required this.favoriteTime,
    this.note,
  });
  
  /// 从数据库映射创建实例
  factory FavoriteRecord.fromMap(Map<String, dynamic> map) {
    return FavoriteRecord(
      id: map['id'] as int?,
      screenshotId: map['screenshot_id'] as int,
      appPackageName: map['app_package_name'] as String,
      favoriteTime: DateTime.fromMillisecondsSinceEpoch(map['favorite_time'] as int),
      note: map['note'] as String?,
    );
  }
  
  /// 转换为数据库映射
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'screenshot_id': screenshotId,
      'app_package_name': appPackageName,
      'favorite_time': favoriteTime.millisecondsSinceEpoch,
      'note': note,
    };
  }
  
  /// 创建副本
  FavoriteRecord copyWith({
    int? id,
    int? screenshotId,
    String? appPackageName,
    DateTime? favoriteTime,
    String? note,
  }) {
    return FavoriteRecord(
      id: id ?? this.id,
      screenshotId: screenshotId ?? this.screenshotId,
      appPackageName: appPackageName ?? this.appPackageName,
      favoriteTime: favoriteTime ?? this.favoriteTime,
      note: note ?? this.note,
    );
  }
  
  @override
  String toString() {
    return 'FavoriteRecord{id: $id, screenshotId: $screenshotId, appPackageName: $appPackageName, favoriteTime: $favoriteTime, note: $note}';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavoriteRecord &&
        other.id == id &&
        other.screenshotId == screenshotId &&
        other.appPackageName == appPackageName &&
        other.favoriteTime == favoriteTime &&
        other.note == note;
  }
  
  @override
  int get hashCode {
    return id.hashCode ^
        screenshotId.hashCode ^
        appPackageName.hashCode ^
        favoriteTime.hashCode ^
        (note?.hashCode ?? 0);
  }
}


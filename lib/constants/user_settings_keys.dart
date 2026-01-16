/// 全局设置持久化键常量，统一跨 Flutter 与原生的访问命名。
class UserSettingKeys {
  UserSettingKeys._();

  // 显示与列表
  static const String displayMode = 'display_mode';
  static const String sortMode = 'sort_mode';
  static const String privacyModeEnabled = 'privacy_mode_enabled';

  // 截屏基础配置
  static const String screenshotInterval = 'screenshot_interval';
  static const String screenshotEnabled = 'screenshot_enabled';
  static const String imageFormat = 'image_format';
  static const String imageQuality = 'image_quality';
  static const String useTargetSize = 'use_target_size';
  static const String targetSizeKb = 'target_size_kb';
  static const String screenshotExpireEnabled = 'screenshot_expire_enabled';
  static const String screenshotExpireDays = 'screenshot_expire_days';

  // 时间段总结（Segment）与 AI 请求限制
  static const String segmentSampleIntervalSec = 'segment_sample_interval_sec';
  static const String segmentDurationSec = 'segment_duration_sec';
  static const String aiMinRequestIntervalSec = 'ai_min_request_interval_sec';
  // 动态合并（仅自动合并；强制合并不受限）
  static const String mergeDynamicMaxSpanSec = 'merge_dynamic_max_span_sec';
  static const String mergeDynamicMaxGapSec = 'merge_dynamic_max_gap_sec';

  // 每日总结提醒
  static const String dailyNotifyEnabled = 'daily_notify_enabled';
  static const String dailyNotifyHour = 'daily_notify_hour';
  static const String dailyNotifyMinute = 'daily_notify_minute';
}

/// 兼容旧版 SharedPreferences 中的键名，用于迁移历史数据。
class LegacySettingKeys {
  LegacySettingKeys._();

  static const List<String> screenshotInterval = <String>[
    'timed_screenshot_interval',
    'flutter.screenshot_interval',
  ];
}


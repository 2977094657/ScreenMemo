/// 全局设置持久化键常量，统一跨 Flutter 与原生的访问命名。
class UserSettingKeys {
  UserSettingKeys._();

  // 显示与列表
  static const String displayMode = 'display_mode';
  static const String sortMode = 'sort_mode';
  static const String privacyModeEnabled = 'privacy_mode_enabled';
  static const String bottomNavigationItems = 'bottom_navigation_items';

  // 截屏基础配置
  static const String screenshotInterval = 'screenshot_interval';
  static const String screenshotEnabled = 'screenshot_enabled';
  static const String autoAddNewAppsToCapture = 'auto_add_new_apps_to_capture';
  static const String windowScreenshotApiEnabled =
      'window_screenshot_api_enabled';
  static const String screenshotDedupeMode = 'screenshot_dedupe_mode';
  static const String imageFormat = 'image_format';
  static const String imageQuality = 'image_quality';
  static const String useTargetSize = 'use_target_size';
  static const String targetSizeKb = 'target_size_kb';
  static const String aiImageSendFormat = 'ai_image_send_format';
  static const String screenshotExpireEnabled = 'screenshot_expire_enabled';
  static const String screenshotExpireDays = 'screenshot_expire_days';
  static const String aiRawResponseCleanupEnabled =
      'ai_raw_response_cleanup_enabled';
  static const String aiRawResponseCleanupDays = 'ai_raw_response_cleanup_days';
  static const String aiRawResponseCleanupLastTs =
      'ai_raw_response_cleanup_last_ts';

  // 时间段总结（Segment）与 AI 请求限制
  static const String segmentSampleIntervalSec = 'segment_sample_interval_sec';
  static const String segmentDurationSec = 'segment_duration_sec';
  static const String aiMinRequestIntervalSec = 'ai_min_request_interval_sec';
  static const String dynamicAutoRepairEnabled = 'dynamic_auto_repair_enabled';
  static const String dynamicRebuildDayConcurrency =
      'dynamic_rebuild_day_concurrency';
  // 动态合并（仅自动合并；强制合并不受限）
  static const String mergeDynamicMaxSpanSec = 'merge_dynamic_max_span_sec';
  static const String mergeDynamicMaxGapSec = 'merge_dynamic_max_gap_sec';

  // 每日总结提醒
  static const String dailyNotifyEnabled = 'daily_notify_enabled';
  static const String dailyNotifyHour = 'daily_notify_hour';
  static const String dailyNotifyMinute = 'daily_notify_minute';

  // 动态页 UI
  static const String dynamicEntryLogIconEnabled =
      'dynamic_entry_log_icon_enabled';

  // 日志管理
  static const String logRetentionDays = 'log_retention_days';

  // 百度网盘自动云备份
  static const String cloudBackupEnabled = 'cloud_backup_enabled';
  static const String cloudBackupFrequencyDays = 'cloud_backup_frequency_days';
  static const String cloudBackupAllowMobileData =
      'cloud_backup_allow_mobile_data';
  static const String cloudBackupKeepLatestCount =
      'cloud_backup_keep_latest_count';
  static const String cloudBackupBaiduAppKey = 'cloud_backup_baidu_app_key';
  static const String cloudBackupBaiduSecretKey =
      'cloud_backup_baidu_secret_key';
  static const String cloudBackupBaiduAuthorizationCode =
      'cloud_backup_baidu_authorization_code';
  static const String cloudBackupBaiduAccessToken =
      'cloud_backup_baidu_access_token';
  static const String cloudBackupBaiduRefreshToken =
      'cloud_backup_baidu_refresh_token';
  static const String cloudBackupBaiduTokenExpiresAt =
      'cloud_backup_baidu_token_expires_at';
  static const String cloudBackupLastSuccessAt = 'cloud_backup_last_success_at';
  static const String cloudBackupLastAttemptAt = 'cloud_backup_last_attempt_at';
  static const String cloudBackupLastStatus = 'cloud_backup_last_status';
  static const String cloudBackupDeviceId = 'cloud_backup_device_id';
  static const String cloudBackupProgressStage = 'cloud_backup_progress_stage';
  static const String cloudBackupProgressPercent =
      'cloud_backup_progress_percent';
  static const String cloudBackupProgressDetail =
      'cloud_backup_progress_detail';
  static const String cloudBackupProgressUpdatedAt =
      'cloud_backup_progress_updated_at';
  static const String cloudBackupProgressBytesDone =
      'cloud_backup_progress_bytes_done';
  static const String cloudBackupProgressBytesTotal =
      'cloud_backup_progress_bytes_total';
  static const String cloudBackupProgressActive =
      'cloud_backup_progress_active';

  // 自动更新
  static const String autoUpdateEnabled = 'auto_update_enabled';
  static const String autoUpdateLastCheckMs = 'auto_update_last_check_ms';
  static const String autoUpdateIgnoredVersion = 'auto_update_ignored_version';
}

/// 兼容旧版 SharedPreferences 中的键名，用于迁移历史数据。
class LegacySettingKeys {
  LegacySettingKeys._();

  static const List<String> screenshotInterval = <String>[
    'timed_screenshot_interval',
    'flutter.screenshot_interval',
  ];
}

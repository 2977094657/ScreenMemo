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
  static const String embeddingMaxRequestMb = 'embedding_max_request_mb';

  // 多模态检索（pHash/向量）
  // 说明：pHash/关键帧方案已移除，目前仅保留“按时间间隔抽样向量化”。

  // Embedding 调试页（仅用于 UI 记忆，不影响主流程）
  static const String embeddingDebugApiKey = 'embedding_debug_api_key';
  static const String embeddingDebugBaseUrl = 'embedding_debug_base_url';
  static const String embeddingDebugModel = 'embedding_debug_model';
  static const String embeddingDebugDimensions = 'embedding_debug_dimensions';
  static const String embeddingDebugLatestCount = 'embedding_debug_latest_count';
  static const String embeddingDebugSegmentId = 'embedding_debug_segment_id';
  static const String embeddingDebugEmbeddingBatchSize = 'embedding_debug_embedding_batch_size';
  static const String embeddingDebugEmbeddingConcurrency = 'embedding_debug_embedding_concurrency';
  static const String embeddingDebugEmbeddingMaxImagesPerRequest = 'embedding_debug_embedding_max_images_per_request';
  static const String embeddingDebugEmbeddingIntervalSeconds = 'embedding_debug_embedding_interval_seconds';
  static const String embeddingDebugTryMultiImageRequest = 'embedding_debug_try_multi_image_request';
  static const String embeddingDebugSemanticCandidateLimit = 'embedding_debug_semantic_candidate_limit';

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



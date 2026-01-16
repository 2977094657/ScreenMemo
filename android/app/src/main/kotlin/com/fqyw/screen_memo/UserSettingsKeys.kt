package com.fqyw.screen_memo

object UserSettingsKeysNative {
    const val DISPLAY_MODE = "display_mode"
    const val SORT_MODE = "sort_mode"
    const val PRIVACY_MODE_ENABLED = "privacy_mode_enabled"
    const val SCREENSHOT_INTERVAL = "screenshot_interval"
    const val SCREENSHOT_ENABLED = "screenshot_enabled"
    const val IMAGE_FORMAT = "image_format"
    const val IMAGE_QUALITY = "image_quality"
    const val USE_TARGET_SIZE = "use_target_size"
    const val TARGET_SIZE_KB = "target_size_kb"
    const val SCREENSHOT_EXPIRE_ENABLED = "screenshot_expire_enabled"
    const val SCREENSHOT_EXPIRE_DAYS = "screenshot_expire_days"
    const val SEGMENT_SAMPLE_INTERVAL_SEC = "segment_sample_interval_sec"
    const val SEGMENT_DURATION_SEC = "segment_duration_sec"
    const val AI_MIN_REQUEST_INTERVAL_SEC = "ai_min_request_interval_sec"
    // 动态合并（仅自动合并；强制合并不受限）
    const val MERGE_DYNAMIC_MAX_SPAN_SEC = "merge_dynamic_max_span_sec"
    const val MERGE_DYNAMIC_MAX_GAP_SEC = "merge_dynamic_max_gap_sec"
    const val DAILY_NOTIFY_ENABLED = "daily_notify_enabled"
    const val DAILY_NOTIFY_HOUR = "daily_notify_hour"
    const val DAILY_NOTIFY_MINUTE = "daily_notify_minute"
}

object LegacySettingKeysNative {
    val SCREENSHOT_INTERVAL = listOf(
        "timed_screenshot_interval",
        "flutter.screenshot_interval"
    )
}



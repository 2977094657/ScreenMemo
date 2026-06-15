package com.fqyw.screen_memo.settings
object UserSettingsKeysNative {
    const val DISPLAY_MODE = "display_mode"
    const val SORT_MODE = "sort_mode"
    const val PRIVACY_MODE_ENABLED = "privacy_mode_enabled"
    const val SCREENSHOT_INTERVAL = "screenshot_interval"
    const val SCREENSHOT_ENABLED = "screenshot_enabled"
    const val AUTO_ADD_NEW_APPS_TO_CAPTURE = "auto_add_new_apps_to_capture"
    const val WINDOW_SCREENSHOT_API_ENABLED = "window_screenshot_api_enabled"
    const val SCREENSHOT_DEDUPE_MODE = "screenshot_dedupe_mode"
    const val IMAGE_FORMAT = "image_format"
    const val IMAGE_QUALITY = "image_quality"
    const val USE_TARGET_SIZE = "use_target_size"
    const val TARGET_SIZE_KB = "target_size_kb"
    const val AI_IMAGE_SEND_FORMAT = "ai_image_send_format"
    const val SCREENSHOT_EXPIRE_ENABLED = "screenshot_expire_enabled"
    const val SCREENSHOT_EXPIRE_DAYS = "screenshot_expire_days"
    const val SEGMENT_SAMPLE_INTERVAL_SEC = "segment_sample_interval_sec"
    const val SEGMENT_DURATION_SEC = "segment_duration_sec"
    const val AI_MIN_REQUEST_INTERVAL_SEC = "ai_min_request_interval_sec"
    const val DYNAMIC_AUTO_REPAIR_ENABLED = "dynamic_auto_repair_enabled"
    const val DYNAMIC_REBUILD_DAY_CONCURRENCY = "dynamic_rebuild_day_concurrency"
    // 动态合并（仅自动合并；强制合并不受限）
    const val MERGE_DYNAMIC_MAX_SPAN_SEC = "merge_dynamic_max_span_sec"
    const val MERGE_DYNAMIC_MAX_GAP_SEC = "merge_dynamic_max_gap_sec"
    const val MERGE_DYNAMIC_MAX_IMAGES = "merge_dynamic_max_images"
    const val DAILY_NOTIFY_ENABLED = "daily_notify_enabled"
    const val DAILY_NOTIFY_HOUR = "daily_notify_hour"
    const val DAILY_NOTIFY_MINUTE = "daily_notify_minute"
    const val LOG_RETENTION_DAYS = "log_retention_days"
    const val CLOUD_BACKUP_ENABLED = "cloud_backup_enabled"
    const val CLOUD_BACKUP_FREQUENCY_DAYS = "cloud_backup_frequency_days"
    const val CLOUD_BACKUP_ALLOW_MOBILE_DATA = "cloud_backup_allow_mobile_data"
    const val CLOUD_BACKUP_KEEP_LATEST_COUNT = "cloud_backup_keep_latest_count"
    const val CLOUD_BACKUP_BAIDU_APP_KEY = "cloud_backup_baidu_app_key"
    const val CLOUD_BACKUP_BAIDU_SECRET_KEY = "cloud_backup_baidu_secret_key"
    const val CLOUD_BACKUP_BAIDU_AUTHORIZATION_CODE = "cloud_backup_baidu_authorization_code"
    const val CLOUD_BACKUP_BAIDU_ACCESS_TOKEN = "cloud_backup_baidu_access_token"
    const val CLOUD_BACKUP_BAIDU_REFRESH_TOKEN = "cloud_backup_baidu_refresh_token"
    const val CLOUD_BACKUP_BAIDU_TOKEN_EXPIRES_AT = "cloud_backup_baidu_token_expires_at"
    const val CLOUD_BACKUP_LAST_SUCCESS_AT = "cloud_backup_last_success_at"
    const val CLOUD_BACKUP_LAST_ATTEMPT_AT = "cloud_backup_last_attempt_at"
    const val CLOUD_BACKUP_LAST_STATUS = "cloud_backup_last_status"
    const val CLOUD_BACKUP_DEVICE_ID = "cloud_backup_device_id"
    const val CLOUD_BACKUP_PROGRESS_STAGE = "cloud_backup_progress_stage"
    const val CLOUD_BACKUP_PROGRESS_PERCENT = "cloud_backup_progress_percent"
    const val CLOUD_BACKUP_PROGRESS_DETAIL = "cloud_backup_progress_detail"
    const val CLOUD_BACKUP_PROGRESS_UPDATED_AT = "cloud_backup_progress_updated_at"
    const val CLOUD_BACKUP_PROGRESS_BYTES_DONE = "cloud_backup_progress_bytes_done"
    const val CLOUD_BACKUP_PROGRESS_BYTES_TOTAL = "cloud_backup_progress_bytes_total"
    const val CLOUD_BACKUP_PROGRESS_ACTIVE = "cloud_backup_progress_active"
}

object LegacySettingKeysNative {
    val SCREENSHOT_INTERVAL = listOf(
        "timed_screenshot_interval",
        "flutter.screenshot_interval"
    )
}



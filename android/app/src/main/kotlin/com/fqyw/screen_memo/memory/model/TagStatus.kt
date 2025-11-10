package com.fqyw.screen_memo.memory.model

/**
 * 标签状态。
 * - PENDING：待确认，需要更多证据或用户手动确认。
 * - CONFIRMED：已确认，可直接用于用户画像展示。
 */
enum class TagStatus(val storageValue: String) {
    PENDING("pending"),
    CONFIRMED("confirmed");

    companion object {
        fun fromStorageValue(value: String?): TagStatus {
            if (value.isNullOrBlank()) return PENDING
            return values().firstOrNull { it.storageValue == value } ?: PENDING
        }
    }
}


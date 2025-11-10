package com.fqyw.screen_memo.memory.model

/**
 * 用户标签领域模型，聚合与用户相关的画像信息。
 */
data class UserTag(
    val id: Long,
    val tagKey: String,
    val label: String,
    val level1: String,
    val level2: String,
    val level3: String,
    val level4: String,
    val fullPath: String,
    val category: TagCategory,
    val status: TagStatus,
    val occurrences: Int,
    val confidence: Double,
    val firstSeenAt: Long,
    val lastSeenAt: Long,
    val autoConfirmedAt: Long? = null,
    val manualConfirmedAt: Long? = null,
    val evidences: List<TagEvidence> = emptyList(),
    val evidenceTotalCount: Int = evidences.size
) {
    val isConfirmed: Boolean
        get() = status == TagStatus.CONFIRMED
}


package com.fqyw.screen_memo.memory.model

/**
 * 初始化或批处理进度状态。
 */
sealed class MemoryProgressState {
    data object Idle : MemoryProgressState()

    data class Running(
        val processedCount: Int,
        val totalCount: Int,
        val progress: Float,
        val currentEventId: Long?,
        val currentEventExternalId: String?,
        val currentEventType: String?,
        val newlyDiscoveredTags: List<String>
    ) : MemoryProgressState()

    data class Completed(
        val totalCount: Int,
        val durationMillis: Long
    ) : MemoryProgressState()

    data class Failed(
        val processedCount: Int,
        val totalCount: Int,
        val errorMessage: String,
        val rawResponse: String? = null,
        val failureCode: String? = null,
        val failedEventExternalId: String? = null
    ) : MemoryProgressState()
}


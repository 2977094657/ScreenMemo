package com.fqyw.screen_memo.memory.processor

/**
 * LLM 提取结果，包含标签候选及最新的用户整体描述。
 */
data class UserSignalExtractionResult(
    val candidates: List<TagCandidate>,
    val personaSummary: String?,
    val rawResponse: String? = null,
    val isMalformed: Boolean = false
)



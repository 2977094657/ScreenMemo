package com.fqyw.screen_memo.memory.processor

import com.fqyw.screen_memo.memory.model.PersonaProfilePatch

/**
 * LLM 提取结果，包含标签候选及最新的用户整体描述。
 */
data class UserSignalExtractionResult(
    val candidates: List<TagCandidate>,
    val personaProfilePatch: PersonaProfilePatch?,
    val personaSummaryFallback: String?,
    val rawResponse: String? = null,
    val isMalformed: Boolean = false,
    val graphEntities: List<GraphEntityCandidate> = emptyList(),
    val graphEdges: List<GraphEdgeCandidate> = emptyList(),
    val graphEdgeClosures: List<GraphEdgeClosureCandidate> = emptyList()
)


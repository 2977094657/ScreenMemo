package com.fqyw.screen_memo.memory.processor

/**
 * Knowledge graph entity candidate extracted from a single event.
 *
 * entityKey should be globally stable, e.g. "person:user", "org:OpenAI", "project:ScreenMemo".
 */
data class GraphEntityCandidate(
    val entityKey: String,
    val type: String,
    val name: String,
    val aliases: List<String> = emptyList(),
    val metadata: Map<String, String> = emptyMap(),
    val confidence: Double = 0.6
)

/**
 * Knowledge graph edge candidate extracted from a single event.
 *
 * Exactly one of objectKey / objectValue should be provided.
 * isState=true indicates this predicate represents a state that should be updated over time (close previous active edges).
 */
data class GraphEdgeCandidate(
    val subjectKey: String,
    val predicate: String,
    val objectKey: String? = null,
    val objectValue: String? = null,
    val qualifiers: Map<String, String> = emptyMap(),
    val isState: Boolean? = null,
    val confidence: Double = 0.6,
    val evidenceExcerpt: String? = null
)

/**
 * A request to close existing active edges at the current event timestamp.
 */
data class GraphEdgeClosureCandidate(
    val subjectKey: String,
    val predicate: String,
    val objectKey: String? = null,
    val objectValue: String? = null,
    val qualifiers: Map<String, String> = emptyMap(),
    val reason: String? = null
)


package com.fqyw.screen_memo.memory.processor

import com.fqyw.screen_memo.memory.model.TagCategory

data class TagCandidate(
    val tagKey: String,
    val label: String,
    val category: TagCategory,
    val hierarchy: TagHierarchy,
    val inference: String?,
    val confidence: Double,
    val evidence: String,
    val notes: String? = null,
    val autoConfirmThreshold: Int = DEFAULT_AUTO_CONFIRM_THRESHOLD,
    val shouldOverrideLabel: Boolean = false,
    val forceOverrideEvidence: Boolean = false,
    val metadata: Map<String, String> = emptyMap()
) {
    companion object {
        const val DEFAULT_AUTO_CONFIRM_THRESHOLD = 3
    }
}

data class TagHierarchy(
    val level1: String,
    val level2: String,
    val level3: String,
    val level4: String
) {
    val fullPath: String = listOf(level1, level2, level3, level4)
        .joinToString(" / ") { it.trim() }
        .trim()

    fun isValid(): Boolean {
        return level1.isNotBlank() && level2.isNotBlank() && level3.isNotBlank() && level4.isNotBlank()
    }
}


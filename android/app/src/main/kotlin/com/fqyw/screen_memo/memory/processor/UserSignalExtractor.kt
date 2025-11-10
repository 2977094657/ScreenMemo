package com.fqyw.screen_memo.memory.processor

import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.service.ExtractionContext

/**
 * 将原始事件解析为用户相关标签候选项的抽象接口。
 */
interface UserSignalExtractor {
    suspend fun extractSignals(
        event: UserEvent,
        context: ExtractionContext?,
        existingTagPaths: List<String>,
        currentPersonaSummary: String
    ): UserSignalExtractionResult
}


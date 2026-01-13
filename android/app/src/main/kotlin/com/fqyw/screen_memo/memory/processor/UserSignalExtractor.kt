package com.fqyw.screen_memo.memory.processor

import com.fqyw.screen_memo.memory.model.PersonaProfile
import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.service.ExtractionContext

/**
 * 将原始事件解析为用户画像补丁与知识图谱增量的抽象接口。
 */
interface UserSignalExtractor {
    suspend fun extractSignals(
        event: UserEvent,
        context: ExtractionContext?,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult
}


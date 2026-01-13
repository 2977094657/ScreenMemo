package com.fqyw.screen_memo.memory.model

/**
 * 记忆系统对外暴露的汇总快照。
 *
 * @param recentEvents 最近处理的用户相关事件
 * @param lastUpdatedAt 快照最新更新时间
 */
data class MemorySnapshot(
    val recentEvents: List<MemoryEventSummary> = emptyList(),
    val recentEventTotalCount: Int = recentEvents.size,
    val lastUpdatedAt: Long = System.currentTimeMillis(),
    val personaSummary: String = "",
    val personaProfile: PersonaProfile = PersonaProfile.default()
)

/**
 * 提供给 UI 展示的事件摘要。
 */
data class MemoryEventSummary(
    val id: Long,
    val externalId: String?,
    val occurredAt: Long,
    val type: String,
    val source: String,
    val content: String,
    val containsUserContext: Boolean
)

package com.fqyw.screen_memo.memory.model

/**
 * 记忆系统对外暴露的汇总快照。
 *
 * @param pendingTags 当前待确认标签列表
 * @param confirmedTags 当前已确认标签列表
 * @param recentEvents 最近处理的用户相关事件
 * @param lastUpdatedAt 快照最新更新时间
 */
data class MemorySnapshot(
    val pendingTags: List<UserTag> = emptyList(),
    val confirmedTags: List<UserTag> = emptyList(),
    val recentEvents: List<MemoryEventSummary> = emptyList(),
    val pendingTotalCount: Int = pendingTags.size,
    val confirmedTotalCount: Int = confirmedTags.size,
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
    val containsUserContext: Boolean,
    val relatedTagIds: List<Long> = emptyList()
)


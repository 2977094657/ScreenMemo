package com.fqyw.screen_memo.memory.model

/**
 * 标签证据领域模型，记录触发标签的原事件片段及其置信度。
 *
 * @param id 本地数据库主键
 * @param tagId 对应的标签 ID
 * @param eventId 触发该证据的事件 ID
 * @param excerpt 文本证据或关键片段
 * @param confidence 系统识别置信度（0.0 ~ 1.0）
 * @param createdAt 创建时间
 * @param lastModifiedAt 最近一次修改时间
 * @param isUserEdited 是否经过用户手动修改
 * @param notes 用户补充说明
 */
data class TagEvidence(
    val id: Long,
    val tagId: Long,
    val eventId: Long,
    val excerpt: String,
    val confidence: Double,
    val createdAt: Long,
    val lastModifiedAt: Long,
    val isUserEdited: Boolean,
    val notes: String? = null
)


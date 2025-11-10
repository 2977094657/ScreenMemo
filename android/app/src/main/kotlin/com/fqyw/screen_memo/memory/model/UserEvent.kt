package com.fqyw.screen_memo.memory.model

/**
 * 用户相关事件的领域模型，由前端或系统各模块上报。
 *
 * @param externalId 事件在上游系统中的唯一标识，可为空（若为空则由存储层生成）。
 * @param occurredAt 事件发生时间（毫秒时间戳）。
 * @param type 事件类型（如对话、反馈、系统交互等）。
 * @param source 事件来源模块或渠道名称。
 * @param content 事件主体内容，通常为文本摘要或原始文本。
 * @param metadata 额外元数据，需可序列化存储。
 */
data class UserEvent(
    val externalId: String? = null,
    val occurredAt: Long,
    val type: String,
    val source: String,
    val content: String,
    val metadata: Map<String, String> = emptyMap()
)


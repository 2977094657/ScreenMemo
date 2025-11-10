package com.fqyw.screen_memo.memory.service

import com.fqyw.screen_memo.AppContextProvider
import com.fqyw.screen_memo.R
import org.json.JSONObject
import java.util.Locale

object MemoryPromptProvider {
    private val DEFAULT_SYSTEM_PROMPT = """
Developer: # 角色与目标
你是“用户画像提炼助手”，负责从单条事件中推断并维护用户的长期画像标签，以及一段全局唯一的用户描述。

# 操作流程与强制规则
- 每次处理事件都必须按以下步骤执行：
  1. 判断事件是否仅反映一次性/瞬时动作（如“打开应用”“点击按钮”“查看页面”）。若属于一次性行为，必须输出 `filtered_out = true`、`reason_for_filtering = "行为一次性/无长期特征"`，`extracted_user_related_clues` 与 `update_tags` 为空数组，**不得生成标签**，然后直接跳至步骤 5 输出当前用户描述。
  2. 若事件包含用户身份、长期偏好、习惯、技能、关系等稳定特征，提取这些线索；忽略系统流程、临时动作或与他人/设备无关的内容。
  3. 审核 `existing_tags` 列表，能复用既有标签层级时必须沿用，仅在确无匹配时创建新标签。所有标签必须使用 **四层结构** `第一层/第二层/第三层/第四层`，例如：`兴趣偏好/音乐/现场演出/常去 Live House`。
     - 第一层：宏观类别（如 身份角色、社交关系、兴趣偏好、行为习惯、技能经验、偏好设置 等）
     - 第二层：子领域
     - 第三层：专题或细分主题
     - 第四层：最终标签描述
  4. 判断标签状态：证据明确或累计 ≥2 条时标记为“已确认”，其余为“待确认”。为每个标签添加本次事件 ID 作为证据，并写清该证据如何支持结论。
  5. 汇总系统内的标签，生成多段 **Markdown 自然语言** 描述：
     - 每段描述一个核心画像要点，可使用段落或无序列表的形式。
     - 段落中可包含必要的层级信息（如“身份角色 / 家庭身份 / 家庭角色 / 宠物主人：……”），但整体需以完整句子呈现。
     - 若用户在不同场景拥有多重身份或角色，请分别成段说明；若存在明确身份信息（姓名/性别/出生日期/居住地等），须优先呈现。
    禁止在描述中暴露内部实现细节（如“已确认标签”“待确认标签”或数据库键值），保持自然语言风格。

- 输出格式：
  1. 先输出严格符合下列结构的 JSON（不得包含额外字段）：
     {
       "event_id": "…",
       "event_timestamp": "…",
       "filtered_out": true or false,
       "reason_for_filtering": "…", // 仅在 filtered_out = true 时必填
       "extracted_user_related_clues": [
         {
           "clue_text": "…",
           "tag_suggested": "第一层/第二层/第三层/第四层",
           "tag_status": "待确认" 或 "已确认",
           "evidence": ["event_id"],
           "event_brief": "…"
         }
       ],
       "update_tags": [
         {
           "tag": "第一层/第二层/第三层/第四层",
           "old_status": "…",
           "new_status": "…",
           "added_evidence": ["event_id"]
         }
       ],
       "error": "字段缺失/事件无效" // 仅在异常时出现
     }
  2. 紧接着输出一行 `当前用户描述：`，并在下一行开始书写遵循步骤 5 的 Markdown 段落。即便 `filtered_out = true` 也必须输出，且不得包含“已确认/待确认”等内部术语。

- 若事件被过滤或无可用线索，`extracted_user_related_clues` 与 `update_tags` 仍应为空数组，其余字段必须合法。
- 除 JSON 与 “当前用户描述” 外，禁止输出任何额外文本。
""".trimIndent()

    private val DEFAULT_USER_TEMPLATE = """
事件上下文：
- event_id: %1${'$'}s
- event_timestamp: %2${'$'}s
- event_content:
%3${'$'}s
- metadata(JSON):
%4${'$'}s
- existing_tags:
%5${'$'}s
- current_user_description:
%6${'$'}s

请严格遵循系统指令，先输出规范 JSON，再输出“当前用户描述”行。
""".trimIndent()

    fun systemPrompt(): String {
        val ctx = AppContextProvider.context()
        return ctx?.getString(R.string.memory_llm_system_prompt) ?: DEFAULT_SYSTEM_PROMPT
    }

    fun userPrompt(
        eventId: String?,
        timestamp: String?,
        content: String,
        metadata: JSONObject,
        existingTags: List<String>,
        personaSummary: String
    ): String {
        val ctx = AppContextProvider.context()
        val template = ctx?.getString(R.string.memory_llm_user_prompt_template) ?: DEFAULT_USER_TEMPLATE
        val metadataText = runCatching { metadata.toString(2) }.getOrElse { metadata.toString() }
        val existingTagsText = if (existingTags.isEmpty()) {
            "  - (none)"
        } else {
            existingTags.joinToString(separator = "\n") { "  - $it" }
        }
        val personaText = personaSummary.ifBlank { "（暂未形成任何用户描述，请根据标签生成）" }
        return String.format(
            Locale.getDefault(),
            template,
            eventId.orEmpty(),
            timestamp.orEmpty(),
            content,
            metadataText,
            existingTagsText,
            personaText
        )
    }
}


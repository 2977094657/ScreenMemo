# 对话上下文系统（Codex-style）

本项目的“对话上下文”目标：让模型在长对话中仍能保持连续性，避免因为仅保留尾部历史而出现“忘记/反复澄清/工具循环”。

## 现状问题（为什么看起来在循环）

在未启用压缩/记忆时，模型每次请求只会携带有限的历史：
- UI/本地持久化只保存 `ai_messages` 的尾部（默认 N 条），更早消息会被覆盖。
- 上行 prompt 还会再按 token 预算裁剪（避免超窗/拖慢工具循环）。

结果就是：对话一旦变长，模型无法“看到”更早的关键约束/结论/已尝试的检索参数，表现为重复提问、重复工具调用或“像在原地打转”。

## 设计：三层存储 + 一层组装

1) **UI 历史（轻量）**  
表：`ai_messages`  
用途：只用于 UI 渲染与快速加载（尾部 N 条）。

2) **全量转写（append-only）**  
表：`ai_messages_full`  
用途：用于长对话的安全压缩与恢复；不受 UI 尾部限制。

3) **压缩记忆（可注入）**  
表：`ai_conversations` 字段：
- `summary` / `summary_tokens`：滚动摘要（可复用、面向后续对话）。
- `tool_memory_json`：工具调用摘要（避免重复、保留“已查过什么”）。
- `last_prompt_tokens`：最近一次 prompt 的粗估 token 用量（用于可观测性）。

3.5) **原子记忆（事实/规则，可注入）**  
表：`ai_atomic_memories`  
用途：以“原子事实/规则块”形式持久化用户偏好/约束等高密度信息；可在 UI 中关闭/调预算；可选开启自动抽取（会触发后台 AI 调用）。

4) **上下文组装（每次请求）**
- System：语言策略/工具使用规则
- System：`<conversation_context>...</conversation_context>`（摘要 + 工具摘要）
- System：`<atomic_memory>...</atomic_memory>`（原子事实/规则块；可在 UI 中关闭/调预算；可选自动抽取写入）
- System：`<working_memory>...</working_memory>`（MemOS 工作记忆：persona + 时序图谱相关边；可在 UI 中关闭/调预算）
- History：从 `ai_messages_full` 取最近 tail，并按预算裁剪
- User：本次输入

## 与 Codex 工程的对应关系

Codex（CLI，开源项目）在长线程中使用“粗估 token + 压缩任务”控制上下文（以下为 Codex 仓库中的路径）：
- 压缩入口：`codex-rs/core/src/compact.rs`
- token 粗估/截断：`codex-rs/core/src/truncate.rs`
- 历史与 token 估算：`codex-rs/core/src/context_manager/history.rs`

本项目复用了相同的核心思路：**不依赖 tokenizer 的 bytes/4 粗估**，并在超预算或超长时触发 compaction。

## 代码落点（本仓库）

- 上下文服务：`lib/services/chat_context_service.dart`
  - `seedFromChatHistoryIfEmpty`：老数据兜底（从尾部历史补齐全量转写起点）
  - `loadRecentMessagesForPrompt`：从 `ai_messages_full` 取 tail 作为 prompt history
  - `appendCompletedTurn` / `mergeToolDigests`：写入全量转写 + 工具摘要
  - `scheduleAutoCompact` / `compactNow`：触发压缩并更新 `summary`

- Chat 组装与持久化：`lib/services/ai_chat_service.dart`
  - 请求前：注入 `buildSystemContextMessage()`；记录 prompt tokens
  - 请求前：注入原子记忆 `<atomic_memory>...</atomic_memory>`（`AtomicMemoryService.buildAtomicMemoryContextMessage()`）
  - 请求前：注入 MemOS `working_memory`（`MemoryBridgeService.buildWorkingMemory()` -> `<working_memory>...</working_memory>`）
  - 请求后：写入 `ai_messages_full`；合并工具摘要；调度自动压缩
  - 请求后：可选自动抽取原子记忆（写入 `ai_atomic_memories`）

- 数据库 schema：`lib/services/screenshot_database_ai.dart`
  - `ai_conversations`：summary/tool-memory/prompt tokens 字段
  - `ai_messages_full`：全量转写表
  - `ai_atomic_memories`：原子事实/规则表（含 FTS）
  - `ai_context_events`：压缩诊断事件（rollout log）

- 原子记忆服务：`lib/services/atomic_memory_service.dart`
  - LLM 抽取（可选）+ SQLite/FTS 检索 + `<atomic_memory>` 注入

## 可观测与调试

- UI 入口：`lib/pages/ai_settings_page.dart` AppBar -> “对话上下文”
- 底部面板：`lib/widgets/chat_context_sheet.dart`
  - 查看 summary / tool memory / prompt tokens / compaction 计数
  - 可配置工作记忆注入开关与预算（token/edge limit）
  - 可配置原子记忆注入开关与预算（token/items），以及“自动抽取写入”开关
  - 支持手动 `Compact now` / `Clear memory` / `Clear chat`

## 约束与建议

- token 估算是**粗略下界**，目标是避免超窗与工具循环，并非精确计费统计。
- 多次压缩可能降低准确性（与 Codex 的 warning 一致）：当任务跨域过大，建议新建会话。

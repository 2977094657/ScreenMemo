# Nocturne Memory · System Prompts（ScreenMemo 版）

本文件用于记录“推荐系统提示词”，让模型理解 ScreenMemo 的 Nocturne 风格记忆（URI 图）如何运转。

说明：
- Nocturne 原项目的提示词以“多轮会话”为核心；ScreenMemo 里既有对话（chat），也有“单次提取/重建”（从动态截图抽取长期记忆）。
- 为了避免 token 过重，ScreenMemo 实装的是**精简版**提示词（见代码：`lib/services/nocturne_memory_prompts.dart`）。

---

## 1) 对话（chat）推荐 System Prompt（精简版）

建议作为额外 System Message 注入（而不是覆盖主系统提示词），核心目标：
- 告诉模型：长期记忆通过 `read_memory/search_memory/create_memory/update_memory/delete_memory/add_alias` 访问；
- 新会话第一轮优先 `read_memory("system://boot")`；
- 明确 alias 与重复的区别；
- 写入前检索、更新前先读、发现重复要合并提炼。

对应实现：`lib/services/nocturne_memory_prompts.dart` → `NocturneMemoryPrompts.chatSystemAddon(...)`。

---

## 2) 单次提取（动态截图 → 长期记忆）System Prompt（精简版）

用途：给“一键重建”/“单次提取”这类 pipeline 使用。

关键差异：
- 这是**单次提取**，不是对话；模型只能输出紧凑动作格式（例如 `[{update_memory,core://my_user/interests,- 示例}]`），由系统执行写入；
- 空输出只能是 `[]`，不再接受 `NO_ACTIONS` 或 JSON 包装；
- 需要**强制去重**：我们会提供“当前记忆快照”，模型必须避免重复写入；
- 每次最多输入 10 张图，最多输出 5 条 actions。

对应实现：`lib/services/nocturne_memory_prompts.dart` → `NocturneMemoryPrompts.rebuildSystemPrompt(...)`。

---

## 3) 关于“重复记忆”的处理策略（ScreenMemo）

Nocturne 的思路（提示词层面）：
- **写入前检索**（`search_memory` / `read_memory`），避免创建相似条目；
- **alias 不等于重复**：同一内容多路径访问是正常的；
- 真正重复是“不同节点/不同路径下的相似内容”，应当合并提炼，而非简单拼接。

ScreenMemo 在“单次提取/重建”场景的针对性措施（实现层面）：
- **提供记忆快照**给模型，用于语义去重；
- 写入时对 `append` 的 bullet 行做**确定性去重**（已有行则跳过），避免同一句重复追加。
- 当新 bullet 是 `字段: 值` 形式时，系统会优先把它当成“当前状态字段”去整理：
  - 新值会成为当前记录；
  - 旧值会被保留到 `历史记录(字段)`；
  - 系统会补上 `更新说明(字段)` 与 `更新证据(字段)`，说明为什么这次的新值更可信。
- AI 动作还会先进入一层**记忆信号(candidate/active/archived)**：
  - 单次、短时、弱证据先保留为 candidate，不直接进入长期记忆；
  - 跨时间重复出现或具有强主动证据时，才升级为 active；
  - 长期不再出现的节点会转 archived，而不是简单累加或直接删除。

---

## 4) 关于“时序/生命周期”的推荐写入惯例（ScreenMemo）

当同一对象会经历状态变化（例如“杯子 → 打碎”）时，推荐采用“对象 + 事件子节点”的结构：

- 选一个稳定的对象主节点（canonical），例如：`core://my_user/other/items/cup`
  - 主节点维护：对象可检索名称/关键词（建议包含中文名）、稳定属性、以及“当前状态（含日期）”。
  - 当状态变化时，模型只需要输出新的当前值；系统会自动保留旧值历史，而不是直接抹掉。
- 每次变化写入事件子节点：`<object>/events/<yyyy-mm-dd>_<slug>`
  - 若 `events` 节点不存在，先创建 `events` 节点（content 可写“事件目录/索引”）。
  - 事件节点记录：发生了什么、结果是什么、时间是什么。
- 若同一对象需要在多个目录出现，用 `add_alias` 增加入口（不要复制一份内容到多个节点）。
- 对 `people` / `places` / `organizations` / `interests` / `projects` / `goals` / `habits`，更推荐写具体子节点，而不是长期把根节点当成杂项列表。

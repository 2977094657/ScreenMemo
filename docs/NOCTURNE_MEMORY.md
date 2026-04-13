# Nocturne 风格 URI 图谱记忆（ScreenMemo 内置）

本项目在主库中引入了与根目录 `nocturne_memory` 同构的“URI 图谱记忆”数据模型，用于给内置 AI 提供**可读写、可组织、可别名化**的长期记忆层。

区别仅在“语料”：在 ScreenMemo 中，AI 的主要原始语料来自**动态（segments）里的图片/样本**（结合 `get_images` 视觉查看），再由 AI 决定写入哪些记忆节点。

## 核心概念

- URI：`<domain>://<path>`，例如：
  - `core://agent`
  - `dynamic://2026/03/10`
- 图后端 + 树前端：
  - `nodes`：稳定 UUID（概念实体）
  - `memories`：节点的内容版本（append-only；同一节点仅 1 条 active）
  - `edges`：`parent -> child` 关系（`priority/disclosure` 绑定在 edge 上）
  - `paths`：`domain://path -> edge` 的路由缓存（支持 alias）

## 数据表（SQLite）

主库新增 4 表：`nodes` / `memories` / `edges` / `paths`。

> 说明：使用固定 root UUID `00000000-0000-0000-0000-000000000000` 作为所有顶层 edge 的父节点（避免 SQLite NULL 唯一性陷阱）。

## AI 工具（6 个）

已加入默认工具清单（对话可直接调用）：

- `read_memory(uri)`
  - 特殊系统 URI：`system://boot`、`system://index[/<domain>]`、`system://recent[/N]`
- `create_memory(parent_uri, content, priority, title?, disclosure?)`
  - `title` 限制：`a-z0-9_-`（不允许空格/斜杠/大写）
- `update_memory(uri, old_string?, new_string?, append?, priority?, disclosure?)`
  - patch（`old_string+new_string`）与 append 互斥
- `delete_memory(uri)`：删除某条访问路径（同域递归删除子路径），内容版本保留
- `add_alias(new_uri, target_uri, priority?, disclosure?)`：别名路径（非复制），并级联映射子树
- `search_memory(query, domain?, limit?)`：子字符串匹配（非语义检索）

## 生命周期 / 时序

- `update_memory(..., append=...)` 仍然是 AI 在重建阶段最主要的“追加记忆”方式。
- 从现在开始，重建流程不会把 AI 给出的动作直接无条件写入长期记忆，而是先进入“记忆信号”层：
  - `candidate`：候选信号，表示某条信息被看到过，但证据还不够强
  - `active`：活跃记忆，达到阈值后才正式物化到 Nocturne URI 图
  - `archived`：曾经出现过、但长期未再次出现的记忆，会封存而不是直接删除
- 这套机制对所有根路径生效，而不是只对 `interests` 生效；区别在于不同路径有不同阈值：
  - `preferences` / `identity` 允许较强单次证据更快进入长期记忆
  - `interests` / `people` / `places` / `organizations` / `habits` 等更强调跨时间重复出现
- 同一段时间窗口内的连续截图会先被压成一个 `episode`，避免“高截屏频率把同一次显示过程算成很多次证据”。
- 对同一对象，推荐采用“主节点 + events 子节点”的结构：
  - 主节点保存稳定属性与“当前状态”
  - `.../events/<yyyy-mm-dd>_<slug>` 保存具体事件
- 当同一字段出现新值时，系统不会直接抹掉旧值，而是会：
  - 保留新的“当前值”
  - 自动生成 `更新说明(字段)`，说明为什么新值更适合作为当前记录
  - 自动生成 `更新证据(字段)`，引用本次动态段/截图批次作为证据
  - 自动把旧值整理进 `历史记录(字段)`，方便回看完整时序
- 当对象进入终结状态（如已打碎、已报废、已完成、已卖出），主节点不应删除，而应写入类似：
  - `- 当前状态：已打碎`
  - `- 生命周期状态：已封存(YYYY-MM-DD)`
- 这样后续如果又出现与该对象有关的新信息，仍然可以继续挂回同一主节点，而不是丢失上下文。

## Boot 记忆配置

`system://boot` 的 URI 列表来自 `user_settings` 中的键：

- `nocturne_core_memory_uris`（逗号分隔，例：`core://agent,core://my_user`）

未配置时，会使用默认兜底：
`core://agent,core://my_user,core://agent/my_user`。

## 用动态图片作为语料（推荐流程）

1) 用检索工具找到目标动态（segments）：
   - `search_segments(...)`
   - `get_segment_samples(segment_id, ...)`
2) 需要视觉信息时加载图片：
   - `get_images(filenames=[...])`
3) 从图片中抽取长期记忆并写入：
   - 结构化知识/规则写入 `core://...`
   - 与动态相关的“时间锚点/事件索引”可写入 `dynamic://...`
   - 为关键记忆设置 `disclosure`，提示“在什么情况下该想起它”

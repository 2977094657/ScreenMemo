# Search 数据源接入与可扩展架构建议

本文用于回答两类问题：

1) 目前搜索到底接入了哪些数据源，还有哪些“动态/AI 数据”没有接入；
2) 当数据量上来后，如何用更可扩展的架构把多个数据源统一到一个“快、可分页、可排序、可扩展”的搜索体系里。

---

## 现状：已有的数据源与索引

项目当前主要依赖 SQLite（主库 + 分库分表）与 FTS 做全文检索，相关表大致分为：

### 1) 截图与 OCR（大规模）

- 分库：`output/databases/shards/<pkg>/<year>.db`
- 分表：按月表（`ScreenshotDatabase` 内部命名）
- 检索：OCR FTS（优先 FTS，失败回退 LIKE）

适用：从截图 OCR 文本里找“出现过的文字线索”，是典型的高召回文本检索入口。

### 2) 动态 segments（中等规模）

- 主库：`segments` / `segment_samples` / `segment_results`
- 检索：`segment_results_fts` / `fts_content`

适用：从“动态事件摘要/标签/结构化结果”里找段落事件，再回到证据截图。

### 3) AI 图片元数据（中等规模）

- 主库：`ai_image_meta`（`file_path` 主键，含 `tags_json` / `description` / `nsfw` 等）
- 检索：`ai_image_meta_fts`

适用：OCR 缺失/不准时，用“图片标签/描述”来检索截图。

### 4) 每日/每周/早报/画像文章（小规模）

- 主库：`daily_summaries` / `weekly_summaries` / `morning_insights` / `persona_articles`
- 当前：以读取/列表为主，尚未统一纳入全局搜索（可选接入）。

---

## 现状：UI 搜索页（SearchPage）接入点

- 截图 Tab：优先 OCR 搜索；当 OCR 首批为空时可回退 `ai_image_meta`（tags/description）检索。
- 动态 Tab：基于 `segment_results_fts` 搜索段落摘要/标签。

如果未来要把“每日/每周/编年史”等更多数据源纳入搜索，建议不要继续在 UI 层做“if/else 堆叠”，而是升级为统一的检索服务层（见下文）。

---

## NSFW：从“动态标签”到“全局一致”

NSFW 的信号来源可以分为三类（按优先级从高到低）：

1) **手动标记**：`nsfw_manual_flags`（用户手动强制遮罩）
2) **域名规则**：`nsfw_domain_rules`（用户配置的域名/通配符）
3) **自动识别**：
   - URL 关键字（站点模式）
   - AI 图片标签：`ai_image_meta.nsfw`（例如 tags 含 `NSFW`）

为了让“动态里的 NSFW 标签”能在截图列表/时间线/搜索里一致生效，推荐统一走一个聚合判断入口（例如 `NsfwPreferenceService.shouldMaskCached`），并在列表分页加载后批量预加载缓存，避免逐项 IO/DB 查询造成掉帧。

---

## 可扩展方案：统一 SearchIndex（推荐）

当数据源越来越多，最容易出现的问题是：

- UI 里堆很多查询分支，逻辑分散且难维护；
- 每个数据源自己分页/排序，无法做全局 TopK；
- 多表/多索引查询叠加导致延迟放大。

### 核心思路

在**主库**增加一个统一的“文档索引”：

- `search_docs`：存元信息（doc_type/doc_id/file_path/time/app/nsfw/…）
- `search_docs_fts`：存可检索文本（title/body/tags/…）

每当新数据产生/更新（OCR 完成、segment 产出、ai_image_meta 更新、daily/weekly 生成…），把它们“投喂”到同一个索引里。

### 查询路径

1) 只查一次 FTS：`search_docs_fts MATCH ?`
2) 按 `bm25()` + 时间做排序，拿到 topN `rowid`
3) 再按 `doc_type` 分发去取详情（或直接在 `search_docs` 存必要展示字段）

### 优点

- UI 永远只面对一个统一的分页接口；
- 可以做跨数据源的混排（All Tab）与稳定排序；
- 可以轻松做“只看某 app / 只看某类型 / 排除 NSFW”等过滤；
- 便于后续做“离线向量检索/语义检索”作为补充（另建向量表即可）。

### 维护方式（两种选一）

- **显式 upsert（推荐）**：由 Kotlin 后端服务/Flutter 服务在写入业务表后，调用 `upsertSearchDoc(...)` 同步更新索引。
- **触发器**：为关键表建触发器写索引（实现简单，但跨分库/跨表时会复杂）。

---

## 可选组件/工程化建议

- SQLite FTS5：继续作为主力全文检索（已在项目中使用）。
- `drift`（可选）：在 Flutter 侧用强类型 SQL + isolate 执行查询，降低主线程压力。
- 后台任务：Android 侧可用 WorkManager/前台服务，将“索引构建/回填/修复”放到后台增量跑。
- UI 层：坚持分页（limit/offset 或 keyset pagination），避免一次性加载与大量 setState 重建。

---

## 扩展后可搜索的数据源清单（建议接入）

统一 `SearchIndex` 后，理论上所有“可落盘且有稳定主键”的内容都能纳入搜索。结合当前项目已有表结构，建议优先接入：

1) **截图 OCR 文本**（跨分库月表）
2) **截图元数据**：应用名/包名、时间、`page_url`/Deep Link（可做域名/关键词搜索）
3) **AI 图片元数据**：`ai_image_meta.tags_json / description / nsfw`
4) **动态（segments）**：`segment_results.output_text / categories / structured_json`（以及 `fts_content.ocr_text`）
5) **收藏/备注**：`favorites.note`（以及“已收藏”过滤）
6) **每日/每周总结**：`daily_summaries / weekly_summaries` 的 `output_text`
7) **早报/画像文章**：`morning_insights / persona_articles`（更偏“长期回忆”检索）
8) **MemOS 记忆后端**（可选）：原生侧 `memory_backend.db` 的标签/证据/画像条目（适合做“知识库式”检索）

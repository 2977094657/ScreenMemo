import 'package:flutter/widgets.dart';

class NocturneMemoryPrompts {
  NocturneMemoryPrompts._();

  static String chatSystemAddon(Locale locale) {
    final String code = locale.languageCode.toLowerCase();
    if (code.startsWith('zh')) return _chatAddonZh;
    return _chatAddonEn;
  }

  // A compact, single-call prompt for the “memory rebuild from images” pipeline.
  // This is intentionally shorter than the full Nocturne README prompt because
  // it runs many times and must stay token-efficient.
  static String rebuildSystemPrompt({required int maxImages}) {
    return _rebuildPromptZh.replaceAll('{MAX_IMAGES}', maxImages.toString());
  }

  static const String _chatAddonZh = '''
### [Nocturne 记忆（ScreenMemo）]
你拥有长期记忆系统（URI 图），通过以下工具访问：
- read_memory / search_memory / create_memory / update_memory / delete_memory / add_alias

#### 启动协议（仅限“新会话/新对话组”的第一轮）
在你回复用户之前，优先调用：read_memory("system://boot")。
把读到的内容当作你自己的长期记忆，而不是外部资料。

#### 架构认知（内容与访问分离）
- URI（domain://path）是访问路径；内容是独立实体。
- add_alias 不是复制：它为同一段内容增加一个新入口（同一内容可多路径）。
- 相同内容的真正“重复”通常来自不同节点/不同路径下的相似条目，需要合并整理。

#### 去重与写入纪律
- 写入前先检索：不确定 URI 用 search_memory；更新/删除前先 read_memory。
- 避免重复追加同样的要点；发现重复则提炼合并，而不是简单拼接。
- 记录稳定、可复用的信息；短期琐碎细节不要写入长期记忆。

#### 生命周期/时序（对象 + 事件）
当同一对象会经历状态变化（例如“杯子后来碎了”）时：
- 为该对象选一个“主节点”（canonical）并保持稳定 URI；在主节点里维护稳定属性与“当前状态（含日期）”。
- 若 <object>/events 不存在，先创建 events 节点（content 可写“事件目录/索引”）。
- 每次变化写入事件子节点：<object>/events/<yyyy-mm-dd>_<slug>（title 仅用 [a-z0-9_-]）。
- 同一对象需要在不同目录出现时，用 add_alias 增加入口，不要复制一份内容到多个节点。
- 回答生命周期/经过：先 read_memory(主节点) 看 children，再按需 read_memory(events/... ) 展开细节。

#### 结构操作（移动/重命名）
先 add_alias 建新路径，再 delete_memory 删除旧路径；不要“delete 再 create”。
''';

  static const String _chatAddonEn = '''
### [Nocturne Memory (ScreenMemo)]
You have a long-term memory system (URI graph) accessible via tools:
- read_memory / search_memory / create_memory / update_memory / delete_memory / add_alias

#### Boot protocol (only for the first turn of a new conversation/group)
Before replying, call: read_memory("system://boot").
Treat returned memories as your own long-term memory, not external references.

#### Architecture (content vs access)
- URI (domain://path) is an access path; content is a separate entity.
- add_alias does NOT copy content; it creates another access path to the same content.
- True duplication is similar content across different nodes/paths and should be merged.

#### De-dup & write discipline
- Search before writing: use search_memory when unsure; read_memory before update/delete.
- Avoid appending the same bullet points repeatedly; merge/refine when duplicates appear.
- Store stable, reusable facts; avoid transient details.

#### Lifecycle/Timeline (Object + Events)
When an object can change over time (e.g., “the cup later broke”):
- Choose a stable canonical object node URI; keep stable attributes and the “current status (with date)” on the object node.
- If <object>/events does not exist, create an events node first (content can be a short index label).
- Write each change as an event child node: <object>/events/<yyyy-mm-dd>_<slug> (title must be [a-z0-9_-]).
- If the same object should appear under multiple directories, use add_alias (do not duplicate content across nodes).
- To explain the full lifecycle: read_memory(object) first (children), then expand specific events as needed.

#### Structural operations (move/rename)
Use add_alias to create the new path first, then delete_memory to remove the old path.
''';

  static const String _rebuildPromptZh = '''
你是 ScreenMemo 的“记忆重建器”。你会收到：
- 最多 {MAX_IMAGES} 张截图（纯图片语料）
- 一份“当前长期记忆快照”（用于去重）

你的任务：只根据截图中**可见且稳定**的信息，提炼用户长期记忆，并输出写入动作（JSON）。

重要：这是单次提取，不是对话。你不能调用工具；你只能输出 JSON。

规则：
1) 不要猜测/补全/编造；不确定就跳过。
2) 输出必须是**纯 JSON**（不要 Markdown、不要解释、不要多余文字）。
3) 只能输出 update_memory/create_memory（actions 列表）。
4) update_memory 只能用 append（不要 patch）。
5) 允许写入的范围：只能在以下 6 个根节点及其任意子节点下写入（允许多层级）：
   - core://my_user/identity/*
   - core://my_user/preferences/*
   - core://my_user/projects/*
   - core://my_user/people/*
   - core://my_user/habits/*
   - core://my_user/other/*
   例如：core://my_user/projects/screen_memo/nocturne。
6) 去重：如果要点已在“记忆快照”里出现（含同义表达），必须跳过，不要重复写入。
7) append 必须以换行开头，并使用 Markdown 列表（- ...）。
8) create_memory 必须提供 title，并且 title 只能使用小写 slug（[a-z0-9_-]），不要用纯数字、不要随机编号。
   - 推荐 args：{"parent_uri":"...","title":"...","content":"...","priority":2}
   - 尽量不要使用 args.uri；如果你输出了 uri，则 uri 必须是完整目标路径，且 title 必须等于 uri 最后一级。
9) 优先更新已有节点（如果快照里已有相近的目录/节点），不确定时写入父级根节点，不要滥建节点。
10) 生命周期/时序（对象 + 事件，推荐）：当你确认“同一对象”发生状态变化：
   - 为该对象选择一个稳定的主节点（canonical），优先复用快照里已存在的对象节点。
   - 主节点（以及事件节点）content 需要包含可检索的对象名称/关键词（例如中文名），避免仅靠 slug。
   - 主节点 append 一条“状态(YYYY-MM-DD)：...”或“变化(YYYY-MM-DD)：...”以便按时间理解。
   - 若 <object>/events 不存在，先 create_memory 创建 events 节点（content 可写“事件目录/索引”）。
   - 同时在该对象下创建事件节点：<object>/events/<yyyy-mm-dd>_<slug>，用于记录细节。
11) 每次最多输出 5 条 actions；没有可写入内容则 {"actions": []}。

输出示例：
{"actions":[
  {"tool":"update_memory","args":{"uri":"core://my_user/preferences","append":"\\n- 喜欢深色主题"}}
]}
''';
}

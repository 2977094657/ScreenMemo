import 'memory_entity_policy.dart';

class NocturneMemoryEntityPrompts {
  NocturneMemoryEntityPrompts._();

  static String visualExtractionSystemPrompt({required int maxImages}) {
    return '''
你是 ScreenMemo 的“视觉记忆候选提取器”。

输入是同一时间段内最多 $maxImages 张截图。你只能依据截图本身可见信息做判断。
同一张截图可能同时提供 original 与局部裁剪视图，但都只代表同一帧视觉证据。

硬性要求：
1. 严禁把截图理解为 OCR 纯文本任务，不要逐字抄写长文本，不要把页面大段文案原样搬运进结果。
2. 你可以识别截图里肉眼可见的名字、品牌、标题、地点、关系、设置项、项目名，但只提炼“适合长期记忆候选层”的稳定对象或稳定事实。
3. 只输出结构化对象，最多返回 5 个 entity 候选。
4. 没有合适候选时，返回空数组。

允许的 root_key 只有：
${MemoryEntityPolicies.rootKeys.join(', ')}

字段要求：
- preferred_name: 给实体的人类可读名称；如果这是某个根节点的聚合事实，允许直接使用 root_key 作为 preferred_name。
- aliases: 同义称呼、缩写、常见英文名或品牌写法。
- visual_signature_summary: 用于后续去重的“视觉识别摘要”，强调外观、界面模式、稳定标签、logo、头像、项目结构、设置状态等。
- stable_visual_cues: 仅列最稳定的视觉线索。
- facts: 只写稳定事实，不要写“一次性看到了什么页面”；每条 fact 都必须给出 evidence_frames。
- evidence_frames: 写本批次中支持该实体的图片序号，从 0 开始。
- should_skip=true 只在该条候选本身不值得进入候选层时使用。
''';
  }

  static String resolutionSystemPrompt() {
    return '''
你是 ScreenMemo 的“实体解析器”。

你会拿到：
1. 一条刚从截图中提取出来的视觉实体候选
2. 同根目录下、通过规则检索出的少量已有候选实体

你的任务是做最终语义判断：
- MATCH_EXISTING
- CREATE_NEW
- ADD_ALIAS_TO_EXISTING
- REVIEW_REQUIRED

要求：
1. 规则检索只是 shortlist，你要做最终语义判断。
2. 即使名称不同，只要明显是同一实体，也应匹配已有实体。
3. 如果是同一实体但新名字更像别名，不要新建，优先 ADD_ALIAS_TO_EXISTING。
4. 只有在 shortlist 都不对时才 CREATE_NEW。
5. 存在明显歧义时用 REVIEW_REQUIRED。
6. 不要因为描述风格不同就拆成两个实体。
7. 这是双路独立复核中的单路判断，必须独立思考，不要为了求稳一律 REVIEW_REQUIRED。
8. 不要尝试决定最终 URI、slug 或 canonical_key；这些由程序端生成。
''';
  }

  static String resolutionArbiterSystemPrompt() {
    return '''
你是 ScreenMemo 的“实体归一仲裁器”。

你会拿到：
1. 原始视觉实体候选
2. shortlist 中的候选实体 dossier
3. Resolver A 的决策
4. Resolver B 的决策

你的任务：
1. 不是简单投票，而是审查 A/B 谁更可信。
2. 只能输出最终决策：
- MATCH_EXISTING
- CREATE_NEW
- ADD_ALIAS_TO_EXISTING
- REVIEW_REQUIRED
3. 若 A/B 都有明显漏洞或证据不足，返回 REVIEW_REQUIRED。
4. 若选择匹配已有实体，必须明确 matched_entity_id。
5. 若建议 CREATE_NEW，不要沿用含糊的 matched_entity_id。
''';
  }

  static String mergePlanSystemPrompt() {
    return '''
你是 ScreenMemo 的“实体合并规划器”。

你会拿到：
1. 新的视觉实体候选
2. 解析决策
3. 如果命中已有实体，还会拿到已有实体摘要

你的任务是输出一份高质量的合并规划：
- preferred_name
- aliases_to_add
- summary_rewrite
- visual_signature_summary
- claims_to_upsert
- events_to_append

要求：
1. summary_rewrite 要写成长期记忆节点内容，强调稳定事实，不要写 OCR 式长抄录。
2. 能抽象成稳定事实的，优先抽象；不稳定的页面瞬时信息不要写进去。
3. 如果是已有实体，summary_rewrite 要吸收新证据后更完整，但不要丢掉仍然成立的旧事实。
4. 不要尝试决定最终 URI、slug 或 canonical_key；程序端会根据实体主键和约束生成 display_uri。
5. claims_to_upsert 要尽量结构化，例如 当前公司 / 当前城市 / 关系 / 项目角色 / 偏好项 / 生命周期状态；每条 claim 都必须给 evidence_frames。
6. events_to_append 只写值得保留的阶段性事件，每条 event 都必须给 evidence_frames。
''';
  }

  static String auditSystemPrompt() {
    return '''
你是 ScreenMemo 的“实体写入审计器”。

你会拿到：
1. 新候选
2. 解析决策
3. 合并规划
4. shortlist 中的相近实体

你要做最后审计，只能返回：
- APPROVE
- BLOCK_DUPLICATE
- BLOCK_AMBIGUOUS
- BLOCK_LOW_EVIDENCE

要求：
1. 如果这条内容其实已经被某个 shortlist 实体覆盖，应 BLOCK_DUPLICATE，并给 suggested_entity_id。
2. 如果 merge plan 明显过度推断，或证据只支持一次性页面观察，应 BLOCK_LOW_EVIDENCE。
3. 如果 shortlist 中有多个都可能是同一实体，且无法安全决策，应 BLOCK_AMBIGUOUS。
4. 审计应偏向质量，不要放过低质量重复写入。
''';
  }
}

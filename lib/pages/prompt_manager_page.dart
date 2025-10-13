import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/ai_settings_service.dart';
import '../widgets/ui_components.dart';
import '../theme/app_theme.dart';

class PromptManagerPage extends StatefulWidget {
  const PromptManagerPage({super.key});

  @override
  State<PromptManagerPage> createState() => _PromptManagerPageState();
}

class _PromptManagerPageState extends State<PromptManagerPage> with SingleTickerProviderStateMixin {
  final AISettingsService _settings = AISettingsService.instance;

  // 当前存储的自定义提示词（null/空 = 使用默认）
  String? _promptSegment;
  String? _promptMerge;
  String? _promptDaily;

  // 编辑状态与控制器
  final TextEditingController _segCtrl = TextEditingController();
  final TextEditingController _mergeCtrl = TextEditingController();
  final TextEditingController _dailyCtrl = TextEditingController();
  bool _editingSeg = false;
  bool _editingMerge = false;
  bool _editingDaily = false;
  bool _savingSeg = false;
  bool _savingMerge = false;
  bool _savingDaily = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _segCtrl.dispose();
   _mergeCtrl.dispose();
   _dailyCtrl.dispose();
   super.dispose();
  }

  Future<void> _load() async {
    try {
      final seg = await _settings.getPromptSegment();
      final mer = await _settings.getPromptMerge();
      final day = await _settings.getPromptDaily();
      if (!mounted) return;
      setState(() {
        _promptSegment = seg;
        _promptMerge = mer;
        _promptDaily = day;

        _segCtrl.text = (seg == null || seg.trim().isEmpty) ? _defaultSegmentPromptPreview : seg;
        _mergeCtrl.text = (mer == null || mer.trim().isEmpty) ? _defaultMergePromptPreview : mer;
        _dailyCtrl.text = (day == null || day.trim().isEmpty) ? _defaultDailyPromptPreview : day;

        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // —— 默认提示词预览（与 AI 设置页保持一致） ——
  String get _defaultSegmentPromptPreview {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final isZh = code.startsWith('zh');
    if (isZh) {
      return '''
请基于以下多张屏幕图片进行中文总结，并输出结构化结果；必须严格遵循：
- 禁止使用OCR文本；直接理解图片内容；
- 不要逐图描述；按应用/主题整合用户在该时间段的‘行为总结’（浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等）；
- 对视频标题、作者、品牌等独特信息，按屏幕原样在输出中保留；
- 对同一文章/视频/页面的连续图片，归为同一 content_group 做整体总结；
- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现“## 概览”或“## 总结”等）；随后再使用 Markdown 小节呈现后续内容；
- Markdown 要求：所有“用于展示的文本字段”须使用 Markdown（overall_summary 与 content_groups[].summary；timeline[].summary 可用简短 Markdown；key_actions[].detail 可用精简 Markdown）；禁止使用代码块围栏（例如 ```），仅输出纯 Markdown 文本；
- 后续小节建议包含："## 关键操作"（按时间的要点清单）、"## 主要活动"（按应用/主题的要点清单）、"## 重点内容"（可保留的标题/作者/品牌等）；
- 在“## 关键操作”中，将相邻/连续同类行为合并为区间，格式“HH:mm:ss-HH:mm:ss：行为描述”（例如“08:16:41-08:27:21：浏览视频评论”）；仅在行为中断或切换时新起一条；控制 3-8 条精要；
- content_groups[].summary 使用 1-3 条 Markdown 要点呈现该组主题/代表性标题/阅读或观看意图；
以 JSON 输出以下字段（不要省略字段名）：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary；
- 仅输出一个 JSON 对象，不要附加解释或 JSON 外的 Markdown；所有展示性内容（含后续小节）请写入 overall_summary 字段的 Markdown；
字段约定（示例说明格式，非固定内容）：
- key_actions[]: [{ "type": "...", "app": "应用名", "ref_image": "文件名", "ref_time": "HH:mm:ss", "detail": "(Markdown) 精简说明", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "可为空", "app": "应用名", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["文件名1"], "summary": "(Markdown) 本组内容要点" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "应用名", "action": "浏览|观看|聊天|购物|搜索|编辑|游戏|设置|下载|分享|其他", "summary": "(Markdown) 一句话行为（可简短强调）" }]
- overall_summary: "(Markdown) 开头是一段无标题的总结段落，随后使用小节与要点，避免流水账并尽可能保留信息"
''';
    } else {
      return '''
Please summarize multiple screenshots in English and output structured results. STRICT rules:
- Do NOT use OCR text; understand images directly.
- Do not describe image-by-image; integrate a "behavior summary" over the time window by app/topic (browse/watch/chat/shop/work/settings/download/share/game, etc.).
- Preserve unique on-screen info like video titles, authors, brands as-is.
- Consecutive images from the same article/video/page should be merged into one content_group for a holistic summary.
- Start with one plain paragraph (no heading) summarizing the time window; then present later content with Markdown subsections.
- Markdown requirements: all display texts must use Markdown (overall_summary and content_groups[].summary; timeline[].summary may use brief Markdown; key_actions[].detail may use concise Markdown). NO code fences (```), only pure Markdown.
- overall_summary MUST include exactly these three second-level sections in this fixed order:
  "## Key Actions"
  "## Main Activities"
  "## Key Content"
  Each section MUST contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet. Do not omit or rename sections.
- In "## Key Actions", merge adjacent/continuous same-type actions as a time range "HH:mm:ss-HH:mm:ss: description"; only start a new item when action breaks/changes; keep 3–8 concise items.
- content_groups[].summary: 1–3 Markdown bullets describing group topic/representative titles/intent.
JSON fields to output (do not omit field names): apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.
- Output exactly ONE JSON object; no explanations or Markdown outside JSON. Put all display content (including sections) in overall_summary (Markdown).
Field conventions (examples, not fixed):
- key_actions[]: [{ "type": "...", "app": "App", "ref_image": "file", "ref_time": "HH:mm:ss", "detail": "(Markdown) brief", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "optional", "app": "App", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["file1"], "summary": "(Markdown) group highlights" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "App", "action": "browse|watch|chat|shop|search|edit|game|settings|download|share|other", "summary": "(Markdown) one-liner (may emphasize briefly)" }]
- overall_summary: "(Markdown) start with a single untitled paragraph; then sections with bullets; avoid narration; retain key info"
''';
    }
  }

  String get _defaultMergePromptPreview {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final isZh = code.startsWith('zh');
    if (isZh) {
      return '''
请基于以下图片产出合并后的总结；必须遵循以下规则（中文输出，结构化JSON，行为导向，禁止逐图/禁止OCR）：
- 禁止使用OCR文本，直接理解图片内容；
- 不要对每张图片逐条描述；请产出用户在该时间段的‘行为总结’，如 浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等，按应用或主题整合；
- 对包含视频标题、作者、品牌等独特信息，按屏幕原样保留；
- 对同一文章/视频/页面的连续图片，归为同一 content_group，做整体总结；
- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现“## 概览”或“## 总结”等）；随后再使用 Markdown 小节呈现后续内容；
- Markdown 要求：所有“用于展示的文本字段”须使用 Markdown（overall_summary 与 content_groups[].summary），用小标题与项目符号清晰呈现；禁止输出 Markdown 代码块标记（如 ```），仅纯 Markdown 文本；
- 后续小节建议包含："## 关键操作"、"## 主要活动"、"## 重点内容"；
- 在“## 关键操作”中，将相邻/连续同类行为合并为区间，格式“HH:mm:ss-HH:mm:ss：行为描述”（例如“08:16:41-08:27:21：浏览视频评论”）；仅在行为中断或切换时新起一条；控制 3-8 条精要；
- content_groups[].summary 为 Markdown，使用 1-3 条要点列出该组主题/代表性标题/阅读或观看意图；
- 为尽可能保留信息，可在 Markdown 中使用无序/有序列表、加粗/斜体与内联代码高亮（但不要使用代码块）；
以 JSON 输出以下字段（与普通事件保持一致，不要省略字段名）：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary；
- 仅输出一个 JSON 对象，不要附加解释或 JSON 外的 Markdown；所有展示性内容（含后续小节）请写入 overall_summary 字段的 Markdown；
字段约定（示例说明格式，非固定内容）：
- key_actions[]: [{ "type": "...", "app": "应用名", "ref_image": "文件名", "ref_time": "HH:mm:ss", "detail": "简要说明（避免敏感信息）", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "可为空", "app": "应用名", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["文件名1"], "summary": "本组内容的Markdown要点" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "应用名", "action": "浏览|观看|聊天|购物|搜索|编辑|游戏|设置|下载|分享|其他", "summary": "一句话行为（可用简短Markdown强调）" }]
- overall_summary: "开头为无标题的一段总结，随后使用Markdown小节与要点，保留多事件合并后的关键信息"
''';
    } else {
      return '''
Please produce a merged summary for the following images. MUST follow (English output, structured JSON, behavior-focused, no per-image narration / no OCR):
- Do NOT use OCR; understand images directly.
- Do not describe each image; output a "behavior summary" over the period (browse/watch/chat/shop/work/settings/download/share/game, etc.), grouped by app/topic.
- Preserve unique on-screen info (video titles/authors/brands) as seen.
- Merge consecutive images from the same article/video/page into one content_group and summarize holistically.
- Start with one plain paragraph (no headings) summarizing the period; then present details using Markdown sections.
- Markdown requirements: all display texts use Markdown (overall_summary and content_groups[].summary); headings and bullet points for clarity; NO code fences (```), only pure Markdown.
- overall_summary MUST include exactly these three second-level sections in this fixed order:
  "## Key Actions"
  "## Main Activities"
  "## Key Content"
  Each section MUST contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet. Do not omit or rename sections.
- In "## Key Actions", merge adjacent same-type actions into ranges "HH:mm:ss-HH:mm:ss: description" (e.g., "08:16:41-08:27:21: reading video comments"); only new item when action breaks; keep 3–8 concise lines.
- content_groups[].summary uses 1–3 Markdown bullets for group topic/representative titles/intent.
- To retain info, you may use lists/bold/italic/inline code in Markdown (but NOT code blocks).
Output JSON fields (same as normal event): apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.
- Output exactly ONE JSON object; no explanations or Markdown outside JSON; all display content belongs to overall_summary (Markdown).
Field conventions (examples, not fixed):
- key_actions[]: [{ "type": "...", "app": "App", "ref_image": "file", "ref_time": "HH:mm:ss", "detail": "brief (avoid sensitive info)", "confidence": 0.0 }]
- content_groups[]: [{ "group_type": "...", "title": "optional", "app": "App", "start_time": "HH:mm:ss", "end_time": "HH:mm:ss", "image_count": 1, "representative_images": ["file1"], "summary": "Markdown bullets" }]
- timeline[]: [{ "time": "HH:mm:ss", "app": "App", "action": "browse|watch|chat|shop|search|edit|game|settings|download|share|other", "summary": "one-liner (may emphasize briefly)" }]
- overall_summary: "Untitled opening paragraph, then Markdown sections with bullets; keep merged multi-event highlights"
''';
    }
  }

  String get _defaultDailyPromptPreview {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final isZh = code.startsWith('zh');
    if (isZh) {
      return '''
请从今日采集的多段屏幕图片生成“每日总结”（中文输出）。必须严格遵循：
- 忽略输入/上下文语言，严格使用当前应用语言输出；本次为中文。
- 禁止使用 OCR 文本；直接从图片语义推断。
- 先输出一段无标题的总览段落；随后用 Markdown 小节呈现细节。
- Markdown 要求：展示类文本必须用 Markdown；禁止代码块围栏（如 ```）；仅输出纯 Markdown。
- 概览后必须按固定顺序包含以下二级小节：
  "## 关键操作"
  "## 主要活动"
  "## 重点内容"
  每个小节至少 3 条以 "- " 开头的要点；信息不足也要保留小节并给出有意义的占位要点。
- 将相邻/连续同类行为合并为时间区间 "HH:mm:ss-HH:mm:ss：描述"；仅在行为中断/切换时新起一条；控制 5–12 条精要。
- content_groups[].summary 使用 1–3 条要点，概述主题/代表性标题/意图。
仅输出一个 JSON 对象，包含字段：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary。
- 不要添加解释或 JSON 之外的 Markdown；所有展示性内容（含小节）写入 overall_summary 的 Markdown。
''';
    } else {
      return '''
Please generate a "daily summary" in English from multiple screenshot segments captured today. STRICT rules:
- Ignore the language used in inputs/context and always respond in the app's current language; for this run, use English.
- Do NOT use OCR text; infer directly from image semantics.
- Start with one plain paragraph (no heading) as an overview; then present details with Markdown subsections.
- Markdown requirements: all display texts must be Markdown; NO code fences (```), only pure Markdown.
- After the overview, include exactly these second-level sections in the fixed order:
  "## Key Actions"
  "## Main Activities"
  "## Key Content"
  Each section must contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet.
- Merge adjacent/continuous same-type actions into ranges "HH:mm:ss-HH:mm:ss: description"; only start a new item when action breaks/changes; keep 5–12 concise items.
- content_groups[].summary uses 1–3 Markdown bullets to describe group topic/representative titles/intent.
Output exactly ONE JSON object with fields: apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.
- Do not add explanations or any Markdown outside JSON; put all display content (including sections) into overall_summary (Markdown).
''';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final t = AppLocalizations.of(context);
    final tabs = <Tab>[
      Tab(text: t.normalEventPromptLabel),
      Tab(text: t.mergeEventPromptLabel),
      Tab(text: t.dailySummaryPromptLabel),
    ];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.promptManagerTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(33),
            child: _buildStyledTabBar(tabs),
          ),
        ),
        body: TabBarView(
          children: [
            _buildPromptTab(
              label: t.normalEventPromptLabel,
              currentMarkdown: (_promptSegment == null || _promptSegment!.trim().isEmpty) ? _defaultSegmentPromptPreview : _promptSegment!,
              editing: _editingSeg,
              controller: _segCtrl,
              onEditToggle: () => setState(() => _editingSeg = !_editingSeg),
              onSave: _saveSeg,
              onReset: _resetSeg,
              saving: _savingSeg,
            ),
            _buildPromptTab(
              label: t.mergeEventPromptLabel,
              currentMarkdown: (_promptMerge == null || _promptMerge!.trim().isEmpty) ? _defaultMergePromptPreview : _promptMerge!,
              editing: _editingMerge,
              controller: _mergeCtrl,
              onEditToggle: () => setState(() => _editingMerge = !_editingMerge),
              onSave: _saveMerge,
              onReset: _resetMerge,
              saving: _savingMerge,
            ),
            _buildPromptTab(
              label: t.dailySummaryPromptLabel,
              currentMarkdown: (_promptDaily == null || _promptDaily!.trim().isEmpty) ? _defaultDailyPromptPreview : _promptDaily!,
              editing: _editingDaily,
              controller: _dailyCtrl,
              onEditToggle: () => setState(() => _editingDaily = !_editingDaily),
              onSave: _saveDaily,
              onReset: _resetDaily,
              saving: _savingDaily,
            ),
          ],
        ),
      ),
    );
  }

  // 截图列表风格 TabBar（下划线指示器）
  Widget _buildStyledTabBar(List<Tab> tabs) {
    final theme = Theme.of(context);
    final Color selectedColor = theme.brightness == Brightness.dark
        ? AppTheme.darkForeground
        : AppTheme.foreground;
    final Color unselectedColor = theme.textTheme.bodySmall?.color ?? AppTheme.mutedForeground;
    
    return SizedBox(
      height: 32,
      child: TabBar(
        tabs: tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.only(left: AppTheme.spacing4),
        labelPadding: const EdgeInsets.only(right: AppTheme.spacing6),
        labelColor: selectedColor,
        unselectedLabelColor: unselectedColor,
        labelStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 2.0, color: selectedColor),
          insets: const EdgeInsets.symmetric(horizontal: 8.0),
        ),
      ),
    );
  }

  Widget _buildPromptTab({
    required String label,
    required String currentMarkdown,
    required bool editing,
    required TextEditingController controller,
    required VoidCallback onEditToggle,
    required Future<void> Function() onSave,
    required Future<void> Function() onReset,
    required bool saving,
  }) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    
    // 编辑模式：使用独立滚动视图完整显示内容
    if (editing) {
      return Column(
        children: [
          // 固定的操作栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: saving ? null : onSave,
                  child: Text(saving ? t.savingLabel : t.actionSave),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onReset,
                  child: Text(t.resetToDefault),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onEditToggle,
                  child: Text(t.dialogCancel),
                ),
              ],
            ),
          ),
          // 可滚动的编辑区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: TextField(
                  controller: controller,
                  maxLines: null, // 不限制行数，完整显示
                  minLines: 20,  // 最小显示行数
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(AppTheme.spacing3),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    // 预览模式：保持原样
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: onEditToggle,
                child: Text(t.actionEdit),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          UICard(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            child: MarkdownBody(
              data: currentMarkdown,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSeg() async {
    if (_savingSeg) return;
    setState(() => _savingSeg = true);
    try {
      final v = _segCtrl.text.trim();
      await _settings.setPromptSegment(v.isEmpty ? null : v);
      await _load();
      if (mounted) {
        setState(() => _editingSeg = false);
        UINotifier.success(context, AppLocalizations.of(context).savedNormalPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingSeg = false);
    }
  }

  Future<void> _resetSeg() async {
    if (_savingSeg) return;
    setState(() => _savingSeg = true);
    try {
      await _settings.setPromptSegment(null);
      await _load();
      if (mounted) {
        setState(() => _editingSeg = false);
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingSeg = false);
    }
  }

  Future<void> _saveMerge() async {
    if (_savingMerge) return;
    setState(() => _savingMerge = true);
    try {
      final v = _mergeCtrl.text.trim();
      await _settings.setPromptMerge(v.isEmpty ? null : v);
      await _load();
      if (mounted) {
        setState(() => _editingMerge = false);
        UINotifier.success(context, AppLocalizations.of(context).savedMergePromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingMerge = false);
    }
  }

  Future<void> _resetMerge() async {
    if (_savingMerge) return;
    setState(() => _savingMerge = true);
    try {
      await _settings.setPromptMerge(null);
      await _load();
      if (mounted) {
        setState(() => _editingMerge = false);
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingMerge = false);
    }
  }

  Future<void> _saveDaily() async {
    if (_savingDaily) return;
    setState(() => _savingDaily = true);
    try {
      final v = _dailyCtrl.text.trim();
      await _settings.setPromptDaily(v.isEmpty ? null : v);
      await _load();
      if (mounted) {
        setState(() => _editingDaily = false);
        UINotifier.success(context, AppLocalizations.of(context).savedDailyPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingDaily = false);
    }
  }

  Future<void> _resetDaily() async {
    if (_savingDaily) return;
    setState(() => _savingDaily = true);
    try {
      await _settings.setPromptDaily(null);
      await _load();
      if (mounted) {
        setState(() => _editingDaily = false);
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingDaily = false);
    }
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/ai_settings_service.dart';
import '../services/ai_chat_service.dart';
import '../widgets/ui_dialog.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

/// AI 设置与测试页面：配置 OpenAI 兼容接口并进行多轮聊天测试
class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  static const double _inputRowHeight = 40.0;
  final AISettingsService _settings = AISettingsService.instance;
  final AIChatService _chat = AIChatService.instance;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _inputController = TextEditingController();

  List<AIMessage> _messages = <AIMessage>[];
  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  bool _streamEnabled = true;
  bool _connExpanded = false;
  bool _groupSelectorVisible = true;
  bool _promptExpanded = false;

  // 提示词管理
  String? _promptSegment;
  String? _promptMerge;
  final TextEditingController _promptSegmentController = TextEditingController();
  final TextEditingController _promptMergeController = TextEditingController();
  bool _editingPromptSegment = false;
  bool _editingPromptMerge = false;
  bool _savingPromptSegment = false;
  bool _savingPromptMerge = false;

  // 默认提示词预览（与原生默认一致，便于渲染&编辑）
  static const String _defaultSegmentPromptPreview = '''
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

  static const String _defaultMergePromptPreview = '''
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

  // 分组相关状态
  List<AISiteGroup> _groups = <AISiteGroup>[];
  int? _activeGroupId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _inputController.dispose();
    _promptSegmentController.dispose();
    _promptMergeController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      // 分组数据与当前激活分组
      final groups = await _settings.listSiteGroups();
      final activeId = await _settings.getActiveGroupId();

      // 基础配置：若存在激活分组，则从分组读取；否则读取未分组键值
      String baseUrl;
      String? apiKey;
      String model;
      final history = await _settings.getChatHistoryByGroup(activeId);
      final streamEnabled = await _settings.getStreamEnabled();
      final segPrompt = await _settings.getPromptSegment();
      final mergePrompt = await _settings.getPromptMerge();

      if (activeId != null) {
        final g = await _settings.getSiteGroupById(activeId);
        baseUrl = g?.baseUrl ?? await _settings.getBaseUrl();
        apiKey = g?.apiKey ?? await _settings.getApiKey();
        model = g?.model ?? await _settings.getModel();
      } else {
        baseUrl = await _settings.getBaseUrl();
        apiKey = await _settings.getApiKey();
        model = await _settings.getModel();
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _activeGroupId = activeId;

        // 未分组：默认值隐藏；分组：直接填充实际值
        if (activeId == null) {
          _baseUrlController.text = (baseUrl == 'https://api.openai.com') ? '' : baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = (model == 'gpt-4o-mini') ? '' : model;
        } else {
          _baseUrlController.text = baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = model;
        }

        _messages = history;
        _streamEnabled = streamEnabled;
        _promptSegment = segPrompt;
        _promptMerge = mergePrompt;
        // 预填编辑器（若无自定义，填充默认预览，方便用户基于默认直接修改）
        _promptSegmentController.text = (_promptSegment == null || _promptSegment!.trim().isEmpty)
            ? _defaultSegmentPromptPreview
            : _promptSegment!;
        _promptMergeController.text = (_promptMerge == null || _promptMerge!.trim().isEmpty)
            ? _defaultMergePromptPreview
            : _promptMerge!;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    setState(() { _saving = true; });
    try {
      final base = _baseUrlController.text.trim();
      final key = _apiKeyController.text.trim();
      final model = _modelController.text.trim();

      final gid = _activeGroupId;
      if (gid != null) {
        // 更新当前分组
        final g = await _settings.getSiteGroupById(gid);
        if (g == null) {
          UINotifier.error(context, AppLocalizations.of(context).groupNotFound);
        } else {
          final updated = g.copyWith(
            baseUrl: base.isEmpty ? g.baseUrl : base,
            apiKey: key.isEmpty ? null : key,
            model: model.isEmpty ? g.model : model,
          );
          await _settings.updateSiteGroup(updated);
          UINotifier.success(context, AppLocalizations.of(context).savedCurrentGroupToast);
        }
      } else {
        // 未分组：保存到键值
        await _settings.setBaseUrl(base);
        await _settings.setApiKey(key.isEmpty ? null : key);
        await _settings.setModel(model);
        UINotifier.success(context, AppLocalizations.of(context).saveSuccess);
      }
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  // ======= 提示词管理 =======
  Widget _buildPromptManagerCard() {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    Widget buildSection({
      required String label,
      required String currentMarkdown,
      required bool editing,
      required TextEditingController controller,
      required VoidCallback onEditToggle,
      required Future<void> Function() onSave,
      required Future<void> Function() onReset,
      required bool saving,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: titleStyle),
              const Spacer(),
              if (!editing)
                TextButton(
                  onPressed: onEditToggle,
                  child: Text(AppLocalizations.of(context).actionEdit),
                )
              else ...[
                TextButton(
                  onPressed: saving ? null : onSave,
                  child: Text(saving ? AppLocalizations.of(context).savingLabel : AppLocalizations.of(context).actionSave),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onReset,
                  child: Text(AppLocalizations.of(context).resetToDefault),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onEditToggle,
                  child: Text(AppLocalizations.of(context).dialogCancel),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          if (!editing)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              padding: const EdgeInsets.all(AppTheme.spacing3),
              child: MarkdownBody(
                data: currentMarkdown,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: TextField(
                controller: controller,
                minLines: 6,
                maxLines: 24,
                style: Theme.of(context).textTheme.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(AppTheme.spacing2),
                ),
              ),
            ),
          const SizedBox(height: AppTheme.spacing3),
        ],
      );
    }

    final segMarkdown = (_promptSegment == null || _promptSegment!.trim().isEmpty)
        ? _defaultSegmentPromptPreview
        : _promptSegment!;
    final mergeMarkdown = (_promptMerge == null || _promptMerge!.trim().isEmpty)
        ? _defaultMergePromptPreview
        : _promptMerge!;

    return UICard(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 折叠标题（点击展开/收起）
          GestureDetector(
            onTap: () => setState(() { _promptExpanded = !_promptExpanded; }),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context).promptManagerTitle, style: titleStyle),
                      const SizedBox(height: 2),
                      Text(
                        _buildPromptSummary(),
                        style: hintStyle,
                      ),
                    ],
                  ),
                ),
                Icon(_promptExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (_promptExpanded) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(AppLocalizations.of(context).promptManagerHint, style: hintStyle),
            const SizedBox(height: AppTheme.spacing3),

            // 普通事件提示词
            buildSection(
              label: AppLocalizations.of(context).normalEventPromptLabel,
              currentMarkdown: segMarkdown,
              editing: _editingPromptSegment,
              controller: _promptSegmentController,
              onEditToggle: () => setState(() => _editingPromptSegment = !_editingPromptSegment),
              onSave: _savePromptSegment,
              onReset: _resetPromptSegment,
              saving: _savingPromptSegment,
            ),

            // 合并事件提示词
            buildSection(
              label: AppLocalizations.of(context).mergeEventPromptLabel,
              currentMarkdown: mergeMarkdown,
              editing: _editingPromptMerge,
              controller: _promptMergeController,
              onEditToggle: () => setState(() => _editingPromptMerge = !_editingPromptMerge),
              onSave: _savePromptMerge,
              onReset: _resetPromptMerge,
              saving: _savingPromptMerge,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _savePromptSegment() async {
    if (_savingPromptSegment) return;
    setState(() => _savingPromptSegment = true);
    try {
      final v = _promptSegmentController.text.trim();
      await _settings.setPromptSegment(v.isEmpty ? null : v);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptSegment = false);
        UINotifier.success(context, AppLocalizations.of(context).savedNormalPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _resetPromptSegment() async {
    if (_savingPromptSegment) return;
    setState(() => _savingPromptSegment = true);
    try {
      await _settings.setPromptSegment(null);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptSegment = false);
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _savePromptMerge() async {
    if (_savingPromptMerge) return;
    setState(() => _savingPromptMerge = true);
    try {
      final v = _promptMergeController.text.trim();
      await _settings.setPromptMerge(v.isEmpty ? null : v);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptMerge = false);
        UINotifier.success(context, AppLocalizations.of(context).savedMergePromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptMerge = false);
    }
  }

  Future<void> _resetPromptMerge() async {
    if (_savingPromptMerge) return;
    setState(() => _savingPromptMerge = true);
    try {
      await _settings.setPromptMerge(null);
      await _loadAll();
      if (mounted) {
        setState(() => _editingPromptMerge = false);
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingPromptMerge = false);
    }
  }

  Future<void> _clearHistory() async {
    try {
      await _chat.clearConversation();
      if (!mounted) return;
      setState(() { _messages = <AIMessage>[]; });
      UINotifier.success(context, AppLocalizations.of(context).clearSuccess);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).clearFailedWithError(e.toString()));
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).messageCannotBeEmpty);
      return;
    }
    setState(() { _sending = true; });
    try {
      // 先本地追加用户消息，提升即时反馈
      setState(() {
        _messages = List<AIMessage>.from(_messages)
          ..add(AIMessage(role: 'user', content: text));
      });
      _inputController.clear();

      if (_streamEnabled) {
        // 追加一个空的助手消息作为占位，后续增量拼接
        setState(() {
          _messages = List<AIMessage>.from(_messages)
            ..add(AIMessage(role: 'assistant', content: ''));
        });
        final stream = _chat.sendMessageStreamed(text);
        await for (final part in stream) {
          if (!mounted) return;
          setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            if (last.role == 'assistant') {
              final updated = AIMessage(role: 'assistant', content: last.content + part);
              final newList = List<AIMessage>.from(_messages);
              newList[lastIdx] = updated;
              _messages = newList;
            }
          });
        }
      } else {
        final assistant = await _chat.sendMessage(text);
        if (!mounted) return;
        setState(() {
          _messages = List<AIMessage>.from(_messages)..add(assistant);
        });
      }
    } catch (e) {
      if (!mounted) return;
      // 将错误显示为一条“错误”气泡，便于区分样式
      setState(() {
        if (_streamEnabled && _messages.isNotEmpty && _messages.last.role == 'assistant') {
          final newList = List<AIMessage>.from(_messages);
          newList[_messages.length - 1] = AIMessage(role: 'error', content: e.toString());
          _messages = newList;
        } else {
          _messages = List<AIMessage>.from(_messages)
            ..add(AIMessage(role: 'error', content: e.toString()));
        }
      });
      UINotifier.error(context, AppLocalizations.of(context).sendFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).aiSettingsTitle),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacing4),
                    child: UICard(
                      padding: const EdgeInsets.all(AppTheme.spacing3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 折叠标题（点击展开/收起）
                          GestureDetector(
                            onTap: () => setState(() {
                              _connExpanded = !_connExpanded;
                              if (_connExpanded) _groupSelectorVisible = true;
                            }),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context).connectionSettingsTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _buildConnSummary(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(_connExpanded ? Icons.expand_less : Icons.expand_more),
                              ],
                            ),
                          ),
                          if (_connExpanded) ...[
                            const SizedBox(height: AppTheme.spacing2),
                            _buildGroupSelector(),
                            const SizedBox(height: AppTheme.spacing2),
                            _buildTextField(
                              controller: _baseUrlController,
                              label: AppLocalizations.of(context).baseUrlLabel,
                              hint: AppLocalizations.of(context).baseUrlHint,
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            _buildTextField(
                              controller: _apiKeyController,
                              label: AppLocalizations.of(context).apiKeyLabel,
                              hint: AppLocalizations.of(context).apiKeyHint,
                              obscure: true,
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            _buildTextField(
                              controller: _modelController,
                              label: AppLocalizations.of(context).modelLabel,
                              hint: AppLocalizations.of(context).modelHint,
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            Row(
                              children: [
                                UIButton(
                                  text: AppLocalizations.of(context).actionSave,
                                  variant: UIButtonVariant.primary,
                                  size: UIButtonSize.small,
                                  onPressed: _saving ? null : _saveSettings,
                                  loading: _saving,
                                ),
                                const SizedBox(width: AppTheme.spacing2),
                                UIButton(
                                  text: AppLocalizations.of(context).clearConversation,
                                  variant: UIButtonVariant.outline,
                                  size: UIButtonSize.small,
                                  onPressed: _clearHistory,
                                ),
                                const SizedBox(width: AppTheme.spacing2),
                                if (_activeGroupId != null)
                                  UIButton(
                                    text: AppLocalizations.of(context).deleteGroup,
                                    variant: UIButtonVariant.outline,
                                    size: UIButtonSize.small,
                                    onPressed: _deleteActiveGroup,
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            // 流式请求开关（紧凑）
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context).streamingRequestTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        AppLocalizations.of(context).streamingRequestHint,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.85,
                                  child: Switch(
                                    value: _streamEnabled,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (v) async {
                                      setState(() { _streamEnabled = v; });
                                      await _settings.setStreamEnabled(v);
                                      if (mounted) {
                                        UINotifier.success(
                                          context,
                                          v ? AppLocalizations.of(context).streamingEnabledToast
                                            : AppLocalizations.of(context).streamingDisabledToast,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
                    child: _buildPromptManagerCard(),
                  ),
                ),
              ],
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing4,
                      vertical: AppTheme.spacing2,
                    ),
                    child: Row(
                      children: [
                        Text(AppLocalizations.of(context).chatTestTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                      ),
                      child: _buildChatList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacing4,
                      AppTheme.spacing2,
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: _inputRowHeight,
                              child: _buildInputField(),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing2),
                          SizedBox(
                            height: _inputRowHeight,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints.tightFor(width: 92),
                              child: SizedBox.expand(
                                child: UIButton(
                                  text: _sending ? AppLocalizations.of(context).sendingLabel : AppLocalizations.of(context).actionSend,
                                  variant: UIButtonVariant.primary,
                                  size: UIButtonSize.small,
                                  onPressed: _sending ? null : _sendMessage,
                                  loading: _sending,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    // 紧凑型输入框（更小的字体与内边距）
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onTap: () {
          // 点击连接设置里的输入框时，自动收起上方分组下拉区域
          if (_groupSelectorVisible) {
            setState(() { _groupSelectorVisible = false; });
          }
        },
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing2,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: Theme.of(context).textTheme.bodySmall,
          hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          filled: false,
        ),
      ),
    );
  }

  /// 折叠头部摘要：展示当前分组 + baseUrl + model（截断显示）
  String _buildConnSummary() {
    final gid = _activeGroupId;
    String groupName;
    if (gid == null) {
      groupName = AppLocalizations.of(context).ungroupedSingleConfig;
    } else {
      final g = _groups.where((e) => e.id == gid).toList();
      groupName = g.isNotEmpty ? g.first.name : AppLocalizations.of(context).siteGroupDefaultName(gid);
    }
    final base = _baseUrlController.text.trim().isEmpty
        ? 'https://api.openai.com'
        : _baseUrlController.text.trim();
    final model = _modelController.text.trim().isEmpty
        ? 'gpt-4o-mini'
        : _modelController.text.trim();

    String brief(String s, int max) => s.length > max ? (s.substring(0, max) + '…') : s;

    return '$groupName · ${brief(base, 36)} · ${brief(model, 24)}';
  }

  /// 折叠头部摘要：提示词管理当前状态
  String _buildPromptSummary() {
    final l10n = AppLocalizations.of(context);
    final seg = (_promptSegment == null || _promptSegment!.trim().isEmpty)
        ? l10n.defaultLabel
        : l10n.customLabel;
    final mer = (_promptMerge == null || _promptMerge!.trim().isEmpty)
        ? l10n.defaultLabel
        : l10n.customLabel;
    return '${l10n.normalShortLabel} $seg · ${l10n.mergeShortLabel} $mer';
  }

  Future<void> _onGroupChanged(int? newId) async {
    await _settings.setActiveGroupId(newId);
    await _loadAll();
    if (!mounted) return;
    UINotifier.success(
      context,
      newId == null
          ? AppLocalizations.of(context).groupSwitchedToUngrouped
          : AppLocalizations.of(context).groupSwitched,
    );
  }

  Future<void> _addGroup() async {
    try {
      final name = AppLocalizations.of(context).siteGroupDefaultName(_groups.length + 1);
      final base = _baseUrlController.text.trim().isEmpty ? 'https://api.openai.com' : _baseUrlController.text.trim();
      final key = _apiKeyController.text.trim();
      final model = _modelController.text.trim().isEmpty ? 'gpt-4o-mini' : _modelController.text.trim();
      final id = await _settings.addSiteGroup(
        name: name,
        baseUrl: base,
        apiKey: key.isEmpty ? null : key,
        model: model,
      );
      await _settings.setActiveGroupId(id);
      await _loadAll();
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).groupAddedToast);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).addGroupFailedWithError(e.toString()));
    }
  }

  Future<void> _renameActiveGroup() async {
    final gid = _activeGroupId;
    if (gid == null) {
      if (mounted) UINotifier.info(context, AppLocalizations.of(context).groupNotSelected);
      return;
    }
    try {
      final g = await _settings.getSiteGroupById(gid);
      if (g == null) {
        if (mounted) UINotifier.error(context, AppLocalizations.of(context).groupNotFound);
        return;
      }
      final controller = TextEditingController(text: g.name);
      await showUIDialog<void>(
        context: context,
        title: AppLocalizations.of(context).renameGroupTitle,
        content: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: TextField(
            controller: controller,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).groupNameLabel,
              hintText: AppLocalizations.of(context).groupNameHint,
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing2,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ),
        actions: [
          UIDialogAction(
            text: AppLocalizations.of(context).dialogCancel,
          ),
          UIDialogAction(
            text: AppLocalizations.of(context).dialogOk,
            style: UIDialogActionStyle.primary,
            closeOnPress: false,
            onPressed: (ctx) async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                UINotifier.error(ctx, AppLocalizations.of(ctx).nameCannotBeEmpty);
                return;
              }
              try {
                final updated = g.copyWith(name: newName);
                await _settings.updateSiteGroup(updated);
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _loadAll();
                if (mounted) UINotifier.success(context, AppLocalizations.of(context).renameSuccess);
              } catch (e) {
                if (ctx.mounted) UINotifier.error(ctx, AppLocalizations.of(ctx).renameFailedWithError(e.toString()));
              }
            },
          ),
        ],
      );
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).loadGroupFailedWithError(e.toString()));
    }
  }

  Future<void> _deleteActiveGroup() async {
    final gid = _activeGroupId;
    if (gid == null) {
      UINotifier.info(context, AppLocalizations.of(context).groupNotSelected);
      return;
    }
    try {
      await _settings.deleteSiteGroup(gid);
      await _settings.setActiveGroupId(null);
      await _loadAll();
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).groupDeletedToast);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).deleteGroupFailedWithError(e.toString()));
    }
  }

  Widget _buildGroupSelector() {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(AppLocalizations.of(context).ungroupedSingleConfig),
      ),
      ..._groups.map((g) => DropdownMenuItem<int?>(
        value: g.id,
        child: Text(g.name),
      )),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).siteGroupsTitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          AppLocalizations.of(context).siteGroupsHint,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppTheme.spacing2),
        if (_groupSelectorVisible)
          Row(
            children: [
              DropdownButton<int?>(
                value: _activeGroupId,
                items: items,
                isDense: true,
                style: Theme.of(context).textTheme.bodySmall,
                onChanged: (v) => _onGroupChanged(v),
              ),
              const SizedBox(width: AppTheme.spacing2),
              UIButton(
                text: AppLocalizations.of(context).rename,
                variant: UIButtonVariant.outline,
                size: UIButtonSize.small,
                onPressed: (_activeGroupId == null) ? null : _renameActiveGroup,
              ),
              const SizedBox(width: AppTheme.spacing2),
              UIButton(
                text: AppLocalizations.of(context).addGroup,
                variant: UIButtonVariant.outline,
                size: UIButtonSize.small,
                onPressed: _addGroup,
              ),
            ],
          )
        else
          TextButton(
            onPressed: () => setState(() { _groupSelectorVisible = true; }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2, vertical: AppTheme.spacing1),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              AppLocalizations.of(context).showGroupSelector,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _inputController,
        textAlignVertical: TextAlignVertical.top,
        onTap: () {
          // 点击底部输入框时收起整个“连接设置”折叠区，避免遮挡内容
          setState(() { _connExpanded = false; });
        },
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).inputMessageHint,
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing2,
          ),
          filled: false,
        ),
        minLines: 1,
        maxLines: 4,
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      itemCount: _messages.length,
      reverse: false,
      padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
      itemBuilder: (context, index) {
        final m = _messages[index];
        final isUser = m.role == 'user';
        final isError = m.role == 'error' ||
            m.content.contains('"error"') ||
            m.content.toLowerCase().contains('server_error') ||
            m.content.toLowerCase().contains('request failed') ||
            m.content.toLowerCase().contains('no candidates returned');
        final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
        final bg = isUser
            ? Theme.of(context).colorScheme.primary
            : isError
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceVariant;
        final fg = isUser
            ? Theme.of(context).colorScheme.onPrimary
            : isError
                ? Theme.of(context).colorScheme.onErrorContainer
                : Theme.of(context).colorScheme.onSurfaceVariant;
        return Align(
          alignment: align,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing2,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: MarkdownBody(
              data: m.content,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
                a: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isUser
                      ? Theme.of(context).colorScheme.onPrimary
                      : isError
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
                h1: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                h2: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                h3: Theme.of(context).textTheme.bodyLarge?.copyWith(color: fg, fontWeight: FontWeight.w600),
                h4: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                h5: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                h6: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, fontStyle: FontStyle.italic),
                code: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, fontFamily: 'monospace'),
              ),
              onTapLink: (text, href, title) async {
                if (href == null) return;
                final uri = Uri.tryParse(href);
                if (uri != null) {
                  try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                }
              },
            ),
          ),
        );
      },
    );
  }
}



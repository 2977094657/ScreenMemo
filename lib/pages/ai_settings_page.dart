import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/ai_settings_service.dart';
import '../services/ai_chat_service.dart';

/// AI 设置与测试页面：配置 OpenAI 兼容接口并进行多轮聊天测试
class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
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
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final baseUrl = await _settings.getBaseUrl();
      final apiKey = await _settings.getApiKey();
      final model = await _settings.getModel();
      final history = await _settings.getChatHistory();
      final streamEnabled = await _settings.getStreamEnabled();
      if (!mounted) return;
      setState(() {
        _baseUrlController.text = baseUrl;
        _apiKeyController.text = apiKey ?? '';
        _modelController.text = model;
        _messages = history;
        _streamEnabled = streamEnabled;
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
      await _settings.setBaseUrl(_baseUrlController.text.trim());
      await _settings.setApiKey(_apiKeyController.text.trim());
      await _settings.setModel(_modelController.text.trim());
      if (!mounted) return;
      UINotifier.success(context, 'Saved');
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, 'Save failed: ' + e.toString());
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Future<void> _clearHistory() async {
    try {
      await _chat.clearConversation();
      if (!mounted) return;
      setState(() { _messages = <AIMessage>[]; });
      UINotifier.success(context, 'Cleared');
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, 'Clear failed: ' + e.toString());
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      UINotifier.error(context, 'Message is empty');
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
      UINotifier.error(context, 'Send failed: ' + e.toString());
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 设置与测试'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  child: UICard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('连接设置',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppTheme.spacing3),
                        _buildTextField(
                          controller: _baseUrlController,
                          label: 'Base URL',
                          hint: 'https://api.openai.com',
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        _buildTextField(
                          controller: _apiKeyController,
                          label: 'API Key',
                          hint: 'sk-... or other provider token',
                          obscure: true,
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        _buildTextField(
                          controller: _modelController,
                          label: 'Model',
                          hint: 'gpt-4o-mini / gpt-4o / compatible',
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        Row(
                          children: [
                            UIButton(
                              text: '保存',
                              variant: UIButtonVariant.primary,
                              onPressed: _saving ? null : _saveSettings,
                              loading: _saving,
                            ),
                            const SizedBox(width: AppTheme.spacing2),
                            UIButton(
                              text: '清空会话',
                              variant: UIButtonVariant.outline,
                              onPressed: _clearHistory,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        // 流式请求开关
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('流式请求',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '开启后将使用 streaming 响应（默认开启）',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.9,
                              child: Switch(
                                value: _streamEnabled,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) async {
                                  setState(() { _streamEnabled = v; });
                                  await _settings.setStreamEnabled(v);
                                  if (mounted) {
                                    UINotifier.success(context, v ? 'Streaming ON' : 'Streaming OFF');
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                          vertical: AppTheme.spacing2,
                        ),
                        child: Row(
                          children: [
                            Text('对话测试',
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
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildInputField(),
                            ),
                            const SizedBox(width: AppTheme.spacing2),
                            UIButton(
                              text: _sending ? '发送中' : '发送',
                              variant: UIButtonVariant.primary,
                              onPressed: _sending ? null : _sendMessage,
                              loading: _sending,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(AppTheme.spacing3),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _inputController,
        decoration: const InputDecoration(
          hintText: 'Type a message...',
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(AppTheme.spacing3),
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
        final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
        final bg = isUser
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceVariant;
        final fg = isUser
            ? Theme.of(context).colorScheme.onPrimary
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
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: isUser ? 0 : 1,
              ),
            ),
            child: Text(
              m.content,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: fg),
            ),
          ),
        );
      },
    );
  }
}



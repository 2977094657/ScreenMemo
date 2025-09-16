import 'screenshot_database.dart';

/// AI 设置与会话持久化服务
/// - 负责保存 baseUrl、apiKey、model
/// - 负责保存/读取多轮对话消息（轻量 JSON 持久化，限制历史条数）
class AISettingsService {
  AISettingsService._internal();
  static final AISettingsService instance = AISettingsService._internal();

  // 存储键名（SQLite ai_settings 表）
  static const String _keyBaseUrl = 'base_url';
  static const String _keyApiKey = 'api_key';
  static const String _keyModel = 'model';
  static const String _conversationId = 'default';
  static const String _keyStreamEnabled = 'stream_enabled';

  // 默认值
  static const String _defaultBaseUrl = 'https://api.openai.com';
  static const String _defaultModel = 'gpt-4o-mini';

  // 历史限制（仅保存最近 N 条，避免无限膨胀）
  static const int _maxHistoryMessages = 40;

  Future<bool> getStreamEnabled() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyStreamEnabled);
    if (v == null || v.isEmpty) return true; // 默认开启
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  Future<void> setStreamEnabled(bool enabled) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyStreamEnabled, enabled ? '1' : '0');
  }

  Future<String> getBaseUrl() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyBaseUrl);
    return (v == null || v.isEmpty) ? _defaultBaseUrl : v;
  }

  Future<void> setBaseUrl(String url) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyBaseUrl, url.trim());
  }

  Future<String?> getApiKey() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyApiKey);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setApiKey(String? key) async {
    final db = ScreenshotDatabase.instance;
    if (key == null || key.trim().isEmpty) {
      await db.setAiSetting(_keyApiKey, null);
    } else {
      await db.setAiSetting(_keyApiKey, key.trim());
    }
  }

  Future<String> getModel() async {
    final db = ScreenshotDatabase.instance;
    final v = await db.getAiSetting(_keyModel);
    return (v == null || v.isEmpty) ? _defaultModel : v;
  }

  Future<void> setModel(String model) async {
    final db = ScreenshotDatabase.instance;
    await db.setAiSetting(_keyModel, model.trim());
  }

  Future<List<AIMessage>> getChatHistory() async {
    final db = ScreenshotDatabase.instance;
    final rows = await db.getAiMessages(_conversationId);
    return rows.map((e) => AIMessage(
      role: (e['role'] as String?) ?? 'user',
      content: (e['content'] as String?) ?? '',
    )).toList();
  }

  Future<void> saveChatHistory(List<AIMessage> messages) async {
    final db = ScreenshotDatabase.instance;
    final trimmed = messages.length > _maxHistoryMessages
        ? messages.sublist(messages.length - _maxHistoryMessages)
        : messages;
    await db.clearAiConversation(_conversationId);
    for (final m in trimmed) {
      await db.appendAiMessage(_conversationId, m.role, m.content);
    }
  }

  Future<void> clearChatHistory() async {
    final db = ScreenshotDatabase.instance;
    await db.clearAiConversation(_conversationId);
  }
}

/// 简单的对话消息模型
class AIMessage {
  final String role; // system | user | assistant
  final String content;

  AIMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };

  factory AIMessage.fromJson(Map<String, dynamic> json) {
    return AIMessage(
      role: (json['role'] as String?) ?? 'user',
      content: (json['content'] as String?) ?? '',
    );
  }
}



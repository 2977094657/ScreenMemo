import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'ai_settings_service.dart';
import 'screenshot_database.dart';

/// OpenAI Chat Completions 兼容服务
/// - 使用 baseUrl + /v1/chat/completions
/// - 使用持久化的历史并在每次对话后保存
class AIChatService {
  AIChatService._internal();
  static final AIChatService instance = AIChatService._internal();

  final AISettingsService _settings = AISettingsService.instance;

  /// 发送一条用户消息，返回助手回复。
  /// - 会保留历史上下文，实现多轮会话
  Future<AIMessage> sendMessage(String userMessage, {Duration timeout = const Duration(seconds: 60)}) async {
    final endpoints = await _settings.getEndpointCandidates();
    Exception? lastError;
  
    for (final ep in endpoints) {
      final apiKey = ep.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        lastError = Exception('API key is empty');
        continue;
      }
      try {
        final uri = Uri.parse(_joinUrl(ep.baseUrl, '/v1/chat/completions'));
  
        // 历史按分组隔离
        final history = await _settings.getChatHistoryByGroup(ep.groupId);
        final List<Map<String, dynamic>> messages = [
          ...history.map((m) => m.toJson()),
          AIMessage(role: 'user', content: userMessage).toJson(),
        ];
  
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + apiKey,
        };
        final body = jsonEncode({
          'model': ep.model,
          'messages': messages,
          'temperature': 0.2,
          'stream': false,
        });
  
        final resp = await http.post(uri, headers: headers, body: body).timeout(timeout);
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw Exception('Request failed: ' + resp.statusCode.toString() + ' ' + resp.body);
        }
  
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          throw Exception('Empty choices');
        }
        final first = choices.first as Map<String, dynamic>;
        final msg = first['message'] as Map<String, dynamic>?;
        if (msg == null) {
          throw Exception('Invalid response');
        }
        final content = (msg['content'] as String?) ?? '';
        final assistant = AIMessage(role: 'assistant', content: content);
  
        // 更新并保存历史（写入对应分组的会话）
        final newHistory = <AIMessage>[...history, AIMessage(role: 'user', content: userMessage), assistant];
        await _settings.saveChatHistoryByGroup(ep.groupId, newHistory);
        await _settings.setActiveGroupId(ep.groupId);
        return assistant;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        continue; // 尝试下一个可用端点
      }
    }
  
    throw lastError ?? Exception('No valid AI endpoint available');
  }

  /// 流式发送用户消息，返回一个按增量文本推送的 Stream。
  /// - 结束后会将完整回复写入历史。
  Stream<String> sendMessageStreamed(String userMessage, {Duration timeout = const Duration(seconds: 60)}) async* {
    final endpoints = await _settings.getEndpointCandidates();
    Exception? lastError;
  
    for (final ep in endpoints) {
      final apiKey = ep.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        lastError = Exception('API key is empty');
        continue;
      }
  
      final uri = Uri.parse(_joinUrl(ep.baseUrl, '/v1/chat/completions'));
      final history = await _settings.getChatHistoryByGroup(ep.groupId);
      final List<Map<String, dynamic>> messages = [
        ...history.map((m) => m.toJson()),
        AIMessage(role: 'user', content: userMessage).toJson(),
      ];
  
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + apiKey,
      };
      final body = jsonEncode({
        'model': ep.model,
        'messages': messages,
        'temperature': 0.2,
        'stream': true,
      });
  
      final client = http.Client();
      StringBuffer full = StringBuffer();
      bool opened = false;
      try {
        final req = http.Request('POST', uri);
        req.headers.addAll(headers);
        req.body = body;
        final streamed = await client.send(req).timeout(timeout);
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          final r = await http.Response.fromStream(streamed);
          throw Exception('Request failed: ' + streamed.statusCode.toString() + ' ' + r.body);
        }
        opened = true;
  
        // 解析 SSE: 按行读取，提取以 "data: " 开头的 JSON 块
        String buffer = '';
        await for (final chunk in streamed.stream.transform(utf8.decoder)) {
          buffer += chunk;
          while (true) {
            final idx = buffer.indexOf('\n');
            if (idx == -1) break;
            final line = buffer.substring(0, idx).trimRight();
            buffer = buffer.substring(idx + 1);
            if (line.isEmpty) continue;
            if (!line.startsWith('data:')) continue;
            final data = line.substring(5).trim();
            if (data == '[DONE]') {
              buffer = '';
              break;
            }
            try {
              final Map<String, dynamic> j = jsonDecode(data) as Map<String, dynamic>;
              final choices = j['choices'];
              if (choices is List && choices.isNotEmpty) {
                final first = choices.first;
                if (first is Map<String, dynamic>) {
                  final delta = first['delta'];
                  if (delta is Map<String, dynamic>) {
                    final part = delta['content'];
                    if (part is String && part.isNotEmpty) {
                      full.write(part);
                      yield part;
                    }
                  }
                }
              }
            } catch (_) {
              // 忽略无法解析的行
            }
          }
        }
  
        // 流式完成：写入历史至对应分组，并切换激活分组
        final assistant = AIMessage(role: 'assistant', content: full.toString());
        final newHistory = <AIMessage>[...history, AIMessage(role: 'user', content: userMessage), assistant];
        await _settings.saveChatHistoryByGroup(ep.groupId, newHistory);
        await _settings.setActiveGroupId(ep.groupId);
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (opened) {
          // 中途失败不再尝试其他端点，直接退出
          break;
        }
        // 未建立连接，尝试下一个端点
      } finally {
        try { client.close(); } catch (_) {}
      }
    }
  
    throw lastError ?? Exception('No valid AI endpoint available');
  }

  /// 清空当前默认会话历史
  Future<void> clearConversation() => _settings.clearChatHistory();

  /// 获取当前会话历史
  Future<List<AIMessage>> getConversation() => _settings.getChatHistory();

  String _joinUrl(String base, String path) {
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!path.startsWith('/')) path = '/' + path;
    return base + path;
  }
}



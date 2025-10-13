import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'ai_settings_service.dart';
import 'screenshot_database.dart';
import 'locale_service.dart';

/// 基础流事件（content/reasoning），用于流式 UI 显示“思考内容”
class AIStreamEvent {
  final String kind; // 'content' | 'reasoning'
  final String data;
  AIStreamEvent(this.kind, this.data);
}

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
    final endpoints = await _settings.getEndpointCandidates(context: 'chat');
    Exception? lastError;
    String? usedModel;
  
    for (final ep in endpoints) {
      usedModel = ep.model;
      final apiKey = ep.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        lastError = Exception('API key is empty');
        continue;
      }
      try {
        final uri = Uri.parse(_joinUrl(ep.baseUrl, ep.chatPath));
  
        // 历史按会话CID隔离 + 注入系统语言指示（本地化读取，忽略上下文语言）
        final history = await _settings.getChatHistory();
        final String langCode = (LocaleService.instance.locale?.languageCode ??
                WidgetsBinding.instance.platformDispatcher.locale.languageCode)
            .toLowerCase();
        final bool isZh = langCode.startsWith('zh');
        final locale = isZh ? const Locale('zh') : const Locale('en');
        final String systemMsg = lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;

        final List<Map<String, dynamic>> messages = [
          {'role': 'system', 'content': systemMsg},
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
        // 非流式接口一般不返回 reasoning；此处保持空
        final assistant = AIMessage(role: 'assistant', content: content);
  
        // 更新并保存历史（写入当前激活会话）
        final newHistory = <AIMessage>[...history, AIMessage(role: 'user', content: userMessage), assistant];
        await _settings.saveChatHistoryActive(newHistory);
        
        // 保存当前使用的模型到会话
        try {
          final cid = await _settings.getActiveConversationCid();
          final db = ScreenshotDatabase.instance;
          await db.database.then((d) => d.execute(
            'UPDATE ai_conversations SET model = ? WHERE cid = ?',
            [usedModel, cid],
          ));
        } catch (_) {}
        
        // 若为会话的第一条用户消息，自动设置会话标题为该消息（截取前30字符）
        if (history.isEmpty) {
          try {
            final cid = await _settings.getActiveConversationCid();
            final title = userMessage.length > 30
                ? userMessage.substring(0, 30) + '...'
                : userMessage;
            await _settings.renameConversation(cid, title);
          } catch (_) {}
        }
        
        return assistant;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        continue; // 尝试下一个可用端点
      }
    }
  
    throw lastError ?? Exception('No valid AI endpoint available');
  }

  /// 新版流式：返回 AIStreamEvent（content 与 reasoning），用于显示"思考内容"
  Stream<AIStreamEvent> sendMessageStreamedV2(String userMessage, {Duration timeout = const Duration(seconds: 60)}) async* {
    final endpoints = await _settings.getEndpointCandidates(context: 'chat');
    Exception? lastError;
    String? usedModel;

    for (final ep in endpoints) {
      usedModel = ep.model;
      final apiKey = ep.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        lastError = Exception('API key is empty');
        continue;
      }

      final uri = Uri.parse(_joinUrl(ep.baseUrl, ep.chatPath));
      final history = await _settings.getChatHistory();
      final String langCode = (LocaleService.instance.locale?.languageCode ??
              WidgetsBinding.instance.platformDispatcher.locale.languageCode)
          .toLowerCase();
      final bool isZh = langCode.startsWith('zh');
      final locale = isZh ? const Locale('zh') : const Locale('en');
      final String systemMsg = lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;

      final List<Map<String, dynamic>> messages = [
        {'role': 'system', 'content': systemMsg},
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
      final StringBuffer reasoningBuf = StringBuffer();
      final DateTime reasoningStart = DateTime.now();
      try {
        final req = http.Request('POST', uri);
        req.headers.addAll(headers);
        req.body = body;
        final streamed = await client.send(req).timeout(timeout);
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          final r = await http.Response.fromStream(streamed);
          throw Exception('Request failed: ' + streamed.statusCode.toString() + ' ' + r.body);
        }

        // 解析 SSE 行
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
                    // 兼容多供应商“思考内容”字段
                    final rc1 = delta['reasoning_content'];
                    final rc2 = (delta['reasoning'] is Map) ? (delta['reasoning']['content']) : null;
                    final rc3 = delta['thinking'];
                    final reasoningPart = rc1 ?? rc2 ?? rc3;
                    if (reasoningPart is String && reasoningPart.isNotEmpty) {
                      reasoningBuf.write(reasoningPart);
                      yield AIStreamEvent('reasoning', reasoningPart);
                    }
                    final part = delta['content'];
                    if (part is String && part.isNotEmpty) {
                      full.write(part);
                      yield AIStreamEvent('content', part);
                    }
                  }
                }
              }
            } catch (_) {
              // 忽略无法解析的行
            }
          }
        }

        // 完整结果写入历史（当前激活会话），并带上推理内容与耗时
        final reasoningText = reasoningBuf.toString();
        final Duration reasoningDuration = DateTime.now().difference(reasoningStart);
        final assistant = AIMessage(
          role: 'assistant',
          content: full.toString(),
          reasoningContent: reasoningText.isEmpty ? null : reasoningText,
          reasoningDuration: reasoningText.isEmpty ? null : reasoningDuration,
        );
        final newHistory = <AIMessage>[...history, AIMessage(role: 'user', content: userMessage), assistant];
        await _settings.saveChatHistoryActive(newHistory);
        
        // 保存当前使用的模型到会话
        try {
          final cid = await _settings.getActiveConversationCid();
          final db = ScreenshotDatabase.instance;
          await db.database.then((d) => d.execute(
            'UPDATE ai_conversations SET model = ? WHERE cid = ?',
            [usedModel, cid],
          ));
        } catch (_) {}
        
        // 若为会话的第一条用户消息，自动设置会话标题为该消息（截取前30字符）
        if (history.isEmpty) {
          try {
            final cid = await _settings.getActiveConversationCid();
            final title = userMessage.length > 30
                ? userMessage.substring(0, 30) + '...'
                : userMessage;
            await _settings.renameConversation(cid, title);
          } catch (_) {}
        }
        
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        // 尝试下一个端点
      } finally {
        try { client.close(); } catch (_) {}
      }
    }
    throw lastError ?? Exception('No valid AI endpoint available');
  }

  /// 独立一次性请求（不使用与不保存会话历史）
  /// - 仅发送单条 user 消息到当前端点，不写 ai_messages，不影响 AI 设置页会话
  /// - context: 使用哪类上下文的提供商/模型（如 'chat' | 'segments'）
  Future<AIMessage> sendMessageOneShot(
    String userMessage, {
    String context = 'chat',
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoints = await _settings.getEndpointCandidates(context: context);
    Exception? lastError;

    for (final ep in endpoints) {
      final apiKey = ep.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        lastError = Exception('API key is empty');
        continue;
      }
      try {
        final uri = Uri.parse(_joinUrl(ep.baseUrl, ep.chatPath));
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + apiKey,
        };
        final String langCode = (LocaleService.instance.locale?.languageCode ??
                WidgetsBinding.instance.platformDispatcher.locale.languageCode)
            .toLowerCase();
        final bool isZh = langCode.startsWith('zh');
        final locale = isZh ? const Locale('zh') : const Locale('en');
        final String systemMsg = lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;

        final body = jsonEncode({
          'model': ep.model,
          'messages': [
            {'role': 'system', 'content': systemMsg},
            {'role': 'user', 'content': userMessage},
          ],
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
        return AIMessage(role: 'assistant', content: content);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        continue; // 尝试下一个端点
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



import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'ai_settings_service.dart';
import 'screenshot_database.dart';
import 'locale_service.dart';
import 'flutter_logger.dart';

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
    try { await FlutterLogger.nativeInfo('AI', 'sendMessage begin len=' + userMessage.length.toString()); } catch (_) {}
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
        try { await FlutterLogger.nativeDebug('AI', 'HTTP POST ' + uri.toString() + ' bodyLen=' + body.length.toString()); } catch (_) {}
        final resp = await http.post(uri, headers: headers, body: body).timeout(timeout);
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw Exception('Request failed: ' + resp.statusCode.toString() + ' ' + resp.body);
        }
  
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        try { await FlutterLogger.nativeDebug('AI', 'resp status=' + resp.statusCode.toString() + ' bodyLen=' + resp.body.length.toString()); } catch (_) {}

        // 兼容多种非流式结构：
        // 1) OpenAI Chat Completions { choices[0].message.content, message.reasoning_content | reasoning | thinking }
        // 2) OpenAI Responses API { output: [ {type:"reasoning"|"message"...} ] }
        // 3) Google Gemini { candidates[].content.parts[] (text/thought) }
        String content = '';
        String reasoningText = '';

        if (data['output'] is List) {
          // Responses API 非流式
          final outs = (data['output'] as List).cast<dynamic>();
          final StringBuffer cbuf = StringBuffer();
          final StringBuffer rbuf = StringBuffer();
          for (final it in outs) {
            if (it is! Map<String, dynamic>) continue;
            final t = it['type'];
            if (t == 'reasoning') {
              final summary = it['summary'];
              if (summary is List) {
                for (final p in summary) {
                  if (p is Map<String, dynamic> && p['type'] == 'summary_text') {
                    final txt = (p['text'] as String?) ?? '';
                    if (txt.isNotEmpty) {
                      if (rbuf.isNotEmpty) rbuf.write('\n');
                      rbuf.write(txt);
                    }
                  }
                }
              }
            } else if (t == 'message') {
              final cont = it['content'];
              if (cont is List) {
                for (final p in cont) {
                  if (p is Map<String, dynamic> && p['type'] == 'output_text') {
                    final txt = (p['text'] as String?) ?? '';
                    if (txt.isNotEmpty) cbuf.write(txt);
                  }
                }
              }
            }
          }
          content = cbuf.toString();
          reasoningText = rbuf.toString();
        } else if (data['candidates'] is List) {
          // Google 非流式（generateContent）
          final candidates = (data['candidates'] as List);
          if (candidates.isNotEmpty && candidates.first is Map<String, dynamic>) {
            final c0 = candidates.first as Map<String, dynamic>;
            final contentObj = c0['content'];
            if (contentObj is Map<String, dynamic>) {
              final parts = contentObj['parts'];
              if (parts is List) {
                final StringBuffer cbuf = StringBuffer();
                final StringBuffer rbuf = StringBuffer();
                for (final p in parts) {
                  if (p is Map<String, dynamic>) {
                    final txt = (p['text'] as String?) ?? '';
                    final thought = (p['thought'] as bool?) ?? false;
                    if (txt.isEmpty) continue;
                    if (thought) {
                      if (rbuf.isNotEmpty) rbuf.write('\n');
                      rbuf.write(txt);
                    } else {
                      cbuf.write(txt);
                    }
                  }
                }
                content = cbuf.toString();
                reasoningText = rbuf.toString();
              }
            }
          }
        } else {
          // Chat Completions 兼容
          final choices = data['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) {
            throw Exception('Empty choices');
          }
          final first = choices.first as Map<String, dynamic>;
          final msg = first['message'] as Map<String, dynamic>?;
          if (msg == null) {
            throw Exception('Invalid response');
          }
          content = (msg['content'] as String?) ?? '';
          final rc = (msg['reasoning_content'] as String?) ?? (msg['reasoning'] as String?) ?? (msg['thinking'] as String?);
          reasoningText = (rc ?? '').trim();
        }

        // 兼容 <think> 标签：提取到 reasoning 并从正文移除
        if (content.isNotEmpty) {
          final RegExp thinkRe = RegExp(r'<think>([\s\S]*?)(?:</think>|$)', dotAll: true);
          final Iterable<RegExpMatch> ms = thinkRe.allMatches(content);
          String extracted = '';
          for (final m in ms) {
            final seg = (m.group(1) ?? '').trim();
            if (seg.isNotEmpty) {
              if (extracted.isNotEmpty) extracted += '\n\n';
              extracted += seg;
            }
          }
          if (extracted.isNotEmpty) {
            reasoningText = reasoningText.isEmpty ? extracted : (reasoningText + '\n' + extracted);
            content = content.replaceAll(thinkRe, '');
          }
        }

        final assistant = AIMessage(
          role: 'assistant',
          content: content,
          reasoningContent: reasoningText.isEmpty ? null : reasoningText,
          reasoningDuration: null,
        );
  
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
    try { await FlutterLogger.nativeInfo('AI', 'sendMessageStreamedV2 begin len=' + userMessage.length.toString()); } catch (_) {}
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
        try { await FlutterLogger.nativeDebug('AI', 'HTTP STREAM POST ' + uri.toString() + ' bodyLen=' + body.length.toString()); } catch (_) {}
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

              // OpenAI Responses API (SSE) 事件兼容：解析 reasoning 与内容增量
              final dynamic t = j['type'];
              if (t is String) {
                if (t == 'response.reasoning_summary_text.delta') {
                  final d = j['delta'];
                  if (d is String && d.isNotEmpty) {
                    reasoningBuf.write(d);
                    yield AIStreamEvent('reasoning', d);
                  }
                  continue;
                }
                if (t == 'response.output_text.delta') {
                  final d = j['delta'];
                  if (d is String && d.isNotEmpty) {
                    full.write(d);
                    yield AIStreamEvent('content', d);
                  }
                  continue;
                }
                if (t == 'response.output_item.added' || t == 'response.completed' || t == 'response.function_call_arguments.done') {
                  // 暂不需要特殊处理；连接会在 completed 后关闭
                  continue;
                }
              }

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
        // 兼容 <think> 标签：提取为 reasoning，并从正文移除
        final String originalContent = full.toString();
        final RegExp thinkRe = RegExp(r'<think>([\s\S]*?)(?:</think>|$)', dotAll: true);
        String extractedFromThink = '';
        for (final m in thinkRe.allMatches(originalContent)) {
          final seg = (m.group(1) ?? '').trim();
          if (seg.isNotEmpty) {
            if (extractedFromThink.isNotEmpty) extractedFromThink += '\n\n';
            extractedFromThink += seg;
          }
        }
        final String cleanedContent = originalContent.replaceAll(thinkRe, '');
        String reasoningText = reasoningBuf.toString();
        if (extractedFromThink.isNotEmpty) {
          reasoningText = reasoningText.isEmpty ? extractedFromThink : (reasoningText + '\n' + extractedFromThink);
        }
        final Duration reasoningDuration = DateTime.now().difference(reasoningStart);
        final assistant = AIMessage(
          role: 'assistant',
          content: cleanedContent,
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

  /// 流式（带显示与实际消息分离）：
  /// - displayUserMessage: UI 中展示与保存为用户消息的内容（原始输入）
  /// - actualUserMessage: 实际发送给模型的提示（例如拼接了上下文的最终提示）
  /// - 历史保存为：[..., user(display), system(actual), assistant]
  Stream<AIStreamEvent> sendMessageStreamedV2WithDisplayOverride(
    String displayUserMessage,
    String actualUserMessage, {
    Duration timeout = const Duration(seconds: 60),
  }) async* {
    try { await FlutterLogger.nativeInfo('AI', 'sendMessageStreamedV2WithDisplayOverride begin displayLen=' + displayUserMessage.length.toString() + ' actualLen=' + actualUserMessage.length.toString()); } catch (_) {}
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
        AIMessage(role: 'user', content: actualUserMessage).toJson(),
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
        try { await FlutterLogger.nativeDebug('AI', 'HTTP STREAM POST ' + uri.toString() + ' bodyLen=' + body.length.toString()); } catch (_) {}
        req.headers.addAll(headers);
        req.body = body;
        final streamed = await client.send(req).timeout(timeout);
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          final r = await http.Response.fromStream(streamed);
          throw Exception('Request failed: ' + streamed.statusCode.toString() + ' ' + r.body);
        }

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
            } catch (_) {}
          }
        }

        // 保存历史：user(原文可见) + system(最终提示隐藏UI) + assistant
        final reasoningText = reasoningBuf.toString();
        final Duration reasoningDuration = DateTime.now().difference(reasoningStart);
        final assistant = AIMessage(
          role: 'assistant',
          content: full.toString(),
          reasoningContent: reasoningText.isEmpty ? null : reasoningText,
          reasoningDuration: reasoningText.isEmpty ? null : reasoningDuration,
        );
        final newHistory = <AIMessage>[
          ...history,
          AIMessage(role: 'user', content: displayUserMessage),
          AIMessage(role: 'system', content: actualUserMessage),
          assistant,
        ];
        await _settings.saveChatHistoryActive(newHistory);

        // 保存模型与标题（以显示消息为标题）
        try {
          final cid = await _settings.getActiveConversationCid();
          final db = ScreenshotDatabase.instance;
          await db.database.then((d) => d.execute('UPDATE ai_conversations SET model = ? WHERE cid = ?', [usedModel, cid]));
        } catch (_) {}
        if (history.isEmpty) {
          try {
            final cid = await _settings.getActiveConversationCid();
            final title = displayUserMessage.length > 30 ? displayUserMessage.substring(0, 30) + '...' : displayUserMessage;
            await _settings.renameConversation(cid, title);
          } catch (_) {}
        }
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      } finally {
        try { client.close(); } catch (_) {}
      }
    }
    throw lastError ?? Exception('No valid AI endpoint available');
  }

  /// 非流式（带显示与实际消息分离）
  Future<AIMessage> sendMessageWithDisplayOverride(
    String displayUserMessage,
    String actualUserMessage, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
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
          AIMessage(role: 'user', content: actualUserMessage).toJson(),
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

        // 保存历史：user(原文) + system(最终提示) + assistant
        final newHistory = <AIMessage>[
          ...history,
          AIMessage(role: 'user', content: displayUserMessage),
          AIMessage(role: 'system', content: actualUserMessage),
          assistant,
        ];
        await _settings.saveChatHistoryActive(newHistory);

        try {
          final cid = await _settings.getActiveConversationCid();
          final db = ScreenshotDatabase.instance;
          await db.database.then((d) => d.execute('UPDATE ai_conversations SET model = ? WHERE cid = ?', [usedModel, cid]));
        } catch (_) {}
        if (history.isEmpty) {
          try {
            final cid = await _settings.getActiveConversationCid();
            final title = displayUserMessage.length > 30 ? displayUserMessage.substring(0, 30) + '...' : displayUserMessage;
            await _settings.renameConversation(cid, title);
          } catch (_) {}
        }
        return assistant;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        continue;
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
        final String base = ep.baseUrl;
        final bool isGoogle = base.contains('googleapis.com') || base.contains('generativelanguage');
        final headers = <String, String>{ 'Content-Type': 'application/json' };
        if (!isGoogle) {
          headers['Authorization'] = 'Bearer ' + apiKey;
        }
        final String langCode = (LocaleService.instance.locale?.languageCode ??
                WidgetsBinding.instance.platformDispatcher.locale.languageCode)
            .toLowerCase();
        final bool isZh = langCode.startsWith('zh');
        final locale = isZh ? const Locale('zh') : const Locale('en');
        final String systemMsg = lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;

        if (isGoogle) {
          // Google Gemini REST: POST {base}/v1beta/models/{model}:generateContent?key=API_KEY
          final String url = (base.endsWith('/'))
              ? base.substring(0, base.length - 1)
              : base;
          final uri = Uri.parse('$url/v1beta/models/${ep.model}:generateContent?key=$apiKey');
          final body = jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': systemMsg},
                  {'text': userMessage},
                ]
              }
            ]
          });
          final resp = await http.post(uri, headers: headers, body: body).timeout(timeout);
          if (resp.statusCode < 200 || resp.statusCode >= 300) {
            throw Exception('Request failed: ${resp.statusCode} ${resp.body}');
          }
          String content = '';
          try {
            final Map<String, dynamic> j = jsonDecode(resp.body) as Map<String, dynamic>;
            final candidates = j['candidates'];
            if (candidates is List && candidates.isNotEmpty) {
              final c0 = candidates.first;
              if (c0 is Map<String, dynamic>) {
                final ct = c0['content'];
                if (ct is Map<String, dynamic>) {
                  final parts = ct['parts'];
                  if (parts is List && parts.isNotEmpty) {
                    final p0 = parts.first;
                    if (p0 is Map<String, dynamic>) {
                      content = (p0['text'] as String?) ?? '';
                    }
                  }
                }
              }
            }
          } catch (_) {}
          // 若响应为错误负载但状态码为200，也要抛出，避免写入空白
          if (content.trim().isEmpty) {
            throw Exception('Empty content: ' + resp.body);
          }
          return AIMessage(role: 'assistant', content: content);
        } else {
          // OpenAI 兼容 REST: /v1/chat/completions
          final uri = Uri.parse(_joinUrl(base, ep.chatPath));
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
        }
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



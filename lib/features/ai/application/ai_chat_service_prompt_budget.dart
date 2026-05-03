part of 'ai_chat_service.dart';

extension AIChatServicePromptBudgetExt on AIChatService {
  bool _apiContentHasImageParts(Object? apiContent) {
    if (apiContent is! List) return false;
    for (final p in apiContent) {
      if (p is Map) {
        final String type = (p['type'] ?? '').toString();
        if (type == 'image_url') return true;
      }
    }
    return false;
  }

  List<Object?> _sanitizeApiContentForTokenEstimate(Object? apiContent) {
    if (apiContent is! List) return const <Object?>[];
    final List<Object?> out = <Object?>[];
    for (final p in apiContent) {
      if (p is! Map) {
        out.add(p);
        continue;
      }
      final String type = (p['type'] ?? '').toString();
      if (type == 'image_url') {
        out.add(<String, Object?>{
          'type': 'image_url',
          'image_url': const <String, Object?>{'url': '<image>'},
        });
        continue;
      }
      if (type == 'text') {
        out.add(<String, Object?>{
          'type': 'text',
          'text': (p['text'] ?? '').toString(),
        });
        continue;
      }
      out.add(<String, Object?>{'type': type});
    }
    return out;
  }

  int _approxTokensForToolLoopMessage(AIMessage message) {
    // Token estimation here must NOT count base64 image payloads as tokens.
    // Otherwise the tool loop will think it is “over budget” immediately after
    // a get_images call and start trimming / looping.
    try {
      final Map<String, dynamic> json = message.toJson();
      final Object? c = json['content'];
      if (c is List) {
        json['content'] = _sanitizeApiContentForTokenEstimate(c);
      }
      return PromptBudget.approxTokensForText(jsonEncode(json));
    } catch (_) {
      final String fallback = message.apiContent == null
          ? message.content
          : (_apiContentHasImageParts(message.apiContent)
                ? '<image parts omitted>'
                : '<structured content>');
      return PromptBudget.approxTokensForText('${message.role}\n$fallback');
    }
  }

  int _approxTokensForToolLoopMessages(List<AIMessage> messages) {
    int total = 0;
    for (final m in messages) {
      total += _approxTokensForToolLoopMessage(m);
    }
    return total;
  }

  String _imageMessagePlaceholderText(AIMessage message) {
    final Object? api = message.apiContent;
    if (api is! List) {
      return _loc(
        '（历史图片已省略，以控制上下文大小；如需再次分析请重新调用 get_images。）',
        '(Previous images omitted to keep context small; call get_images again if needed.)',
      );
    }
    final List<String> names = <String>[];
    for (final p in api) {
      if (p is! Map) continue;
      if ((p['type'] ?? '').toString() != 'text') continue;
      final String t = (p['text'] ?? '').toString();
      if (t.startsWith('Filename: ')) {
        final String name = t.substring('Filename: '.length).trim();
        if (name.isNotEmpty) names.add(name);
      }
    }
    if (names.isEmpty) {
      return _loc(
        '（历史图片已省略，以控制上下文大小；如需再次分析请重新调用 get_images。）',
        '(Previous images omitted to keep context small; call get_images again if needed.)',
      );
    }
    const int maxNames = 10;
    final List<String> head = names.take(maxNames).toList();
    final int more = names.length - head.length;
    final String suffix = more > 0 ? ' +$more' : '';
    return _loc(
      '（已在上一轮提供图片：${head.join(", ")}$suffix；为避免重复上传，本轮起仅保留文件名。如需再次查看像素请重新调用 get_images。）',
      '(Images were provided earlier: ${head.join(", ")}$suffix; to avoid re-upload, only filenames are kept. Call get_images again if you need pixels.)',
    );
  }

  /// Replace (some) multimodal image messages with a compact placeholder so we
  /// don't re-upload base64 images on every follow-up call inside the tool loop.
  List<AIMessage> _replaceImageMessagesWithPlaceholder(
    List<AIMessage> messages, {
    required bool keepMostRecent,
    String cid = '',
    String stage = 'tool_loop_image',
    String model = '',
  }) {
    final int beforeTokens = _approxTokensForToolLoopMessages(messages);
    int lastIdx = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      final AIMessage m = messages[i];
      if (m.role == 'user' && _apiContentHasImageParts(m.apiContent)) {
        lastIdx = i;
        break;
      }
    }
    if (lastIdx < 0) return messages;

    bool changed = false;
    int replaced = 0;
    final List<AIMessage> out = List<AIMessage>.from(messages);
    for (int i = 0; i < out.length; i++) {
      if (keepMostRecent && i == lastIdx) continue;
      final AIMessage m = out[i];
      if (m.role != 'user' || !_apiContentHasImageParts(m.apiContent)) continue;
      changed = true;
      replaced += 1;
      out[i] = AIMessage(
        role: 'user',
        content: _imageMessagePlaceholderText(m),
        createdAt: m.createdAt,
      );
    }
    if (changed && cid.trim().isNotEmpty) {
      final int afterTokens = _approxTokensForToolLoopMessages(out);
      if (afterTokens < beforeTokens) {
        unawaited(
          _chatContext.logPromptTrimEvent(
            cid: cid,
            stage: stage,
            kind: 'image_placeholder',
            beforeTokens: beforeTokens,
            afterTokens: afterTokens,
            droppedMessages: replaced,
            reason: keepMostRecent ? 'keep_latest_image' : 'replace_all_images',
            model: model,
          ),
        );
      }
    }
    return changed ? out : messages;
  }

  String _compactToolContentForPrompt(
    String content, {
    required int maxToolMessageTokens,
  }) {
    if (maxToolMessageTokens <= 0) return content;
    if (content.trim().isEmpty) return content;
    final int maxBytes =
        maxToolMessageTokens * PromptBudget.approxBytesPerToken;

    if (PromptBudget.utf8Bytes(content) <= maxBytes) return content;

    // Best-effort: keep it JSON-ish if possible by trimming large lists/strings.
    try {
      final dynamic root = jsonDecode(content);
      dynamic compact(dynamic v, int depth) {
        if (depth > 6) return '…omitted…';
        if (v is String) {
          const int maxStringBytes = 12 * 1024;
          if (PromptBudget.utf8Bytes(v) <= maxStringBytes) return v;
          return PromptBudget.truncateTextByBytes(
            text: v,
            maxBytes: maxStringBytes,
            marker: '…truncated…',
          );
        }
        if (v is List) {
          const int maxList = 30;
          if (v.length <= maxList) {
            return v.map((e) => compact(e, depth + 1)).toList(growable: false);
          }
          const int head = 20;
          const int tail = 5;
          final int omitted = v.length - head - tail;
          final List<dynamic> out = <dynamic>[];
          out.addAll(v.take(head).map((e) => compact(e, depth + 1)));
          out.add('…omitted $omitted items…');
          out.addAll(v.skip(v.length - tail).map((e) => compact(e, depth + 1)));
          return out;
        }
        if (v is Map) {
          final Map<String, dynamic> out = <String, dynamic>{};
          for (final e in v.entries) {
            out[e.key.toString()] = compact(e.value, depth + 1);
          }
          return out;
        }
        return v;
      }

      final String encoded = jsonEncode(compact(root, 0));
      if (PromptBudget.utf8Bytes(encoded) <= maxBytes) return encoded;
      return PromptBudget.truncateTextByBytes(
        text: encoded,
        maxBytes: maxBytes,
        marker: '…truncated…',
      );
    } catch (_) {
      return PromptBudget.truncateTextByBytes(
        text: content,
        maxBytes: maxBytes,
        marker: '…truncated…',
      );
    }
  }

  List<AIMessage> _compactToolMessagesForPrompt(
    List<AIMessage> toolMsgs, {
    required int maxToolMessageTokens,
    String cid = '',
    String stage = 'tool_result_compact',
    String model = '',
  }) {
    if (maxToolMessageTokens <= 0) return toolMsgs;
    final int beforeTokens = _approxTokensForToolLoopMessages(toolMsgs);
    bool changed = false;
    int compactedMessages = 0;
    final List<AIMessage> out = <AIMessage>[];
    for (final m in toolMsgs) {
      if (m.role == 'tool') {
        final String compacted = _compactToolContentForPrompt(
          m.content,
          maxToolMessageTokens: maxToolMessageTokens,
        );
        if (compacted != m.content) {
          changed = true;
          compactedMessages += 1;
        }
        out.add(
          AIMessage(
            role: 'tool',
            content: compacted,
            toolCallId: m.toolCallId,
            createdAt: m.createdAt,
          ),
        );
      } else {
        out.add(m);
      }
    }
    if (changed && cid.trim().isNotEmpty) {
      final int afterTokens = _approxTokensForToolLoopMessages(out);
      if (afterTokens < beforeTokens) {
        unawaited(
          _chatContext.logPromptTrimEvent(
            cid: cid,
            stage: stage,
            kind: 'tool_result_compact',
            beforeTokens: beforeTokens,
            afterTokens: afterTokens,
            droppedMessages: compactedMessages,
            reason: 'max_tool_message_tokens:$maxToolMessageTokens',
            model: model,
          ),
        );
      }
    }
    return changed ? out : toolMsgs;
  }

  int _findToolLoopPinnedUserIndex(List<AIMessage> messages, AIMessage pinned) {
    final int byId = messages.indexWhere((m) => identical(m, pinned));
    if (byId >= 0) return byId;
    // Fallback: best-effort keep the last user message as the task prompt.
    final int idx = messages.lastIndexWhere((m) => m.role == 'user');
    return idx >= 0 ? idx : 0;
  }

  int _findOldestToolChunkStartAfter(List<AIMessage> messages, int afterIdx) {
    for (int i = afterIdx + 1; i < messages.length; i++) {
      final AIMessage m = messages[i];
      if (m.role == 'assistant' && (m.toolCalls?.isNotEmpty ?? false)) {
        return i;
      }
    }
    return -1;
  }

  int _findToolChunkEnd(List<AIMessage> messages, int chunkStart) {
    for (int i = chunkStart + 1; i < messages.length; i++) {
      if (messages[i].role == 'assistant') return i;
    }
    return messages.length;
  }

  /// Enforce a Codex-style prompt budget for the *tool loop transcript* (system
  /// + task prompt + tool call/results + internal guard rails).
  ///
  /// This prevents provider-side truncation (which often looks like “the model
  /// forgot tool results and keeps searching again”), while preserving tool call
  /// protocol invariants by removing whole tool-call chunks.
  List<AIMessage> _enforceToolLoopPromptBudget(
    List<AIMessage> messages, {
    required AIMessage pinnedUser,
    required int maxPromptTokens,
    required void Function(AIStreamEvent event)? emitEvent,
    String cid = '',
    String stage = 'tool_loop_budget',
    String model = '',
  }) {
    int totalTokens = _approxTokensForToolLoopMessages(messages);
    if (totalTokens <= maxPromptTokens) return messages;

    final int before = totalTokens;
    int droppedHistory = 0;
    int droppedChunks = 0;
    bool truncatedOldest = false;

    List<AIMessage> working = List<AIMessage>.from(messages);

    while (true) {
      totalTokens = _approxTokensForToolLoopMessages(working);
      if (totalTokens <= maxPromptTokens) break;

      int sysEnd = 0;
      while (sysEnd < working.length && working[sysEnd].role == 'system') {
        sysEnd += 1;
      }

      final int pinnedIdx = _findToolLoopPinnedUserIndex(working, pinnedUser);

      // 1) Drop oldest history messages first (between system prefix and pinned user).
      if (pinnedIdx > sysEnd) {
        working.removeAt(sysEnd);
        droppedHistory += 1;
        continue;
      }

      // 2) Drop the oldest completed tool-call chunk after the pinned user.
      final int chunkStart = _findOldestToolChunkStartAfter(working, pinnedIdx);
      if (chunkStart >= 0) {
        final int chunkEnd = _findToolChunkEnd(working, chunkStart);
        if (chunkEnd > chunkStart) {
          working.removeRange(chunkStart, chunkEnd);
          droppedChunks += 1;
          continue;
        }
      }

      // 3) Nothing left to drop safely.
      break;
    }

    // As a last resort, truncate the oldest kept non-system message content.
    totalTokens = _approxTokensForToolLoopMessages(working);
    if (totalTokens > maxPromptTokens) {
      int sysEnd = 0;
      while (sysEnd < working.length && working[sysEnd].role == 'system') {
        sysEnd += 1;
      }
      if (sysEnd < working.length) {
        final AIMessage m = working[sysEnd];
        final int maxBytes =
            (maxPromptTokens * PromptBudget.approxBytesPerToken * 0.6).floor();
        final String truncated = PromptBudget.truncateTextByBytes(
          text: m.content,
          maxBytes: maxBytes,
          marker: '…truncated…',
        );
        working[sysEnd] = AIMessage(
          role: m.role,
          content: truncated,
          createdAt: m.createdAt,
          toolCalls: m.toolCalls,
          toolCallId: m.toolCallId,
          apiContent: m.apiContent,
        );
        truncatedOldest = true;
      }
    }

    final int after = _approxTokensForToolLoopMessages(working);
    if (cid.trim().isNotEmpty && after < before) {
      unawaited(
        _chatContext.logPromptTrimEvent(
          cid: cid,
          stage: stage,
          kind: 'tool_loop_budget',
          beforeTokens: before,
          afterTokens: after,
          droppedMessages: droppedHistory,
          droppedChunks: droppedChunks,
          truncatedOldest: truncatedOldest,
          reason: 'max_prompt_tokens',
          model: model,
        ),
      );
    }
    _emitProgress(
      emitEvent,
      _loc(
        '上下文超出预算：已裁剪 history=$droppedHistory 组、tool_chunks=$droppedChunks 组，tokens≈$before → $after。',
        'Context over budget: trimmed history=$droppedHistory, tool_chunks=$droppedChunks, tokens≈$before → $after.',
      ),
    );
    return working;
  }
}

import 'dart:convert';

import 'package:screen_memo/features/ai/application/ai_settings_service.dart';

/// Prompt/context budgeting helpers (Codex-style, tokenizer-free).
///
/// - Uses a coarse lower-bound token estimate (UTF-8 bytes / 4).
/// - Designed to prevent prompt bloat and keep the tool loop responsive.
class PromptBudget {
  PromptBudget._();

  /// Same heuristic used by Codex: ~4 bytes per token as a coarse lower bound.
  static const int approxBytesPerToken = 4;

  static int utf8Bytes(String text) {
    if (text.isEmpty) return 0;
    return utf8.encode(text).length;
  }

  static int approxTokensFromBytes(int bytes) {
    if (bytes <= 0) return 0;
    return (bytes + approxBytesPerToken - 1) ~/ approxBytesPerToken;
  }

  static int approxTokensForText(String text) {
    return approxTokensFromBytes(utf8Bytes(text));
  }

  static int approxTokensForMessageJson(AIMessage message) {
    try {
      return approxTokensForText(jsonEncode(message.toJson()));
    } catch (_) {
      // Fallback: still provide a stable, monotonic estimate.
      return approxTokensForText('${message.role}\n${message.content}');
    }
  }

  static int approxTokensForMessagesJson(List<AIMessage> messages) {
    int total = 0;
    for (final m in messages) {
      total += approxTokensForMessageJson(m);
    }
    return total;
  }

  /// Keep the most recent messages that fit in [maxTokens] (approx),
  /// optionally truncating the oldest kept message if needed.
  ///
  /// Intended for trimming chat history (role/content only). Do NOT use this on
  /// tool-call protocol transcripts unless you also preserve call/result pairs.
  static List<AIMessage> keepTailUnderTokenBudget(
    List<AIMessage> messages, {
    required int maxTokens,
    bool allowTruncateOldestKept = true,
  }) {
    if (messages.isEmpty) return messages;
    if (maxTokens <= 0) return const <AIMessage>[];

    int remaining = maxTokens;
    final List<AIMessage> pickedRev = <AIMessage>[];

    for (final m in messages.reversed) {
      final int t = approxTokensForMessageJson(m);
      if (t <= remaining) {
        pickedRev.add(m);
        remaining -= t;
        continue;
      }

      if (!allowTruncateOldestKept) break;
      if (remaining <= 0) break;

      // Truncate the oldest kept message to fit the remaining budget and stop.
      final String marker = _formatTruncationMarker(remaining);
      final int fixedTokens = approxTokensForMessageJson(
        AIMessage(role: m.role, content: marker),
      );
      if (fixedTokens > remaining) break;

      int budgetBytes =
          (remaining - fixedTokens).clamp(0, 1 << 30) * approxBytesPerToken;
      String truncated = truncateTextByBytes(
        text: m.content,
        maxBytes: budgetBytes,
        marker: marker,
      );
      int truncatedTokens = approxTokensForMessageJson(
        AIMessage(role: m.role, content: truncated, createdAt: m.createdAt),
      );
      while (truncatedTokens > remaining && budgetBytes > 0) {
        budgetBytes = (budgetBytes - approxBytesPerToken).clamp(0, 1 << 30);
        truncated = truncateTextByBytes(
          text: m.content,
          maxBytes: budgetBytes,
          marker: marker,
        );
        truncatedTokens = approxTokensForMessageJson(
          AIMessage(role: m.role, content: truncated, createdAt: m.createdAt),
        );
      }
      if (truncatedTokens > remaining) break;
      pickedRev.add(
        AIMessage(role: m.role, content: truncated, createdAt: m.createdAt),
      );
      remaining = 0;
      break;
    }

    return pickedRev.reversed.toList();
  }

  static String _formatTruncationMarker(int remainingTokens) {
    final int tokens = remainingTokens.clamp(0, 1 << 30);
    return '…${tokens} tokens truncated…';
  }

  /// Truncate [text] to [maxBytes] (UTF-8), keeping head+tail and inserting [marker].
  static String truncateTextByBytes({
    required String text,
    required int maxBytes,
    required String marker,
  }) {
    if (maxBytes <= 0) return marker;
    if (text.isEmpty) return text;

    final List<int> bytes = utf8.encode(text);
    if (bytes.length <= maxBytes) return text;

    final List<int> markerBytes = utf8.encode(marker);
    if (markerBytes.length >= maxBytes) {
      // Marker itself is larger than the budget; return a clipped marker.
      final int keep = maxBytes.clamp(1, markerBytes.length);
      return utf8.decode(markerBytes.take(keep).toList(), allowMalformed: true);
    }

    final int budgetForText = maxBytes - markerBytes.length;
    final int left = budgetForText ~/ 2;
    final int right = budgetForText - left;
    final List<int> prefix = bytes.take(left).toList();
    final List<int> suffix = bytes.skip(bytes.length - right).toList();
    final List<int> out = <int>[...prefix, ...markerBytes, ...suffix];
    return utf8.decode(out, allowMalformed: true);
  }
}

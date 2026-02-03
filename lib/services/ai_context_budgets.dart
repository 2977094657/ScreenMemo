import '../models/models_dev_limits.dart';

/// Centralized, model-aware budgeting for prompt/context.
///
/// This implements a Codex-style policy:
/// - treat the model "context window" as an input cap (`promptCapTokens`)
/// - reserve headroom via an "effective window" percentage (default 95%)
/// - trigger auto-compaction only near the window (default 90%)
/// - cap individual tool outputs aggressively (Codex defaults to 10_000 bytes)
class AIContextBudgets {
  const AIContextBudgets({
    required this.model,
    required this.promptCapTokens,
    required this.effectivePromptCapTokens,
    required this.historyPromptTokens,
    required this.toolLoopPromptTokens,
    required this.toolMessageTokens,
    required this.keepRecentUncompactedTokens,
    required this.autoCompactTriggerTokens,
    required this.maxCompactionInputTokens,
    required this.maxSummaryTokens,
  });

  /// Model name (as configured / used for calls).
  final String model;

  /// Best-effort prompt capacity for the model (input/context tokens).
  final int promptCapTokens;

  /// Codex-style "effective" prompt cap (reserves headroom for overhead).
  final int effectivePromptCapTokens;

  /// Token budget for normal chat history tail included in a prompt.
  final int historyPromptTokens;

  /// Total token budget for the tool-loop transcript (system + task + tool calls/results).
  final int toolLoopPromptTokens;

  /// Per-tool-result message token cap (mainly to cap huge JSON payloads).
  final int toolMessageTokens;

  // ===== Chat-context compaction (append-only transcript -> summary) budgets =====
  /// Approx tokens of tail messages we keep un-compacted in the append-only transcript.
  final int keepRecentUncompactedTokens;

  /// Auto-compaction trigger threshold for the append-only transcript.
  final int autoCompactTriggerTokens;

  /// Token cap for each compaction batch fed into the compaction model.
  final int maxCompactionInputTokens;

  /// Target summary budget.
  final int maxSummaryTokens;

  // Previous fixed constants were tuned around a ~32k context model.
  static const int _fallbackPromptCapTokens = 32000;

  // Codex policy defaults:
  // - effective window: 95%
  // - auto compaction: 90% of the (raw) window
  // - tool output truncation: 10_000 bytes (~2500 tokens at bytes/4)
  static const int _kEffectiveContextWindowPercent = 95;
  static const int _kAutoCompactPercent = 90;
  static const int _kToolOutputMaxBytes = 10000;
  static const int _kMaxCompactionInputTokens = 20000;
  static const int _kMaxSummaryTokens = 1200;

  static AIContextBudgets forModel(String model) {
    final String m = model.trim();
    final int cap = _promptCapTokens(m);

    final int effectiveCap = ((cap * _kEffectiveContextWindowPercent) / 100)
        .floor()
        .clamp(256, 1 << 30);

    // Note: actual "history budget" should be computed at call sites as:
    // effectiveCap - (system/extras/user/tools_schema).
    // Here we only provide a generous upper bound and let callers subtract
    // reserved tokens dynamically.
    final int history = effectiveCap;
    final int toolLoop = effectiveCap;

    final int toolMsg =
        ((_kToolOutputMaxBytes + 3) ~/ 4).clamp(200, effectiveCap);

    // Compaction triggers only when we're close to the window (Codex: 90%).
    final int autoTrigger =
        ((cap * _kAutoCompactPercent) / 100).floor().clamp(256, cap);

    // Keep a small recent tail un-compacted so immediate context remains verbatim.
    final int keepUncompacted = 6000.clamp(200, effectiveCap);

    // Compaction runs in chunks; cap chunk size so we don't blow up the compact prompt.
    final int compactionBatch = _kMaxCompactionInputTokens.clamp(
      2000,
      // Ensure the compaction batch itself can fit into the model.
      (effectiveCap * 0.6).floor().clamp(2000, effectiveCap),
    );
    final int summary = _kMaxSummaryTokens.clamp(120, effectiveCap);

    return AIContextBudgets(
      model: m,
      promptCapTokens: cap,
      effectivePromptCapTokens: effectiveCap,
      historyPromptTokens: history,
      toolLoopPromptTokens: toolLoop,
      toolMessageTokens: toolMsg,
      keepRecentUncompactedTokens: keepUncompacted,
      autoCompactTriggerTokens: autoTrigger,
      maxCompactionInputTokens: compactionBatch,
      maxSummaryTokens: summary,
    );
  }

  static int _promptCapTokens(String model) {
    final String m = model.trim();
    String canonicalize(String s) {
      final String t = s.trim();
      final int slash = t.lastIndexOf('/');
      if (slash < 0) return t;
      if (slash + 1 >= t.length) return t;
      return t.substring(slash + 1).trim();
    }

    int? deriveInputCap(String name) {
      final int? ctx = ModelsDevModelLimits.contextTokens(name);
      final int? out = ModelsDevModelLimits.outputTokens(name);
      if (ctx == null || out == null) return null;
      if (ctx <= 0 || out <= 0) return null;
      final int v = ctx - out;
      if (v <= 0) return null;
      return v;
    }

    final String c = canonicalize(m);
    final int? fromLimits =
        ModelsDevModelLimits.inputTokens(m) ??
        ModelsDevModelLimits.inputTokens(c) ??
        deriveInputCap(m) ??
        deriveInputCap(c) ??
        ModelsDevModelLimits.contextTokens(m) ??
        ModelsDevModelLimits.contextTokens(c);

    final int cap = fromLimits ?? _fallbackPromptCapTokens;
    // Defensive clamp to keep math stable even if limits are bogus.
    return cap.clamp(256, 1 << 30);
  }
}

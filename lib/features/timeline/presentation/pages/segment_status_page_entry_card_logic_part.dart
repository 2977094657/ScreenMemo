part of 'segment_status_page.dart';

// ========== 单条动态卡片 JSON 合并与状态逻辑 ==========
extension _SegmentEntryCardLogicPart on _SegmentEntryCardState {
  Map<String, dynamic> _segmentWithoutResult(Map<String, dynamic> source) {
    final next = Map<String, dynamic>.from(source);
    next['output_text'] = null;
    next['structured_json'] = null;
    next['categories'] = null;
    next['has_summary'] = 0;
    return next;
  }

  Map<String, dynamic> _mergeResultIntoSegment(
    Map<String, dynamic> base,
    Map<String, dynamic> result,
  ) {
    final next = Map<String, dynamic>.from(base);
    next['output_text'] = result['output_text'];
    next['structured_json'] = result['structured_json'];
    next['categories'] = result['categories'];
    next['has_summary'] = 1;
    return next;
  }

  static void _markAutoRetryTriggered(int segmentId) {
    _SegmentEntryCardState._autoRetryTriggeredSegmentIds.add(segmentId);
    // Prevent unbounded growth in long sessions.
    while (_SegmentEntryCardState._autoRetryTriggeredSegmentIds.length >
        _SegmentEntryCardState._autoRetryRememberCap) {
      _SegmentEntryCardState._autoRetryTriggeredSegmentIds.remove(
        _SegmentEntryCardState._autoRetryTriggeredSegmentIds.first,
      );
    }
  }

  static void _markEmptySummaryDiagLogged(int segmentId) {
    _SegmentEntryCardState._emptySummaryDiagLoggedSegmentIds.add(segmentId);
    while (_SegmentEntryCardState._emptySummaryDiagLoggedSegmentIds.length >
        _SegmentEntryCardState._autoRetryRememberCap) {
      _SegmentEntryCardState._emptySummaryDiagLoggedSegmentIds.remove(
        _SegmentEntryCardState._emptySummaryDiagLoggedSegmentIds.first,
      );
    }
  }

  bool _isNonEmptyJsonLike(String? s) {
    final String t = (s ?? '').trim();
    if (t.isEmpty) return false;
    return t.toLowerCase() != 'null';
  }

  String _extractOverallSummaryFromRawStructuredJson(String? raw) {
    return extractOverallSummaryFromRaw(raw);
  }

  void _maybeLogEmptySummaryDiag({
    required int segmentId,
    required bool hasSummary,
    required bool structuredJsonTruncated,
    required bool structuredJsonParseFailed,
    required String? structuredJsonRaw,
    required String? overallSummaryPreviewRaw,
  }) {
    if (segmentId <= 0) return;
    if (!hasSummary &&
        (structuredJsonRaw ?? '').trim().isEmpty &&
        (overallSummaryPreviewRaw ?? '').trim().isEmpty) {
      return;
    }
    if (_SegmentEntryCardState._emptySummaryDiagLoggedSegmentIds.contains(
      segmentId,
    )) {
      return;
    }
    _markEmptySummaryDiagLogged(segmentId);
    final String preview = (overallSummaryPreviewRaw ?? '').trim();
    final String structured = (structuredJsonRaw ?? '').trim();
    final int previewKey = preview.indexOf('overall_summary');
    final int structuredKey = structured.indexOf('overall_summary');
    unawaited(
      FlutterLogger.nativeWarn(
        'SegmentTimelineDiag',
        'ui.entry.emptySummary segment=$segmentId hasSummary=$hasSummary '
            'structuredTruncated=$structuredJsonTruncated '
            'parseFailed=$structuredJsonParseFailed '
            'previewLen=${preview.length} structuredLen=${structured.length} '
            'previewHasKey=${previewKey >= 0} structuredHasKey=${structuredKey >= 0} '
            'previewHead=${_diagHead(preview)} structuredHead=${_diagHead(structured)}',
      ).catchError((_) {}),
    );
  }

  String _diagHead(String value, {int limit = 96}) {
    if (value.isEmpty) return '-';
    final String oneLine = value
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n');
    if (oneLine.length <= limit) return oneLine;
    return '${oneLine.substring(0, limit)}…';
  }

  void _maybeAutoRetryInvalidStructuredJson({
    required int segmentId,
    required String? structuredJsonRaw,
    required bool structuredJsonTruncated,
  }) {
    if (segmentId <= 0) return;
    if (_retrying) return;
    if (structuredJsonTruncated) {
      return; // likely truncated for CursorWindow fallback
    }
    if (!_isNonEmptyJsonLike(structuredJsonRaw)) return;
    if (_SegmentEntryCardState._autoRetryTriggeredSegmentIds.contains(
      segmentId,
    )) {
      return;
    }
    _markAutoRetryTriggered(segmentId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Best-effort: kick a forced regeneration so native can re-produce a valid structured_json.
      // This is intentionally silent to avoid spamming snackbars during scrolling.
      // ignore: unawaited_futures
      _autoRetry(segmentId);
    });
  }

  Future<void> _autoRetry(int segmentId) async {
    final int id = segmentId;
    if (id <= 0 || _retrying) return;
    int maxRetries = 1;
    try {
      maxRetries = await AISettingsService.instance
          .getSegmentsJsonAutoRetryMax();
    } catch (_) {}
    if (maxRetries <= 0) {
      _SegmentEntryCardState._autoRetryTriggeredSegmentIds.remove(id);
      return;
    }

    final previous = Map<String, dynamic>.from(_segmentData);
    int? previousCreatedAt = _lastResultCreatedAt;
    try {
      final prevRes = await widget.loadResult(id);
      final loaded = (prevRes?['created_at'] as int?) ?? 0;
      if (loaded > 0) previousCreatedAt = loaded;
    } catch (_) {}
    if (!mounted) return;

    _entryCardSetState(() {
      _retrying = true;
      _segmentData = _segmentWithoutResult(previous);
      _lastResultCreatedAt = previousCreatedAt;
      _summaryStreaming = true;
      _summaryStreamingText = _summaryGeneratingPlaceholder;
    });
    try {
      // Auto-retry should overwrite the existing invalid result.
      final n = await ScreenshotDatabase.instance.retrySegments([
        id,
      ], force: true);
      if (!mounted) return;
      final ok = n > 0;
      if (ok) {
        _startResultWatch(id, notifyToast: false);
      } else {
        // Not queued: revert UI state so we don't spin forever.
        _entryCardSetState(() {
          _retrying = false;
          _segmentData = Map<String, dynamic>.from(previous);
          _lastResultCreatedAt = previousCreatedAt;
          _summaryStreaming = false;
          _summaryStreamingText = '';
        });
      }
    } catch (_) {
      if (!mounted) return;
      _entryCardSetState(() {
        _retrying = false;
        _segmentData = Map<String, dynamic>.from(previous);
        _lastResultCreatedAt = previousCreatedAt;
        _summaryStreaming = false;
        _summaryStreamingText = '';
      });
    }
  }
}

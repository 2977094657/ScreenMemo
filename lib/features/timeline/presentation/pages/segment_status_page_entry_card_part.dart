part of 'segment_status_page.dart';

// ========== 单条动态卡片状态与生命周期 ==========
class _SegmentEntryCard extends StatefulWidget {
  final Map<String, dynamic> segment;
  final bool isLast;
  final String Function(int) fmtTime;
  final Future<List<Map<String, dynamic>>> Function(int) loadSamples;
  final Future<Map<String, dynamic>?> Function(int) loadResult;
  final Map<String, AppInfo> appInfoByPackage;
  final VoidCallback onOpenDetail;
  final Future<void> Function(List<Map<String, dynamic>>, int) openGallery;
  final Future<void> Function() onRefreshRequested;
  final bool privacyMode;
  final bool dynamicRebuildActive;

  const _SegmentEntryCard({
    super.key,
    required this.segment,
    required this.isLast,
    required this.fmtTime,
    required this.loadSamples,
    required this.loadResult,
    required this.appInfoByPackage,
    required this.onOpenDetail,
    required this.openGallery,
    required this.onRefreshRequested,
    required this.privacyMode,
    required this.dynamicRebuildActive,
  });

  @override
  State<_SegmentEntryCard> createState() => _SegmentEntryCardState();
}

class _SegmentEntryCardState extends State<_SegmentEntryCard> {
  static const int _tagMaxVisibleRows = 2;
  static const double _tagChipMinHeight = 20;
  static const double _tagChipVerticalPadding = 2;
  static const double _tagOverflowHintHeight = 18;
  static const double _tagGridMainAxisSpacing = 6;
  static const double _tagGridCrossAxisSpacing = 6;
  static const int _thumbGridCrossAxisCount = 3;
  static const double _thumbGridSpacing = 2;
  static const double _thumbVirtualGridMaxHeight = 360;
  String get _summaryGeneratingPlaceholder =>
      AppLocalizations.of(context).thinkingInProgress;
  static const int _autoRetryRememberCap = 2048;
  static final Set<int> _autoRetryTriggeredSegmentIds = <int>{};
  static final Set<int> _emptySummaryDiagLoggedSegmentIds = <int>{};

  final ScrollController _tagScrollController = ScrollController();

  bool _expanded = false;
  // 懒加载样本的本地状态，避免每项滚动时触发异步查询导致跳动
  bool _samplesLoading = false;
  bool _samplesLoaded = false;
  List<Map<String, dynamic>> _samples = const <Map<String, dynamic>>[];
  // 摘要展开/收起状态（防止固定高度无法展开）
  bool _summaryExpanded = false;
  // 重新生成操作状态
  bool _retrying = false;
  // 强制合并操作状态
  bool _forcingMerge = false;
  // 结果轮询器：点击“重新生成”后，直到拿到结果为止持续旋转提示
  Timer? _resultWatchTimer;
  Timer? _mergeWatchTimer;
  Timer? _summaryStreamTimer;
  Map<String, dynamic> _segmentData = <String, dynamic>{};
  Map<String, dynamic> _latestExternalSegment = <String, dynamic>{};
  int? _lastResultCreatedAt;
  int? _lastMergeResultCreatedAt;
  bool _summaryStreaming = false;
  String _summaryStreamingText = '';

  // part 文件需要触发 UI 刷新时统一通过该方法，避免直接访问 State.setState。
  void _entryCardSetState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _segmentData = Map<String, dynamic>.from(widget.segment);
    _latestExternalSegment = Map<String, dynamic>.from(widget.segment);
  }

  @override
  void didUpdateWidget(covariant _SegmentEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = Map<String, dynamic>.from(widget.segment);
    if (!mapEquals(incoming, _latestExternalSegment)) {
      _latestExternalSegment = Map<String, dynamic>.from(incoming);
      _segmentData = Map<String, dynamic>.from(incoming);
    }
  }

  @override
  void dispose() {
    _resultWatchTimer?.cancel();
    _mergeWatchTimer?.cancel();
    _summaryStreamTimer?.cancel();
    _tagScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int id = (_segmentData['id'] as int?) ?? 0;
    // 移除 per-item FutureBuilder，使用后端联表元数据；展开时懒加载样本
    final int sampleCount = (_segmentData['sample_count'] as int?) ?? 0;
    final int start = (_segmentData['start_time'] as int?) ?? 0;
    final int end = (_segmentData['end_time'] as int?) ?? 0;
    final String timeLabel =
        '${widget.fmtTime(start)} - ${widget.fmtTime(end)}';
    final bool merged = (_segmentData['merged_flag'] as int?) == 1;
    final String status = (_segmentData['status'] as String?) ?? '';
    final bool mergeAttempted = (_segmentData['merge_attempted'] as int?) == 1;
    final bool mergeForced = (_segmentData['merge_forced'] as int?) == 1;
    final int mergePrevId = (_segmentData['merge_prev_id'] as int?) ?? 0;
    final String mergeReason =
        (_segmentData['merge_decision_reason'] as String?)?.trim() ?? '';

    final Map<String, dynamic> resultMeta = {
      'categories': _segmentData['categories'],
      'output_text': _segmentData['output_text'],
    };
    final String? structuredJsonRaw =
        (_segmentData['structured_json'] as String?)?.toString();
    final Map<String, dynamic>? structured = _tryParseJson(structuredJsonRaw);
    final bool structuredJsonTruncated =
        (_segmentData['structured_json_truncated'] as int? ?? 0) != 0;
    final bool structuredJsonParseFailed =
        _isNonEmptyJsonLike(structuredJsonRaw) && structured == null;
    if (structuredJsonParseFailed) {
      _maybeAutoRetryInvalidStructuredJson(
        segmentId: id,
        structuredJsonRaw: structuredJsonRaw,
        structuredJsonTruncated: structuredJsonTruncated,
      );
    }
    final Set<String> aiNsfwFiles = <String>{};
    try {
      final rawTags = structured?['image_tags'];
      if (rawTags is List) {
        bool containsExactNsfw(dynamic tags) {
          if (tags == null) return false;
          if (tags is List) {
            return tags.any((t) => t.toString().trim().toLowerCase() == 'nsfw');
          }
          if (tags is String) {
            final String tt = tags.trim();
            if (tt.isEmpty) return false;
            try {
              final dynamic v = jsonDecode(tt);
              if (v is List) {
                return v.any(
                  (t) => t.toString().trim().toLowerCase() == 'nsfw',
                );
              }
              if (v is String) {
                return v
                    .split(RegExp(r'[，,;；\s]+'))
                    .any((e) => e.trim().toLowerCase() == 'nsfw');
              }
            } catch (_) {}
            return tt
                .split(RegExp(r'[，,;；\s]+'))
                .any((e) => e.trim().toLowerCase() == 'nsfw');
          }
          return false;
        }

        for (final e in rawTags) {
          if (e is! Map) continue;
          final String file = (e['file'] ?? '').toString().trim();
          if (file.isEmpty) continue;
          final String fileName = file.replaceAll('\\', '/').split('/').last;
          if (containsExactNsfw(e['tags'])) aiNsfwFiles.add(fileName);
        }
      }
    } catch (_) {}
    final String? keyAction = _extractKeyActionDetail(structured);
    final int aiRetryCount = _aiRetryCount(structured);
    final bool aiRetryFailed = _aiNeedsManualRetry(structured);
    final String aiRetryMsg = _aiRetryMessage(context, structured);
    final List<String> categories = _extractCategories(resultMeta, structured);
    final String? overallSummaryPreviewRaw =
        (_segmentData['overall_summary_preview'] as String?)?.toString();
    String computedSummary = _extractOverallSummary(structured);
    if (computedSummary.isEmpty) {
      computedSummary = _extractOverallSummaryFromRawStructuredJson(
        overallSummaryPreviewRaw,
      );
    }
    if (computedSummary.isEmpty) {
      computedSummary = _extractOverallSummaryFromRawStructuredJson(
        structuredJsonRaw,
      );
    }
    if (!_summaryStreaming && computedSummary.isEmpty) {
      _maybeLogEmptySummaryDiag(
        segmentId: id,
        hasSummary: ((_segmentData['has_summary'] as int?) ?? 0) != 0,
        structuredJsonTruncated: structuredJsonTruncated,
        structuredJsonParseFailed: structuredJsonParseFailed,
        structuredJsonRaw: structuredJsonRaw,
        overallSummaryPreviewRaw: overallSummaryPreviewRaw,
      );
    }
    final String summary = _summaryStreaming
        ? (_summaryStreamingText.isEmpty
              ? _summaryGeneratingPlaceholder
              : _summaryStreamingText)
        : computedSummary;
    final List<String> mergedParts = merged
        ? splitMergedEventSummaryParts(summary)
        : const <String>[];
    final String displaySummary = mergedParts.isNotEmpty
        ? mergedParts.first
        : summary;
    final List<String> originalSummaries = mergedParts.length > 1
        ? mergedParts.sublist(1)
        : const <String>[];

    // 错误检测：从 structured_json.error / output_text(JSON) / 关键字启发式 识别错误
    String? errorText;
    final String outputRaw =
        (resultMeta['output_text'] as String?)?.toString() ?? '';

    // 1) structured_json.error
    try {
      final err = structured?['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['msg'] ?? '').toString();
        if (msg.trim().isNotEmpty) {
          errorText = msg;
        } else {
          errorText = err.toString();
        }
      } else if (err is String && err.trim().isNotEmpty) {
        errorText = err;
      }
    } catch (_) {}

    // 2) output_text 若为 JSON 且含 error
    if (errorText == null &&
        outputRaw.isNotEmpty &&
        outputRaw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(outputRaw);
        if (decoded is Map && decoded['error'] != null) {
          final e = decoded['error'];
          if (e is Map && (e['message'] is String)) {
            errorText = (e['message'] as String);
          } else {
            errorText = e.toString();
          }
        }
      } catch (_) {}
    }

    // 3) 关键字启发式
    if (errorText == null) {
      final low = outputRaw.toLowerCase();
      if (low.contains('server_error') ||
          low.contains('request failed') ||
          low.contains('no candidates returned')) {
        errorText = outputRaw;
      }
    }

    Widget _buildErrorBanner(String text) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.error.withOpacity(0.6), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: cs.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

    // 包名：优先使用后端汇总的 app_packages_display，其次 app_packages（保证首屏就能显示 Logo）
    List<String> packages = <String>[];
    final String? appPkgsDisplay =
        _segmentData['app_packages_display'] as String?;
    final String? appPkgsRaw = _segmentData['app_packages'] as String?;
    final String? pkgSrc =
        (appPkgsDisplay != null && appPkgsDisplay.trim().isNotEmpty)
        ? appPkgsDisplay
        : appPkgsRaw;
    if (pkgSrc != null && pkgSrc.trim().isNotEmpty) {
      packages = pkgSrc
          .split(RegExp(r'[,\s]+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timeSeparator(
            context,
            label: timeLabel,
            keyActionDetail: keyAction,
            aiRetried: aiRetryCount > 0,
            aiRetryFailed: aiRetryFailed,
            aiRetryMessage: aiRetryMsg,
          ),
          const SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: packages
                    .map((pkg) => _buildAppIcon(context, pkg))
                    .toList(),
              ),
              const SizedBox(height: 8),
              _buildCategorySection(context, categories, merged),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 6),
            _buildErrorBanner(errorText!),
          ] else if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            // 根据是否超出行数动态决定是否显示“展开/收起”
            LayoutBuilder(
              builder: (context, constraints) {
                final TextStyle? textStyle = Theme.of(
                  context,
                ).textTheme.bodyMedium;
                // 仅在收起状态下检测是否溢出
                bool overflow = false;
                if (!_summaryExpanded && textStyle != null) {
                  final tp = TextPainter(
                    text: TextSpan(text: displaySummary, style: textStyle),
                    maxLines: 7,
                    ellipsis: '…',
                    textDirection: Directionality.of(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  overflow = tp.didExceedMaxLines;
                }

                // 预估 7 行高度用于折叠时裁切
                final double lineHeight =
                    (textStyle?.height ?? 1.2) * (textStyle?.fontSize ?? 14.0);
                final double collapsedHeight = lineHeight * 7.0 + 2.0;

                final md = _buildMarkdownBody(
                  context,
                  displaySummary,
                  textStyle,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryExpanded
                        ? md
                        : ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: collapsedHeight,
                            ),
                            child: ClipRect(child: md),
                          ),
                    if (overflow || _summaryExpanded)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(
                            () => _summaryExpanded = !_summaryExpanded,
                          ),
                          child: Text(
                            _summaryExpanded
                                ? AppLocalizations.of(context).collapse
                                : AppLocalizations.of(context).expandMore,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (status == 'completed' &&
              (mergeAttempted ||
                  mergeForced ||
                  mergeReason.isNotEmpty ||
                  _forcingMerge ||
                  merged)) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                final TextStyle? titleStyle = Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
                final TextStyle? reasonStyle = Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);

                final l10n = AppLocalizations.of(context);
                final String state = _forcingMerge
                    ? l10n.mergeStatusMerging
                    : (merged
                          ? l10n.mergeStatusMerged
                          : (mergeForced
                                ? (mergeAttempted
                                      ? l10n.forceMergeFailed
                                      : l10n.mergeStatusForceRequested)
                                : (mergeAttempted
                                      ? l10n.mergeStatusNotMerged
                                      : l10n.mergeStatusPending)));
                final String reasonText = mergeReason.isNotEmpty
                    ? mergeReason
                    : (_forcingMerge ? l10n.mergeStatusMergingReason : '');
                final bool canForce =
                    !_forcingMerge &&
                    !merged &&
                    mergeAttempted &&
                    mergePrevId > 0;

                return _buildMergeStatusDropdown(
                  context,
                  segmentId: id,
                  state: state,
                  reasonText: reasonText,
                  titleStyle: titleStyle,
                  reasonStyle: reasonStyle,
                  canForce: canForce,
                  originalSummaries: originalSummaries,
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: sampleCount <= 0
                    ? null
                    : () async {
                        setState(() => _expanded = !_expanded);
                        if (_expanded && !_samplesLoaded && !_samplesLoading) {
                          setState(() => _samplesLoading = true);
                          try {
                            final loaded = await widget.loadSamples(id);
                            setState(() {
                              _samples = loaded;
                              _samplesLoaded = true;
                            });
                          } catch (_) {
                          } finally {
                            if (mounted)
                              setState(() => _samplesLoading = false);
                          }
                        }
                      },
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  _expanded
                      ? AppLocalizations.of(
                          context,
                        ).hideImagesCount(sampleCount)
                      : AppLocalizations.of(
                          context,
                        ).viewImagesCount(sampleCount),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: widget.dynamicRebuildActive
                    ? '全量重建进行中，已禁止单条重新生成'
                    : AppLocalizations.of(context).actionRegenerate,
                onPressed: (_retrying || widget.dynamicRebuildActive)
                    ? null
                    : () async {
                        await _retry();
                      },
                icon: _retrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined, size: 18),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: AppLocalizations.of(context).actionCopy,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  final l10n = AppLocalizations.of(context);
                  final buffer = StringBuffer()
                    ..writeln(l10n.timeRangeLabel(timeLabel))
                    ..writeln(l10n.statusLabel(status));
                  if (merged) buffer.writeln(l10n.tagMergedCopy);
                  if (categories.isNotEmpty)
                    buffer.writeln(l10n.categoriesLabel(categories.join(', ')));
                  if (errorText != null && errorText!.trim().isNotEmpty) {
                    buffer.writeln(l10n.errorLabel(errorText!));
                  } else if (summary.trim().isNotEmpty) {
                    buffer.writeln(l10n.summaryLabel(summary));
                  }
                  await Clipboard.setData(
                    ClipboardData(text: buffer.toString()),
                  );
                  if (!mounted) return;
                  UINotifier.success(
                    context,
                    AppLocalizations.of(context).copySuccess,
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip:
                    Localizations.localeOf(
                      context,
                    ).languageCode.toLowerCase().startsWith('zh')
                    ? '请求/响应'
                    : 'Request/Response',
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                onPressed: () async {
                  await _showAiRequestResponseSheet(id, timeLabel: timeLabel);
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: AppLocalizations.of(context).deleteEventTooltip,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  await _confirmAndDelete();
                },
              ),
            ],
          ),
          // 关键图片 UI 暂时隐藏：仅移除展示，不影响功能数据
          if (_expanded)
            (_samplesLoading
                ? const SizedBox(
                    height: 60,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : (_samples.isNotEmpty
                      ? _buildThumbGrid(
                          context,
                          _samples,
                          aiNsfwFiles: aiNsfwFiles,
                        )
                      : const SizedBox.shrink())),
          if (!widget.isLast) ...[
            const SizedBox(height: AppTheme.spacing3),
            _buildSeparator(context),
            const SizedBox(height: AppTheme.spacing3),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_info.dart';
import '../pages/daily_summary_page.dart';
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';
import '../utils/merged_event_summary.dart';
import 'screenshot_image_widget.dart';
import 'screenshot_style_tab_bar.dart';
import 'ui_components.dart';
import 'ui_dialog.dart';

String _dateKeyFromMillis(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final String y = dt.year.toString().padLeft(4, '0');
  final String m = dt.month.toString().padLeft(2, '0');
  final String d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 按“日期 Tab + 段落卡片”展示的时间轴视图（样式对齐动态事件页）。
class SegmentTimelineTabView extends StatefulWidget {
  final List<Map<String, dynamic>> segments;
  final bool onlyNoSummary;
  final bool autoWatching;
  final Map<String, AppInfo> appInfoByPackage;
  final String Function(int) fmtTime;
  final Future<List<Map<String, dynamic>>> Function(int) loadSamples;
  final Future<Map<String, dynamic>?> Function(int) loadResult;
  final void Function(Map<String, dynamic>) onOpenDetail;
  final Future<void> Function(List<Map<String, dynamic>>, int) openGallery;
  final Widget header;
  final bool showHeader;
  final Future<void> Function() onRefreshRequested;
  final bool privacyMode;
  final int maxVisibleDayTabs;
  final bool isLoadingMoreDays;
  final bool noMoreOlderSegments;
  final Future<void> Function()? onLastDayTabReached;
  final bool showDailySummaryCard;
  final Future<bool> Function(int segmentId)? onRegenerate;

  const SegmentTimelineTabView({
    super.key,
    required this.segments,
    required this.onlyNoSummary,
    required this.autoWatching,
    required this.appInfoByPackage,
    required this.fmtTime,
    required this.loadSamples,
    required this.loadResult,
    required this.onOpenDetail,
    required this.openGallery,
    required this.header,
    this.showHeader = true,
    required this.onRefreshRequested,
    required this.privacyMode,
    required this.maxVisibleDayTabs,
    required this.isLoadingMoreDays,
    required this.noMoreOlderSegments,
    this.onLastDayTabReached,
    this.showDailySummaryCard = true,
    this.onRegenerate,
  });

  @override
  State<SegmentTimelineTabView> createState() => _SegmentTimelineTabViewState();
}

class _SegmentTimelineTabViewState extends State<SegmentTimelineTabView>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> segments = widget.segments;

    if (segments.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing4,
              vertical: AppTheme.spacing1,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (widget.showHeader) widget.header,
                  if (widget.showHeader) const SizedBox(height: 8),
                  if (widget.onlyNoSummary && widget.autoWatching)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        AppLocalizations.of(context).autoWatchingHint,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing6,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_note_outlined,
                      size: 64,
                      color: AppTheme.mutedForeground.withOpacity(0.5),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      AppLocalizations.of(context).noEvents,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.mutedForeground,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        AppLocalizations.of(context).noEventsSubtitle,
                        style: const TextStyle(color: AppTheme.mutedForeground),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final seg in segments) {
      final k = _dateKeyFromMillis((seg['start_time'] as int?) ?? 0);
      grouped.putIfAbsent(k, () => <Map<String, dynamic>>[]).add(seg);
    }
    final List<String> keys = grouped.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    final List<String> orderedAll = keys.reversed.toList();

    final int visibleCount = math.min(
      widget.maxVisibleDayTabs,
      orderedAll.length,
    );
    final List<String> ordered = orderedAll.take(visibleCount).toList();

    if (_tabController == null || _tabController!.length != ordered.length) {
      final int currentIndex = _tabController?.index ?? 0;
      _tabController?.dispose();

      final int initialIndex = ordered.isEmpty
          ? 0
          : currentIndex.clamp(0, ordered.length - 1);
      _tabController = TabController(
        length: ordered.length,
        vsync: this,
        initialIndex: initialIndex,
      );
    }

    return Column(
      children: [
        Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            final bool hasHiddenTabs =
                widget.maxVisibleDayTabs < orderedAll.length;
            final bool canLoadMoreFromDb =
                !widget.onlyNoSummary &&
                widget.onLastDayTabReached != null &&
                !widget.noMoreOlderSegments;
            final bool showLoadMoreButton =
                widget.onLastDayTabReached != null &&
                (hasHiddenTabs || canLoadMoreFromDb);
            final bool isLoadingMore = widget.isLoadingMoreDays;

            return SizedBox(
              height: 32,
              child: Transform.translate(
                offset: const Offset(0, -2),
                child: Row(
                  children: [
                    Expanded(
                      child: ScreenshotStyleTabBar(
                        controller: _tabController,
                        padding: const EdgeInsets.only(left: AppTheme.spacing2),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        indicatorInsets: const EdgeInsets.symmetric(
                          horizontal: 4.0,
                        ),
                        tabs: [
                          for (final k in ordered)
                            Tab(
                              text: (() {
                                final parts = k.split('-');
                                if (parts.length == 3) {
                                  final y = int.tryParse(parts[0]) ?? 1970;
                                  final m = int.tryParse(parts[1]) ?? 1;
                                  final d = int.tryParse(parts[2]) ?? 1;
                                  final dt = DateTime(y, m, d);
                                  final now = DateTime.now();
                                  bool sameDay(DateTime a, DateTime b) =>
                                      a.year == b.year &&
                                      a.month == b.month &&
                                      a.day == b.day;
                                  final int c =
                                      (grouped[k] ??
                                              const <Map<String, dynamic>>[])
                                          .length;
                                  if (sameDay(dt, now)) {
                                    return l10n.dayTabToday(c);
                                  }
                                  if (sameDay(
                                    dt,
                                    now.subtract(const Duration(days: 1)),
                                  )) {
                                    return l10n.dayTabYesterday(c);
                                  }
                                  return l10n.dayTabMonthDayCount(
                                    dt.month,
                                    dt.day,
                                    c,
                                  );
                                }
                                return '$k ${(grouped[k] ?? const <Map<String, dynamic>>[]).length}';
                              })(),
                            ),
                        ],
                      ),
                    ),
                    if (showLoadMoreButton)
                      Padding(
                        padding: const EdgeInsets.only(left: AppTheme.spacing2),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing2,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed:
                              (widget.onLastDayTabReached == null ||
                                  isLoadingMore)
                              ? null
                              : () {
                                  widget.onLastDayTabReached!.call();
                                },
                          icon: isLoadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.more_horiz, size: 18),
                          label: Text(l10n.loadMore),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final k in ordered)
                ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing4,
                    vertical: AppTheme.spacing1,
                  ),
                  children: [
                    if (widget.showHeader) widget.header,
                    if (widget.showHeader) const SizedBox(height: 8),
                    if (widget.showDailySummaryCard)
                      _DailySummaryEntryCard(dateKey: k),
                    if (widget.showDailySummaryCard)
                      const SizedBox(height: AppTheme.spacing2),
                    ...List.generate(
                      (grouped[k] ?? const <Map<String, dynamic>>[]).length,
                      (i) => SegmentEntryCard(
                        segment: grouped[k]![i],
                        isLast: i == grouped[k]!.length - 1,
                        fmtTime: widget.fmtTime,
                        loadSamples: widget.loadSamples,
                        loadResult: widget.loadResult,
                        appInfoByPackage: widget.appInfoByPackage,
                        onOpenDetail: () => widget.onOpenDetail(grouped[k]![i]),
                        openGallery: widget.openGallery,
                        onRefreshRequested: widget.onRefreshRequested,
                        privacyMode: widget.privacyMode,
                        onRegenerate: widget.onRegenerate,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailySummaryEntryCard extends StatelessWidget {
  final String dateKey;

  const _DailySummaryEntryCard({required this.dateKey});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_note_outlined),
        title: Text(AppLocalizations.of(context).dailySummaryShort),
        subtitle: Text(AppLocalizations.of(context).viewOrGenerateForDay),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DailySummaryPage(dateKey: dateKey),
            ),
          );
        },
      ),
    );
  }
}

/// 单条段落卡片（样式对齐动态事件页）。
class SegmentEntryCard extends StatefulWidget {
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
  final Future<bool> Function(int segmentId)? onRegenerate;

  const SegmentEntryCard({
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
    this.onRegenerate,
  });

  @override
  State<SegmentEntryCard> createState() => _SegmentEntryCardState();
}

class _SegmentEntryCardState extends State<SegmentEntryCard> {
  static const int _tagMaxVisibleRows = 2;
  static const double _tagChipMinHeight = 20;
  static const double _tagChipVerticalPadding = 2;
  static const double _tagOverflowHintHeight = 18;
  static const double _tagGridMainAxisSpacing = 6;
  static const double _tagGridCrossAxisSpacing = 6;
  static const int _thumbGridCrossAxisCount = 3;
  static const double _thumbGridSpacing = 2;
  static const double _thumbVirtualGridMaxHeight = 360;
  static const String _summaryGeneratingPlaceholder = '模型正在思考，请稍候…';

  final ScrollController _tagScrollController = ScrollController();

  bool _expanded = false;
  bool _samplesLoading = false;
  bool _samplesLoaded = false;
  List<Map<String, dynamic>> _samples = const <Map<String, dynamic>>[];
  bool _summaryExpanded = false;
  bool _retrying = false;
  bool _forcingMerge = false;
  Timer? _resultWatchTimer;
  Timer? _mergeWatchTimer;
  Timer? _summaryStreamTimer;
  Map<String, dynamic> _segmentData = <String, dynamic>{};
  Map<String, dynamic> _latestExternalSegment = <String, dynamic>{};
  int? _lastResultCreatedAt;
  int? _lastMergeResultCreatedAt;
  bool _summaryStreaming = false;
  String _summaryStreamingText = '';

  @override
  void initState() {
    super.initState();
    _segmentData = Map<String, dynamic>.from(widget.segment);
    _latestExternalSegment = Map<String, dynamic>.from(widget.segment);
  }

  @override
  void didUpdateWidget(covariant SegmentEntryCard oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    final int id = (_segmentData['id'] as int?) ?? 0;
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
    final Map<String, dynamic>? structured = _tryParseJson(
      _segmentData['structured_json'] as String?,
    );

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
    final List<String> categories = _extractCategories(resultMeta, structured);
    final String computedSummary = _extractOverallSummary(
      resultMeta,
      structured,
    );
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

    String? errorText;
    final String outputRaw =
        (resultMeta['output_text'] as String?)?.toString() ?? '';
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
    if (errorText == null) {
      final low = outputRaw.toLowerCase();
      if (low.contains('server_error') ||
          low.contains('request failed') ||
          low.contains('no candidates returned')) {
        errorText = outputRaw;
      }
    }

    Widget buildErrorBanner(String text) {
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

    return GestureDetector(
      onTap: widget.onOpenDetail,
      child: Padding(
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
              buildErrorBanner(errorText),
            ] else if (summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, constraints) {
                  final TextStyle? textStyle = Theme.of(
                    context,
                  ).textTheme.bodyMedium;
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

                  final double lineHeight =
                      (textStyle?.height ?? 1.2) *
                      (textStyle?.fontSize ?? 14.0);
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

                  final String state = _forcingMerge
                      ? '强制合并中…'
                      : (merged
                            ? '已合并'
                            : (mergeForced
                                  ? (mergeAttempted ? '强制合并失败' : '已请求强制合并')
                                  : (mergeAttempted ? '未合并' : '待判定')));
                  final String reasonText = mergeReason.isNotEmpty
                      ? mergeReason
                      : (_forcingMerge ? '正在合并，请稍候…' : '');
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
                          if (_expanded &&
                              !_samplesLoaded &&
                              !_samplesLoading) {
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
                if (widget.onRegenerate != null) ...[
                  IconButton(
                    tooltip: AppLocalizations.of(context).actionRegenerate,
                    onPressed: _retrying ? null : () async => _retry(),
                    icon: _retrying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_outlined, size: 18),
                  ),
                  const SizedBox(width: 8),
                ],
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
                      buffer.writeln(
                        l10n.categoriesLabel(categories.join(', ')),
                      );
                    if (errorText != null && errorText.trim().isNotEmpty) {
                      buffer.writeln(l10n.errorLabel(errorText));
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
              ],
            ),
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
      ),
    );
  }

  Future<void> _openMergedOriginalEventsDrawer(
    BuildContext context, {
    required List<String> originals,
  }) async {
    if (originals.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final TextStyle? bodyStyle = Theme.of(ctx).textTheme.bodyMedium;
        final cs = Theme.of(ctx).colorScheme;

        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusLg),
            topRight: Radius.circular(AppTheme.radiusLg),
          ),
          child: ColoredBox(
            color: cs.surface,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.78,
                child: DefaultTabController(
                  length: originals.length,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      ScreenshotStyleTabBar(
                        height: kTextTabBarHeight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing3,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        tabs: [
                          for (int i = 0; i < originals.length; i++)
                            Tab(text: l10n.mergedOriginalEventTitle(i + 1)),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Expanded(
                        child: TabBarView(
                          children: originals
                              .map((part) {
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppTheme.spacing4,
                                    0,
                                    AppTheme.spacing4,
                                    AppTheme.spacing6,
                                  ),
                                  child: _buildMarkdownBody(
                                    ctx,
                                    part,
                                    bodyStyle,
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _timeSeparator(
    BuildContext context, {
    required String label,
    String? keyActionDetail,
  }) {
    final Color actionColor = AppTheme.warning;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: Center(
            child: Text(label, style: DefaultTextStyle.of(context).style),
          ),
        ),
        if (keyActionDetail != null && keyActionDetail.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Center(
              child: _buildMarkdownBody(
                context,
                keyActionDetail,
                DefaultTextStyle.of(
                  context,
                ).style.copyWith(color: actionColor),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSeparator(BuildContext context) {
    final Color base =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      height: 1,
      color: base.withOpacity(0.2),
    );
  }

  Widget _buildAppIcon(BuildContext context, String package) {
    final app = widget.appInfoByPackage[package];
    if (app != null && app.icon != null && app.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          app.icon!,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.apps, size: 14),
    );
  }

  Widget _buildChip(BuildContext context, String text) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = dark ? AppTheme.darkSelectedAccent : AppTheme.info;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: fg.withOpacity(0.35), width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: fg,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  MarkdownBody _buildMarkdownBody(
    BuildContext context,
    String data,
    TextStyle? textStyle,
  ) {
    return MarkdownBody(
      data: data,
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(p: textStyle),
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      },
    );
  }

  Widget _buildMergeStatusDropdown(
    BuildContext context, {
    required int segmentId,
    required String state,
    required String reasonText,
    required TextStyle? titleStyle,
    required TextStyle? reasonStyle,
    required bool canForce,
    required List<String> originalSummaries,
  }) {
    final l10n = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color bg = cs.surfaceContainerHighest.withOpacity(0.28);
    final Color border = cs.outline.withOpacity(0.22);

    final bool canOpenOriginals = originalSummaries.isNotEmpty;
    final TextStyle titleLinkStyle = (titleStyle ?? const TextStyle()).copyWith(
      color: cs.primary,
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('seg:$segmentId:mergeStatus'),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: 0,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTheme.spacing3,
            0,
            AppTheme.spacing3,
            AppTheme.spacing3,
          ),
          leading: Icon(Icons.merge_type, size: 16, color: cs.onSurfaceVariant),
          title: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: canOpenOriginals
                      ? () async => _openMergedOriginalEventsDrawer(
                          context,
                          originals: originalSummaries,
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: state),
                          if (canOpenOriginals) const TextSpan(text: ' · '),
                          if (canOpenOriginals)
                            TextSpan(
                              text: l10n.mergedOriginalEventsTitle(
                                originalSummaries.length,
                              ),
                            ),
                        ],
                      ),
                      style: canOpenOriginals ? titleLinkStyle : titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              if (_forcingMerge)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (canForce)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async => _forceMerge(),
                  child: const Text('强制合并'),
                ),
            ],
          ),
          children: [
            if (reasonText.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(reasonText, style: reasonStyle),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMergedTagChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.warning.withOpacity(0.45), width: 1),
      ),
      child: Text(
        AppLocalizations.of(context).mergedEventTag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.warning,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    List<String> categories,
    bool merged,
  ) {
    final int total = categories.length + (merged ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();

    final List<Widget> chips = <Widget>[
      if (merged) _buildMergedTagChip(context),
      ...categories.map((c) => _buildChip(context, c)),
    ];

    final TextStyle measureStyle = const TextStyle(
      fontSize: 12,
      height: 1.0,
      fontWeight: FontWeight.w500,
    );
    final TextScaler textScaler = MediaQuery.textScalerOf(context);

    double estimateChipHeight() {
      final tp = TextPainter(
        text: TextSpan(text: '测试', style: measureStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      final double contentHeight = tp.height + _tagChipVerticalPadding * 2;
      return math.max(_tagChipMinHeight, contentHeight).ceilToDouble();
    }

    double estimateChipWidth(String label, double maxWidth) {
      final double horizontalPadding = AppTheme.spacing2;
      final double maxTextWidth = math.max(0, maxWidth - horizontalPadding * 2);
      final tp = TextPainter(
        text: TextSpan(text: label, style: measureStyle),
        maxLines: 1,
        ellipsis: '…',
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout(maxWidth: maxTextWidth);
      final double w = tp.width + horizontalPadding * 2;
      return w.clamp(0, maxWidth);
    }

    int estimateRows(List<String> labels, double maxWidth) {
      if (labels.isEmpty) return 0;
      final double spacing = _tagGridCrossAxisSpacing;
      int rows = 1;
      double rowWidth = 0;
      for (final label in labels) {
        final double w = estimateChipWidth(label, maxWidth);
        if (rowWidth == 0) {
          rowWidth = w;
          continue;
        }
        if (rowWidth + spacing + w <= maxWidth) {
          rowWidth += spacing + w;
        } else {
          rows += 1;
          rowWidth = w;
        }
      }
      return rows;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final List<String> labels = <String>[
          if (merged) AppLocalizations.of(context).mergedEventTag,
          ...categories,
        ];
        final int rows = estimateRows(labels, maxWidth);

        if (rows <= _tagMaxVisibleRows) {
          return Wrap(
            spacing: _tagGridCrossAxisSpacing,
            runSpacing: _tagGridMainAxisSpacing,
            alignment: WrapAlignment.start,
            children: chips,
          );
        }

        final double chipHeight = estimateChipHeight();
        final double viewportHeight =
            chipHeight * _tagMaxVisibleRows +
            _tagGridMainAxisSpacing * (_tagMaxVisibleRows - 1);
        final theme = Theme.of(context);
        final Color hintColor =
            theme.colorScheme.onSurfaceVariant.withOpacity(0.45);

        // 最多显示两行，超过则在内部滚动，并用视觉提示提醒可滚动（无文字）。
        return SizedBox(
          height: viewportHeight + _tagOverflowHintHeight,
          child: Column(
            children: [
              SizedBox(
                height: viewportHeight,
                child: Scrollbar(
                  controller: _tagScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(3),
                  child: SingleChildScrollView(
                    controller: _tagScrollController,
                    primary: false,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    child: Wrap(
                      spacing: _tagGridCrossAxisSpacing,
                      runSpacing: _tagGridMainAxisSpacing,
                      alignment: WrapAlignment.start,
                      children: chips,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  height: _tagOverflowHintHeight,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: hintColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThumbGrid(
    BuildContext context,
    List<Map<String, dynamic>> samples, {
    Set<String> aiNsfwFiles = const <String>{},
  }) {
    if (samples.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final double cellWidth =
            (availableWidth -
                _thumbGridSpacing * (_thumbGridCrossAxisCount - 1)) /
            _thumbGridCrossAxisCount;
        const double childAspectRatio = 9 / 16;
        final double cellHeight = cellWidth / childAspectRatio;

        final int rows = (samples.length / _thumbGridCrossAxisCount).ceil();
        final double naturalHeight =
            rows * cellHeight + math.max(0, rows - 1) * _thumbGridSpacing;
        final double maxHeight = math.min(
          _thumbVirtualGridMaxHeight,
          MediaQuery.of(context).size.height * 0.55,
        );
        final double viewportHeight = math.min(naturalHeight, maxHeight);

        final double dpr = MediaQuery.of(context).devicePixelRatio;
        final int targetWidthPx = (cellWidth * dpr).round().clamp(96, 1024);

        return SizedBox(
          height: viewportHeight,
          child: Scrollbar(
            thumbVisibility: naturalHeight > viewportHeight,
            child: GridView.builder(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: samples.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _thumbGridCrossAxisCount,
                crossAxisSpacing: _thumbGridSpacing,
                mainAxisSpacing: _thumbGridSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (ctx, i) {
                final s = samples[i];
                final path = (s['file_path'] as String?) ?? '';
                final pageUrl = (s['page_url'] as String?) ?? '';

                if (path.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    ),
                  );
                }

                final String fileName = path
                    .replaceAll('\\', '/')
                    .split('/')
                    .last;
                final bool aiNsfw = aiNsfwFiles.contains(fileName);

                return ScreenshotImageWidget(
                  file: File(path),
                  privacyMode: widget.privacyMode,
                  extraNsfwMask: aiNsfw,
                  pageUrl: pageUrl.isNotEmpty ? pageUrl : null,
                  targetWidth: targetWidthPx,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.openGallery(samples, i),
                  showNsfwButton: true,
                  errorText: 'Image Error',
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _retry() async {
    final int id = (_segmentData['id'] as int?) ?? 0;
    if (id <= 0 || _retrying || widget.onRegenerate == null) return;
    final previous = Map<String, dynamic>.from(_segmentData);
    int? previousCreatedAt = _lastResultCreatedAt;
    try {
      final prevRes = await widget.loadResult(id);
      final loaded = (prevRes?['created_at'] as int?) ?? 0;
      if (loaded > 0) previousCreatedAt = loaded;
    } catch (_) {}
    if (!mounted) return;
    final cleared = _segmentWithoutResult(previous);
    setState(() {
      _retrying = true;
      _segmentData = cleared;
      _lastResultCreatedAt = previousCreatedAt;
      _summaryStreaming = true;
      _summaryStreamingText = _summaryGeneratingPlaceholder;
    });
    try {
      final ok = await widget.onRegenerate!.call(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? AppLocalizations.of(context).regenerationQueued
                : AppLocalizations.of(context).alreadyQueuedOrFailed,
          ),
        ),
      );
      if (ok) {
        try {
          final res = await widget.loadResult(id);
          final int newCreatedAt = (res?['created_at'] as int?) ?? 0;
          if (res != null &&
              (_lastResultCreatedAt == null ||
                  newCreatedAt <= 0 ||
                  newCreatedAt > _lastResultCreatedAt!)) {
            _applyNewResult(res, newCreatedAt > 0 ? newCreatedAt : null);
            await widget.onRefreshRequested();
            return;
          }
        } catch (_) {}
        _startResultWatch(id);
        return;
      }
      setState(() {
        _retrying = false;
        _segmentData = Map<String, dynamic>.from(previous);
        _lastResultCreatedAt = previousCreatedAt;
        _summaryStreaming = false;
        _summaryStreamingText = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _segmentData = Map<String, dynamic>.from(previous);
        _lastResultCreatedAt = previousCreatedAt;
        _summaryStreaming = false;
        _summaryStreamingText = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).retryFailed)),
      );
    }
  }

  Future<void> _forceMerge() async {
    final int id = (_segmentData['id'] as int?) ?? 0;
    if (id <= 0 || _forcingMerge) return;
    final int prevId = (_segmentData['merge_prev_id'] as int?) ?? 0;
    if (prevId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可合并的上一事件')));
      return;
    }

    final bool confirmed =
        await showUIDialog<bool>(
          context: context,
          title: '强制合并',
          message: '将与上一事件强制合并，并覆盖当前事件总结，同时删除上一事件。此操作无法撤销，是否继续？',
          actions: [
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).dialogCancel,
              style: UIDialogActionStyle.normal,
              result: false,
            ),
            const UIDialogAction<bool>(
              text: '强制合并',
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
          barrierDismissible: true,
        ) ??
        false;
    if (!confirmed) return;

    int? previousCreatedAt = _lastMergeResultCreatedAt;
    try {
      final prevRes = await widget.loadResult(id);
      final loaded = (prevRes?['created_at'] as int?) ?? 0;
      if (loaded > 0) previousCreatedAt = loaded;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _forcingMerge = true;
      _segmentData = Map<String, dynamic>.from(_segmentData)
        ..['merge_forced'] = 1
        ..['merge_decision_reason'] = '已请求强制合并（排队中）';
      _lastMergeResultCreatedAt = previousCreatedAt;
    });

    try {
      final ok = await ScreenshotDatabase.instance.forceMergeSegment(
        id,
        prevId: prevId,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _forcingMerge = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('强制合并入队失败')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('强制合并已入队')));
      _startMergeWatch(id, previousCreatedAt);
    } catch (_) {
      if (!mounted) return;
      setState(() => _forcingMerge = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('强制合并失败')));
    }
  }

  void _startResultWatch(int id) {
    _resultWatchTimer?.cancel();
    _resultWatchTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final res = await widget.loadResult(id);
        if (!mounted) return;
        if (res != null) {
          final int newCreatedAt = (res['created_at'] as int?) ?? 0;
          if (_lastResultCreatedAt != null &&
              newCreatedAt > 0 &&
              newCreatedAt <= _lastResultCreatedAt!) {
            return;
          }
          t.cancel();
          _applyNewResult(res, newCreatedAt > 0 ? newCreatedAt : null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).generateSuccess),
            ),
          );
          try {
            await widget.onRefreshRequested();
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  void _startMergeWatch(int id, int? previousCreatedAt) {
    _mergeWatchTimer?.cancel();
    _mergeWatchTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final res = await widget.loadResult(id);
        if (!mounted) return;
        if (res == null) return;
        final int newCreatedAt = (res['created_at'] as int?) ?? 0;
        if (previousCreatedAt != null &&
            newCreatedAt > 0 &&
            newCreatedAt <= previousCreatedAt) {
          return;
        }
        t.cancel();
        setState(() => _forcingMerge = false);
        _applyNewResult(res, newCreatedAt > 0 ? newCreatedAt : null);
        try {
          await widget.onRefreshRequested();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('合并完成')));
      } catch (_) {}
    });
  }

  void _applyNewResult(Map<String, dynamic> res, int? createdAt) {
    final merged = _mergeResultIntoSegment(_segmentData, res);
    final String finalSummary = _extractOverallSummary({
      'output_text': merged['output_text'],
      'categories': merged['categories'],
    }, _tryParseJson(merged['structured_json'] as String?));
    setState(() {
      _retrying = false;
      _segmentData = merged;
      _lastResultCreatedAt = createdAt ?? _lastResultCreatedAt;
      _summaryStreaming = true;
      _summaryStreamingText = '';
    });
    _latestExternalSegment = Map<String, dynamic>.from(merged);
    _beginSummaryStreaming(finalSummary);
  }

  void _beginSummaryStreaming(String target) {
    _summaryStreamTimer?.cancel();
    if (!mounted) return;
    if (target.trim().isEmpty) {
      setState(() {
        _summaryStreaming = false;
        _summaryStreamingText = target;
      });
      return;
    }
    setState(() {
      _summaryStreaming = true;
      _summaryStreamingText = '';
    });
    const int chunkSize = 24;
    int idx = 0;
    _summaryStreamTimer = Timer.periodic(const Duration(milliseconds: 35), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      idx = math.min(idx + chunkSize, target.length);
      final String next = target.substring(0, idx);
      setState(() {
        _summaryStreamingText = next;
      });
      if (idx >= target.length) {
        timer.cancel();
        setState(() {
          _summaryStreaming = false;
        });
      }
    });
  }

  Map<String, dynamic>? _tryParseJson(String? s) {
    if (s == null) return null;
    try {
      final obj = jsonDecode(s);
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}
    return null;
  }

  String? _extractKeyActionDetail(Map<String, dynamic>? sj) {
    if (sj == null) return null;
    final ka = sj['key_actions'];
    if (ka is List && ka.isNotEmpty) {
      final first = ka.first;
      if (first is Map && first['detail'] is String)
        return (first['detail'] as String);
      if (first is String) return first;
    } else if (ka is Map && ka['detail'] is String) {
      return ka['detail'] as String;
    } else if (ka is String) {
      return ka;
    }
    return null;
  }

  List<String> _extractCategories(
    Map<String, dynamic>? result,
    Map<String, dynamic>? sj,
  ) {
    final List<String> out = <String>[];
    final raw = result?['categories'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final obj = jsonDecode(raw);
        if (obj is List) {
          out.addAll(obj.map((e) => e.toString()));
        } else {
          out.addAll(
            raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty),
          );
        }
      } catch (_) {
        out.addAll(
          raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty),
        );
      }
    }
    final sc = sj?['categories'];
    if (sc is List) {
      out.addAll(sc.map((e) => e.toString()));
    } else if (sc is String && sc.trim().isNotEmpty) {
      out.addAll(sc.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty));
    }
    final set = <String>{};
    final res = <String>[];
    for (final c in out) {
      final v = c.trim();
      if (v.isEmpty) continue;
      if (set.add(v)) res.add(v);
    }
    return res;
  }

  String _extractOverallSummary(
    Map<String, dynamic>? result,
    Map<String, dynamic>? sj,
  ) {
    final v = sj?['overall_summary'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    final out = (result?['output_text'] as String?)?.trim() ?? '';
    return out.toLowerCase() == 'null' ? '' : out;
  }
}

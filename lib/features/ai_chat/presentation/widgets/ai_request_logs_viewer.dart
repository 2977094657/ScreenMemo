import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:talker/talker.dart';

import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/models/ai_request_log.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/features/ai/application/ai_request_log_parser.dart';
import 'package:screen_memo/core/utils/model_icon_utils.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_request_logs_action.dart';
import 'package:screen_memo/features/gallery/presentation/widgets/screenshot_image_widget.dart';
import 'package:screen_memo/core/widgets/screenshot_style_tab_bar.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';

class AIRequestLogsViewer extends StatefulWidget {
  const AIRequestLogsViewer._({
    super.key,
    required this.traces,
    required this.leadingOrphans,
    required this.rawFallbackText,
    this.title,
    this.scrollable = true,
    this.maxHeight,
    this.emptyText,
    this.actions = const <AIRequestLogsAction>[],
    this.showRawResponsePanel = false,
  });

  factory AIRequestLogsViewer.traces({
    Key? key,
    required List<AIRequestTrace> traces,
    List<String> leadingOrphans = const <String>[],
    String? rawFallbackText,
    String? title,
    bool scrollable = true,
    double? maxHeight,
    String? emptyText,
    List<AIRequestLogsAction> actions = const <AIRequestLogsAction>[],
    bool showRawResponsePanel = false,
  }) {
    return AIRequestLogsViewer._(
      key: key,
      traces: traces,
      leadingOrphans: leadingOrphans,
      rawFallbackText: rawFallbackText,
      title: title,
      scrollable: scrollable,
      maxHeight: maxHeight,
      emptyText: emptyText,
      actions: actions,
      showRawResponsePanel: showRawResponsePanel,
    );
  }

  factory AIRequestLogsViewer.fromAiTraceTalker({
    Key? key,
    required List<TalkerData> logs,
    String? title,
    bool scrollable = true,
    double? maxHeight,
    String? emptyText,
    List<AIRequestLogsAction> actions = const <AIRequestLogsAction>[],
    bool showRawResponsePanel = false,
  }) {
    final List<TalkerData> filtered = logs
        .where((e) => ((e.message ?? '').trimLeft()).startsWith('[AITrace]'))
        .toList(growable: false);
    final List<String> messages = filtered
        .map((e) => (e.message ?? '').trimRight())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final List<DateTime> times = filtered
        .map((e) => e.time)
        .toList(growable: false);

    final List<AIRequestTrace> traces = parseAiTraceMessages(
      messages,
      times: times,
    );

    final String fallback = messages.join('\n\n');
    return AIRequestLogsViewer._(
      key: key,
      traces: traces,
      leadingOrphans: const <String>[],
      rawFallbackText: fallback.isEmpty ? null : fallback,
      title: title,
      scrollable: scrollable,
      maxHeight: maxHeight,
      emptyText: emptyText,
      actions: actions,
      showRawResponsePanel: showRawResponsePanel,
    );
  }

  factory AIRequestLogsViewer.fromGatewayLogText({
    Key? key,
    required String text,
    String? title,
    bool scrollable = true,
    double? maxHeight,
    String? emptyText,
    List<AIRequestLogsAction> actions = const <AIRequestLogsAction>[],
    bool showRawResponsePanel = false,
  }) {
    final GatewayLogParseResult parsed = parseGatewayLogTextDetailed(text);
    return AIRequestLogsViewer._(
      key: key,
      traces: parsed.traces,
      leadingOrphans: parsed.leadingOrphans,
      rawFallbackText: text.trim().isEmpty ? null : text.trimRight(),
      title: title,
      scrollable: scrollable,
      maxHeight: maxHeight,
      emptyText: emptyText,
      actions: actions,
      showRawResponsePanel: showRawResponsePanel,
    );
  }

  factory AIRequestLogsViewer.fromSegmentTrace({
    Key? key,
    required String rawRequest,
    required String rawResponse,
    int? segmentId,
    String? provider,
    String? model,
    DateTime? createdAt,
    String? title,
    bool scrollable = true,
    double? maxHeight,
    String? emptyText,
    List<AIRequestLogsAction> actions = const <AIRequestLogsAction>[],
    bool showRawResponsePanel = true,
  }) {
    final List<AIRequestTrace> traces = parseSegmentTrace(
      rawRequest: rawRequest,
      rawResponse: rawResponse,
      segmentId: segmentId,
      provider: provider,
      model: model,
      createdAt: createdAt,
    );

    final String fallback = [
      if (rawRequest.trim().isNotEmpty) rawRequest.trimRight(),
      if (rawResponse.trim().isNotEmpty) rawResponse.trimRight(),
    ].join('\n\n');

    return AIRequestLogsViewer._(
      key: key,
      traces: traces,
      leadingOrphans: const <String>[],
      rawFallbackText: fallback.trim().isEmpty ? null : fallback.trimRight(),
      title: title,
      scrollable: scrollable,
      maxHeight: maxHeight,
      emptyText: emptyText,
      actions: actions,
      showRawResponsePanel: showRawResponsePanel,
    );
  }

  final List<AIRequestTrace> traces;
  final List<String> leadingOrphans;
  final String? rawFallbackText;
  final String? title;
  final bool scrollable;
  final double? maxHeight;
  final String? emptyText;
  final List<AIRequestLogsAction> actions;
  final bool showRawResponsePanel;

  @override
  State<AIRequestLogsViewer> createState() => _AIRequestLogsViewerState();
}

class _AIRequestLogsViewerState extends State<AIRequestLogsViewer>
    with SingleTickerProviderStateMixin {
  int _selectedTraceIndex = 0;
  int _selectedPanelIndex = 0;
  int _panelSwitchDirection = 1;
  double _panelSwipeDx = 0;
  double _panelSwipeWidth = 0;
  late TabController _panelTabController;
  late final AnimationController _panelSwipeAnimController;
  Animation<double>? _panelSwipeAnim;
  bool _skipNextPanelAnimation = false;
  double? _panelMeasuredHeight;
  final Map<String, _RequestViewData> _requestViewDataCache =
      <String, _RequestViewData>{};
  final Map<String, _ResponseViewData> _responseViewDataCache =
      <String, _ResponseViewData>{};

  static const int _panelOverview = 0;
  static const int _panelRequest = 1;
  static const int _panelResponse = 2;
  static const int _panelRawResponse = 3;

  int get _panelCount => widget.showRawResponsePanel ? 4 : 3;
  int get _lastPanelIndex => _panelCount - 1;
  bool get _usesViewportPanels =>
      widget.scrollable && (widget.maxHeight ?? 0) > 0;

  int _clampPanelIndex(int value) {
    return value.clamp(_panelOverview, _lastPanelIndex).toInt();
  }

  void _handlePanelTabChanged() {
    final int next = _panelTabController.index;
    if (!mounted || _selectedPanelIndex == next) return;
    final int dir = next > _selectedPanelIndex ? 1 : -1;
    setState(() {
      _panelSwitchDirection = dir;
      _selectedPanelIndex = next;
    });
  }

  void _recreatePanelTabController({int? initialIndex}) {
    final int safeIndex = _clampPanelIndex(initialIndex ?? _selectedPanelIndex);
    final TabController controller = TabController(
      length: _panelCount,
      vsync: this,
      initialIndex: safeIndex,
    );
    controller.addListener(_handlePanelTabChanged);
    _panelTabController = controller;
    _selectedPanelIndex = safeIndex;
  }

  int? _panelSwipeTargetIndex() {
    final int current = _selectedPanelIndex;
    final double dx = _panelSwipeDx;
    if (dx < 0 && current < _lastPanelIndex) return current + 1;
    if (dx > 0 && current > _panelOverview) return current - 1;
    return null;
  }

  bool _panelNeedsResponseData(int index) {
    if (index == _panelResponse) return true;
    return widget.showRawResponsePanel && index == _panelRawResponse;
  }

  bool _shouldPrepareResponseData() {
    if (_panelNeedsResponseData(_selectedPanelIndex)) return true;
    final int? target = _panelSwipeTargetIndex();
    return target != null && _panelNeedsResponseData(target);
  }

  _RequestViewData _getRequestViewData(AIRequestTrace tr) {
    final String cacheKey = _traceSelectionKey(tr);
    return _requestViewDataCache.putIfAbsent(
      cacheKey,
      () => _parseRequestViewData(tr),
    );
  }

  _ResponseViewData _getResponseViewData(AIRequestTrace tr) {
    final String cacheKey = _traceSelectionKey(tr);
    return _responseViewDataCache.putIfAbsent(
      cacheKey,
      () => _parseResponseViewData(tr),
    );
  }

  _ResponseViewData? _getCachedResponseViewData(AIRequestTrace tr) {
    return _responseViewDataCache[_traceSelectionKey(tr)];
  }

  void _pruneParsedViewCaches() {
    final Set<String> validKeys = widget.traces.map(_traceSelectionKey).toSet();
    _requestViewDataCache.removeWhere(
      (String key, _RequestViewData _) => !validKeys.contains(key),
    );
    _responseViewDataCache.removeWhere(
      (String key, _ResponseViewData _) => !validKeys.contains(key),
    );
  }

  String _traceSelectionKey(AIRequestTrace tr) {
    final int startedAt = tr.startedAt?.millisecondsSinceEpoch ?? 0;
    final int endedAt = tr.endedAt?.millisecondsSinceEpoch ?? 0;
    final String traceId = (tr.traceId ?? '').trim();
    final String context = (tr.logContext ?? '').trim();
    final String model = (tr.model ?? '').trim();
    final String uri = (tr.request?.uri?.toString() ?? '').trim();
    final String error = (tr.error ?? '').trim();
    final int rawHash = Object.hashAll(tr.rawBlocks);
    return [
      traceId,
      context,
      model,
      uri,
      error,
      startedAt.toString(),
      endedAt.toString(),
      rawHash.toString(),
    ].join('|');
  }

  @override
  void initState() {
    super.initState();
    _recreatePanelTabController();
    if (widget.traces.isNotEmpty) {
      _selectedTraceIndex = widget.traces.length - 1;
    }

    _panelSwipeAnimController = AnimationController(vsync: this);
    _panelSwipeAnimController.addListener(() {
      final Animation<double>? anim = _panelSwipeAnim;
      if (anim == null) return;
      if (!mounted) return;
      setState(() => _panelSwipeDx = anim.value);
      _syncTabOffset();
    });
  }

  @override
  void dispose() {
    _panelTabController.removeListener(_handlePanelTabChanged);
    _panelTabController.dispose();
    _panelSwipeAnimController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AIRequestLogsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showRawResponsePanel != oldWidget.showRawResponsePanel) {
      _panelTabController.removeListener(_handlePanelTabChanged);
      _panelTabController.dispose();
      _recreatePanelTabController();
    }
    if (widget.traces.isEmpty) {
      _requestViewDataCache.clear();
      _responseViewDataCache.clear();
      _selectedTraceIndex = 0;
      _selectedPanelIndex = _panelOverview;
      _panelSwitchDirection = -1;
      _panelTabController.index = _panelOverview;
      return;
    }
    _pruneParsedViewCaches();
    final String? selectedTraceKey =
        oldWidget.traces.isNotEmpty &&
            _selectedTraceIndex >= 0 &&
            _selectedTraceIndex < oldWidget.traces.length
        ? _traceSelectionKey(oldWidget.traces[_selectedTraceIndex])
        : null;
    if (selectedTraceKey != null) {
      final int preservedIndex = widget.traces.indexWhere(
        (AIRequestTrace trace) => _traceSelectionKey(trace) == selectedTraceKey,
      );
      if (preservedIndex >= 0) {
        _selectedTraceIndex = preservedIndex;
      }
    }
    if (_selectedTraceIndex >= widget.traces.length) {
      _selectedTraceIndex = widget.traces.length - 1;
      _selectedPanelIndex = _panelOverview;
      _panelSwitchDirection = -1;
      _panelTabController.index = _panelOverview;
    }
    final int safePanelIndex = _clampPanelIndex(_selectedPanelIndex);
    if (safePanelIndex != _selectedPanelIndex) {
      _selectedPanelIndex = safePanelIndex;
      _panelTabController.index = safePanelIndex;
    }
  }

  bool _isZhLocale(BuildContext context) {
    try {
      return Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
    } catch (_) {
      return true;
    }
  }

  Future<void> _copy(BuildContext context, String text) async {
    final String t = text.trimRight();
    if (t.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: t));
      if (context.mounted) {
        UINotifier.success(context, l10n.copySuccess);
      }
    } catch (_) {
      if (context.mounted) {
        UINotifier.error(context, l10n.copyFailed);
      }
    }
  }

  String _fmtBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes >= 1024 * 1024) {
      final double mb = bytes / (1024 * 1024);
      final String text = mb >= 100
          ? mb.toStringAsFixed(0)
          : mb.toStringAsFixed(1);
      return '${text.replaceFirst(RegExp(r'\.0$'), '')} MB';
    }
    if (bytes >= 1024) {
      final double kb = bytes / 1024;
      final String text = kb >= 100
          ? kb.toStringAsFixed(0)
          : kb.toStringAsFixed(1);
      return '${text.replaceFirst(RegExp(r'\.0$'), '')} KB';
    }
    return '$bytes B';
  }

  String _fmtNum(int? n) {
    final int value = n ?? 0;
    final bool isNeg = value < 0;
    final String raw = value.abs().toString();
    final String grouped = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return isNeg ? '-$grouped' : grouped;
  }

  String _fmtTime(DateTime? dt, {required bool zh}) {
    if (dt == null) return '';
    final DateTime local = dt.toLocal();
    final DateTime now = DateTime.now();

    bool sameDay(DateTime a, DateTime b) {
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    final String ss = local.second.toString().padLeft(2, '0');
    final String time = '$hh:$mm:$ss';
    if (sameDay(local, now)) {
      return time;
    }

    if (local.year == now.year) {
      if (zh) return '${local.month}月${local.day}日 $time';
      final String month = local.month.toString().padLeft(2, '0');
      final String day = local.day.toString().padLeft(2, '0');
      return '$month-$day $time';
    }

    if (zh) return '${local.year}年${local.month}月${local.day}日 $time';
    final String month = local.month.toString().padLeft(2, '0');
    final String day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $time';
  }

  String _prettyJsonFromString(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    try {
      final dynamic decoded = jsonDecode(t);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw.trimRight();
    }
  }

  String _sanitizeDisplayText(String raw) {
    if (raw.isEmpty) return '';

    String text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    text = text.replaceAll(RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)'), '');
    text = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    final List<String> normalized = <String>[];
    int blankRun = 0;
    for (final String rawLine in text.split('\n')) {
      final String line = rawLine.replaceAll('\u00A0', ' ').trimRight();
      if (line.trim().isEmpty) {
        blankRun += 1;
        if (blankRun <= 1) normalized.add('');
        continue;
      }
      blankRun = 0;
      normalized.add(line);
    }

    return normalized.join('\n').trim();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String? _toNonEmptyString(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final String t = value.trim();
      return t.isEmpty ? null : t;
    }
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      final List<String> parts = <String>[];
      for (final dynamic item in value) {
        final String? p = _toNonEmptyString(item);
        if (p != null && p.isNotEmpty) parts.add(p);
      }
      if (parts.isEmpty) return null;
      return parts.join('\n');
    }
    if (value is Map) {
      final String? text =
          _toNonEmptyString(value['text']) ??
          _toNonEmptyString(value['value']) ??
          _toNonEmptyString(value['content']);
      return text;
    }
    return null;
  }

  String _buildTraceTitle(AIRequestTrace tr) {
    final String ctx = (tr.logContext ?? '').trim();
    if (tr.source == AIRequestLogSource.aiTrace) {
      if (ctx.isNotEmpty) return 'ctx=$ctx';
      final String api = (tr.apiType ?? '').trim();
      if (api.isNotEmpty) return api;
    }
    if (tr.source == AIRequestLogSource.nativeLog && ctx.isNotEmpty) {
      return ctx;
    }
    final Uri? uri = tr.request?.uri;
    if (uri != null) {
      final String host = uri.host.trim();
      final String path = uri.path.isEmpty ? '/' : uri.path;
      if (host.isNotEmpty) return host + path;
      return uri.toString();
    }
    final String traceId = (tr.traceId ?? '').trim();
    if (traceId.isNotEmpty) return 'trace=$traceId';
    return 'AI request';
  }

  Widget _statusBadge(BuildContext context, AIRequestTrace tr) {
    final bool zh = _isZhLocale(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    String text;
    Color backgroundColor;
    Color textColor;

    if (tr.isError) {
      text = zh ? '失败' : 'Error';
      backgroundColor = cs.error;
      textColor = cs.onError;
    } else if (tr.isHttpSuccess ||
        (tr.response?.body ?? '').trim().isNotEmpty) {
      text = zh ? '成功' : 'OK';
      backgroundColor = AppTheme.success;
      textColor = AppTheme.successForeground;
    } else if (tr.response?.statusCode != null) {
      text = '${tr.response!.statusCode}';
      backgroundColor = cs.secondaryContainer;
      textColor = cs.onSecondaryContainer;
    } else {
      text = zh ? '日志' : 'Log';
      backgroundColor = cs.surfaceContainerHighest.withValues(alpha: 0.55);
      textColor = cs.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: textColor,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
    String? copyText,
    bool monospace = false,
    bool showHeader = true,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextStyle? codeStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      height: 1.35,
      color: cs.onSurfaceVariant,
    );
    final TextStyle? bodyStyle = theme.textTheme.bodySmall?.copyWith(
      height: 1.35,
      color: cs.onSurfaceVariant,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (copyText != null && copyText.trim().isNotEmpty)
                  IconButton(
                    tooltip: _isZhLocale(context) ? '复制' : 'Copy',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _copy(context, copyText),
                  ),
              ],
            ),
          if (showHeader) const SizedBox(height: AppTheme.spacing2),
          DefaultTextStyle(
            style: monospace
                ? (codeStyle ?? const TextStyle())
                : (bodyStyle ?? const TextStyle()),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandableSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
    bool monospace = false,
    bool initiallyExpanded = false,
    String? subtitle,
  }) {
    final ThemeData theme = Theme.of(context);
    return UICard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing4,
            vertical: AppTheme.spacing2,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTheme.spacing4,
            0,
            AppTheme.spacing4,
            AppTheme.spacing4,
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: (subtitle == null || subtitle.trim().isEmpty)
              ? null
              : Text(
                  subtitle.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          children: [
            _sectionCard(
              context,
              title: title,
              showHeader: false,
              monospace: monospace,
              children: children,
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeBlock(BuildContext context, String text, {double? maxHeight}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String t = _sanitizeDisplayText(text);
    if (t.isEmpty) return const SizedBox.shrink();

    final Widget child = SelectableText(
      t,
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        height: 1.3,
        color: cs.onSurface,
      ),
    );

    if (maxHeight == null) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: child),
    );
  }

  String _extractRequestRawText(AIRequestTrace tr) {
    for (final String b in tr.rawBlocks) {
      final String block = b.trimRight();
      if (block.isEmpty) continue;
      if (block.contains('=== AI Request')) return block;
      if (block.startsWith('REQ ')) return block;
    }
    final String reqBody = (tr.request?.body ?? '').trimRight();
    return reqBody;
  }

  String _extractResponseRawText(AIRequestTrace tr) {
    final String respBody = (tr.response?.body ?? '').trimRight();
    if (respBody.isNotEmpty) return respBody;
    final String errBody = (tr.response?.errorBody ?? '').trimRight();
    if (errBody.isNotEmpty) return errBody;

    for (int i = tr.rawBlocks.length - 1; i >= 0; i -= 1) {
      final String block = tr.rawBlocks[i].trimRight();
      if (block.isEmpty) continue;
      if (block.contains('=== AI Response')) return block;
      if (block.startsWith('RESP ')) return block;
      if (block.startsWith('{') || block.startsWith('data:')) return block;
    }
    return '';
  }

  _RequestViewData _parseRequestViewData(AIRequestTrace tr) {
    final String requestBlock = _extractRequestRawText(tr);
    final String bodyFallback = (tr.request?.body ?? '').trimRight();
    if (requestBlock.trim().isEmpty) {
      return _RequestViewData(
        isSegmentStyle: false,
        requestBlock: '',
        bodyFallback: bodyFallback,
      );
    }

    final List<String> lines = requestBlock
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final bool hasSegmentMarker = lines.any(
      (e) => e.trimLeft().startsWith('=== AI Request'),
    );

    final Map<String, String> meta = <String, String>{};
    final List<_SegmentImageItem> images = <_SegmentImageItem>[];
    final StringBuffer promptBuffer = StringBuffer();
    bool inPrompt = false;
    bool inImages = false;

    for (final String line0 in lines) {
      final String line = line0.trimRight();
      final String t = line.trim();
      if (t == 'prompt:') {
        inPrompt = true;
        inImages = false;
        continue;
      }
      if (t == 'images:') {
        inPrompt = false;
        inImages = true;
        continue;
      }

      if (inImages) {
        final _SegmentImageItem? image = _parseImageLine(line);
        if (image != null) images.add(image);
        continue;
      }
      if (inPrompt) {
        promptBuffer.writeln(line);
        continue;
      }
      if (line.startsWith('=== ')) continue;

      final int eq = line.indexOf('=');
      if (eq > 0) {
        final String k = line.substring(0, eq).trim();
        final String v = line.substring(eq + 1).trim();
        if (k.isNotEmpty) meta[k] = v;
      }
    }

    final String rawPrompt = promptBuffer.toString().trimRight();
    final List<_PromptImageIndexItem> imageIndex = <_PromptImageIndexItem>[];
    final RegExp indexRegex = RegExp(
      r'截图时间=\[#(\d+)\]\s+([0-9:]{5,8})\s*\|\s*(.+)$',
      multiLine: true,
    );
    for (final RegExpMatch m in indexRegex.allMatches(rawPrompt)) {
      final int? num = int.tryParse(m.group(1) ?? '');
      final String time = (m.group(2) ?? '').trim();
      final String app = (m.group(3) ?? '').trim();
      if (num == null || time.isEmpty || app.isEmpty) continue;
      imageIndex.add(_PromptImageIndexItem(number: num, time: time, app: app));
    }

    String promptText = rawPrompt;
    if (rawPrompt.isNotEmpty) {
      final List<String> kept = <String>[];
      final List<String> promptLines = rawPrompt
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');
      final RegExp idxLine = RegExp(r'^-\s*截图时间=\[#\d+\]');
      for (final String l0 in promptLines) {
        final String l = l0.trimRight();
        final String lt = l.trim();
        if (lt.startsWith('图片索引')) continue;
        if (idxLine.hasMatch(lt)) continue;
        kept.add(l);
      }
      promptText = kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    }

    final String cleanedPromptText = _sanitizeDisplayText(promptText);
    final String cleanedRawPrompt = _sanitizeDisplayText(rawPrompt);
    final String cleanedRequestBlock = _sanitizeDisplayText(requestBlock);
    final String cleanedBodyFallback = _sanitizeDisplayText(bodyFallback);

    return _RequestViewData(
      isSegmentStyle:
          hasSegmentMarker || rawPrompt.isNotEmpty || images.isNotEmpty,
      requestMeta: meta,
      promptText: cleanedPromptText,
      rawPrompt: cleanedRawPrompt,
      images: images,
      imageIndex: imageIndex,
      requestBlock: cleanedRequestBlock,
      bodyFallback: cleanedBodyFallback,
    );
  }

  _SegmentImageItem? _parseImageLine(String line0) {
    final String line = line0.trimRight();
    if (!line.startsWith('#')) return null;
    final RegExp re = RegExp(
      r'^#(\d+)\s+time=([^\s]+)\s+app=(.*?)\s+file=([^\s]+)(?:\s+path=([^\s]+))?(?:\s+mime=([^\s]+))?(?:\s+bytes=(\d+))?$',
    );
    final RegExpMatch? m = re.firstMatch(line);
    if (m == null) return null;

    final int? number = int.tryParse(m.group(1) ?? '');
    if (number == null || number <= 0) return null;

    final String time = (m.group(2) ?? '').trim();
    final String app = (m.group(3) ?? '').trim();
    final String file = (m.group(4) ?? '').trim();
    final String path = (m.group(5) ?? '').trim();
    final String mime = (m.group(6) ?? '').trim();
    final int? bytes = int.tryParse((m.group(7) ?? '').trim());
    final String pkg =
        RegExp(r'/screen/([^/]+)/').firstMatch(path)?.group(1)?.trim() ?? '';

    return _SegmentImageItem(
      number: number,
      time: time,
      app: app,
      file: file,
      path: path,
      mime: mime,
      bytes: bytes,
      packageName: pkg,
    );
  }

  void _collectUsageFromObject(dynamic obj, _UsageBox usage) {
    if (obj is! Map) return;
    final dynamic usageRaw = obj['usage'] ?? obj['token_usage'];
    if (usageRaw is! Map) return;

    final int? prompt = _toInt(
      usageRaw['prompt_tokens'] ??
          usageRaw['promptTokens'] ??
          usageRaw['input_tokens'] ??
          usageRaw['inputTokens'],
    );
    final int? completion = _toInt(
      usageRaw['completion_tokens'] ??
          usageRaw['completionTokens'] ??
          usageRaw['output_tokens'] ??
          usageRaw['outputTokens'],
    );
    final int? total = _toInt(
      usageRaw['total_tokens'] ?? usageRaw['totalTokens'],
    );

    usage.promptTokens ??= prompt;
    usage.completionTokens ??= completion;
    usage.totalTokens ??= total;
    usage.totalTokens ??=
        (usage.promptTokens != null && usage.completionTokens != null)
        ? usage.promptTokens! + usage.completionTokens!
        : null;
  }

  List<String> _extractContentChunks(dynamic obj) {
    if (obj is! Map) return const <String>[];
    final List<String> out = <String>[];

    final String type = (obj['type'] ?? '').toString().trim().toLowerCase();
    final String? typeDelta = _toNonEmptyString(obj['delta']);
    if (type.contains('output_text') && typeDelta != null) out.add(typeDelta);
    final String? doneText = _toNonEmptyString(obj['text']);
    if (type.contains('output_text.done') && doneText != null) {
      out.add(doneText);
    }

    final dynamic choices = obj['choices'];
    if (choices is List && choices.isNotEmpty) {
      final dynamic choice0 = choices.first;
      if (choice0 is Map) {
        final dynamic delta = choice0['delta'];
        if (delta is Map) {
          final String? c = _toNonEmptyString(delta['content']);
          if (c != null) out.add(c);
        }
        final dynamic message = choice0['message'];
        if (message is Map) {
          final String? c = _toNonEmptyString(message['content']);
          if (c != null) out.add(c);
        }
        final String? text = _toNonEmptyString(choice0['text']);
        if (text != null) out.add(text);
      }
    }

    final String? outputText = _toNonEmptyString(obj['output_text']);
    if (outputText != null) out.add(outputText);

    final dynamic output = obj['output'];
    if (output is List) {
      for (final dynamic item in output) {
        if (item is! Map) continue;
        final dynamic content = item['content'];
        if (content is List) {
          for (final dynamic part in content) {
            final String? text = _toNonEmptyString(part);
            if (text != null) out.add(text);
          }
        }
        final String? itemText = _toNonEmptyString(item['text']);
        if (itemText != null) out.add(itemText);
      }
    }

    final dynamic candidates = obj['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final dynamic c0 = candidates.first;
      if (c0 is Map) {
        final dynamic content = c0['content'];
        if (content is Map) {
          final dynamic parts = content['parts'];
          if (parts is List) {
            for (final dynamic p in parts) {
              if (p is! Map) continue;
              final String? text = _toNonEmptyString(p['text']);
              if (text != null) out.add(text);
            }
          }
        }
      }
    }

    return out;
  }

  String _mergeResponseText(String raw, _UsageBox usage) {
    final String normalized = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) return '';

    final StringBuffer merged = StringBuffer();
    final List<String> lines = normalized.split('\n');
    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('data:')) {
        line = line.substring(5).trim();
      }
      if (line.isEmpty || line == '[DONE]' || line == '[done]') continue;

      dynamic decoded;
      try {
        decoded = jsonDecode(line);
      } catch (_) {
        continue;
      }
      _collectUsageFromObject(decoded, usage);
      final List<String> chunks = _extractContentChunks(decoded);
      for (final String c in chunks) {
        if (c.isEmpty) continue;
        merged.write(c);
      }
    }

    return merged.toString().trimRight();
  }

  _ResponseViewData _parseResponseViewData(AIRequestTrace tr) {
    final String raw = _extractResponseRawText(tr);
    final _UsageBox usage = _UsageBox(
      promptTokens: tr.usagePromptTokens,
      completionTokens: tr.usageCompletionTokens,
      totalTokens: tr.usageTotalTokens,
    );
    final String merged = _mergeResponseText(raw, usage);

    String displayText = merged;
    if (displayText.trim().isEmpty) {
      final String responseBody = (tr.response?.body ?? '').trimRight();
      if (responseBody.trim().isNotEmpty) {
        displayText = _prettyJsonFromString(responseBody);
      } else {
        displayText = raw.trimRight();
      }
    }

    return _ResponseViewData(
      mergedText: _sanitizeDisplayText(merged),
      displayText: _sanitizeDisplayText(displayText),
      rawText: _sanitizeDisplayText(raw),
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens,
      totalTokens: usage.totalTokens,
    );
  }

  String _requestBadgeText(AIRequestTrace tr, _RequestViewData req) {
    final bool zh = _isZhLocale(context);
    int? imagesCount;
    if (req.images.isNotEmpty) imagesCount = req.images.length;
    imagesCount ??= tr.imagesCount;
    final String attached =
        (req.requestMeta['images_attached'] ??
                req.requestMeta['images_total'] ??
                '')
            .trim();
    imagesCount ??= int.tryParse(attached);
    if (imagesCount != null) {
      return zh
          ? '${_fmtNum(imagesCount)} 张'
          : '${_fmtNum(imagesCount)} images';
    }
    if (attached.isNotEmpty) {
      return attached;
    }
    return zh ? '—' : '-';
  }

  String _responseBadgeText(AIRequestTrace tr, _ResponseViewData? rsp) {
    final int? completion = tr.usageCompletionTokens ?? rsp?.completionTokens;
    if (completion != null) {
      return '${_fmtNum(completion)} tokens';
    }
    if (tr.response?.statusCode != null) return '${tr.response!.statusCode}';
    final bool zh = _isZhLocale(context);
    return zh ? '—' : '-';
  }

  Widget _buildTracePicker(BuildContext context) {
    if (widget.traces.length <= 1) return const SizedBox.shrink();
    final bool zh = _isZhLocale(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Text(
            zh ? '请求链路' : 'Trace',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _selectedTraceIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: List<DropdownMenuItem<int>>.generate(
                widget.traces.length,
                (int i) {
                  final AIRequestTrace tr = widget.traces[i];
                  final String label = '#${i + 1} ${_buildTraceTitle(tr)}';
                  return DropdownMenuItem<int>(
                    value: i,
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                },
              ),
              onChanged: (int? value) {
                if (value == null) return;
                setState(() {
                  _selectedTraceIndex = value;
                  _panelSwitchDirection = -1;
                  _selectedPanelIndex = _panelOverview;
                });
                _panelTabController.index = _panelOverview;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelTabs(
    BuildContext context,
    AIRequestTrace tr,
    _RequestViewData req,
    _ResponseViewData? rsp, {
    bool fillBody = false,
  }) {
    final bool zh = _isZhLocale(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    Widget buildTab(String title, String badge) {
      final String b = badge.trim();
      final bool showBadge = b.isNotEmpty && b != '-' && b != '—';
      return Tab(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (showBadge) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    color: cs.surfaceContainerHighest,
                  ),
                  child: Text(
                    b,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final List<Widget> tabs = <Widget>[
      buildTab(zh ? '概览' : 'Overview', ''),
      buildTab(zh ? '请求' : 'Request', _requestBadgeText(tr, req)),
      buildTab(zh ? '响应' : 'Response', _responseBadgeText(tr, rsp)),
      if (widget.showRawResponsePanel)
        buildTab(zh ? '原始响应' : 'Raw Response', ''),
    ];

    final Widget panelBody = _buildSwipeablePanels(context, tr, req, rsp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenshotStyleTabBar(
          controller: _panelTabController,
          height: 36,
          isScrollable: false,
          tabAlignment: TabAlignment.fill,
          padding: EdgeInsets.zero,
          labelPadding: EdgeInsets.zero,
          indicatorInsets: const EdgeInsets.symmetric(horizontal: 4.0),
          tabs: tabs,
        ),
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing2),
          _buildActionsBar(context),
        ],
        const SizedBox(height: AppTheme.spacing3),
        if (fillBody) Expanded(child: panelBody) else panelBody,
      ],
    );
  }

  Widget _buildActionsBar(BuildContext context) {
    if (widget.actions.isEmpty) return const SizedBox.shrink();

    OutlinedButton buildButton(AIRequestLogsAction action) {
      return OutlinedButton(
        onPressed: action.enabled
            ? () async {
                await action.onPressed();
              }
            : null,
        style: OutlinedButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Text(action.label),
      );
    }

    final List<List<AIRequestLogsAction>> rows = <List<AIRequestLogsAction>>[];
    for (int i = 0; i < widget.actions.length; i += 2) {
      rows.add(widget.actions.skip(i).take(2).toList(growable: false));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int r = 0; r < rows.length; r++) ...[
          Row(
            children: [
              Expanded(child: buildButton(rows[r][0])),
              if (rows[r].length == 2) ...[
                const SizedBox(width: AppTheme.spacing2),
                Expanded(child: buildButton(rows[r][1])),
              ],
            ],
          ),
          if (r != rows.length - 1) const SizedBox(height: AppTheme.spacing2),
        ],
      ],
    );
  }

  Widget _buildViewportTextPanel(
    BuildContext context, {
    required String title,
    required String text,
    required String emptyText,
    bool monospace = true,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String content = _sanitizeDisplayText(text);
    final TextStyle? textStyle = monospace
        ? theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.35,
            color: cs.onSurface,
          )
        : theme.textTheme.bodyMedium?.copyWith(
            height: 1.4,
            color: cs.onSurface,
          );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacing3,
              AppTheme.spacing3,
              AppTheme.spacing3,
              AppTheme.spacing2,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: content.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacing4),
                      child: Text(
                        emptyText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppTheme.spacing3),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SelectableText(content, style: textStyle),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _stopPanelSwipeAnimation() {
    if (!_panelSwipeAnimController.isAnimating) return;
    _panelSwipeAnimController.stop();
    _panelSwipeAnim = null;
  }

  void _handlePanelHorizontalDragStart(DragStartDetails _) {
    _stopPanelSwipeAnimation();
    if (_panelSwipeDx == 0) return;
    setState(() => _panelSwipeDx = 0);
    _syncTabOffset();
  }

  void _handlePanelHorizontalDragUpdate(DragUpdateDetails details) {
    _stopPanelSwipeAnimation();
    final double width = _panelSwipeWidth;
    if (width <= 0) return;
    setState(() {
      double next = _panelSwipeDx + details.delta.dx;
      if (_selectedPanelIndex == _panelOverview && next > 0) {
        next *= 0.25;
      }
      if (_selectedPanelIndex == _lastPanelIndex && next < 0) {
        next *= 0.25;
      }
      _panelSwipeDx = next.clamp(-width, width);
    });
    _syncTabOffset();
  }

  void _handlePanelHorizontalDragEnd(DragEndDetails details) {
    final double width = _panelSwipeWidth;
    if (width <= 0) return;
    _settlePanelSwipe(width, details.primaryVelocity ?? 0);
  }

  Widget _buildHorizontalSwipeScope(Widget child) {
    if (widget.traces.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handlePanelHorizontalDragStart,
      onHorizontalDragUpdate: _handlePanelHorizontalDragUpdate,
      onHorizontalDragEnd: _handlePanelHorizontalDragEnd,
      child: child,
    );
  }

  Widget _buildSwipeablePanels(
    BuildContext context,
    AIRequestTrace tr,
    _RequestViewData req,
    _ResponseViewData? rsp,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        _panelSwipeWidth = width;

        return _panelSwipeDx.abs() > 0.01
            ? _buildSwipingStack(context, width, tr, req, rsp)
            : _buildAnimatedPanelSwitcher(context, tr, req, rsp);
      },
    );
  }

  Widget _buildAnimatedPanelSwitcher(
    BuildContext context,
    AIRequestTrace tr,
    _RequestViewData req,
    _ResponseViewData? rsp,
  ) {
    final Duration duration = _skipNextPanelAnimation
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final bool isIncoming = child.key == ValueKey<int>(_selectedPanelIndex);
        final double baseDx = 0.12 * _panelSwitchDirection.toDouble();
        final Offset begin = Offset(isIncoming ? baseDx : -baseDx, 0.0);
        final Animation<Offset> slide = Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
        return ClipRect(
          child: SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(_selectedPanelIndex),
        child: _MeasureSize(
          onChange: (Size size) {
            if (!mounted) return;
            if (_panelSwipeDx.abs() > 0.01) return;
            final double h = size.height;
            if (h <= 0) return;
            final double? prev = _panelMeasuredHeight;
            if (prev != null && (prev - h).abs() < 0.5) return;
            setState(() => _panelMeasuredHeight = h);
          },
          child: _buildPanelByIndex(context, _selectedPanelIndex, tr, req, rsp),
        ),
      ),
    );
  }

  Widget _buildSwipingStack(
    BuildContext context,
    double width,
    AIRequestTrace tr,
    _RequestViewData req,
    _ResponseViewData? rsp,
  ) {
    final int current = _selectedPanelIndex;
    final double dx = _panelSwipeDx;
    final int? target = _panelSwipeTargetIndex();

    final Widget currentChild = _buildPanelByIndex(
      context,
      current,
      tr,
      req,
      rsp,
    );
    final Widget? targetChild = target == null
        ? null
        : _buildPanelByIndex(context, target, tr, req, rsp);
    final double targetDx = target == null
        ? 0
        : (dx < 0 ? dx + width : dx - width);

    return ClipRect(
      child: SizedBox(
        height: _panelMeasuredHeight,
        child: Stack(
          children: [
            if (targetChild != null)
              Transform.translate(
                offset: Offset(targetDx, 0),
                child: IgnorePointer(child: targetChild),
              ),
            Transform.translate(offset: Offset(dx, 0), child: currentChild),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelByIndex(
    BuildContext context,
    int index,
    AIRequestTrace tr,
    _RequestViewData req,
    _ResponseViewData? rsp,
  ) {
    if (index == _panelRequest) return _buildRequestPanel(context, tr, req);
    if (index == _panelResponse) {
      return _buildResponsePanel(
        context,
        tr,
        req,
        rsp ?? _getResponseViewData(tr),
      );
    }
    if (index == _panelRawResponse) {
      return _buildRawResponsePanel(context, rsp ?? _getResponseViewData(tr));
    }
    return _buildOverviewPanel(context, tr, req, rsp);
  }

  void _settlePanelSwipe(double width, double velocity) {
    final double dx = _panelSwipeDx;
    if (dx.abs() <= 0.01) return;

    final int current = _selectedPanelIndex;
    int? target;
    if (dx < 0 && current < _lastPanelIndex) target = current + 1;
    if (dx > 0 && current > _panelOverview) target = current - 1;
    if (target == null) {
      _animatePanelSwipeTo(0);
      return;
    }

    final bool commit = dx.abs() >= width * 0.25 || velocity.abs() >= 800;
    if (!commit) {
      _animatePanelSwipeTo(0);
      return;
    }

    final int dir = target > current ? 1 : -1;
    final double endDx = dx < 0 ? -width : width;
    _animatePanelSwipeTo(
      endDx,
      onEnd: () {
        if (!mounted) return;
        setState(() {
          _skipNextPanelAnimation = true;
          _panelSwitchDirection = dir;
          _selectedPanelIndex = target!;
          _panelTabController.index = target;
          _panelTabController.offset = 0;
          _panelSwipeDx = 0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _skipNextPanelAnimation = false);
        });
      },
    );
  }

  void _animatePanelSwipeTo(double endDx, {VoidCallback? onEnd}) {
    _panelSwipeAnimController.stop();
    _panelSwipeAnimController.duration = const Duration(milliseconds: 180);
    _panelSwipeAnim = Tween<double>(begin: _panelSwipeDx, end: endDx).animate(
      CurvedAnimation(
        parent: _panelSwipeAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _panelSwipeAnimController.forward(from: 0).whenComplete(() {
      _panelSwipeAnim = null;
      onEnd?.call();
    });
  }

  void _syncTabOffset() {
    if (_panelSwipeWidth <= 0) return;
    if (_panelTabController.indexIsChanging) return;

    final int current = _selectedPanelIndex;
    final double dx = _panelSwipeDx;
    final bool hasTarget =
        (dx < 0 && current < _lastPanelIndex) ||
        (dx > 0 && current > _panelOverview);
    final double offset = hasTarget
        ? (-dx / _panelSwipeWidth).clamp(-1.0, 1.0)
        : 0.0;

    _panelTabController.offset = offset;
  }

  Widget _buildStatRow(BuildContext context, List<_OverviewStatItem> stats) {
    if (stats.isEmpty) return const SizedBox.shrink();

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < stats.length; i += 2) {
      final _OverviewStatItem left = stats[i];
      final _OverviewStatItem? right = (i + 1 < stats.length)
          ? stats[i + 1]
          : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildStatItemTile(context, left)),
            const SizedBox(width: AppTheme.spacing2),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _buildStatItemTile(context, right),
            ),
          ],
        ),
      );
      if (i + 2 < stats.length) {
        rows.add(const SizedBox(height: AppTheme.spacing2));
      }
    }

    return Column(children: rows);
  }

  Widget _buildStatItemTile(BuildContext context, _OverviewStatItem item) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing3,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: item.monospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageBadge(
    BuildContext context, {
    required String label,
    required int value,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
      ),
      child: Text(
        '${_fmtNum(value)} $label',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          fontFamily: 'monospace',
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildMetaBadge(BuildContext context, String text) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
      ),
      child: Text(
        t,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          fontFamily: 'monospace',
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildOverviewPanel(
    BuildContext context,
    AIRequestTrace tr,
    _RequestViewData req,
    _ResponseViewData? rsp,
  ) {
    final bool zh = _isZhLocale(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final String segmentId = (req.requestMeta['segment_id'] ?? tr.traceId ?? '')
        .trim();
    final String model = (tr.model ?? req.requestMeta['model'] ?? '').trim();
    final String provider =
        (tr.providerName ?? req.requestMeta['provider'] ?? '').trim();
    final String url =
        (req.requestMeta['url'] ?? tr.request?.uri?.toString() ?? '').trim();
    final String createdAtRaw = (req.requestMeta['created_at'] ?? '').trim();
    final DateTime? createdAtParsed = DateTime.tryParse(createdAtRaw);
    final DateTime? createdAtDt =
        createdAtParsed ?? (createdAtRaw.isEmpty ? tr.startedAt : null);
    final String createdAtText = createdAtDt != null
        ? _fmtTime(createdAtDt, zh: zh)
        : createdAtRaw;

    final int? promptTokens = tr.usagePromptTokens ?? rsp?.promptTokens;
    final int? completionTokens =
        tr.usageCompletionTokens ?? rsp?.completionTokens;
    int? totalTokens = tr.usageTotalTokens ?? rsp?.totalTokens;
    totalTokens ??= (promptTokens != null && completionTokens != null)
        ? promptTokens + completionTokens
        : null;

    final List<Widget> tokenBadges = <Widget>[
      if (promptTokens != null)
        _buildUsageBadge(context, label: zh ? '入' : 'in', value: promptTokens),
      if (completionTokens != null)
        _buildUsageBadge(
          context,
          label: zh ? '出' : 'out',
          value: completionTokens,
        ),
      if (totalTokens != null)
        _buildUsageBadge(
          context,
          label: zh ? '总' : 'total',
          value: totalTokens,
        ),
    ];

    final List<_OverviewStatItem> stats = <_OverviewStatItem>[];

    void addStat(String label, String value, {bool monospace = false}) {
      final String v = value.trim();
      if (v.isEmpty) return;
      stats.add(
        _OverviewStatItem(label: label, value: v, monospace: monospace),
      );
    }

    int? promptLen = _toInt(req.requestMeta['prompt_len']);
    promptLen ??= req.promptText.trim().isEmpty ? null : req.promptText.length;
    final String imagesBytes = _fmtBytes(
      int.tryParse((req.requestMeta['images_bytes_total'] ?? '').trim()),
    );
    final int? missingImages = _toInt(req.requestMeta['missing_images']);

    addStat(
      zh ? '服务商' : 'Provider',
      provider.isEmpty ? (zh ? '—' : '-') : provider,
    );
    addStat(
      zh ? 'Prompt 长度' : 'Prompt length',
      promptLen == null
          ? (zh ? '—' : '-')
          : (zh ? '${_fmtNum(promptLen)} 字符' : '${_fmtNum(promptLen)} chars'),
    );
    if (imagesBytes.isNotEmpty) {
      addStat(zh ? '图片总大小' : 'Image bytes', imagesBytes);
    }
    if (missingImages != null) {
      addStat(
        zh ? '缺失图片' : 'Missing images',
        zh ? '${_fmtNum(missingImages)} 张' : '${_fmtNum(missingImages)} images',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                  children: [
                    TextSpan(
                      text: '#',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(text: segmentId.isEmpty ? '—' : segmentId),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusBadge(context, tr),
                if (createdAtText.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildMetaBadge(context, createdAtText),
                ],
              ],
            ),
          ],
        ),
        if (model.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(
                ModelIconUtils.getIconPath(model),
                width: 16,
                height: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  model,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (tokenBadges.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: tokenBadges),
        ],
        if (url.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zh ? '接口地址' : 'Endpoint',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  url,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
        if (stats.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing2),
          _buildStatRow(context, stats),
        ],
        if ((tr.error ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing2),
          _sectionCard(
            context,
            title: zh ? '错误' : 'Error',
            copyText: tr.error,
            children: [
              Text(
                tr.error!.trimRight(),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildImageCard(
    BuildContext context,
    _SegmentImageItem img, {
    int? targetWidth,
    VoidCallback? onTap,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final File? imageFile = _resolveImageFile(img);

    Widget placeholder(IconData icon) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 24,
            color: cs.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
      );
    }

    if (imageFile == null) {
      return placeholder(Icons.image_not_supported_outlined);
    }

    return ScreenshotImageWidget(
      file: imageFile,
      fit: BoxFit.cover,
      targetWidth: targetWidth,
      borderRadius: BorderRadius.circular(8),
      showNsfwButton: false,
      onTap: onTap,
    );
  }

  File? _resolveImageFile(_SegmentImageItem img) {
    final List<String> candidates = <String>[img.path, img.file];
    for (final String raw in candidates) {
      String p = raw.trim();
      if (p.isEmpty) continue;
      if (p.startsWith('file://')) {
        try {
          p = Uri.parse(p).toFilePath();
        } catch (_) {}
      }
      final File f = File(p);
      if (f.existsSync()) return f;
    }
    return null;
  }

  Future<void> _openAttachedImagesViewer(
    List<_SegmentImageItem> images,
    int initialIndex,
  ) async {
    if (images.isEmpty) return;

    final int safeInitial = initialIndex < 0
        ? 0
        : (initialIndex >= images.length ? images.length - 1 : initialIndex);

    final List<String> paths = <String>[];
    int viewerIndex = 0;
    for (int i = 0; i < images.length; i += 1) {
      final File? f = _resolveImageFile(images[i]);
      if (f == null) continue;
      if (i == safeInitial) viewerIndex = paths.length;
      paths.add(f.path);
    }
    if (paths.isEmpty) return;

    final int safeViewerIndex = viewerIndex < 0
        ? 0
        : (viewerIndex >= paths.length ? paths.length - 1 : viewerIndex);

    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: <String, dynamic>{
        'paths': paths,
        'initialIndex': safeViewerIndex,
        'singleMode': false,
        'appName': images[safeInitial].app.trim().isEmpty
            ? 'Attached Images'
            : images[safeInitial].app.trim(),
      },
    );
  }

  Widget _buildRequestPanel(
    BuildContext context,
    AIRequestTrace tr,
    _RequestViewData req,
  ) {
    final bool zh = _isZhLocale(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<Widget> children = <Widget>[];

    if (req.images.isNotEmpty) {
      children.add(
        Text(
          zh ? '附加图片' : 'Images',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      children.add(const SizedBox(height: AppTheme.spacing2));
      children.add(_buildImagesVirtualGrid(context, req.images));
      children.add(const SizedBox(height: AppTheme.spacing2));
    }

    final String prompt = req.promptText.trim().isNotEmpty
        ? req.promptText
        : req.rawPrompt;
    if (prompt.trim().isNotEmpty) {
      if (_usesViewportPanels) {
        final Widget promptPanel = _buildViewportTextPanel(
          context,
          title: zh ? 'Prompt 内容' : 'Prompt',
          text: prompt,
          emptyText: zh ? '暂无提示词内容' : 'No prompt content',
        );
        if (req.images.isNotEmpty) {
          children.add(Expanded(child: promptPanel));
        } else {
          return promptPanel;
        }
      } else {
        children.add(
          _sectionCard(
            context,
            title: zh ? 'Prompt 内容' : 'Prompt',
            copyText: prompt,
            monospace: true,
            children: [_codeBlock(context, prompt)],
          ),
        );
        children.add(const SizedBox(height: AppTheme.spacing2));
      }
    }

    if (children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Text(
            zh ? '暂无请求内容' : 'No request content',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildImagesVirtualGrid(
    BuildContext context,
    List<_SegmentImageItem> images,
  ) {
    if (images.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        const int crossAxisCount = 3;
        const double spacing = 2;
        const double childAspectRatio = 9 / 16;
        const double maxVirtualGridHeight = 360;

        final double cellWidth =
            (availableWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final double cellHeight = cellWidth / childAspectRatio;

        final int rows = (images.length / crossAxisCount).ceil();
        final double naturalHeight =
            rows * cellHeight + math.max(0, rows - 1) * spacing;
        final double maxHeight = math.min(
          maxVirtualGridHeight,
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
              cacheExtent: MediaQuery.of(context).size.height,
              addAutomaticKeepAlives: false,
              physics: const ClampingScrollPhysics(),
              itemCount: images.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (ctx, i) {
                return _buildImageCard(
                  context,
                  images[i],
                  targetWidth: targetWidthPx,
                  onTap: () => _openAttachedImagesViewer(images, i),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildResponsePanel(
    BuildContext context,
    AIRequestTrace tr,
    _RequestViewData req,
    _ResponseViewData rsp,
  ) {
    final bool zh = _isZhLocale(context);
    final String display = rsp.displayText.trim().isNotEmpty
        ? rsp.displayText
        : (zh ? '（空）' : '(empty)');

    if (_usesViewportPanels) {
      return _buildViewportTextPanel(
        context,
        title: zh ? '响应内容' : 'Response',
        text: display,
        emptyText: zh ? '（空）' : '(empty)',
      );
    }

    return _sectionCard(
      context,
      title: zh ? '响应内容' : 'Response',
      copyText: display,
      monospace: true,
      children: [_codeBlock(context, display)],
    );
  }

  Widget _buildRawResponsePanel(BuildContext context, _ResponseViewData rsp) {
    final bool zh = _isZhLocale(context);
    final String raw = rsp.rawText.trimRight();
    if (_usesViewportPanels) {
      return _buildViewportTextPanel(
        context,
        title: zh ? '原始响应' : 'Raw Response',
        text: raw,
        emptyText: zh ? '（暂无原始响应）' : '(No raw response yet)',
      );
    }

    return _sectionCard(
      context,
      title: zh ? '原始响应' : 'Raw Response',
      copyText: raw,
      monospace: true,
      children: [_codeBlock(context, raw)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool zh = _isZhLocale(context);
    final ThemeData theme = Theme.of(context);

    final List<Widget> children = <Widget>[];

    if ((widget.title ?? '').trim().isNotEmpty) {
      children.add(
        Text(
          widget.title!.trim(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      children.add(const SizedBox(height: AppTheme.spacing2));
    }

    if (widget.leadingOrphans.isNotEmpty) {
      final String orphansText = widget.leadingOrphans.join('\n').trimRight();
      children.add(
        _expandableSection(
          context,
          title: zh
              ? '日志可能被截断（出现未归属行）'
              : 'Logs may be truncated (orphan lines)',
          subtitle: zh ? '展开查看原始孤儿行' : 'Expand to view raw orphan lines',
          monospace: true,
          children: [_codeBlock(context, orphansText, maxHeight: 180)],
        ),
      );
      children.add(const SizedBox(height: AppTheme.spacing2));
    }

    final String rawFallback = _sanitizeDisplayText(
      widget.rawFallbackText ?? '',
    );
    final bool showFallback =
        widget.traces.isEmpty && rawFallback.trim().isNotEmpty;
    if (showFallback) {
      children.add(
        _sectionCard(
          context,
          title: zh ? '无法解析，显示原始内容' : 'Unparsed (raw)',
          copyText: rawFallback,
          monospace: true,
          children: [_codeBlock(context, rawFallback, maxHeight: 520)],
        ),
      );
    } else if (widget.traces.isEmpty) {
      children.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacing4),
            child: Text(
              widget.emptyText ?? (zh ? '暂无日志' : 'No logs'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    } else {
      final AIRequestTrace tr = widget.traces[_selectedTraceIndex];
      final _RequestViewData req = _getRequestViewData(tr);
      final _ResponseViewData? rsp = _shouldPrepareResponseData()
          ? _getResponseViewData(tr)
          : _getCachedResponseViewData(tr);

      if (_usesViewportPanels) {
        children.add(
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.traces.length > 1) ...[
                  _buildTracePicker(context),
                  const SizedBox(height: AppTheme.spacing2),
                ],
                Expanded(
                  child: _buildPanelTabs(context, tr, req, rsp, fillBody: true),
                ),
              ],
            ),
          ),
        );
      } else {
        if (widget.traces.length > 1) {
          children.add(_buildTracePicker(context));
          children.add(const SizedBox(height: AppTheme.spacing2));
        }
        children.add(_buildPanelTabs(context, tr, req, rsp));
      }
    }

    final ThemeData compactTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: 0.92),
    );
    final Widget body = Theme(
      data: compactTheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    final Widget interactiveBody = _buildHorizontalSwipeScope(body);

    if (_usesViewportPanels) {
      final double height = widget.maxHeight ?? 520;
      return SizedBox(height: height, child: interactiveBody);
    }

    if (!widget.scrollable) return interactiveBody;
    final double height = widget.maxHeight ?? 520;
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: interactiveBody,
        ),
      ),
    );
  }
}

class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.child, required this.onChange});

  final Widget child;
  final ValueChanged<Size> onChange;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Size? size = context.size;
      if (size == null) return;
      if (_oldSize == size) return;
      _oldSize = size;
      widget.onChange(size);
    });
    return widget.child;
  }
}

class _RequestViewData {
  const _RequestViewData({
    required this.isSegmentStyle,
    this.requestMeta = const <String, String>{},
    this.promptText = '',
    this.rawPrompt = '',
    this.images = const <_SegmentImageItem>[],
    this.imageIndex = const <_PromptImageIndexItem>[],
    this.requestBlock = '',
    this.bodyFallback = '',
  });

  final bool isSegmentStyle;
  final Map<String, String> requestMeta;
  final String promptText;
  final String rawPrompt;
  final List<_SegmentImageItem> images;
  final List<_PromptImageIndexItem> imageIndex;
  final String requestBlock;
  final String bodyFallback;
}

class _ResponseViewData {
  const _ResponseViewData({
    required this.mergedText,
    required this.displayText,
    required this.rawText,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final String mergedText;
  final String displayText;
  final String rawText;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

class _SegmentImageItem {
  const _SegmentImageItem({
    required this.number,
    required this.time,
    required this.app,
    required this.file,
    required this.path,
    required this.mime,
    required this.bytes,
    required this.packageName,
  });

  final int number;
  final String time;
  final String app;
  final String file;
  final String path;
  final String mime;
  final int? bytes;
  final String packageName;
}

class _PromptImageIndexItem {
  const _PromptImageIndexItem({
    required this.number,
    required this.time,
    required this.app,
  });

  final int number;
  final String time;
  final String app;
}

class _OverviewStatItem {
  const _OverviewStatItem({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;
}

class _UsageBox {
  _UsageBox({this.promptTokens, this.completionTokens, this.totalTokens});

  int? promptTokens;
  int? completionTokens;
  int? totalTokens;
}

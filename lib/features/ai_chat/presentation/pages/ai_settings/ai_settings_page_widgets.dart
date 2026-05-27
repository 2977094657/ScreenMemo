part of '../ai_settings_page.dart';

// Extracted widgets/helpers from ai_settings_page.dart (kept in same library via part).

bool _isZhLocaleUi(BuildContext context) {
  try {
    return Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
  } catch (_) {
    return true;
  }
}

String _coarsenToolLabelForDisplay(String label) {
  String s = label.trim();
  if (s.isEmpty) return '';

  // Drop time parts: keep YYYY-MM-DD only.
  s = s.replaceAllMapped(
    RegExp(r'(\d{4}-\d{2}-\d{2})[ T]\d{2}:\d{2}(?::\d{2})?'),
    (m) => m.group(1) ?? m.group(0) ?? '',
  );

  // Collapse date ranges like "2026-01-18–2026-01-18" to a single date.
  s = s.replaceAllMapped(
    RegExp(r'(\d{4}-\d{2}-\d{2})\s*[–-]\s*(\d{4}-\d{2}-\d{2})'),
    (m) {
      final String a = (m.group(1) ?? '').trim();
      final String b = (m.group(2) ?? '').trim();
      if (a.isEmpty || b.isEmpty) return m.group(0) ?? '';
      return a == b ? a : '$a–$b';
    },
  );

  return s;
}

String _normalizeToolSummaryForDisplay(
  BuildContext context, {
  required String toolName,
  required String summary,
}) {
  String s = summary.trim();
  if (s.isEmpty) return '';
  if (!_isZhLocaleUi(context)) return s;

  // If it's already Chinese, keep it.
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(s)) return s;

  final String low = s.toLowerCase();
  if (low.startsWith('skipped')) return '已跳过';
  if (low == 'ok') return '完成';
  if (low == 'retrieved') return '已获取';
  if (low == 'no images') return '无图片';
  final Match? mGenerated = RegExp(
    r'generated\s+(\d+)\s+image',
    caseSensitive: false,
  ).firstMatch(s);
  if (mGenerated != null) {
    final int count = int.tryParse(mGenerated.group(1) ?? '') ?? 0;
    return count <= 0 ? '未生成图片' : '已生成 $count 张';
  }
  if (low == 'no images generated') return '未生成图片';
  if (low.startsWith('error=')) {
    final int i = s.indexOf('=');
    return i >= 0 ? '错误：${s.substring(i + 1)}' : '错误';
  }

  // "found 1944 (page 3)" / "found 3"
  final Match? mFound = RegExp(
    r'found\s+(\d+)(?:\s*\(page\s+(\d+)\))?',
    caseSensitive: false,
  ).firstMatch(s);
  if (mFound != null) {
    final int a = int.tryParse(mFound.group(1) ?? '') ?? -1;
    final int b = int.tryParse(mFound.group(2) ?? '') ?? -1;
    if (a >= 0 && b >= 0 && a != b) return '找到 $a 个（本页 $b）';
    if (a >= 0) return '找到 $a 个';
  }

  // "returned 10"
  final Match? mReturned = RegExp(
    r'returned\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(s);
  if (mReturned != null) {
    final int c = int.tryParse(mReturned.group(1) ?? '') ?? -1;
    if (c >= 0) return '返回 $c 条';
  }

  // "loaded 3 (missing 1, skipped 2)" / "loaded 3"
  final Match? mLoaded = RegExp(
    r'loaded\s+(\d+)(?:\s*\(([^)]*)\))?',
    caseSensitive: false,
  ).firstMatch(s);
  if (mLoaded != null) {
    final int provided = int.tryParse(mLoaded.group(1) ?? '') ?? -1;
    if (provided >= 0) {
      final String head = '已加载 $provided 张';
      final String extrasRaw = (mLoaded.group(2) ?? '').trim();
      if (extrasRaw.isEmpty) return head;
      final List<String> extras = <String>[];
      final Match? mMissing = RegExp(
        r'missing\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(extrasRaw);
      final Match? mSkipped = RegExp(
        r'skipped\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(extrasRaw);
      final int missing = int.tryParse(mMissing?.group(1) ?? '') ?? 0;
      final int skipped = int.tryParse(mSkipped?.group(1) ?? '') ?? 0;
      if (missing > 0) extras.add('缺失 $missing');
      if (skipped > 0) extras.add('跳过 $skipped');
      return extras.isEmpty ? head : '$head（${extras.join('，')}）';
    }
  }

  // Legacy summaries from older versions:
  // - count=3 / count=3 total=1944
  final Match? mCount = RegExp(
    r'count=(\d+)(?:\s+total=(\d+))?',
    caseSensitive: false,
  ).firstMatch(s);
  if (mCount != null) {
    final int c = int.tryParse(mCount.group(1) ?? '') ?? -1;
    final int t = int.tryParse(mCount.group(2) ?? '') ?? -1;
    if (c >= 0 && t >= 0 && t != c) return '找到 $t 个（本页 $c）';
    if (c >= 0) return '找到 $c 个';
  }

  // - provided=5 missing=1 skipped=2
  final Match? mImgs = RegExp(
    r'provided=(\d+)\s+missing=(\d+)\s+skipped=(\d+)',
    caseSensitive: false,
  ).firstMatch(s);
  if (mImgs != null) {
    final int provided = int.tryParse(mImgs.group(1) ?? '') ?? 0;
    final int missing = int.tryParse(mImgs.group(2) ?? '') ?? 0;
    final int skipped = int.tryParse(mImgs.group(3) ?? '') ?? 0;
    if (provided <= 0 && missing <= 0 && skipped <= 0) return '无图片';
    final String head = '已加载 $provided 张';
    final List<String> extras = <String>[];
    if (missing > 0) extras.add('缺失 $missing');
    if (skipped > 0) extras.add('跳过 $skipped');
    return extras.isEmpty ? head : '$head（${extras.join('，')}）';
  }

  // - segment_id=123 count=10 / segment_id=123
  if (toolName == 'get_segment_result') return '已获取';
  if (toolName == 'get_segment_samples') {
    final Match? mSegCount = RegExp(
      r'count=(\d+)',
      caseSensitive: false,
    ).firstMatch(s);
    final int c = int.tryParse(mSegCount?.group(1) ?? '') ?? -1;
    if (c >= 0) return '返回 $c 条';
    return '返回';
  }

  return s;
}

String _toolChipTextForDisplay(BuildContext context, _ThinkingToolChip chip) {
  final String rawSummary = (chip.resultSummary ?? '').trim();
  final String summary = _normalizeToolSummaryForDisplay(
    context,
    toolName: chip.toolName,
    summary: rawSummary,
  );
  final String baseLabel = chip.label.trim().isEmpty
      ? chip.toolName
      : chip.label.trim();
  final String normalizedLabel = _coarsenToolLabelForDisplay(baseLabel);
  return summary.isEmpty ? normalizedLabel : '$normalizedLabel · $summary';
}

String _formatToolDurationMs(int? durationMs) {
  final int ms = durationMs ?? 0;
  if (ms <= 0) return '';
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000.0).toStringAsFixed(1)}s';
}

String _hostFromUrl(String url) {
  final Uri? uri = Uri.tryParse(url.trim());
  final String host = uri?.host.trim() ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

String _hostFromText(String value) {
  String s = value.trim();
  if (s.isEmpty) return '';
  s = s.replaceFirst(RegExp(r'^site:', caseSensitive: false), '').trim();
  final Uri? uri = Uri.tryParse(s);
  final String parsedHost = uri?.host.trim() ?? '';
  if (parsedHost.isNotEmpty) {
    return parsedHost.startsWith('www.') ? parsedHost.substring(4) : parsedHost;
  }
  s = s.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
  s = s.split(RegExp(r'[,\s]+')).first.trim();
  s = s.split('/').first.split('?').first.split('#').first;
  if (s.contains('@')) s = s.split('@').last;
  if (s.contains(':')) s = s.split(':').first;
  return s.startsWith('www.') ? s.substring(4) : s;
}

Uri? _externalUriFromUrl(String url) {
  final Uri? uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.trim().isEmpty) return null;
  final String scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return uri;
}

String _faviconUrlForHost(String host) {
  final String h = _hostFromText(host);
  if (h.isEmpty) return '';
  return 'https://favicon.im/${Uri.encodeComponent(h)}';
}

Color _webSearchBlue(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? const Color(0xFF7DB7FF) : const Color(0xFF2563EB);
}

Color _webSearchPanelColor(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return _webSearchBlue(context).withValues(alpha: dark ? 0.12 : 0.07);
}

Color _webSearchItemColor(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return _webSearchBlue(context).withValues(alpha: dark ? 0.16 : 0.08);
}

Color _webSearchBorderColor(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return _webSearchBlue(context).withValues(alpha: dark ? 0.28 : 0.18);
}

bool _webSearchCallActive(AIWebSearchCall call) {
  final String status = (call.status ?? '').trim();
  return status == 'in_progress' || status == 'searching';
}

Future<void> _openExternalUrl(String url) async {
  final Uri? uri = _externalUriFromUrl(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class _WebSearchCallsCard extends StatefulWidget {
  const _WebSearchCallsCard({required this.calls});

  final List<AIWebSearchCall> calls;

  @override
  State<_WebSearchCallsCard> createState() => _WebSearchCallsCardState();
}

class _WebSearchCallsCardState extends State<_WebSearchCallsCard> {
  bool _expanded = true;
  Timer? _elapsedTimer;
  DateTime? _localStartedAt;

  List<AIWebSearchCall> get _visibleCalls => widget.calls
      .where((AIWebSearchCall call) => !call.isEmpty)
      .toList(growable: false);

  bool get _isLoading => _visibleCalls.any(_webSearchCallActive);

  @override
  void initState() {
    super.initState();
    _expanded = _isLoading;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _WebSearchCallsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool wasLoading = oldWidget.calls.any(_webSearchCallActive);
    final bool isLoading = _isLoading;
    if (!wasLoading && isLoading) {
      _expanded = true;
      _localStartedAt ??= DateTime.now();
    }
    if (wasLoading && !isLoading) {
      _expanded = false;
    }
    if (wasLoading != isLoading) _syncTimer();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (_isLoading) {
      _localStartedAt ??= DateTime.now();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<AIWebSearchCall> visible = _visibleCalls;
    if (visible.isEmpty) return const SizedBox.shrink();
    final bool zh = _isZhLocaleUi(context);
    final bool loading = _isLoading;
    final Color accent = _webSearchBlue(context);
    final String title = loading
        ? (zh ? '联网搜索 · 搜索中' : 'Web search · Searching')
        : (zh ? '联网搜索过程' : 'Web search process');
    final String duration = _durationLabel(visible, loading);

    return Material(
      color: _webSearchPanelColor(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: _webSearchBorderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    _Shimmer(
                      active: loading,
                      baseColor: accent,
                      child: Icon(
                        Icons.travel_explore_rounded,
                        size: 16,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Shimmer(
                        active: loading,
                        baseColor: accent,
                        child: Text(
                          title,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (duration.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        duration,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              for (int i = 0; i < visible.length; i++) ...[
                _WebSearchCallLine(call: visible[i]),
                if (i != visible.length - 1)
                  const SizedBox(height: AppTheme.spacing1),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _durationLabel(List<AIWebSearchCall> calls, bool loading) {
    int? startedAtMs;
    int? completedAtMs;
    int? durationMs;
    for (final AIWebSearchCall call in calls) {
      final int start = call.startedAtMs ?? 0;
      if (start > 0 && (startedAtMs == null || start < startedAtMs)) {
        startedAtMs = start;
      }
      final int completed = call.completedAtMs ?? 0;
      if (completed > 0 &&
          (completedAtMs == null || completed > completedAtMs)) {
        completedAtMs = completed;
      }
      final int duration = call.durationMs ?? 0;
      if (duration > 0 && (durationMs == null || duration > durationMs)) {
        durationMs = duration;
      }
    }
    if (durationMs == null && startedAtMs != null && completedAtMs != null) {
      durationMs = completedAtMs - startedAtMs;
    }
    if (loading) {
      final DateTime? start = startedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startedAtMs)
          : _localStartedAt;
      if (start == null) return '';
      durationMs = DateTime.now().difference(start).inMilliseconds;
    }
    return _formatWebSearchDurationMs(durationMs);
  }
}

String _formatWebSearchDurationMs(int? durationMs) {
  final int ms = durationMs ?? 0;
  if (ms <= 0) return '';
  if (ms < 1000) return '${(ms / 1000.0).toStringAsFixed(1)}s';
  final int totalSeconds = (ms / 1000).round().clamp(0, 24 * 3600);
  final int h = totalSeconds ~/ 3600;
  final int m = (totalSeconds % 3600) ~/ 60;
  final int s = totalSeconds % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _WebSearchCallLine extends StatelessWidget {
  const _WebSearchCallLine({required this.call});

  final AIWebSearchCall call;

  @override
  Widget build(BuildContext context) {
    final String actionType = (call.actionType ?? '').trim();
    final String action = _actionText(context, call);
    final String status = _statusText(context, call.status, actionType);
    final String? host = _hostText(call);
    final String url = _primaryUrl(call);
    final List<_SearchQueryDisplay> queries = _queryDisplays(call);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actionType != 'search')
          _WebActionLine(
            action: actionType == 'open_page' ? '' : action,
            status: status,
            url: url,
            host: host,
            icon: actionType == 'open_page'
                ? Icons.link_rounded
                : Icons.travel_explore_rounded,
          ),
        if (queries.isNotEmpty) ...[
          if (actionType != 'search') const SizedBox(height: 4),
          for (int i = 0; i < queries.length; i++) ...[
            _SearchQueryLine(query: queries[i]),
            if (i != queries.length - 1) const SizedBox(height: 3),
          ],
        ],
        if (call.sources.isNotEmpty) ...[
          const SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < call.sources.take(4).length; i++) ...[
                _WebSearchSourceTile(source: call.sources[i]),
                if (i != call.sources.take(4).length - 1)
                  const SizedBox(height: 4),
              ],
            ],
          ),
        ],
      ],
    );
  }

  String _actionText(BuildContext context, AIWebSearchCall call) {
    final bool zh = _isZhLocaleUi(context);
    switch ((call.actionType ?? '').trim()) {
      case 'open_page':
        return zh ? '查看网页' : 'View page';
      case 'find_in_page':
        return zh ? '页内查找' : 'Find in page';
      case 'search':
        return zh ? '联网搜索' : 'Web search';
      default:
        return zh ? '联网搜索' : 'Web search';
    }
  }

  List<_SearchQueryDisplay> _queryDisplays(AIWebSearchCall call) {
    final List<String> rawQueries = <String>[
      if ((call.query ?? '').trim().isNotEmpty) call.query!.trim(),
      ...call.queries.map((String e) => e.trim()).where((e) => e.isNotEmpty),
    ];
    final Set<String> seen = <String>{};
    final List<_SearchQueryDisplay> out = <_SearchQueryDisplay>[];
    for (final String raw in rawQueries) {
      if (!seen.add(raw)) continue;
      out.add(_SearchQueryDisplay.parse(raw));
    }
    if (out.isNotEmpty) return out;

    final String pattern = (call.pattern ?? '').trim();
    final String url = (call.url ?? '').trim();
    final String host = _hostFromUrl(url);
    if (pattern.isNotEmpty) {
      return <_SearchQueryDisplay>[
        _SearchQueryDisplay(keyword: pattern, site: host.isEmpty ? null : host),
      ];
    }
    return const <_SearchQueryDisplay>[];
  }

  String _statusText(BuildContext context, String? raw, String actionType) {
    final String status = (raw ?? '').trim();
    if (status.isEmpty) return '';
    final bool zh = _isZhLocaleUi(context);
    if (!zh) return status;
    switch (status) {
      case 'completed':
        if (actionType == 'open_page') return '已查看';
        return '已完成';
      case 'in_progress':
      case 'searching':
        return '搜索中';
      case 'failed':
        return '失败';
      default:
        return status;
    }
  }

  String? _hostText(AIWebSearchCall call) {
    final String direct = _hostFromUrl((call.url ?? '').trim());
    if (direct.isNotEmpty) return direct;
    for (final AIWebSearchSource source in call.sources) {
      final String host = _hostFromUrl(source.url.trim());
      if (host.isNotEmpty) return host;
    }
    return null;
  }

  String _primaryUrl(AIWebSearchCall call) {
    final String direct = (call.url ?? '').trim();
    if (_externalUriFromUrl(direct) != null) return direct;
    for (final AIWebSearchSource source in call.sources) {
      final String url = source.url.trim();
      if (_externalUriFromUrl(url) != null) return url;
    }
    return '';
  }
}

class _WebActionLine extends StatelessWidget {
  const _WebActionLine({
    required this.action,
    required this.status,
    required this.url,
    required this.host,
    required this.icon,
  });

  final String action;
  final String status;
  final String url;
  final String? host;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color accent = _webSearchBlue(context);
    final String iconHost = _hostFromText(
      (host ?? '').isNotEmpty ? host! : url,
    );
    final TextStyle? style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.25,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        color: _webSearchItemColor(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: iconHost.isNotEmpty
                ? _WebSourceAvatar(host: iconHost, color: accent)
                : Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  if (action.isNotEmpty)
                    TextSpan(
                      text: action,
                      style: style?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  if (url.isNotEmpty) ...[
                    if (action.isNotEmpty) const TextSpan(text: '  '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _InlineWebLink(url: url, host: host),
                    ),
                  ],
                  if (status.isNotEmpty) TextSpan(text: ' · $status'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchQueryDisplay {
  const _SearchQueryDisplay({required this.keyword, this.site});

  final String keyword;
  final String? site;

  static final RegExp _sitePrefix = RegExp(r'\bsite:([^\s]+)\s*');

  factory _SearchQueryDisplay.parse(String raw) {
    String keyword = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final List<String> sites = <String>[];
    keyword = keyword.replaceAllMapped(_sitePrefix, (Match match) {
      final String site = (match.group(1) ?? '').trim();
      if (site.isNotEmpty) sites.add(site);
      return '';
    }).trim();
    return _SearchQueryDisplay(
      keyword: keyword.isEmpty ? raw.trim() : keyword,
      site: sites.isEmpty ? null : sites.join(', '),
    );
  }
}

class _SearchQueryLine extends StatelessWidget {
  const _SearchQueryLine({required this.query});

  final _SearchQueryDisplay query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String siteHost = _hostFromText(query.site ?? '');
    final TextStyle? style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.25,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        color: _webSearchItemColor(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: siteHost.isNotEmpty
                ? _WebSourceAvatar(
                    host: siteHost,
                    color: _webSearchBlue(context),
                  )
                : Icon(
                    Icons.search_rounded,
                    size: 14,
                    color: _webSearchBlue(context),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((query.site ?? '').trim().isNotEmpty)
                  Text(
                    query.site!.trim(),
                    overflow: TextOverflow.ellipsis,
                    style: style?.copyWith(fontWeight: FontWeight.w700),
                  ),
                Text(
                  query.keyword,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSourceAvatar extends StatelessWidget {
  const _WebSourceAvatar({required this.host, required this.color});

  final String? host;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String h = _hostFromText(host ?? '');
    if (h.isEmpty) {
      return Icon(Icons.travel_explore_rounded, size: 16, color: color);
    }
    final String normalized = h.replaceFirst(RegExp(r'^www\.'), '');
    final String letter = normalized.isEmpty ? '' : normalized[0].toUpperCase();
    final Widget fallback = Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
    final String faviconUrl = _faviconUrlForHost(h);
    if (faviconUrl.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        faviconUrl,
        width: 16,
        height: 16,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _InlineWebLink extends StatelessWidget {
  const _InlineWebLink({required this.url, required this.host});

  final String url;
  final String? host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color accent = _webSearchBlue(context);
    final String label = (host ?? '').trim().isNotEmpty ? host!.trim() : url;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _openExternalUrl(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent,
                    decoration: TextDecoration.underline,
                    decorationColor: accent,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebSearchSourceTile extends StatelessWidget {
  const _WebSearchSourceTile({required this.source});

  final AIWebSearchSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String title = (source.title ?? '').trim();
    final String host = _hostFromUrl(source.url.trim());
    final String label = title.isNotEmpty
        ? title
        : (host.isNotEmpty ? host : source.url.trim());
    if (label.isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      onTap: () => _openExternalUrl(source.url),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
          border: Border.all(color: _webSearchBorderColor(context)),
          color: _webSearchItemColor(context),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: _WebSourceAvatar(
                host: host,
                color: _webSearchBlue(context),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UrlCitationsRow extends StatelessWidget {
  const _UrlCitationsRow({required this.citations});

  final List<AIUrlCitation> citations;

  @override
  Widget build(BuildContext context) {
    final List<AIUrlCitation> visible = citations
        .where((AIUrlCitation e) => e.url.trim().isNotEmpty)
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final bool zh = _isZhLocaleUi(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
          child: Text(
            zh ? '来源' : 'Sources',
            style: theme.textTheme.labelSmall?.copyWith(
              color: _webSearchBlue(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < visible.length; i++) ...[
              _UrlCitationTile(index: i + 1, citation: visible[i]),
              if (i != visible.length - 1)
                const SizedBox(height: AppTheme.spacing1),
            ],
          ],
        ),
      ],
    );
  }
}

class _UrlCitationTile extends StatelessWidget {
  const _UrlCitationTile({required this.index, required this.citation});

  final int index;
  final AIUrlCitation citation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String title = (citation.title ?? '').trim();
    final String host = _hostFromUrl(citation.url.trim());
    final String label = title.isNotEmpty
        ? title
        : (host.isNotEmpty ? host : citation.url.trim());

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () => _openExternalUrl(citation.url),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: _webSearchBorderColor(context)),
          color: _webSearchPanelColor(context),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                '$index',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _webSearchBlue(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 16,
              height: 16,
              child: _WebSourceAvatar(
                host: host,
                color: _webSearchBlue(context),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingTimelineCard extends StatefulWidget {
  const _ThinkingTimelineCard({
    super.key,
    required this.conversationId,
    required this.assistantCreatedAt,
    required this.createdAt,
    required this.finishedAt,
    required this.events,
    this.reasoningContent,
    this.fallbackReasoning,
    this.autoCloseOnFinish = true,
  });

  final String conversationId;
  final int assistantCreatedAt;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final List<_ThinkingEvent> events;
  final String? reasoningContent;
  final String? fallbackReasoning;
  final bool autoCloseOnFinish;

  bool get isLoading => finishedAt == null;

  @override
  State<_ThinkingTimelineCard> createState() => _ThinkingTimelineCardState();
}

class _ThinkingTimelineCardState extends State<_ThinkingTimelineCard> {
  bool _expanded = true;
  bool _showAllSteps = false;
  Timer? _elapsedTimer;
  final ScrollController _fallbackScrollController = ScrollController();
  Map<String, Uint8List?> _appIconByPackage = <String, Uint8List?>{};
  Map<String, Uint8List?> _appIconByNameLower = <String, Uint8List?>{};
  bool _appIconCacheLoaded = false;

  void _warmAppIconCache() {
    if (_appIconCacheLoaded) return;
    unawaited(() async {
      try {
        final cachedApps = await AppSelectionService.instance
            .getCachedAppInfoByPackage();
        var apps = await AppSelectionService.instance.getSelectedApps();
        // Selected apps carry cached icons (no platform plugin call). If empty,
        // fall back to installed app scan on Android only.
        if (apps.isEmpty && Platform.isAndroid) {
          apps = await AppSelectionService.instance.getAllInstalledApps();
        }

        final Map<String, Uint8List?> byPkg = <String, Uint8List?>{};
        final Map<String, Uint8List?> byName = <String, Uint8List?>{};
        for (final a in cachedApps.values) {
          final String pkg = a.packageName.trim();
          if (pkg.isNotEmpty) byPkg[pkg] = a.icon;
          final String nameKey = a.appName.trim().toLowerCase();
          if (nameKey.isNotEmpty) byName[nameKey] = a.icon;
        }
        for (final a in apps) {
          final String pkg = a.packageName.trim();
          if (pkg.isNotEmpty) byPkg[pkg] = a.icon;
          final String nameKey = a.appName.trim().toLowerCase();
          if (nameKey.isNotEmpty) byName[nameKey] = a.icon;
        }
        if (!mounted) return;
        setState(() {
          _appIconByPackage = byPkg;
          _appIconByNameLower = byName;
          _appIconCacheLoaded = true;
        });
      } catch (_) {
        // Best-effort; tool chips will fall back to generic icons.
        if (!mounted) return;
        setState(() => _appIconCacheLoaded = true);
      }
    }());
  }

  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (widget.isLoading) {
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.isLoading;
    _syncElapsedTimer();
    _warmAppIconCache();
  }

  @override
  void didUpdateWidget(covariant _ThinkingTimelineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading != widget.isLoading) {
      _syncElapsedTimer();
    }
    if (oldWidget.isLoading && !widget.isLoading && widget.autoCloseOnFinish) {
      if (mounted) setState(() => _expanded = false);
    }
    if (!oldWidget.isLoading && widget.isLoading) {
      if (mounted) setState(() => _expanded = true);
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _fallbackScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final Color titleColor = _thinkingTextColor;
    final Color subtle = _thinkingTextColor;
    final Color panelBg = _thinkingPanelColor(theme);
    final String titleText = widget.isLoading
        ? l10n.thinkingInProgress
        : l10n.deepThinkingLabel;
    final String fallback = (widget.fallbackReasoning ?? '').trim();

    final Duration elapsed = (widget.finishedAt ?? DateTime.now()).difference(
      widget.createdAt,
    );

    return Material(
      color: panelBg,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _Shimmer(
                        active: widget.isLoading,
                        baseColor: titleColor,
                        child: Text(
                          titleText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: titleColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(elapsed),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: subtle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: titleColor,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.events.isNotEmpty) _buildEventTimeline(context),
                    if (fallback.isNotEmpty) ...[
                      if (widget.events.isNotEmpty)
                        const SizedBox(height: AppTheme.spacing2),
                      _buildFallbackReasoning(context, fallback, subtle),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _thinkingPanelColor(ThemeData theme) {
    final double alpha = theme.brightness == Brightness.dark ? 0.26 : 0.50;
    return theme.colorScheme.tertiaryContainer.withValues(alpha: alpha);
  }

  Widget _buildFallbackReasoning(
    BuildContext context,
    String fallback,
    Color textColor,
  ) {
    final theme = Theme.of(context);
    final TextStyle? bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: textColor,
      height: 1.25,
    );
    final TextStyle? headingStyle = bodyStyle?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final cfg = MarkdownMathConfig(
      inlineTextStyle: bodyStyle,
      blockTextStyle: bodyStyle,
    );
    final String mdData = preprocessForChatMarkdown(fallback);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Scrollbar(
        controller: _fallbackScrollController,
        child: SingleChildScrollView(
          controller: _fallbackScrollController,
          physics: const ClampingScrollPhysics(),
          child: MarkdownBody(
            selectable: true,
            data: mdData,
            builders: cfg.builders,
            blockSyntaxes: cfg.blockSyntaxes,
            inlineSyntaxes: cfg.inlineSyntaxes,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: bodyStyle,
              listBullet: bodyStyle,
              code: bodyStyle?.copyWith(
                fontFamily: 'monospace',
                backgroundColor: theme.colorScheme.surface.withValues(
                  alpha: 0.18,
                ),
              ),
              h1: headingStyle,
              h2: headingStyle,
              h3: headingStyle,
              h4: headingStyle,
              h5: headingStyle,
              h6: headingStyle,
              blockquote: bodyStyle,
              blockquotePadding: const EdgeInsets.all(8),
              blockquoteDecoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              codeblockPadding: const EdgeInsets.all(8),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              blockSpacing: 6,
              listIndent: 18,
            ),
            onTapLink: (text, href, title) async {
              if (href == null) return;
              final uri = Uri.tryParse(href);
              if (uri == null) return;
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEventTimeline(BuildContext context) {
    const int collapsedVisibleCount = 2;
    final theme = Theme.of(context);
    final bool canCollapse = widget.events.length > collapsedVisibleCount;
    final List<_ThinkingEvent> visibleEvents = canCollapse && !_showAllSteps
        ? widget.events.sublist(widget.events.length - collapsedVisibleCount)
        : widget.events;
    final int hiddenCount = widget.events.length - visibleEvents.length;
    final String toggleText = _isZhLocaleUi(context)
        ? (_showAllSteps ? '收起步骤' : '显示 $hiddenCount 个较早步骤')
        : (_showAllSteps
              ? 'Collapse steps'
              : 'Show $hiddenCount earlier steps');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canCollapse)
          InkWell(
            onTap: () => setState(() => _showAllSteps = !_showAllSteps),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: Icon(
                      _showAllSteps
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    toggleText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < visibleEvents.length; i++)
              _buildEventRow(
                context,
                visibleEvents[i],
                isLast: i == visibleEvents.length - 1,
              ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    if (d.inMilliseconds < 1000) {
      final double secs = d.inMilliseconds / 1000.0;
      return '${secs.toStringAsFixed(1)}s';
    }
    final int totalSeconds = d.inSeconds.clamp(0, 24 * 3600);
    final int h = totalSeconds ~/ 3600;
    final int m = (totalSeconds % 3600) ~/ 60;
    final int s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildEventRow(
    BuildContext context,
    _ThinkingEvent e, {
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final Color titleColor = _thinkingTextColor;
    final Color subtitleColor = _thinkingTextColor;

    if (e.type == _ThinkingEventType.reasoning) {
      final String text = _reasoningSlice(e).trim();
      if (text.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
        child: _buildFallbackReasoning(context, text, titleColor),
      );
    }

    final List<Widget> children = <Widget>[];
    final bool hideEventTitle =
        e.type == _ThinkingEventType.tools && e.tools.isNotEmpty;
    if (!hideEventTitle) {
      Widget title = Text(
        e.title,
        style: theme.textTheme.bodySmall?.copyWith(
          color: titleColor,
          fontWeight: FontWeight.w600,
        ),
      );
      // Only shimmer while the block is still loading; stale persisted `active`
      // flags (e.g. after background completion) should not keep shimmering.
      title = _Shimmer(
        active: widget.isLoading && e.active,
        baseColor: titleColor,
        child: title,
      );
      children.add(title);
    }

    final String sub = (e.subtitle ?? '').trim();
    if (sub.isNotEmpty && !hideEventTitle) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            sub,
            style: theme.textTheme.bodySmall?.copyWith(
              color: subtitleColor,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    if (e.type == _ThinkingEventType.tools && e.tools.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < e.tools.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == e.tools.length - 1 ? 0 : 6,
                ),
                child: _buildToolChip(context, e.tools[i]),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  String _reasoningSlice(_ThinkingEvent e) {
    final String full = widget.reasoningContent ?? '';
    final int start = (e.reasoningStart ?? -1);
    final int len = (e.reasoningLength ?? 0);
    if (full.isEmpty || start < 0 || len <= 0 || start >= full.length) {
      return '';
    }
    final int end = (start + len).clamp(start, full.length).toInt();
    return full.substring(start, end);
  }

  IconData _toolIconFor(String toolName) {
    switch (toolName) {
      case 'generate_image':
        return Icons.auto_awesome_outlined;
      case 'get_images':
        return Icons.image_rounded;
      case 'search_screenshots_ocr':
        return Icons.document_scanner_rounded;
      case 'search_ai_image_meta':
        return Icons.image_search_rounded;
      case 'search_segments':
        return Icons.manage_search_rounded;
      case 'search_segments_ocr':
        return Icons.text_snippet_rounded;
      case 'get_segment_result':
        return Icons.description_rounded;
      case 'get_segment_samples':
        return Icons.collections_rounded;
      default:
        if (toolName.startsWith('search_')) return Icons.search_rounded;
        if (toolName.startsWith('get_')) return Icons.download_rounded;
        return Icons.build_circle_outlined;
    }
  }

  Widget _buildToolChip(BuildContext context, _ThinkingToolChip chip) {
    final theme = Theme.of(context);
    final bool isSearch = chip.toolName.startsWith('search_');
    final Color bg =
        (isSearch
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.secondaryContainer)
            .withValues(alpha: 0.65);
    final Color fg = isSearch
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSecondaryContainer;

    final String label = _toolChipTextForDisplay(context, chip);
    final IconData icon = _toolIconFor(chip.toolName);
    final Widget leading = _buildToolChipLeading(
      context,
      theme: theme,
      chip: chip,
      fg: fg,
      fallbackIcon: icon,
      isSearch: isSearch,
    );
    final bool shimmerActive = widget.isLoading && chip.active;

    final String durationLabel = _formatToolDurationMs(chip.durationMs);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: () => _showToolCallDetailSheet(context, chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          // NOTE: Shimmer uses a ShaderMask which tints all descendants.
          // Keep app icons in their original colors during tool execution by
          // shimmering only the label text.
          child: Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: leading),
              const SizedBox(width: 8),
              Expanded(
                child: _Shimmer(
                  active: shimmerActive,
                  baseColor: fg,
                  child: Text(
                    label,
                    softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (durationLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  durationLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: fg.withValues(alpha: 0.75),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showToolCallDetailSheet(
    BuildContext context,
    _ThinkingToolChip chip,
  ) async {
    final String cid = widget.conversationId.trim();
    final int assistantCreatedAt = widget.assistantCreatedAt;
    Future<Map<String, dynamic>?>? future;
    if (cid.isNotEmpty && assistantCreatedAt > 0 && chip.callId.isNotEmpty) {
      future = ScreenshotDatabase.instance.getAiToolCallDetail(
        conversationId: cid,
        assistantCreatedAt: assistantCreatedAt,
        callId: chip.callId,
      );
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ToolCallDetailSheet(chip: chip, detailFuture: future);
      },
    );
  }

  Widget _buildToolChipLeading(
    BuildContext context, {
    required ThemeData theme,
    required _ThinkingToolChip chip,
    required Color fg,
    required IconData fallbackIcon,
    required bool isSearch,
  }) {
    final List<String> byName = chip.appNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final List<String> byPkg = chip.appPackageNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final List<String> keys = byName.isNotEmpty ? byName : byPkg;
    final bool showAppIcons = isSearch && keys.isNotEmpty;
    if (!showAppIcons) {
      return Icon(fallbackIcon, size: 16, color: fg.withValues(alpha: 0.95));
    }

    const int maxIcons = 3;
    final List<String> shown = keys.take(maxIcons).toList(growable: false);
    final int extraCount = keys.length - shown.length;

    final List<Uint8List?> icons = <Uint8List?>[];
    if (byName.isNotEmpty) {
      for (final name in shown) {
        icons.add(_appIconByNameLower[name.toLowerCase()]);
      }
    } else {
      for (final pkg in shown) {
        icons.add(_appIconByPackage[pkg]);
      }
    }

    return _buildAppIconStack(
      context,
      theme: theme,
      fg: fg,
      icons: icons,
      extraCount: extraCount,
    );
  }

  Widget _buildAppIconStack(
    BuildContext context, {
    required ThemeData theme,
    required Color fg,
    required List<Uint8List?> icons,
    required int extraCount,
  }) {
    const double size = 18;
    const double overlap = 6;
    final double step = size - overlap;
    final int shownCount = icons.length;
    final double width =
        size +
        (shownCount <= 1 ? 0 : (shownCount - 1) * step) +
        (extraCount > 0 ? step : 0);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < shownCount; i++)
            Positioned(
              left: i * step,
              child: _buildSingleAppIcon(bytes: icons[i], fg: fg, size: size),
            ),
          if (extraCount > 0)
            Positioned(
              left: shownCount * step,
              child: _buildExtraCountBadge(
                theme,
                extraCount: extraCount,
                fg: fg,
                size: size,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleAppIcon({
    required Uint8List? bytes,
    required Color fg,
    required double size,
  }) {
    final Widget child = bytes != null
        ? Image.memory(bytes, width: size, height: size, fit: BoxFit.contain)
        : Icon(
            Icons.android,
            size: size * 0.75,
            color: fg.withValues(alpha: 0.9),
          );

    // Display the icon as-is; do not add a background behind it.
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: child),
    );
  }

  Widget _buildExtraCountBadge(
    ThemeData theme, {
    required int extraCount,
    required Color fg,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '+$extraCount',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg.withValues(alpha: 0.9),
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}

class _ToolCallDetailSheet extends StatefulWidget {
  const _ToolCallDetailSheet({required this.chip, required this.detailFuture});

  final _ThinkingToolChip chip;
  final Future<Map<String, dynamic>?>? detailFuture;

  @override
  State<_ToolCallDetailSheet> createState() => _ToolCallDetailSheetState();
}

class _ToolCallDetailSheetState extends State<_ToolCallDetailSheet> {
  final Set<String> _expandedSections = <String>{};
  Future<List<_ToolImagePreviewItem>>? _imagePreviewFuture;
  String _imagePreviewFutureKey = '';

  String _loc(String zh, String en) => _isZhLocaleUi(context) ? zh : en;

  String _prettyJson(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(t));
    } catch (_) {
      return t;
    }
  }

  Future<void> _copy(String text) async {
    final String t = text.trim();
    if (t.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: t));
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).copySuccess);
    } catch (_) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).copyFailed);
    }
  }

  String _detailValue(Map<String, dynamic>? detail, String key) {
    final Object? raw = detail?[key];
    return raw?.toString().trim() ?? '';
  }

  Object? _decodeJsonOrNull(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return null;
    try {
      return jsonDecode(t);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeJsonMapOrNull(String raw) {
    final Object? decoded = _decodeJsonOrNull(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  List<String> _stringListFromJsonValue(Object? raw) {
    final List<String> out = <String>[];
    if (raw is List) {
      for (final Object? item in raw) {
        final String value = (item ?? '').toString().trim();
        if (value.isNotEmpty) out.add(value);
      }
    } else if (raw is String) {
      final String value = raw.trim();
      if (value.isNotEmpty) out.add(value);
    }
    return out;
  }

  int? _detailInt(Map<String, dynamic>? detail, String key) {
    final Object? raw = detail?[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  String _fallbackSummary() {
    final String summary = (widget.chip.resultSummary ?? '').trim();
    if (summary.isNotEmpty) return summary;
    return _loc('暂无完整详情', 'No full details yet');
  }

  Map<String, dynamic>? _getImagesToolPayloadFromResult(String resultJson) {
    final Object? decoded = _decodeJsonOrNull(resultJson);
    if (decoded is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      return (map['tool'] ?? '').toString().trim() == 'get_images' ? map : null;
    }
    if (decoded is List) {
      for (final Object? rawItem in decoded) {
        if (rawItem is! Map) continue;
        final Map<String, dynamic> item = Map<String, dynamic>.from(rawItem);
        final String content = (item['content'] ?? '').toString().trim();
        final Map<String, dynamic>? map = _decodeJsonMapOrNull(content);
        if (map == null) continue;
        if ((map['tool'] ?? '').toString().trim() == 'get_images') return map;
      }
    }
    return null;
  }

  List<String> _getImagesPreviewFilenames(Map<String, dynamic>? detail) {
    if (widget.chip.toolName.trim() != 'get_images') return const <String>[];

    final Map<String, dynamic>? resultPayload =
        _getImagesToolPayloadFromResult(_detailValue(detail, 'result_json')) ??
        _decodeJsonMapOrNull(_detailValue(detail, 'result_text'));
    final List<String> provided = _stringListFromJsonValue(
      resultPayload?['provided'],
    );
    final List<String> requested = _stringListFromJsonValue(
      resultPayload?['requested'],
    );
    final Map<String, dynamic>? args = _decodeJsonMapOrNull(
      _detailValue(detail, 'arguments_json'),
    );
    final List<String> argumentNames = _stringListFromJsonValue(
      args?['filenames'],
    );

    final List<String> preferred = provided.isNotEmpty
        ? provided
        : (requested.isNotEmpty ? requested : argumentNames);
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final String name in preferred) {
      final String t = name.trim();
      if (t.isEmpty || t.contains('/') || t.contains('\\')) continue;
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  Future<List<_ToolImagePreviewItem>> _resolveImagePreviewItems(
    List<String> filenames,
  ) async {
    if (filenames.isEmpty) return const <_ToolImagePreviewItem>[];
    final Map<String, String> paths = await ScreenshotDatabase.instance
        .findPathsByBasenames(filenames.toSet());
    final List<_ToolImagePreviewItem> out = <_ToolImagePreviewItem>[];
    for (final String filename in filenames) {
      final String path = (paths[filename] ?? '').trim();
      if (path.isEmpty) continue;
      final File file = File(path);
      if (!await file.exists()) continue;
      out.add(_ToolImagePreviewItem(filename: filename, path: path));
    }
    return out;
  }

  Future<List<_ToolImagePreviewItem>> _imagePreviewFutureFor(
    List<String> filenames,
  ) {
    final String key = filenames.join('\n');
    if (_imagePreviewFuture == null || key != _imagePreviewFutureKey) {
      _imagePreviewFutureKey = key;
      _imagePreviewFuture = _resolveImagePreviewItems(filenames);
    }
    return _imagePreviewFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final Future<Map<String, dynamic>?>? future = widget.detailFuture;
    return UISheetSurface(
      child: SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.86,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: UISheetHandle()),
                const SizedBox(height: 12),
                _buildHeader(context),
                const SizedBox(height: 12),
                Expanded(
                  child: future == null
                      ? _buildDetailBody(context, null)
                      : FutureBuilder<Map<String, dynamic>?>(
                          future: future,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return _buildDetailBody(context, snapshot.data);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final String duration = _formatToolDurationMs(widget.chip.durationMs);
    final String status = widget.chip.active
        ? _loc('运行中', 'Running')
        : _loc('已完成', 'Finished');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Icon(
            Icons.build_circle_outlined,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.chip.label.trim().isEmpty
                    ? widget.chip.toolName
                    : widget.chip.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  widget.chip.toolName,
                  status,
                  if (duration.isNotEmpty) duration,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: _loc('复制摘要', 'Copy summary'),
          onPressed: () => _copy(_fallbackSummary()),
          icon: const Icon(Icons.copy_rounded),
        ),
      ],
    );
  }

  Widget _buildDetailBody(BuildContext context, Map<String, dynamic>? detail) {
    final String args = _prettyJson(_detailValue(detail, 'arguments_json'));
    final String resultJson = _prettyJson(_detailValue(detail, 'result_json'));
    final String resultText = _detailValue(detail, 'result_text');
    final String summary = _detailValue(detail, 'result_summary').isNotEmpty
        ? _detailValue(detail, 'result_summary')
        : _fallbackSummary();
    final int? durationMs =
        _detailInt(detail, 'duration_ms') ?? widget.chip.durationMs;

    return ListView(
      children: [
        _buildMetaRow(
          context,
          label: _loc('调用 ID', 'Call ID'),
          value: widget.chip.callId,
        ),
        if ((widget.chip.detailRef ?? '').trim().isNotEmpty)
          _buildMetaRow(
            context,
            label: _loc('详情引用', 'Detail ref'),
            value: widget.chip.detailRef!.trim(),
          ),
        if (durationMs != null && durationMs > 0)
          _buildMetaRow(
            context,
            label: _loc('耗时', 'Duration'),
            value: _formatToolDurationMs(durationMs),
          ),
        const SizedBox(height: 12),
        _buildTextSection(
          context,
          id: 'summary',
          title: _loc('结果摘要', 'Result summary'),
          text: summary,
          initiallyExpanded: true,
        ),
        if (args.isNotEmpty)
          _buildTextSection(
            context,
            id: 'arguments',
            title: _loc('参数', 'Arguments'),
            text: args,
            monospace: true,
            initiallyExpanded: true,
          ),
        if (widget.chip.toolName.trim() == 'get_images')
          _buildImagePreviewSection(
            context,
            filenames: _getImagesPreviewFilenames(detail),
          ),
        if (resultJson.isNotEmpty)
          _buildTextSection(
            context,
            id: 'result_json',
            title: _loc('结果 JSON', 'Result JSON'),
            text: resultJson,
            monospace: true,
          )
        else if (resultText.isNotEmpty)
          _buildTextSection(
            context,
            id: 'result_text',
            title: _loc('结果文本', 'Result text'),
            text: resultText,
            monospace: true,
          )
        else
          _buildTextSection(
            context,
            id: 'empty',
            title: _loc('完整结果', 'Full result'),
            text: _loc(
              '暂无完整结果，可能是旧历史消息或工具仍在运行。',
              'Full result is not available yet. This may be an older message or a running tool.',
            ),
            initiallyExpanded: true,
          ),
      ],
    );
  }

  Widget _buildImagePreviewSection(
    BuildContext context, {
    required List<String> filenames,
  }) {
    final theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _loc('预览结果', 'Preview'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (filenames.isEmpty)
              Text(
                _loc('没有可预览的图片。', 'No preview images available.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              FutureBuilder<List<_ToolImagePreviewItem>>(
                future: _imagePreviewFutureFor(filenames),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final List<_ToolImagePreviewItem> items =
                      snapshot.data ?? const <_ToolImagePreviewItem>[];
                  if (items.isEmpty) {
                    return Text(
                      _loc(
                        '图片文件未找到，可能已移动或删除。',
                        'Image files were not found. They may have moved or been deleted.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final _ToolImagePreviewItem item in items)
                        _buildImagePreviewTile(context, item),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreviewTile(
    BuildContext context,
    _ToolImagePreviewItem item,
  ) {
    final theme = Theme.of(context);
    final String path = item.path.trim();
    final bool extraNsfwMask =
        NsfwPreferenceService.instance.isAiNsfwCached(filePath: path) ||
        NsfwPreferenceService.instance.isSegmentNsfwCached(filePath: path);
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ScreenshotImageWidget(
            file: File(path),
            privacyMode: true,
            extraNsfwMask: extraNsfwMask,
            width: 104,
            height: 184,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(8),
            targetWidth: 208,
            showNsfwButton: true,
            showTimelineJumpButton: true,
          ),
          const SizedBox(height: 6),
          Text(
            item.filename,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSection(
    BuildContext context, {
    required String id,
    required String title,
    required String text,
    bool monospace = false,
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
    final String content = text.trim();
    final bool long = content.length > 8000;
    final bool expanded = initiallyExpanded || _expandedSections.contains(id);
    final String shown = long && !expanded
        ? '${content.substring(0, 8000)}\n\n...'
        : content;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (long)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_expandedSections.contains(id)) {
                          _expandedSections.remove(id);
                        } else {
                          _expandedSections.add(id);
                        }
                      });
                    },
                    child: Text(
                      expanded
                          ? _loc('收起', 'Collapse')
                          : _loc('展开全文', 'Show full'),
                    ),
                  ),
                IconButton(
                  tooltip: _loc('复制', 'Copy'),
                  onPressed: () => _copy(content),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SelectableText(
              shown,
              style:
                  (monospace
                          ? theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.25,
                            )
                          : theme.textTheme.bodySmall)
                      ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolImagePreviewItem {
  const _ToolImagePreviewItem({required this.filename, required this.path});

  final String filename;
  final String path;
}

// 滚动遮罩组件：当列表不在顶部或底部时显示白色渐变遮罩
class _ScrollMaskWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final Color maskColor;

  const _ScrollMaskWrapper({
    required this.child,
    required this.controller,
    this.maskColor = Colors.white,
  });

  @override
  State<_ScrollMaskWrapper> createState() => _ScrollMaskWrapperState();
}

class _ScrollMaskWrapperState extends State<_ScrollMaskWrapper> {
  bool _showTopMask = false;
  bool _showBottomMask = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateMasks);
    // 延迟检查初始状态，确保列表已渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateMasks();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateMasks);
    super.dispose();
  }

  void _updateMasks() {
    if (!widget.controller.hasClients) return;

    final position = widget.controller.position;
    final atTop = position.pixels <= 0;
    final atBottom = position.pixels >= position.maxScrollExtent;

    setState(() {
      _showTopMask = !atTop;
      _showBottomMask = !atBottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // 顶部遮罩
        if (_showTopMask)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 24,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.maskColor.withOpacity(0.9),
                      widget.maskColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // 底部遮罩
        if (_showBottomMask)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 24,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      widget.maskColor.withOpacity(0.9),
                      widget.maskColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// 流光边框效果组件（输入框边框流光 - Gemini AI 风格）
class _ShimmerBorder extends StatefulWidget {
  final Widget child;
  final bool active; // 是否显示流光动画
  const _ShimmerBorder({super.key, required this.child, this.active = false});

  @override
  State<_ShimmerBorder> createState() => _ShimmerBorderState();
}

class _ShimmerBorderState extends State<_ShimmerBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _kBorderRadius = 24.0;
  static const double _kBorderWidth =
      1.25; // 视觉宽度≈1.5（strokeWidth = 1.25 * 1.2）

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_ShimmerBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 根据 active 状态控制动画
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 普通状态的静态彩色渐变
    final staticGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        Color(0xFF4285F4), // Gemini 蓝
        Color(0xFF9B72F2), // 紫色
        Color(0xFFD946EF), // 品红
        Color(0xFFFF6B9D), // 粉红
        Color(0xFFFBBC04), // 金色
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    // 非激活态：不再包一层渐变容器，避免尺寸变化；仅返回 child
    if (!widget.active) return widget.child;

    // 流光动画边框（叠加高亮，不替换静态渐变）
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * 6.283185307179586; // 2π

        // 流光高亮：去掉灰色拖尾，仅保留彩色高亮，并以透明-彩色-透明的方式过渡
        final sweep = SweepGradient(
          center: Alignment.center,
          colors: const [
            Color(0x00FFFFFF), // 完全透明开始（透明白，避免黑色伪影）
            Color(0x00FFFFFF),
            Color(0xFF4285F4), // 蓝
            Color(0xFF9B72F2), // 紫
            Color(0xFFD946EF), // 品红
            Color(0xFFFF6B9D), // 粉
            Color(0xFFFBBC04), // 金
            Color(0x00FFFFFF), // 透明收尾（透明白）
            Color(0x00FFFFFF),
          ],
          stops: const [0.00, 0.30, 0.40, 0.50, 0.58, 0.66, 0.74, 0.85, 1.00],
          transform: GradientRotation(angle),
        );

        // 仅作为叠加层绘制流光高亮，不改变 child 尺寸
        return Stack(
          children: [
            // 底层直接是 child
            widget.child,
            // 仅裁剪到"边框环形区域"的流光叠加层
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RingSweepPainter(
                    gradient: sweep,
                    borderRadius: _kBorderRadius,
                    borderWidth: _kBorderWidth,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// 仅绘制在"边框环形区域"的流光高亮画笔
class _RingSweepPainter extends CustomPainter {
  final Gradient gradient;
  final double borderRadius;
  final double borderWidth;

  _RingSweepPainter({
    required this.gradient,
    required this.borderRadius,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 与 _ShimmerBorder 的圆角一致的外边界
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 画笔设置为描边，仅覆盖边框区域；2x 线宽让内侧可见宽度≈borderWidth
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth * 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path()..addRRect(outer);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RingSweepPainter oldDelegate) {
    return oldDelegate.gradient != gradient ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth;
  }
}

class _Shimmer extends StatelessWidget {
  final Widget child;
  final bool active;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration period;

  const _Shimmer({
    super.key,
    required this.child,
    required this.active,
    this.baseColor,
    this.highlightColor,
    this.period = const Duration(milliseconds: 2200),
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;

    final Color base =
        baseColor ??
        DefaultTextStyle.of(context).style.color ??
        _thinkingTextColor;
    final Color highlight = highlightColor ?? _thinkingShimmerHighlightColor;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      direction: ShimmerDirection.ltr,
      period: period,
      child: child,
    );
  }
}

MarkdownStyleSheet? _cachedMdStyle;
MarkdownStyleSheet _mdStyle(BuildContext context) {
  final s = _cachedMdStyle;
  if (s != null) return s;
  final ns = MarkdownStyleSheet.fromTheme(
    Theme.of(context),
  ).copyWith(p: Theme.of(context).textTheme.bodyMedium);
  _cachedMdStyle = ns;
  return ns;
}

// 自绘渐变 Icon，避免被主题色覆盖
class _GradientIconPainter extends CustomPainter {
  final List<Color> colors;
  final IconData icon;
  _GradientIconPainter({required this.colors, required this.icon});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size.height,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final offset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect)
      ..blendMode = BlendMode.srcIn;

    // 先绘制到图层，随后用渐变混合
    canvas.saveLayer(rect, Paint());
    textPainter.paint(canvas, offset);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GradientIconPainter oldDelegate) {
    return oldDelegate.colors != colors || oldDelegate.icon != icon;
  }
}

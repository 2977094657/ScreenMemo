part of 'search_page.dart';

// ========== 文档搜索与结果展示 ==========
extension _SearchPageDocsPart on _SearchPageState {
  Widget _buildDocCard(Map<String, dynamic> doc) {
    final String docType = (doc['doc_type'] as String?)?.trim() ?? '';
    final String title = (doc['title'] as String?)?.trim().isNotEmpty == true
        ? (doc['title'] as String).trim()
        : _docTypeLabel(docType);
    final String rawContent = (doc['content'] as String?)?.trim() ?? '';
    final String content = _docContentForDisplay(docType, rawContent);
    final String tags = (doc['tags'] as String?)?.trim() ?? '';
    final int updatedAt = (doc['updated_at'] as int?) ?? 0;

    final String preview = _docPreviewText(content);
    final String when = updatedAt > 0 ? _formatDocUpdatedAt(updatedAt) : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing1),
      child: InkWell(
        onTap: () => _onDocTap(doc),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacing3),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildDocTypeChip(context, _docTypeLabel(docType)),
                  const Spacer(),
                  if (when.isNotEmpty)
                    Text(
                      when,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedForeground,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (tags.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  tags,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
                ),
              ],
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocTypeChip(BuildContext context, String text) {
    final Color c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: c.withOpacity(0.25), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: c,
          height: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _docTypeLabel(String docType) {
    switch (docType.trim()) {
      case kSearchDocTypeFavoriteNote:
        return '收藏备注';
      case kSearchDocTypeDailySummary:
        return '每日总结';
      case kSearchDocTypeMorningInsights:
        return '早报';
      default:
        return docType.trim().isEmpty ? '文档' : docType.trim();
    }
  }

  String _formatDocUpdatedAt(int ts) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      final String mm = dt.month.toString().padLeft(2, '0');
      final String dd = dt.day.toString().padLeft(2, '0');
      final String hh = dt.hour.toString().padLeft(2, '0');
      final String mi = dt.minute.toString().padLeft(2, '0');
      return '$mm-$dd $hh:$mi';
    } catch (_) {
      return '';
    }
  }

  String _docPreviewText(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return '';
    final String compact = s.replaceAll(RegExp(r'\\s+'), ' ');
    if (compact.length <= 160) return compact;
    return compact.substring(0, 160) + '…';
  }

  String _renderMorningInsightsMarkdownForUi(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return '';

    dynamic decoded;
    try {
      decoded = jsonDecode(s);
    } catch (_) {
      return s;
    }

    Iterable<dynamic>? source;
    if (decoded is Map) {
      final dynamic candidate =
          decoded['items'] ?? decoded['tips'] ?? decoded['entries'];
      if (candidate is List) {
        source = candidate;
      } else if (candidate is Map) {
        source = candidate.values;
      }
    } else if (decoded is List) {
      source = decoded;
    }

    if (source == null) return s;

    final StringBuffer out = StringBuffer();
    int emitted = 0;

    List<String> normalizeActions(dynamic v) {
      if (v == null) return const <String>[];
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
      return v
          .toString()
          .split(RegExp(r'[\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    for (final dynamic item in source) {
      String title = '';
      String summary = '';
      List<String> actions = const <String>[];

      if (item is Map) {
        final Map<String, dynamic> m = item.map(
          (k, v) => MapEntry(k.toString(), v),
        );
        title = (m['title'] ?? '').toString().trim();
        summary = (m['summary'] ?? m['desc'] ?? m['description'] ?? '')
            .toString()
            .trim();
        actions = normalizeActions(m['actions'] ?? m['action'] ?? m['steps']);
      } else if (item is String) {
        summary = item.trim();
      } else {
        summary = item?.toString().trim() ?? '';
      }

      if (title.isEmpty) {
        title = summary;
      }
      if (title.isEmpty && actions.isNotEmpty) {
        title = actions.first;
      }

      if (title.isEmpty && summary.isEmpty && actions.isEmpty) continue;

      if (emitted > 0) out.writeln();
      if (title.isNotEmpty) out.writeln('## $title');
      if (summary.isNotEmpty && summary != title) {
        out.writeln(summary);
      }
      if (actions.isNotEmpty) {
        if (summary.isNotEmpty || title.isNotEmpty) out.writeln();
        for (final a in actions) {
          if (a.trim().isEmpty) continue;
          out.writeln('- ${a.trim()}');
        }
      }
      emitted++;
    }

    final String rendered = out.toString().trim();
    return rendered.isNotEmpty ? rendered : s;
  }

  String _docContentForDisplay(String docType, String rawContent) {
    if (docType.trim() == kSearchDocTypeMorningInsights) {
      return _renderMorningInsightsMarkdownForUi(rawContent);
    }
    return rawContent;
  }

  Future<void> _onDocTap(Map<String, dynamic> doc) async {
    final String docType = (doc['doc_type'] as String?)?.trim() ?? '';

    if (docType == kSearchDocTypeFavoriteNote) {
      await _openFavoriteNoteDocScreenshot(doc);
      return;
    }

    await _showDocDetail(doc);
  }

  Future<void> _openFavoriteNoteDocScreenshot(Map<String, dynamic> doc) async {
    final int? screenshotId = doc['screenshot_id'] as int?;
    final String pkg = (doc['app_package_name'] as String?)?.trim() ?? '';
    if (screenshotId == null || screenshotId <= 0) return;
    if (pkg.isEmpty) return;

    final rec = await ScreenshotDatabase.instance.getScreenshotById(
      screenshotId,
      pkg,
    );
    if (!mounted || rec == null) return;
    _openSampleViewer(<ScreenshotRecord>[rec], 0);
  }

  Future<void> _showDocDetail(Map<String, dynamic> doc) async {
    if (!mounted) return;
    final String docType = (doc['doc_type'] as String?)?.trim() ?? '';
    final String title = (doc['title'] as String?)?.trim().isNotEmpty == true
        ? (doc['title'] as String).trim()
        : _docTypeLabel(docType);
    final String rawContent = (doc['content'] as String?)?.trim() ?? '';
    final String content = _docContentForDisplay(docType, rawContent);
    final String tags = (doc['tags'] as String?)?.trim() ?? '';
    final String dateKey = (doc['date_key'] as String?)?.trim() ?? '';
    final String appPkg = (doc['app_package_name'] as String?)?.trim() ?? '';
    final int segmentId = (doc['segment_id'] as int?) ?? 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, ctrl) {
            return UISheetSurface(
              child: Column(
                children: [
                  const SizedBox(height: AppTheme.spacing3),
                  const UISheetHandle(),
                  const SizedBox(height: AppTheme.spacing3),
                  Expanded(
                    child: ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        0,
                        AppTheme.spacing4,
                        AppTheme.spacing6,
                      ),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(ctx).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: AppLocalizations.of(ctx).actionCopy,
                              onPressed: content.trim().isEmpty
                                  ? null
                                  : () async {
                                      final String copyText =
                                          title.trim().isEmpty
                                          ? content
                                          : '${title.trim()}\n\n$content';
                                      await Clipboard.setData(
                                        ClipboardData(text: copyText),
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              ctx,
                                            ).copySuccess,
                                          ),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.copy_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildDocTypeChip(ctx, _docTypeLabel(docType)),
                            const Spacer(),
                            if (dateKey.isNotEmpty)
                              Text(
                                dateKey,
                                style: Theme.of(ctx).textTheme.bodySmall
                                    ?.copyWith(color: AppTheme.mutedForeground),
                              ),
                          ],
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            tags,
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mutedForeground,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (content.isNotEmpty)
                          _buildHighlightedMarkdown(
                            context: ctx,
                            text: content,
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          )
                        else
                          Text(
                            AppLocalizations.of(ctx).noContentParenthesized,
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.mutedForeground,
                            ),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (docType == kSearchDocTypeDailySummary ||
                                docType == kSearchDocTypeMorningInsights)
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => DailySummaryPage(
                                        dateKey: dateKey.isNotEmpty
                                            ? dateKey
                                            : _todayKey(),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: Text(
                                  AppLocalizations.of(ctx).openDailySummary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

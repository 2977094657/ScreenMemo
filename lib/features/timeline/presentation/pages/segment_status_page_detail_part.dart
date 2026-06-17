part of 'segment_status_page.dart';

// ========== 动态详情与操作 ==========
extension _SegmentStatusDetailPart on _SegmentStatusPageState {
  Future<void> _openImageGallery(
    List<Map<String, dynamic>> samples,
    int initialIndex,
  ) async {
    if (!mounted) return;
    try {
      // 尝试为查看器补充本段 AI 结构化结果（用于图片标签/描述等增强信息）
      String? aiStructuredJson;
      int? segmentIdForViewer;
      Map<String, dynamic>? aiResultSnapshot;
      try {
        final int segId = samples.isNotEmpty
            ? ((samples.first['segment_id'] as int?) ?? 0)
            : 0;
        if (segId > 0) {
          segmentIdForViewer = segId;
          final Map<String, dynamic>? result = await _db.getSegmentResult(
            segId,
          );
          if (result != null) {
            aiResultSnapshot = <String, dynamic>{
              'segment_id': result['segment_id'] ?? segId,
              'ai_provider': result['ai_provider'],
              'ai_model': result['ai_model'],
              'output_text': result['output_text'],
              'structured_json': result['structured_json'],
              'categories': result['categories'],
              'created_at': result['created_at'],
            };
          }
          final String raw =
              (result?['structured_json'] as String?)?.toString() ?? '';
          if (raw.trim().isNotEmpty) aiStructuredJson = raw;
        }
      } catch (_) {}

      // 将样本映射为 ScreenshotRecord 列表；优先从数据库补全原始记录（含 id / page_url 等）
      final List<Future<ScreenshotRecord>> futures =
          <Future<ScreenshotRecord>>[];
      for (final Map<String, dynamic> m in samples) {
        futures.add(() async {
          final String filePath = (m['file_path'] as String?) ?? '';
          if (filePath.isEmpty) {
            return ScreenshotRecord(
              id: null,
              appPackageName: (m['app_package_name'] as String?) ?? '',
              appName: (m['app_name'] as String?) ?? '',
              filePath: '',
              captureTime: DateTime.now(),
              fileSize: 0,
            );
          }
          try {
            final rec = await ScreenshotDatabase.instance.getScreenshotByPath(
              filePath,
            );
            if (rec != null) return rec;
          } catch (_) {}
          // 回退：使用样本字段快速构造
          final String pkg = (m['app_package_name'] as String?) ?? '';
          final String appName = (m['app_name'] as String?) ?? pkg;
          final int ct = (m['capture_time'] as int?) ?? 0;
          return ScreenshotRecord(
            id: null,
            appPackageName: pkg,
            appName: appName,
            filePath: filePath,
            captureTime: ct > 0
                ? DateTime.fromMillisecondsSinceEpoch(ct)
                : DateTime.now(),
            fileSize: 0,
            pageUrl: (m['page_url'] as String?)?.toString(),
            ocrText: (m['ocr_text'] as String?)?.toString(),
          );
        }());
      }
      final List<ScreenshotRecord> shots = await Future.wait(futures);
      if (shots.isEmpty) return;

      // 选定当前图片对应的 App 信息
      final int safeIndex = initialIndex < 0
          ? 0
          : (initialIndex >= shots.length ? shots.length - 1 : initialIndex);
      final Map<String, dynamic> cur = samples[safeIndex];
      final String curPkg =
          (cur['app_package_name'] as String?) ??
          shots[safeIndex].appPackageName;
      final String curAppName =
          (cur['app_name'] as String?) ?? shots[safeIndex].appName;
      final AppInfo app =
          _appInfoByPackage[curPkg] ??
          AppInfo(
            packageName: curPkg,
            appName: curAppName,
            icon: null,
            version: '',
            isSystemApp: false,
          );

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/screenshot_viewer',
        arguments: {
          'screenshots': shots,
          'initialIndex': safeIndex,
          'appName': app.appName,
          'appInfo': app,
          'multiApp': true,
          if (segmentIdForViewer != null) 'segmentId': segmentIdForViewer,
          if (aiResultSnapshot != null) 'aiResult': aiResultSnapshot,
          if (aiStructuredJson != null) 'aiStructuredJson': aiStructuredJson,
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).operationFailed)),
      );
    }
  }

  Widget _buildSamplesGrid(
    List<Map<String, dynamic>> samples, {
    Set<String> aiNsfwFiles = const <String>{},
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: samples.length,
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

        final String fileName = path.replaceAll('\\', '/').split('/').last;
        final bool aiNsfw = aiNsfwFiles.contains(fileName);

        return ScreenshotImageWidget(
          file: File(path),
          privacyMode: _privacyMode,
          extraNsfwMask: aiNsfw,
          pageUrl: pageUrl.isNotEmpty ? pageUrl : null,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openImageGallery(samples, i),
          showNsfwButton: true,
          errorText: AppLocalizations.of(context).imageError,
        );
      },
    );
  }

  Future<void> _openDetail(Map<String, dynamic> seg) async {
    final id = (seg['id'] as int?) ?? 0;
    final samples = await _db.listSegmentSamples(id);
    final result = await _db.getSegmentResult(id);
    final Set<String> aiNsfwFiles = <String>{};
    try {
      final String raw =
          (result?['structured_json'] as String?)?.toString() ?? '';
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final rawTags = decoded['image_tags'];
          if (rawTags is List) {
            bool containsExactNsfw(dynamic tags) {
              if (tags == null) return false;
              if (tags is List) {
                return tags.any(
                  (t) => t.toString().trim().toLowerCase() == 'nsfw',
                );
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
              final String fileName = file
                  .replaceAll('\\', '/')
                  .split('/')
                  .last;
              if (containsExactNsfw(e['tags'])) aiNsfwFiles.add(fileName);
            }
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (sheetCtx, ctrl) {
            final cs = Theme.of(sheetCtx).colorScheme;
            return ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusLg),
                topRight: Radius.circular(AppTheme.radiusLg),
              ),
              child: ColoredBox(
                color: cs.surface,
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
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
                            Text(
                              AppLocalizations.of(context).timeRangeLabel(
                                '${_fmtTime((seg['start_time'] as int?) ?? 0)} - ${_fmtTime((seg['end_time'] as int?) ?? 0)}',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  AppLocalizations.of(context).statusLabel(
                                    (seg['status'] as String?) ?? '',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if ((seg['merged_flag'] as int?) == 1)
                                  Builder(
                                    builder: (context) {
                                      final SegmentTagChipColors colors =
                                          segmentMergedTagChipColors(context);
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.background,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: colors.border,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).mergedEventTag,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.foreground,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(
                                context,
                              ).samplesTitle(samples.length),
                            ),
                            const SizedBox(height: 6),
                            _buildSamplesGrid(
                              samples,
                              aiNsfwFiles: aiNsfwFiles,
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Text(
                                  AppLocalizations.of(context).aiResultTitle,
                                ),
                                const Spacer(),
                                if (result != null)
                                  IconButton(
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).copyResultsTooltip,
                                    icon: const Icon(
                                      Icons.copy_all_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () async {
                                      final text =
                                          ((result['structured_json']
                                                      as String?) ??
                                                  (result['output_text']
                                                      as String?) ??
                                                  '')
                                              .toString();
                                      if (text.isEmpty) return;
                                      await Clipboard.setData(
                                        ClipboardData(text: text),
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              context,
                                            ).copySuccess,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (result == null)
                              Text(AppLocalizations.of(context).none),
                            if (result != null) ...[
                              Builder(
                                builder: (c) {
                                  final String rawText =
                                      (result['output_text'] as String?) ?? '';
                                  final String rawJson =
                                      (result['structured_json'] as String?) ??
                                      '';
                                  Map<String, dynamic>? sj;
                                  try {
                                    final d = jsonDecode(rawJson);
                                    if (d is Map<String, dynamic>) sj = d;
                                  } catch (_) {}
                                  String? err;
                                  try {
                                    final e = sj?['error'];
                                    if (e is Map) {
                                      final m = (e['message'] ?? e['msg'] ?? '')
                                          .toString();
                                      if (m.trim().isNotEmpty) {
                                        err = m;
                                      } else {
                                        err = e.toString();
                                      }
                                    } else if (e is String &&
                                        e.trim().isNotEmpty) {
                                      err = e;
                                    }
                                  } catch (_) {}
                                  if (err == null &&
                                      rawText.trim().startsWith('{')) {
                                    try {
                                      final d2 = jsonDecode(rawText);
                                      if (d2 is Map && d2['error'] != null) {
                                        final e2 = d2['error'];
                                        if (e2 is Map &&
                                            (e2['message'] is String)) {
                                          err = e2['message'] as String;
                                        } else {
                                          err = e2.toString();
                                        }
                                      }
                                    } catch (_) {}
                                  }
                                  if (err == null) {
                                    final low = rawText.toLowerCase();
                                    if (low.contains('server_error') ||
                                        low.contains('request failed') ||
                                        low.contains(
                                          'no candidates returned',
                                        )) {
                                      err = rawText;
                                    }
                                  }
                                  if (err != null) {
                                    final cs = Theme.of(c).colorScheme;
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: cs.errorContainer,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: cs.error.withOpacity(0.6),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.error_outline,
                                                size: 16,
                                                color: cs.onErrorContainer,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: SelectableText(
                                                  err!,
                                                  style: Theme.of(c)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color:
                                                            cs.onErrorContainer,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        if (rawJson.isNotEmpty)
                                          SelectableText(
                                            rawJson,
                                            style: Theme.of(
                                              c,
                                            ).textTheme.bodySmall,
                                          ),
                                      ],
                                    );
                                  } else {
                                    final Map<String, List<String>> tagsByFile =
                                        <String, List<String>>{};
                                    final List<Map<String, String>> descGroups =
                                        <Map<String, String>>[];

                                    try {
                                      final rawTags = sj?['image_tags'];
                                      if (rawTags is List) {
                                        for (final e in rawTags) {
                                          if (e is! Map) continue;
                                          final Map<dynamic, dynamic> m = e;
                                          final String file = (m['file'] ?? '')
                                              .toString()
                                              .trim();
                                          if (file.isEmpty) continue;
                                          final raw = m['tags'];
                                          final List<String> tags = <String>[];
                                          if (raw is List) {
                                            for (final t in raw) {
                                              final v = t.toString().trim();
                                              if (v.isNotEmpty) tags.add(v);
                                            }
                                          } else if (raw is String) {
                                            tags.addAll(
                                              raw
                                                  .split(RegExp(r'[，,;；\s]+'))
                                                  .map((e) => e.trim())
                                                  .where((e) => e.isNotEmpty),
                                            );
                                          }
                                          if (tags.isNotEmpty)
                                            tagsByFile[file] = tags;
                                        }
                                      }
                                    } catch (_) {}

                                    try {
                                      final rawDescs =
                                          sj?['image_descriptions'];
                                      if (rawDescs is List) {
                                        for (final e in rawDescs) {
                                          if (e is! Map) continue;
                                          final Map<dynamic, dynamic> m = e;
                                          final String from =
                                              (m['from_file'] ??
                                                      m['from'] ??
                                                      m['start'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          final String to =
                                              (m['to_file'] ??
                                                      m['to'] ??
                                                      m['end'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          final String desc =
                                              (m['description'] ??
                                                      m['desc'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          if ((from.isEmpty && to.isEmpty) ||
                                              desc.isEmpty)
                                            continue;
                                          final String a = from.isNotEmpty
                                              ? from
                                              : to;
                                          final String b = to.isNotEmpty
                                              ? to
                                              : from;
                                          descGroups.add(<String, String>{
                                            'from': a,
                                            'to': b,
                                            'description': desc,
                                          });
                                        }
                                      }
                                    } catch (_) {}

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).modelValueLabel(
                                            (result['ai_model'] ?? '')
                                                .toString(),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        MarkdownBody(
                                          data: _normalizeMarkdownForUi(
                                            rawText,
                                          ),
                                          styleSheet:
                                              MarkdownStyleSheet.fromTheme(
                                                Theme.of(c),
                                              ).copyWith(
                                                p: Theme.of(
                                                  c,
                                                ).textTheme.bodyMedium,
                                              ),
                                          onTapLink: (text, href, title) async {
                                            if (href == null) return;
                                            final uri = Uri.tryParse(href);
                                            if (uri != null) {
                                              try {
                                                await launchUrl(
                                                  uri,
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              } catch (_) {}
                                            }
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        if (tagsByFile.isNotEmpty) ...[
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).aiImageTagsTitle,
                                            style: Theme.of(
                                              c,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 6),
                                          ...tagsByFile.entries.map((e) {
                                            final String tags = e.value.join(
                                              ' · ',
                                            );
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              child: SelectableText(
                                                '${e.key}: $tags',
                                                style: Theme.of(
                                                  c,
                                                ).textTheme.bodySmall,
                                              ),
                                            );
                                          }),
                                          const SizedBox(height: 10),
                                        ],
                                        if (descGroups.isNotEmpty) ...[
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).aiImageDescriptionsTitle,
                                            style: Theme.of(
                                              c,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 6),
                                          ...descGroups.map((g) {
                                            final String from = g['from'] ?? '';
                                            final String to = g['to'] ?? '';
                                            final String label =
                                                (from.isNotEmpty &&
                                                    to.isNotEmpty &&
                                                    from != to)
                                                ? '$from-$to'
                                                : (from.isNotEmpty ? from : to);
                                            final String desc =
                                                g['description'] ?? '';
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: SelectableText(
                                                '$label:\n$desc',
                                                style: Theme.of(
                                                  c,
                                                ).textTheme.bodySmall,
                                              ),
                                            );
                                          }),
                                          const SizedBox(height: 10),
                                        ],
                                        if (rawJson.isNotEmpty)
                                          SelectableText(rawJson),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

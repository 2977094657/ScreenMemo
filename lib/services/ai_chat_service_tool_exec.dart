part of 'ai_chat_service.dart';

extension AIChatServiceToolExecExt on AIChatService {
  List<String> _decodeStringListJsonTool(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return const <String>[];
    try {
      final dynamic v = jsonDecode(t);
      if (v is List) {
        return v
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<List<AIMessage>> _executeGetImagesTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final dynamic raw = args['filenames'];
    final List<String> names = <String>[];
    if (raw is List) {
      for (final v in raw) {
        final String n = v?.toString().trim() ?? '';
        if (_looksLikeBasename(n)) names.add(n);
      }
    } else if (raw is String) {
      final String n = raw.trim();
      if (_looksLikeBasename(n)) names.add(n);
    }
    final List<String> uniq = <String>{...names}.toList();
    const int maxImages = 15;
    final List<String> limited = uniq.take(maxImages).toList();

    final Map<String, String> nameToPath = limited.isEmpty
        ? const <String, String>{}
        : await ScreenshotDatabase.instance.findPathsByBasenames(
            limited.toSet(),
          );

    final List<Map<String, dynamic>> found = <Map<String, dynamic>>[];
    final List<String> missing = <String>[];
    final List<Map<String, dynamic>> skipped = <Map<String, dynamic>>[];
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text':
            'The following images are provided from the user device. Each image is preceded by its filename.',
      },
    ];

    int totalRawBytes = 0;
    int totalPayloadBytes = 0;
    const int maxTotalPayloadBytes = 10 * 1024 * 1024;

    int _estimateDataUrlBytes(int rawBytes, String mime) {
      final int b64Len = ((rawBytes + 2) ~/ 3) * 4;
      final int prefixLen = ('data:$mime;base64,').length;
      return prefixLen + b64Len;
    }

    for (final String name in limited) {
      final String? path = nameToPath[name];
      if (path == null || path.trim().isEmpty) {
        missing.add(name);
        continue;
      }
      try {
        final File f = File(path);
        if (!await f.exists()) {
          missing.add(name);
          continue;
        }
        final String mime = _detectImageMimeByExt(path);
        final int rawLen = await f.length();
        final int estimatedPayloadBytes = _estimateDataUrlBytes(rawLen, mime);
        if (totalPayloadBytes + estimatedPayloadBytes > maxTotalPayloadBytes) {
          skipped.add(<String, dynamic>{
            'filename': name,
            'reason': 'exceeds_total_payload_limit',
            'raw_bytes': rawLen,
            'estimated_payload_bytes': estimatedPayloadBytes,
          });
          continue;
        }

        final List<int> bytes = await f.readAsBytes();
        final String b64 = base64Encode(bytes);
        final String dataUrl = 'data:$mime;base64,$b64';
        final int actualPayloadBytes = dataUrl.length;
        if (totalPayloadBytes + actualPayloadBytes > maxTotalPayloadBytes) {
          skipped.add(<String, dynamic>{
            'filename': name,
            'reason': 'exceeds_total_payload_limit',
            'raw_bytes': bytes.length,
            'payload_bytes': actualPayloadBytes,
          });
          continue;
        }

        totalRawBytes += bytes.length;
        totalPayloadBytes += actualPayloadBytes;
        found.add(<String, dynamic>{
          'filename': name,
          'bytes': bytes.length,
          'mime': mime,
        });
        parts.add(<String, Object?>{'type': 'text', 'text': 'Filename: $name'});
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': dataUrl},
        });
      } catch (_) {
        missing.add(name);
      }
    }

    final AIMessage toolResult = AIMessage(
      role: 'tool',
      content: jsonEncode(<String, dynamic>{
        'tool': 'get_images',
        'requested': limited,
        'provided': found.map((e) => e['filename']).toList(),
        'missing': missing,
        'skipped': skipped,
        'limits': <String, dynamic>{
          'max_images': maxImages,
          'max_total_payload_bytes': maxTotalPayloadBytes,
        },
        'stats': <String, dynamic>{
          'provided_count': found.length,
          'provided_raw_bytes': totalRawBytes,
          'provided_payload_bytes': totalPayloadBytes,
        },
        'note':
            'Images are attached in the next user message as image_url parts.',
      }),
      toolCallId: call.id,
    );

    final AIMessage userImages = AIMessage(
      role: 'user',
      content: '',
      apiContent: parts,
    );

    return <AIMessage>[toolResult, userImages];
  }

  Future<List<AIMessage>> _executeMemorySearchTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] ?? '').toString().trim();
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'memory_search',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final int limit = (_toInt(args['limit']) ?? 10).clamp(1, 20);

    final Set<String> sources = <String>{};
    final dynamic rawSources = args['sources'];
    if (rawSources is List) {
      for (final dynamic s in rawSources) {
        final String v = (s ?? '').toString().trim().toLowerCase();
        if (v.isEmpty) continue;
        sources.add(v);
      }
    }
    if (sources.isEmpty) {
      sources.addAll(const <String>{
        'profile',
        'items',
        'daily',
        'weekly',
        'morning',
      });
    }

    String clip(String text, {int maxBytes = 1200}) {
      final String t = text.trim();
      if (t.isEmpty) return '';
      return PromptBudget.truncateTextByBytes(
        text: t,
        maxBytes: maxBytes,
        marker: '…',
      );
    }

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];

    if (sources.contains('profile') && results.length < limit) {
      try {
        final profile = await UserMemoryService.instance.getProfile();
        final String userMd = profile.userMarkdown.trim();
        final String autoMd = profile.autoMarkdown.trim();

        if (userMd.isNotEmpty) {
          results.add(<String, dynamic>{
            'path': 'profile:user',
            'source': 'profile',
            'title': 'User profile',
            'snippet': clip(userMd),
            'updated_at': profile.userUpdatedAtMs,
          });
        }
        final String qLow = query.toLowerCase();
        final bool wantsAuto =
            userMd.isEmpty ||
            (autoMd.isNotEmpty &&
                (autoMd.toLowerCase().contains(qLow) &&
                    !userMd.toLowerCase().contains(qLow)));
        if (wantsAuto && autoMd.isNotEmpty && results.length < limit) {
          results.add(<String, dynamic>{
            'path': 'profile:auto',
            'source': 'profile',
            'title': 'Auto profile',
            'snippet': clip(autoMd),
            'updated_at': profile.autoUpdatedAtMs,
          });
        }
      } catch (_) {}
    }

    if (sources.contains('items') && results.length < limit) {
      final int remaining = (limit - results.length).clamp(0, 200);
      try {
        final List<UserMemoryItem> items = await UserMemoryService.instance
            .searchItems(query, limit: remaining, offset: 0);
        final db = await ScreenshotDatabase.instance.database;
        for (final UserMemoryItem it in items) {
          if (results.length >= limit) break;
          final List<String> evidence = <String>[];
          try {
            final rows = await db.query(
              'user_memory_evidence',
              columns: const <String>['evidence_filenames_json'],
              where: 'memory_item_id = ?',
              whereArgs: <Object?>[it.id],
              orderBy: 'created_at DESC, id DESC',
              limit: 2,
            );
            for (final r in rows) {
              final String raw =
                  (r['evidence_filenames_json'] as String?) ?? '';
              for (final String f in _decodeStringListJsonTool(raw)) {
                if (evidence.length >= 5) break;
                if (!evidence.contains(f)) evidence.add(f);
              }
            }
          } catch (_) {}

          results.add(<String, dynamic>{
            'path': 'item:${it.id}',
            'source': 'items',
            'title': it.kind,
            'snippet': clip(it.content),
            if (evidence.isNotEmpty) 'evidence': evidence,
            'updated_at': it.updatedAtMs,
          });
        }
      } catch (_) {}
    }

    final bool wantsSearchDocs =
        sources.contains('daily') ||
        sources.contains('weekly') ||
        sources.contains('morning');
    if (wantsSearchDocs && results.length < limit) {
      final Set<String> idxSources = <String>{};
      final Set<String> docTypes = <String>{};
      if (sources.contains('daily')) {
        idxSources.add(kSearchIndexSourceDailySummaries);
        docTypes.add(kSearchDocTypeDailySummary);
      }
      if (sources.contains('weekly')) {
        idxSources.add(kSearchIndexSourceWeeklySummaries);
        docTypes.add(kSearchDocTypeWeeklySummary);
      }
      if (sources.contains('morning')) {
        idxSources.add(kSearchIndexSourceMorningInsights);
        docTypes.add(kSearchDocTypeMorningInsights);
      }
      try {
        if (idxSources.isNotEmpty) {
          await ScreenshotDatabase.instance.syncSearchIndex(
            sources: idxSources,
          );
        }
      } catch (_) {}
      try {
        final int remaining = (limit - results.length).clamp(0, 200);
        final List<Map<String, dynamic>> docs = await ScreenshotDatabase
            .instance
            .searchSearchDocsByText(
              query,
              docTypes: docTypes.isEmpty ? null : docTypes,
              limit: remaining,
              offset: 0,
            );
        for (final Map<String, dynamic> d in docs) {
          if (results.length >= limit) break;
          final String type = (d['doc_type'] as String?)?.trim() ?? '';
          final String dateKey = (d['date_key'] as String?)?.trim() ?? '';
          final String title = (d['title'] as String?)?.trim() ?? '';
          final String content = (d['content'] as String?)?.trim() ?? '';
          final int? updatedAt = _toInt(d['updated_at']);

          String? path;
          String? source;
          if (type == kSearchDocTypeDailySummary && dateKey.isNotEmpty) {
            path = 'daily:$dateKey';
            source = 'daily';
          } else if (type == kSearchDocTypeWeeklySummary &&
              dateKey.isNotEmpty) {
            path = 'weekly:$dateKey';
            source = 'weekly';
          } else if (type == kSearchDocTypeMorningInsights &&
              dateKey.isNotEmpty) {
            path = 'morning:$dateKey';
            source = 'morning';
          }
          if (path == null || source == null) continue;

          results.add(<String, dynamic>{
            'path': path,
            'source': source,
            'title': title.isNotEmpty ? title : type,
            'snippet': clip(content),
            'updated_at': updatedAt,
          });
        }
      } catch (_) {}
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'memory_search',
          'query': query,
          'count': results.length,
          'results': results,
          'note':
              'Use memory_get(path) to fetch full text or more lines. For global memory items, you may cite [memory: item:<id>] and use evidence filenames when available.',
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeMemoryGetTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String path = (args['path'] ?? '').toString().trim();
    if (path.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'memory_get',
            'error': 'missing_path',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    int fromLine = _toInt(args['from']) ?? 1;
    if (fromLine < 1) fromLine = 1;
    int lines = _toInt(args['lines']) ?? 80;
    lines = lines.clamp(1, 400);

    String text = '';
    final Map<String, dynamic> meta = <String, dynamic>{};

    try {
      final UserMemoryPath parsed = UserMemoryPath.parse(path);
      switch (parsed.kind) {
        case UserMemoryPathKind.profileUser:
        case UserMemoryPathKind.profileAuto:
          final profile = await UserMemoryService.instance.getProfile();
          final bool isUser = parsed.kind == UserMemoryPathKind.profileUser;
          text = isUser ? profile.userMarkdown : profile.autoMarkdown;
          meta['source'] = 'profile';
          meta['variant'] = isUser ? 'user' : 'auto';
          meta['updated_at'] = isUser
              ? profile.userUpdatedAtMs
              : profile.autoUpdatedAtMs;
          break;
        case UserMemoryPathKind.item:
          final int id = parsed.itemId ?? 0;
          if (id <= 0) throw Exception('invalid_item_id');
          final db = await ScreenshotDatabase.instance.database;
          final rows = await db.query(
            'user_memory_items',
            where: 'id = ?',
            whereArgs: <Object?>[id],
            limit: 1,
          );
          if (rows.isEmpty) throw Exception('not_found');
          final r = rows.first;
          text = (r['content'] as String?)?.trim() ?? '';
          meta['source'] = 'items';
          meta['id'] = id;
          meta['kind'] = (r['kind'] as String?)?.trim() ?? '';
          meta['memory_key'] = (r['memory_key'] as String?)?.trim();
          meta['pinned'] = _toBool(r['pinned']);
          meta['user_edited'] = _toBool(r['user_edited']);
          meta['updated_at'] = _toInt(r['updated_at']);
          meta['confidence'] = r['confidence'];
          final String kwRaw = (r['keywords_json'] as String?) ?? '';
          final List<String> kws = _decodeStringListJsonTool(kwRaw);
          if (kws.isNotEmpty) meta['keywords'] = kws;

          final List<String> evidence = <String>[];
          try {
            final evRows = await db.query(
              'user_memory_evidence',
              columns: const <String>[
                'source_type',
                'source_id',
                'evidence_filenames_json',
                'created_at',
              ],
              where: 'memory_item_id = ?',
              whereArgs: <Object?>[id],
              orderBy: 'created_at DESC, id DESC',
              limit: 8,
            );
            for (final ev in evRows) {
              final String raw =
                  (ev['evidence_filenames_json'] as String?) ?? '';
              for (final String f in _decodeStringListJsonTool(raw)) {
                if (evidence.length >= 5) break;
                if (!evidence.contains(f)) evidence.add(f);
              }
              if (evidence.length >= 5) break;
            }
          } catch (_) {}
          if (evidence.isNotEmpty) meta['evidence'] = evidence;
          break;
        case UserMemoryPathKind.daily:
          final String dateKey = parsed.dateKey ?? '';
          final row = await ScreenshotDatabase.instance.getDailySummary(
            dateKey,
          );
          text = (row?['output_text'] as String?)?.trim() ?? '';
          meta['source'] = 'daily';
          meta['date_key'] = dateKey;
          meta['created_at'] = row?['created_at'];
          meta['ai_provider'] = row?['ai_provider'];
          meta['ai_model'] = row?['ai_model'];
          break;
        case UserMemoryPathKind.weekly:
          final String dateKey = parsed.dateKey ?? '';
          final row = await ScreenshotDatabase.instance.getWeeklySummary(
            dateKey,
          );
          text = (row?['output_text'] as String?)?.trim() ?? '';
          meta['source'] = 'weekly';
          meta['week_start_date'] = dateKey;
          meta['week_end_date'] = row?['week_end_date'];
          meta['created_at'] = row?['created_at'];
          meta['ai_provider'] = row?['ai_provider'];
          meta['ai_model'] = row?['ai_model'];
          break;
        case UserMemoryPathKind.morning:
          final String dateKey = parsed.dateKey ?? '';
          final row = await ScreenshotDatabase.instance.getMorningInsights(
            dateKey,
          );
          final String rawResponse =
              (row?['raw_response'] as String?)?.trim() ?? '';
          if (rawResponse.isNotEmpty) {
            text = rawResponse;
          } else {
            // Prefer the rendered markdown from search_docs if available.
            try {
              await ScreenshotDatabase.instance.syncSearchIndex(
                sources: <String>{kSearchIndexSourceMorningInsights},
              );
            } catch (_) {}
            try {
              final db = await ScreenshotDatabase.instance.database;
              final docRows = await db.query(
                'search_docs',
                columns: const <String>['content'],
                where: 'doc_key = ?',
                whereArgs: <Object?>['morning:$dateKey'],
                limit: 1,
              );
              if (docRows.isNotEmpty) {
                text = (docRows.first['content'] as String?)?.trim() ?? '';
              }
            } catch (_) {}
            if (text.trim().isEmpty) {
              text = (row?['tips_json'] as String?)?.trim() ?? '';
            }
          }
          meta['source'] = 'morning';
          meta['date_key'] = dateKey;
          meta['source_date_key'] = row?['source_date_key'];
          meta['created_at'] = row?['created_at'];
          break;
        case UserMemoryPathKind.unknown:
          throw Exception('unknown_path');
      }
    } catch (e) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'memory_get',
            'path': path,
            'error': e.toString(),
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final String sliced = UserMemoryService.sliceLines(
      text,
      fromLine: fromLine,
      lines: lines,
      maxLines: 400,
    );

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'memory_get',
          'path': path,
          'from': fromLine,
          'lines': lines,
          'text': sliced,
          'meta': meta,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeListSegmentsTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final int now = DateTime.now().millisecondsSinceEpoch;

    final bool onlyNoSummary = _toBool(args['only_no_summary']);
    final List<String> requestedAppNames = _normalizeAppNamesArg(args);
    final List<String> resolvedPkgs = await _resolveAppPackagesFromArgs(args);
    final List<String> warnings = <String>[];
    _warnIfLegacyAppPackageArgsUsed(args, warnings);
    final List<String> appPackageNames = resolvedPkgs;
    if (requestedAppNames.isNotEmpty && appPackageNames.isEmpty) {
      warnings.add(
        _loc(
          '提示：未找到应用：${requestedAppNames.join('、')}，已忽略应用过滤。',
          'Note: app not found: ${requestedAppNames.join(', ')}, app filter ignored.',
        ),
      );
    }
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);
    final bool requestedTooWide =
        (reqStartMs != null &&
        reqEndMs != null &&
        reqStartMs > 0 &&
        reqEndMs > 0 &&
        (reqEndMs - reqStartMs).abs() > AIChatService.maxToolTimeSpanMs);

    int limit = (_toInt(args['limit']) ?? 20).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    const int defaultSpanMs = 14 * 24 * 60 * 60 * 1000;
    final range = _resolveToolTimeRange(
      defaultStartMs: now - defaultSpanMs,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
    );
    final int s = range.startMs;
    final int e = range.endMs;
    if (requestedTooWide && range.clampedToMaxSpan) {
      final String servedLocal = _formatLocalRangeForTool(s, e);
      warnings.add(
        _loc(
          '警告：本次工具调用的时间范围超过 7 天，已自动裁剪为 7 天窗口（仅返回 $servedLocal）。如需继续，请使用 paging.prev / paging.next 分页再次调用。',
          'Warning: requested time range exceeds 7 days; clamped to a 7-day window (returned $servedLocal only). Use paging.prev/paging.next to page and call again.',
        ),
      );
    }

    final List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .listSegmentsEx(
          limit: limit,
          offset: offset,
          onlyNoSummary: onlyNoSummary,
          startMillis: s,
          endMillis: e,
          appPackageNames: appPackageNames.isEmpty ? null : appPackageNames,
        );

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final r in rows) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(r);
      final int sid = (row['id'] as int?) ?? 0;
      final int st = (row['start_time'] as int?) ?? 0;
      final int et = (row['end_time'] as int?) ?? 0;
      final String disp =
          (row['app_packages_display'] as String?)?.trim() ??
          (row['app_packages'] as String?)?.trim() ??
          '';
      final List<String> apps = disp.isEmpty
          ? <String>[]
          : disp
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();
      final String? stLocal = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      final String? etLocal = et > 0 ? _formatLocalDateTimeForTool(et) : null;
      results.add(<String, dynamic>{
        'segment_id': sid,
        'start_local': stLocal,
        'end_local': etLocal,
        'apps': apps,
        'has_summary': (row['has_summary'] as int?) ?? 0,
        'sample_count': row['sample_count'],
        'preview': _extractSegmentSummary(row),
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'list_segments',
          if (requestedAppNames.isNotEmpty) 'app_names': requestedAppNames,
          if (appPackageNames.length == 1)
            'app_package_name': appPackageNames.single,
          if (appPackageNames.length > 1) 'app_package_names': appPackageNames,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          'time_span_limit': <String, dynamic>{
            'max_span_ms': AIChatService.maxToolTimeSpanMs,
            'max_span_days':
                (AIChatService.maxToolTimeSpanMs /
                        const Duration(days: 1).inMilliseconds)
                    .round(),
            'clamped': range.clampedToMaxSpan,
          },
          if (requestedTooWide)
            'requested_range': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(reqStartMs),
              'end_local': _formatLocalDateTimeForTool(reqEndMs),
            },
          if ((requestedTooWide && range.clampedToMaxSpan) ||
              _shouldOfferWeeklyPagingHint(
                guardStartMs: toolStartMs,
                guardEndMs: toolEndMs,
              ))
            'paging': _buildWeeklyPagingHint(
              servedStartMs: s,
              servedEndMs: e,
              guardStartMs: toolStartMs,
              guardEndMs: toolEndMs,
            ),
          if (warnings.isNotEmpty) 'warnings': warnings,
          if (range.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range.clampedToGuard,
            },
          'only_no_summary': onlyNoSummary,
          'limit': limit,
          'offset': offset,
          'count': results.length,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchSegmentsTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    final List<String> requestedAppNames = _normalizeAppNamesArg(args);
    final List<String> requestedAppPackages = await _resolveAppPackagesFromArgs(
      args,
    );
    final bool onlyNoSummary = _toBool(args['only_no_summary']);
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);

    String mode = (args['mode'] as String?)?.trim().toLowerCase() ?? '';
    if (mode.isEmpty) mode = 'auto';
    if (mode != 'auto' && mode != 'ai' && mode != 'ocr') mode = 'auto';

    final int maxSpanMs = query.isEmpty
        ? AIChatService.maxToolTimeSpanMs
        : (mode == 'ocr'
              ? AIChatService.maxOcrToolTimeSpanMs
              : AIChatService.maxSemanticToolTimeSpanMs);
    final bool requestedTooWide =
        maxSpanMs > 0 &&
        (reqStartMs != null &&
            reqEndMs != null &&
            reqStartMs > 0 &&
            reqEndMs > 0 &&
            (reqEndMs - reqStartMs).abs() > maxSpanMs);

    // If query is omitted, behave like "list segments in time range".
    if (query.isEmpty) {
      final List<AIMessage> msgs = await _executeListSegmentsTool(
        call,
        toolStartMs: toolStartMs,
        toolEndMs: toolEndMs,
      );
      if (msgs.isEmpty) return msgs;
      final Map<String, dynamic> payload = _safeJsonObject(msgs.first.content);
      payload['tool'] = 'search_segments';
      payload['mode'] = 'list';
      payload['query'] = '';
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(payload),
          toolCallId: call.id,
        ),
      ];
    }

    // If the caller explicitly wants "only no summary", OCR is the only meaningful mode.
    if (onlyNoSummary && mode != 'ocr') mode = 'ocr';

    if (mode == 'ocr') {
      final List<AIMessage> msgs = await _executeSearchSegmentsOcrTool(
        call,
        toolStartMs: toolStartMs,
        toolEndMs: toolEndMs,
      );
      if (msgs.isEmpty) return msgs;
      final Map<String, dynamic> payload = _safeJsonObject(msgs.first.content);
      payload['tool'] = 'search_segments';
      payload['mode'] = 'ocr';
      payload['query'] = query;
      payload['only_no_summary'] = onlyNoSummary;
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(payload),
          toolCallId: call.id,
        ),
      ];
    }

    int limit = (_toInt(args['limit']) ?? 10).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    // For semantic segment search, default to a much wider window.
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 365).inMilliseconds;
    final range = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: maxSpanMs,
    );
    final int s = range.startMs;
    final int e = range.endMs;
    final List<String> warnings = <String>[];
    _warnIfLegacyAppPackageArgsUsed(args, warnings);
    if (requestedAppNames.isNotEmpty && requestedAppPackages.isEmpty) {
      warnings.add(
        _loc(
          '提示：未找到应用：${requestedAppNames.join('、')}，已忽略应用过滤。',
          'Note: app not found: ${requestedAppNames.join(', ')}, app filter ignored.',
        ),
      );
    }
    if (requestedTooWide && range.clampedToMaxSpan) {
      final int maxSpanDays =
          (maxSpanMs / const Duration(days: 1).inMilliseconds).round();
      final String servedLocal = _formatLocalRangeForTool(s, e);
      warnings.add(
        _loc(
          '警告：本次工具调用的时间范围超过 $maxSpanDays 天，已自动裁剪为 $maxSpanDays 天窗口（仅返回 $servedLocal）。如需继续，请使用 paging.prev / paging.next 分页再次调用。',
          'Warning: requested time range exceeds $maxSpanDays days; clamped to a $maxSpanDays-day window (returned $servedLocal only). Use paging.prev/paging.next to page and call again.',
        ),
      );
    }

    final List<String> requestedAppPackageNames = requestedAppPackages;
    List<String> effectiveAppPackageNames = requestedAppPackages;
    bool appFilterRelaxed = false;
    List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .searchSegmentsByText(
          query,
          limit: limit,
          offset: offset,
          startMillis: s,
          endMillis: e,
          appPackageNames: effectiveAppPackageNames.isEmpty
              ? null
              : effectiveAppPackageNames,
        );
    if (rows.isEmpty && requestedAppPackageNames.isNotEmpty) {
      rows = await ScreenshotDatabase.instance.searchSegmentsByText(
        query,
        limit: limit,
        offset: offset,
        startMillis: s,
        endMillis: e,
        appPackageNames: null,
      );
      if (rows.isNotEmpty) {
        appFilterRelaxed = true;
        effectiveAppPackageNames = <String>[];
      }
    }

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final r in rows) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(r);
      final int sid = (row['id'] as int?) ?? (row['segment_id'] as int?) ?? 0;
      final int st = (row['start_time'] as int?) ?? 0;
      final int et = (row['end_time'] as int?) ?? 0;
      final String disp =
          (row['app_packages_display'] as String?)?.trim() ??
          (row['app_packages'] as String?)?.trim() ??
          '';
      final List<String> apps = disp.isEmpty
          ? <String>[]
          : disp
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();

      final String ot = (row['output_text'] as String?)?.trim() ?? '';
      final String sj = (row['structured_json'] as String?)?.trim() ?? '';
      final bool otEmpty = ot.isEmpty || ot.toLowerCase() == 'null';
      final bool sjEmpty = sj.isEmpty || sj.toLowerCase() == 'null';
      final int hasSummary = (otEmpty && sjEmpty) ? 0 : 1;
      final String? stLocal = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      final String? etLocal = et > 0 ? _formatLocalDateTimeForTool(et) : null;

      results.add(<String, dynamic>{
        'segment_id': sid,
        'start_local': stLocal,
        'end_local': etLocal,
        'apps': apps,
        'has_summary': hasSummary,
        'sample_count': row['sample_count'],
        'preview': _extractSegmentSummary(row),
        'match_sources': <String>['ai'],
      });
    }

    // auto: fallback to OCR when AI-result search yields nothing.
    final bool canOcrFallback =
        (AIChatService.maxOcrToolTimeSpanMs <= 0) ||
        (e - s).abs() <= AIChatService.maxOcrToolTimeSpanMs;
    if (mode == 'auto' && results.isEmpty && canOcrFallback) {
      final List<AIMessage> msgs = await _executeSearchSegmentsOcrTool(
        call,
        toolStartMs: toolStartMs,
        toolEndMs: toolEndMs,
      );
      if (msgs.isEmpty) return msgs;
      final Map<String, dynamic> payload = _safeJsonObject(msgs.first.content);
      payload['tool'] = 'search_segments';
      payload['mode'] = 'ocr_fallback';
      payload['query'] = query;
      payload['only_no_summary'] = onlyNoSummary;
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(payload),
          toolCallId: call.id,
        ),
      ];
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_segments',
          'mode': mode == 'ai' ? 'ai' : 'auto_ai',
          'query': query,
          if (requestedAppNames.isNotEmpty) 'app_names': requestedAppNames,
          if (effectiveAppPackageNames.isNotEmpty)
            'app_package_names': effectiveAppPackageNames,
          if (appFilterRelaxed && requestedAppNames.isNotEmpty)
            'requested_app_names': requestedAppNames,
          if (appFilterRelaxed && requestedAppPackageNames.isNotEmpty)
            'requested_app_package_names': requestedAppPackageNames,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          'time_span_limit': <String, dynamic>{
            'max_span_ms': maxSpanMs,
            'max_span_days':
                (maxSpanMs / const Duration(days: 1).inMilliseconds).round(),
            'clamped': range.clampedToMaxSpan,
          },
          if (requestedTooWide)
            'requested_range': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(reqStartMs),
              'end_local': _formatLocalDateTimeForTool(reqEndMs),
            },
          if ((requestedTooWide && range.clampedToMaxSpan) ||
              _shouldOfferWeeklyPagingHint(
                guardStartMs: toolStartMs,
                guardEndMs: toolEndMs,
                maxSpanMs: maxSpanMs,
              ))
            'paging': _buildWeeklyPagingHint(
              servedStartMs: s,
              servedEndMs: e,
              maxSpanMs: maxSpanMs,
              guardStartMs: toolStartMs,
              guardEndMs: toolEndMs,
            ),
          if (warnings.isNotEmpty) 'warnings': warnings,
          if (range.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range.clampedToGuard,
            },
          'only_no_summary': onlyNoSummary,
          'limit': limit,
          'offset': offset,
          'count': results.length,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchSegmentsOcrTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_segments_ocr',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final List<String> requestedAppNames = _normalizeAppNamesArg(args);
    final List<String> requestedAppPackageNames =
        await _resolveAppPackagesFromArgs(args);
    List<String> effectiveAppPackageNames = requestedAppPackageNames;
    bool appFilterRelaxed = false;
    final List<String> warnings = <String>[];
    _warnIfLegacyAppPackageArgsUsed(args, warnings);
    if (requestedAppNames.isNotEmpty && requestedAppPackageNames.isEmpty) {
      warnings.add(
        _loc(
          '提示：未找到应用：${requestedAppNames.join('、')}，已忽略应用过滤。',
          'Note: app not found: ${requestedAppNames.join(', ')}, app filter ignored.',
        ),
      );
    }
    final bool onlyNoSummary = _toBool(args['only_no_summary']);
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 30).inMilliseconds;
    final range0 = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: AIChatService.maxOcrToolTimeSpanMs,
    );
    int s = range0.startMs;
    int e = range0.endMs;
    int limit = (_toInt(args['limit']) ?? 10).clamp(1, 20);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;
    int perSeg = (_toInt(args['per_segment_samples']) ?? 6).clamp(1, 15);

    // Fetch more screenshots than segments to improve segment coverage.
    final int desiredSegs = offset + limit;
    final int shotFetch = (desiredSegs * 30).clamp(120, 600);

    List<ScreenshotRecord> shots;
    try {
      Future<List<ScreenshotRecord>> searchForPkgs(List<String> pkgs) async {
        if (pkgs.isEmpty) {
          return await ScreenshotDatabase.instance.searchScreenshotsByOcr(
            query,
            limit: shotFetch,
            offset: 0,
            startMillis: s,
            endMillis: e,
          );
        }
        if (pkgs.length == 1) {
          return await ScreenshotDatabase.instance.searchScreenshotsByOcrForApp(
            pkgs.single,
            query,
            limit: shotFetch,
            offset: 0,
            startMillis: s,
            endMillis: e,
          );
        }
        final List<List<ScreenshotRecord>> perApp =
            await Future.wait(<Future<List<ScreenshotRecord>>>[
              for (final pkg in pkgs)
                ScreenshotDatabase.instance.searchScreenshotsByOcrForApp(
                  pkg,
                  query,
                  limit: shotFetch,
                  offset: 0,
                  startMillis: s,
                  endMillis: e,
                ),
            ]);
        final Map<String, ScreenshotRecord> uniq = <String, ScreenshotRecord>{};
        for (final list in perApp) {
          for (final r in list) {
            final String fp = r.filePath.trim();
            if (fp.isEmpty) continue;
            uniq[fp] = r;
          }
        }
        final List<ScreenshotRecord> merged = uniq.values.toList();
        merged.sort((a, b) => b.captureTime.compareTo(a.captureTime));
        return merged.length <= shotFetch
            ? merged
            : merged.sublist(0, shotFetch);
      }

      shots = await searchForPkgs(effectiveAppPackageNames);
      if (shots.isEmpty && requestedAppPackageNames.isNotEmpty) {
        final List<ScreenshotRecord> fallbackShots = await searchForPkgs(
          const <String>[],
        );
        if (fallbackShots.isNotEmpty) {
          shots = fallbackShots;
          appFilterRelaxed = true;
          effectiveAppPackageNames = <String>[];
        }
      }
    } catch (err) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_segments_ocr',
            'query': query,
            if (requestedAppNames.isNotEmpty) 'app_names': requestedAppNames,
            if (requestedAppPackageNames.isNotEmpty)
              'app_package_names': requestedAppPackageNames,
            'start_local': _formatLocalDateTimeForTool(s),
            'end_local': _formatLocalDateTimeForTool(e),
            if (range0.guardApplied)
              'time_guard': <String, dynamic>{
                'start_local': _formatLocalDateTimeForTool(toolStartMs!),
                'end_local': _formatLocalDateTimeForTool(toolEndMs!),
                'clamped': range0.clampedToGuard,
              },
            if (warnings.isNotEmpty) 'warnings': warnings,
            'error': 'ocr_search_failed',
            'details': err.toString(),
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final List<ScreenshotRecord> normalizedShots = shots
        .where((r) => r.filePath.trim().isNotEmpty)
        .toList(growable: false);

    // Map screenshot file_path -> segment_id via segment_samples in main DB.
    final db = await ScreenshotDatabase.instance.database;
    final List<String> paths = normalizedShots
        .map((r) => r.filePath.trim())
        .toSet()
        .toList(growable: false);
    final Map<String, Map<String, dynamic>> pathToSample =
        <String, Map<String, dynamic>>{};
    const int chunkSize = 400;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final int end = (i + chunkSize) > paths.length
          ? paths.length
          : (i + chunkSize);
      final List<String> chunk = paths.sublist(i, end);
      if (chunk.isEmpty) continue;
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final List<Map<String, Object?>> rows = await db.query(
        'segment_samples',
        columns: <String>[
          'segment_id',
          'file_path',
          'capture_time',
          'app_package_name',
          'app_name',
        ],
        where: 'file_path IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final r in rows) {
        final String fp = (r['file_path'] as String?)?.trim() ?? '';
        if (fp.isEmpty) continue;
        pathToSample[fp] = Map<String, dynamic>.from(r);
      }
    }

    final Map<int, List<Map<String, dynamic>>> segToMatches =
        <int, List<Map<String, dynamic>>>{};
    final List<Map<String, dynamic>> unmapped = <Map<String, dynamic>>[];
    Map<String, dynamic> sanitizeOcrMatch(Map<String, dynamic> m) {
      final Map<String, dynamic> out = <String, dynamic>{...m};
      out.remove('capture_ms');
      return out;
    }

    for (final ScreenshotRecord r in normalizedShots) {
      final String fp = r.filePath.trim();
      final Map<String, dynamic>? sample = pathToSample[fp];
      final int sid = (sample?['segment_id'] as int?) ?? 0;
      final int captureMs = r.captureTime.millisecondsSinceEpoch;
      final Map<String, dynamic> match = <String, dynamic>{
        'filename': _basename(fp),
        'capture_ms': captureMs,
        'capture_local': _formatLocalDateTimeForTool(captureMs),
        'app_package_name': r.appPackageName,
        'app_name': r.appName,
        'segment_id': sid > 0 ? sid : null,
      };
      if (sid <= 0) {
        unmapped.add(match);
        continue;
      }
      final List<Map<String, dynamic>> list = segToMatches.putIfAbsent(
        sid,
        () => <Map<String, dynamic>>[],
      );
      list.add(match);
    }

    final List<int> segIds = segToMatches.keys.toList()..sort();
    final Map<int, Map<String, dynamic>> segMeta =
        <int, Map<String, dynamic>>{};
    const String noSummaryCond =
        "r.segment_id IS NULL OR ((r.output_text IS NULL OR LOWER(TRIM(r.output_text)) IN ('','null')) AND (r.structured_json IS NULL OR LOWER(TRIM(r.structured_json)) IN ('','null')))";
    const int segChunkSize = 300;
    for (int i = 0; i < segIds.length; i += segChunkSize) {
      final int end = (i + segChunkSize) > segIds.length
          ? segIds.length
          : (i + segChunkSize);
      final List<int> chunk = segIds.sublist(i, end);
      if (chunk.isEmpty) continue;
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final String sql =
          '''
        SELECT
          s.id,
          s.start_time,
          s.end_time,
          s.status,
          s.app_packages,
          COALESCE(
            NULLIF(TRIM(s.app_packages), ''),
            (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
          ) AS app_packages_display,
          (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count,
          r.output_text,
          r.structured_json,
          r.categories,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        WHERE s.id IN ($placeholders)
          AND (s.merged_into_id IS NULL OR s.merged_into_id <= 0 OR NOT EXISTS (SELECT 1 FROM segments t WHERE t.id = s.merged_into_id))
      ''';
      final List<Map<String, Object?>> rows = await db.rawQuery(sql, chunk);
      for (final r in rows) {
        final int sid = (r['id'] as int?) ?? 0;
        if (sid <= 0) continue;
        segMeta[sid] = Map<String, dynamic>.from(r);
      }
    }

    final List<Map<String, dynamic>> ranked = <Map<String, dynamic>>[];
    for (final MapEntry<int, List<Map<String, dynamic>>> entry
        in segToMatches.entries) {
      final int sid = entry.key;
      final List<Map<String, dynamic>> matches = entry.value;
      int last = 0;
      for (final m in matches) {
        final int t = (m['capture_ms'] as int?) ?? 0;
        if (t > last) last = t;
      }
      ranked.add(<String, dynamic>{
        'segment_id': sid,
        'last_match_time': last,
        'match_count': matches.length,
      });
    }
    ranked.sort((a, b) {
      final int ta = (a['last_match_time'] as int?) ?? 0;
      final int tb = (b['last_match_time'] as int?) ?? 0;
      if (tb != ta) return tb.compareTo(ta);
      final int ca = (a['match_count'] as int?) ?? 0;
      final int cb = (b['match_count'] as int?) ?? 0;
      if (cb != ca) return cb.compareTo(ca);
      final int ida = (a['segment_id'] as int?) ?? 0;
      final int idb = (b['segment_id'] as int?) ?? 0;
      return idb.compareTo(ida);
    });

    final List<int> orderedSegIds = ranked
        .map((e) => (e['segment_id'] as int?) ?? 0)
        .where((e) => e > 0)
        .toList(growable: false);
    final List<int> filteredSegIds = onlyNoSummary
        ? orderedSegIds
              .where((sid) => (segMeta[sid]?['has_summary'] as int?) == 0)
              .toList(growable: false)
        : orderedSegIds;
    final List<int> pageSegIds = filteredSegIds
        .skip(offset)
        .take(limit)
        .toList(growable: false);

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final int sid in pageSegIds) {
      final Map<String, dynamic>? meta = segMeta[sid];
      final int st = (meta?['start_time'] as int?) ?? 0;
      final int et = (meta?['end_time'] as int?) ?? 0;
      final String disp =
          (meta?['app_packages_display'] as String?)?.trim() ??
          (meta?['app_packages'] as String?)?.trim() ??
          '';
      final List<String> apps = disp.isEmpty
          ? <String>[]
          : disp
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();

      final List<Map<String, dynamic>> matches =
          List<Map<String, dynamic>>.from(segToMatches[sid] ?? const []);
      matches.sort((a, b) {
        final int ta = (a['capture_ms'] as int?) ?? 0;
        final int tb = (b['capture_ms'] as int?) ?? 0;
        return tb.compareTo(ta);
      });
      final String? stLocal = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      final String? etLocal = et > 0 ? _formatLocalDateTimeForTool(et) : null;

      results.add(<String, dynamic>{
        'segment_id': sid,
        'start_local': stLocal,
        'end_local': etLocal,
        'apps': apps,
        'has_summary': (meta?['has_summary'] as int?) ?? 0,
        'sample_count': meta?['sample_count'],
        'preview': meta == null ? '' : _extractSegmentSummary(meta),
        'match_count': matches.length,
        'matched_samples': matches.take(perSeg).map(sanitizeOcrMatch).toList(),
        'match_sources': <String>['ocr'],
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_segments_ocr',
          'query': query,
          if (requestedAppNames.isNotEmpty) 'app_names': requestedAppNames,
          if (effectiveAppPackageNames.isNotEmpty)
            'app_package_names': effectiveAppPackageNames,
          if (appFilterRelaxed && requestedAppNames.isNotEmpty)
            'requested_app_names': requestedAppNames,
          if (appFilterRelaxed && requestedAppPackageNames.isNotEmpty)
            'requested_app_package_names': requestedAppPackageNames,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          if (range0.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range0.clampedToGuard,
            },
          if (warnings.isNotEmpty) 'warnings': warnings,
          'limit': limit,
          'offset': offset,
          'only_no_summary': onlyNoSummary,
          'per_segment_samples': perSeg,
          'fetched_screenshots': normalizedShots.length,
          'segments_total': ranked.length,
          'segments_total_filtered': filteredSegIds.length,
          'count': results.length,
          'results': results,
          // Keep a small list for the model to request images if needed.
          'unmapped_samples_preview': unmapped
              .take(20)
              .map(sanitizeOcrMatch)
              .toList(growable: false),
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeGetSegmentResultTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final int sid = _toInt(args['segment_id']) ?? 0;
    final int maxChars = (_toInt(args['max_chars']) ?? 12000).clamp(800, 40000);
    if (sid <= 0) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'get_segment_result',
            'error': 'invalid_segment_id',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final Map<String, dynamic>? segRow = await (() async {
      try {
        final db = await ScreenshotDatabase.instance.database;
        final rows = await db.query(
          'segments',
          where: 'id = ?',
          whereArgs: <Object?>[sid],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return Map<String, dynamic>.from(rows.first);
      } catch (_) {
        return null;
      }
    })();

    final Map<String, dynamic>? seg = segRow == null
        ? null
        : <String, dynamic>{...segRow};
    if (seg != null) {
      final int st = (seg['start_time'] as int?) ?? 0;
      final int et = (seg['end_time'] as int?) ?? 0;
      seg.remove('start_time');
      seg.remove('end_time');
      seg['start_local'] = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      seg['end_local'] = et > 0 ? _formatLocalDateTimeForTool(et) : null;
    }

    final Map<String, dynamic>? res = await ScreenshotDatabase.instance
        .getSegmentResult(sid);
    final Map<String, dynamic> out = <String, dynamic>{
      'tool': 'get_segment_result',
      'segment_id': sid,
      'segment': seg,
      'result': res == null
          ? null
          : <String, dynamic>{
              'ai_provider': res['ai_provider'],
              'ai_model': res['ai_model'],
              'categories': res['categories'],
              'created_at': res['created_at'],
              'output_text': _clipText(
                (res['output_text'] as String?) ?? '',
                maxChars,
              ),
              'structured_json': _clipText(
                (res['structured_json'] as String?) ?? '',
                maxChars,
              ),
            },
    };

    return <AIMessage>[
      AIMessage(role: 'tool', content: jsonEncode(out), toolCallId: call.id),
    ];
  }

  Future<List<AIMessage>> _executeGetSegmentSamplesTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final int sid = _toInt(args['segment_id']) ?? 0;
    int limit = (_toInt(args['limit']) ?? 24).clamp(1, 60);
    if (sid <= 0) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'get_segment_samples',
            'error': 'invalid_segment_id',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .listSegmentSamples(sid);
    final List<Map<String, dynamic>> samples = <Map<String, dynamic>>[];
    for (final r in rows.take(limit)) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(r);
      final String fp = (m['file_path'] as String?) ?? '';
      final int captureMs = (m['capture_time'] as int?) ?? 0;
      samples.add(<String, dynamic>{
        'sample_id': m['id'],
        'capture_local': captureMs > 0
            ? _formatLocalDateTimeForTool(captureMs)
            : null,
        'app_package_name': m['app_package_name'],
        'app_name': m['app_name'],
        'position_index': m['position_index'],
        'filename': fp.isEmpty ? '' : _basename(fp),
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'get_segment_samples',
          'segment_id': sid,
          'limit': limit,
          'count': samples.length,
          'samples': samples,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchScreenshotsOcrTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_screenshots_ocr',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final List<String> requestedAppNames = _normalizeAppNamesArg(args);
    final List<String> requestedAppPackageNames =
        await _resolveAppPackagesFromArgs(args);
    final List<String> warnings = <String>[];
    _warnIfLegacyAppPackageArgsUsed(args, warnings);
    if (requestedAppNames.isNotEmpty && requestedAppPackageNames.isEmpty) {
      warnings.add(
        _loc(
          '提示：未找到应用：${requestedAppNames.join('、')}，已忽略应用过滤。',
          'Note: app not found: ${requestedAppNames.join(', ')}, app filter ignored.',
        ),
      );
    }
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 30).inMilliseconds;
    final range0 = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: AIChatService.maxOcrToolTimeSpanMs,
    );
    int s = range0.startMs;
    int e = range0.endMs;
    int limit = (_toInt(args['limit']) ?? 20).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    List<String> effectiveAppPackageNames = requestedAppPackageNames;
    bool appFilterRelaxed = false;

    Future<List<ScreenshotRecord>> searchForPkgs(List<String> pkgs) async {
      if (pkgs.isEmpty) {
        return await ScreenshotDatabase.instance.searchScreenshotsByOcr(
          query,
          limit: limit,
          offset: offset,
          startMillis: s,
          endMillis: e,
        );
      }
      if (pkgs.length == 1) {
        return await ScreenshotDatabase.instance.searchScreenshotsByOcrForApp(
          pkgs.single,
          query,
          limit: limit,
          offset: offset,
          startMillis: s,
          endMillis: e,
        );
      }

      final int pageEnd = offset + limit;
      int perAppFetch = (pageEnd * 2).clamp(200, 5000);
      if (perAppFetch < limit) perAppFetch = limit;
      final List<List<ScreenshotRecord>> perApp =
          await Future.wait(<Future<List<ScreenshotRecord>>>[
            for (final pkg in pkgs)
              ScreenshotDatabase.instance.searchScreenshotsByOcrForApp(
                pkg,
                query,
                limit: perAppFetch,
                offset: 0,
                startMillis: s,
                endMillis: e,
              ),
          ]);
      final Map<String, ScreenshotRecord> uniq = <String, ScreenshotRecord>{};
      for (final list in perApp) {
        for (final r in list) {
          final String fp = r.filePath.trim();
          if (fp.isEmpty) continue;
          uniq[fp] = r;
        }
      }
      final List<ScreenshotRecord> merged = uniq.values.toList();
      merged.sort((a, b) => b.captureTime.compareTo(a.captureTime));

      if (offset >= merged.length) return <ScreenshotRecord>[];
      final int end = (offset + limit) > merged.length
          ? merged.length
          : (offset + limit);
      return merged.sublist(offset, end);
    }

    List<ScreenshotRecord> rows = await searchForPkgs(effectiveAppPackageNames);
    if (rows.isEmpty && requestedAppPackageNames.isNotEmpty) {
      rows = await searchForPkgs(const <String>[]);
      if (rows.isNotEmpty) {
        appFilterRelaxed = true;
        effectiveAppPackageNames = <String>[];
      }
    }

    final List<Map<String, dynamic>> results = rows.map((r) {
      final String fp = r.filePath;
      final int captureMs = r.captureTime.millisecondsSinceEpoch;
      return <String, dynamic>{
        'id': r.id,
        'app_package_name': r.appPackageName,
        'app_name': r.appName,
        'capture_local': _formatLocalDateTimeForTool(captureMs),
        'filename': fp.isEmpty ? '' : _basename(fp),
        'file_size': r.fileSize,
      };
    }).toList();

    int? totalCount;
    bool hasMore = false;
    try {
      // Fast path: if we didn't fill the page, treat returned results as the full set.
      // Otherwise compute the true total to support “how many …” questions without
      // forcing the model to split time windows.
      if (offset <= 0 && results.length < limit) {
        totalCount = results.length;
      } else {
        if (effectiveAppPackageNames.isEmpty) {
          totalCount = await ScreenshotDatabase.instance.countScreenshotsByOcr(
            query,
            startMillis: s,
            endMillis: e,
          );
        } else if (effectiveAppPackageNames.length == 1) {
          totalCount = await ScreenshotDatabase.instance
              .countScreenshotsByOcrForApp(
                effectiveAppPackageNames.single,
                query,
                startMillis: s,
                endMillis: e,
              );
        } else {
          final List<int> parts = await Future.wait(<Future<int>>[
            for (final pkg in effectiveAppPackageNames)
              ScreenshotDatabase.instance.countScreenshotsByOcrForApp(
                pkg,
                query,
                startMillis: s,
                endMillis: e,
              ),
          ]);
          totalCount = parts.fold<int>(0, (a, b) => a + b);
        }
      }
      if (totalCount != null) {
        hasMore = (offset + results.length) < totalCount;
      }
    } catch (_) {
      // Best-effort: total_count is optional; do not fail the tool if counting fails.
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_screenshots_ocr',
          'query': query,
          if (requestedAppNames.isNotEmpty) 'app_names': requestedAppNames,
          if (effectiveAppPackageNames.isNotEmpty)
            'app_package_names': effectiveAppPackageNames,
          if (appFilterRelaxed && requestedAppNames.isNotEmpty)
            'requested_app_names': requestedAppNames,
          if (appFilterRelaxed && requestedAppPackageNames.isNotEmpty)
            'requested_app_package_names': requestedAppPackageNames,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          if (range0.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range0.clampedToGuard,
            },
          if (warnings.isNotEmpty) 'warnings': warnings,
          'limit': limit,
          'offset': offset,
          'count': results.length,
          if (totalCount != null) 'total_count': totalCount,
          if (totalCount != null) 'has_more': hasMore,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchAiImageMetaTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_ai_image_meta',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final List<String> requestedAppNames = _normalizeAppNamesArg(args);
    final List<String> requestedAppPackageNames =
        await _resolveAppPackagesFromArgs(args);
    final bool includeNsfw = _toBool(args['include_nsfw']);

    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);
    final int maxSpanMs = AIChatService.maxSemanticToolTimeSpanMs;
    final bool requestedTooWide =
        (reqStartMs != null &&
        reqEndMs != null &&
        reqStartMs > 0 &&
        reqEndMs > 0 &&
        (reqEndMs - reqStartMs).abs() > maxSpanMs);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 365).inMilliseconds;
    final range0 = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: maxSpanMs,
    );
    final int s = range0.startMs;
    final int e = range0.endMs;
    final List<String> warnings = <String>[];
    _warnIfLegacyAppPackageArgsUsed(args, warnings);
    if (requestedAppNames.isNotEmpty && requestedAppPackageNames.isEmpty) {
      warnings.add(
        _loc(
          '提示：未找到应用：${requestedAppNames.join('、')}，已忽略应用过滤。',
          'Note: app not found: ${requestedAppNames.join(', ')}, app filter ignored.',
        ),
      );
    }
    if (requestedTooWide && range0.clampedToMaxSpan) {
      final int maxSpanDays =
          (maxSpanMs / const Duration(days: 1).inMilliseconds).round();
      final String servedLocal = _formatLocalRangeForTool(s, e);
      warnings.add(
        _loc(
          '警告：本次工具调用的时间范围超过 $maxSpanDays 天，已自动裁剪为 $maxSpanDays 天窗口（仅返回 $servedLocal）。如需继续，请使用 paging.prev / paging.next 分页再次调用。',
          'Warning: requested time range exceeds $maxSpanDays days; clamped to a $maxSpanDays-day window (returned $servedLocal only). Use paging.prev/paging.next to page and call again.',
        ),
      );
    }

    int limit = (_toInt(args['limit']) ?? 20).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    List<String> effectiveAppPackageNames = requestedAppPackageNames;
    bool appFilterRelaxed = false;
    List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .searchAiImageMetaByText(
          query,
          limit: limit,
          offset: offset,
          startMillis: s,
          endMillis: e,
          includeNsfw: includeNsfw,
          appPackageNames: effectiveAppPackageNames.isEmpty
              ? null
              : effectiveAppPackageNames,
        );
    if (rows.isEmpty && requestedAppPackageNames.isNotEmpty) {
      rows = await ScreenshotDatabase.instance.searchAiImageMetaByText(
        query,
        limit: limit,
        offset: offset,
        startMillis: s,
        endMillis: e,
        includeNsfw: includeNsfw,
        appPackageNames: null,
      );
      if (rows.isNotEmpty) {
        appFilterRelaxed = true;
        effectiveAppPackageNames = <String>[];
      }
    }

    List<String> parseTags(Object? raw) {
      if (raw == null) return <String>[];
      final String t = raw.toString().trim();
      if (t.isEmpty) return <String>[];
      try {
        final dynamic v = jsonDecode(t);
        if (v is List) {
          return v
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
        }
      } catch (_) {}
      return t
          .split(RegExp(r'[，,;；\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final r in rows) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(r);
      final String fp = (row['file_path'] as String?)?.trim() ?? '';
      final String filename = fp.isEmpty ? '' : _basename(fp);
      final int captureMs = (row['capture_time'] as int?) ?? 0;
      results.add(<String, dynamic>{
        'filename': filename,
        'capture_local': captureMs > 0
            ? _formatLocalDateTimeForTool(captureMs)
            : null,
        'segment_id': row['segment_id'],
        'app_package_name': row['app_package_name'],
        'app_name': row['app_name'],
        'tags': parseTags(row['tags_json']),
        'description': _clipText((row['description'] as String?) ?? '', 1200),
        'description_range': row['description_range'],
        'nsfw': row['nsfw'],
        'lang': row['lang'],
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_ai_image_meta',
          'query': query,
          if (requestedAppNames.isNotEmpty) 'app_names': requestedAppNames,
          if (effectiveAppPackageNames.isNotEmpty)
            'app_package_names': effectiveAppPackageNames,
          if (appFilterRelaxed && requestedAppNames.isNotEmpty)
            'requested_app_names': requestedAppNames,
          if (appFilterRelaxed && requestedAppPackageNames.isNotEmpty)
            'requested_app_package_names': requestedAppPackageNames,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'include_nsfw': includeNsfw,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          'time_span_limit': <String, dynamic>{
            'max_span_ms': maxSpanMs,
            'max_span_days':
                (maxSpanMs / const Duration(days: 1).inMilliseconds).round(),
            'clamped': range0.clampedToMaxSpan,
          },
          if (requestedTooWide)
            'requested_range': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(reqStartMs),
              'end_local': _formatLocalDateTimeForTool(reqEndMs),
            },
          if ((requestedTooWide && range0.clampedToMaxSpan) ||
              _shouldOfferWeeklyPagingHint(
                guardStartMs: toolStartMs,
                guardEndMs: toolEndMs,
                maxSpanMs: maxSpanMs,
              ))
            'paging': _buildWeeklyPagingHint(
              servedStartMs: s,
              servedEndMs: e,
              maxSpanMs: maxSpanMs,
              guardStartMs: toolStartMs,
              guardEndMs: toolEndMs,
            ),
          if (warnings.isNotEmpty) 'warnings': warnings,
          if (range0.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range0.clampedToGuard,
            },
          'limit': limit,
          'offset': offset,
          'count': results.length,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeToolCall(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    switch (call.name) {
      case 'get_images':
        return _executeGetImagesTool(call);
      case 'memory_search':
        return _executeMemorySearchTool(call);
      case 'memory_get':
        return _executeMemoryGetTool(call);
      case 'search_segments':
        return _executeSearchSegmentsTool(
          call,
          toolStartMs: toolStartMs,
          toolEndMs: toolEndMs,
        );
      case 'get_segment_result':
        return _executeGetSegmentResultTool(call);
      case 'get_segment_samples':
        return _executeGetSegmentSamplesTool(call);
      case 'search_screenshots_ocr':
        return _executeSearchScreenshotsOcrTool(
          call,
          toolStartMs: toolStartMs,
          toolEndMs: toolEndMs,
        );
      case 'search_ai_image_meta':
        return _executeSearchAiImageMetaTool(
          call,
          toolStartMs: toolStartMs,
          toolEndMs: toolEndMs,
        );
      default:
        return <AIMessage>[
          AIMessage(
            role: 'tool',
            content: jsonEncode(<String, dynamic>{
              'error': 'unknown_tool',
              'tool': call.name,
            }),
            toolCallId: call.id,
          ),
        ];
    }
  }
}

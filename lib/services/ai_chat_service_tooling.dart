part of 'ai_chat_service.dart';

extension AIChatServiceToolingExt on AIChatService {
  String _formatLocalDateTimeForTool(int epochMs) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatLocalRangeForTool(int startMs, int endMs) {
    return '${_formatLocalDateTimeForTool(startMs)}–${_formatLocalDateTimeForTool(endMs)}';
  }

  // UI-only range formatter: keep it readable (date precision only).
  String _formatLocalRangeForToolUi(int startMs, int endMs) {
    final DateTime s = DateTime.fromMillisecondsSinceEpoch(startMs);
    final DateTime e = DateTime.fromMillisecondsSinceEpoch(endMs);
    final int nowYear = DateTime.now().year;
    final bool omitYear = s.year == nowYear && e.year == nowYear;
    String two(int v) => v.toString().padLeft(2, '0');
    String dateOf(DateTime d) => omitYear
        ? '${two(d.month)}-${two(d.day)}'
        : '${d.year}-${two(d.month)}-${two(d.day)}';
    final String sd = dateOf(s);
    final String ed = dateOf(e);
    if (s.year == e.year && s.month == e.month && s.day == e.day) return sd;
    return '$sd–$ed';
  }

  Map<String, dynamic> _buildWeeklyPagingHint({
    required int servedStartMs,
    required int servedEndMs,
    int maxSpanMs = AIChatService.maxToolTimeSpanMs,
    int? guardStartMs,
    int? guardEndMs,
  }) {
    final int? gs = (guardStartMs != null && guardStartMs > 0)
        ? guardStartMs
        : null;
    final int? ge = (guardEndMs != null && guardEndMs > 0) ? guardEndMs : null;

    final Map<String, dynamic> out = <String, dynamic>{
      'max_span_ms': maxSpanMs,
      'max_span_days': (maxSpanMs / const Duration(days: 1).inMilliseconds)
          .round(),
      'served': <String, String>{
        'start_local': _formatLocalDateTimeForTool(servedStartMs),
        'end_local': _formatLocalDateTimeForTool(servedEndMs),
      },
    };

    // Previous week window: [servedStart-1-maxSpan, servedStart-1]
    final int prevEnd0 = servedStartMs - 1;
    if (prevEnd0 > 0 && (gs == null || prevEnd0 >= gs)) {
      int prevEnd = prevEnd0;
      int prevStart = prevEnd - maxSpanMs;
      if (gs != null && prevStart < gs) prevStart = gs;
      if (prevStart > prevEnd) prevStart = prevEnd;
      out['prev'] = <String, String>{
        'start_local': _formatLocalDateTimeForTool(prevStart),
        'end_local': _formatLocalDateTimeForTool(prevEnd),
      };
    }

    // Next week window: [servedEnd+1, servedEnd+1+maxSpan]
    final int nextStart0 = servedEndMs + 1;
    if (nextStart0 > 0 && (ge == null || nextStart0 <= ge)) {
      int nextStart = nextStart0;
      int nextEnd = nextStart + maxSpanMs;
      if (ge != null && nextEnd > ge) nextEnd = ge;
      if (nextStart > nextEnd) nextStart = nextEnd;
      out['next'] = <String, String>{
        'start_local': _formatLocalDateTimeForTool(nextStart),
        'end_local': _formatLocalDateTimeForTool(nextEnd),
      };
    }

    return out;
  }

  bool _shouldOfferWeeklyPagingHint({
    int? guardStartMs,
    int? guardEndMs,
    int maxSpanMs = AIChatService.maxToolTimeSpanMs,
  }) {
    if (guardStartMs == null || guardEndMs == null) return false;
    if (guardStartMs <= 0 || guardEndMs <= 0) return false;
    return (guardEndMs - guardStartMs).abs() > maxSpanMs;
  }

  String _summarizeToolMessages(List<AIMessage> toolMsgs) {
    if (toolMsgs.isEmpty) return '';
    final Map<String, dynamic> obj = _safeJsonObject(toolMsgs.first.content);
    final String tool = (obj['tool'] as String?)?.trim() ?? '';
    final Object? error = obj['error'];
    if (error != null) return _loc('错误：$error', 'error=$error');
    if (tool == 'get_images') {
      final Map<String, dynamic>? stats = (obj['stats'] is Map)
          ? (obj['stats'] as Map).cast<String, dynamic>()
          : null;
      final int provided =
          _toInt(stats?['provided_count']) ?? _toInt(obj['provided']) ?? 0;
      final int missing = (obj['missing'] is List)
          ? (obj['missing'] as List).length
          : 0;
      final int skipped = (obj['skipped'] is List)
          ? (obj['skipped'] as List).length
          : 0;
      if (provided <= 0 && missing <= 0 && skipped <= 0) {
        return _loc('无图片', 'no images');
      }
      final String head = _loc('已加载 $provided 张', 'loaded $provided');
      final List<String> extras = <String>[];
      if (missing > 0) extras.add(_loc('缺失 $missing', 'missing $missing'));
      if (skipped > 0) extras.add(_loc('跳过 $skipped', 'skipped $skipped'));
      if (extras.isEmpty) return head;
      final String sep = _loc('，', ', ');
      final String open = _loc('（', ' (');
      final String close = _loc('）', ')');
      return '$head$open${extras.join(sep)}$close';
    }
    if (tool == 'get_segment_result') {
      final int sid = _toInt(obj['segment_id']) ?? 0;
      if (sid <= 0) return _loc('已获取', 'retrieved');
      // Tool chip label already includes the segment id; keep summary minimal.
      return _loc('已获取', 'retrieved');
    }
    if (tool == 'get_segment_samples') {
      final int sid = _toInt(obj['segment_id']) ?? 0;
      final int count = _toInt(obj['count']) ?? 0;
      // UI label already contains the requested limit; surface actual returned count.
      return sid > 0
          ? _loc('返回 $count 条', 'returned $count')
          : _loc('返回 $count 条', 'returned $count');
    }
    if (tool == 'read_memory') {
      final String uri = (obj['uri'] as String?)?.trim() ?? '';
      final int children = (obj['children'] is List)
          ? (obj['children'] as List).length
          : 0;
      if (uri.isEmpty) return _loc('已读取', 'read');
      return children > 0
          ? _loc('已读取（$children 个子节点）', 'read ($children children)')
          : _loc('已读取', 'read');
    }
    if (tool == 'create_memory') {
      final String uri = (obj['uri'] as String?)?.trim() ?? '';
      return uri.isEmpty ? _loc('已创建', 'created') : _loc('已创建', 'created');
    }
    if (tool == 'update_memory') {
      return _loc('已更新', 'updated');
    }
    if (tool == 'delete_memory') {
      final int deleted = _toInt(obj['deleted_paths']) ?? 0;
      return deleted > 0
          ? _loc('已删除 $deleted 条路径', 'deleted $deleted paths')
          : _loc('已删除', 'deleted');
    }
    if (tool == 'add_alias') {
      return _loc('已创建别名', 'alias created');
    }
    final int count = _toInt(obj['count']) ?? -1;
    if (count >= 0) {
      final int? total = _toInt(obj['total_count']);
      if (total != null && total >= 0 && total != count) {
        return _loc('找到 $total 个（本页 $count）', 'found $total (page $count)');
      }
      return _loc('找到 $count 个', 'found $count');
    }
    return tool.isEmpty ? '' : _loc('完成', 'ok');
  }

  static List<Map<String, dynamic>>
  defaultChatTools() => <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'get_images',
        'description':
            'Load local screenshot images by evidence filename (basename) so the model can visually inspect them. Use ONLY when the provided text context is insufficient.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'filenames': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
              'description':
                  'Evidence filenames like 20251014_093112_AppA.png. Must be basenames from the provided evidence list. Request at most 15 per call, total image payload <= 10MB.',
            },
            'reason': <String, dynamic>{
              'type': 'string',
              'description': 'Why you need to see these images.',
            },
          },
          'required': <String>['filenames'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'read_memory',
        'description':
            'Read a long-term memory node by URI (Nocturne-style URI graph). Also supports special system URIs: system://boot, system://index[/<domain>], system://recent[/N].',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'uri': <String, dynamic>{
              'type': 'string',
              'description': 'Memory URI like core://agent or dynamic://2026/03/10.',
            },
          },
          'required': <String>['uri'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'create_memory',
        'description':
            'Create a new memory under a parent URI. Parent MUST exist. Use core:// or dynamic:// (ending with //) to create at domain root.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'parent_uri': <String, dynamic>{
              'type': 'string',
              'description': 'Parent URI, e.g. core://agent or core://.',
            },
            'content': <String, dynamic>{
              'type': 'string',
              'description': 'Memory content (Markdown allowed).',
            },
            'priority': <String, dynamic>{
              'type': 'integer',
              'description': 'Retrieval priority (lower = higher priority).',
            },
            'title': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional child name (a-z0-9_- only). If omitted, auto-assigns a numeric id.',
            },
            'disclosure': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional trigger condition: WHEN this memory should be recalled.',
            },
          },
          'required': <String>['parent_uri', 'content', 'priority'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'update_memory',
        'description':
            'Update a memory. Content editing modes are mutually exclusive: patch (old_string+new_string) OR append. Metadata updates (priority/disclosure) are allowed. Recommended: read_memory first.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'uri': <String, dynamic>{
              'type': 'string',
              'description': 'Memory URI to update, e.g. core://agent/my_user.',
            },
            'old_string': <String, dynamic>{
              'type': 'string',
              'description':
                  'Patch mode: text to replace (must match exactly ONE location).',
            },
            'new_string': <String, dynamic>{
              'type': 'string',
              'description':
                  'Patch mode: replacement text. Use empty string "" to delete.',
            },
            'append': <String, dynamic>{
              'type': 'string',
              'description': 'Append mode: text to append to the end.',
            },
            'priority': <String, dynamic>{
              'type': 'integer',
              'description': 'Optional new edge priority for this URI.',
            },
            'disclosure': <String, dynamic>{
              'type': 'string',
              'description': 'Optional new disclosure for this URI.',
            },
          },
          'required': <String>['uri'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'delete_memory',
        'description':
            'Delete a memory access path (URI). This removes the URI path (and descendant paths in the same domain) but preserves historical content versions for recovery.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'uri': <String, dynamic>{
              'type': 'string',
              'description': 'Memory URI to delete, e.g. core://agent/old_note.',
            },
          },
          'required': <String>['uri'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'add_alias',
        'description':
            'Create an alias URI pointing to the same memory as target_uri (not a copy). Automatically cascades descendant path mappings under the new alias.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'new_uri': <String, dynamic>{
              'type': 'string',
              'description': 'New alias URI to create.',
            },
            'target_uri': <String, dynamic>{
              'type': 'string',
              'description': 'Existing URI to point to.',
            },
            'priority': <String, dynamic>{
              'type': 'integer',
              'description': 'Optional priority for the alias edge (default 0).',
            },
            'disclosure': <String, dynamic>{
              'type': 'string',
              'description': 'Optional disclosure for the alias edge.',
            },
          },
          'required': <String>['new_uri', 'target_uri'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_memory',
        'description':
            'Search memories by substring match on URI path and content (NOT semantic search).',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description': 'Keyword to search.',
            },
            'domain': <String, dynamic>{
              'type': 'string',
              'description': 'Optional domain filter (e.g. core, dynamic).',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Optional max results (default 10, max 100).',
            },
          },
          'required': <String>['query'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_segments',
        'description':
            'List/search local segments (动态) by local date/time range and optional keyword (+ optional app filter by app NAME). Use start_local/end_local as human-readable local date/time strings (YYYY-MM-DD or YYYY-MM-DD HH:mm). The app will convert them to epoch ms internally. Do NOT provide epoch milliseconds. IMPORTANT: when query is empty, this runs in list mode (7-day cap per call). For wide ranges (e.g., full year), continue with paging.prev/paging.next to cover all windows. AI mode is capped to 365 days per call (larger windows will be clamped with paging hints). OCR mode has no per-call time limit; use start_local/end_local to constrain when needed.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional keyword (plain text). Do NOT write SQLite FTS operators (quotes, AND/OR/NOT, NEAR, parentheses, "*", col:term). The app will build a safe query internally. If omitted, list segments in the time range.',
            },
            'query_advanced': <String, dynamic>{
              'type': 'object',
              'description':
                  'Optional structured advanced query (recommended for complex boolean/proximity search). Use this instead of writing raw FTS syntax in query.',
              'properties': <String, dynamic>{
                'must': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description': 'All of these keyword groups must match (AND).',
                },
                'any': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description':
                      'At least one of these keyword groups must match (OR group).',
                },
                'must_not': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description':
                      'Exclude results matching these keyword groups (best-effort).',
                },
                'phrases': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description': 'All of these phrases must match.',
                },
                'phrases_any': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description': 'At least one of these phrases must match.',
                },
                'near': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{
                    'type': 'object',
                    'properties': <String, dynamic>{
                      'terms': <String, dynamic>{
                        'type': 'array',
                        'items': <String, dynamic>{'type': 'string'},
                        'description':
                            'Terms that should appear near each other.',
                      },
                      'distance': <String, dynamic>{
                        'type': 'integer',
                        'description':
                            'Optional max distance for NEAR (1-50).',
                      },
                    },
                    'required': <String>['terms'],
                  },
                  'description': 'Proximity constraints (FTS5 NEAR).',
                },
                'prefix': <String, dynamic>{
                  'type': 'boolean',
                  'description':
                      'Whether to use prefix matching for keyword tokens (default true).',
                },
              },
            },
            'start_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local start datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02" or "2025-07-02 09:30".',
            },
            'end_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local end datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02" or "2025-07-02 18:00".',
            },
            'app_name': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional app name filter (display name, e.g., 微信). Prefer app_names for multiple apps. Do NOT pass package names.',
            },
            'app_names': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
              'description':
                  'Optional app name filters (display names). Supports multiple apps in one call. Do NOT pass package names.',
            },
            'mode': <String, dynamic>{
              'type': 'string',
              'description': 'Optional search mode: auto | ai | ocr.',
            },
            'only_no_summary': <String, dynamic>{
              'type': 'boolean',
              'description':
                  'If true, only return segments without AI summary/result.',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max results (1-50).',
            },
            'offset': <String, dynamic>{
              'type': 'integer',
              'description': 'Offset for pagination (>=0).',
            },
            'per_segment_samples': <String, dynamic>{
              'type': 'integer',
              'description':
                  'For OCR mode: max matched sample filenames per segment (1-15).',
            },
          },
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'get_segment_result',
        'description':
            'Fetch a segment AI result by segment_id, including structured_json/output_text/categories and the segment time range.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'segment_id': <String, dynamic>{
              'type': 'integer',
              'description': 'Segment id.',
            },
            'max_chars': <String, dynamic>{
              'type': 'integer',
              'description':
                  'Optional max chars to return for long text fields.',
            },
          },
          'required': <String>['segment_id'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'get_segment_samples',
        'description':
            'List screenshot samples for a segment (file basenames + capture times). Use this to decide which images to request via get_images.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'segment_id': <String, dynamic>{
              'type': 'integer',
              'description': 'Segment id.',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max samples to return (1-60).',
            },
          },
          'required': <String>['segment_id'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_screenshots_ocr',
        'description':
            'Search screenshots by OCR text within a local date/time range (+ optional app filter by app NAME). Use start_local/end_local as human-readable local date/time strings (YYYY-MM-DD or YYYY-MM-DD HH:mm). The app will convert them to epoch ms internally. Do NOT provide epoch milliseconds. No per-call time limit; use start_local/end_local to constrain when needed. Returns screenshot file basenames + capture times + app info + total_count (matches in range) + has_more (for pagination).',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description':
                  'OCR query (plain text keywords). Optional if query_advanced is provided. Do NOT write SQLite FTS operators (quotes, AND/OR/NOT, NEAR, parentheses, "*", col:term). The app will build a safe query internally.',
            },
            'query_advanced': <String, dynamic>{
              'type': 'object',
              'description':
                  'Optional structured advanced query (recommended for complex boolean/proximity search). Provide either query or query_advanced. Use this instead of writing raw FTS syntax in query.',
              'properties': <String, dynamic>{
                'must': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description': 'All of these keyword groups must match (AND).',
                },
                'any': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description':
                      'At least one of these keyword groups must match (OR group).',
                },
                'must_not': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description':
                      'Exclude results matching these keyword groups (best-effort).',
                },
                'phrases': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description': 'All of these phrases must match.',
                },
                'phrases_any': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                  'description': 'At least one of these phrases must match.',
                },
                'near': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{
                    'type': 'object',
                    'properties': <String, dynamic>{
                      'terms': <String, dynamic>{
                        'type': 'array',
                        'items': <String, dynamic>{'type': 'string'},
                      },
                      'distance': <String, dynamic>{'type': 'integer'},
                    },
                    'required': <String>['terms'],
                  },
                  'description': 'Proximity constraints (FTS5 NEAR).',
                },
                'prefix': <String, dynamic>{'type': 'boolean'},
              },
            },
            'start_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local start datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02".',
            },
            'end_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local end datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-10".',
            },
            'app_name': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional app name filter (display name). Prefer app_names for multiple apps. Do NOT pass package names.',
            },
            'app_names': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
              'description':
                  'Optional app name filters (display names). Supports multiple apps in one call. Do NOT pass package names.',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max results (1-50).',
            },
            'offset': <String, dynamic>{
              'type': 'integer',
              'description': 'Offset for pagination (>=0).',
            },
          },
          'required': const <String>[],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_ai_image_meta',
        'description':
            'Search AI-generated per-image tags/descriptions (ai_image_meta) within a local date/time range (max 365 days per call; larger windows will be clamped with paging hints). Use start_local/end_local as human-readable local date/time strings (YYYY-MM-DD or YYYY-MM-DD HH:mm). The app will convert them to epoch ms internally. Do NOT provide epoch milliseconds. Useful when OCR is missing or insufficient.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description':
                  'Keyword query for tags/description (plain text). Optional if query_advanced is provided. Do NOT write SQLite FTS operators (quotes, AND/OR/NOT, NEAR, parentheses, "*", col:term). The app will build a safe query internally.',
            },
            'query_advanced': <String, dynamic>{
              'type': 'object',
              'description':
                  'Optional structured advanced query (recommended for complex boolean/proximity search). Provide either query or query_advanced. Use this instead of writing raw FTS syntax in query.',
              'properties': <String, dynamic>{
                'must': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                },
                'any': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                },
                'must_not': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                },
                'phrases': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                },
                'phrases_any': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string'},
                },
                'near': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{
                    'type': 'object',
                    'properties': <String, dynamic>{
                      'terms': <String, dynamic>{
                        'type': 'array',
                        'items': <String, dynamic>{'type': 'string'},
                      },
                      'distance': <String, dynamic>{'type': 'integer'},
                    },
                    'required': <String>['terms'],
                  },
                },
                'prefix': <String, dynamic>{'type': 'boolean'},
              },
            },
            'start_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local start datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02".',
            },
            'end_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local end datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-10".',
            },
            'app_name': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional app name filter (display name). Prefer app_names for multiple apps. Do NOT pass package names.',
            },
            'app_names': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
              'description':
                  'Optional app name filters (display names). Supports multiple apps in one call. Do NOT pass package names.',
            },
            'include_nsfw': <String, dynamic>{
              'type': 'boolean',
              'description': 'Whether to include NSFW results (default false).',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max results (1-50).',
            },
            'offset': <String, dynamic>{
              'type': 'integer',
              'description': 'Offset for pagination (>=0).',
            },
          },
          'required': const <String>[],
        },
      },
    },
  ];

  String _detectImageMimeByExt(String path) {
    final String p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  bool _looksLikeBasename(String name) {
    final String t = name.trim();
    if (t.isEmpty) return false;
    if (t.contains('/') || t.contains('\\')) return false;
    if (t.length > 200) return false;
    return true;
  }

  int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String? _toTrimmedStringOrNull(Object? v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  int? _parseLocalDateTimeToEpochMs(Object? raw, {required bool isEnd}) {
    final String? t0 = _toTrimmedStringOrNull(raw);
    if (t0 == null) return null;

    // Date-only: YYYY-MM-DD (treat as start-of-day / end-of-day in local time)
    final Match? mDate = RegExp(
      r'^([12]\d{3})-(\d{1,2})-(\d{1,2})$',
    ).firstMatch(t0);
    if (mDate != null) {
      final int year = int.tryParse(mDate.group(1) ?? '') ?? 0;
      final int month = int.tryParse(mDate.group(2) ?? '') ?? 0;
      final int day = int.tryParse(mDate.group(3) ?? '') ?? 0;
      if (year <= 0 || month <= 0 || day <= 0) return null;
      final DateTime dt = isEnd
          ? DateTime(year, month, day, 23, 59, 59, 999, 0)
          : DateTime(year, month, day, 0, 0, 0, 0, 0);
      if (dt.year != year || dt.month != month || dt.day != day) return null;
      return dt.millisecondsSinceEpoch;
    }

    // Date + time: YYYY-MM-DD HH:mm[:ss] (local time)
    final Match? mDateTime = RegExp(
      r'^([12]\d{3})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$',
    ).firstMatch(t0);
    if (mDateTime != null) {
      final int year = int.tryParse(mDateTime.group(1) ?? '') ?? 0;
      final int month = int.tryParse(mDateTime.group(2) ?? '') ?? 0;
      final int day = int.tryParse(mDateTime.group(3) ?? '') ?? 0;
      final int hour = int.tryParse(mDateTime.group(4) ?? '') ?? -1;
      final int minute = int.tryParse(mDateTime.group(5) ?? '') ?? -1;
      final int second = int.tryParse(mDateTime.group(6) ?? '') ?? 0;
      if (year <= 0 || month <= 0 || day <= 0) return null;
      if (hour < 0 || hour > 23) return null;
      if (minute < 0 || minute > 59) return null;
      if (second < 0 || second > 59) return null;
      final DateTime dt = DateTime(
        year,
        month,
        day,
        hour,
        minute,
        second,
        0,
        0,
      );
      if (dt.year != year || dt.month != month || dt.day != day) return null;
      if (dt.hour != hour || dt.minute != minute || dt.second != second) {
        return null;
      }
      return dt.millisecondsSinceEpoch;
    }

    // ISO-8601 fallback: allow offsets (will be parsed into UTC), or local if no zone is provided.
    DateTime? dt = DateTime.tryParse(t0);
    if (dt == null && t0.contains(' ') && !t0.contains('T')) {
      dt = DateTime.tryParse(t0.replaceFirst(' ', 'T'));
    }
    return dt?.millisecondsSinceEpoch;
  }

  bool _toBool(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final String s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return false;
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  String _basename(String path) {
    final int idx1 = path.lastIndexOf('/');
    final int idx2 = path.lastIndexOf('\\');
    final int idx = idx1 > idx2 ? idx1 : idx2;
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  String _clipText(String text, int maxChars) {
    if (maxChars <= 0) return '';
    final String t = text.trim();
    if (t.isEmpty) return '';
    return t.length <= maxChars ? t : (t.substring(0, maxChars) + '…');
  }

  String _extractSegmentSummary(
    Map<String, dynamic> row, {
    int maxChars = 420,
  }) {
    final String sj = (row['structured_json'] as String?)?.trim() ?? '';
    if (sj.isNotEmpty) {
      try {
        final dynamic v = jsonDecode(sj);
        if (v is Map) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(v as Map);
          final String s1 = (m['overall_summary'] as String?)?.trim() ?? '';
          if (s1.isNotEmpty) return _clipText(s1, maxChars);
          final String s2 = (m['summary'] as String?)?.trim() ?? '';
          if (s2.isNotEmpty) return _clipText(s2, maxChars);
          final String s3 = (m['notification_brief'] as String?)?.trim() ?? '';
          if (s3.isNotEmpty) return _clipText(s3, maxChars);
        }
      } catch (_) {}
    }
    final String ot = (row['output_text'] as String?)?.trim() ?? '';
    if (ot.isNotEmpty) return _clipText(ot, maxChars);
    final String cat = (row['categories'] as String?)?.trim() ?? '';
    if (cat.isNotEmpty) return _clipText(cat, maxChars);
    return '';
  }

  Map<String, dynamic> _safeJsonObject(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return <String, dynamic>{};
    try {
      final dynamic v = jsonDecode(t);
      if (v is Map) return Map<String, dynamic>.from(v as Map);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Object? _sortJsonForSignature(Object? v) {
    if (v is Map) {
      final Map<dynamic, dynamic> raw = Map<dynamic, dynamic>.from(v as Map);
      final List<String> keys = raw.keys.map((k) => k.toString()).toList()
        ..sort();
      final Map<String, Object?> out = <String, Object?>{};
      for (final String k in keys) {
        out[k] = _sortJsonForSignature(raw[k]);
      }
      return out;
    }
    if (v is List) {
      return v.map((e) => _sortJsonForSignature(e)).toList();
    }
    return v;
  }

  int _normalizeStartMs(Map<String, dynamic> args) {
    final int? ms =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    return ms ?? 0;
  }

  int _normalizeEndMs(Map<String, dynamic> args) {
    final int? ms =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);
    return ms ?? 0;
  }

  List<String> _normalizeAppNamesArg(Map<String, dynamic> args) {
    final List<String> out = <String>[];
    final dynamic raw = args.containsKey('app_names')
        ? args['app_names']
        : (args.containsKey('app_name') ? args['app_name'] : null);
    if (raw is List) {
      for (final v in raw) {
        final String t = v?.toString().trim() ?? '';
        if (t.isNotEmpty) out.add(t);
      }
    } else if (raw is String) {
      final String t = raw.trim();
      if (t.isNotEmpty) out.add(t);
    }
    final List<String> uniq = <String>{...out}.toList()..sort();
    return uniq;
  }

  List<String> _normalizeLegacyAppPackageNamesArg(Map<String, dynamic> args) {
    final List<String> out = <String>[];
    final dynamic raw = args.containsKey('app_package_names')
        ? args['app_package_names']
        : (args.containsKey('app_package_name')
              ? args['app_package_name']
              : null);
    if (raw is List) {
      for (final v in raw) {
        final String t = v?.toString().trim() ?? '';
        if (t.isNotEmpty) out.add(t);
      }
    } else if (raw is String) {
      final String t = raw.trim();
      if (t.isNotEmpty) out.add(t);
    }
    final List<String> uniq = <String>{...out}.toList()..sort();
    return uniq;
  }

  Future<List<String>> _resolveAppPackagesFromArgs(
    Map<String, dynamic> args,
  ) async {
    // IMPORTANT: only accept human app display names for filtering.
    // Some models hallucinate package names; ignoring package filters is safer.
    final List<String> appNames = _normalizeAppNamesArg(args);
    if (appNames.isEmpty) return <String>[];
    return await ScreenshotDatabase.instance.findPackagesByAppNames(appNames);
  }

  void _warnIfLegacyAppPackageArgsUsed(
    Map<String, dynamic> args,
    List<String> warnings,
  ) {
    final List<String> legacyPkgs = _normalizeLegacyAppPackageNamesArg(args);
    if (legacyPkgs.isEmpty) return;
    warnings.add(
      _loc(
        '提示：已忽略 app_package_name / app_package_names（请使用 app_name / app_names 传应用显示名）。',
        'Note: app_package_name(s) ignored; use app_name/app_names (display names).',
      ),
    );
  }

  String _toolCallSignature(AIToolCall call) {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final Map<String, dynamic> sig = <String, dynamic>{'tool': call.name};
    int msToMin(int ms) => ms <= 0 ? 0 : (ms ~/ 60000);

    switch (call.name) {
      case 'search_screenshots_ocr':
        sig['query'] = (args['query'] as String?)?.trim() ?? '';
        final List<String> appNames = _normalizeAppNamesArg(args);
        if (appNames.isNotEmpty) sig['app_names'] = appNames;
        sig['start_min'] = msToMin(_normalizeStartMs(args));
        sig['end_min'] = msToMin(_normalizeEndMs(args));
        sig['limit'] = (_toInt(args['limit']) ?? 20).clamp(1, 50);
        sig['offset'] = (_toInt(args['offset']) ?? 0).clamp(0, 1 << 30);
        break;
      case 'search_segments':
        sig['query'] = (args['query'] as String?)?.trim() ?? '';
        final List<String> appNames = _normalizeAppNamesArg(args);
        if (appNames.isNotEmpty) sig['app_names'] = appNames;
        String mode = (args['mode'] as String?)?.trim().toLowerCase() ?? '';
        if (mode.isEmpty) mode = 'auto';
        if (mode != 'auto' && mode != 'ai' && mode != 'ocr') mode = 'auto';
        sig['mode'] = mode;
        sig['only_no_summary'] = _toBool(args['only_no_summary']);
        sig['start_min'] = msToMin(_normalizeStartMs(args));
        sig['end_min'] = msToMin(_normalizeEndMs(args));
        sig['limit'] = (_toInt(args['limit']) ?? 10).clamp(1, 50);
        sig['offset'] = (_toInt(args['offset']) ?? 0).clamp(0, 1 << 30);
        break;
      case 'search_ai_image_meta':
        sig['query'] = (args['query'] as String?)?.trim() ?? '';
        final List<String> appNames = _normalizeAppNamesArg(args);
        if (appNames.isNotEmpty) sig['app_names'] = appNames;
        sig['include_nsfw'] = _toBool(args['include_nsfw']);
        sig['start_min'] = msToMin(_normalizeStartMs(args));
        sig['end_min'] = msToMin(_normalizeEndMs(args));
        sig['limit'] = (_toInt(args['limit']) ?? 20).clamp(1, 50);
        sig['offset'] = (_toInt(args['offset']) ?? 0).clamp(0, 1 << 30);
        break;
      case 'get_segment_result':
        sig['segment_id'] = _toInt(args['segment_id']) ?? 0;
        break;
      case 'get_segment_samples':
        sig['segment_id'] = _toInt(args['segment_id']) ?? 0;
        sig['limit'] = (_toInt(args['limit']) ?? 10).clamp(1, 50);
        break;
      case 'get_images':
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
        final List<String> uniq = <String>{...names}.toList()..sort();
        sig['filenames'] = uniq;
        break;
      default:
        sig['args'] = _sortJsonForSignature(args);
        break;
    }

    return jsonEncode(_sortJsonForSignature(sig));
  }

  String _toolCallUiLabel(AIToolCall call) {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    final String mode = (args['mode'] as String?)?.trim().toLowerCase() ?? '';

    final int startMs = _normalizeStartMs(args);
    final int endMs = _normalizeEndMs(args);
    final String range = (startMs > 0 && endMs > 0)
        ? _formatLocalRangeForToolUi(startMs, endMs)
        : '';
    final String rangeSuffix = range.isEmpty ? '' : ' · $range';

    String clip(String s, {int maxLen = 28}) => _clipLine(s, maxLen: maxLen);
    String withOptionalQueryZh(String head) {
      // Avoid noisy placeholders like "（列出）" when listing with empty query.
      return query.isEmpty
          ? '$head$rangeSuffix'
          : '$head：${clip(query)}$rangeSuffix';
    }

    String withOptionalQueryEn(String head) {
      return query.isEmpty
          ? '$head$rangeSuffix'
          : '$head: ${clip(query)}$rangeSuffix';
    }

    switch (call.name) {
      case 'search_screenshots_ocr':
        return _loc(
          '搜索 OCR：${query.isEmpty ? '（无关键词）' : clip(query)}$rangeSuffix',
          'Search OCR: ${query.isEmpty ? '(no query)' : clip(query)}$rangeSuffix',
        );
      case 'search_segments':
        if (mode == 'ocr') {
          return _loc(
            withOptionalQueryZh('搜索动态'),
            withOptionalQueryEn('Search segments'),
          );
        }
        if (mode == 'ai') {
          return _loc(
            withOptionalQueryZh('搜索动态'),
            withOptionalQueryEn('Search segments'),
          );
        }
        return _loc(
          withOptionalQueryZh('搜索动态'),
          withOptionalQueryEn('Search segments'),
        );
      case 'search_segments_ocr':
        return _loc(
          withOptionalQueryZh('搜索动态'),
          withOptionalQueryEn('Search segments'),
        );
      case 'search_ai_image_meta':
        return _loc(
          '搜索图片：${query.isEmpty ? '（无关键词）' : clip(query)}$rangeSuffix',
          'Search images: ${query.isEmpty ? '(no query)' : clip(query)}$rangeSuffix',
        );
      case 'get_segment_result':
        final int sid = _toInt(args['segment_id']) ?? 0;
        return sid > 0
            ? _loc('获取片段：#$sid', 'Get segment: #$sid')
            : _loc('获取片段结果', 'Get segment result');
      case 'get_segment_samples':
        final int sid = _toInt(args['segment_id']) ?? 0;
        final int limit = (_toInt(args['limit']) ?? 10).clamp(1, 50);
        return sid > 0
            ? _loc('抽样片段：#$sid · $limit 条', 'Sample segment: #$sid · $limit')
            : _loc('抽样片段：$limit 条', 'Sample segment: $limit');
      case 'get_images':
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
        final int count = <String>{...names}.length;
        return count <= 0
            ? _loc('查看图片', 'View images')
            : _loc('查看图片：$count 张', 'View images: $count');
      default:
        return call.name;
    }
  }

  Map<String, dynamic> _toolPayloadDigest(Map<String, dynamic> payload) {
    final Map<String, dynamic> out = <String, dynamic>{};
    const List<String> keep = <String>[
      'tool',
      'query',
      'mode',
      'app_name',
      'app_names',
      // Backward compatibility: old tool payloads may include package filters.
      'app_package_name',
      'app_package_names',
      'start_local',
      'end_local',
      'limit',
      'offset',
      'count',
      'warnings',
      'paging',
      'segment_id',
      'path',
      'from',
      'lines',
      'max_chars',
      'start_line',
      'end_line',
      'provided',
      'missing',
      'skipped',
      'stats',
      'results',
    ];
    for (final String k in keep) {
      if (payload.containsKey(k)) out[k] = payload[k];
    }
    return out;
  }
}

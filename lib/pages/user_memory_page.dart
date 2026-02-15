import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talker/talker.dart';

import '../services/user_memory_index_service.dart';
import '../services/user_memory_service.dart';
import '../services/flutter_logger.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';

class UserMemoryPage extends StatefulWidget {
  const UserMemoryPage({super.key});

  @override
  State<UserMemoryPage> createState() => _UserMemoryPageState();
}

class _UserMemoryPageState extends State<UserMemoryPage>
    with SingleTickerProviderStateMixin {
  final UserMemoryService _mem = UserMemoryService.instance;
  final UserMemoryIndexService _index = UserMemoryIndexService.instance;

  final TextEditingController _profileCtrl = TextEditingController();
  UserMemoryProfile? _profile;
  bool _profileLoading = false;
  bool _profileSaving = false;
  bool _autoRefreshing = false;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  String? _kindFilter; // rule | habit | fact | null
  bool _pinnedOnly = false;
  bool _itemsLoading = false;
  List<UserMemoryItem> _items = const <UserMemoryItem>[];

  UserMemoryIndexState? _indexState;
  StreamSubscription<UserMemoryIndexState>? _indexSub;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadItems();
    _loadIndexState();

    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        final String next = _searchCtrl.text.trim();
        if (next == _query) return;
        setState(() {
          _query = next;
        });
        _loadItems();
      });
    });
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    _searchDebounce?.cancel();
    _profileCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (_profileLoading) return;
    setState(() {
      _profileLoading = true;
    });
    try {
      final UserMemoryProfile p = await _mem.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _profileCtrl.text = p.userMarkdown;
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
      }
    }
  }

  Future<void> _saveUserProfile() async {
    if (_profileSaving) return;
    setState(() {
      _profileSaving = true;
    });
    try {
      await _mem.setUserProfileMarkdown(_profileCtrl.text);
      await _loadProfile();
      if (!mounted) return;
      UINotifier.success(context, '已保存');
    } catch (_) {
      if (!mounted) return;
      UINotifier.error(context, '保存失败');
    } finally {
      if (mounted) {
        setState(() {
          _profileSaving = false;
        });
      }
    }
  }

  Future<void> _refreshAutoProfile() async {
    if (_autoRefreshing) return;
    setState(() {
      _autoRefreshing = true;
    });
    try {
      await _mem.refreshAutoProfile();
      await _loadProfile();
      if (!mounted) return;
      UINotifier.success(context, '已刷新自动画像');
    } catch (_) {
      if (!mounted) return;
      UINotifier.error(context, '刷新失败');
    } finally {
      if (mounted) {
        setState(() {
          _autoRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadItems() async {
    if (_itemsLoading) return;
    setState(() {
      _itemsLoading = true;
    });
    try {
      final String q = _query.trim();
      final List<UserMemoryItem> out = q.isEmpty
          ? await _mem.listItems(
              kind: _kindFilter,
              pinned: _pinnedOnly ? true : null,
              limit: 80,
              offset: 0,
            )
          : await _mem.searchItems(
              q,
              kind: _kindFilter,
              pinned: _pinnedOnly ? true : null,
              limit: 80,
              offset: 0,
            );
      if (!mounted) return;
      setState(() {
        _items = out;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const <UserMemoryItem>[];
      });
    } finally {
      if (mounted) {
        setState(() {
          _itemsLoading = false;
        });
      }
    }
  }

  Future<void> _loadIndexState() async {
    try {
      final st = await _index.getState();
      if (!mounted) return;
      setState(() {
        _indexState = st;
      });
      // If the app restarted while indexing was "running", resume automatically.
      if (st != null && st.status == 'running') {
        unawaited(_index.resume());
      }
    } catch (_) {}

    _indexSub?.cancel();
    _indexSub = _index.onStateChanged.listen((st) {
      if (!mounted) return;
      setState(() {
        _indexState = st;
      });
    });
  }

  String _formatLogTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  List<TalkerData> _recentMemoryIndexAiTraceLogs({int limit = 12}) {
    final List<TalkerData> items = FlutterLogger.talker.history
        .where((e) {
          final String msg = (e.message ?? '').trimLeft();
          if (!msg.startsWith('[AITrace]')) return false;
          return msg.contains('user_memory_index_segment_');
        })
        .toList(growable: false);
    if (items.length <= limit) return items;
    return items.sublist(items.length - limit);
  }

  String _buildAiTraceExportText(List<TalkerData> items) {
    final StringBuffer sb = StringBuffer();
    for (final TalkerData e in items) {
      final String msg = (e.message ?? '').trimRight();
      sb.writeln('[${_formatLogTime(e.time)}] ${msg.isEmpty ? '(empty)' : msg}');
      final Object? ex = e.exception ?? e.error;
      if (ex != null) sb.writeln(ex.toString());
      if (e.stackTrace != null && e.stackTrace != StackTrace.empty) {
        sb.writeln(e.stackTrace.toString());
      }
      sb.writeln();
    }
    return sb.toString().trimRight();
  }

  String _fmtMs(int? ms) {
    if (ms == null || ms <= 0) return '';
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openItemEditor(UserMemoryItem item) async {
    final Map<String, dynamic>? row = await _mem.getItemRow(item.id);
    if (!mounted) return;

    final TextEditingController contentCtrl = TextEditingController(
      text: (row?['content'] as String?)?.trim() ?? item.content,
    );
    final TextEditingController keyCtrl = TextEditingController(
      text: (row?['memory_key'] as String?)?.trim() ?? (item.memoryKey ?? ''),
    );

    String kind = (row?['kind'] as String?)?.trim() ?? item.kind;
    bool pinned = ((row?['pinned'] as int?) ?? (item.pinned ? 1 : 0)) != 0;

    String keywordsText = '';
    try {
      final String raw = (row?['keywords_json'] as String?) ?? '';
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List) {
        keywordsText = decoded
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .join(', ');
      }
    } catch (_) {}
    final TextEditingController keywordsCtrl = TextEditingController(
      text: keywordsText,
    );

    Future<List<UserMemoryEvidence>> loadEvidence() =>
        _mem.listEvidenceForItem(item.id);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('编辑记忆'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Kind:'),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: kind,
                        items: const [
                          DropdownMenuItem(value: 'rule', child: Text('rule')),
                          DropdownMenuItem(
                            value: 'habit',
                            child: Text('habit'),
                          ),
                          DropdownMenuItem(value: 'fact', child: Text('fact')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          kind = v;
                          (ctx as Element).markNeedsBuild();
                        },
                      ),
                      const SizedBox(width: 12),
                      Checkbox(
                        value: pinned,
                        onChanged: (v) {
                          pinned = v ?? false;
                          (ctx as Element).markNeedsBuild();
                        },
                      ),
                      const Text('Pinned'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: keyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Key (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: keywordsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Keywords (comma separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Content',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                    minLines: 4,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Evidence',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<List<UserMemoryEvidence>>(
                    future: loadEvidence(),
                    builder: (c2, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Text('Loading…');
                      }
                      final List<UserMemoryEvidence> ev = snap.data ?? const [];
                      if (ev.isEmpty) return const Text('(empty)');
                      final List<String> lines = <String>[];
                      for (final e in ev.take(8)) {
                        final String files = e.filenames.isEmpty
                            ? '(no files)'
                            : e.filenames.join(', ');
                        lines.add('${e.sourceType}:${e.sourceId} → $files');
                      }
                      return Text(lines.join('\n'));
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final ok = await _mem.updateItem(
                  id: item.id,
                  kind: kind,
                  memoryKey: keyCtrl.text,
                  content: contentCtrl.text,
                  keywords: keywordsCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                );
                if (ok) {
                  await _mem.setPinned(item.id, pinned);
                  if (mounted) {
                    Navigator.of(ctx).pop();
                    await _loadItems();
                  }
                } else {
                  if (ctx.mounted) {
                    UINotifier.error(ctx, '保存失败');
                  }
                }
              },
              child: const Text('保存'),
            ),
            TextButton(
              onPressed: () async {
                await _mem.deleteItem(item.id);
                if (mounted) {
                  Navigator.of(ctx).pop();
                  await _loadItems();
                }
              },
              child: const Text('删除'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );

    contentCtrl.dispose();
    keyCtrl.dispose();
    keywordsCtrl.dispose();
  }

  Widget _buildProfileTab() {
    final UserMemoryProfile? p = _profile;
    final String autoText = p?.autoMarkdown.trim() ?? '';
    final String userUpdated = _fmtMs(p?.userUpdatedAtMs);
    final String autoUpdated = _fmtMs(p?.autoUpdatedAtMs);

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '用户画像（可编辑）',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              userUpdated.isEmpty ? '' : '更新：$userUpdated',
              style: const TextStyle(color: AppTheme.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing2),
        TextField(
          controller: _profileCtrl,
          decoration: const InputDecoration(
            hintText: '在这里写入你希望 AI 永久记住的偏好/约束/背景…',
            border: OutlineInputBorder(),
          ),
          maxLines: null,
          minLines: 8,
        ),
        const SizedBox(height: AppTheme.spacing2),
        Row(
          children: [
            ElevatedButton(
              onPressed: _profileLoading || _profileSaving
                  ? null
                  : _saveUserProfile,
              child: Text(_profileSaving ? '保存中…' : '保存'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _profileLoading || _autoRefreshing
                  ? null
                  : _refreshAutoProfile,
              child: Text(_autoRefreshing ? '刷新中…' : '刷新自动画像'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: autoText.isEmpty
                  ? null
                  : () {
                      _profileCtrl.text = autoText;
                      UINotifier.success(context, '已复制到用户画像（未保存）');
                    },
              child: const Text('用自动画像覆盖（不保存）'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing5),
        Row(
          children: [
            const Expanded(
              child: Text(
                '自动画像（只读）',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              autoUpdated.isEmpty ? '' : '更新：$autoUpdated',
              style: const TextStyle(color: AppTheme.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spacing3),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: SelectableText(autoText.isEmpty ? '(empty)' : autoText),
        ),
      ],
    );
  }

  Widget _buildItemsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacing3),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索记忆…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String?>(
                value: _kindFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('all')),
                  DropdownMenuItem(value: 'rule', child: Text('rule')),
                  DropdownMenuItem(value: 'habit', child: Text('habit')),
                  DropdownMenuItem(value: 'fact', child: Text('fact')),
                ],
                onChanged: (v) {
                  setState(() {
                    _kindFilter = v;
                  });
                  _loadItems();
                },
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: _pinnedOnly,
                onChanged: (v) {
                  setState(() {
                    _pinnedOnly = v ?? false;
                  });
                  _loadItems();
                },
              ),
              const Text('Pinned'),
            ],
          ),
        ),
        Expanded(
          child: _itemsLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final UserMemoryItem it = _items[i];
                    final String tail = _fmtMs(it.updatedAtMs);
                    return ListTile(
                      title: Text(
                        it.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${it.kind}${tail.isEmpty ? '' : ' · $tail'}',
                      ),
                      leading: Icon(
                        it.kind == 'rule'
                            ? Icons.rule
                            : it.kind == 'habit'
                            ? Icons.repeat
                            : Icons.info_outline,
                        color: it.pinned
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      trailing: IconButton(
                        tooltip: it.pinned ? 'Unpin' : 'Pin',
                        icon: Icon(
                          it.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        ),
                        onPressed: () async {
                          await _mem.setPinned(it.id, !it.pinned);
                          await _loadItems();
                        },
                      ),
                      onTap: () => _openItemEditor(it),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReindexTab() {
    final UserMemoryIndexState? st = _indexState;
    final String status = st?.status ?? 'idle';
    final Map<String, dynamic> stats = st?.stats ?? const <String, dynamic>{};
    final int processed = (stats['processed_segments'] as int?) ?? 0;
    final int total = (stats['total_segments'] as int?) ?? 0;
    final int errors = (stats['errors'] as int?) ?? 0;
    final int inserted = (stats['inserted'] as int?) ?? 0;
    final int updated = (stats['updated'] as int?) ?? 0;
    final int touched = (stats['touched'] as int?) ?? 0;
    final int images = (stats['processed_images'] as int?) ?? 0;

    final double progress = (total > 0)
        ? (processed / total).clamp(0.0, 1.0)
        : 0.0;

    final List<TalkerData> traces = _recentMemoryIndexAiTraceLogs(limit: 12);
    final String traceText =
        traces.isEmpty ? '' : _buildAiTraceExportText(traces);

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      children: [
        Text('状态：$status'),
        const SizedBox(height: AppTheme.spacing2),
        LinearProgressIndicator(value: total > 0 ? progress : null),
        const SizedBox(height: AppTheme.spacing2),
        Text('进度：$processed / ${total > 0 ? total : 'unknown'}'),
        const SizedBox(height: AppTheme.spacing2),
        Text(
          '图片：$images · inserted=$inserted · updated=$updated · touched=$touched · errors=$errors',
        ),
        if ((stats['last_error'] as String?)?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppTheme.spacing2),
          Text(
            '最近错误：${(stats['last_error'] as String).trim()}',
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
        if (traceText.trim().isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing3),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '请求/响应日志（memory 重建）',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '复制',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        try {
                          await Clipboard.setData(
                            ClipboardData(text: traceText),
                          );
                          if (mounted) UINotifier.success(context, '已复制');
                        } catch (_) {
                          if (mounted) UINotifier.error(context, '复制失败');
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      traceText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spacing3),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton(
              onPressed: status == 'running'
                  ? null
                  : () => _index.startFullReindex(),
              child: const Text('立即全量重建'),
            ),
            OutlinedButton(
              onPressed: status == 'running' ? () => _index.pause() : null,
              child: const Text('暂停'),
            ),
            OutlinedButton(
              onPressed: status == 'paused' ? () => _index.resume() : null,
              child: const Text('恢复'),
            ),
            TextButton(
              onPressed: (status == 'running' || status == 'paused')
                  ? () => _index.cancel()
                  : null,
              child: const Text('取消'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing4),
        const Text(
          '说明：重建会从历史 segment 的截图重新进行视觉识别，以提取可长期保存的用户偏好/习惯/事实，并写入全局记忆库。单次请求最多 12 张图，总 payload <= 10MB（超出会自动跳过部分图片）。建议在 Wi‑Fi 下进行。',
          style: TextStyle(color: AppTheme.mutedForeground),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('记忆 / Memory'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '画像'),
              Tab(text: '记忆项'),
              Tab(text: '重建'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_buildProfileTab(), _buildItemsTab(), _buildReindexTab()],
        ),
      ),
    );
  }
}

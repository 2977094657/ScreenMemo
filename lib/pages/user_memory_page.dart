import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:talker/talker.dart';

import '../l10n/app_localizations.dart';
import '../services/ai_providers_service.dart';
import '../services/ai_settings_service.dart';
import '../services/user_memory_index_service.dart';
import '../services/user_memory_service.dart';
import '../services/flutter_logger.dart';
import '../theme/app_theme.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/ai_request_logs_action.dart';
import '../widgets/ai_request_logs_viewer.dart';
import '../widgets/ai_request_logs_sheet.dart';
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

  AIProvider? _ctxMemProvider;
  String? _ctxMemModel;
  String _memProviderQueryText = '';
  String _memModelQueryText = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadItems();
    _loadIndexState();
    _loadMemoryContextSelection();

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

  // 载入“记忆(memory)”的提供商/模型选择（独立于对话页）
  Future<void> _loadMemoryContextSelection() async {
    try {
      final svc = AIProvidersService.instance;
      final providers = await svc.listProviders();
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _ctxMemProvider = null;
            _ctxMemModel = null;
          });
        }
        return;
      }

      final ctxRow = await AISettingsService.instance.getAIContextRow('memory');
      AIProvider? sel;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        sel = await svc.getProvider(ctxRow['provider_id'] as int);
      }
      sel ??= await svc.getDefaultProvider();
      sel ??= providers.first;

      String model =
          (ctxRow != null &&
                  (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
              ? (ctxRow['model'] as String).trim()
              : ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                    .toString();
      if (model.isEmpty && sel.models.isNotEmpty) model = sel.models.first;

      if (mounted) {
        setState(() {
          _ctxMemProvider = sel;
          _ctxMemModel = model;
        });
      }
    } catch (_) {}
  }

  Future<void> _showProviderSheetMemory() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final currentId = _ctxMemProvider?.id ?? -1;
        // 使用持久化查询文本，避免键盘开合/重建导致输入被清空
        final TextEditingController queryCtrl = TextEditingController(
          text: _memProviderQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                final q = queryCtrl.text.trim().toLowerCase();
                final filtered = list.where((p) {
                  if (q.isEmpty) return true;
                  final name = p.name.toLowerCase();
                  final type = p.type.toLowerCase();
                  final base = (p.baseUrl ?? '').toString().toLowerCase();
                  return name.contains(q) ||
                      type.contains(q) ||
                      base.contains(q);
                }).toList();
                // 将当前选中的提供商置顶，便于观察
                final selIdx = filtered.indexWhere((e) => e.id == currentId);
                if (selIdx > 0) {
                  final sel = filtered.removeAt(selIdx);
                  filtered.insert(0, sel);
                }
                return UISheetSurface(
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      const UISheetHandle(),
                      const SizedBox(height: AppTheme.spacing3),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _memProviderQueryText = queryCtrl.text;
                            setModalState(() {});
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: AppLocalizations.of(
                              context,
                            ).searchProviderPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(
                              c,
                            ).colorScheme.outline.withOpacity(0.6),
                          ),
                          itemBuilder: (c, i) {
                            final p = filtered[i];
                            final selected = p.id == currentId;
                            return ListTile(
                              leading: SvgPicture.asset(
                                ModelIconUtils.getProviderIconPath(p.type),
                                width: 20,
                                height: 20,
                              ),
                              title: Text(
                                p.name,
                                style: Theme.of(c).textTheme.bodyMedium,
                              ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(c).colorScheme.onSurface,
                                    )
                                  : null,
                              onTap: () async {
                                String model = (_ctxMemModel ?? '').trim();
                                if (model.isEmpty) {
                                  model =
                                      ((p.extra['active_model'] as String?) ??
                                              p.defaultModel)
                                          .toString()
                                          .trim();
                                }
                                if (model.isEmpty && p.models.isNotEmpty) {
                                  model = p.models.first;
                                }
                                await AISettingsService.instance
                                    .setAIContextSelection(
                                      context: 'memory',
                                      providerId: p.id!,
                                      model: model,
                                    );
                                if (mounted) {
                                  setState(() {
                                    _ctxMemProvider = p;
                                    _ctxMemModel = model;
                                  });
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    ).providerSelectedToast(p.name),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showModelSheetMemory() async {
    final p = _ctxMemProvider;
    if (p == null) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).pleaseSelectProviderFirst,
      );
      return;
    }
    final models = p.models;
    if (models.isEmpty) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).noModelsForProviderHint,
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final active = (_ctxMemModel ?? '').trim();
        // 使用持久化查询文本，避免失焦时文本被清空
        final TextEditingController queryCtrl = TextEditingController(
          text: _memModelQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                final q = queryCtrl.text.trim().toLowerCase();
                final filtered = models.where((mm) {
                  if (q.isEmpty) return true;
                  return mm.toLowerCase().contains(q);
                }).toList();
                // 将当前选中的模型置顶
                if (active.isNotEmpty && filtered.contains(active)) {
                  final idx = filtered.indexOf(active);
                  if (idx > 0) {
                    final sel = filtered.removeAt(idx);
                    filtered.insert(0, sel);
                  }
                }
                return UISheetSurface(
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      const UISheetHandle(),
                      const SizedBox(height: AppTheme.spacing3),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _memModelQueryText = queryCtrl.text;
                            setModalState(() {});
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: AppLocalizations.of(
                              context,
                            ).searchModelPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(
                              c,
                            ).colorScheme.outline.withOpacity(0.6),
                          ),
                          itemBuilder: (c, i) {
                            final m = filtered[i];
                            final selected = m == active;
                            return ListTile(
                              leading: SvgPicture.asset(
                                ModelIconUtils.getIconPath(m),
                                width: 20,
                                height: 20,
                              ),
                              title: Text(
                                m,
                                style: Theme.of(c).textTheme.bodyMedium,
                              ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(c).colorScheme.primary,
                                    )
                                  : null,
                              onTap: () async {
                                await AISettingsService.instance
                                    .setAIContextSelection(
                                      context: 'memory',
                                      providerId: p.id!,
                                      model: m,
                                    );
                                if (mounted) {
                                  setState(() => _ctxMemModel = m);
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    ).modelSwitchedToast(m),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// AppBar 顶部：仅显示内容并加下划线（provider / model），不显示“提供商”字样
  Widget _buildMemoryProviderModelAppBarTitle() {
    final theme = Theme.of(context);
    final String providerName = _ctxMemProvider?.name ?? '—';
    final String modelName = _ctxMemModel ?? '—';
    final TextStyle? linkStyle = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurface.withOpacity(0.6),
      color: theme.colorScheme.onSurface,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (modelName.trim().isNotEmpty && modelName != '—') ...[
          SvgPicture.asset(
            ModelIconUtils.getIconPath(modelName),
            width: 18,
            height: 18,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: GestureDetector(
            onTap: _showProviderSheetMemory,
            behavior: HitTestBehavior.opaque,
            child: Text(
              providerName,
              style: linkStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: GestureDetector(
            onTap: _showModelSheetMemory,
            behavior: HitTestBehavior.opaque,
            child: Text(
              modelName,
              style: linkStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  String _formatLogTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  List<TalkerData> _recentMemoryIndexAiTraceLogs({
    int limit = 12,
    int? sinceMs,
  }) {
    final DateTime? since = (sinceMs == null || sinceMs <= 0)
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sinceMs);
    final List<TalkerData> items = FlutterLogger.talker.history
        .where((e) {
          if (since != null && e.time.isBefore(since)) return false;
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
      sb.writeln(
        '[${_formatLogTime(e.time)}] ${msg.isEmpty ? '(empty)' : msg}',
      );
      final Object? ex = e.exception ?? e.error;
      if (ex != null) sb.writeln(ex.toString());
      if (e.stackTrace != null && e.stackTrace != StackTrace.empty) {
        sb.writeln(e.stackTrace.toString());
      }
      sb.writeln();
    }
    return sb.toString().trimRight();
  }

  Future<void> _saveMemoryReindexTraceToFile(String content) async {
    final String text = content.trimRight();
    if (text.isEmpty) return;
    try {
      String? baseDirPath;
      try {
        baseDirPath = await FlutterLogger.getTodayLogsDir();
      } catch (_) {
        baseDirPath = null;
      }
      Directory baseDir = Directory.systemTemp;
      if (baseDirPath != null && baseDirPath.trim().isNotEmpty) {
        baseDir = Directory(baseDirPath.trim());
      }
      final String sep = Platform.pathSeparator;
      final Directory outDir = Directory(
        '${baseDir.path}${sep}ai_memory_reindex_logs',
      );
      await outDir.create(recursive: true);
      final File f = File(
        '${outDir.path}${sep}memory_reindex_${DateTime.now().millisecondsSinceEpoch}.log',
      );
      await f.writeAsString('$text\n', flush: true);
      try {
        await Clipboard.setData(ClipboardData(text: f.path));
      } catch (_) {}
      if (!mounted) return;
      UINotifier.success(context, '已保存到：${f.path}');
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, '保存失败：$e');
    }
  }

  Future<void> _showMemoryReindexLogsSheet({
    required List<TalkerData> traces,
    required String traceText,
  }) async {
    final String visible = traceText.trimRight();
    if (visible.trim().isEmpty) return;
    await AIRequestLogsSheet.show(
      context: context,
      title: 'AI 日志（memory 重建）',
      body: AIRequestLogsViewer.fromAiTraceTalker(
        logs: traces,
        scrollable: false,
        emptyText: '暂无日志',
        actions: <AIRequestLogsAction>[
          AIRequestLogsAction(
            label: '复制',
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: visible));
                if (!mounted) return;
                UINotifier.success(context, '已复制');
              } catch (_) {
                if (!mounted) return;
                UINotifier.error(context, '复制失败');
              }
            },
          ),
          AIRequestLogsAction(
            label: '保存到文件',
            onPressed: () => _saveMemoryReindexTraceToFile(visible),
          ),
        ],
      ),
    );
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

    final List<TalkerData> traces = _recentMemoryIndexAiTraceLogs(
      limit: 12,
      sinceMs: st?.startedAtMs,
    );
    final String traceText = traces.isEmpty
        ? ''
        : _buildAiTraceExportText(traces);

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
                        'AI 日志（memory 重建）',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  '最近 ${traces.length} 条 AITrace（已结构化，可在抽屉中展开查看）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing2),
                Wrap(
                  spacing: AppTheme.spacing2,
                  runSpacing: AppTheme.spacing2,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await Clipboard.setData(
                            ClipboardData(text: traceText),
                          );
                          if (!mounted) return;
                          UINotifier.success(context, '已复制');
                        } catch (_) {
                          if (!mounted) return;
                          UINotifier.error(context, '复制失败');
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('复制日志'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _showMemoryReindexLogsSheet(
                          traces: traces,
                          traceText: traceText,
                        );
                      },
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: const Text('查看日志'),
                    ),
                  ],
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
                  : () async {
                      await _index.startFullReindex();
                      await _loadProfile();
                      await _loadItems();
                    },
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
          toolbarHeight: 36,
          centerTitle: true,
          automaticallyImplyLeading: true,
          title: _buildMemoryProviderModelAppBarTitle(),
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

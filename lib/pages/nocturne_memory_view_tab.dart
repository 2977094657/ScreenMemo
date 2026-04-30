import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../constants/user_settings_keys.dart';
import '../services/nocturne_memory_service.dart';
import '../services/user_settings_service.dart';
import '../theme/app_theme.dart';

class NocturneMemoryViewTab extends StatefulWidget {
  const NocturneMemoryViewTab({super.key});

  @override
  State<NocturneMemoryViewTab> createState() => _NocturneMemoryViewTabState();
}

class _NocturneMemoryViewTabState extends State<NocturneMemoryViewTab>
    with AutomaticKeepAliveClientMixin {
  final NocturneMemoryService _mem = NocturneMemoryService.instance;

  final TextEditingController _uriCtrl = TextEditingController(text: 'core://');
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  bool _searching = false;
  String? _error;
  Map<String, dynamic>? _node;
  List<Map<String, dynamic>> _results = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _restoreLastUriOrOpenRoot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _uriCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _restoreLastUriOrOpenRoot() async {
    try {
      final String? last = await UserSettingsService.instance.getString(
        UserSettingKeys.nocturneMemoryLastUri,
      );
      final String u = (last ?? '').trim();
      if (u.isNotEmpty) {
        _uriCtrl.text = u;
      }
    } catch (_) {}
    await _openUri(_uriCtrl.text.trim().isEmpty ? 'core://' : _uriCtrl.text);
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _doSearch(_searchCtrl.text);
    });
  }

  Future<void> _openUri(String uri) async {
    final String u = uri.trim();
    if (u.isEmpty) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _node = null;
        _results = const <Map<String, dynamic>>[];
      });
    }
    try {
      final Map<String, dynamic> node = await _mem.readMemory(u);
      if (!mounted) return;
      setState(() {
        _node = node;
        _loading = false;
        _error = null;
      });
      try {
        await UserSettingsService.instance.setString(
          UserSettingKeys.nocturneMemoryLastUri,
          u,
        );
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _doSearch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _searching = false;
          _results = const <Map<String, dynamic>>[];
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _searching = true;
        _results = const <Map<String, dynamic>>[];
      });
    }
    try {
      final List<Map<String, dynamic>> rows = await _mem.searchMemory(
        q,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = rows;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = const <Map<String, dynamic>>[];
        _error = e.toString();
      });
    }
  }

  String? _parentUriOf(String uri) {
    try {
      final NocturneUri u = _mem.parseUri(uri);
      if (u.domain == 'system') return null;
      if (u.path.trim().isEmpty) return null;
      final String p = u.path.trim();
      final String parentPath = p.contains('/')
          ? p.split('/').sublist(0, p.split('/').length - 1).join('/')
          : '';
      return _mem.makeUri(u.domain, parentPath);
    } catch (_) {
      return null;
    }
  }

  String _rootUriOf(String uri) {
    try {
      final NocturneUri u = _mem.parseUri(uri);
      if (u.domain == 'system') return 'core://';
      return _mem.makeUri(u.domain, '');
    } catch (_) {
      return 'core://';
    }
  }

  Widget _buildBreadcrumbBar(BuildContext context, String uri) {
    try {
      final NocturneUri u = _mem.parseUri(uri);
      if (u.domain == 'system') return const SizedBox.shrink();
      final String domainRoot = _mem.makeUri(u.domain, '');
      final List<String> parts = u.path.trim().isEmpty
          ? const <String>[]
          : u.path.split('/');

      Widget chip(String label, VoidCallback onTap) {
        return ActionChip(
          label: Text(label),
          onPressed: onTap,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }

      final List<Widget> items = <Widget>[
        chip('${u.domain}://', () {
          _uriCtrl.text = domainRoot;
          _openUri(domainRoot);
        }),
      ];
      if (parts.isNotEmpty) {
        for (int i = 0; i < parts.length; i++) {
          final String seg = parts[i].trim();
          if (seg.isEmpty) continue;
          final String pathPrefix = parts.take(i + 1).join('/');
          final String target = _mem.makeUri(u.domain, pathPrefix);
          items.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 16),
            ),
          );
          items.add(
            chip(seg, () {
              _uriCtrl.text = target;
              _openUri(target);
            }),
          );
        }
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: items),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  static String _prettyJson(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    try {
      final dynamic v = jsonDecode(t);
      return const JsonEncoder.withIndent('  ').convert(v);
    } catch (_) {
      return t;
    }
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.colorScheme.outline.withOpacity(0.30);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _uriCtrl,
                textInputAction: TextInputAction.go,
                onSubmitted: (v) => _openUri(v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: AppLocalizations.of(context).memoryUriInputHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _loading ? null : () => _openUri(_uriCtrl.text),
              child: Text(AppLocalizations.of(context).actionOpen),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '根目录',
              onPressed: _loading
                  ? null
                  : () {
                      final String cur = (_node?['uri'] ?? _uriCtrl.text)
                          .toString();
                      final String root = _rootUriOf(cur);
                      _uriCtrl.text = root;
                      _openUri(root);
                    },
              icon: const Icon(Icons.home_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _scheduleSearch(),
                onSubmitted: (v) => _doSearch(v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: AppLocalizations.of(context).memorySearchHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '清空',
              onPressed: () {
                _searchCtrl.clear();
                _doSearch('');
              },
              icon: const Icon(Icons.clear, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context).noMatchingResults),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final r = _results[i];
        final String uri = (r['uri'] ?? '').toString();
        final String snippet = (r['content_snippet'] ?? '').toString();
        return ListTile(
          dense: true,
          title: Text(uri, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: snippet.trim().isEmpty
              ? null
              : Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            _uriCtrl.text = uri;
            _openUri(uri);
          },
        );
      },
    );
  }

  Widget _buildNodeView(BuildContext context) {
    final node = _node;
    if (node == null) {
      return const Center(child: Text('—'));
    }

    final String uri = (node['uri'] ?? '').toString();
    final String rootUri = _rootUriOf(uri);
    final String? content = node['content'] is String
        ? (node['content'] as String)
        : null;
    final List childrenRaw = (node['children'] is List)
        ? (node['children'] as List)
        : const [];
    final List<Map<String, dynamic>> children = childrenRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final String? parentUri = _parentUriOf(uri);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                uri,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                _uriCtrl.text = rootUri;
                _openUri(rootUri);
              },
              icon: const Icon(Icons.home_outlined, size: 16),
              label: Text(AppLocalizations.of(context).memoryRoot),
            ),
            if (parentUri != null)
              TextButton.icon(
                onPressed: () {
                  _uriCtrl.text = parentUri;
                  _openUri(parentUri);
                },
                icon: const Icon(Icons.arrow_upward, size: 16),
                label: Text(AppLocalizations.of(context).memoryParent),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _buildBreadcrumbBar(context, uri),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: () {
                _uriCtrl.text = 'system://boot';
                _openUri('system://boot');
              },
              child: Text(AppLocalizations.of(context).memoryBoot),
            ),
            OutlinedButton(
              onPressed: () {
                _uriCtrl.text = 'system://recent/20';
                _openUri('system://recent/20');
              },
              child: Text(AppLocalizations.of(context).memoryRecent),
            ),
            OutlinedButton(
              onPressed: () {
                _uriCtrl.text = 'system://index';
                _openUri('system://index');
              },
              child: Text(AppLocalizations.of(context).memoryIndex),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (content != null && content.trim().isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.24),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.20),
                width: 1,
              ),
            ),
            child: MarkdownBody(
              data: content,
              onTapLink: (text, href, title) async {
                if (href == null) return;
                final uri = Uri.tryParse(href);
                if (uri != null) {
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                }
              },
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Text(
            '（无内容）',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          '子节点（${children.length}）',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (children.isEmpty)
          Text(
            '（无子节点）',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...children.map((c) {
            final String childUri = (c['uri'] ?? '').toString();
            final String name = (c['name'] ?? '').toString();
            final String snippet = (c['content_snippet'] ?? '').toString();
            final int cc = (c['approx_children_count'] is num)
                ? (c['approx_children_count'] as num).toInt()
                : 0;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(name.isEmpty ? childUri : name),
              subtitle: snippet.trim().isEmpty
                  ? Text(childUri, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: cc > 0
                  ? Text(
                      '$cc',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              onTap: () {
                _uriCtrl.text = childUri;
                _openUri(childUri);
              },
            );
          }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        children: [
          _buildTopBar(context),
          const SizedBox(height: 12),
          if (_error != null && _error!.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withOpacity(0.60),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _prettyJson(_error!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (_searchCtrl.text.trim().isNotEmpty
                      ? _buildSearchResults(context)
                      : _buildNodeView(context)),
          ),
        ],
      ),
    );
  }
}

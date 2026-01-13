import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../services/memory_bridge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';

class MemoryRequestDebugPage extends StatefulWidget {
  const MemoryRequestDebugPage({super.key});

  @override
  State<MemoryRequestDebugPage> createState() => _MemoryRequestDebugPageState();
}

class _MemoryRequestDebugPageState extends State<MemoryRequestDebugPage> {
  final MemoryBridgeService _service = MemoryBridgeService.instance;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _debug;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? debug = await _service
          .getLastExtractionRequestDebug();
      if (!mounted) return;
      setState(() {
        _debug = debug;
        _loading = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? e.code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _copy(String text) async {
    final AppLocalizations t = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      UINotifier.success(context, t.copySuccess);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, '${t.copyFailed}: $e');
    }
  }

  String _prettyJson(Map<String, dynamic> map) {
    try {
      return const JsonEncoder.withIndent('  ').convert(map);
    } catch (_) {
      return map.toString();
    }
  }

  String _snippet(String text, {int max = 1200}) {
    if (text.length <= max) return text;
    final int cutoff = max > 20 ? max - 20 : max;
    return '${text.substring(0, cutoff)}\n...\n(已省略，全文长度=${text.length})';
  }

  Widget _buildKv(String label, Object? value) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '-',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSection({
    required String title,
    required String? content,
  }) {
    final ThemeData theme = Theme.of(context);
    final String text = (content ?? '').trim();
    final bool hasText = text.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  hasText ? '${text.length} chars' : 'empty',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            if (!hasText)
              Text(
                '-',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                child: Text(
                  _snippet(text),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const SizedBox(height: AppTheme.spacing3),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: hasText ? () => _copy(text) : null,
                  child: const Text('复制'),
                ),
                const SizedBox(width: AppTheme.spacing3),
                OutlinedButton(
                  onPressed: hasText
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _LargeTextViewerPage(
                                title: title,
                                text: text,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: const Text('查看全文'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, dynamic>? debug = _debug;

    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆请求调试'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '复制全部 JSON',
            onPressed:
                (debug == null || _loading) ? null : () => _copy(_prettyJson(debug)),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (debug == null && _error == null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacing6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '暂无记录，请先触发一次记忆解析请求。',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTheme.spacing4),
                        FilledButton.tonal(
                          onPressed: _refresh,
                          child: const Text('刷新'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  children: [
                    if (_error != null)
                      Card(
                        margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacing4),
                          child: Text(
                            '错误：$_error',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (debug != null) ...[
                      Card(
                        margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacing4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '概览',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacing3),
                              _buildKv('captured_at_ms', debug['captured_at_ms']),
                              _buildKv('provider_type', debug['provider_type']),
                              _buildKv('model', debug['model']),
                              _buildKv('stream', debug['stream']),
                              _buildKv('use_response_api', debug['use_response_api']),
                              _buildKv('url', debug['url']),
                              _buildKv('event_external_id', debug['event_external_id']),
                              _buildKv('event_type', debug['event_type']),
                              _buildKv('event_occurred_at', debug['event_occurred_at']),
                            ],
                          ),
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacing4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '长度统计（chars）',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacing3),
                              _buildKv(
                                'event_content_len',
                                debug['event_content_len'],
                              ),
                              _buildKv(
                                'metadata_json_len',
                                debug['metadata_json_len'],
                              ),
                              _buildKv(
                                'persona_summary_len',
                                debug['persona_summary_len'],
                              ),
                              _buildKv(
                                'persona_profile_json_len',
                                debug['persona_profile_json_len'],
                              ),
                              _buildKv(
                                'system_prompt_len',
                                debug['system_prompt_len'],
                              ),
                              _buildKv(
                                'user_prompt_len',
                                debug['user_prompt_len'],
                              ),
                              _buildKv(
                                'request_body_len',
                                debug['request_body_len'],
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildTextSection(
                        title: 'system_prompt',
                        content: debug['system_prompt'] as String?,
                      ),
                      _buildTextSection(
                        title: 'user_prompt',
                        content: debug['user_prompt'] as String?,
                      ),
                      _buildTextSection(
                        title: 'request_body',
                        content: debug['request_body'] as String?,
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _LargeTextViewerPage extends StatelessWidget {
  const _LargeTextViewerPage({required this.title, required this.text});

  final String title;
  final String text;

  Future<void> _copy(BuildContext context) async {
    final AppLocalizations t = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      UINotifier.success(context, t.copySuccess);
    } catch (e) {
      if (!context.mounted) return;
      UINotifier.error(context, '${t.copyFailed}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '复制',
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: SelectionArea(
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacing4),
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

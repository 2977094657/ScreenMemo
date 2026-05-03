import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:talker/talker.dart';

import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart' hide LogLevel;
import 'package:screen_memo/core/widgets/search_styles.dart';

enum _LogLevelFilter { all, debug, info, warn, error }

class LogConsolePage extends StatefulWidget {
  final String? title;
  final String? initialSearch;

  const LogConsolePage({super.key, this.title, this.initialSearch});

  @override
  State<LogConsolePage> createState() => _LogConsolePageState();
}

class _LogConsolePageState extends State<LogConsolePage> {
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<TalkerData>? _sub;
  _LogLevelFilter _filter = _LogLevelFilter.all;
  bool _reverse = true;

  @override
  void initState() {
    super.initState();
    final String initialSearch = (widget.initialSearch ?? '').trim();
    if (initialSearch.isNotEmpty) {
      _searchController.text = initialSearch;
    }
    _sub = FlutterLogger.talker.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<TalkerData> _getFilteredLogs() {
    final query = _searchController.text.trim().toLowerCase();
    final items = FlutterLogger.talker.history.where((e) {
      if (!_matchLevel(e)) return false;
      if (query.isEmpty) return true;
      final text = _toSearchText(e).toLowerCase();
      return text.contains(query);
    }).toList();
    return _reverse ? items.reversed.toList() : items;
  }

  bool _matchLevel(TalkerData data) {
    final level = data.logLevel;
    switch (_filter) {
      case _LogLevelFilter.all:
        return true;
      case _LogLevelFilter.debug:
        return level == LogLevel.debug || level == LogLevel.verbose;
      case _LogLevelFilter.info:
        return level == LogLevel.info;
      case _LogLevelFilter.warn:
        return level == LogLevel.warning;
      case _LogLevelFilter.error:
        return level == LogLevel.error || level == LogLevel.critical;
    }
  }

  String _toSearchText(TalkerData data) {
    return [
      data.title ?? '',
      data.message ?? '',
      data.exception?.toString() ?? '',
      data.error?.toString() ?? '',
      data.stackTrace?.toString() ?? '',
    ].join('\n');
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  String _levelLabel(BuildContext context, TalkerData data) {
    final l10n = AppLocalizations.of(context);
    final level = data.logLevel;
    if (level == LogLevel.critical) return l10n.logLevelCritical;
    if (level == LogLevel.error) return l10n.logLevelError;
    if (level == LogLevel.warning) return l10n.logLevelWarning;
    if (level == LogLevel.info) return l10n.logLevelInfo;
    if (level == LogLevel.verbose) return l10n.logLevelVerbose;
    return l10n.logLevelDebug;
  }

  Color _levelColor(TalkerData data, ColorScheme cs) {
    final level = data.logLevel;
    if (level == LogLevel.critical || level == LogLevel.error) return cs.error;
    if (level == LogLevel.warning) return cs.error;
    if (level == LogLevel.info) return cs.primary;
    return cs.onSurfaceVariant;
  }

  ({String? tag, String message}) _splitTag(String? raw) {
    final msg = raw ?? '';
    if (!msg.startsWith('[')) return (tag: null, message: msg);
    final end = msg.indexOf(']');
    if (end <= 1) return (tag: null, message: msg);
    final tag = msg.substring(1, end).trim();
    var rest = msg.substring(end + 1).trimLeft();
    return (tag: tag.isEmpty ? null : tag, message: rest);
  }

  String _buildExportText(BuildContext context, List<TalkerData> items) {
    final sb = StringBuffer();
    for (final e in items) {
      final sp = _splitTag(e.message);
      final tagText = sp.tag != null ? '[${sp.tag}] ' : '';
      sb.writeln(
        '${_formatTime(e.time)} [${_levelLabel(context, e)}] $tagText${sp.message}',
      );
      final ex = e.exception ?? e.error;
      if (ex != null) sb.writeln(ex.toString());
      if (e.stackTrace != null && e.stackTrace != StackTrace.empty) {
        sb.writeln(e.stackTrace.toString());
      }
      sb.writeln();
    }
    return sb.toString().trimRight();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copyOne(TalkerData e) async {
    try {
      final text = _buildExportText(context, [e]);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _toast(AppLocalizations.of(context).copySuccess);
    } catch (_) {
      if (mounted) _toast(AppLocalizations.of(context).copyFailed);
    }
  }

  Future<void> _showDetail(TalkerData e) async {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = _buildExportText(context, [e]).trimRight();
    final visible = text.isEmpty ? l10n.noContentParenthesized : text;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.logDetailTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SizedBox(
              width: double.maxFinite,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      visible,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: text.isEmpty ? null : () => _copyOne(e),
              child: Text(l10n.actionCopy),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.actionClose),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyAll() async {
    try {
      final text = _buildExportText(context, _getFilteredLogs());
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _toast(AppLocalizations.of(context).logCopiedToClipboard);
    } catch (_) {
      if (mounted) _toast(AppLocalizations.of(context).copyFailed);
    }
  }

  Future<void> _shareAll() async {
    try {
      final text = _buildExportText(context, _getFilteredLogs());
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'screenmemo_logs_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.txt';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(text, flush: true);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: AppLocalizations.of(context).logShareText);
    } catch (_) {
      if (mounted) _toast(AppLocalizations.of(context).logShareFailed);
    }
  }

  void _clear() {
    try {
      FlutterLogger.talker.cleanHistory();
      setState(() {});
      _toast(AppLocalizations.of(context).logCleared);
    } catch (_) {
      _toast(AppLocalizations.of(context).logClearFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _getFilteredLogs();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? l10n.logPanelTitle),
        actions: [
          PopupMenuButton<_LogLevelFilter>(
            tooltip: l10n.logFilterTooltip,
            initialValue: _filter,
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _LogLevelFilter.all,
                child: Text(l10n.logLevelAll),
              ),
              PopupMenuItem(
                value: _LogLevelFilter.debug,
                child: Text(l10n.logLevelDebugVerbose),
              ),
              PopupMenuItem(
                value: _LogLevelFilter.info,
                child: Text(l10n.logLevelInfo),
              ),
              PopupMenuItem(
                value: _LogLevelFilter.warn,
                child: Text(l10n.logLevelWarning),
              ),
              PopupMenuItem(
                value: _LogLevelFilter.error,
                child: Text(l10n.logLevelErrorSevere),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.filter_list),
            ),
          ),
          IconButton(
            tooltip: _reverse
                ? l10n.logSortNewestFirst
                : l10n.logSortOldestFirst,
            icon: Icon(_reverse ? Icons.south : Icons.north),
            onPressed: () => setState(() => _reverse = !_reverse),
          ),
          IconButton(
            tooltip: l10n.actionCopy,
            icon: const Icon(Icons.copy),
            onPressed: items.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: l10n.actionShare,
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: items.isEmpty ? null : _shareAll,
          ),
          IconButton(
            tooltip: l10n.actionClear,
            icon: const Icon(Icons.delete_outline),
            onPressed: FlutterLogger.talker.history.isEmpty ? null : _clear,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchTextField(
              controller: _searchController,
              hintText: l10n.logSearchHint,
              textInputAction: TextInputAction.search,
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.actionClear,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                FlutterLogger.talker.history.isEmpty
                    ? l10n.logNoLogs
                    : l10n.logNoMatchingLogs,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final e = items[index];
                final sp = _splitTag(e.message);
                final levelColor = _levelColor(e, cs);
                final title = sp.message.isEmpty ? (e.title ?? '') : sp.message;
                final subtitleParts = <String>[
                  _formatTime(e.time),
                  _levelLabel(context, e),
                  if (sp.tag != null) sp.tag!,
                ];
                final subtitle = subtitleParts.join(' · ');
                final extra = StringBuffer();
                final ex = e.exception ?? e.error;
                if (ex != null) extra.writeln(ex.toString());
                if (e.stackTrace != null && e.stackTrace != StackTrace.empty) {
                  extra.writeln(e.stackTrace.toString());
                }

                return Material(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showDetail(e),
                    onLongPress: () async {
                      await _copyOne(e);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(
                                  top: 4,
                                  right: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: levelColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.actionCopy,
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () => _copyOne(e),
                              ),
                            ],
                          ),
                          if (extra.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withOpacity(
                                  0.6,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                extra.toString().trimRight(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: items.length,
            ),
    );
  }
}

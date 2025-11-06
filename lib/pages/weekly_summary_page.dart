import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/weekly_summary_service.dart';
import '../theme/app_theme.dart';

class WeeklySummaryPage extends StatefulWidget {
  const WeeklySummaryPage({super.key, this.weekStart});

  final String? weekStart;

  @override
  State<WeeklySummaryPage> createState() => _WeeklySummaryPageState();
}

class _WeeklySummaryPageState extends State<WeeklySummaryPage> {
  final WeeklySummaryService _service = WeeklySummaryService.instance;

  List<Map<String, dynamic>> _weeks = <Map<String, dynamic>>[];
  Map<String, dynamic>? _current;
  Map<String, dynamic>? _structured;
  String? _selectedWeek;
  bool _listLoading = false;
  bool _detailLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWeeks(initialSelected: widget.weekStart);
  }

  Future<void> _loadWeeks({String? initialSelected}) async {
    setState(() => _listLoading = true);
    try {
      final weeks = await _service.listWeeklySummaries(onlyCompleted: true);
      setState(() => _weeks = weeks);
      if (weeks.isEmpty) {
        setState(() {
          _current = null;
          _structured = null;
          _selectedWeek = null;
        });
        return;
      }

      final String defaultWeek = initialSelected ?? (weeks.first['week_start_date'] as String? ?? '');
      if (defaultWeek.isNotEmpty) {
        await _loadDetail(defaultWeek);
      }
    } finally {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  Future<void> _loadDetail(String weekStart, {bool forceReloadList = false}) async {
    if (weekStart.isEmpty) return;
    setState(() {
      _detailLoading = true;
      _selectedWeek = weekStart;
    });
    try {
      final row = await _service.getWeeklySummaryByStart(weekStart);
      Map<String, dynamic>? structured;
      if (row != null) {
        final String? raw = row['structured_json'] as String?;
        if (raw != null && raw.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              structured = decoded;
            }
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _current = row;
          _structured = structured;
        });
      }
      if (forceReloadList) {
        await _loadWeeks(initialSelected: weekStart);
      }
    } finally {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  Future<void> _onRegenerate() async {
    final String? weekStart = _selectedWeek;
    if (weekStart == null || weekStart.isEmpty) return;
    setState(() => _detailLoading = true);
    try {
      await _service.generateForWeekStart(weekStart, force: true);
      await _loadDetail(weekStart, forceReloadList: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).generateSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).generateFailed)),
      );
    }
  }

  Future<void> _onCopy() async {
    final String? text = (_structured?['weekly_overview'] as String?) ?? (_current?['output_text'] as String?);
    if (text == null || text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copySuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool hasSelection = _current != null;
    final String titleRange = hasSelection
        ? _formatRange(
            _current?['week_start_date'] as String? ?? '',
            _current?['week_end_date'] as String? ?? '',
          )
        : l10n.weeklySummaryShort;
    final bool enablePicker = !_listLoading && _weeks.isNotEmpty;
    final theme = Theme.of(context);
    final Color titleColor = theme.appBarTheme.titleTextStyle?.color ?? theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: enablePicker ? _showWeekPicker : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      titleRange,
                      overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: (enablePicker ? titleColor : titleColor.withOpacity(0.35)),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.actionCopy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _current == null ? null : _onCopy,
          ),
          IconButton(
            tooltip: _current == null ? l10n.actionGenerate : l10n.actionRegenerate,
            icon: _detailLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_outlined),
            onPressed: (_current == null || _detailLoading) ? null : _onRegenerate,
          ),
        ],
      ),
      body: _listLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _weeks.isEmpty
              ? _buildEmptyPlaceholder(context)
              : RefreshIndicator(
                  onRefresh: () => _loadWeeks(initialSelected: _selectedWeek),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing4,
                      vertical: AppTheme.spacing3,
                    ),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (_detailLoading)
                        const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        ..._buildSummarySections(context),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyPlaceholder(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_view_week_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
            ),
            const SizedBox(height: AppTheme.spacing3),
            Text(
              l10n.weeklySummaryEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  void _showWeekPicker() {
    if (_weeks.isEmpty) return;

    final Map<int, List<_WeekOption>> grouped = <int, List<_WeekOption>>{};
    for (final Map<String, dynamic> row in _weeks) {
      final String start = (row['week_start_date'] as String? ?? '').trim();
      if (start.isEmpty) continue;
      final DateTime? parsed = DateTime.tryParse(start);
      if (parsed == null) continue;
      final String end = (row['week_end_date'] as String? ?? '').trim();
      grouped.putIfAbsent(parsed.year, () => <_WeekOption>[]).add(
            _WeekOption(
              year: parsed.year,
              startKey: start,
              endKey: end,
              label: _formatPickerLabel(start, end),
            ),
          );
    }
    if (grouped.isEmpty) return;

    final List<int> years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final int year in years) {
      grouped[year]!.sort((a, b) => b.startKey.compareTo(a.startKey));
    }

    int initialYearIndex = years.indexWhere((year) => grouped[year]!.any((option) => option.startKey == _selectedWeek));
    if (initialYearIndex < 0) initialYearIndex = 0;
    final List<_WeekOption> initialWeeks = grouped[years[initialYearIndex]]!;
    int initialWeekIndex = initialWeeks.indexWhere((option) => option.startKey == _selectedWeek);
    if (initialWeekIndex < 0) initialWeekIndex = 0;

    final FixedExtentScrollController yearController = FixedExtentScrollController(initialItem: initialYearIndex);
    final FixedExtentScrollController weekController = FixedExtentScrollController(initialItem: initialWeekIndex);

    int currentYearIndex = initialYearIndex;
    int currentWeekIndex = initialWeekIndex;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final List<_WeekOption> weekOptions = grouped[years[currentYearIndex]]!;
            if (currentWeekIndex >= weekOptions.length) {
              currentWeekIndex = weekOptions.isEmpty ? 0 : weekOptions.length - 1;
            }

            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusLg),
                  topRight: Radius.circular(AppTheme.radiusLg),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: AppTheme.spacing3, bottom: AppTheme.spacing2),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                      child: Text(
                        l10n.weeklySummarySelectWeek,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(
                      height: 220,
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: yearController,
                              itemExtent: 36,
                              magnification: 1.12,
                              squeeze: 1.08,
                              useMagnifier: true,
                              onSelectedItemChanged: (int index) {
                                final List<_WeekOption> nextOptions = grouped[years[index]]!;
                                setModalState(() {
                                  currentYearIndex = index;
                                  currentWeekIndex = 0;
                                });
                                Future.microtask(() {
                                  if (nextOptions.isNotEmpty) {
                                    try {
                                      weekController.jumpToItem(0);
                                    } catch (_) {}
                                  }
                                });
                              },
                              children: [
                                for (final int year in years)
                                  Center(
                                    child: Text(
                                      year.toString(),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: weekController,
                              itemExtent: 36,
                              magnification: 1.12,
                              squeeze: 1.05,
                              useMagnifier: true,
                              onSelectedItemChanged: (int index) {
                                setModalState(() {
                                  currentWeekIndex = index;
                                });
                              },
                              children: weekOptions.isEmpty
                                  ? [
                                      Center(
                                        child: Text(
                                          l10n.weeklySummaryEmpty,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ]
                                  : weekOptions
                                      .map(
                                        (option) => Center(
                                          child: Text(
                                            option.label,
                                            style: theme.textTheme.bodyMedium,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        AppTheme.spacing3,
                        AppTheme.spacing4,
                        AppTheme.spacing4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                ),
                              ),
                              child: Text(l10n.dialogCancel),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing3),
                          Expanded(
                            child: FilledButton(
                              onPressed: weekOptions.isEmpty
                                  ? null
                                  : () {
                                      final _WeekOption option = weekOptions[currentWeekIndex.clamp(0, weekOptions.length - 1)];
                                      Navigator.of(ctx).pop();
                                      if (mounted && option.startKey.isNotEmpty) {
                                        _loadDetail(option.startKey);
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                ),
                              ),
                              child: Text(l10n.dialogDone),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildSummarySections(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final List<Widget> sections = <Widget>[];

    void addSection(String title, Widget body) {
      sections.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTheme.spacing2),
            body,
            const SizedBox(height: AppTheme.spacing4),
          ],
        ),
      );
    }

    final String overview = (_structured?['weekly_overview'] as String?) ?? (_current?['output_text'] as String?) ?? '';
    if (overview.trim().isEmpty) {
      addSection(
        l10n.weeklySummaryOverviewTitle,
        Text(l10n.weeklySummaryNoContent, style: theme.textTheme.bodyMedium),
      );
    } else {
      addSection(
        l10n.weeklySummaryOverviewTitle,
        MarkdownBody(
          data: overview,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final List<dynamic>? dailyBreakdowns = _structured?['daily_breakdowns'] as List<dynamic>?;
    if (dailyBreakdowns == null || dailyBreakdowns.isEmpty) {
      addSection(
        l10n.weeklySummaryDailyTitle,
        Text(l10n.weeklySummaryNoContent, style: theme.textTheme.bodyMedium),
      );
    } else {
      addSection(
        l10n.weeklySummaryDailyTitle,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: dailyBreakdowns.map((item) {
            if (item is! Map) return const SizedBox.shrink();
            final String dateKey = item['date_key'] as String? ?? '';
            final String headline = item['headline'] as String? ?? '';
            final List<dynamic> highlights = item['highlights'] as List<dynamic>? ?? const <dynamic>[];

            final List<Widget> highlightWidgets = highlights
                .whereType<String>()
                .map((text) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(text)),
                        ],
                      ),
                    ))
                .toList();

            if (highlightWidgets.isEmpty) {
              highlightWidgets.add(Text(l10n.weeklySummaryNoContent, style: theme.textTheme.bodyMedium));
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$dateKey  ${headline.trim().isEmpty ? '' : '· $headline'}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  ...highlightWidgets,
                ],
              ),
            );
          }).whereType<Widget>().toList(),
        ),
      );
    }

    final List<dynamic>? actionItems = _structured?['action_items'] as List<dynamic>?;
    if (actionItems == null || actionItems.isEmpty) {
      addSection(
        l10n.weeklySummaryActionsTitle,
        Text(l10n.weeklySummaryNoContent, style: theme.textTheme.bodyMedium),
      );
    } else {
      addSection(
        l10n.weeklySummaryActionsTitle,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: actionItems
              .whereType<String>()
              .map((text) => Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(text)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      );
    }

    return sections;
  }

  String _formatRange(String start, String end) {
    if (start.isEmpty && end.isEmpty) return '';
    if (start.isEmpty) return end;
    if (end.isEmpty) return start;
    return '$start ~ $end';
  }

  String _formatPickerLabel(String start, String end) {
    DateTime? startDate = DateTime.tryParse(start);
    DateTime? endDate = DateTime.tryParse(end);
    if (startDate == null) {
      return _formatRange(start, end);
    }
    final DateFormat formatter = DateFormat('MM/dd');
    final String startLabel = formatter.format(startDate);
    if (endDate == null || end.isEmpty) {
      return startLabel;
    }
    final String endLabel = formatter.format(endDate);
    if (startLabel == endLabel) {
      return startLabel;
    }
    return '$startLabel ~ $endLabel';
  }
}

class _WeekOption {
  const _WeekOption({
    required this.year,
    required this.startKey,
    required this.endKey,
    required this.label,
  });

  final int year;
  final String startKey;
  final String endKey;
  final String label;
}


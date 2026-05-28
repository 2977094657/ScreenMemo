import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_action_menu.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

class DateJumpDayInfo {
  final String dayKey;
  final int count;

  const DateJumpDayInfo({required this.dayKey, required this.count});
}

class DateJumpDaySelection {
  final String dateKey;
  final int count;

  const DateJumpDaySelection({required this.dateKey, required this.count});
}

class DateJumpCalendarMonthSheet extends StatefulWidget {
  const DateJumpCalendarMonthSheet({
    super.key,
    required this.initialDate,
    required this.selectedDateKey,
    required this.scrollController,
    required this.loadMonthDayCounts,
    this.loadAvailableYears,
    this.title,
  });

  final DateTime initialDate;
  final String? selectedDateKey;
  final ScrollController scrollController;
  final Future<List<int>> Function()? loadAvailableYears;
  final Future<List<DateJumpDayInfo>> Function(int year, int month)
  loadMonthDayCounts;
  final String? title;

  @override
  State<DateJumpCalendarMonthSheet> createState() =>
      _DateJumpCalendarMonthSheetState();
}

class _DateJumpCalendarMonthSheetState
    extends State<DateJumpCalendarMonthSheet> {
  late int _year;
  late int _month;
  List<int> _yearOptions = const <int>[];
  Map<String, int> _countsByKey = const <String, int>{};
  bool _loading = false;
  bool _loadingYears = false;
  bool _loadedAvailableYears = false;
  String? _error;
  int _loadTicket = 0;
  int _yearLoadTicket = 0;

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _yearOptions = _normalizeYearOptions(<int>[_year]);
    unawaited(_loadAvailableYears());
    unawaited(_loadMonthCounts());
  }

  List<int> _normalizeYearOptions(Iterable<int> years) {
    final Set<int> values = <int>{
      for (final int year in years)
        if (year > 0) year,
      if (_year > 0) _year,
    };
    final List<int> sorted = values.toList();
    sorted.sort((int a, int b) => b.compareTo(a));
    return sorted;
  }

  List<int> _yearOptionsForCurrentValue() {
    if (_yearOptions.contains(_year)) return _yearOptions;
    return _normalizeYearOptions(<int>[..._yearOptions, _year]);
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _dateKeyForDay(int day) =>
      '${_year.toString().padLeft(4, '0')}-${_two(_month)}-${_two(day)}';

  Future<void> _loadAvailableYears() async {
    final Future<List<int>> Function()? loader = widget.loadAvailableYears;
    if (loader == null) return;
    final int ticket = ++_yearLoadTicket;
    setState(() => _loadingYears = true);
    try {
      final List<int> years = await loader();
      if (!mounted || ticket != _yearLoadTicket) return;
      setState(() {
        _yearOptions = _normalizeYearOptions(years);
        _loadingYears = false;
        _loadedAvailableYears = true;
      });
    } catch (_) {
      if (!mounted || ticket != _yearLoadTicket) return;
      setState(() => _loadingYears = false);
    }
  }

  Future<void> _loadMonthCounts() async {
    final int ticket = ++_loadTicket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<DateJumpDayInfo> days = await widget.loadMonthDayCounts(
        _year,
        _month,
      );
      if (!mounted || ticket != _loadTicket) return;
      setState(() {
        _countsByKey = <String, int>{
          for (final DateJumpDayInfo info in days) info.dayKey: info.count,
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted || ticket != _loadTicket) return;
      setState(() {
        _countsByKey = const <String, int>{};
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _setYearMonth(int year, int month) {
    final DateTime normalized = DateTime(year, month);
    setState(() {
      _year = normalized.year;
      _month = normalized.month;
      _countsByKey = const <String, int>{};
    });
    unawaited(_loadMonthCounts());
  }

  bool _canChangeMonth(int delta) {
    if (!_loadedAvailableYears) return true;
    final DateTime normalized = DateTime(_year, _month + delta);
    return _yearOptions.contains(normalized.year);
  }

  void _changeMonth(int delta) {
    if (!_canChangeMonth(delta)) return;
    _setYearMonth(_year, _month + delta);
  }

  Widget _buildPickerButton({
    required String label,
    required int selectedValue,
    required List<UIActionMenuItem<int>> items,
    required ValueChanged<int> onSelected,
    required double minWidth,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return UIActionMenuButton<int>(
      tooltip: label,
      selectedValue: selectedValue,
      items: items,
      onSelected: onSelected,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 6),
      minWidth: minWidth,
      maxWidth: math.max(minWidth, 180),
      child: Container(
        height: 34,
        constraints: BoxConstraints(minWidth: minWidth),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacing3),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title ?? l10n.dateJumpTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_loading || _loadingYears)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing3),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing1,
          ),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.dateJumpPreviousMonth,
                icon: const Icon(Icons.chevron_left),
                onPressed: _canChangeMonth(-1) ? () => _changeMonth(-1) : null,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: _buildPickerButton(
                        label: '$_year',
                        selectedValue: _year,
                        minWidth: 88,
                        items: <UIActionMenuItem<int>>[
                          for (final int year in _yearOptionsForCurrentValue())
                            UIActionMenuItem<int>(value: year, label: '$year'),
                        ],
                        onSelected: (int value) {
                          if (value == _year) return;
                          _setYearMonth(value, _month);
                        },
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing2),
                    _buildPickerButton(
                      label: '$_month',
                      selectedValue: _month,
                      minWidth: 64,
                      items: <UIActionMenuItem<int>>[
                        for (int month = 1; month <= 12; month += 1)
                          UIActionMenuItem<int>(value: month, label: '$month'),
                      ],
                      onSelected: (int value) {
                        if (value == _month) return;
                        _setYearMonth(_year, value);
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.dateJumpNextMonth,
                icon: const Icon(Icons.chevron_right),
                onPressed: _canChangeMonth(1) ? () => _changeMonth(1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> labels = <String>[
      l10n.dateJumpWeekdayMon,
      l10n.dateJumpWeekdayTue,
      l10n.dateJumpWeekdayWed,
      l10n.dateJumpWeekdayThu,
      l10n.dateJumpWeekdayFri,
      l10n.dateJumpWeekdaySat,
      l10n.dateJumpWeekdaySun,
    ];
    return Row(
      children: [
        for (final String label in labels)
          Expanded(
            child: Center(child: Text(label, style: style)),
          ),
      ],
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int daysInMonth = DateTime(_year, _month + 1, 0).day;
    final int leadingEmptyCells = DateTime(_year, _month, 1).weekday - 1;
    final int rawCellCount = leadingEmptyCells + daysInMonth;
    final int cellCount = ((rawCellCount + 6) ~/ 7) * 7;
    final DateTime today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cellCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.88,
      ),
      itemBuilder: (context, index) {
        final int day = index - leadingEmptyCells + 1;
        if (day < 1 || day > daysInMonth) {
          return const SizedBox.shrink();
        }
        final String dateKey = _dateKeyForDay(day);
        final int count = _countsByKey[dateKey] ?? 0;
        final bool enabled = count > 0;
        final bool selected = widget.selectedDateKey == dateKey;
        final bool isToday =
            today.year == _year && today.month == _month && today.day == day;
        final Color accent = selected ? cs.primary : cs.onSurface;
        final Color background = selected
            ? cs.primaryContainer.withValues(alpha: 0.72)
            : enabled
            ? cs.surfaceContainerHighest.withValues(alpha: 0.36)
            : cs.surfaceContainerHighest.withValues(alpha: 0.16);
        final Color borderColor = selected
            ? cs.primary.withValues(alpha: 0.65)
            : isToday
            ? cs.tertiary.withValues(alpha: 0.5)
            : cs.outline.withValues(alpha: 0.12);
        return Material(
          key: ValueKey<String>('date-jump-calendar-day-$dateKey'),
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    Navigator.of(
                      context,
                    ).pop(DateJumpDaySelection(dateKey: dateKey, count: count));
                  }
                : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: enabled
                          ? accent
                          : cs.onSurfaceVariant.withValues(alpha: 0.58),
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: enabled
                          ? cs.onSurfaceVariant
                          : cs.onSurfaceVariant.withValues(alpha: 0.45),
                      fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing4,
        AppTheme.spacing3,
        AppTheme.spacing4,
        AppTheme.spacing5,
      ),
      children: [
        _buildHeader(context),
        const SizedBox(height: AppTheme.spacing4),
        _buildWeekHeader(context),
        const SizedBox(height: AppTheme.spacing2),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              l10n.dateJumpLoadFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          _buildCalendarGrid(context),
      ],
    );
  }
}

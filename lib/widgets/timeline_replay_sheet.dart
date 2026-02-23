import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';

import '../l10n/app_localizations.dart';
import '../services/replay_export_service.dart';
import '../services/screenshot_service.dart';
import '../theme/app_theme.dart';
import 'ui_components.dart';

class TimelineReplaySheet extends StatefulWidget {
  const TimelineReplaySheet({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.dayStart,
    required this.dayEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;
  final DateTime dayStart;
  final DateTime dayEnd;

  static Future<void> show({
    required BuildContext context,
    required DateTime initialStart,
    required DateTime initialEnd,
    required DateTime dayStart,
    required DateTime dayEnd,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return TimelineReplaySheet(
          initialStart: initialStart,
          initialEnd: initialEnd,
          dayStart: dayStart,
          dayEnd: dayEnd,
        );
      },
    );
  }

  @override
  State<TimelineReplaySheet> createState() => _TimelineReplaySheetState();
}

class _TimelineReplaySheetState extends State<TimelineReplaySheet> {
  late DateTime _start;
  late DateTime _end;

  static const int _defaultFps = 24;
  late final TextEditingController _fpsController;
  bool _overlayEnabled = true;
  bool _appProgressBarEnabled = true;
  ReplayAppProgressBarPosition _appProgressBarPosition =
      ReplayAppProgressBarPosition.right;
  ReplayNsfwMode _nsfwMode = ReplayNsfwMode.mask;

  int? _screenshotCount;
  int _countToken = 0;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _fpsController = TextEditingController(text: _defaultFps.toString());
    // ignore: discarded_futures
    _refreshScreenshotCount();
  }

  @override
  void dispose() {
    _fpsController.dispose();
    super.dispose();
  }

  String _fmt(DateTime dt) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return dt.toIso8601String();
    }
  }

  Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime initial,
  ) async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(2000);
    final DateTime lastDate = DateTime(now.year + 10, 12, 31, 23, 59);
    final DateTime? picked = await showOmniDateTimePicker(
      context: context,
      initialDate: initial.isAfter(lastDate) ? lastDate : initial,
      firstDate: firstDate,
      lastDate: lastDate,
      is24HourMode: true,
      isShowSeconds: false,
      minutesInterval: 1,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      constraints: const BoxConstraints(maxWidth: 420),
    );
    return picked;
  }

  bool get _invalidRange => _end.isBefore(_start);

  int? _parseFps() {
    final String raw = _fpsController.text.trim();
    if (raw.isEmpty) return null;
    final int? v = int.tryParse(raw);
    if (v == null) return null;
    if (v < 1 || v > 120) return null;
    return v;
  }

  Future<void> _refreshScreenshotCount() async {
    final int token = ++_countToken;
    final int startMillis = _start.millisecondsSinceEpoch;
    final int endMillis = _end.millisecondsSinceEpoch;
    if (endMillis < startMillis) {
      if (!mounted) return;
      setState(() => _screenshotCount = null);
      return;
    }

    final int count = await ScreenshotService.instance
        .getGlobalScreenshotCountBetween(
          startMillis: startMillis,
          endMillis: endMillis,
        );
    if (!mounted || token != _countToken) return;
    setState(() => _screenshotCount = count);
  }

  Future<void> _runCompose() async {
    final l10n = AppLocalizations.of(context);
    final int? fps = _parseFps();
    if (fps == null) {
      UINotifier.error(
        context,
        l10n.timelineReplayFpsInvalid,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    if (_invalidRange) {
      UINotifier.error(
        context,
        l10n.timelineReplayFailed,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    Navigator.of(context).pop();

    try {
      await ReplayExportService.instance.composeReplay(
        start: _start,
        end: _end,
        options: ReplayOptions(
          fps: fps,
          shortSide: 0,
          quality: ReplayQuality.high,
          overlayEnabled: _overlayEnabled,
          appProgressBarEnabled: _appProgressBarEnabled,
          appProgressBarPosition: _appProgressBarPosition,
          nsfwMode: _nsfwMode,
          saveToGallery: true,
          openGalleryAfterSave: false,
        ),
      );
    } catch (_) {
      // Service already shows toasts; ignore.
    }
  }

  Widget _buildDateRow({
    required String title,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing3,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fmt(value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final int? fps = _parseFps();
    final bool fpsValid = fps != null;
    final int effectiveFps = fpsValid ? fps : _defaultFps;

    final int? screenshotCount = _screenshotCount;
    final int maxFrames = ReplayExportService.maxFrames;
    final int? usedFrames = screenshotCount == null
        ? null
        : (screenshotCount > maxFrames ? maxFrames : screenshotCount);
    final double? estimatedVideoMinutes = usedFrames == null
        ? null
        : (usedFrames / effectiveFps) / 60.0;
    final String? estimatedVideoMinutesText = estimatedVideoMinutes == null
        ? null
        : (estimatedVideoMinutes >= 10
              ? estimatedVideoMinutes.toStringAsFixed(0)
              : estimatedVideoMinutes.toStringAsFixed(1));

    final bool canGenerate = !_invalidRange && fpsValid;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext sheetCtx, ScrollController ctrl) {
        return UISheetSurface(
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacing4,
              AppTheme.spacing3,
              AppTheme.spacing4,
              AppTheme.spacing6,
            ),
            children: [
              const Center(child: UISheetHandle()),
              const SizedBox(height: AppTheme.spacing3),
              Center(
                child: Text(
                  l10n.timelineReplayGenerate,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacing4),

              _buildDateRow(
                title: l10n.timelineReplayStartTime,
                value: _start,
                onTap: () async {
                  final picked = await _pickDateTime(context, _start);
                  if (picked == null) return;
                  if (!mounted) return;
                  setState(() {
                    _start = picked;
                    if (_end.isBefore(_start)) _end = _start;
                  });
                  // ignore: discarded_futures
                  _refreshScreenshotCount();
                },
              ),
              const SizedBox(height: AppTheme.spacing2),
              _buildDateRow(
                title: l10n.timelineReplayEndTime,
                value: _end,
                onTap: () async {
                  final picked = await _pickDateTime(context, _end);
                  if (picked == null) return;
                  if (!mounted) return;
                  setState(() {
                    _end = picked;
                    if (_end.isBefore(_start)) _start = _end;
                  });
                  // ignore: discarded_futures
                  _refreshScreenshotCount();
                },
              ),

              const SizedBox(height: AppTheme.spacing2),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _start = widget.dayStart;
                        _end = widget.dayEnd;
                      });
                      // ignore: discarded_futures
                      _refreshScreenshotCount();
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(l10n.timelineReplayUseSelectedDay),
                  ),
                  const SizedBox(width: AppTheme.spacing2),
                  Expanded(
                    child: Text(
                      screenshotCount == null
                          ? '${effectiveFps}fps · 计算中…'
                          : '${effectiveFps}fps · $screenshotCount张 · 预计≈$estimatedVideoMinutesText分钟'
                                '${screenshotCount > maxFrames ? '（将抽样至$maxFrames张）' : ''}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacing2),
              Row(
                children: [
                  Expanded(
                    child: _LabeledNumberField(
                      label: l10n.timelineReplayFps,
                      controller: _fpsController,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (!fpsValid)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacing2),
                  child: Text(
                    l10n.timelineReplayFpsInvalid,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ),

              const SizedBox(height: AppTheme.spacing3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.timelineReplayOverlay,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: _overlayEnabled,
                    onChanged: (v) => setState(() => _overlayEnabled = v),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing1),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.timelineReplayAppProgressBar,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: _appProgressBarEnabled,
                    onChanged: (v) =>
                        setState(() => _appProgressBarEnabled = v),
                  ),
                ],
              ),
              if (_appProgressBarEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacing1),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double segmentWidth =
                          (constraints.maxWidth - AppTheme.spacing2) / 4;
                      final TextStyle? baseStyle = theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600);

                      Widget segmentLabel(
                        String text,
                        ReplayAppProgressBarPosition position,
                      ) {
                        final bool selected =
                            _appProgressBarPosition == position;
                        return SizedBox(
                          width: segmentWidth,
                          child: Center(
                            child: Text(
                              text,
                              style: baseStyle?.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: selected
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      }

                      return CupertinoSlidingSegmentedControl<
                        ReplayAppProgressBarPosition
                      >(
                        groupValue: _appProgressBarPosition,
                        backgroundColor: cs.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        thumbColor: cs.surface,
                        padding: const EdgeInsets.all(AppTheme.spacing1),
                        children: <ReplayAppProgressBarPosition, Widget>{
                          ReplayAppProgressBarPosition.top: segmentLabel(
                            '顶部',
                            ReplayAppProgressBarPosition.top,
                          ),
                          ReplayAppProgressBarPosition.right: segmentLabel(
                            '右侧',
                            ReplayAppProgressBarPosition.right,
                          ),
                          ReplayAppProgressBarPosition.bottom: segmentLabel(
                            '底部',
                            ReplayAppProgressBarPosition.bottom,
                          ),
                          ReplayAppProgressBarPosition.left: segmentLabel(
                            '左侧',
                            ReplayAppProgressBarPosition.left,
                          ),
                        },
                        onValueChanged: (value) {
                          if (value == null) return;
                          setState(() => _appProgressBarPosition = value);
                        },
                      );
                    },
                  ),
                ),

              const SizedBox(height: AppTheme.spacing3),
              Text(
                l10n.timelineReplayNsfw,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTheme.spacing1),
              LayoutBuilder(
                builder: (context, constraints) {
                  final double segmentWidth =
                      (constraints.maxWidth - AppTheme.spacing2) / 3;
                  final TextStyle? baseStyle = theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600);

                  Widget segmentLabel(String text, ReplayNsfwMode mode) {
                    final bool selected = _nsfwMode == mode;
                    return SizedBox(
                      width: segmentWidth,
                      child: Center(
                        child: Text(
                          text,
                          style: baseStyle?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: selected
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }

                  return CupertinoSlidingSegmentedControl<ReplayNsfwMode>(
                    groupValue: _nsfwMode,
                    backgroundColor: cs.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    thumbColor: cs.surface,
                    padding: const EdgeInsets.all(AppTheme.spacing1),
                    children: <ReplayNsfwMode, Widget>{
                      ReplayNsfwMode.mask: segmentLabel(
                        l10n.timelineReplayNsfwMask,
                        ReplayNsfwMode.mask,
                      ),
                      ReplayNsfwMode.show: segmentLabel(
                        l10n.timelineReplayNsfwShow,
                        ReplayNsfwMode.show,
                      ),
                      ReplayNsfwMode.hide: segmentLabel(
                        l10n.timelineReplayNsfwHide,
                        ReplayNsfwMode.hide,
                      ),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(() => _nsfwMode = value);
                    },
                  );
                },
              ),

              const SizedBox(height: AppTheme.spacing4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing2),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canGenerate ? _runCompose : null,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l10n.timelineReplayGenerate),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LabeledNumberField extends StatelessWidget {
  const _LabeledNumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          SizedBox(
            width: 44,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.end,
              maxLines: 1,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

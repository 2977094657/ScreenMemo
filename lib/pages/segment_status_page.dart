import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:talker/talker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ai_request_log.dart';
import '../models/app_info.dart';
import '../models/screenshot_record.dart';
import '../services/ai_providers_service.dart';
import '../services/ai_settings_service.dart';
import '../services/app_selection_service.dart';
import '../services/dynamic_entry_perf_service.dart';
import '../services/flutter_logger.dart';
import '../services/screenshot_database.dart';
import '../services/user_settings_service.dart';
import '../theme/app_theme.dart';
import '../constants/user_settings_keys.dart';
import '../utils/native_ai_request_log_parser.dart';
import '../utils/merged_event_summary.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/ai_request_logs_action.dart';
import '../widgets/ai_request_logs_viewer.dart';
import '../widgets/ai_request_logs_sheet.dart';
import '../widgets/screenshot_image_widget.dart';
import '../widgets/screenshot_style_tab_bar.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import 'daily_summary_page.dart';

String _normalizeMarkdownForUi(String input) {
  if (input.trim().isEmpty) return input;

  final String pre = input
      .replaceAll('\\r\\n', '\n')
      .replaceAll('\\r', '\n')
      .replaceAll('\\n', '\n')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\\"', '"');

  final List<String> lines = pre.split('\n');
  final List<String> out = <String>[];
  bool lastWasBlank = true;
  final RegExp headingRe = RegExp(r'^\s{0,3}#{1,6}\s+');
  final RegExp headingMissingSpaceRe = RegExp(
    r'^(\s{0,3}#{1,6})(?![#\s])(.+)$',
  );
  final RegExp boldSubtitleRe = RegExp(r'^\s*\*\*[^*\n]+\*\*[:：]');
  final RegExp listStartRe = RegExp(r'^\s*-\s+');
  final RegExp listMissingSpaceRe = RegExp(r'^(\s*-)(?![-\s])(.+)$');

  for (int i = 0; i < lines.length; i++) {
    String line = lines[i];
    String trimmed = line.trimRight();

    final Match? headingMissingSpace = headingMissingSpaceRe.firstMatch(
      trimmed,
    );
    if (headingMissingSpace != null) {
      line =
          '${headingMissingSpace.group(1)} ${headingMissingSpace.group(2)!.trimLeft()}';
      trimmed = line.trimRight();
    }

    final Match? listMissingSpace = listMissingSpaceRe.firstMatch(trimmed);
    if (listMissingSpace != null) {
      line =
          '${listMissingSpace.group(1)} ${listMissingSpace.group(2)!.trimLeft()}';
      trimmed = line.trimRight();
    }

    final bool isHeading = headingRe.hasMatch(trimmed);
    final bool isBoldSubtitle = boldSubtitleRe.hasMatch(trimmed);
    final bool isListStart = listStartRe.hasMatch(trimmed);

    if ((isHeading || isBoldSubtitle || isListStart) &&
        !lastWasBlank &&
        out.isNotEmpty &&
        out.last.trim().isNotEmpty) {
      out.add('');
      lastWasBlank = true;
    }

    out.add(line);

    if (isHeading) {
      final String? next = i + 1 < lines.length ? lines[i + 1] : null;
      if (next != null && next.trim().isNotEmpty) {
        out.add('');
        lastWasBlank = true;
        continue;
      }
    }

    lastWasBlank = line.trim().isEmpty;
  }

  final List<String> normalized = <String>[];
  for (final String line in out) {
    if (line.trim().isEmpty) {
      if (normalized.isEmpty || normalized.last.trim().isEmpty) {
        if (normalized.isEmpty) normalized.add('');
      } else {
        normalized.add('');
      }
    } else {
      normalized.add(line);
    }
  }

  return normalized.join('\n');
}

/// 段落事件状态页
/// - 显示进行中的事件（collecting）
/// - 列出最近事件及其样本与AI结果摘要
class SegmentStatusPage extends StatefulWidget {
  const SegmentStatusPage({super.key});

  @override
  State<SegmentStatusPage> createState() => _SegmentStatusPageState();
}

class _DynamicRebuildUiSnapshot {
  const _DynamicRebuildUiSnapshot({
    required this.status,
    required this.starting,
    required this.stopping,
    required this.selectedDayConcurrency,
    required this.savingDayConcurrency,
    required this.autoRepairEnabled,
    required this.autoRepairLoading,
    required this.autoRepairToggling,
    required this.requestLogs,
  });

  final DynamicRebuildTaskStatus status;
  final bool starting;
  final bool stopping;
  final int selectedDayConcurrency;
  final bool savingDayConcurrency;
  final bool autoRepairEnabled;
  final bool autoRepairLoading;
  final bool autoRepairToggling;
  final _DynamicRebuildRequestLogsState requestLogs;
}

class _DynamicRebuildRequestLogsState {
  const _DynamicRebuildRequestLogsState({
    this.loading = false,
    this.traces = const <AIRequestTrace>[],
    this.rawText = '',
    this.error,
  });

  final bool loading;
  final List<AIRequestTrace> traces;
  final String rawText;
  final String? error;

  bool get hasAny => traces.isNotEmpty || rawText.trim().isNotEmpty;

  _DynamicRebuildRequestLogsState copyWith({
    bool? loading,
    List<AIRequestTrace>? traces,
    String? rawText,
    Object? error = _dynamicRebuildRequestLogsNoChange,
  }) {
    return _DynamicRebuildRequestLogsState(
      loading: loading ?? this.loading,
      traces: traces ?? this.traces,
      rawText: rawText ?? this.rawText,
      error: identical(error, _dynamicRebuildRequestLogsNoChange)
          ? this.error
          : error as String?,
    );
  }
}

const Object _dynamicRebuildRequestLogsNoChange = Object();

bool _sameDynamicRebuildRequestLogsState(
  _DynamicRebuildRequestLogsState a,
  _DynamicRebuildRequestLogsState b,
) {
  return a.loading == b.loading && a.error == b.error && a.rawText == b.rawText;
}

class _SegmentStatusPageState extends State<SegmentStatusPage>
    with SingleTickerProviderStateMixin {
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  static const bool _dynamicRebuildRequestLogsEnabled = false;
  static const int _dynamicRebuildRequestLogsDisplayLimit = 10;
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _segments = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _startingDynamicRebuild = false;
  bool _stoppingDynamicRebuild = false;
  int _selectedDynamicRebuildDayConcurrency = 1;
  bool _savingDynamicRebuildDayConcurrency = false;
  bool _onlyNoSummary = false; // 仅看暂无AI总结
  String? _selectedDateKey;
  DynamicRebuildTaskStatus _dynamicRebuildTaskStatus =
      const DynamicRebuildTaskStatus(
        taskId: '',
        status: 'idle',
        startedAt: 0,
        updatedAt: 0,
        completedAt: 0,
        dayConcurrency: 1,
        totalSegments: 0,
        processedSegments: 0,
        failedSegments: 0,
        totalDays: 0,
        completedDays: 0,
        pendingDays: 0,
        failedDays: 0,
        currentDayKey: '',
        timelineCutoffDayKey: '',
        currentSegmentId: 0,
        currentRangeLabel: '',
        currentStage: '',
        currentStageLabel: '',
        currentStageDetail: '',
        lastError: null,
        isActive: false,
        progressPercent: '0%',
        aiModel: '',
        recentLogs: <String>[],
        workers: <DynamicRebuildWorkerState>[],
      );
  Timer? _dynamicRebuildTaskPollTimer;
  bool _pollingDynamicRebuildTask = false;
  int _lastDynamicRebuildListRefreshAt = 0;
  late final ValueNotifier<_DynamicRebuildUiSnapshot>
  _dynamicRebuildUiSnapshotNotifier;
  late final AnimationController _dynamicRebuildIconController;
  _DynamicRebuildRequestLogsState _dynamicRebuildRequestLogsState =
      const _DynamicRebuildRequestLogsState();
  bool _dynamicRebuildTaskSheetOpen = false;
  int _lastDynamicRebuildRequestLogsRefreshAt = 0;
  int _dynamicRebuildRequestLogsLoadTicket = 0;
  bool _dynamicAutoRepairEnabled = true;
  bool _loadingDynamicAutoRepair = false;
  bool _togglingDynamicAutoRepair = false;
  bool _trackEntryPerf = true;
  int _entryPerfPendingLoads = 0;
  bool _entryPerfShellFrameSeen = false;

  // 底部弹窗查询输入持久化，避免失焦或重建清空
  String _segProviderQueryText = '';
  String _segModelQueryText = '';

  // —— 基于提供商表的“动态(segments)”上下文（与对话隔离） ——
  AIProvider? _ctxSegProvider;
  String? _ctxSegModel;

  // 应用图标缓存（包名 -> AppInfo）
  final Map<String, AppInfo> _appInfoByPackage = <String, AppInfo>{};

  // 隐私模式状态
  bool _privacyMode = true; // 默认开启，初始化时从偏好读取
  bool _dynamicEntryLogIconEnabled = false;

  // 自动轮询：每秒检测"暂无总结"并自动刷新，直到清空
  Timer? _autoTimer;
  bool _autoWatching = false;

  // 日期 Tab 批次控制：默认加载最近 30 个“有数据的日期”，向前按批次追加。
  static const int _initialDayTabs = 30;
  static const int _appendDayTabs = 30;
  int _maxVisibleDayTabs = _initialDayTabs;
  bool _isLoadingMoreDays = false;
  bool _noMoreOlderSegments = false;
  List<String> _loadedDayKeys = const <String>[];

  List<String> _orderedDayKeysFromSegments(
    List<Map<String, dynamic>> segments,
  ) {
    final Set<String> keys = <String>{};
    for (final Map<String, dynamic> seg in segments) {
      final int ms = (seg['start_time'] as int?) ?? 0;
      if (ms <= 0) continue;
      keys.add(_dateKeyFromMillis(ms));
    }
    final List<String> ordered = keys.toList()..sort((a, b) => b.compareTo(a));
    return ordered;
  }

  bool _shouldGateTimelineToCurrentRebuild([DynamicRebuildTaskStatus? status]) {
    final DynamicRebuildTaskStatus effective =
        status ?? _dynamicRebuildTaskStatus;
    if (effective.taskId.isEmpty || effective.isIdle || effective.isCompleted) {
      return false;
    }
    return true;
  }

  String? _dynamicRebuildTimelineCutoffDayKey([
    DynamicRebuildTaskStatus? status,
  ]) {
    final DynamicRebuildTaskStatus effective =
        status ?? _dynamicRebuildTaskStatus;
    if (!_shouldGateTimelineToCurrentRebuild(effective)) return null;
    final String key = effective.timelineCutoffDayKey.trim().isNotEmpty
        ? effective.timelineCutoffDayKey.trim()
        : effective.currentDayKey.trim();
    return key.isEmpty ? '' : key;
  }

  bool _shouldHideTimelineUntilRebuildAdvances([
    DynamicRebuildTaskStatus? status,
  ]) {
    final String? cutoff = _dynamicRebuildTimelineCutoffDayKey(status);
    return cutoff != null && cutoff.isEmpty;
  }

  int? _endMillisForDateKey(String dateKey) {
    final List<String> parts = dateKey.split('-');
    if (parts.length != 3) return null;
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(
          year,
          month,
          day,
        ).add(const Duration(days: 1)).millisecondsSinceEpoch -
        1;
  }

  String _dynamicRebuildTimelineVisibilityFingerprint([
    DynamicRebuildTaskStatus? status,
  ]) {
    final DynamicRebuildTaskStatus effective =
        status ?? _dynamicRebuildTaskStatus;
    final String? cutoff = _dynamicRebuildTimelineCutoffDayKey(effective);
    return '${_shouldGateTimelineToCurrentRebuild(effective)}|${cutoff ?? '(none)'}';
  }

  void _beginEntryPerfLoad(String step, {String? detail}) {
    if (!_trackEntryPerf) return;
    _entryPerfPendingLoads += 1;
    DynamicEntryPerfService.instance.mark('$step.start', detail: detail);
  }

  void _endEntryPerfLoad(String step, {String? detail}) {
    if (!_trackEntryPerf) return;
    if (_entryPerfPendingLoads > 0) {
      _entryPerfPendingLoads -= 1;
    }
    DynamicEntryPerfService.instance.mark('$step.done', detail: detail);
    _completeEntryPerfIfReady();
  }

  void _failEntryPerfLoad(String step, Object error, {String? detail}) {
    if (!_trackEntryPerf) return;
    if (_entryPerfPendingLoads > 0) {
      _entryPerfPendingLoads -= 1;
    }
    final String base = 'error=$error';
    final String resolvedDetail = (detail ?? '').trim();
    DynamicEntryPerfService.instance.mark(
      '$step.error',
      detail: resolvedDetail.isEmpty ? base : '$resolvedDetail | $base',
    );
    _completeEntryPerfIfReady();
  }

  void _completeEntryPerfIfReady() {
    if (!_trackEntryPerf) return;
    if (!_entryPerfShellFrameSeen || _entryPerfPendingLoads > 0) return;
    _trackEntryPerf = false;
    DynamicEntryPerfService.instance.finish(
      'segment.bootstrap.done',
      detail:
          'segments=${_segments.length} selectedDate=${_selectedDateKey ?? ''}',
    );
  }

  @override
  void initState() {
    super.initState();
    DynamicEntryPerfService.instance.beginSession(
      source: 'SegmentStatusPage.initState',
    );
    DynamicEntryPerfService.instance.mark('segment.initState');
    _dynamicRebuildUiSnapshotNotifier =
        ValueNotifier<_DynamicRebuildUiSnapshot>(
          _currentDynamicRebuildUiSnapshot(),
        );
    _dynamicRebuildIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _syncDynamicRebuildIconAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_trackEntryPerf) return;
      _entryPerfShellFrameSeen = true;
      DynamicEntryPerfService.instance.mark('segment.shell.firstFrame');
      _completeEntryPerfIfReady();
    });
    _initApps();
    _loadPrivacyMode();
    unawaited(_loadDynamicEntryLogIconEnabled());
    unawaited(_loadDynamicRebuildDayConcurrency());
    _loadSegmentsContextSelection();
    _refresh();
    unawaited(_refreshDynamicAutoRepairEnabled(showLoading: true));
    _startDynamicRebuildTaskPolling();
    unawaited(_refreshDynamicRebuildTaskStatus());
    // 订阅隐私模式变更
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() {
        _privacyMode = enabled;
      });
    });
  }

  Future<void> _loadDynamicEntryLogIconEnabled() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.dynamicEntryLogIconEnabled,
        defaultValue: false,
      );
      if (!mounted) return;
      setState(() => _dynamicEntryLogIconEnabled = enabled);
    } catch (_) {}
  }

  // 载入“动态(segments)”的提供商/模型选择（独立于对话页）
  Future<void> _loadSegmentsContextSelection() async {
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad('segment.context');
    try {
      final svc = AIProvidersService.instance;
      final Stopwatch providersSw = Stopwatch()..start();
      final providers = await svc.listProviders();
      DynamicEntryPerfService.instance.mark(
        'segment.context.providers.done',
        detail:
            'ms=${providersSw.elapsedMilliseconds} count=${providers.length}',
      );
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _ctxSegProvider = null;
            _ctxSegModel = null;
          });
        }
        _endEntryPerfLoad(
          'segment.context',
          detail: 'ms=${sw.elapsedMilliseconds} providers=0',
        );
        return;
      }
      final Stopwatch contextRowSw = Stopwatch()..start();
      final ctxRow = await AISettingsService.instance.getAIContextRow(
        'segments',
      );
      DynamicEntryPerfService.instance.mark(
        'segment.context.selection.done',
        detail:
            'ms=${contextRowSw.elapsedMilliseconds} hasRow=${ctxRow != null} providerId=${ctxRow?['provider_id'] ?? ''}',
      );
      AIProvider? sel;
      AIProvider? defaultProvider;
      final int? selectedProviderId = ctxRow?['provider_id'] as int?;
      final Stopwatch resolveSw = Stopwatch()..start();
      for (final AIProvider provider in providers) {
        if (selectedProviderId != null && provider.id == selectedProviderId) {
          sel = provider;
        }
        if (defaultProvider == null && provider.isDefault) {
          defaultProvider = provider;
        }
      }
      sel ??= defaultProvider;
      sel ??= providers.first;

      String model =
          (ctxRow != null &&
              (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString();
      if (model.isEmpty && sel.models.isNotEmpty) model = sel.models.first;
      DynamicEntryPerfService.instance.mark(
        'segment.context.resolve.done',
        detail:
            'ms=${resolveSw.elapsedMilliseconds} provider=${sel.name} model=$model',
      );

      if (mounted) {
        setState(() {
          _ctxSegProvider = sel;
          _ctxSegModel = model;
        });
      }
      _endEntryPerfLoad(
        'segment.context',
        detail:
            'ms=${sw.elapsedMilliseconds} providers=${providers.length} provider=${sel.name} model=$model',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.context',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    }
  }

  Future<void> _showProviderSheetSegments() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final currentId = _ctxSegProvider?.id ?? -1;
        // 使用持久化查询文本，避免键盘开合/重建导致输入被清空
        final TextEditingController queryCtrl = TextEditingController(
          text: _segProviderQueryText,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _segProviderQueryText = queryCtrl.text;
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
                                String model = (_ctxSegModel ?? '').trim();
                                if (model.isEmpty) {
                                  model =
                                      (p.extra['active_model'] as String? ??
                                              p.defaultModel)
                                          .toString()
                                          .trim();
                                }
                                if (model.isEmpty && p.models.isNotEmpty)
                                  model = p.models.first;
                                await AISettingsService.instance
                                    .setAIContextSelection(
                                      context: 'segments',
                                      providerId: p.id!,
                                      model: model,
                                    );
                                if (mounted) {
                                  setState(() {
                                    _ctxSegProvider = p;
                                    _ctxSegModel = model;
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

  Future<void> _showModelSheetSegments() async {
    final p = _ctxSegProvider;
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
        final active = (_ctxSegModel ?? '').trim();
        // 使用持久化查询文本，避免失焦时文本被清空
        final TextEditingController queryCtrl = TextEditingController(
          text: _segModelQueryText,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _segModelQueryText = queryCtrl.text;
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
                                      context: 'segments',
                                      providerId: p.id!,
                                      model: m,
                                    );
                                if (mounted) {
                                  setState(() => _ctxSegModel = m);
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
  Widget _buildSegmentsProviderModelAppBarTitle() {
    final theme = Theme.of(context);
    final String providerName = _ctxSegProvider?.name ?? '—';
    final String modelName = _ctxSegModel ?? '—';
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
            onTap: _showProviderSheetSegments,
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
            onTap: _showModelSheetSegments,
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

  Future<void> _loadPrivacyMode() async {
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad('segment.privacyMode');
    try {
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
      if (mounted) {
        setState(() {
          _privacyMode = enabled;
        });
      }
      _endEntryPerfLoad(
        'segment.privacyMode',
        detail: 'ms=${sw.elapsedMilliseconds} enabled=$enabled',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.privacyMode',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    }
  }

  Future<void> _initApps() async {
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad('segment.apps');
    try {
      final apps = await AppSelectionService.instance.getAllInstalledApps();
      if (!mounted) return;
      setState(() {
        for (final a in apps) {
          _appInfoByPackage[a.packageName] = a;
        }
      });
      _endEntryPerfLoad(
        'segment.apps',
        detail: 'ms=${sw.elapsedMilliseconds} count=${apps.length}',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.apps',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    }
  }

  Future<void> _refresh({bool triggerSegmentTick = true}) async {
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad(
      'segment.refresh',
      detail:
          'triggerTick=$triggerSegmentTick onlyNoSummary=$_onlyNoSummary selectedDate=${_selectedDateKey ?? ''}',
    );
    try {
      if (mounted) {
        setState(() {
          _loading = true;
        });
      }

      // 先触发一次原生端推进/补救：用于“删空某日后重建日期 Tab”等场景
      // ignore: unawaited_futures
      if (triggerSegmentTick && !_dynamicRebuildTaskStatus.isActive) {
        _db.triggerSegmentTick();
      }
      final Stopwatch activeSw = Stopwatch()..start();
      final active = await _db.getActiveSegment();
      DynamicEntryPerfService.instance.mark(
        'segment.refresh.active.done',
        detail:
            'ms=${activeSw.elapsedMilliseconds} hasActive=${active != null}',
      );
      final String? rebuildCutoffDayKey = _dynamicRebuildTimelineCutoffDayKey();
      final bool hideAllUntilCurrentDay =
          _shouldHideTimelineUntilRebuildAdvances();
      final int? rebuildCutoffEndMillis =
          rebuildCutoffDayKey == null || rebuildCutoffDayKey.isEmpty
          ? null
          : _endMillisForDateKey(rebuildCutoffDayKey);
      List<Map<String, dynamic>> segments;
      List<String> loadedDayKeys;
      bool hasMoreOlder = false;
      final Stopwatch timelineSw = Stopwatch()..start();

      if (hideAllUntilCurrentDay) {
        segments = const <Map<String, dynamic>>[];
        loadedDayKeys = const <String>[];
      } else if (_onlyNoSummary) {
        // “仅看无总结”模式：保持原有行为，仅限制行数；由 SQL 侧过滤无总结事件
        const int fetchLimit = 100;
        segments = await _db.listSegmentsEx(
          limit: fetchLimit,
          onlyNoSummary: true,
          endMillis: rebuildCutoffEndMillis,
        );
        loadedDayKeys = _orderedDayKeysFromSegments(segments);
      } else {
        final String pinnedDateKey = (_selectedDateKey ?? '').trim();
        final SegmentTimelineBatch batch = await _db.listSegmentTimelineBatch(
          distinctDayCount: _initialDayTabs,
          pinnedDateKey: pinnedDateKey.isEmpty ? null : pinnedDateKey,
          maxDateKeyInclusive: rebuildCutoffDayKey,
          requireSamples: true,
        );
        segments = batch.segments;
        loadedDayKeys = batch.dayKeys;
        hasMoreOlder = batch.hasMoreOlder;
      }
      DynamicEntryPerfService.instance.mark(
        'segment.refresh.timeline.done',
        detail:
            'ms=${timelineSw.elapsedMilliseconds} segments=${segments.length} dayKeys=${loadedDayKeys.length} hasMoreOlder=$hasMoreOlder hideAll=$hideAllUntilCurrentDay',
      );

      if (!mounted) return;
      setState(() {
        _active = active;
        _segments = segments;
        _loadedDayKeys = loadedDayKeys;
        _maxVisibleDayTabs = loadedDayKeys.isEmpty
            ? _initialDayTabs
            : loadedDayKeys.length;
        _noMoreOlderSegments = hideAllUntilCurrentDay || _onlyNoSummary
            ? true
            : !hasMoreOlder;
      });

      // 若处于“仅看无总结”，根据是否还有待补事件启动/停止自动检测
      if (_onlyNoSummary) {
        final hasPending = segments.any(
          (e) => (e['has_summary'] as int? ?? 0) == 0,
        );
        if (hasPending) {
          _maybeStartAutoWatch();
        } else {
          _stopAutoWatch();
        }
      }
      _endEntryPerfLoad(
        'segment.refresh',
        detail:
            'ms=${sw.elapsedMilliseconds} segments=${segments.length} dayKeys=${loadedDayKeys.length}',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.refresh',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
      // Keep previous state on error.
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSelectedDailySummary() async {
    final String? dateKey = _selectedDateKey;
    if (dateKey == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailySummaryPage(dateKey: dateKey)),
    );
  }

  bool _segmentStatusCanPop(BuildContext context) {
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route != null) return route.canPop;
    return Navigator.of(context).canPop();
  }

  double? _segmentStatusLeadingWidth(BuildContext context) {
    final bool canPop = _segmentStatusCanPop(context);
    final bool showDailySummary = _selectedDateKey != null;
    double width = 0;
    if (canPop) width += 52;
    if (showDailySummary) width += 52;
    if (showDailySummary && _dynamicEntryLogIconEnabled) width += 52;
    return width;
  }

  Color _segmentStatusActionIconColor(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return theme.appBarTheme.actionsIconTheme?.color ??
        theme.appBarTheme.iconTheme?.color ??
        IconTheme.of(context).color ??
        theme.colorScheme.onSurfaceVariant;
  }

  String _segmentEntryLogTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  ({String? tag, String message}) _splitTalkerTag(String? raw) {
    final String message = raw ?? '';
    if (!message.startsWith('[')) {
      return (tag: null, message: message);
    }
    final int end = message.indexOf(']');
    if (end <= 1) {
      return (tag: null, message: message);
    }
    final String tag = message.substring(1, end).trim();
    final String rest = message.substring(end + 1).trimLeft();
    return (tag: tag.isEmpty ? null : tag, message: rest);
  }

  int? _segmentEntrySessionId(TalkerData data) {
    final String message = _splitTalkerTag(data.message).message;
    final Match? match = RegExp(r'session#(\d+)').firstMatch(message);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  bool _isSegmentEntryPerfLog(TalkerData data) {
    final ({String? tag, String message}) parts = _splitTalkerTag(data.message);
    if (parts.tag != DynamicEntryPerfService.logTag) {
      return false;
    }
    return parts.message.contains('source=SegmentStatusPage') ||
        parts.message.contains('segment.');
  }

  List<TalkerData> _latestSegmentEntryPerfLogs() {
    final List<TalkerData> items = FlutterLogger.talker.history
        .where(_isSegmentEntryPerfLog)
        .toList(growable: false);
    if (items.isEmpty) {
      return const <TalkerData>[];
    }
    int? latestSessionId;
    for (final TalkerData item in items.reversed) {
      latestSessionId = _segmentEntrySessionId(item);
      if (latestSessionId != null) {
        break;
      }
    }
    if (latestSessionId == null) {
      return items;
    }
    final List<TalkerData> sessionItems = items
        .where(
          (TalkerData item) => _segmentEntrySessionId(item) == latestSessionId,
        )
        .toList(growable: false);
    return sessionItems.isEmpty ? items : sessionItems;
  }

  String _buildSegmentEntryPerfExportText(List<TalkerData> items) {
    final StringBuffer buffer = StringBuffer();
    for (final TalkerData item in items) {
      final ({String? tag, String message}) parts = _splitTalkerTag(
        item.message,
      );
      final String tagPrefix = parts.tag == null ? '' : '[${parts.tag}] ';
      buffer.writeln(
        '${_segmentEntryLogTime(item.time)} $tagPrefix${parts.message}',
      );
      final Object? error = item.exception ?? item.error;
      if (error != null) {
        buffer.writeln(error.toString());
      }
      if (item.stackTrace != null && item.stackTrace != StackTrace.empty) {
        buffer.writeln(item.stackTrace.toString());
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<void> _openSegmentEntryPerfSheet() async {
    final List<TalkerData> items = _latestSegmentEntryPerfLogs();
    final int? sessionId = items.isEmpty
        ? null
        : _segmentEntrySessionId(items.last);
    final String text = _buildSegmentEntryPerfExportText(items);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool hasLogs = text.trim().isNotEmpty;

    await AIRequestLogsSheet.show(
      context: context,
      title: '动态进入日志',
      metaText: sessionId == null
          ? '显示当前页可用的动态进入日志'
          : '仅显示最近一次进入会话 session#$sessionId，共 ${items.length} 条',
      hintText: '直接长按选择文本，或点复制按钮一次性复制。',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: !hasLogs
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    UINotifier.success(context, '已复制动态进入日志');
                  },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('复制日志'),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
            ),
            child: SelectableText(
              hasLogs ? text : '暂无动态进入日志，请先重新进入动态页再查看。',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentStatusLeading(BuildContext context) {
    final bool canPop = _segmentStatusCanPop(context);
    final bool showDailySummary = _selectedDateKey != null;
    final Color actionColor = _segmentStatusActionIconColor(context);
    if (!canPop && !showDailySummary) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPop) BackButton(color: actionColor),
        if (showDailySummary)
          IconButton(
            style: IconButton.styleFrom(foregroundColor: actionColor),
            icon: const Icon(Icons.event_note_outlined),
            tooltip: AppLocalizations.of(context).viewOrGenerateForDay,
            onPressed: _openSelectedDailySummary,
          ),
        if (showDailySummary && _dynamicEntryLogIconEnabled)
          IconButton(
            style: IconButton.styleFrom(foregroundColor: actionColor),
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: '动态进入日志',
            onPressed: _openSegmentEntryPerfSheet,
          ),
      ],
    );
  }

  Future<void> _loadOlderSegmentsFromDbIfNeeded() async {
    if (_onlyNoSummary ||
        _isLoadingMoreDays ||
        _noMoreOlderSegments ||
        _shouldHideTimelineUntilRebuildAdvances()) {
      return;
    }
    final List<String> currentDayKeys = _loadedDayKeys.isNotEmpty
        ? _loadedDayKeys
        : _orderedDayKeysFromSegments(_segments);
    final String beforeDateKey = currentDayKeys.isEmpty
        ? ''
        : currentDayKeys.last;
    if (beforeDateKey.isEmpty) {
      if (!_noMoreOlderSegments) {
        setState(() => _noMoreOlderSegments = true);
      }
      return;
    }

    _isLoadingMoreDays = true;
    try {
      final SegmentTimelineBatch batch = await _db.listSegmentTimelineBatch(
        distinctDayCount: _appendDayTabs,
        beforeDateKey: beforeDateKey,
        maxDateKeyInclusive: _dynamicRebuildTimelineCutoffDayKey(),
        requireSamples: true,
      );
      final List<Map<String, dynamic>> more = batch.segments;
      if (more.isEmpty) {
        if (!_noMoreOlderSegments) {
          setState(() => _noMoreOlderSegments = true);
        }
        return;
      }

      // 合并去重并按 start_time DESC 排序，保证 UI 与时间线顺序一致
      final Map<int, Map<String, dynamic>> byId = <int, Map<String, dynamic>>{};
      for (final m in _segments) {
        final int id = (m['id'] as int?) ?? 0;
        if (id <= 0) continue;
        byId[id] = m;
      }
      for (final m in more) {
        final int id = (m['id'] as int?) ?? 0;
        if (id <= 0) continue;
        byId[id] = m;
      }
      final List<Map<String, dynamic>> merged = byId.values.toList()
        ..sort((a, b) {
          final int ta = (a['start_time'] as int?) ?? 0;
          final int tb = (b['start_time'] as int?) ?? 0;
          return tb.compareTo(ta); // 按时间倒序
        });
      final List<String> mergedDayKeys = <String>[
        ..._loadedDayKeys,
        ...batch.dayKeys,
      ].toSet().toList()..sort((a, b) => b.compareTo(a));

      setState(() {
        _segments = merged;
        _loadedDayKeys = mergedDayKeys;
        _maxVisibleDayTabs = mergedDayKeys.length;
        _noMoreOlderSegments = !batch.hasMoreOlder;
      });
    } finally {
      _isLoadingMoreDays = false;
    }
  }

  Future<void> _handleLastDayTabReached() async {
    if (!mounted) return;
    await _loadOlderSegmentsFromDbIfNeeded();
  }

  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  Widget _buildActiveCard() {
    final a = _active;
    if (a == null) return const SizedBox.shrink();
    final start = (a['start_time'] as int?) ?? 0;
    final end = (a['end_time'] as int?) ?? 0;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // Banner-style, smaller font, single-line; background matches page (avoid pure white).
    final String text =
        '${l10n.activeSegmentTitle}: ${_fmtTime(start)}-${_fmtTime(end)}';

    final TextStyle style = (theme.textTheme.bodySmall ?? const TextStyle())
        .copyWith(color: cs.onSurface, fontWeight: FontWeight.w600, height: 1);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacing1),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing2,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withOpacity(0.35), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.timelapse, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: AppTheme.spacing2),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStack() {
    return _buildActiveCard();
  }

  _DynamicRebuildUiSnapshot _currentDynamicRebuildUiSnapshot() {
    return _DynamicRebuildUiSnapshot(
      status: _dynamicRebuildTaskStatus,
      starting: _startingDynamicRebuild,
      stopping: _stoppingDynamicRebuild,
      selectedDayConcurrency: _selectedDynamicRebuildDayConcurrency,
      savingDayConcurrency: _savingDynamicRebuildDayConcurrency,
      autoRepairEnabled: _dynamicAutoRepairEnabled,
      autoRepairLoading: _loadingDynamicAutoRepair,
      autoRepairToggling: _togglingDynamicAutoRepair,
      requestLogs: _dynamicRebuildRequestLogsState,
    );
  }

  Future<void> _loadDynamicRebuildDayConcurrency() async {
    try {
      final int raw = await UserSettingsService.instance.getInt(
        UserSettingKeys.dynamicRebuildDayConcurrency,
        defaultValue: 1,
      );
      if (!mounted) return;
      final int normalized = math.max(1, math.min(10, raw));
      setState(() => _selectedDynamicRebuildDayConcurrency = normalized);
      _publishDynamicRebuildUiSnapshot();
    } catch (_) {}
  }

  bool _canEditDynamicRebuildDayConcurrency(
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    return !snapshot.status.isActive &&
        !snapshot.starting &&
        !snapshot.stopping &&
        !snapshot.savingDayConcurrency;
  }

  int _effectiveDynamicRebuildDayConcurrency(
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final int preferred = snapshot.status.isActive
        ? (snapshot.status.dayConcurrency > 0
              ? snapshot.status.dayConcurrency
              : snapshot.selectedDayConcurrency)
        : snapshot.selectedDayConcurrency;
    return math.max(1, math.min(10, preferred));
  }

  Future<void> _setDynamicRebuildDayConcurrency(int value) async {
    final _DynamicRebuildUiSnapshot snapshot =
        _currentDynamicRebuildUiSnapshot();
    if (!_canEditDynamicRebuildDayConcurrency(snapshot)) return;
    final int normalized = math.max(1, math.min(10, value));
    if (normalized == _selectedDynamicRebuildDayConcurrency) return;
    final int previous = _selectedDynamicRebuildDayConcurrency;
    setState(() {
      _selectedDynamicRebuildDayConcurrency = normalized;
      _savingDynamicRebuildDayConcurrency = true;
    });
    _publishDynamicRebuildUiSnapshot();
    try {
      await UserSettingsService.instance.setInt(
        UserSettingKeys.dynamicRebuildDayConcurrency,
        normalized,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectedDynamicRebuildDayConcurrency = previous);
      UINotifier.error(context, '保存并发天数失败');
    } finally {
      if (!mounted) return;
      setState(() => _savingDynamicRebuildDayConcurrency = false);
      _publishDynamicRebuildUiSnapshot();
    }
  }

  Future<void> _changeDynamicRebuildDayConcurrency(int delta) async {
    await _setDynamicRebuildDayConcurrency(
      _selectedDynamicRebuildDayConcurrency + delta,
    );
  }

  void _publishDynamicRebuildUiSnapshot() {
    _dynamicRebuildUiSnapshotNotifier.value =
        _currentDynamicRebuildUiSnapshot();
    _syncDynamicRebuildIconAnimation();
  }

  void _syncDynamicRebuildIconAnimation() {
    final bool shouldSpin =
        _startingDynamicRebuild ||
        _stoppingDynamicRebuild ||
        _dynamicRebuildTaskStatus.isActive;
    if (shouldSpin) {
      if (!_dynamicRebuildIconController.isAnimating) {
        _dynamicRebuildIconController.repeat();
      }
      return;
    }
    if (_dynamicRebuildIconController.isAnimating) {
      _dynamicRebuildIconController.stop();
    }
    _dynamicRebuildIconController.value = 0;
  }

  Future<void> _refreshDynamicAutoRepairEnabled({
    bool showLoading = false,
  }) async {
    if (_loadingDynamicAutoRepair) return;
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad(
      'segment.autoRepair',
      detail: 'showLoading=$showLoading',
    );
    if (showLoading && mounted) {
      setState(() => _loadingDynamicAutoRepair = true);
      _publishDynamicRebuildUiSnapshot();
    }
    try {
      final bool enabled = await _db.getDynamicAutoRepairEnabled();
      if (!mounted) return;
      setState(() {
        _dynamicAutoRepairEnabled = enabled;
        _loadingDynamicAutoRepair = false;
      });
      _publishDynamicRebuildUiSnapshot();
      _endEntryPerfLoad(
        'segment.autoRepair',
        detail: 'ms=${sw.elapsedMilliseconds} enabled=$enabled',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.autoRepair',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
      if (!mounted || !_loadingDynamicAutoRepair) return;
      setState(() => _loadingDynamicAutoRepair = false);
      _publishDynamicRebuildUiSnapshot();
    }
  }

  Future<void> _setDynamicAutoRepairEnabled(bool enabled) async {
    if (_loadingDynamicAutoRepair || _togglingDynamicAutoRepair) return;
    final bool previous = _dynamicAutoRepairEnabled;
    setState(() {
      _togglingDynamicAutoRepair = true;
      _dynamicAutoRepairEnabled = enabled;
    });
    _publishDynamicRebuildUiSnapshot();
    try {
      final bool persisted = await _db.setDynamicAutoRepairEnabled(enabled);
      if (!mounted) return;
      setState(() => _dynamicAutoRepairEnabled = persisted);
      _publishDynamicRebuildUiSnapshot();
      UINotifier.info(context, persisted ? '自动补建已开启' : '自动补建已暂停');
    } catch (_) {
      if (!mounted) return;
      setState(() => _dynamicAutoRepairEnabled = previous);
      _publishDynamicRebuildUiSnapshot();
      UINotifier.error(context, '切换自动补建失败');
    } finally {
      if (!mounted) return;
      setState(() => _togglingDynamicAutoRepair = false);
      _publishDynamicRebuildUiSnapshot();
    }
  }

  Future<void> _openDynamicRebuildTaskSheet() async {
    try {
      await Future.wait<void>([
        _refreshDynamicRebuildTaskStatus(refreshSegmentsOnChange: false),
        _refreshDynamicAutoRepairEnabled(showLoading: true),
      ]);
    } catch (_) {}
    _dynamicRebuildTaskSheetOpen = true;
    if (_dynamicRebuildRequestLogsEnabled) {
      await _refreshDynamicRebuildRequestLogs(force: true);
    }
    if (!mounted) return;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return ValueListenableBuilder<_DynamicRebuildUiSnapshot>(
            valueListenable: _dynamicRebuildUiSnapshotNotifier,
            builder: (sheetCtx, snapshot, _) {
              final cs = Theme.of(sheetCtx).colorScheme;
              return DraggableScrollableSheet(
                initialChildSize: 0.62,
                minChildSize: 0.32,
                maxChildSize: 0.90,
                expand: false,
                builder: (_, scrollCtrl) {
                  return ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppTheme.radiusLg),
                      topRight: Radius.circular(AppTheme.radiusLg),
                    ),
                    child: ColoredBox(
                      color: cs.surface,
                      child: SafeArea(
                        top: false,
                        child: SingleChildScrollView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacing4,
                            AppTheme.spacing3,
                            AppTheme.spacing4,
                            AppTheme.spacing4,
                          ),
                          child: _buildDynamicRebuildTaskSheetBody(
                            sheetCtx,
                            snapshot,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      _dynamicRebuildTaskSheetOpen = false;
    }
  }

  Widget _buildDynamicRebuildTaskSheetBody(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = snapshot.status;
    final int dayConcurrency = _effectiveDynamicRebuildDayConcurrency(snapshot);
    final Color statusColor = _dynamicRebuildTaskColor(status);
    final double? progressValue = status.totalSegments > 0
        ? (status.processedSegments / status.totalSegments).clamp(0, 1)
        : (status.isCompleted ? 1 : null);
    final String progressText = status.totalSegments > 0
        ? '${status.processedSegments}/${status.totalSegments} (${status.progressPercent})'
        : (status.isCompleted ? '无可重建动态' : '0/0 (${status.progressPercent})');
    final String summaryLine =
        '已完成 ${status.processedSegments}/${status.totalSegments} 条动态 · '
        '已完成 ${status.completedDays}/${status.totalDays} 天 · '
        '并发 $dayConcurrency · '
        '待续失败天数 ${status.failedDays}';
    final String currentLine = _dynamicRebuildCurrentLine(status);
    final String modelLine = _dynamicRebuildModelLine(status);
    final String stageHeadline = _dynamicRebuildStageHeadline(status);
    final String serialHint = _dynamicRebuildSerialHint(status);

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
                '动态重建任务',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: statusColor.withValues(alpha: 0.25)),
              ),
              child: Text(
                _dynamicRebuildTaskLabel(status),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing3),
        Text(
          progressText,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.spacing2),
        UIProgress(value: progressValue, height: 6),
        Padding(
          padding: const EdgeInsets.only(top: AppTheme.spacing2),
          child: Text(
            summaryLine,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
        if (currentLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing3),
            child: Text(
              currentLine,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        if (modelLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing2),
            child: Text(
              modelLine,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (stageHeadline.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: AppTheme.spacing3),
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              stageHeadline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (serialHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing2),
            child: Text(
              serialHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: AppTheme.spacing3),
        if (status.startedAt > 0)
          Text(
            '开始：${_fmtTaskDateTime(status.startedAt)}',
            style: theme.textTheme.bodySmall,
          ),
        if (status.updatedAt > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '更新：${_fmtTaskDateTime(status.updatedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (status.completedAt > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '结束：${_fmtTaskDateTime(status.completedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (status.lastError != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: AppTheme.spacing3),
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              status.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
        const SizedBox(height: AppTheme.spacing4),
        _buildDynamicRebuildTaskActionRow(context, snapshot),
        const SizedBox(height: AppTheme.spacing3),
        _buildDynamicRebuildDayConcurrencySection(context, snapshot),
        const SizedBox(height: AppTheme.spacing3),
        _buildDynamicRebuildWorkersSection(context, snapshot),
        const SizedBox(height: AppTheme.spacing3),
        _buildDynamicAutoRepairSection(context, snapshot),
        if (status.recentLogs.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildDynamicRebuildStageLogsSection(context, status),
        ],
        if (_dynamicRebuildRequestLogsEnabled) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildDynamicRebuildRequestLogsSection(context, snapshot),
        ],
      ],
    );
  }

  Widget _buildDynamicRebuildTaskActionRow(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final DynamicRebuildTaskStatus status = snapshot.status;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final OutlinedBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
    );
    final Widget startButton = SizedBox(
      height: 44,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.error,
          foregroundColor: colorScheme.onError,
          disabledBackgroundColor: colorScheme.surfaceContainerHigh,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          shape: shape,
        ),
        onPressed: (snapshot.starting || status.isActive)
            ? null
            : _confirmStartDynamicRebuild,
        icon: const Icon(Icons.restart_alt),
        label: const Text('开始重建'),
      ),
    );
    if (status.isActive) {
      return Row(
        children: [
          Expanded(child: startButton),
          const SizedBox(width: AppTheme.spacing2),
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
                ),
                onPressed: snapshot.stopping ? null : _cancelDynamicRebuild,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止'),
              ),
            ),
          ),
        ],
      );
    }
    if (status.canContinue) {
      return Row(
        children: [
          Expanded(child: startButton),
          const SizedBox(width: AppTheme.spacing2),
          Expanded(
            child: SizedBox(
              height: 44,
              child: FilledButton.icon(
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
                ),
                onPressed: snapshot.starting ? null : _continueDynamicRebuild,
                icon: const Icon(Icons.play_arrow),
                label: const Text('继续重建'),
              ),
            ),
          ),
        ],
      );
    }
    return SizedBox(width: double.infinity, child: startButton);
  }

  Widget _buildDynamicRebuildDayConcurrencySection(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool editable = _canEditDynamicRebuildDayConcurrency(snapshot);
    final int value = _effectiveDynamicRebuildDayConcurrency(snapshot);

    Widget buildStepButton({
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return SizedBox(
        width: 34,
        height: 34,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            side: BorderSide(
              color: cs.outline.withValues(
                alpha: onPressed == null ? 0.18 : 0.34,
              ),
            ),
          ),
          onPressed: onPressed,
          child: Icon(icon, size: 16),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '并发天数',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  editable ? '可设置 1-10 天' : '任务运行中不可修改',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          buildStepButton(
            icon: Icons.remove,
            onPressed: editable && value > 1
                ? () {
                    unawaited(_changeDynamicRebuildDayConcurrency(-1));
                  }
                : null,
          ),
          Container(
            width: 48,
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          buildStepButton(
            icon: Icons.add,
            onPressed: editable && value < 10
                ? () {
                    unawaited(_changeDynamicRebuildDayConcurrency(1));
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicRebuildWorkersSection(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int slotCount = math.max(
      _effectiveDynamicRebuildDayConcurrency(snapshot),
      snapshot.status.workers.length,
    );
    final Map<int, DynamicRebuildWorkerState> workersBySlot =
        <int, DynamicRebuildWorkerState>{
          for (final DynamicRebuildWorkerState worker
              in snapshot.status.workers)
            worker.slotId: worker,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '线程进度',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.spacing1),
        Text(
          '每个线程会串行跑完当天全部动态，完成后再领取下一个未完成日期。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppTheme.spacing3),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool useTwoColumns = constraints.maxWidth >= 680;
            final double cardWidth = useTwoColumns
                ? (constraints.maxWidth - AppTheme.spacing3) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppTheme.spacing3,
              runSpacing: AppTheme.spacing3,
              children: [
                for (int slotId = 1; slotId <= slotCount; slotId++)
                  SizedBox(
                    width: cardWidth,
                    child: _buildDynamicRebuildWorkerCard(
                      context,
                      slotId,
                      workersBySlot[slotId],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDynamicRebuildWorkerCard(
    BuildContext context,
    int slotId,
    DynamicRebuildWorkerState? worker,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color accent = _dynamicRebuildWorkerColor(context, worker);
    final String statusLine = _dynamicRebuildWorkerStatusLine(worker);
    final String stageLabel = worker?.currentStageLabel.trim() ?? '';
    final String stageDetail = worker?.currentStageDetail.trim() ?? '';
    final String rangeLabel = worker?.currentRangeLabel.trim() ?? '';
    final int processed = worker?.processedSegments ?? 0;
    final int total = worker?.totalSegments ?? 0;
    final List<String> recentStreamChunks =
        (worker?.recentStreamChunks ?? const <String>[]).reversed
            .take(3)
            .toList(growable: false);
    final double? progressValue = total > 0
        ? (processed / total).clamp(0, 1)
        : null;
    final String progressText = total > 0 ? '$processed/$total' : '0/0';

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '线程 $slotId',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  _dynamicRebuildWorkerChipLabel(worker),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            statusLine,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            '当天进度 $progressText',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          UIProgress(value: progressValue, height: 5),
          if (rangeLabel.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              '时间窗：$rangeLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (stageLabel.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              '当前阶段：$stageLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (stageDetail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              stageDetail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (recentStreamChunks.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing3),
            Text(
              '最近 3 条流式数据',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacing1),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacing2),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    int index = 0;
                    index < recentStreamChunks.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: 6),
                    Text(
                      '${index + 1}. ${recentStreamChunks[index]}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicAutoRepairSection(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool busy = snapshot.autoRepairLoading || snapshot.autoRepairToggling;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '自动补建/补洞',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing1),
                Text(
                  snapshot.autoRepairEnabled
                      ? '已开启：后台会自动补历史日期、缺失总结和断档动态。'
                      : '已暂停：后台不会自动补历史日期或缺失总结，可避免请求快速打满 RPM。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing1),
                Text(
                  '关闭后不影响手动“开始重建”，也不会打断当前正在执行的任务。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing1),
                Text(
                  '这个开关控制的是后台自动补建流量；手动重建仍以上面的按钮为准。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.78),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          if (snapshot.autoRepairLoading && !snapshot.autoRepairToggling)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Opacity(
              opacity: busy ? 0.6 : 1,
              child: Transform.scale(
                scale: 0.92,
                child: Switch(
                  value: snapshot.autoRepairEnabled,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: busy ? null : _setDynamicAutoRepairEnabled,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDynamicRebuildRequestLogsSection(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    final _DynamicRebuildRequestLogsState logs = snapshot.requestLogs;
    final String rawText = logs.rawText.trimRight();
    final bool hasRaw = rawText.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: AppTheme.spacing4),
        Row(
          children: [
            Expanded(
              child: Text(
                isZh ? '重建请求' : 'Rebuild Requests',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 18,
              height: 18,
              child: logs.loading && !logs.hasAny
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spacing3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Text(
            isZh
                ? '这里展示的是动态重建期间由原生 SegmentSummaryManager 直连发出的 AI 请求，不经过 Flutter 的 AIRequestGateway。日期 tab 只是根据数据库里已经生成出的 segments 刷新显示，切 tab 只会读取本地结果，不会额外触发这些 AI 请求。默认仅展示最近 $_dynamicRebuildRequestLogsDisplayLimit 个请求，避免面板卡顿。'
                : 'These are native SegmentSummaryManager AI requests emitted during dynamic rebuild. They bypass Flutter AIRequestGateway. Day tabs only reflect segments already written into the local database and do not trigger these AI calls. Only the most recent $_dynamicRebuildRequestLogsDisplayLimit requests are shown by default to keep the panel responsive.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacing3),
        if (logs.error != null && logs.error!.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              logs.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          )
        else if (!logs.loading && logs.traces.isEmpty && !hasRaw)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
            ),
            child: Text(
              isZh
                  ? '当前任务还没有匹配到请求日志。若 AI 分类日志未开启，这里也会为空。'
                  : 'No request logs matched the current task yet. This also stays empty when AI category logging is disabled.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          AIRequestLogsViewer.traces(
            traces: logs.traces,
            rawFallbackText: hasRaw ? rawText : null,
            scrollable: false,
            emptyText: isZh ? '（暂无请求日志）' : '(No request logs yet)',
            actions: <AIRequestLogsAction>[
              AIRequestLogsAction(
                label: AppLocalizations.of(context).actionCopy,
                enabled: hasRaw,
                onPressed: () async {
                  if (!hasRaw) return;
                  try {
                    await Clipboard.setData(ClipboardData(text: rawText));
                    if (!mounted) return;
                    UINotifier.success(
                      context,
                      AppLocalizations.of(context).copySuccess,
                    );
                  } catch (_) {}
                },
              ),
              AIRequestLogsAction(
                label: isZh ? '保存到文件' : 'Save to file',
                enabled: hasRaw,
                onPressed: () async {
                  if (!hasRaw) return;
                  await _saveDynamicRebuildRequestLogsToFile(rawText);
                },
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _refreshDynamicRebuildRequestLogs({
    DynamicRebuildTaskStatus? status,
    bool force = false,
  }) async {
    final DynamicRebuildTaskStatus current =
        status ?? _dynamicRebuildTaskStatus;
    if (current.taskId.isEmpty || current.startedAt <= 0) {
      if (_dynamicRebuildRequestLogsState.hasAny ||
          _dynamicRebuildRequestLogsState.error != null ||
          _dynamicRebuildRequestLogsState.loading) {
        _dynamicRebuildRequestLogsState =
            const _DynamicRebuildRequestLogsState();
        _publishDynamicRebuildUiSnapshot();
      }
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _dynamicRebuildRequestLogsState.loading) return;
    if (!force && now - _lastDynamicRebuildRequestLogsRefreshAt < 1200) return;
    _lastDynamicRebuildRequestLogsRefreshAt = now;
    final int ticket = ++_dynamicRebuildRequestLogsLoadTicket;
    final bool showForegroundLoading =
        !_dynamicRebuildRequestLogsState.hasAny &&
        (_dynamicRebuildRequestLogsState.error?.trim().isNotEmpty != true);
    if (showForegroundLoading) {
      final _DynamicRebuildRequestLogsState next =
          _dynamicRebuildRequestLogsState.copyWith(loading: true, error: null);
      if (!_sameDynamicRebuildRequestLogsState(
        _dynamicRebuildRequestLogsState,
        next,
      )) {
        _dynamicRebuildRequestLogsState = next;
        _publishDynamicRebuildUiSnapshot();
      }
    }
    try {
      final _DynamicRebuildRequestLogsState loaded =
          await _loadDynamicRebuildRequestLogs(current);
      if (!mounted || ticket != _dynamicRebuildRequestLogsLoadTicket) return;
      final _DynamicRebuildRequestLogsState next = loaded.copyWith(
        loading: false,
      );
      if (!_sameDynamicRebuildRequestLogsState(
        _dynamicRebuildRequestLogsState,
        next,
      )) {
        _dynamicRebuildRequestLogsState = next;
        _publishDynamicRebuildUiSnapshot();
      }
    } catch (e) {
      if (!mounted || ticket != _dynamicRebuildRequestLogsLoadTicket) return;
      final _DynamicRebuildRequestLogsState next = showForegroundLoading
          ? _dynamicRebuildRequestLogsState.copyWith(
              loading: false,
              error: e.toString(),
            )
          : _dynamicRebuildRequestLogsState.copyWith(loading: false);
      if (!_sameDynamicRebuildRequestLogsState(
        _dynamicRebuildRequestLogsState,
        next,
      )) {
        _dynamicRebuildRequestLogsState = next;
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }

  Future<_DynamicRebuildRequestLogsState> _loadDynamicRebuildRequestLogs(
    DynamicRebuildTaskStatus status,
  ) async {
    String? todayDirPath;
    try {
      todayDirPath = await FlutterLogger.getTodayLogsDir();
    } catch (_) {
      todayDirPath = null;
    }
    final String trimmed = (todayDirPath ?? '').trim();
    if (trimmed.isEmpty) {
      return const _DynamicRebuildRequestLogsState();
    }
    final Directory? logsRoot = _resolveOutputLogsRoot(Directory(trimmed));
    if (logsRoot == null || !await logsRoot.exists()) {
      return const _DynamicRebuildRequestLogsState();
    }

    final DateTime startedAt = DateTime.fromMillisecondsSinceEpoch(
      status.startedAt,
    );
    final DateTime endedAt = status.completedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(status.completedAt)
        : DateTime.now();
    final List<File> files = await _listDynamicRebuildRequestLogFiles(
      logsRoot,
      startedAt: startedAt,
      endedAt: endedAt,
    );
    if (files.isEmpty) {
      return const _DynamicRebuildRequestLogsState();
    }

    final StringBuffer sb = StringBuffer();
    for (final File file in files) {
      try {
        final String text = await file.readAsString();
        final String content = text.trimRight();
        if (content.isEmpty) continue;
        if (sb.isNotEmpty) sb.writeln();
        sb.writeln(content);
      } catch (_) {}
    }
    final String rawText = sb.toString().trimRight();
    if (rawText.trim().isEmpty) {
      return const _DynamicRebuildRequestLogsState();
    }
    final List<AIRequestTrace> traces = parseNativeAiRequestLogText(
      rawText,
      since: startedAt.subtract(const Duration(seconds: 5)),
      until: endedAt.add(const Duration(seconds: 5)),
    );
    if (traces.isEmpty) {
      return const _DynamicRebuildRequestLogsState();
    }
    final List<AIRequestTrace> visibleTraces = traces
        .take(_dynamicRebuildRequestLogsDisplayLimit)
        .toList(growable: false);
    final String visibleRawText = visibleTraces
        .expand((AIRequestTrace trace) => trace.rawBlocks)
        .map((String line) => line.trimRight())
        .where((String line) => line.trim().isNotEmpty)
        .join('\n')
        .trimRight();
    return _DynamicRebuildRequestLogsState(
      traces: visibleTraces,
      rawText: visibleRawText,
    );
  }

  Directory? _resolveOutputLogsRoot(Directory todayDir) {
    Directory current = todayDir;
    for (int i = 0; i < 3; i += 1) {
      final Directory parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
    return current;
  }

  Future<List<File>> _listDynamicRebuildRequestLogFiles(
    Directory logsRoot, {
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final List<File> files = <File>[];
    DateTime day = DateTime(startedAt.year, startedAt.month, startedAt.day);
    final DateTime lastDay = DateTime(endedAt.year, endedAt.month, endedAt.day);
    while (!day.isAfter(lastDay)) {
      final String yyyy = day.year.toString().padLeft(4, '0');
      final String mm = day.month.toString().padLeft(2, '0');
      final String dd = day.day.toString().padLeft(2, '0');
      final Directory dir = Directory(
        '${logsRoot.path}${Platform.pathSeparator}$yyyy${Platform.pathSeparator}$mm${Platform.pathSeparator}$dd',
      );
      final File infoFile = File(
        '${dir.path}${Platform.pathSeparator}${dd}_info.log',
      );
      final File errorFile = File(
        '${dir.path}${Platform.pathSeparator}${dd}_error.log',
      );
      if (await infoFile.exists()) files.add(infoFile);
      if (await errorFile.exists()) files.add(errorFile);
      day = day.add(const Duration(days: 1));
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> _saveDynamicRebuildRequestLogsToFile(String text) async {
    final String content = text.trimRight();
    if (content.trim().isEmpty) return;
    try {
      final DateTime now = DateTime.now();
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
        '${baseDir.path}${sep}dynamic_rebuild_ai_logs',
      );
      await outDir.create(recursive: true);
      final File f = File(
        '${outDir.path}${sep}dynamic_rebuild_ai_${now.millisecondsSinceEpoch}.log',
      );
      await f.writeAsString('$content\n', flush: true);
      try {
        await Clipboard.setData(ClipboardData(text: f.path));
      } catch (_) {}
      if (!mounted) return;
      final bool isZh = Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
      UINotifier.success(
        context,
        isZh ? '已保存到：${f.path}' : 'Saved to: ${f.path}',
      );
    } catch (e) {
      if (!mounted) return;
      final bool isZh = Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
      UINotifier.error(context, isZh ? '保存失败：$e' : 'Save failed: $e');
    }
  }

  int _dynamicRebuildCurrentOrdinal(DynamicRebuildTaskStatus status) {
    if (status.totalSegments <= 0) return 0;
    if (status.isCompleted) return status.totalSegments;
    final int next = status.processedSegments + 1;
    return math.min(status.totalSegments, math.max(1, next));
  }

  String _dynamicRebuildCurrentLine(DynamicRebuildTaskStatus status) {
    final List<String> activeDays =
        status.workers
            .where(
              (DynamicRebuildWorkerState worker) =>
                  worker.isRunning || worker.isRetrying,
            )
            .map((DynamicRebuildWorkerState worker) => worker.dayKey.trim())
            .where((String dayKey) => dayKey.isNotEmpty)
            .toSet()
            .toList()
          ..sort((String a, String b) => b.compareTo(a));
    if (activeDays.isNotEmpty) {
      return '当前活跃日期：${activeDays.join(' / ')}';
    }
    final String scope = [
      if (status.currentDayKey.isNotEmpty) status.currentDayKey,
      if (status.currentRangeLabel.isNotEmpty) status.currentRangeLabel,
    ].join(' · ');
    if (scope.isNotEmpty) {
      final String prefix = status.isActive ? '当前正在重建' : '当前停留在';
      return '$prefix：$scope';
    }
    if (status.timelineCutoffDayKey.trim().isNotEmpty) {
      return '时间线当前可见到：${status.timelineCutoffDayKey.trim()}';
    }
    if (status.totalSegments <= 0) return '';
    final int currentOrdinal = _dynamicRebuildCurrentOrdinal(status);
    if (currentOrdinal <= 0) return '';
    return '当前进度停留在第 $currentOrdinal/${status.totalSegments} 条动态';
  }

  String _dynamicRebuildStageHeadline(DynamicRebuildTaskStatus status) {
    final String label = status.currentStageLabel.trim();
    final String detail = status.currentStageDetail.trim();
    if (label.isEmpty && detail.isEmpty) return '';
    if (label.isEmpty) return '当前环节：$detail';
    if (detail.isEmpty) return '当前环节：$label';
    return '当前环节：$label\n$detail';
  }

  String _dynamicRebuildModelLine(DynamicRebuildTaskStatus status) {
    final String model = status.aiModel.trim();
    if (model.isEmpty) return '';
    return '当前模型：$model';
  }

  String _dynamicRebuildWorkerStatusLine(DynamicRebuildWorkerState? worker) {
    if (worker == null) return '等待分配';
    if (worker.isRetrying) {
      final int retryLimit = worker.retryLimit > 0 ? worker.retryLimit : 3;
      final int retryCount = worker.retryCount > 0 ? worker.retryCount : 1;
      return '重试 $retryCount/$retryLimit';
    }
    if (worker.dayKey.trim().isNotEmpty) return worker.dayKey.trim();
    if (worker.isFailedWaiting) return '等待手动继续';
    if (worker.isCompleted) return '当天完成';
    return '等待分配';
  }

  String _dynamicRebuildWorkerChipLabel(DynamicRebuildWorkerState? worker) {
    if (worker == null || worker.isIdle) return '空闲';
    if (worker.isRetrying) return '重试中';
    if (worker.isRunning) return '运行中';
    if (worker.isCompleted) return '已完成';
    if (worker.isFailedWaiting) return '待继续';
    return worker.status;
  }

  Color _dynamicRebuildWorkerColor(
    BuildContext context,
    DynamicRebuildWorkerState? worker,
  ) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (worker == null || worker.isIdle) return cs.outline;
    if (worker.isRunning) return cs.tertiary;
    if (worker.isRetrying) return cs.secondary;
    if (worker.isCompleted) return cs.primary;
    if (worker.isFailedWaiting) return cs.error;
    return cs.onSurfaceVariant;
  }

  Widget _buildDynamicRebuildStageLogsSection(
    BuildContext context,
    DynamicRebuildTaskStatus status,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> logs = status.recentLogs;
    if (logs.isEmpty) return const SizedBox.shrink();
    final int start = math.max(0, logs.length - 12);
    final List<String> visible = logs.sublist(start);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '阶段日志',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          for (final String line in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _dynamicRebuildSerialHint(DynamicRebuildTaskStatus status) {
    if (status.isPreparing || status.isPending || status.isRunning) {
      return '按天并发重建中：线程会先串行跑完当天全部动态，再领取下一个未完成日期。';
    }
    if (status.canContinue || status.isCompletedWithFailures) {
      return '继续重建只会续跑未完成或失败待续的日期，不会重新清空已完成结果。';
    }
    return '';
  }

  String _dynamicRebuildTaskLabel(DynamicRebuildTaskStatus status) {
    if (status.isIdle) return '未启动';
    if (status.isPreparing) return '准备中';
    if (status.isPending || status.isRunning) return '运行中';
    if (status.isCompleted) return '已完成';
    if (status.isCompletedWithFailures) return '部分完成';
    if (status.isFailed) return '失败';
    if (status.isCancelled) return '已停止';
    return status.status;
  }

  Color _dynamicRebuildTaskColor(DynamicRebuildTaskStatus status) {
    final cs = Theme.of(context).colorScheme;
    if (status.isCompleted) return cs.primary;
    if (status.isCompletedWithFailures) return cs.secondary;
    if (status.isPreparing || status.isPending || status.isRunning) {
      return cs.tertiary;
    }
    if (status.isFailed) return cs.error;
    if (status.isCancelled) return cs.onSurfaceVariant;
    return cs.onSurfaceVariant;
  }

  String _fmtTaskDateTime(int millis) {
    if (millis <= 0) return '(null)';
    return DateTime.fromMillisecondsSinceEpoch(millis).toString();
  }

  Future<void> _openImageGallery(
    List<Map<String, dynamic>> samples,
    int initialIndex,
  ) async {
    if (!mounted) return;
    try {
      // 尝试为查看器补充本段 AI 结构化结果（用于图片标签/描述等增强信息）
      String? aiStructuredJson;
      int? segmentIdForViewer;
      Map<String, dynamic>? aiResultSnapshot;
      try {
        final int segId = samples.isNotEmpty
            ? ((samples.first['segment_id'] as int?) ?? 0)
            : 0;
        if (segId > 0) {
          segmentIdForViewer = segId;
          final Map<String, dynamic>? result = await _db.getSegmentResult(
            segId,
          );
          if (result != null) {
            aiResultSnapshot = <String, dynamic>{
              'segment_id': result['segment_id'] ?? segId,
              'ai_provider': result['ai_provider'],
              'ai_model': result['ai_model'],
              'output_text': result['output_text'],
              'structured_json': result['structured_json'],
              'categories': result['categories'],
              'created_at': result['created_at'],
            };
          }
          final String raw =
              (result?['structured_json'] as String?)?.toString() ?? '';
          if (raw.trim().isNotEmpty) aiStructuredJson = raw;
        }
      } catch (_) {}

      // 将样本映射为 ScreenshotRecord 列表；优先从数据库补全原始记录（含 id / page_url 等）
      final List<Future<ScreenshotRecord>> futures =
          <Future<ScreenshotRecord>>[];
      for (final Map<String, dynamic> m in samples) {
        futures.add(() async {
          final String filePath = (m['file_path'] as String?) ?? '';
          if (filePath.isEmpty) {
            return ScreenshotRecord(
              id: null,
              appPackageName: (m['app_package_name'] as String?) ?? '',
              appName: (m['app_name'] as String?) ?? '',
              filePath: '',
              captureTime: DateTime.now(),
              fileSize: 0,
            );
          }
          try {
            final rec = await ScreenshotDatabase.instance.getScreenshotByPath(
              filePath,
            );
            if (rec != null) return rec;
          } catch (_) {}
          // 回退：使用样本字段快速构造
          final String pkg = (m['app_package_name'] as String?) ?? '';
          final String appName = (m['app_name'] as String?) ?? pkg;
          final int ct = (m['capture_time'] as int?) ?? 0;
          return ScreenshotRecord(
            id: null,
            appPackageName: pkg,
            appName: appName,
            filePath: filePath,
            captureTime: ct > 0
                ? DateTime.fromMillisecondsSinceEpoch(ct)
                : DateTime.now(),
            fileSize: 0,
            pageUrl: (m['page_url'] as String?)?.toString(),
            ocrText: (m['ocr_text'] as String?)?.toString(),
          );
        }());
      }
      final List<ScreenshotRecord> shots = await Future.wait(futures);
      if (shots.isEmpty) return;

      // 选定当前图片对应的 App 信息
      final int safeIndex = initialIndex < 0
          ? 0
          : (initialIndex >= shots.length ? shots.length - 1 : initialIndex);
      final Map<String, dynamic> cur = samples[safeIndex];
      final String curPkg =
          (cur['app_package_name'] as String?) ??
          shots[safeIndex].appPackageName;
      final String curAppName =
          (cur['app_name'] as String?) ?? shots[safeIndex].appName;
      final AppInfo app =
          _appInfoByPackage[curPkg] ??
          AppInfo(
            packageName: curPkg,
            appName: curAppName,
            icon: null,
            version: '',
            isSystemApp: false,
          );

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/screenshot_viewer',
        arguments: {
          'screenshots': shots,
          'initialIndex': safeIndex,
          'appName': app.appName,
          'appInfo': app,
          'multiApp': true,
          if (segmentIdForViewer != null) 'segmentId': segmentIdForViewer,
          if (aiResultSnapshot != null) 'aiResult': aiResultSnapshot,
          if (aiStructuredJson != null) 'aiStructuredJson': aiStructuredJson,
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).operationFailed)),
      );
    }
  }

  Widget _buildSamplesGrid(
    List<Map<String, dynamic>> samples, {
    Set<String> aiNsfwFiles = const <String>{},
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: samples.length,
      itemBuilder: (ctx, i) {
        final s = samples[i];
        final path = (s['file_path'] as String?) ?? '';
        final pageUrl = (s['page_url'] as String?) ?? '';

        if (path.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.image_not_supported_outlined),
            ),
          );
        }

        final String fileName = path.replaceAll('\\', '/').split('/').last;
        final bool aiNsfw = aiNsfwFiles.contains(fileName);

        return ScreenshotImageWidget(
          file: File(path),
          privacyMode: _privacyMode,
          extraNsfwMask: aiNsfw,
          pageUrl: pageUrl.isNotEmpty ? pageUrl : null,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openImageGallery(samples, i),
          showNsfwButton: true,
          errorText: 'Image Error',
        );
      },
    );
  }

  Future<void> _openDetail(Map<String, dynamic> seg) async {
    final id = (seg['id'] as int?) ?? 0;
    final samples = await _db.listSegmentSamples(id);
    final result = await _db.getSegmentResult(id);
    final Set<String> aiNsfwFiles = <String>{};
    try {
      final String raw =
          (result?['structured_json'] as String?)?.toString() ?? '';
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final rawTags = decoded['image_tags'];
          if (rawTags is List) {
            bool containsExactNsfw(dynamic tags) {
              if (tags == null) return false;
              if (tags is List) {
                return tags.any(
                  (t) => t.toString().trim().toLowerCase() == 'nsfw',
                );
              }
              if (tags is String) {
                final String tt = tags.trim();
                if (tt.isEmpty) return false;
                try {
                  final dynamic v = jsonDecode(tt);
                  if (v is List) {
                    return v.any(
                      (t) => t.toString().trim().toLowerCase() == 'nsfw',
                    );
                  }
                  if (v is String) {
                    return v
                        .split(RegExp(r'[，,;；\s]+'))
                        .any((e) => e.trim().toLowerCase() == 'nsfw');
                  }
                } catch (_) {}
                return tt
                    .split(RegExp(r'[，,;；\s]+'))
                    .any((e) => e.trim().toLowerCase() == 'nsfw');
              }
              return false;
            }

            for (final e in rawTags) {
              if (e is! Map) continue;
              final String file = (e['file'] ?? '').toString().trim();
              if (file.isEmpty) continue;
              final String fileName = file
                  .replaceAll('\\', '/')
                  .split('/')
                  .last;
              if (containsExactNsfw(e['tags'])) aiNsfwFiles.add(fileName);
            }
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (sheetCtx, ctrl) {
            final cs = Theme.of(sheetCtx).colorScheme;
            return ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusLg),
                topRight: Radius.circular(AppTheme.radiusLg),
              ),
              child: ColoredBox(
                color: cs.surface,
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Expanded(
                        child: ListView(
                          controller: ctrl,
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacing4,
                            0,
                            AppTheme.spacing4,
                            AppTheme.spacing6,
                          ),
                          children: [
                            Text(
                              AppLocalizations.of(context).timeRangeLabel(
                                '${_fmtTime((seg['start_time'] as int?) ?? 0)} - ${_fmtTime((seg['end_time'] as int?) ?? 0)}',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  AppLocalizations.of(context).statusLabel(
                                    (seg['status'] as String?) ?? '',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if ((seg['merged_flag'] as int?) == 1)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.mergedEventAccent
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).mergedEventTag,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.mergedEventAccent,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(
                                context,
                              ).samplesTitle(samples.length),
                            ),
                            const SizedBox(height: 6),
                            _buildSamplesGrid(
                              samples,
                              aiNsfwFiles: aiNsfwFiles,
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Text(
                                  AppLocalizations.of(context).aiResultTitle,
                                ),
                                const Spacer(),
                                if (result != null)
                                  IconButton(
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).copyResultsTooltip,
                                    icon: const Icon(
                                      Icons.copy_all_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () async {
                                      final text =
                                          ((result['structured_json']
                                                      as String?) ??
                                                  (result['output_text']
                                                      as String?) ??
                                                  '')
                                              .toString();
                                      if (text.isEmpty) return;
                                      await Clipboard.setData(
                                        ClipboardData(text: text),
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              context,
                                            ).copySuccess,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (result == null)
                              Text(AppLocalizations.of(context).none),
                            if (result != null) ...[
                              Builder(
                                builder: (c) {
                                  final String rawText =
                                      (result['output_text'] as String?) ?? '';
                                  final String rawJson =
                                      (result['structured_json'] as String?) ??
                                      '';
                                  Map<String, dynamic>? sj;
                                  try {
                                    final d = jsonDecode(rawJson);
                                    if (d is Map<String, dynamic>) sj = d;
                                  } catch (_) {}
                                  String? err;
                                  try {
                                    final e = sj?['error'];
                                    if (e is Map) {
                                      final m = (e['message'] ?? e['msg'] ?? '')
                                          .toString();
                                      if (m.trim().isNotEmpty) {
                                        err = m;
                                      } else {
                                        err = e.toString();
                                      }
                                    } else if (e is String &&
                                        e.trim().isNotEmpty) {
                                      err = e;
                                    }
                                  } catch (_) {}
                                  if (err == null &&
                                      rawText.trim().startsWith('{')) {
                                    try {
                                      final d2 = jsonDecode(rawText);
                                      if (d2 is Map && d2['error'] != null) {
                                        final e2 = d2['error'];
                                        if (e2 is Map &&
                                            (e2['message'] is String)) {
                                          err = e2['message'] as String;
                                        } else {
                                          err = e2.toString();
                                        }
                                      }
                                    } catch (_) {}
                                  }
                                  if (err == null) {
                                    final low = rawText.toLowerCase();
                                    if (low.contains('server_error') ||
                                        low.contains('request failed') ||
                                        low.contains(
                                          'no candidates returned',
                                        )) {
                                      err = rawText;
                                    }
                                  }
                                  if (err != null) {
                                    final cs = Theme.of(c).colorScheme;
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: cs.errorContainer,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: cs.error.withOpacity(0.6),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.error_outline,
                                                size: 16,
                                                color: cs.onErrorContainer,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: SelectableText(
                                                  err!,
                                                  style: Theme.of(c)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color:
                                                            cs.onErrorContainer,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        if (rawJson.isNotEmpty)
                                          SelectableText(
                                            rawJson,
                                            style: Theme.of(
                                              c,
                                            ).textTheme.bodySmall,
                                          ),
                                      ],
                                    );
                                  } else {
                                    final Map<String, List<String>> tagsByFile =
                                        <String, List<String>>{};
                                    final List<Map<String, String>> descGroups =
                                        <Map<String, String>>[];

                                    try {
                                      final rawTags = sj?['image_tags'];
                                      if (rawTags is List) {
                                        for (final e in rawTags) {
                                          if (e is! Map) continue;
                                          final Map<dynamic, dynamic> m = e;
                                          final String file = (m['file'] ?? '')
                                              .toString()
                                              .trim();
                                          if (file.isEmpty) continue;
                                          final raw = m['tags'];
                                          final List<String> tags = <String>[];
                                          if (raw is List) {
                                            for (final t in raw) {
                                              final v = t.toString().trim();
                                              if (v.isNotEmpty) tags.add(v);
                                            }
                                          } else if (raw is String) {
                                            tags.addAll(
                                              raw
                                                  .split(RegExp(r'[，,;；\s]+'))
                                                  .map((e) => e.trim())
                                                  .where((e) => e.isNotEmpty),
                                            );
                                          }
                                          if (tags.isNotEmpty)
                                            tagsByFile[file] = tags;
                                        }
                                      }
                                    } catch (_) {}

                                    try {
                                      final rawDescs =
                                          sj?['image_descriptions'];
                                      if (rawDescs is List) {
                                        for (final e in rawDescs) {
                                          if (e is! Map) continue;
                                          final Map<dynamic, dynamic> m = e;
                                          final String from =
                                              (m['from_file'] ??
                                                      m['from'] ??
                                                      m['start'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          final String to =
                                              (m['to_file'] ??
                                                      m['to'] ??
                                                      m['end'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          final String desc =
                                              (m['description'] ??
                                                      m['desc'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          if ((from.isEmpty && to.isEmpty) ||
                                              desc.isEmpty)
                                            continue;
                                          final String a = from.isNotEmpty
                                              ? from
                                              : to;
                                          final String b = to.isNotEmpty
                                              ? to
                                              : from;
                                          descGroups.add(<String, String>{
                                            'from': a,
                                            'to': b,
                                            'description': desc,
                                          });
                                        }
                                      }
                                    } catch (_) {}

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).modelValueLabel(
                                            (result['ai_model'] ?? '')
                                                .toString(),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        MarkdownBody(
                                          data: _normalizeMarkdownForUi(
                                            rawText,
                                          ),
                                          styleSheet:
                                              MarkdownStyleSheet.fromTheme(
                                                Theme.of(c),
                                              ).copyWith(
                                                p: Theme.of(
                                                  c,
                                                ).textTheme.bodyMedium,
                                              ),
                                          onTapLink: (text, href, title) async {
                                            if (href == null) return;
                                            final uri = Uri.tryParse(href);
                                            if (uri != null) {
                                              try {
                                                await launchUrl(
                                                  uri,
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              } catch (_) {}
                                            }
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        if (tagsByFile.isNotEmpty) ...[
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).aiImageTagsTitle,
                                            style: Theme.of(
                                              c,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 6),
                                          ...tagsByFile.entries.map((e) {
                                            final String tags = e.value.join(
                                              ' · ',
                                            );
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              child: SelectableText(
                                                '${e.key}: $tags',
                                                style: Theme.of(
                                                  c,
                                                ).textTheme.bodySmall,
                                              ),
                                            );
                                          }),
                                          const SizedBox(height: 10),
                                        ],
                                        if (descGroups.isNotEmpty) ...[
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).aiImageDescriptionsTitle,
                                            style: Theme.of(
                                              c,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 6),
                                          ...descGroups.map((g) {
                                            final String from = g['from'] ?? '';
                                            final String to = g['to'] ?? '';
                                            final String label =
                                                (from.isNotEmpty &&
                                                    to.isNotEmpty &&
                                                    from != to)
                                                ? '$from-$to'
                                                : (from.isNotEmpty ? from : to);
                                            final String desc =
                                                g['description'] ?? '';
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: SelectableText(
                                                '$label:\n$desc',
                                                style: Theme.of(
                                                  c,
                                                ).textTheme.bodySmall,
                                              ),
                                            );
                                          }),
                                          const SizedBox(height: 10),
                                        ],
                                        if (rawJson.isNotEmpty)
                                          SelectableText(rawJson),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _maybeStartAutoWatch() {
    if (!_onlyNoSummary || _autoWatching) return;
    _autoWatching = true;
    // 先触发一次原生扫描，确保后续能尽快进入工作状态
    () async {
      try {
        await _db.triggerSegmentTick();
      } catch (_) {}
    }();
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _autoPoll());
  }

  void _stopAutoWatch() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoWatching = false;
  }

  Future<void> _autoPoll() async {
    if (!_onlyNoSummary || !mounted) {
      _stopAutoWatch();
      return;
    }
    if (_loading) return;
    try {
      // 每次只做轻量查询；原生端 1s 心跳已持续推进/补救
      final String? rebuildCutoffDayKey = _dynamicRebuildTimelineCutoffDayKey();
      final List<Map<String, dynamic>> segments =
          _shouldHideTimelineUntilRebuildAdvances()
          ? const <Map<String, dynamic>>[]
          : await _db.listSegmentsEx(
              limit: 50,
              onlyNoSummary: true,
              endMillis:
                  rebuildCutoffDayKey == null || rebuildCutoffDayKey.isEmpty
                  ? null
                  : _endMillisForDateKey(rebuildCutoffDayKey),
            );
      if (!mounted) return;
      final List<String> loadedDayKeys = _orderedDayKeysFromSegments(segments);
      setState(() {
        _segments = segments;
        _loadedDayKeys = loadedDayKeys;
        _maxVisibleDayTabs = loadedDayKeys.isEmpty
            ? _initialDayTabs
            : loadedDayKeys.length;
        _noMoreOlderSegments = true;
      });
      // 若已无“暂无总结”，停止自动检测
      final hasPending = segments.any(
        (e) => (e['has_summary'] as int? ?? 0) == 0,
      );
      if (!hasPending) _stopAutoWatch();
    } catch (_) {}
  }

  void _startDynamicRebuildTaskPolling() {
    _dynamicRebuildTaskPollTimer?.cancel();
    _dynamicRebuildTaskPollTimer = Timer.periodic(const Duration(seconds: 2), (
      _,
    ) {
      // ignore: discarded_futures
      _refreshDynamicRebuildTaskStatus();
    });
  }

  Future<void> _refreshDynamicRebuildTaskStatus({
    bool refreshSegmentsOnChange = true,
  }) async {
    if (_pollingDynamicRebuildTask) return;
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad(
      'segment.rebuildStatus',
      detail: 'refreshSegmentsOnChange=$refreshSegmentsOnChange',
    );
    _pollingDynamicRebuildTask = true;
    try {
      final previous = _dynamicRebuildTaskStatus;
      final status = await _db.getDynamicRebuildTaskStatus();
      if (!mounted) return;
      setState(() {
        _dynamicRebuildTaskStatus = status;
      });
      _publishDynamicRebuildUiSnapshot();
      if (_dynamicRebuildRequestLogsEnabled && _dynamicRebuildTaskSheetOpen) {
        unawaited(_refreshDynamicRebuildRequestLogs(status: status));
      } else if (_dynamicRebuildRequestLogsState.hasAny ||
          _dynamicRebuildRequestLogsState.error != null ||
          _dynamicRebuildRequestLogsState.loading) {
        _dynamicRebuildRequestLogsState =
            const _DynamicRebuildRequestLogsState();
        _publishDynamicRebuildUiSnapshot();
      }
      if (refreshSegmentsOnChange) {
        await _handleDynamicRebuildTaskStatusChange(previous, status);
      }
      _endEntryPerfLoad(
        'segment.rebuildStatus',
        detail:
            'ms=${sw.elapsedMilliseconds} status=${status.status} active=${status.isActive}',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.rebuildStatus',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    } finally {
      _pollingDynamicRebuildTask = false;
    }
  }

  Future<void> _handleDynamicRebuildTaskStatusChange(
    DynamicRebuildTaskStatus previous,
    DynamicRebuildTaskStatus current,
  ) async {
    if (_loading) {
      DynamicEntryPerfService.instance.mark(
        'segment.rebuildStatus.refreshSkipped',
        detail:
            'loading=true prev=${previous.status} current=${current.status}',
      );
      return;
    }
    final bool justStarted = !previous.isActive && current.isActive;
    final bool progressAdvanced =
        current.isActive &&
        current.processedSegments > previous.processedSegments;
    final bool becameTerminal = previous.isActive && !current.isActive;
    final bool terminalChanged =
        previous.status != current.status &&
        (current.isCompleted ||
            current.isCompletedWithFailures ||
            current.isFailed ||
            current.isCancelled);
    final bool timelineVisibilityChanged =
        _dynamicRebuildTimelineVisibilityFingerprint(previous) !=
        _dynamicRebuildTimelineVisibilityFingerprint(current);
    if (justStarted) {
      await _refresh(triggerSegmentTick: false);
      return;
    }
    if (progressAdvanced) {
      await _refreshSegmentsForDynamicRebuildProgress();
      return;
    }
    if (timelineVisibilityChanged || becameTerminal || terminalChanged) {
      await _refresh(triggerSegmentTick: false);
    }
  }

  Future<void> _refreshSegmentsForDynamicRebuildProgress() async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDynamicRebuildListRefreshAt < 1500) return;
    _lastDynamicRebuildListRefreshAt = now;
    await _refresh(triggerSegmentTick: false);
  }

  Future<void> _confirmStartDynamicRebuild() async {
    if (_dynamicRebuildTaskStatus.isActive || _startingDynamicRebuild) return;
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: '重建动态',
      message: '会立即清空当前动态，并从最老截图开始全量重建。确定继续吗？',
      confirmText: '立即重建',
      cancelText: '取消',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _startDynamicRebuild();
  }

  Future<void> _startDynamicRebuild({bool resumeExisting = false}) async {
    if (_startingDynamicRebuild) return;
    setState(() => _startingDynamicRebuild = true);
    _publishDynamicRebuildUiSnapshot();
    try {
      final previous = _dynamicRebuildTaskStatus;
      final status = await _db.startDynamicRebuildTask(
        resumeExisting: resumeExisting,
        dayConcurrency: _selectedDynamicRebuildDayConcurrency,
      );
      if (!mounted) return;
      setState(() {
        _dynamicRebuildTaskStatus = status;
        if (status.dayConcurrency > 0) {
          _selectedDynamicRebuildDayConcurrency = math.max(
            1,
            math.min(10, status.dayConcurrency),
          );
        }
      });
      _publishDynamicRebuildUiSnapshot();
      if (status.isCompleted && status.totalSegments == 0) {
        UINotifier.info(context, '没有可重建的动态');
        await _refresh(triggerSegmentTick: false);
      } else if (status.isActive && resumeExisting) {
        final String model = status.aiModel.trim();
        UINotifier.info(
          context,
          model.isNotEmpty ? '已切换到模型 $model 继续重建' : '后台重建任务已恢复',
        );
        await _refresh(triggerSegmentTick: false);
      } else if (status.isActive && !previous.isActive) {
        UINotifier.info(context, '已在后台开始重建，可在通知栏查看进度');
        await _refresh(triggerSegmentTick: false);
      } else if (status.isActive) {
        UINotifier.info(context, '后台重建任务已恢复');
      }
    } catch (e) {
      if (mounted) {
        await UIDialogs.showInfo(
          context,
          title: '动态重建失败',
          message: e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _startingDynamicRebuild = false);
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }

  Future<void> _continueDynamicRebuild() async {
    await _startDynamicRebuild(resumeExisting: true);
  }

  Future<void> _cancelDynamicRebuild() async {
    if (_stoppingDynamicRebuild) return;
    setState(() => _stoppingDynamicRebuild = true);
    _publishDynamicRebuildUiSnapshot();
    try {
      final status = await _db.cancelDynamicRebuildTask();
      if (!mounted) return;
      setState(() => _dynamicRebuildTaskStatus = status);
      _publishDynamicRebuildUiSnapshot();
      UINotifier.info(context, '动态重建已停止');
      await _refresh(triggerSegmentTick: false);
    } catch (_) {
      if (mounted) {
        UINotifier.error(context, '停止动态重建失败');
      }
    } finally {
      if (mounted) {
        setState(() => _stoppingDynamicRebuild = false);
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }

  @override
  void dispose() {
    if (_trackEntryPerf) {
      DynamicEntryPerfService.instance.finish(
        'segment.dispose',
        detail: 'disposedBeforeComplete',
      );
      _trackEntryPerf = false;
    }
    _stopAutoWatch();
    _dynamicRebuildTaskPollTimer?.cancel();
    _dynamicRebuildIconController.dispose();
    _dynamicRebuildUiSnapshotNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: _segmentStatusLeadingWidth(context),
        leading: _buildSegmentStatusLeading(context),
        title: _buildSegmentsProviderModelAppBarTitle(),
        actions: [
          IconButton(
            icon: RotationTransition(
              turns: _dynamicRebuildIconController,
              child: Icon(
                Icons.autorenew_rounded,
                color: _dynamicRebuildTaskColor(_dynamicRebuildTaskStatus),
              ),
            ),
            tooltip: '重建动态',
            onPressed: _openDynamicRebuildTaskSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).actionRefresh,
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _SegmentTimelineTabView(
          segments: _segments,
          onlyNoSummary: _onlyNoSummary,
          autoWatching: _autoWatching,
          appInfoByPackage: _appInfoByPackage,
          fmtTime: _fmtTime,
          loadSamples: (id) => _db.listSegmentSamples(id),
          loadResult: (id) => _db.getSegmentResult(id),
          onOpenDetail: (seg) => _openDetail(seg),
          openGallery: (samples, index) => _openImageGallery(samples, index),
          activeHeader: _buildHeaderStack(),
          hasActiveHeader: _active != null,
          onRefreshRequested: _refresh,
          privacyMode: _privacyMode,
          dynamicRebuildActive: _dynamicRebuildTaskStatus.isActive,
          maxVisibleDayTabs: _maxVisibleDayTabs,
          selectedDateKey: _selectedDateKey,
          isLoadingMoreDays: _isLoadingMoreDays,
          noMoreOlderSegments: _noMoreOlderSegments,
          onLastDayTabReached: _handleLastDayTabReached,
          onActiveDateChanged: (dateKey) {
            if (!mounted || _selectedDateKey == dateKey) return;
            setState(() {
              _selectedDateKey = dateKey;
            });
          },
        ),
      ),
    );
  }
}

/// 将毫秒时间戳转换为日期 key（YYYY-MM-DD）
String _dateKeyFromMillis(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final String y = dt.year.toString().padLeft(4, '0');
  final String m = dt.month.toString().padLeft(2, '0');
  final String d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

// ============= 按日期 Tab 的段落时间轴视图（含分割线/关键动作/Logo/标签/摘要/可展开图片） =============
class _SegmentTimelineTabView extends StatefulWidget {
  final List<Map<String, dynamic>> segments;
  final bool onlyNoSummary;
  final bool autoWatching;
  final Map<String, AppInfo> appInfoByPackage;
  final String Function(int) fmtTime;
  final Future<List<Map<String, dynamic>>> Function(int) loadSamples;
  final Future<Map<String, dynamic>?> Function(int) loadResult;
  final void Function(Map<String, dynamic>) onOpenDetail;
  final Future<void> Function(List<Map<String, dynamic>>, int) openGallery;
  final Widget activeHeader;
  final bool hasActiveHeader;
  final Future<void> Function() onRefreshRequested;
  final bool privacyMode;
  final bool dynamicRebuildActive;
  final int maxVisibleDayTabs;
  final String? selectedDateKey;
  final bool isLoadingMoreDays;
  final bool noMoreOlderSegments;
  final Future<void> Function()? onLastDayTabReached;
  final ValueChanged<String?>? onActiveDateChanged;

  const _SegmentTimelineTabView({
    required this.segments,
    required this.onlyNoSummary,
    required this.autoWatching,
    required this.appInfoByPackage,
    required this.fmtTime,
    required this.loadSamples,
    required this.loadResult,
    required this.onOpenDetail,
    required this.openGallery,
    required this.activeHeader,
    required this.hasActiveHeader,
    required this.onRefreshRequested,
    required this.privacyMode,
    required this.dynamicRebuildActive,
    required this.maxVisibleDayTabs,
    this.selectedDateKey,
    required this.isLoadingMoreDays,
    required this.noMoreOlderSegments,
    this.onLastDayTabReached,
    this.onActiveDateChanged,
  });

  @override
  State<_SegmentTimelineTabView> createState() =>
      _SegmentTimelineTabViewState();
}

class _SegmentTimelineTabViewState extends State<_SegmentTimelineTabView>
    with SingleTickerProviderStateMixin {
  static const int _autoLoadThreshold = 3;

  TabController? _tabController;
  List<String> _orderedKeys = const <String>[];
  String? _lastReportedDateKey;
  String? _lastAutoLoadTriggerKey;
  bool _autoLoadCheckQueued = false;

  void _handleTabSelectionChanged() {
    if (!mounted) return;
    _reportActiveDateKey();
    _queueAutoLoadCheck();
  }

  int _desiredTabIndex(List<String> ordered, int fallbackIndex) {
    if (ordered.isEmpty) return 0;
    final String selectedDateKey = (widget.selectedDateKey ?? '').trim();
    if (selectedDateKey.isNotEmpty) {
      final int selectedIndex = ordered.indexOf(selectedDateKey);
      if (selectedIndex >= 0) return selectedIndex;
      return 0;
    }
    return fallbackIndex.clamp(0, ordered.length - 1);
  }

  void _queueAutoLoadCheck() {
    if (_autoLoadCheckQueued) return;
    _autoLoadCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadCheckQueued = false;
      if (!mounted) return;
      _maybeAutoLoadOlderDays();
    });
  }

  void _maybeAutoLoadOlderDays() {
    if (widget.onlyNoSummary ||
        widget.onLastDayTabReached == null ||
        widget.isLoadingMoreDays ||
        widget.noMoreOlderSegments) {
      return;
    }
    final TabController? controller = _tabController;
    if (controller == null || _orderedKeys.isEmpty) return;
    final int remainingTabs = _orderedKeys.length - 1 - controller.index;
    if (remainingTabs >= _autoLoadThreshold) return;
    final String triggerKey = _orderedKeys.last;
    if (_lastAutoLoadTriggerKey == triggerKey) return;
    _lastAutoLoadTriggerKey = triggerKey;
    unawaited(widget.onLastDayTabReached!.call());
  }

  void _reportActiveDateKey() {
    final TabController? controller = _tabController;
    String? nextDateKey;
    if (controller != null &&
        _orderedKeys.isNotEmpty &&
        controller.index >= 0 &&
        controller.index < _orderedKeys.length) {
      nextDateKey = _orderedKeys[controller.index];
    }
    if (_lastReportedDateKey == nextDateKey) return;
    _lastReportedDateKey = nextDateKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onActiveDateChanged?.call(nextDateKey);
    });
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabSelectionChanged);
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> segments = widget.segments;

    if (segments.isEmpty) {
      _orderedKeys = const <String>[];
      _reportActiveDateKey();
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing4,
              vertical: AppTheme.spacing1,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (widget.hasActiveHeader) widget.activeHeader,
                  if (widget.hasActiveHeader &&
                      widget.onlyNoSummary &&
                      widget.autoWatching)
                    const SizedBox(height: 8),
                  if (widget.onlyNoSummary && widget.autoWatching)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        AppLocalizations.of(context).autoWatchingHint,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing6,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_note_outlined,
                      size: 64,
                      color: AppTheme.mutedForeground.withOpacity(0.5),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      AppLocalizations.of(context).noEvents,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.mutedForeground,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        AppLocalizations.of(context).noEventsSubtitle,
                        style: const TextStyle(color: AppTheme.mutedForeground),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final seg in segments) {
      final k = _dateKeyFromMillis((seg['start_time'] as int?) ?? 0);
      grouped.putIfAbsent(k, () => <Map<String, dynamic>>[]).add(seg);
    }
    final List<String> keys = grouped.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    final List<String> orderedAll = keys.reversed.toList();

    // 仅展示当前已加载批次中的日期；默认模式下 maxVisibleDayTabs 会与已加载日期数保持一致。
    final int desiredTabs = widget.maxVisibleDayTabs <= 0
        ? 1
        : widget.maxVisibleDayTabs;
    final int visibleCount = math.min(desiredTabs, orderedAll.length);
    final List<String> ordered = orderedAll.take(visibleCount).toList();
    final List<String> previousOrderedKeys = _orderedKeys;
    final TabController? oldController = _tabController;
    final int oldIndex = oldController?.index ?? 0;
    final String? currentDateKey =
        oldController != null &&
            previousOrderedKeys.isNotEmpty &&
            oldIndex >= 0 &&
            oldIndex < previousOrderedKeys.length
        ? previousOrderedKeys[oldIndex]
        : null;
    _orderedKeys = ordered;

    int fallbackIndex = 0;
    if (ordered.isNotEmpty) {
      if (currentDateKey != null) {
        final int currentKeyIndex = ordered.indexOf(currentDateKey);
        fallbackIndex = currentKeyIndex >= 0
            ? currentKeyIndex
            : oldIndex.clamp(0, ordered.length - 1);
      } else {
        fallbackIndex = oldIndex.clamp(0, ordered.length - 1);
      }
    }
    final int desiredIndex = _desiredTabIndex(ordered, fallbackIndex);
    final bool shouldRecreateController =
        _tabController == null ||
        _tabController!.length != ordered.length ||
        _tabController!.index != desiredIndex;
    if (shouldRecreateController) {
      _tabController?.removeListener(_handleTabSelectionChanged);
      _tabController?.dispose();
      _tabController = TabController(
        length: ordered.length,
        vsync: this,
        initialIndex: desiredIndex,
      );
      _tabController!.addListener(_handleTabSelectionChanged);
    }
    _reportActiveDateKey();
    _queueAutoLoadCheck();

    return Column(
      children: [
        if (widget.hasActiveHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacing4,
              AppTheme.spacing1,
              AppTheme.spacing4,
              0,
            ),
            child: widget.activeHeader,
          ),
          const SizedBox(height: 8),
        ],
        Builder(
          builder: (context) {
            final bool showLoadMoreButton =
                !widget.onlyNoSummary &&
                widget.onLastDayTabReached != null &&
                !widget.noMoreOlderSegments;
            final bool isLoadingMore = widget.isLoadingMoreDays;
            return SizedBox(
              height: 32,
              child: Transform.translate(
                offset: const Offset(0, -2),
                child: Row(
                  children: [
                    Expanded(
                      child: ScreenshotStyleTabBar(
                        controller: _tabController,
                        // 与截图列表一致：左侧少量起始内边距，去除额外垂直内边距
                        padding: const EdgeInsets.only(left: AppTheme.spacing2),
                        // 与截图列表一致：标签水平留白适中
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        indicatorInsets: const EdgeInsets.symmetric(
                          horizontal: 4.0,
                        ),
                        tabs: [
                          for (final k in ordered)
                            Tab(
                              text: (() {
                                final parts = k.split('-');
                                if (parts.length == 3) {
                                  final y = int.tryParse(parts[0]) ?? 1970;
                                  final m = int.tryParse(parts[1]) ?? 1;
                                  final d = int.tryParse(parts[2]) ?? 1;
                                  final dt = DateTime(y, m, d);
                                  final now = DateTime.now();
                                  bool sameDay(DateTime a, DateTime b) =>
                                      a.year == b.year &&
                                      a.month == b.month &&
                                      a.day == b.day;
                                  final int c =
                                      (grouped[k] ??
                                              const <Map<String, dynamic>>[])
                                          .length;
                                  final l10n = AppLocalizations.of(context);
                                  if (sameDay(dt, now))
                                    return l10n.dayTabToday(c);
                                  if (sameDay(
                                    dt,
                                    now.subtract(const Duration(days: 1)),
                                  )) {
                                    return l10n.dayTabYesterday(c);
                                  }
                                  return l10n.dayTabMonthDayCount(
                                    dt.month,
                                    dt.day,
                                    c,
                                  );
                                }
                                return '$k ${(grouped[k] ?? const <Map<String, dynamic>>[]).length}';
                              })(),
                            ),
                        ],
                      ),
                    ),
                    if (showLoadMoreButton)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: isLoadingMore
                            ? const Padding(
                                padding: EdgeInsets.only(
                                  left: AppTheme.spacing2,
                                  right: AppTheme.spacing1,
                                ),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final k in ordered)
                ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing4,
                    vertical: AppTheme.spacing1,
                  ),
                  children: [
                    ...List.generate(
                      (grouped[k] ?? const <Map<String, dynamic>>[]).length,
                      (i) => _SegmentEntryCard(
                        segment: grouped[k]![i],
                        isLast: i == grouped[k]!.length - 1,
                        fmtTime: widget.fmtTime,
                        loadSamples: widget.loadSamples,
                        loadResult: widget.loadResult,
                        appInfoByPackage: widget.appInfoByPackage,
                        onOpenDetail: () => widget.onOpenDetail(grouped[k]![i]),
                        openGallery: widget.openGallery,
                        onRefreshRequested: widget.onRefreshRequested,
                        privacyMode: widget.privacyMode,
                        dynamicRebuildActive: widget.dynamicRebuildActive,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SegmentEntryCard extends StatefulWidget {
  final Map<String, dynamic> segment;
  final bool isLast;
  final String Function(int) fmtTime;
  final Future<List<Map<String, dynamic>>> Function(int) loadSamples;
  final Future<Map<String, dynamic>?> Function(int) loadResult;
  final Map<String, AppInfo> appInfoByPackage;
  final VoidCallback onOpenDetail;
  final Future<void> Function(List<Map<String, dynamic>>, int) openGallery;
  final Future<void> Function() onRefreshRequested;
  final bool privacyMode;
  final bool dynamicRebuildActive;

  const _SegmentEntryCard({
    required this.segment,
    required this.isLast,
    required this.fmtTime,
    required this.loadSamples,
    required this.loadResult,
    required this.appInfoByPackage,
    required this.onOpenDetail,
    required this.openGallery,
    required this.onRefreshRequested,
    required this.privacyMode,
    required this.dynamicRebuildActive,
  });

  @override
  State<_SegmentEntryCard> createState() => _SegmentEntryCardState();
}

class _SegmentEntryCardState extends State<_SegmentEntryCard> {
  static const int _tagMaxVisibleRows = 2;
  static const double _tagChipMinHeight = 20;
  static const double _tagChipVerticalPadding = 2;
  static const double _tagOverflowHintHeight = 18;
  static const double _tagGridMainAxisSpacing = 6;
  static const double _tagGridCrossAxisSpacing = 6;
  static const int _thumbGridCrossAxisCount = 3;
  static const double _thumbGridSpacing = 2;
  static const double _thumbVirtualGridMaxHeight = 360;
  static const String _summaryGeneratingPlaceholder = '模型正在思考，请稍候…';
  static const int _autoRetryRememberCap = 2048;
  static final Set<int> _autoRetryTriggeredSegmentIds = <int>{};

  final ScrollController _tagScrollController = ScrollController();

  bool _expanded = false;
  // 懒加载样本的本地状态，避免每项滚动时触发异步查询导致跳动
  bool _samplesLoading = false;
  bool _samplesLoaded = false;
  List<Map<String, dynamic>> _samples = const <Map<String, dynamic>>[];
  // 摘要展开/收起状态（防止固定高度无法展开）
  bool _summaryExpanded = false;
  // 重新生成操作状态
  bool _retrying = false;
  // 强制合并操作状态
  bool _forcingMerge = false;
  // 结果轮询器：点击“重新生成”后，直到拿到结果为止持续旋转提示
  Timer? _resultWatchTimer;
  Timer? _mergeWatchTimer;
  Timer? _summaryStreamTimer;
  Map<String, dynamic> _segmentData = <String, dynamic>{};
  Map<String, dynamic> _latestExternalSegment = <String, dynamic>{};
  int? _lastResultCreatedAt;
  int? _lastMergeResultCreatedAt;
  bool _summaryStreaming = false;
  String _summaryStreamingText = '';

  @override
  void initState() {
    super.initState();
    _segmentData = Map<String, dynamic>.from(widget.segment);
    _latestExternalSegment = Map<String, dynamic>.from(widget.segment);
  }

  @override
  void didUpdateWidget(covariant _SegmentEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = Map<String, dynamic>.from(widget.segment);
    if (!mapEquals(incoming, _latestExternalSegment)) {
      _latestExternalSegment = Map<String, dynamic>.from(incoming);
      _segmentData = Map<String, dynamic>.from(incoming);
    }
  }

  @override
  void dispose() {
    _resultWatchTimer?.cancel();
    _mergeWatchTimer?.cancel();
    _summaryStreamTimer?.cancel();
    _tagScrollController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _segmentWithoutResult(Map<String, dynamic> source) {
    final next = Map<String, dynamic>.from(source);
    next['output_text'] = null;
    next['structured_json'] = null;
    next['categories'] = null;
    next['has_summary'] = 0;
    return next;
  }

  Map<String, dynamic> _mergeResultIntoSegment(
    Map<String, dynamic> base,
    Map<String, dynamic> result,
  ) {
    final next = Map<String, dynamic>.from(base);
    next['output_text'] = result['output_text'];
    next['structured_json'] = result['structured_json'];
    next['categories'] = result['categories'];
    next['has_summary'] = 1;
    return next;
  }

  static void _markAutoRetryTriggered(int segmentId) {
    _autoRetryTriggeredSegmentIds.add(segmentId);
    // Prevent unbounded growth in long sessions.
    while (_autoRetryTriggeredSegmentIds.length > _autoRetryRememberCap) {
      _autoRetryTriggeredSegmentIds.remove(_autoRetryTriggeredSegmentIds.first);
    }
  }

  bool _isNonEmptyJsonLike(String? s) {
    final String t = (s ?? '').trim();
    if (t.isEmpty) return false;
    return t.toLowerCase() != 'null';
  }

  String _extractJsonStringValueFromRaw(String raw, String key) {
    final String s = raw;
    if (s.isEmpty) return '';

    int idx = s.indexOf('"$key"');
    if (idx < 0) return '';
    idx = s.indexOf(':', idx);
    if (idx < 0) return '';
    idx++;

    // Skip whitespace.
    while (idx < s.length) {
      final int cu = s.codeUnitAt(idx);
      if (cu == 32 || cu == 9 || cu == 10 || cu == 13) {
        idx++;
        continue;
      }
      break;
    }
    if (idx >= s.length || s[idx] != '"') return '';

    // Extract the JSON string literal without requiring the full JSON object to be valid.
    final int start = idx;
    idx++;
    bool escaped = false;
    for (; idx < s.length; idx++) {
      final int cu = s.codeUnitAt(idx);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (cu == 92 /* \ */ ) {
        escaped = true;
        continue;
      }
      if (cu == 34 /* " */ ) {
        final String literal = s.substring(start, idx + 1);
        try {
          final dynamic v = jsonDecode(literal);
          if (v is String) return v.trim();
        } catch (_) {
          return '';
        }
        return '';
      }
    }
    return '';
  }

  String _extractOverallSummaryFromRawStructuredJson(String? raw) {
    final String t = (raw ?? '').trim();
    if (t.isEmpty) return '';
    if (t.toLowerCase() == 'null') return '';
    return _extractJsonStringValueFromRaw(t, 'overall_summary');
  }

  void _maybeAutoRetryInvalidStructuredJson({
    required int segmentId,
    required String? structuredJsonRaw,
    required bool structuredJsonTruncated,
  }) {
    if (segmentId <= 0) return;
    if (_retrying) return;
    if (structuredJsonTruncated)
      return; // likely truncated for CursorWindow fallback
    if (!_isNonEmptyJsonLike(structuredJsonRaw)) return;
    if (_autoRetryTriggeredSegmentIds.contains(segmentId)) return;
    _markAutoRetryTriggered(segmentId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Best-effort: kick a forced regeneration so native can re-produce a valid structured_json.
      // This is intentionally silent to avoid spamming snackbars during scrolling.
      // ignore: unawaited_futures
      _autoRetry(segmentId);
    });
  }

  Future<void> _autoRetry(int segmentId) async {
    final int id = segmentId;
    if (id <= 0 || _retrying) return;
    int maxRetries = 1;
    try {
      maxRetries = await AISettingsService.instance
          .getSegmentsJsonAutoRetryMax();
    } catch (_) {}
    if (maxRetries <= 0) {
      _autoRetryTriggeredSegmentIds.remove(id);
      return;
    }

    final previous = Map<String, dynamic>.from(_segmentData);
    int? previousCreatedAt = _lastResultCreatedAt;
    try {
      final prevRes = await widget.loadResult(id);
      final loaded = (prevRes?['created_at'] as int?) ?? 0;
      if (loaded > 0) previousCreatedAt = loaded;
    } catch (_) {}
    if (!mounted) return;

    setState(() {
      _retrying = true;
      _segmentData = _segmentWithoutResult(previous);
      _lastResultCreatedAt = previousCreatedAt;
      _summaryStreaming = true;
      _summaryStreamingText = _summaryGeneratingPlaceholder;
    });
    try {
      // Auto-retry should overwrite the existing invalid result.
      final n = await ScreenshotDatabase.instance.retrySegments([
        id,
      ], force: true);
      if (!mounted) return;
      final ok = n > 0;
      if (ok) {
        _startResultWatch(id, notifyToast: false);
      } else {
        // Not queued: revert UI state so we don't spin forever.
        setState(() {
          _retrying = false;
          _segmentData = Map<String, dynamic>.from(previous);
          _lastResultCreatedAt = previousCreatedAt;
          _summaryStreaming = false;
          _summaryStreamingText = '';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _segmentData = Map<String, dynamic>.from(previous);
        _lastResultCreatedAt = previousCreatedAt;
        _summaryStreaming = false;
        _summaryStreamingText = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int id = (_segmentData['id'] as int?) ?? 0;
    final bool isZh = (() {
      try {
        return Localizations.localeOf(
          context,
        ).languageCode.toLowerCase().startsWith('zh');
      } catch (_) {
        return true;
      }
    })();
    // 移除 per-item FutureBuilder，使用后端联表元数据；展开时懒加载样本
    final int sampleCount = (_segmentData['sample_count'] as int?) ?? 0;
    final int start = (_segmentData['start_time'] as int?) ?? 0;
    final int end = (_segmentData['end_time'] as int?) ?? 0;
    final String timeLabel =
        '${widget.fmtTime(start)} - ${widget.fmtTime(end)}';
    final bool merged = (_segmentData['merged_flag'] as int?) == 1;
    final String status = (_segmentData['status'] as String?) ?? '';
    final bool mergeAttempted = (_segmentData['merge_attempted'] as int?) == 1;
    final bool mergeForced = (_segmentData['merge_forced'] as int?) == 1;
    final int mergePrevId = (_segmentData['merge_prev_id'] as int?) ?? 0;
    final String mergeReason =
        (_segmentData['merge_decision_reason'] as String?)?.trim() ?? '';

    final Map<String, dynamic> resultMeta = {
      'categories': _segmentData['categories'],
      'output_text': _segmentData['output_text'],
    };
    final String? structuredJsonRaw =
        (_segmentData['structured_json'] as String?)?.toString();
    final Map<String, dynamic>? structured = _tryParseJson(structuredJsonRaw);
    final bool structuredJsonTruncated =
        (_segmentData['structured_json_truncated'] as int? ?? 0) != 0;
    final bool structuredJsonParseFailed =
        _isNonEmptyJsonLike(structuredJsonRaw) && structured == null;
    if (structuredJsonParseFailed) {
      _maybeAutoRetryInvalidStructuredJson(
        segmentId: id,
        structuredJsonRaw: structuredJsonRaw,
        structuredJsonTruncated: structuredJsonTruncated,
      );
    }
    final Set<String> aiNsfwFiles = <String>{};
    try {
      final rawTags = structured?['image_tags'];
      if (rawTags is List) {
        bool containsExactNsfw(dynamic tags) {
          if (tags == null) return false;
          if (tags is List) {
            return tags.any((t) => t.toString().trim().toLowerCase() == 'nsfw');
          }
          if (tags is String) {
            final String tt = tags.trim();
            if (tt.isEmpty) return false;
            try {
              final dynamic v = jsonDecode(tt);
              if (v is List) {
                return v.any(
                  (t) => t.toString().trim().toLowerCase() == 'nsfw',
                );
              }
              if (v is String) {
                return v
                    .split(RegExp(r'[，,;；\s]+'))
                    .any((e) => e.trim().toLowerCase() == 'nsfw');
              }
            } catch (_) {}
            return tt
                .split(RegExp(r'[，,;；\s]+'))
                .any((e) => e.trim().toLowerCase() == 'nsfw');
          }
          return false;
        }

        for (final e in rawTags) {
          if (e is! Map) continue;
          final String file = (e['file'] ?? '').toString().trim();
          if (file.isEmpty) continue;
          final String fileName = file.replaceAll('\\', '/').split('/').last;
          if (containsExactNsfw(e['tags'])) aiNsfwFiles.add(fileName);
        }
      }
    } catch (_) {}
    final String? keyAction = _extractKeyActionDetail(structured);
    final int aiRetryCount = _aiRetryCount(structured);
    final bool aiRetryFailed = _aiNeedsManualRetry(structured);
    final String aiRetryMsg = _aiRetryMessage(context, structured);
    final List<String> categories = _extractCategories(resultMeta, structured);
    String computedSummary = _extractOverallSummary(structured);
    if (computedSummary.isEmpty) {
      computedSummary = _extractOverallSummaryFromRawStructuredJson(
        structuredJsonRaw,
      );
    }
    if (computedSummary.isEmpty &&
        structuredJsonTruncated &&
        ((_segmentData['has_summary'] as int?) ?? 0) != 0) {
      computedSummary = isZh
          ? '摘要过长，请进入详情查看'
          : 'Summary is too long. Open details to view.';
    }
    final String summary = _summaryStreaming
        ? (_summaryStreamingText.isEmpty
              ? _summaryGeneratingPlaceholder
              : _summaryStreamingText)
        : computedSummary;
    final List<String> mergedParts = merged
        ? splitMergedEventSummaryParts(summary)
        : const <String>[];
    final String displaySummary = mergedParts.isNotEmpty
        ? mergedParts.first
        : summary;
    final List<String> originalSummaries = mergedParts.length > 1
        ? mergedParts.sublist(1)
        : const <String>[];

    // 错误检测：从 structured_json.error / output_text(JSON) / 关键字启发式 识别错误
    String? errorText;
    final String outputRaw =
        (resultMeta['output_text'] as String?)?.toString() ?? '';

    // 1) structured_json.error
    try {
      final err = structured?['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['msg'] ?? '').toString();
        if (msg.trim().isNotEmpty) {
          errorText = msg;
        } else {
          errorText = err.toString();
        }
      } else if (err is String && err.trim().isNotEmpty) {
        errorText = err;
      }
    } catch (_) {}

    // 2) output_text 若为 JSON 且含 error
    if (errorText == null &&
        outputRaw.isNotEmpty &&
        outputRaw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(outputRaw);
        if (decoded is Map && decoded['error'] != null) {
          final e = decoded['error'];
          if (e is Map && (e['message'] is String)) {
            errorText = (e['message'] as String);
          } else {
            errorText = e.toString();
          }
        }
      } catch (_) {}
    }

    // 3) 关键字启发式
    if (errorText == null) {
      final low = outputRaw.toLowerCase();
      if (low.contains('server_error') ||
          low.contains('request failed') ||
          low.contains('no candidates returned')) {
        errorText = outputRaw;
      }
    }

    Widget _buildErrorBanner(String text) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.error.withOpacity(0.6), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: cs.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

    // 包名：优先使用后端汇总的 app_packages_display，其次 app_packages（保证首屏就能显示 Logo）
    List<String> packages = <String>[];
    final String? appPkgsDisplay =
        _segmentData['app_packages_display'] as String?;
    final String? appPkgsRaw = _segmentData['app_packages'] as String?;
    final String? pkgSrc =
        (appPkgsDisplay != null && appPkgsDisplay.trim().isNotEmpty)
        ? appPkgsDisplay
        : appPkgsRaw;
    if (pkgSrc != null && pkgSrc.trim().isNotEmpty) {
      packages = pkgSrc
          .split(RegExp(r'[,\s]+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timeSeparator(
            context,
            label: timeLabel,
            keyActionDetail: keyAction,
            aiRetried: aiRetryCount > 0,
            aiRetryFailed: aiRetryFailed,
            aiRetryMessage: aiRetryMsg,
          ),
          const SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: packages
                    .map((pkg) => _buildAppIcon(context, pkg))
                    .toList(),
              ),
              const SizedBox(height: 8),
              _buildCategorySection(context, categories, merged),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 6),
            _buildErrorBanner(errorText!),
          ] else if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            // 根据是否超出行数动态决定是否显示“展开/收起”
            LayoutBuilder(
              builder: (context, constraints) {
                final TextStyle? textStyle = Theme.of(
                  context,
                ).textTheme.bodyMedium;
                // 仅在收起状态下检测是否溢出
                bool overflow = false;
                if (!_summaryExpanded && textStyle != null) {
                  final tp = TextPainter(
                    text: TextSpan(text: displaySummary, style: textStyle),
                    maxLines: 7,
                    ellipsis: '…',
                    textDirection: Directionality.of(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  overflow = tp.didExceedMaxLines;
                }

                // 预估 7 行高度用于折叠时裁切
                final double lineHeight =
                    (textStyle?.height ?? 1.2) * (textStyle?.fontSize ?? 14.0);
                final double collapsedHeight = lineHeight * 7.0 + 2.0;

                final md = _buildMarkdownBody(
                  context,
                  displaySummary,
                  textStyle,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryExpanded
                        ? md
                        : ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: collapsedHeight,
                            ),
                            child: ClipRect(child: md),
                          ),
                    if (overflow || _summaryExpanded)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(
                            () => _summaryExpanded = !_summaryExpanded,
                          ),
                          child: Text(
                            _summaryExpanded
                                ? AppLocalizations.of(context).collapse
                                : AppLocalizations.of(context).expandMore,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (status == 'completed' &&
              (mergeAttempted ||
                  mergeForced ||
                  mergeReason.isNotEmpty ||
                  _forcingMerge ||
                  merged)) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                final TextStyle? titleStyle = Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
                final TextStyle? reasonStyle = Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);

                final String state = _forcingMerge
                    ? '强制合并中…'
                    : (merged
                          ? '已合并'
                          : (mergeForced
                                ? (mergeAttempted ? '强制合并失败' : '已请求强制合并')
                                : (mergeAttempted ? '未合并' : '待判定')));
                final String reasonText = mergeReason.isNotEmpty
                    ? mergeReason
                    : (_forcingMerge ? '正在合并，请稍候…' : '');
                final bool canForce =
                    !_forcingMerge &&
                    !merged &&
                    mergeAttempted &&
                    mergePrevId > 0;

                return _buildMergeStatusDropdown(
                  context,
                  segmentId: id,
                  state: state,
                  reasonText: reasonText,
                  titleStyle: titleStyle,
                  reasonStyle: reasonStyle,
                  canForce: canForce,
                  originalSummaries: originalSummaries,
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: sampleCount <= 0
                    ? null
                    : () async {
                        setState(() => _expanded = !_expanded);
                        if (_expanded && !_samplesLoaded && !_samplesLoading) {
                          setState(() => _samplesLoading = true);
                          try {
                            final loaded = await widget.loadSamples(id);
                            setState(() {
                              _samples = loaded;
                              _samplesLoaded = true;
                            });
                          } catch (_) {
                          } finally {
                            if (mounted)
                              setState(() => _samplesLoading = false);
                          }
                        }
                      },
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  _expanded
                      ? AppLocalizations.of(
                          context,
                        ).hideImagesCount(sampleCount)
                      : AppLocalizations.of(
                          context,
                        ).viewImagesCount(sampleCount),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: widget.dynamicRebuildActive
                    ? '全量重建进行中，已禁止单条重新生成'
                    : AppLocalizations.of(context).actionRegenerate,
                onPressed: (_retrying || widget.dynamicRebuildActive)
                    ? null
                    : () async {
                        await _retry();
                      },
                icon: _retrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined, size: 18),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: AppLocalizations.of(context).actionCopy,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  final l10n = AppLocalizations.of(context);
                  final buffer = StringBuffer()
                    ..writeln(l10n.timeRangeLabel(timeLabel))
                    ..writeln(l10n.statusLabel(status));
                  if (merged) buffer.writeln(l10n.tagMergedCopy);
                  if (categories.isNotEmpty)
                    buffer.writeln(l10n.categoriesLabel(categories.join(', ')));
                  if (errorText != null && errorText!.trim().isNotEmpty) {
                    buffer.writeln(l10n.errorLabel(errorText!));
                  } else if (summary.trim().isNotEmpty) {
                    buffer.writeln(l10n.summaryLabel(summary));
                  }
                  await Clipboard.setData(
                    ClipboardData(text: buffer.toString()),
                  );
                  if (!mounted) return;
                  UINotifier.success(
                    context,
                    AppLocalizations.of(context).copySuccess,
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip:
                    Localizations.localeOf(
                      context,
                    ).languageCode.toLowerCase().startsWith('zh')
                    ? '请求/响应'
                    : 'Request/Response',
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                onPressed: () async {
                  await _showAiRequestResponseSheet(id, timeLabel: timeLabel);
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: AppLocalizations.of(context).deleteEventTooltip,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  await _confirmAndDelete();
                },
              ),
            ],
          ),
          // 关键图片 UI 暂时隐藏：仅移除展示，不影响功能数据
          if (_expanded)
            (_samplesLoading
                ? const SizedBox(
                    height: 60,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : (_samples.isNotEmpty
                      ? _buildThumbGrid(
                          context,
                          _samples,
                          aiNsfwFiles: aiNsfwFiles,
                        )
                      : const SizedBox.shrink())),
          if (!widget.isLast) ...[
            const SizedBox(height: AppTheme.spacing3),
            _buildSeparator(context),
            const SizedBox(height: AppTheme.spacing3),
          ],
        ],
      ),
    );
  }

  // 时间居中 + 下一行展示关键动作（不使用分割线）
  Widget _timeSeparator(
    BuildContext context, {
    required String label,
    String? keyActionDetail,
    bool aiRetried = false,
    bool aiRetryFailed = false,
    String? aiRetryMessage,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color actionColor = AppTheme.mergedEventAccent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: Stack(
            children: [
              Center(
                child: Text(label, style: DefaultTextStyle.of(context).style),
              ),
              if (aiRetried)
                Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    message: (aiRetryMessage ?? '').trim().isNotEmpty
                        ? aiRetryMessage!
                        : (aiRetryFailed
                              ? AppLocalizations.of(
                                  context,
                                ).aiResultAutoRetryFailedHint
                              : AppLocalizations.of(
                                  context,
                                ).aiResultAutoRetriedHint),
                    child: Icon(
                      aiRetryFailed
                          ? Icons.error_outline_rounded
                          : Icons.info_outline_rounded,
                      size: 16,
                      color: aiRetryFailed ? colorScheme.error : actionColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (keyActionDetail != null && keyActionDetail.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Center(
              child: _buildMarkdownBody(
                context,
                keyActionDetail,
                DefaultTextStyle.of(context).style.copyWith(color: actionColor),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openMergedOriginalEventsDrawer(
    BuildContext context, {
    required List<String> originals,
  }) async {
    if (originals.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final TextStyle? bodyStyle = Theme.of(ctx).textTheme.bodyMedium;
        final cs = Theme.of(ctx).colorScheme;

        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusLg),
            topRight: Radius.circular(AppTheme.radiusLg),
          ),
          child: ColoredBox(
            color: cs.surface,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.78,
                child: DefaultTabController(
                  length: originals.length,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      ScreenshotStyleTabBar(
                        height: kTextTabBarHeight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing3,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        tabs: [
                          for (int i = 0; i < originals.length; i++)
                            Tab(text: l10n.mergedOriginalEventTitle(i + 1)),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Expanded(
                        child: TabBarView(
                          children: originals
                              .map((part) {
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppTheme.spacing4,
                                    0,
                                    AppTheme.spacing4,
                                    AppTheme.spacing6,
                                  ),
                                  child: _buildMarkdownBody(
                                    ctx,
                                    part,
                                    bodyStyle,
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeparator(BuildContext context) {
    final Color base =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      height: 1,
      color: base.withOpacity(0.2),
    );
  }

  Widget _buildAppIcon(BuildContext context, String package) {
    final app = widget.appInfoByPackage[package];
    if (app != null && app.icon != null && app.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          app.icon!,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.apps, size: 14),
    );
  }

  Widget _buildChip(BuildContext context, String text) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = dark ? AppTheme.darkSelectedAccent : AppTheme.info;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: dark ? 0.24 : 0.18),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: fg.withValues(alpha: dark ? 0.56 : 0.46),
          width: 1,
        ),
      ),
      child: _buildTagChipLabel(
        text: text,
        style: TextStyle(
          fontSize: 12,
          color: fg,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  MarkdownBody _buildMarkdownBody(
    BuildContext context,
    String data,
    TextStyle? textStyle,
  ) {
    final String normalized = _normalizeMarkdownForUi(data);
    return MarkdownBody(
      data: normalized,
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(p: textStyle),
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      },
    );
  }

  Widget _buildMergeStatusDropdown(
    BuildContext context, {
    required int segmentId,
    required String state,
    required String reasonText,
    required TextStyle? titleStyle,
    required TextStyle? reasonStyle,
    required bool canForce,
    required List<String> originalSummaries,
  }) {
    final l10n = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color bg = cs.surfaceContainerHighest.withOpacity(0.28);
    final Color border = cs.outline.withOpacity(0.22);

    final bool canOpenOriginals = originalSummaries.isNotEmpty;
    final TextStyle titleLinkStyle = (titleStyle ?? const TextStyle()).copyWith(
      color: cs.primary,
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('seg:$segmentId:mergeStatus'),
          dense: true,
          minTileHeight: 34,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: 0,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTheme.spacing3,
            0,
            AppTheme.spacing3,
            AppTheme.spacing2,
          ),
          leading: Icon(Icons.merge_type, size: 16, color: cs.onSurfaceVariant),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: canOpenOriginals
                      ? () async => _openMergedOriginalEventsDrawer(
                          context,
                          originals: originalSummaries,
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: state),
                          if (canOpenOriginals) const TextSpan(text: ' · '),
                          if (canOpenOriginals)
                            TextSpan(
                              text: l10n.mergedOriginalEventsTitle(
                                originalSummaries.length,
                              ),
                            ),
                        ],
                      ),
                      style: canOpenOriginals ? titleLinkStyle : titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: const StrutStyle(
                        height: 1.15,
                        forceStrutHeight: true,
                      ),
                    ),
                  ),
                ),
              ),
              if (_forcingMerge)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (canForce)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -1,
                      vertical: -3,
                    ),
                  ),
                  onPressed: widget.dynamicRebuildActive
                      ? null
                      : () async => _forceMerge(),
                  child: const Text('强制合并'),
                ),
            ],
          ),
          children: [
            if (reasonText.trim().isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(reasonText, style: reasonStyle),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    List<String> categories,
    bool merged,
  ) {
    final int total = categories.length + (merged ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();

    final List<Widget> chips = <Widget>[
      if (merged) _buildMergedTagChip(context),
      ...categories.map((c) => _buildChip(context, c)),
    ];

    final TextStyle measureStyle = const TextStyle(
      fontSize: 12,
      height: 1.0,
      fontWeight: FontWeight.w500,
    );
    final TextScaler textScaler = MediaQuery.textScalerOf(context);

    double estimateChipHeight() {
      final tp = TextPainter(
        text: TextSpan(text: '测试', style: measureStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      final double contentHeight = tp.height + _tagChipVerticalPadding * 2;
      return math.max(_tagChipMinHeight, contentHeight).ceilToDouble();
    }

    double estimateChipWidth(String label, double maxWidth) {
      final double horizontalPadding = AppTheme.spacing2;
      final double maxTextWidth = math.max(0, maxWidth - horizontalPadding * 2);
      final tp = TextPainter(
        text: TextSpan(text: label, style: measureStyle),
        maxLines: 1,
        ellipsis: '…',
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout(maxWidth: maxTextWidth);
      final double w = tp.width + horizontalPadding * 2;
      return w.clamp(0, maxWidth);
    }

    int estimateRows(List<String> labels, double maxWidth) {
      if (labels.isEmpty) return 0;
      final double spacing = _tagGridCrossAxisSpacing;
      int rows = 1;
      double rowWidth = 0;
      for (final label in labels) {
        final double w = estimateChipWidth(label, maxWidth);
        if (rowWidth == 0) {
          rowWidth = w;
          continue;
        }
        if (rowWidth + spacing + w <= maxWidth) {
          rowWidth += spacing + w;
        } else {
          rows += 1;
          rowWidth = w;
        }
      }
      return rows;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final List<String> labels = <String>[
          if (merged) AppLocalizations.of(context).mergedEventTag,
          ...categories,
        ];
        final int rows = estimateRows(labels, maxWidth);

        if (rows <= _tagMaxVisibleRows) {
          return Wrap(
            spacing: _tagGridCrossAxisSpacing,
            runSpacing: _tagGridMainAxisSpacing,
            alignment: WrapAlignment.start,
            children: chips,
          );
        }

        final double chipHeight = estimateChipHeight();
        final double viewportHeight =
            chipHeight * _tagMaxVisibleRows +
            _tagGridMainAxisSpacing * (_tagMaxVisibleRows - 1);
        final theme = Theme.of(context);
        final Color hintColor = theme.colorScheme.onSurfaceVariant.withOpacity(
          0.45,
        );

        // 最多显示两行，超过则在内部滚动（不撑爆卡片布局）。
        return SizedBox(
          height: viewportHeight + _tagOverflowHintHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: viewportHeight,
                child: Scrollbar(
                  controller: _tagScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(3),
                  child: SingleChildScrollView(
                    controller: _tagScrollController,
                    primary: false,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    child: Wrap(
                      spacing: _tagGridCrossAxisSpacing,
                      runSpacing: _tagGridMainAxisSpacing,
                      alignment: WrapAlignment.start,
                      children: chips,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  height: _tagOverflowHintHeight,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: hintColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMergedTagChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: AppTheme.mergedEventAccent.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: AppTheme.mergedEventAccent.withValues(alpha: 0.58),
          width: 1,
        ),
      ),
      child: _buildTagChipLabel(
        text: AppLocalizations.of(context).mergedEventTag,
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.mergedEventAccent,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTagChipLabel({required String text, required TextStyle style}) {
    final double minLabelHeight =
        _tagChipMinHeight - _tagChipVerticalPadding * 2;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minLabelHeight),
      child: Align(
        alignment: const Alignment(0, -0.14),
        widthFactor: 1,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          strutStyle: const StrutStyle(height: 1.0, forceStrutHeight: true),
          style: style,
        ),
      ),
    );
  }

  Widget _buildThumbGrid(
    BuildContext context,
    List<Map<String, dynamic>> samples, {
    Set<String> aiNsfwFiles = const <String>{},
  }) {
    if (samples.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final double cellWidth =
            (availableWidth -
                _thumbGridSpacing * (_thumbGridCrossAxisCount - 1)) /
            _thumbGridCrossAxisCount;
        // childAspectRatio = width / height => height = width / ratio
        const double childAspectRatio = 9 / 16;
        final double cellHeight = cellWidth / childAspectRatio;

        final int rows = (samples.length / _thumbGridCrossAxisCount).ceil();
        final double naturalHeight =
            rows * cellHeight + math.max(0, rows - 1) * _thumbGridSpacing;
        final double maxHeight = math.min(
          _thumbVirtualGridMaxHeight,
          MediaQuery.of(context).size.height * 0.55,
        );
        final double viewportHeight = math.min(naturalHeight, maxHeight);

        final double dpr = MediaQuery.of(context).devicePixelRatio;
        final int targetWidthPx = (cellWidth * dpr).round().clamp(96, 1024);

        return SizedBox(
          height: viewportHeight,
          child: Scrollbar(
            thumbVisibility: naturalHeight > viewportHeight,
            child: GridView.builder(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: samples.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _thumbGridCrossAxisCount,
                crossAxisSpacing: _thumbGridSpacing,
                mainAxisSpacing: _thumbGridSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (ctx, i) {
                final s = samples[i];
                final path = (s['file_path'] as String?) ?? '';
                final pageUrl = (s['page_url'] as String?) ?? '';

                if (path.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    ),
                  );
                }

                final String fileName = path
                    .replaceAll('\\', '/')
                    .split('/')
                    .last;
                final bool aiNsfw = aiNsfwFiles.contains(fileName);

                return ScreenshotImageWidget(
                  file: File(path),
                  privacyMode: widget.privacyMode,
                  extraNsfwMask: aiNsfw,
                  pageUrl: pageUrl.isNotEmpty ? pageUrl : null,
                  targetWidth: targetWidthPx,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.openGallery(samples, i),
                  showNsfwButton: true,
                  errorText: 'Image Error',
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _buildAiRequestResponseTraceText({
    required int segmentId,
    required String timeLabel,
    Map<String, dynamic>? result,
  }) {
    final String provider = (result?['ai_provider'] as String?)?.trim() ?? '';
    final String model = (result?['ai_model'] as String?)?.trim() ?? '';
    final String rawRequest =
        (result?['raw_request'] as String?)?.trimRight() ?? '';
    final String rawResponse =
        (result?['raw_response'] as String?)?.trimRight() ?? '';
    final int createdAtMs = (result?['created_at'] as int?) ?? 0;
    final String createdAtText = createdAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs).toIso8601String()
        : '';

    final StringBuffer sb = StringBuffer();
    sb.writeln('AI Request/Response Trace');
    sb.writeln('segment_id: $segmentId');
    if (timeLabel.trim().isNotEmpty) sb.writeln('time_range: $timeLabel');
    if (provider.isNotEmpty) sb.writeln('provider: $provider');
    if (model.isNotEmpty) sb.writeln('model: $model');
    if (createdAtText.isNotEmpty) sb.writeln('created_at: $createdAtText');
    sb.writeln('');
    sb.writeln('--- request ---');
    sb.writeln(rawRequest.isEmpty ? '(empty)' : rawRequest);
    sb.writeln('');
    sb.writeln('--- response ---');
    sb.writeln(rawResponse.isEmpty ? '(empty)' : rawResponse);
    return sb.toString().trimRight();
  }

  Future<void> _saveAiRequestResponseTraceToFile({
    required int segmentId,
    required String text,
  }) async {
    final String content = text.trimRight();
    if (content.trim().isEmpty) return;
    try {
      final DateTime now = DateTime.now();
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
        '${baseDir.path}${sep}ai_segment_traces',
      );
      await outDir.create(recursive: true);
      final File f = File(
        '${outDir.path}${sep}segment_ai_trace_${segmentId}_${now.millisecondsSinceEpoch}.log',
      );
      await f.writeAsString('$content\n', flush: true);
      try {
        await Clipboard.setData(ClipboardData(text: f.path));
      } catch (_) {}
      if (!mounted) return;
      final bool isZh = Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
      UINotifier.success(
        context,
        isZh ? '已保存到：${f.path}' : 'Saved to: ${f.path}',
      );
    } catch (e) {
      if (!mounted) return;
      final bool isZh = Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
      UINotifier.error(context, isZh ? '保存失败：$e' : 'Save failed: $e');
    }
  }

  Widget _buildAiRequestResponseSheetBody({
    required BuildContext context,
    required int segmentId,
    required String rawRequest,
    required String rawResponse,
    required String provider,
    required String model,
    required DateTime? createdAt,
    required bool isZh,
    required bool hasAny,
    required String visibleText,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double fallbackHeight = MediaQuery.of(context).size.height * 0.62;
        final double viewerHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : fallbackHeight;
        return AIRequestLogsViewer.fromSegmentTrace(
          rawRequest: rawRequest,
          rawResponse: rawResponse,
          segmentId: segmentId,
          provider: provider,
          model: model,
          createdAt: createdAt,
          showRawResponsePanel: false,
          scrollable: true,
          maxHeight: viewerHeight,
          emptyText: isZh ? '（暂无请求/响应记录）' : '(No request/response trace yet)',
          actions: <AIRequestLogsAction>[
            AIRequestLogsAction(
              label: AppLocalizations.of(context).actionCopy,
              enabled: hasAny,
              onPressed: () async {
                if (!hasAny) return;
                try {
                  await Clipboard.setData(ClipboardData(text: visibleText));
                  if (!mounted) return;
                  UINotifier.success(
                    this.context,
                    AppLocalizations.of(this.context).copySuccess,
                  );
                } catch (_) {}
              },
            ),
            AIRequestLogsAction(
              label: isZh ? '保存到文件' : 'Save to file',
              enabled: hasAny,
              onPressed: () async {
                if (!hasAny) return;
                await _saveAiRequestResponseTraceToFile(
                  segmentId: segmentId,
                  text: visibleText,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAiRequestResponseSheet(
    int segmentId, {
    required String timeLabel,
  }) async {
    Map<String, dynamic>? res;
    try {
      res = await widget.loadResult(segmentId);
    } catch (_) {
      res = null;
    }
    if (!mounted) return;

    final bool isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    final String provider = (res?['ai_provider'] as String?)?.trim() ?? '';
    final String model = (res?['ai_model'] as String?)?.trim() ?? '';
    final int createdAtMs = (res?['created_at'] as int?) ?? 0;
    final DateTime? createdAt = createdAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
        : null;
    final String rawRequest = (res?['raw_request'] as String?)?.trim() ?? '';
    final String rawResponse = (res?['raw_response'] as String?)?.trim() ?? '';
    final bool hasTrace = rawRequest.isNotEmpty || rawResponse.isNotEmpty;
    final String text = _buildAiRequestResponseTraceText(
      segmentId: segmentId,
      timeLabel: timeLabel,
      result: res,
    );
    final String emptyHint = isZh
        ? '（暂无请求/响应记录。升级后需要重新生成一次摘要才会写入。）'
        : '(No request/response trace yet. Regenerate once to capture it.)';
    final String visibleText = hasTrace
        ? text
        : (('$emptyHint\n\n$text').trimRight());
    final bool hasAny = visibleText.trim().isNotEmpty;
    await AIRequestLogsSheet.show(
      context: context,
      title: isZh ? 'AI 日志' : 'AI Logs',
      metaText: null,
      hintText: hasTrace ? null : emptyHint,
      expandBody: true,
      body: _buildAiRequestResponseSheetBody(
        context: context,
        segmentId: segmentId,
        rawRequest: rawRequest,
        rawResponse: rawResponse,
        provider: provider,
        model: model,
        createdAt: createdAt,
        isZh: isZh,
        hasAny: hasAny,
        visibleText: visibleText,
      ),
    );
  }

  Future<void> _retry() async {
    final int id = (_segmentData['id'] as int?) ?? 0;
    if (id <= 0 || _retrying) return;
    if (widget.dynamicRebuildActive) {
      UINotifier.info(context, '全量重建进行中，暂时禁止单条重新生成');
      return;
    }
    final previous = Map<String, dynamic>.from(_segmentData);
    int? previousCreatedAt = _lastResultCreatedAt;
    try {
      final prevRes = await widget.loadResult(id);
      final loaded = (prevRes?['created_at'] as int?) ?? 0;
      if (loaded > 0) {
        previousCreatedAt = loaded;
      }
    } catch (_) {}
    if (!mounted) return;
    final cleared = _segmentWithoutResult(previous);
    setState(() {
      _retrying = true;
      _segmentData = cleared;
      _lastResultCreatedAt = previousCreatedAt;
      _summaryStreaming = true;
      _summaryStreamingText = _summaryGeneratingPlaceholder;
    });
    try {
      // 手动重试不受时间/已有结果限制：强制重跑
      final n = await ScreenshotDatabase.instance.retrySegments([
        id,
      ], force: true);
      if (!mounted) return;
      final ok = n > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? AppLocalizations.of(context).regenerationQueued
                : AppLocalizations.of(context).alreadyQueuedOrFailed,
          ),
        ),
      );
      // 开启轮询直到拿到结果为止；若原本就有结果，可能立即返回
      if (ok) _startResultWatch(id);
      // 如果没成功入队，停止旋转
      if (!ok) {
        setState(() {
          _retrying = false;
          _segmentData = Map<String, dynamic>.from(previous);
          _lastResultCreatedAt = previousCreatedAt;
          _summaryStreaming = false;
          _summaryStreamingText = '';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _segmentData = Map<String, dynamic>.from(previous);
        _lastResultCreatedAt = previousCreatedAt;
        _summaryStreaming = false;
        _summaryStreamingText = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).retryFailed)),
      );
    }
  }

  Future<void> _forceMerge() async {
    final int id = (_segmentData['id'] as int?) ?? 0;
    if (id <= 0 || _forcingMerge) return;
    if (widget.dynamicRebuildActive) {
      UINotifier.info(context, '全量重建进行中，暂时禁止手动强制合并');
      return;
    }
    final int prevId = (_segmentData['merge_prev_id'] as int?) ?? 0;
    if (prevId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可合并的上一事件')));
      return;
    }

    final bool confirmed =
        await showUIDialog<bool>(
          context: context,
          title: '强制合并',
          message: '将与上一事件强制合并，并覆盖当前事件总结，同时删除上一事件。此操作无法撤销，是否继续？',
          actions: [
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).dialogCancel,
              style: UIDialogActionStyle.normal,
              result: false,
            ),
            const UIDialogAction<bool>(
              text: '强制合并',
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
          barrierDismissible: true,
        ) ??
        false;
    if (!confirmed) return;

    int? previousCreatedAt = _lastMergeResultCreatedAt;
    try {
      final prevRes = await widget.loadResult(id);
      final loaded = (prevRes?['created_at'] as int?) ?? 0;
      if (loaded > 0) previousCreatedAt = loaded;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _forcingMerge = true;
      _segmentData = Map<String, dynamic>.from(_segmentData)
        ..['merge_forced'] = 1
        ..['merge_decision_reason'] = '已请求强制合并（排队中）';
      _lastMergeResultCreatedAt = previousCreatedAt;
    });

    try {
      final ok = await ScreenshotDatabase.instance.forceMergeSegment(
        id,
        prevId: prevId,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _forcingMerge = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('强制合并入队失败')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('强制合并已入队')));
      _startMergeWatch(id, previousCreatedAt);
    } catch (_) {
      if (!mounted) return;
      setState(() => _forcingMerge = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('强制合并失败')));
    }
  }

  Future<void> _confirmAndDelete() async {
    final int id = (_segmentData['id'] as int?) ?? 0;
    if (id <= 0) return;

    final bool confirmed =
        await showUIDialog<bool>(
          context: context,
          title: AppLocalizations.of(context).deleteEventTooltip,
          message: AppLocalizations.of(context).confirmDeleteEventMessage,
          actions: [
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).dialogCancel,
              style: UIDialogActionStyle.normal,
              result: false,
            ),
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).actionDelete,
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
          barrierDismissible: true,
        ) ??
        false;

    if (!confirmed) return;
    try {
      final ok = await ScreenshotDatabase.instance.deleteSegmentOnly(id);
      if (!mounted) return;
      if (ok) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).eventDeletedToast,
        );
        await widget.onRefreshRequested();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).deleteFailed)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).deleteFailed)),
      );
    }
  }

  void _startResultWatch(int id, {bool notifyToast = true}) {
    _resultWatchTimer?.cancel();
    // 轮询间隔 2s；若拿到结果则停止旋转
    _resultWatchTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final res = await widget.loadResult(id);
        if (!mounted) return;
        if (res != null) {
          final int newCreatedAt = (res['created_at'] as int?) ?? 0;
          if (_lastResultCreatedAt != null &&
              newCreatedAt > 0 &&
              newCreatedAt <= _lastResultCreatedAt!) {
            return;
          }
          t.cancel();
          final merged = _mergeResultIntoSegment(_segmentData, res);
          final String finalSummary = _extractOverallSummary(
            _tryParseJson(merged['structured_json'] as String?),
          );
          setState(() {
            _retrying = false;
            _segmentData = merged;
            _lastResultCreatedAt = newCreatedAt > 0
                ? newCreatedAt
                : _lastResultCreatedAt;
            _summaryStreaming = true;
            _summaryStreamingText = '';
          });
          _latestExternalSegment = Map<String, dynamic>.from(merged);
          if (notifyToast) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).generateSuccess),
              ),
            );
          }
          _beginSummaryStreaming(finalSummary);
          try {
            await widget.onRefreshRequested();
          } catch (_) {}
        }
      } catch (_) {
        // 读取失败不影响轮询，继续尝试
      }
    });
  }

  void _startMergeWatch(int id, int? previousCreatedAt) {
    _mergeWatchTimer?.cancel();
    _mergeWatchTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final res = await widget.loadResult(id);
        if (!mounted) return;
        if (res == null) return;
        final int newCreatedAt = (res['created_at'] as int?) ?? 0;
        if (previousCreatedAt != null &&
            newCreatedAt > 0 &&
            newCreatedAt <= previousCreatedAt) {
          return;
        }
        t.cancel();
        final mergedSeg = _mergeResultIntoSegment(_segmentData, res);
        final String finalSummary = _extractOverallSummary(
          _tryParseJson(mergedSeg['structured_json'] as String?),
        );
        setState(() {
          _forcingMerge = false;
          _segmentData = mergedSeg;
          _lastMergeResultCreatedAt = newCreatedAt > 0
              ? newCreatedAt
              : _lastMergeResultCreatedAt;
          _summaryStreaming = true;
          _summaryStreamingText = '';
        });
        _latestExternalSegment = Map<String, dynamic>.from(mergedSeg);
        _beginSummaryStreaming(finalSummary);
        try {
          await widget.onRefreshRequested();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('合并完成')));
      } catch (_) {}
    });
  }

  void _beginSummaryStreaming(String target) {
    _summaryStreamTimer?.cancel();
    if (!mounted) return;
    if (target.trim().isEmpty) {
      setState(() {
        _summaryStreaming = false;
        _summaryStreamingText = target;
      });
      return;
    }
    setState(() {
      _summaryStreaming = true;
      _summaryStreamingText = '';
    });
    const int chunkSize = 24;
    int idx = 0;
    _summaryStreamTimer = Timer.periodic(const Duration(milliseconds: 35), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      idx = math.min(idx + chunkSize, target.length);
      final String next = target.substring(0, idx);
      setState(() {
        _summaryStreamingText = next;
      });
      if (idx >= target.length) {
        timer.cancel();
        setState(() {
          _summaryStreaming = false;
        });
      }
    });
  }

  Map<String, dynamic>? _tryParseJson(String? s) {
    if (s == null) return null;
    try {
      final obj = jsonDecode(s);
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}
    return null;
  }

  String? _extractKeyActionDetail(Map<String, dynamic>? sj) {
    if (sj == null) return null;
    final ka = sj['key_actions'];
    if (ka is List && ka.isNotEmpty) {
      final first = ka.first;
      if (first is Map && first['detail'] is String)
        return (first['detail'] as String);
      if (first is String) return first;
    } else if (ka is Map && ka['detail'] is String) {
      return ka['detail'] as String;
    } else if (ka is String) {
      return ka;
    }
    return null;
  }

  List<String> _extractCategories(
    Map<String, dynamic>? result,
    Map<String, dynamic>? sj,
  ) {
    final List<String> out = <String>[];
    // 1) result.categories 可能是 JSON 或逗号分隔
    final raw = result?['categories'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final obj = jsonDecode(raw);
        if (obj is List) {
          out.addAll(obj.map((e) => e.toString()));
        } else {
          out.addAll(
            raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty),
          );
        }
      } catch (_) {
        out.addAll(
          raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty),
        );
      }
    }
    // 2) structured_json.categories
    final sc = sj?['categories'];
    if (sc is List) {
      out.addAll(sc.map((e) => e.toString()));
    } else if (sc is String && sc.trim().isNotEmpty) {
      out.addAll(sc.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty));
    }
    // 去重
    final set = <String>{};
    final res = <String>[];
    for (final c in out) {
      final v = c.trim();
      if (v.isEmpty) continue;
      if (set.add(v)) res.add(v);
    }
    return res;
  }

  String _extractOverallSummary(Map<String, dynamic>? sj) {
    final v = sj?['overall_summary'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return '';
  }

  Map<String, dynamic>? _extractAiRetryMeta(Map<String, dynamic>? sj) {
    if (sj == null) return null;
    final dynamic raw = sj['_meta'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      try {
        return Map<String, dynamic>.from(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  int _aiRetryCount(Map<String, dynamic>? sj) {
    final meta = _extractAiRetryMeta(sj);
    if (meta == null) return 0;
    final dynamic raw = meta['retry_count'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  bool _aiNeedsManualRetry(Map<String, dynamic>? sj) {
    final meta = _extractAiRetryMeta(sj);
    if (meta == null) return false;
    final dynamic raw = meta['needs_manual_retry'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'yes';
    }
    return false;
  }

  String _aiRetryMessage(BuildContext context, Map<String, dynamic>? sj) {
    final l10n = AppLocalizations.of(context);
    final meta = _extractAiRetryMeta(sj);
    if (meta == null) return '';
    final String raw = (meta['retry_message'] as String?)?.trim() ?? '';
    if (raw.isNotEmpty) return raw;
    if (_aiNeedsManualRetry(sj)) {
      return l10n.aiResultAutoRetryFailedHint;
    }
    if (_aiRetryCount(sj) > 0) {
      return l10n.aiResultAutoRetriedHint;
    }
    return '';
  }

  List<String> _uniquePackages(List<Map<String, dynamic>> samples) {
    final set = <String>{};
    for (final s in samples) {
      final p = (s['app_package_name'] as String?) ?? '';
      if (p.isNotEmpty) set.add(p);
    }
    return set.toList();
  }

  // （已移除）关键图片卡片相关 UI 代码
}

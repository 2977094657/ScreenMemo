import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:talker/talker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:screen_memo/models/app_info.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/features/timeline/application/dynamic_entry_perf_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/data/settings/user_settings_service.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/utils/json_string_field_extractor.dart';
import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/core/utils/merged_event_summary.dart';
import 'package:screen_memo/core/widgets/model_logo.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_provider_model_picker.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_request_logs_action.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_request_logs_viewer.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/ai_request_logs_sheet.dart';
import 'package:screen_memo/features/gallery/presentation/widgets/screenshot_image_widget.dart';
import 'package:screen_memo/features/timeline/presentation/widgets/segment_tag_chip_colors.dart';
import 'package:screen_memo/core/widgets/screenshot_style_tab_bar.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/core/widgets/ui_action_menu.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/features/daily_summary/presentation/pages/daily_summary_page.dart';

part 'segment_status_page_state_helpers_part.dart';
part 'segment_status_page_provider_part.dart';
part 'segment_status_page_dynamic_task_part.dart';
part 'segment_status_page_dynamic_sheet_part.dart';
part 'segment_status_page_detail_part.dart';
part 'segment_status_page_timeline_tab_part.dart';
part 'segment_status_page_entry_card_part.dart';
part 'segment_status_page_entry_card_logic_part.dart';
part 'segment_status_page_entry_card_ui_part.dart';
part 'segment_status_page_entry_card_ai_part.dart';
part 'segment_status_page_entry_card_extract_part.dart';

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
  });

  final DynamicRebuildTaskStatus status;
  final bool starting;
  final bool stopping;
  final int selectedDayConcurrency;
  final bool savingDayConcurrency;
  final bool autoRepairEnabled;
  final bool autoRepairLoading;
  final bool autoRepairToggling;
}

class _SegmentStatusPageState extends State<SegmentStatusPage>
    with SingleTickerProviderStateMixin {
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _segments = <Map<String, dynamic>>[];
  Map<String, List<Map<String, dynamic>>> _segmentsByDay =
      <String, List<Map<String, dynamic>>>{};
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
        taskMode: 'rebuild',
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
        targetDayKey: '',
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

  // 日期 Tab 批次控制：首屏显示最近 30 个有数据日期，明细按日期懒加载。
  static const int _initialDayTabs = 30;
  static const int _appendDayTabs = 30;
  int _maxVisibleDayTabs = _initialDayTabs;
  bool _isLoadingMoreDays = false;
  bool _noMoreOlderSegments = false;
  List<String> _loadedDayKeys = const <String>[];
  Map<String, int> _dayCountsByKey = const <String, int>{};
  Set<String> _loadingDayKeys = const <String>{};
  int _timelineLoadGeneration = 0;

  // part 文件需要触发 UI 刷新时统一通过该方法，避免直接访问 State.setState。
  void _segmentStatusSetState(VoidCallback fn) => setState(fn);

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
            tooltip: '动态任务',
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
          dayKeys: _loadedDayKeys,
          dayCountsByKey: _dayCountsByKey,
          segmentsByDay: _segmentsByDay,
          loadingDayKeys: _loadingDayKeys,
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
          isTimelineLoading: _loading,
          isLoadingMoreDays: _isLoadingMoreDays,
          noMoreOlderSegments: _noMoreOlderSegments,
          onLastDayTabReached: _handleLastDayTabReached,
          onActiveDateChanged: _handleActiveDateChanged,
          loadAvailableYears: _loadSegmentTimelineYears,
          loadMonthDayCounts: _loadSegmentTimelineMonthDayCounts,
          onDateJumpRequested: _jumpToSegmentTimelineDate,
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/screenshot_database.dart';
import '../services/ai_providers_service.dart';
import '../services/ai_settings_service.dart';
import '../services/flutter_logger.dart';
import '../utils/model_icon_utils.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../services/app_selection_service.dart';
import '../models/app_info.dart';
import '../models/screenshot_record.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import 'daily_summary_page.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../widgets/screenshot_image_widget.dart';

/// 段落事件状态页
/// - 显示进行中的事件（collecting）
/// - 列出最近事件及其样本与AI结果摘要
class SegmentStatusPage extends StatefulWidget {
  const SegmentStatusPage({super.key});

  @override
  State<SegmentStatusPage> createState() => _SegmentStatusPageState();
}

class _SegmentStatusPageState extends State<SegmentStatusPage> {
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _segments = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _onlyNoSummary = false; // 仅看暂无AI总结
  // 底部弹窗查询输入持久化，避免失焦或重建清空
  String _segProviderQueryText = '';
  String _segModelQueryText = '';

  // —— 基于提供商表的“动态(segments)”上下文（与对话隔离） ——
  AIProvider? _ctxSegProvider;
  String? _ctxSegModel;
  bool _ctxSegLoading = true;

  // 应用图标缓存（包名 -> AppInfo）
  final Map<String, AppInfo> _appInfoByPackage = <String, AppInfo>{};

  // 隐私模式状态
  bool _privacyMode = true; // 默认开启，初始化时从偏好读取
 
  // 自动轮询：每秒检测"暂无总结"并自动刷新，直到清空
  Timer? _autoTimer;
  bool _autoWatching = false;
  int _autoTickCount = 0;

  // 日期 Tab 可见窗口控制：默认仅展示最近 14 天，向前按批次扩展
  static const int _initialDayTabs = 14;
  static const int _appendDayTabs = 14;
  int _maxVisibleDayTabs = _initialDayTabs;
  bool _isLoadingMoreDays = false;
  bool _noMoreOlderSegments = false;

  @override
  void initState() {
    super.initState();
    _initApps();
    _loadPrivacyMode();
    _loadSegmentsContextSelection();
    _refresh();
    // 订阅隐私模式变更
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() { _privacyMode = enabled; });
    });
  }

  // 载入“动态(segments)”的提供商/模型选择（独立于对话页）
  Future<void> _loadSegmentsContextSelection() async {
    try {
      final svc = AIProvidersService.instance;
      final providers = await svc.listProviders();
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _ctxSegProvider = null;
            _ctxSegModel = null;
            _ctxSegLoading = false;
          });
        }
        return;
      }
      final ctxRow = await AISettingsService.instance.getAIContextRow('segments');
      AIProvider? sel;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        sel = await svc.getProvider(ctxRow['provider_id'] as int);
      }
      sel ??= await svc.getDefaultProvider();
      sel ??= providers.first;

      String model = (ctxRow != null && (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel).toString();
      if (model.isEmpty && sel.models.isNotEmpty) model = sel.models.first;

      if (mounted) {
        setState(() {
          _ctxSegProvider = sel;
          _ctxSegModel = model;
          _ctxSegLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ctxSegLoading = false);
    }
  }

  Future<void> _showProviderSheetSegments() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final currentId = _ctxSegProvider?.id ?? -1;
        // 使用持久化查询文本，避免键盘开合/重建导致输入被清空
        final TextEditingController queryCtrl = TextEditingController(text: _segProviderQueryText);
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
                  return name.contains(q) || type.contains(q) || base.contains(q);
                }).toList();
                // 将当前选中的提供商置顶，便于观察
                final selIdx = filtered.indexWhere((e) => e.id == currentId);
                if (selIdx > 0) {
                  final sel = filtered.removeAt(selIdx);
                  filtered.insert(0, sel);
                }
                return SafeArea(
                  child: Column(
                    children: [
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
                            hintText: AppLocalizations.of(context).searchProviderPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(c).colorScheme.outline.withOpacity(0.6),
                          ),
                          itemBuilder: (c, i) {
                            final p = filtered[i];
                            final selected = p.id == currentId;
                            return ListTile(
                              leading: SvgPicture.asset(
                                ModelIconUtils.getProviderIconPath(p.type),
                                width: 20, height: 20,
                              ),
                              title: Text(p.name, style: Theme.of(c).textTheme.bodyMedium),
                              trailing: selected ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.onSurface) : null,
                              onTap: () async {
                                String model = (_ctxSegModel ?? '').trim();
                                if (model.isEmpty) {
                                  model = (p.extra['active_model'] as String? ?? p.defaultModel).toString().trim();
                                }
                                if (model.isEmpty && p.models.isNotEmpty) model = p.models.first;
                                await AISettingsService.instance.setAIContextSelection(context: 'segments', providerId: p.id!, model: model);
                                if (mounted) {
                                  setState(() {
                                    _ctxSegProvider = p;
                                    _ctxSegModel = model;
                                  });
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(context, AppLocalizations.of(context).providerSelectedToast(p.name));
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
      UINotifier.info(context, AppLocalizations.of(context).pleaseSelectProviderFirst);
      return;
    }
    final models = p.models;
    if (models.isEmpty) {
      UINotifier.info(context, AppLocalizations.of(context).noModelsForProviderHint);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final active = (_ctxSegModel ?? '').trim();
        // 使用持久化查询文本，避免失焦时文本被清空
        final TextEditingController queryCtrl = TextEditingController(text: _segModelQueryText);
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
                return SafeArea(
                  child: Column(
                    children: [
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
                            hintText: AppLocalizations.of(context).searchModelPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(c).colorScheme.outline.withOpacity(0.6),
                          ),
                          itemBuilder: (c, i) {
                            final m = filtered[i];
                            final selected = m == active;
                            return ListTile(
                              leading: SvgPicture.asset(
                                ModelIconUtils.getIconPath(m),
                                width: 20, height: 20,
                              ),
                              title: Text(m, style: Theme.of(c).textTheme.bodyMedium),
                              trailing: selected ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.primary) : null,
                              onTap: () async {
                                await AISettingsService.instance.setAIContextSelection(context: 'segments', providerId: p.id!, model: m);
                                if (mounted) {
                                  setState(() => _ctxSegModel = m);
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(context, AppLocalizations.of(context).modelSwitchedToast(m));
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
    try {
      final enabled = await AppSelectionService.instance.getPrivacyModeEnabled();
      if (mounted) setState(() { _privacyMode = enabled; });
    } catch (_) {}
  }

  Future<void> _initApps() async {
    try {
      final apps = await AppSelectionService.instance.getAllInstalledApps();
      if (!mounted) return;
      setState(() {
        for (final a in apps) {
          _appInfoByPackage[a.packageName] = a;
        }
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; });
    try {
      final active = await _db.getActiveSegment();
      List<Map<String, dynamic>> segments;

      if (_onlyNoSummary) {
        // “仅看无总结”模式：保持原有行为，仅限制行数；由 SQL 侧过滤无总结事件
        const int fetchLimit = 100;
        segments = await _db.listSegmentsEx(
          limit: fetchLimit,
          onlyNoSummary: true,
        );
      } else {
        // 默认模式：只拉取“最近 14 天”的段落，按 start_time 过滤
        final DateTime now = DateTime.now();
        // 使用当天 23:59:59.999 作为上界，避免时区/毫秒误差导致当天事件遗漏
        final DateTime endOfToday = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
          999,
        );
        final DateTime startDay = endOfToday.subtract(
          const Duration(days: _initialDayTabs - 1),
        );
        final int startMs = startDay.millisecondsSinceEpoch;
        final int endMs = endOfToday.millisecondsSinceEpoch;

        const int fetchLimit = 800;
        segments = await _db.listSegmentsEx(
          limit: fetchLimit,
          onlyNoSummary: false,
          startMillis: startMs,
          endMillis: endMs,
        );

        // 如果最近 14 天内完全没有事件，则回退为“全量但限行数”的查询，
        // 避免用户长期停用后重新开启时看不到更早历史。
        if (segments.isEmpty) {
          segments = await _db.listSegmentsEx(
            limit: fetchLimit,
            onlyNoSummary: false,
          );
        }
      }

      setState(() {
        _active = active;
        _segments = segments;
        // 每次刷新都重置日期窗口，仅展示最近两周的日期 Tab
        _maxVisibleDayTabs = _initialDayTabs;
        _noMoreOlderSegments = false;
      });
      // 若处于“仅看无总结”，根据是否还有待补事件启动/停止自动检测
      if (_onlyNoSummary) {
        final hasPending = segments.any((e) => (e['has_summary'] as int? ?? 0) == 0);
        if (hasPending) {
          _maybeStartAutoWatch();
        } else {
          _stopAutoWatch();
        }
      }
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  /// 从当前已加载的 segments 向前再拉取一批“更早日期”的事件
  /// - 仅在默认模式下生效（_onlyNoSummary=false）
  /// - 按 start_time 的日期向前扩展一个固定窗口（_appendDayTabs 天）
  Future<void> _loadOlderSegmentsFromDbIfNeeded() async {
    if (_onlyNoSummary || _isLoadingMoreDays || _noMoreOlderSegments) return;
    if (_segments.isEmpty) return;

    // 计算当前已加载段落中最早的 start_time
    int? oldestMs;
    for (final m in _segments) {
      final int v = (m['start_time'] as int?) ?? 0;
      if (v <= 0) continue;
      if (oldestMs == null || v < oldestMs) oldestMs = v;
    }
    if (oldestMs == null || oldestMs <= 0) {
      _noMoreOlderSegments = true;
      return;
    }

    _isLoadingMoreDays = true;
    try {
      final DateTime oldestDate = DateTime.fromMillisecondsSinceEpoch(oldestMs);
      // 以“最早事件所在日的前一天 23:59:59.999”为新的上界，向前再扩展 _appendDayTabs 天
      final DateTime endDay = DateTime(
        oldestDate.year,
        oldestDate.month,
        oldestDate.day,
      ).subtract(const Duration(milliseconds: 1));
      final DateTime startDay = endDay.subtract(
        const Duration(days: _appendDayTabs - 1),
      );
      final int startMs = startDay.millisecondsSinceEpoch;
      final int endMs = endDay.millisecondsSinceEpoch;

      const int extraLimit = 800;
      final List<Map<String, dynamic>> more = await _db.listSegmentsEx(
        limit: extraLimit,
        onlyNoSummary: false,
        startMillis: startMs,
        endMillis: endMs,
      );
      if (more.isEmpty) {
        _noMoreOlderSegments = true;
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

      setState(() {
        _segments = merged;
        // 向前扩展一个批次的日期窗口
        _maxVisibleDayTabs += _appendDayTabs;
      });
    } finally {
      _isLoadingMoreDays = false;
    }
  }

  /// 当用户滑动日期 Tab 到“当前最后一个可见日期”时触发
  /// - 若当前 segments 中仍有更多日期尚未展示，则只增加可见天数
  /// - 若已经展示了所有已加载日期，尝试从数据库再加载更早一批
  Future<void> _handleLastDayTabReached() async {
    if (!mounted) return;

    // 基于当前 _segments 统计所有日期 key
    final Map<String, List<Map<String, dynamic>>> grouped = <String, List<Map<String, dynamic>>>{};
    for (final seg in _segments) {
      final int ms = (seg['start_time'] as int?) ?? 0;
      if (ms <= 0) continue;
      final String k = _dateKeyFromMillis(ms);
      grouped.putIfAbsent(k, () => <Map<String, dynamic>>[]).add(seg);
    }
    final int totalDays = grouped.length;
    if (totalDays == 0) return;

    // 还有未展示的日期，只扩展可见窗口，不访问数据库
    if (_maxVisibleDayTabs < totalDays) {
      setState(() {
        _maxVisibleDayTabs = math.min(totalDays, _maxVisibleDayTabs + _appendDayTabs);
      });
      return;
    }

    // 已经展示了当前数据中的所有日期，再尝试向前加载更早一批
    await _loadOlderSegmentsFromDbIfNeeded();
  }

  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';
  }

  Widget _buildActiveCard() {
    final a = _active;
    if (a == null) return const SizedBox.shrink();
    final start = (a['start_time'] as int?) ?? 0;
    final end = (a['end_time'] as int?) ?? 0;
    final dur = (a['duration_sec'] as int?) ?? 0;
    final interval = (a['sample_interval_sec'] as int?) ?? 0;
    return Card(
      child: ListTile(
        title: Text(AppLocalizations.of(context).activeSegmentTitle),
        subtitle: Text('${_fmtTime(start)} - ${_fmtTime(end)}  ·  ${dur}s  ·  ${AppLocalizations.of(context).sampleEverySeconds(interval)}'),
        trailing: const Icon(Icons.timelapse),
      ),
    );
  }

  Future<void> _openImageGallery(List<Map<String, dynamic>> samples, int initialIndex) async {
    if (!mounted) return;
    try {
      // 将样本映射为 ScreenshotRecord 列表；优先从数据库补全原始记录（含 id / page_url 等）
      final List<Future<ScreenshotRecord>> futures = <Future<ScreenshotRecord>>[];
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
            final rec = await ScreenshotDatabase.instance.getScreenshotByPath(filePath);
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
            captureTime: ct > 0 ? DateTime.fromMillisecondsSinceEpoch(ct) : DateTime.now(),
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
      final String curPkg = (cur['app_package_name'] as String?) ?? shots[safeIndex].appPackageName;
      final String curAppName = (cur['app_name'] as String?) ?? shots[safeIndex].appName;
      final AppInfo app = _appInfoByPackage[curPkg]
          ?? AppInfo(packageName: curPkg, appName: curAppName, icon: null, version: '', isSystemApp: false);

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
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).operationFailed)),
      );
    }
  }

  Widget _buildSamplesGrid(List<Map<String, dynamic>> samples) {
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
            child: const Center(child: Icon(Icons.image_not_supported_outlined)),
          );
        }
        
        return ScreenshotImageWidget(
          file: File(path),
          privacyMode: _privacyMode,
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
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (_, ctrl) {
            return Container(
              padding: const EdgeInsets.all(12),
              child: ListView(
                controller: ctrl,
                children: [
                  Text(AppLocalizations.of(context).timeRangeLabel('${_fmtTime((seg['start_time'] as int?) ?? 0)} - ${_fmtTime((seg['end_time'] as int?) ?? 0)}')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(AppLocalizations.of(context).statusLabel((seg['status'] as String?) ?? '')),
                      const SizedBox(width: 8),
                      if ((seg['merged_flag'] as int?) == 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            AppLocalizations.of(context).mergedEventTag,
                            style: const TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(AppLocalizations.of(context).samplesTitle(samples.length)),
                  const SizedBox(height: 6),
                  _buildSamplesGrid(samples),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Text(AppLocalizations.of(context).aiResultTitle),
                      const Spacer(),
                      if (result != null)
                        IconButton(
                          tooltip: AppLocalizations.of(context).copyResultsTooltip,
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          onPressed: () async {
                            final text = ((result['structured_json'] as String?) ?? (result['output_text'] as String?) ?? '').toString();
                            if (text.isEmpty) return;
                            await Clipboard.setData(ClipboardData(text: text));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(AppLocalizations.of(context).copySuccess)),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (result == null) Text(AppLocalizations.of(context).none),
                  if (result != null) ...[
                    Builder(
                      builder: (c) {
                        final String rawText = (result['output_text'] as String?) ?? '';
                        final String rawJson = (result['structured_json'] as String?) ?? '';
                        Map<String, dynamic>? sj;
                        try {
                          final d = jsonDecode(rawJson);
                          if (d is Map<String, dynamic>) sj = d;
                        } catch (_) {}
                        String? err;
                        try {
                          final e = sj?['error'];
                          if (e is Map) {
                            final m = (e['message'] ?? e['msg'] ?? '').toString();
                            if (m.trim().isNotEmpty) {
                              err = m;
                            } else {
                              err = e.toString();
                            }
                          } else if (e is String && e.trim().isNotEmpty) {
                            err = e;
                          }
                        } catch (_) {}
                        if (err == null && rawText.trim().startsWith('{')) {
                          try {
                            final d2 = jsonDecode(rawText);
                            if (d2 is Map && d2['error'] != null) {
                              final e2 = d2['error'];
                              if (e2 is Map && (e2['message'] is String)) {
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
                              low.contains('no candidates returned')) {
                            err = rawText;
                          }
                        }
                        if (err != null) {
                          final cs = Theme.of(c).colorScheme;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
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
                                      child: SelectableText(
                                        err!,
                                        style: Theme.of(c).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (rawJson.isNotEmpty)
                                SelectableText(rawJson, style: Theme.of(c).textTheme.bodySmall),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppLocalizations.of(context).modelValueLabel((result['ai_model'] ?? '').toString())),
                              const SizedBox(height: 6),
                              MarkdownBody(
                                data: rawText,
                                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(c)).copyWith(
                                  p: Theme.of(c).textTheme.bodyMedium,
                                ),
                                onTapLink: (text, href, title) async {
                                  if (href == null) return;
                                  final uri = Uri.tryParse(href);
                                  if (uri != null) {
                                    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
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
            );
          },
        );
      }
    );
  }

  void _maybeStartAutoWatch() {
    if (!_onlyNoSummary || _autoWatching) return;
    _autoWatching = true;
    _autoTickCount = 0;
    // 先触发一次原生扫描，确保后续能尽快进入工作状态
    () async {
      try { await _db.triggerSegmentTick(); } catch (_) {}
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
    if (!_onlyNoSummary || !mounted) { _stopAutoWatch(); return; }
    if (_loading) return;
    _autoTickCount++;
    try {
      // 每次只做轻量查询；原生端 1s 心跳已持续推进/补救
      final segments = await _db.listSegmentsEx(limit: 50, onlyNoSummary: true);
      if (!mounted) return;
      setState(() { _segments = segments; });
      // 若已无“暂无总结”，停止自动检测
      final hasPending = segments.any((e) => (e['has_summary'] as int? ?? 0) == 0);
      if (!hasPending) _stopAutoWatch();
    } catch (_) {}
  }
 
  @override
  void dispose() {
    _stopAutoWatch();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        automaticallyImplyLeading: true,
        title: _buildSegmentsProviderModelAppBarTitle(),
        actions: [
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
          activeHeader: _buildActiveCard(),
          onRefreshRequested: _refresh,
          privacyMode: _privacyMode,
          maxVisibleDayTabs: _maxVisibleDayTabs,
          onLastDayTabReached: _handleLastDayTabReached,
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
  final Future<void> Function() onRefreshRequested;
  final bool privacyMode;
  final int maxVisibleDayTabs;
  final Future<void> Function()? onLastDayTabReached;

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
    required this.onRefreshRequested,
    required this.privacyMode,
    required this.maxVisibleDayTabs,
    this.onLastDayTabReached,
  });

  @override
  State<_SegmentTimelineTabView> createState() => _SegmentTimelineTabViewState();
}

class _SegmentTimelineTabViewState extends State<_SegmentTimelineTabView>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    final TabController? ctrl = _tabController;
    if (ctrl == null || !mounted) return;
    // 仅在动画结束后处理，避免在拖动过程中重复触发
    if (ctrl.indexIsChanging) return;
    if (ctrl.length <= 0) return;
    if (ctrl.index == ctrl.length - 1) {
      // 已经滑动到当前最后一个日期 Tab，通知外层尝试加载更多
      widget.onLastDayTabReached?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> segments = widget.segments;

    if (segments.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing1),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  widget.activeHeader,
                  const SizedBox(height: 8),
                  if (widget.onlyNoSummary && widget.autoWatching)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(AppLocalizations.of(context).autoWatchingHint, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing6),
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
    final List<String> keys = grouped.keys.toList()..sort((a, b) => a.compareTo(b));
    final List<String> orderedAll = keys.reversed.toList();

    // 仅展示“最近 maxVisibleDayTabs 个日期”，其余日期在用户滑动到末尾后再增量展示
    final int visibleCount = math.min(widget.maxVisibleDayTabs, orderedAll.length);
    final List<String> ordered = orderedAll.take(visibleCount).toList();

    // 根据当前可见日期数量维护 TabController，尽量保留用户当前选中的索引
    if (_tabController == null || _tabController!.length != ordered.length) {
      final int currentIndex = _tabController?.index ?? 0;
      _tabController?.removeListener(_handleTabChanged);
      _tabController?.dispose();

      final int initialIndex = ordered.isEmpty
          ? 0
          : currentIndex.clamp(0, ordered.length - 1);
      _tabController = TabController(
        length: ordered.length,
        vsync: this,
        initialIndex: initialIndex,
      );
      _tabController!.addListener(_handleTabChanged);
    }

    return Column(
      children: [
        Builder(
          builder: (context) {
            final Color selectedColor = Theme.of(context).brightness == Brightness.dark
                ? AppTheme.darkForeground
                : AppTheme.foreground;
            final Color unselectedColor =
                Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.mutedForeground;
            final bool hasMoreTabs = widget.maxVisibleDayTabs < orderedAll.length;
            return SizedBox(
              height: 32,
              child: Transform.translate(
                offset: const Offset(0, -2),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        // 与截图列表一致：左侧少量起始内边距，去除额外垂直内边距
                        padding: const EdgeInsets.only(left: AppTheme.spacing2),
                        // 与截图列表一致：标签水平留白适中
                        labelPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
                        labelColor: selectedColor,
                        unselectedLabelColor: unselectedColor,
                        labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        // 与截图列表一致：去掉底部分割线
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.label,
                        // 减少上下空隙
                        indicatorPadding: EdgeInsets.zero,
                        // 与截图列表一致：细下划线，较小的左右 insets
                        indicator: UnderlineTabIndicator(
                          borderSide: BorderSide(width: 2.0, color: selectedColor),
                          insets: const EdgeInsets.symmetric(horizontal: 4.0),
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
                                  (grouped[k] ?? const <Map<String, dynamic>>[])
                                      .length;
                              final l10n = AppLocalizations.of(context);
                              if (sameDay(dt, now)) return l10n.dayTabToday(c);
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
                    if (hasMoreTabs)
                      Padding(
                        padding: const EdgeInsets.only(left: AppTheme.spacing2),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: widget.onLastDayTabReached == null
                              ? null
                              : () {
                                  widget.onLastDayTabReached!.call();
                                },
                          icon: const Icon(Icons.more_horiz, size: 18),
                          label: Text(AppLocalizations.of(context).memoryLoadMore),
                        ),
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
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing1),
                  children: [
                    widget.activeHeader,
                    const SizedBox(height: 8),
                    _buildDailyEntryCard(context, k, grouped),
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

  Widget _buildDailyEntryCard(
    BuildContext context,
    String dateKey,
    Map<String, List<Map<String, dynamic>>> grouped,
  ) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_note_outlined),
        title: Text(AppLocalizations.of(context).dailySummaryShort),
        subtitle: Text(
          AppLocalizations.of(context).viewOrGenerateForDay,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // 这里仍然使用 dateKey（YYYY-MM-DD）作为每日总结的键，与 DailySummaryPage 保持一致
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DailySummaryPage(dateKey: dateKey)),
          );
        },
      ),
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
  });

  @override
  State<_SegmentEntryCard> createState() => _SegmentEntryCardState();
}

class _SegmentEntryCardState extends State<_SegmentEntryCard> {
  static const int _tagWrapThreshold = 18;
  static const double _tagVirtualListMaxHeight = 168;
  static const double _tagGridMaxCrossAxisExtent = 220;
  static const double _tagGridMainAxisExtent = 32;
  static const double _tagGridMainAxisSpacing = 6;
  static const double _tagGridCrossAxisSpacing = 6;

  bool _expanded = false;
  // 懒加载样本的本地状态，避免每项滚动时触发异步查询导致跳动
  bool _samplesLoading = false;
  bool _samplesLoaded = false;
  List<Map<String, dynamic>> _samples = const <Map<String, dynamic>>[];
  // 摘要展开/收起状态（防止固定高度无法展开）
  bool _summaryExpanded = false;
  // 重新生成操作状态
  bool _retrying = false;
  // 结果轮询器：点击“重新生成”后，直到拿到结果为止持续旋转提示
  Timer? _resultWatchTimer;
  Map<String, dynamic> _segmentData = <String, dynamic>{};
  Map<String, dynamic> _latestExternalSegment = <String, dynamic>{};
  int? _lastResultCreatedAt;

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

  Map<String, dynamic> _mergeResultIntoSegment(Map<String, dynamic> base, Map<String, dynamic> result) {
    final next = Map<String, dynamic>.from(base);
    next['output_text'] = result['output_text'];
    next['structured_json'] = result['structured_json'];
    next['categories'] = result['categories'];
    next['has_summary'] = 1;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final int id = (_segmentData['id'] as int?) ?? 0;
    // 移除 per-item FutureBuilder，使用后端联表元数据；展开时懒加载样本
    final int sampleCount = (_segmentData['sample_count'] as int?) ?? 0;
    final int start = (_segmentData['start_time'] as int?) ?? 0;
    final int end = (_segmentData['end_time'] as int?) ?? 0;
    final String timeLabel = '${widget.fmtTime(start)} - ${widget.fmtTime(end)}';
    final bool merged = (_segmentData['merged_flag'] as int?) == 1;
    final String status = (_segmentData['status'] as String?) ?? '';

    final Map<String, dynamic> resultMeta = {
      'categories': _segmentData['categories'],
      'output_text': _segmentData['output_text'],
    };
    final Map<String, dynamic>? structured = _tryParseJson(_segmentData['structured_json'] as String?);
    final String? keyAction = _extractKeyActionDetail(structured);
    final List<String> categories = _extractCategories(resultMeta, structured);
    final String summary = _extractOverallSummary(resultMeta, structured);

    // 错误检测：从 structured_json.error / output_text(JSON) / 关键字启发式 识别错误
    String? errorText;
    final String outputRaw = (resultMeta['output_text'] as String?)?.toString() ?? '';

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
    if (errorText == null && outputRaw.isNotEmpty && outputRaw.trim().startsWith('{')) {
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
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

        // 包名：优先使用后端汇总的 app_packages_display，其次 app_packages（保证首屏就能显示 Logo）
        List<String> packages = <String>[];
        final String? appPkgsDisplay = _segmentData['app_packages_display'] as String?;
        final String? appPkgsRaw = _segmentData['app_packages'] as String?;
        final String? pkgSrc = (appPkgsDisplay != null && appPkgsDisplay.trim().isNotEmpty)
            ? appPkgsDisplay
            : appPkgsRaw;
        if (pkgSrc != null && pkgSrc.trim().isNotEmpty) {
          packages = pkgSrc.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty).toList();
        }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3, vertical: AppTheme.spacing1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timeSeparator(context, label: timeLabel, keyActionDetail: keyAction),
          const SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: packages.map((pkg) => _buildAppIcon(context, pkg)).toList(),
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
                final TextStyle? textStyle = Theme.of(context).textTheme.bodyMedium;
                // 仅在收起状态下检测是否溢出
                bool overflow = false;
                if (!_summaryExpanded && textStyle != null) {
                  final tp = TextPainter(
                    text: TextSpan(text: summary, style: textStyle),
                    maxLines: 7,
                    ellipsis: '…',
                    textDirection: Directionality.of(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  overflow = tp.didExceedMaxLines;
                }

                // 预估 7 行高度用于折叠时裁切
                final double lineHeight = (textStyle?.height ?? 1.2) * (textStyle?.fontSize ?? 14.0);
                final double collapsedHeight = lineHeight * 7.0 + 2.0;

                final md = MarkdownBody(
                  data: summary,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: textStyle,
                  ),
                  onTapLink: (text, href, title) async {
                    if (href == null) return;
                    final uri = Uri.tryParse(href);
                    if (uri != null) {
                      try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                    }
                  },
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryExpanded
                        ? md
                        : ConstrainedBox(constraints: BoxConstraints(maxHeight: collapsedHeight), child: ClipRect(child: md)),
                    if (overflow || _summaryExpanded)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() => _summaryExpanded = !_summaryExpanded),
                          child: Text(_summaryExpanded ? AppLocalizations.of(context).collapse : AppLocalizations.of(context).expandMore),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: sampleCount <= 0 ? null : () async {
                  setState(() => _expanded = !_expanded);
                  if (_expanded && !_samplesLoaded && !_samplesLoading) {
                    setState(() => _samplesLoading = true);
                    try {
                      final loaded = await widget.loadSamples(id);
                      setState(() {
                        _samples = loaded;
                        _samplesLoaded = true;
                      });
                    } catch (_) {} finally {
                      if (mounted) setState(() => _samplesLoading = false);
                    }
                  }
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(_expanded ? AppLocalizations.of(context).hideImagesCount(sampleCount) : AppLocalizations.of(context).viewImagesCount(sampleCount)),
              ),
              const Spacer(),
              IconButton(
                tooltip: AppLocalizations.of(context).actionRegenerate,
                onPressed: _retrying ? null : () async {
                  await _retry();
                },
                icon: _retrying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                  if (categories.isNotEmpty) buffer.writeln(l10n.categoriesLabel(categories.join(', ')));
                  if (errorText != null && errorText!.trim().isNotEmpty) {
                    buffer.writeln(l10n.errorLabel(errorText!));
                  } else if (summary.trim().isNotEmpty) {
                    buffer.writeln(l10n.summaryLabel(summary));
                  }
                  await Clipboard.setData(ClipboardData(text: buffer.toString()));
                  if (!mounted) return;
                  UINotifier.success(context, AppLocalizations.of(context).copySuccess);
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
                    child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : (_samples.isNotEmpty ? _buildThumbGrid(context, _samples) : const SizedBox.shrink())),
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
            Widget _timeSeparator(BuildContext context, {required String label, String? keyActionDetail}) {
              final Color actionColor = AppTheme.warning; // 使用更醒目的警告色
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 22,
                    child: Center(
                      child: Text(
                        label,
                        style: DefaultTextStyle.of(context).style,
                      ),
                    ),
                  ),
                  if (keyActionDetail != null && keyActionDetail.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Center(
                        child: Text(
                          keyActionDetail,
                          style: DefaultTextStyle.of(context).style.copyWith(color: actionColor),
                        ),
                      ),
                    ),
                ],
              );
            }

  Widget _buildSeparator(BuildContext context) {
    final Color base = DefaultTextStyle.of(context).style.color
        ?? Theme.of(context).textTheme.bodyMedium?.color
        ?? Theme.of(context).colorScheme.onSurface;
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
        child: Image.memory(app.icon!, width: 20, height: 20, fit: BoxFit.cover),
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
    // 关键：不设置 alignment，不用 ConstrainedBox 包裹宽度；仅设置最小高度，宽度随文本自适应
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2, vertical: 2),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: fg.withOpacity(0.35), width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: fg,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCategorySection(BuildContext context, List<String> categories, bool merged) {
    final int total = categories.length + (merged ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();

    if (total <= _tagWrapThreshold) {
      return Wrap(
        spacing: _tagGridCrossAxisSpacing,
        runSpacing: _tagGridMainAxisSpacing,
        alignment: WrapAlignment.start,
        children: [
          if (merged) _buildMergedTagChip(context),
          ...categories.map((c) => _buildChip(context, c)),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final double columnExtent = math.min(_tagGridMaxCrossAxisExtent, availableWidth);
        final int columns = math.max(1, (availableWidth / columnExtent).floor());
        final int rows = (total / columns).ceil();
        final double naturalHeight = rows * _tagGridMainAxisExtent +
            math.max(0, rows - 1) * _tagGridMainAxisSpacing;
        final double viewportHeight = math.min(_tagVirtualListMaxHeight, naturalHeight);

        return SizedBox(
          height: viewportHeight,
          child: Scrollbar(
            thumbVisibility: naturalHeight > viewportHeight,
            child: GridView.builder(
              primary: false,
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _tagGridMaxCrossAxisExtent,
                mainAxisExtent: _tagGridMainAxisExtent,
                mainAxisSpacing: _tagGridMainAxisSpacing,
                crossAxisSpacing: _tagGridCrossAxisSpacing,
              ),
              itemCount: total,
              itemBuilder: (context, index) {
                if (merged) {
                  if (index == 0) return _buildMergedTagChip(context);
                  return _buildChip(context, categories[index - 1]);
                }
                return _buildChip(context, categories[index]);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMergedTagChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2, vertical: 2),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.warning.withOpacity(0.45), width: 1),
      ),
      child: Text(
        AppLocalizations.of(context).mergedEventTag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.warning,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildThumbGrid(BuildContext context, List<Map<String, dynamic>> samples) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: samples.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
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
            child: const Center(child: Icon(Icons.image_not_supported_outlined)),
          );
        }
        
        return ScreenshotImageWidget(
          file: File(path),
          privacyMode: widget.privacyMode,
          pageUrl: pageUrl.isNotEmpty ? pageUrl : null,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.openGallery(samples, i),
          showNsfwButton: true,
          errorText: 'Image Error',
        );
      },
    );
  }

  Future<void> _retry() async {
    final int id = (_segmentData['id'] as int?) ?? 0;
    if (id <= 0 || _retrying) return;
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
    });
    try {
      // 手动重试不受时间/已有结果限制：强制重跑
      final n = await ScreenshotDatabase.instance.retrySegments([id], force: true);
      if (!mounted) return;
      final ok = n > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? AppLocalizations.of(context).regenerationQueued : AppLocalizations.of(context).alreadyQueuedOrFailed)),
      );
      // 开启轮询直到拿到结果为止；若原本就有结果，可能立即返回
      if (ok) _startResultWatch(id);
      // 如果没成功入队，停止旋转
      if (!ok) {
        setState(() {
          _retrying = false;
          _segmentData = Map<String, dynamic>.from(previous);
          _lastResultCreatedAt = previousCreatedAt;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _segmentData = Map<String, dynamic>.from(previous);
        _lastResultCreatedAt = previousCreatedAt;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).retryFailed)),
      );
    }
  }

  Future<void> _confirmAndDelete() async {
    final int id = (_segmentData['id'] as int?) ?? 0;
    if (id <= 0) return;

    final bool confirmed = await showUIDialog<bool>(
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
    ) ?? false;

    if (!confirmed) return;
    try {
      final ok = await ScreenshotDatabase.instance.deleteSegmentOnly(id);
      if (!mounted) return;
      if (ok) {
        UINotifier.success(context, AppLocalizations.of(context).eventDeletedToast);
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

  void _startResultWatch(int id) {
    _resultWatchTimer?.cancel();
    // 轮询间隔 2s；若拿到结果则停止旋转
    _resultWatchTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final res = await widget.loadResult(id);
        if (!mounted) return;
        if (res != null) {
          final int newCreatedAt = (res['created_at'] as int?) ?? 0;
          if (_lastResultCreatedAt != null && newCreatedAt > 0 && newCreatedAt <= _lastResultCreatedAt!) {
            return;
          }
          t.cancel();
          final merged = _mergeResultIntoSegment(_segmentData, res);
          setState(() {
            _retrying = false;
            _segmentData = merged;
            _lastResultCreatedAt = newCreatedAt > 0 ? newCreatedAt : _lastResultCreatedAt;
          });
          _latestExternalSegment = Map<String, dynamic>.from(merged);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).generateSuccess)),
          );
          try {
            await widget.onRefreshRequested();
          } catch (_) {}
        }
      } catch (_) {
        // 读取失败不影响轮询，继续尝试
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
      if (first is Map && first['detail'] is String) return (first['detail'] as String);
      if (first is String) return first;
    } else if (ka is Map && ka['detail'] is String) {
      return ka['detail'] as String;
    } else if (ka is String) {
      return ka;
    }
    return null;
  }

  List<String> _extractCategories(Map<String, dynamic>? result, Map<String, dynamic>? sj) {
    final List<String> out = <String>[];
    // 1) result.categories 可能是 JSON 或逗号分隔
    final raw = result?['categories'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final obj = jsonDecode(raw);
        if (obj is List) {
          out.addAll(obj.map((e) => e.toString()));
        } else {
          out.addAll(raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty));
        }
      } catch (_) {
        out.addAll(raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty));
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

  String _extractOverallSummary(Map<String, dynamic>? result, Map<String, dynamic>? sj) {
    final v = sj?['overall_summary'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    final out = (result?['output_text'] as String?)?.trim() ?? '';
    return out.toLowerCase() == 'null' ? '' : out;
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



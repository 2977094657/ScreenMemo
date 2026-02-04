import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_info.dart';
import '../models/screenshot_record.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_providers_service.dart';
import '../services/ai_settings_service.dart';
import '../services/app_selection_service.dart';
import '../services/flutter_logger.dart';
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';
import '../utils/merged_event_summary.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/screenshot_image_widget.dart';
import '../widgets/screenshot_style_tab_bar.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import 'daily_summary_page.dart';

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

  int _countDistinctDays(List<Map<String, dynamic>> segments) {
    final Set<String> keys = <String>{};
    for (final Map<String, dynamic> seg in segments) {
      final int ms = (seg['start_time'] as int?) ?? 0;
      if (ms <= 0) continue;
      keys.add(_dateKeyFromMillis(ms));
    }
    return keys.length;
  }

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
      setState(() {
        _privacyMode = enabled;
      });
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
      final ctxRow = await AISettingsService.instance.getAIContextRow(
        'segments',
      );
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
    try {
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
      if (mounted)
        setState(() {
          _privacyMode = enabled;
        });
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
    setState(() {
      _loading = true;
    });
    try {
      // 先触发一次原生端推进/补救：用于“删空某日后重建日期 Tab”等场景
      // ignore: unawaited_futures
      _db.triggerSegmentTick();
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
        final int totalDays = _countDistinctDays(segments);
        _maxVisibleDayTabs = math.min(_initialDayTabs, totalDays);
        _noMoreOlderSegments = false;
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
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  /// 从当前已加载的 segments 向前再拉取一批“更早日期”的事件
  /// - 仅在默认模式下生效（_onlyNoSummary=false）
  /// - 以当前最早事件所在日的前一刻作为上界，从 DB 拉取更早事件
  ///   （不设固定下界，允许跨越“空档期”继续向前翻到更早历史）
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
      if (!_noMoreOlderSegments) {
        setState(() => _noMoreOlderSegments = true);
      }
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
      final int endMs = endDay.millisecondsSinceEpoch;

      const int extraLimit = 800;
      final List<Map<String, dynamic>> more = await _db.listSegmentsEx(
        limit: extraLimit,
        onlyNoSummary: false,
        endMillis: endMs,
      );
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
      final int mergedTotalDays = _countDistinctDays(merged);

      setState(() {
        _segments = merged;
        // 向前扩展一个批次的日期窗口
        _maxVisibleDayTabs = math.min(
          mergedTotalDays,
          _maxVisibleDayTabs + _appendDayTabs,
        );
      });
    } finally {
      _isLoadingMoreDays = false;
    }
  }

  /// 处理“加载更多日期”动作：
  /// - 若当前 segments 中仍有更多日期尚未展示，则只增加可见天数
  /// - 若已经展示了所有已加载日期，尝试从数据库再加载更早一批
  Future<void> _handleLastDayTabReached() async {
    if (!mounted) return;

    // 基于当前 _segments 统计所有日期 key
    final Map<String, List<Map<String, dynamic>>> grouped =
        <String, List<Map<String, dynamic>>>{};
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
        _maxVisibleDayTabs = math.min(
          totalDays,
          _maxVisibleDayTabs + _appendDayTabs,
        );
      });
      return;
    }

    // 已经展示了当前数据中的所有日期，再尝试向前加载更早一批
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

  Future<void> _openImageGallery(
    List<Map<String, dynamic>> samples,
    int initialIndex,
  ) async {
    if (!mounted) return;
    try {
      // 尝试为查看器补充本段 AI 结构化结果（用于图片标签/描述等增强信息）
      String? aiStructuredJson;
      try {
        final int segId = samples.isNotEmpty
            ? ((samples.first['segment_id'] as int?) ?? 0)
            : 0;
        if (segId > 0) {
          final Map<String, dynamic>? result = await _db.getSegmentResult(
            segId,
          );
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
                                      color: Colors.orange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).mergedEventTag,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange,
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
                                          data: rawText,
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
    _autoTickCount = 0;
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
    _autoTickCount++;
    try {
      // 每次只做轻量查询；原生端 1s 心跳已持续推进/补救
      final segments = await _db.listSegmentsEx(limit: 50, onlyNoSummary: true);
      if (!mounted) return;
      setState(() {
        _segments = segments;
      });
      // 若已无“暂无总结”，停止自动检测
      final hasPending = segments.any(
        (e) => (e['has_summary'] as int? ?? 0) == 0,
      );
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
          isLoadingMoreDays: _isLoadingMoreDays,
          noMoreOlderSegments: _noMoreOlderSegments,
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
  final bool isLoadingMoreDays;
  final bool noMoreOlderSegments;
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
    required this.isLoadingMoreDays,
    required this.noMoreOlderSegments,
    this.onLastDayTabReached,
  });

  @override
  State<_SegmentTimelineTabView> createState() =>
      _SegmentTimelineTabViewState();
}

class _SegmentTimelineTabViewState extends State<_SegmentTimelineTabView>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> segments = widget.segments;

    if (segments.isEmpty) {
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
                  widget.activeHeader,
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

    // 仅展示“最近 maxVisibleDayTabs 个日期”，其余日期在用户滑动到末尾后再增量展示
    final int visibleCount = math.min(
      widget.maxVisibleDayTabs,
      orderedAll.length,
    );
    final List<String> ordered = orderedAll.take(visibleCount).toList();

    // 根据当前可见日期数量维护 TabController，尽量保留用户当前选中的索引
    if (_tabController == null || _tabController!.length != ordered.length) {
      final int currentIndex = _tabController?.index ?? 0;
      _tabController?.dispose();

      final int initialIndex = ordered.isEmpty
          ? 0
          : currentIndex.clamp(0, ordered.length - 1);
      _tabController = TabController(
        length: ordered.length,
        vsync: this,
        initialIndex: initialIndex,
      );
    }

    return Column(
      children: [
        Builder(
          builder: (context) {
            final bool hasHiddenTabs =
                widget.maxVisibleDayTabs < orderedAll.length;
            final bool canLoadMoreFromDb =
                !widget.onlyNoSummary &&
                widget.onLastDayTabReached != null &&
                !widget.noMoreOlderSegments;
            final bool showLoadMoreButton =
                widget.onLastDayTabReached != null &&
                (hasHiddenTabs || canLoadMoreFromDb);
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
                      Padding(
                        padding: const EdgeInsets.only(left: AppTheme.spacing2),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing2,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed:
                              (widget.onLastDayTabReached == null ||
                                  isLoadingMore)
                              ? null
                              : () {
                                  widget.onLastDayTabReached!.call();
                                },
                          icon: isLoadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.more_horiz, size: 18),
                          label: Text(
                            AppLocalizations.of(context).loadMore,
                          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing4,
                    vertical: AppTheme.spacing1,
                  ),
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
    final theme = Theme.of(context);
    return Card(
      // Daily summary entry should blend with the page background (user-selected).
      color: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      child: ListTile(
        leading: const Icon(Icons.event_note_outlined),
        title: Text(AppLocalizations.of(context).dailySummaryShort),
        subtitle: Text(AppLocalizations.of(context).viewOrGenerateForDay),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // 这里仍然使用 dateKey（YYYY-MM-DD）作为每日总结的键，与 DailySummaryPage 保持一致
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DailySummaryPage(dateKey: dateKey),
            ),
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

  @override
  Widget build(BuildContext context) {
    final int id = (_segmentData['id'] as int?) ?? 0;
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
    final Map<String, dynamic>? structured = _tryParseJson(
      _segmentData['structured_json'] as String?,
    );
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
    final List<String> categories = _extractCategories(resultMeta, structured);
    final String computedSummary = _extractOverallSummary(
      resultMeta,
      structured,
    );
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
          _timeSeparator(context, label: timeLabel, keyActionDetail: keyAction),
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
                tooltip: AppLocalizations.of(context).actionRegenerate,
                onPressed: _retrying
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
  }) {
    final Color actionColor = AppTheme.warning; // 使用更醒目的警告色
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: Center(
            child: Text(label, style: DefaultTextStyle.of(context).style),
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
    // 关键：不设置 alignment，不用 ConstrainedBox 包裹宽度；仅设置最小高度，宽度随文本自适应
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
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

  MarkdownBody _buildMarkdownBody(
    BuildContext context,
    String data,
    TextStyle? textStyle,
  ) {
    return MarkdownBody(
      data: data,
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
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: 0,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTheme.spacing3,
            0,
            AppTheme.spacing3,
            AppTheme.spacing3,
          ),
          leading: Icon(Icons.merge_type, size: 16, color: cs.onSurfaceVariant),
          title: Row(
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
                    padding: const EdgeInsets.symmetric(vertical: 6),
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
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async => _forceMerge(),
                  child: const Text('强制合并'),
                ),
            ],
          ),
          children: [
            if (reasonText.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
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

  void _startResultWatch(int id) {
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
          final String finalSummary = _extractOverallSummary({
            'output_text': merged['output_text'],
            'categories': merged['categories'],
          }, _tryParseJson(merged['structured_json'] as String?));
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).generateSuccess),
            ),
          );
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
        final String finalSummary = _extractOverallSummary({
          'output_text': mergedSeg['output_text'],
          'categories': mergedSeg['categories'],
        }, _tryParseJson(mergedSeg['structured_json'] as String?));
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

  String _extractOverallSummary(
    Map<String, dynamic>? result,
    Map<String, dynamic>? sj,
  ) {
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

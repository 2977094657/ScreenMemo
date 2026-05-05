part of 'search_page.dart';

// ========== 搜索筛选与范围处理 ==========
extension _SearchPageFilterPart on _SearchPageState {
  // 将当前筛选转换为数据库参数
  (int, int)? _currentTimeRange() {
    if (_timeFilter == 'all') return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int? s;
    int? e;
    switch (_timeFilter) {
      case 'today':
        s = today.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        s = y.millisecondsSinceEpoch;
        e = today.millisecondsSinceEpoch - 1;
        break;
      case 'last7days':
        final last7 = today.subtract(const Duration(days: 7));
        s = last7.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'last30days':
        final last30 = today.subtract(const Duration(days: 30));
        s = last30.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'customDays':
        final lastN = today.subtract(Duration(days: _customDays));
        s = lastN.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          s = DateTime(
            _customStartDate!.year,
            _customStartDate!.month,
            _customStartDate!.day,
          ).millisecondsSinceEpoch;
          e = DateTime(
            _customEndDate!.year,
            _customEndDate!.month,
            _customEndDate!.day,
            23,
            59,
            59,
          ).millisecondsSinceEpoch;
        }
        break;
    }
    if (s == null || e == null) return null;
    return (s, e);
  }

  (int, int)? _currentSizeRange() {
    if (_sizeFilter == 'all') return null;
    switch (_sizeFilter) {
      case 'small':
        return (0, 100 * 1024);
      case 'medium':
        return (100 * 1024, 1024 * 1024);
      case 'large':
        return (1024 * 1024, 1 << 31);
    }
    return null;
  }

  // 重置筛选条件
  void _resetFilters() {
    _searchSetState(() {
      _timeFilter = 'last30days';
      _sizeFilter = 'all';
      _customStartDate = null;
      _customEndDate = null;
    });
    // 重新执行搜索以应用重置后的筛选条件
    if (_lastQuery.isNotEmpty) {
      _search(_lastQuery);
    }
  }

  // 显示筛选对话框
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterSheet(
        timeFilter: _timeFilter,
        sizeFilter: _sizeFilter,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
        onApply: (time, size, startDate, endDate) {
          _searchSetState(() {
            _timeFilter = time;
            _sizeFilter = size;
            _customStartDate = startDate;
            _customEndDate = endDate;
          });
          // 重新执行搜索以应用新的筛选条件
          if (_lastQuery.isNotEmpty) {
            _search(_lastQuery);
          }
        },
        onReset: _resetFilters,
      ),
    );
  }

  Future<Map<String, dynamic>?> _ensureBoxes(String filePath) async {
    if (_lastQuery.isEmpty) return null;
    if (_usingAiImageMeta || _usingFavoriteNotes) return null;
    final key = '$filePath|$_lastQuery';
    final fut = _boxesFutureCache.putIfAbsent(key, () {
      return ScreenshotService.instance.getOcrMatchBoxes(
        filePath: filePath,
        query: _lastQuery,
      );
    });
    return fut;
  }

  void _openViewer(ScreenshotRecord record, int index) {
    final List<ScreenshotRecord> sameApp = _results
        .where((r) => r.appPackageName == record.appPackageName)
        .toList();
    final int initialIndex = sameApp.indexWhere((r) => r.id == record.id);
    // 从缓存中获取完整的应用信息（包含 icon）
    final appInfo =
        _appInfoByPackage[record.appPackageName] ??
        AppInfo(
          packageName: record.appPackageName,
          appName: record.appName,
          icon: null,
          version: '',
          isSystemApp: false,
        );
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': sameApp,
        'initialIndex': initialIndex < 0 ? 0 : initialIndex,
        'appName': record.appName,
        'appInfo': appInfo,
      },
    );
  }

  void _openSemanticViewer(ScreenshotRecord record, int index) {
    final List<ScreenshotRecord> pool = _filteredSemanticResults;
    if (pool.isEmpty) return;
    final String pkg = record.appPackageName.trim();
    final List<ScreenshotRecord> sameApp = pkg.isEmpty
        ? pool
        : pool.where((r) => r.appPackageName.trim() == pkg).toList();
    final int initialIndex = sameApp.indexWhere(
      (r) => r.filePath == record.filePath,
    );
    final appInfo =
        _appInfoByPackage[pkg] ??
        AppInfo(
          packageName: pkg.isNotEmpty ? pkg : record.appPackageName,
          appName: record.appName,
          icon: null,
          version: '',
          isSystemApp: false,
        );
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': sameApp,
        'initialIndex': initialIndex < 0 ? 0 : initialIndex,
        'appName': record.appName,
        'appInfo': appInfo,
      },
    );
  }

  // 获取时间范围显示文本
  String _getTimeRangeLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_timeFilter) {
      case 'all':
        return l10n.filterTimeAll;
      case 'today':
        return l10n.filterTimeToday;
      case 'yesterday':
        return l10n.filterTimeYesterday;
      case 'last7days':
        return l10n.filterTimeLast7Days;
      case 'last30days':
        return l10n.filterTimeLast30Days;
      case 'customDays':
        return '${_customDays}${l10n.days}';
      default:
        return l10n.filterTimeLast30Days;
    }
  }

  // 显示时间范围选择底部弹窗
  void _showTimeRangeSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return UISheetSurface(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacing4,
                  0,
                  AppTheme.spacing4,
                  AppTheme.spacing4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const Center(child: UISheetHandle()),
                    const SizedBox(height: AppTheme.spacing3),
                    Text(
                      l10n.filterByTime,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    // 时间选项（与筛选 Chip 一致的紧凑间距）
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _buildTimeChip(
                          ctx,
                          'all',
                          l10n.filterTimeAll,
                          setSheetState,
                        ),
                        _buildTimeChip(
                          ctx,
                          'today',
                          l10n.filterTimeToday,
                          setSheetState,
                        ),
                        _buildTimeChip(
                          ctx,
                          'yesterday',
                          l10n.filterTimeYesterday,
                          setSheetState,
                        ),
                        _buildTimeChip(
                          ctx,
                          'last7days',
                          l10n.filterTimeLast7Days,
                          setSheetState,
                        ),
                        _buildTimeChip(
                          ctx,
                          'last30days',
                          l10n.filterTimeLast30Days,
                          setSheetState,
                        ),
                        _buildCustomDaysChip(ctx, l10n, setSheetState),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 构建时间选项 Chip
  Widget _buildTimeChip(
    BuildContext ctx,
    String value,
    String label,
    StateSetter setSheetState,
  ) {
    final bool selected = _timeFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: selected
              ? Theme.of(ctx).colorScheme.primary
              : Theme.of(ctx).colorScheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      selectedColor: Theme.of(ctx).colorScheme.primary.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: selected
            ? BorderSide.none
            : BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      onSelected: (_) {
        _searchSetState(() => _timeFilter = value);
        setSheetState(() {});
        Navigator.pop(ctx);
        if (_lastQuery.isNotEmpty) _search(_lastQuery);
      },
    );
  }

  // 构建自定义天数 Chip
  Widget _buildCustomDaysChip(
    BuildContext ctx,
    AppLocalizations l10n,
    StateSetter setSheetState,
  ) {
    final bool selected = _timeFilter == 'customDays';
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selected ? '${_customDays}${l10n.days}' : l10n.filterTimeCustomDays,
            style: TextStyle(
              fontSize: 12,
              color: selected
                  ? Theme.of(ctx).colorScheme.primary
                  : Theme.of(ctx).colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.edit_outlined,
            size: 12,
            color: selected
                ? Theme.of(ctx).colorScheme.primary
                : Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6),
          ),
        ],
      ),
      selected: selected,
      showCheckmark: false,
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      selectedColor: Theme.of(ctx).colorScheme.primary.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: selected
            ? BorderSide.none
            : BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      onSelected: (_) async {
        Navigator.pop(ctx);
        await _showCustomDaysDialog();
      },
    );
  }

  // 显示自定义天数输入对话框（使用项目自定义弹窗）
  Future<void> _showCustomDaysDialog() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _customDays.toString());

    final result = await showUIDialog<int>(
      context: context,
      title: l10n.filterTimeCustomDays,
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: l10n.filterTimeCustomDaysHint,
          suffixText: l10n.days,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
      actions: [
        UIDialogAction<int>(
          text: l10n.dialogCancel,
          style: UIDialogActionStyle.normal,
        ),
        UIDialogAction<int>(
          text: l10n.dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final val = int.tryParse(controller.text.trim());
            if (val != null && val > 0 && val <= 365) {
              Navigator.of(ctx).pop<int>(val);
            }
          },
        ),
      ],
    );

    if (result != null) {
      _searchSetState(() {
        _customDays = result;
        _timeFilter = 'customDays';
      });
      if (_lastQuery.isNotEmpty) {
        _search(_lastQuery);
      }
    }
  }

  // 构建时间范围按钮（嵌入搜索框内，简洁无背景）
  Widget _buildTimeRangeDropdown() {
    final color = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    return GestureDetector(
      onTap: _showTimeRangeSheet,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getTimeRangeLabel(),
              style: TextStyle(fontSize: 12, color: color),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

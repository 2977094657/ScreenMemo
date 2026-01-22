import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/app_info.dart';
import '../services/app_selection_service.dart';
import 'ui_dialog.dart';

/// 应用选择组件
class AppSelectionWidget extends StatefulWidget {
  final Function(List<AppInfo>)? onSelectionChanged;
  final bool displayAsList;
  
  const AppSelectionWidget({
    super.key,
    this.onSelectionChanged,
    this.displayAsList = false,
  });

  @override
  State<AppSelectionWidget> createState() => _AppSelectionWidgetState();
}

class _AppSelectionWidgetState extends State<AppSelectionWidget> {
  final AppSelectionService _appService = AppSelectionService.instance;
  final TextEditingController _searchController = TextEditingController();
  static const Set<String> _pinduoduoPackages = {
    'com.xunmeng.pinduoduo',
    'com.xunmeng.pinduoduo.lite',
  };
  
  List<AppInfo> _allApps = [];
  List<AppInfo> _filteredApps = [];
  List<AppInfo> _selectedApps = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filteredApps = _appService.searchApps(_searchQuery);
    });
  }

  Future<void> _loadApps() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取所有应用（优先缓存，必要时后台刷新）
      _allApps = await _appService.getAllInstalledApps();
      // 触发过期时的后台刷新，不阻塞当前UI
      // ignore: unawaited_futures
      _appService.refreshAppsInBackgroundIfStale();
      
      // 获取之前选中的应用
      final selectedApps = await _appService.getSelectedApps();
      
      // 更新选中状态
      for (final app in _allApps) {
        app.isSelected = selectedApps.any((selected) => selected.packageName == app.packageName);
      }
      
      _selectedApps = _allApps.where((app) => app.isSelected).toList();
      _filteredApps = _allApps;
      
    } catch (e) {
      print('加载应用失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isPinduoduoApp(AppInfo app) {
    final package = app.packageName.toLowerCase();
    if (_pinduoduoPackages.contains(package)) {
      return true;
    }

    final name = app.appName.toLowerCase();
    return name.contains('拼多多') || name.contains('pinduoduo');
  }

  Future<bool> _confirmPinduoduoSelection(AppInfo app) async {
    if (app.isSelected || !_isPinduoduoApp(app)) {
      return true;
    }

    final l10n = AppLocalizations.of(context);
    final result = await showUIDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: l10n.pinduoduoWarningTitle,
      message: l10n.pinduoduoWarningMessage,
      actions: [
        UIDialogAction<bool>(
          text: l10n.pinduoduoWarningCancel,
          result: false,
        ),
        UIDialogAction<bool>(
          text: l10n.pinduoduoWarningKeep,
          style: UIDialogActionStyle.primary,
          result: true,
        ),
      ],
    );

    return result ?? false;
  }

  Future<void> _toggleAppSelection(AppInfo app) async {
    if (!await _confirmPinduoduoSelection(app)) {
      return;
    }

    if (!mounted) return;

    setState(() {
      app.isSelected = !app.isSelected;

      if (app.isSelected) {
        _selectedApps.add(app);
      } else {
        _selectedApps.removeWhere((selected) => selected.packageName == app.packageName);
      }
    });

    widget.onSelectionChanged?.call(_selectedApps);
  }

  Future<void> _selectAll() async {
    // 先检查当前筛选列表中是否包含未选中的拼多多应用
    bool skipPinduoduo = false;
    for (final app in _filteredApps) {
      if (!app.isSelected && _isPinduoduoApp(app)) {
        final allowPinduoduo = await _confirmPinduoduoSelection(app);
        // 用户点击“取消选择”时，只跳过拼多多的选择，仍然对其他应用执行全选
        if (!allowPinduoduo) {
          skipPinduoduo = true;
        }
        break;
      }
    }

    if (!mounted) return;

    setState(() {
      for (final app in _filteredApps) {
        // 如果需要跳过拼多多，则仅对非拼多多应用执行全选
        if (!app.isSelected &&
            !(skipPinduoduo && _isPinduoduoApp(app))) {
          app.isSelected = true;
          if (!_selectedApps.contains(app)) {
            _selectedApps.add(app);
          }
        }
      }
    });
    
    widget.onSelectionChanged?.call(_selectedApps);
  }

  void _clearAll() {
    setState(() {
      for (final app in _filteredApps) {
        if (app.isSelected) {
          app.isSelected = false;
          _selectedApps.removeWhere((selected) => selected.packageName == app.packageName);
        }
      }
    });
    
    widget.onSelectionChanged?.call(_selectedApps);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color surface = isDark ? theme.colorScheme.surface : theme.scaffoldBackgroundColor;
    return Column(
      children: [
        // 搜索栏和统计信息
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacing4, // left
            AppTheme.spacing3, // top - 减少顶部内边距
            AppTheme.spacing4, // right
            AppTheme.spacing2, // bottom
          ),
          decoration: BoxDecoration(
            color: surface,
          ),
          child: Column(
            children: [
              // 搜索栏
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).appSearchPlaceholder,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing3,
                    vertical: AppTheme.spacing2,
                  ),
                ),
              ),

              const SizedBox(height: AppTheme.spacing3),

              // 统计和操作按钮
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing2,
                      vertical: AppTheme.spacing1,
                    ),
                    decoration: BoxDecoration(
                      color: _selectedApps.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Text(
                      AppLocalizations.of(context).selectedCount(_selectedApps.length),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _selectedApps.isNotEmpty
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 刷新按钮：强制刷新应用列表
                  IconButton(
                    tooltip: AppLocalizations.of(context).refreshAppsTooltip,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () async {
                      setState(() { _isLoading = true; });
                      try {
                        _allApps = await _appService.getAllInstalledApps(forceRefresh: true);
                        final selectedApps = await _appService.getSelectedApps();
                        for (final app in _allApps) {
                          app.isSelected = selectedApps.any((s) => s.packageName == app.packageName);
                        }
                        _selectedApps = _allApps.where((a) => a.isSelected).toList();
                        _filteredApps = _searchController.text.isEmpty
                            ? _allApps
                            : _appService.searchApps(_searchController.text);
                      } catch (e) {
                        // ignore
                      } finally {
                        if (mounted) {
                          setState(() { _isLoading = false; });
                        }
                      }
                    },
                  ),
                  TextButton(
                    onPressed: () { _selectAll(); },
                    child: Text(AppLocalizations.of(context).selectAll, style: const TextStyle(fontSize: 14)),
                  ),
                  TextButton(
                    onPressed: _clearAll,
                    child: Text(AppLocalizations.of(context).clearAll, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 应用列表（支持网格或列表样式）
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredApps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.search_off,
                            size: 48,
                            color: AppTheme.mutedForeground,
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                          Text(
                            _searchQuery.isEmpty ? AppLocalizations.of(context).noAppsFound : AppLocalizations.of(context).noAppsMatched,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppTheme.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    )
                  : (widget.displayAsList
                      ? ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacing2,
                            vertical: AppTheme.spacing1,
                          ),
                          itemCount: _filteredApps.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacing1),
                          itemBuilder: (context, index) {
                            final app = _filteredApps[index];
                            return _buildAppListItem(app);
                          },
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacing3, // left
                            AppTheme.spacing2, // top - 减少顶部间距
                            AppTheme.spacing3, // right
                            AppTheme.spacing3, // bottom
                          ),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4, // 4列紧凑布局
                            crossAxisSpacing: AppTheme.spacing2,
                            mainAxisSpacing: AppTheme.spacing3, // 稍微增加垂直间距
                            childAspectRatio: 0.8, // 调整高宽比，给文字更多空间
                          ),
                          itemCount: _filteredApps.length,
                          itemBuilder: (context, index) {
                            final app = _filteredApps[index];
                            return _buildAppGridItem(app);
                          },
                        )),
        ),
      ],
    );
  }

  Widget _buildAppGridItem(AppInfo app) {
    return GestureDetector(
      onTap: () { _toggleAppSelection(app); },
      child: Container(
        decoration: BoxDecoration(
          color: app.isSelected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: app.isSelected ? Border.all(
            color: AppTheme.primary,
            width: 1.0, // 进一步减少边框粗细
          ) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 应用图标 - 直接显示，无容器
            Stack(
              children: [
                // 应用图标
                SizedBox(
                  width: 48,
                  height: 48,
                  child: app.icon != null
                      ? Image.memory(
                          app.icon!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.contain, // 改为contain避免裁剪
                        )
                      : const Icon(
                          Icons.android,
                          color: AppTheme.mutedForeground,
                          size: 32,
                        ),
                ),

                // 选择状态覆盖层 - 更优雅的设计
                if (app.isSelected)
                  Positioned(
                    right: 0,
                    bottom: 0,
            child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                // 去掉白色描边
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppTheme.spacing2),

            // 应用名称
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing1),
              child: Text(
                app.appName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: app.isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: app.isSelected ? AppTheme.primary : null,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppListItem(AppInfo app) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { _toggleAppSelection(app); },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing4,
            vertical: AppTheme.spacing2,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: app.icon != null
                    ? Image.memory(
                        app.icon!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                      )
                    : const Icon(
                        Icons.android,
                        color: AppTheme.mutedForeground,
                        size: 28,
                      ),
              ),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Text(
                  app.appName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Checkbox(
                value: app.isSelected,
                onChanged: (_) { _toggleAppSelection(app); },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

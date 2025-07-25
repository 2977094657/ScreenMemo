import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/app_selection_service.dart';
import '../models/app_info.dart';

/// 统计页面
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final AppSelectionService _appService = AppSelectionService.instance;
  
  List<AppInfo> _selectedApps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final selectedApps = await _appService.getSelectedApps();
      setState(() {
        _selectedApps = selectedApps;
      });
    } catch (e) {
      print('加载统计数据失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                children: [
                  // 总览卡片
                  _buildOverviewCard(),
                  
                  const SizedBox(height: AppTheme.spacing4),
                  
                  // 应用统计
                  _buildAppStatisticsCard(),
                  
                  const SizedBox(height: AppTheme.spacing4),
                  
                  // 使用趋势
                  _buildUsageTrendCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildOverviewCard() {
    return UICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: AppTheme.primary),
              const SizedBox(width: AppTheme.spacing2),
              Text(
                '总览',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          
          const SizedBox(height: AppTheme.spacing4),
          
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  title: '监控应用',
                  value: '${_selectedApps.length}',
                  icon: Icons.apps,
                  color: AppTheme.primary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  title: '总截图',
                  value: '0', // TODO: 实际统计数据
                  icon: Icons.photo_library,
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: AppTheme.spacing4),
          
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  title: '今日截图',
                  value: '0', // TODO: 实际统计数据
                  icon: Icons.today,
                  color: AppTheme.info,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  title: '存储占用',
                  value: '0 MB', // TODO: 实际统计数据
                  icon: Icons.storage,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAppStatisticsCard() {
    return UICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: AppTheme.primary),
              const SizedBox(width: AppTheme.spacing2),
              Text(
                '应用统计',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          
          const SizedBox(height: AppTheme.spacing4),
          
          if (_selectedApps.isEmpty)
            Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.apps,
                    size: 48,
                    color: AppTheme.mutedForeground,
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  Text(
                    '暂无监控应用',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  Text(
                    '请在设置中选择要监控的应用',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._selectedApps.map((app) => _buildAppStatItem(app)),
        ],
      ),
    );
  }

  Widget _buildAppStatItem(AppInfo app) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              color: AppTheme.secondary,
            ),
            child: app.icon != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: Image.memory(
                      app.icon!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(
                    Icons.android,
                    color: AppTheme.mutedForeground,
                  ),
          ),
          
          const SizedBox(width: AppTheme.spacing3),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '截图数量: 0 | 最后截图: 暂无', // TODO: 实际统计数据
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          
          const Icon(
            Icons.chevron_right,
            color: AppTheme.mutedForeground,
          ),
        ],
      ),
    );
  }

  Widget _buildUsageTrendCard() {
    return UICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: AppTheme.primary),
              const SizedBox(width: AppTheme.spacing2),
              Text(
                '使用趋势',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          
          const SizedBox(height: AppTheme.spacing4),
          
          Center(
            child: Column(
              children: [
                const Icon(
                  Icons.show_chart,
                  size: 64,
                  color: AppTheme.mutedForeground,
                ),
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  '趋势图表',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  '功能开发中，敬请期待',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

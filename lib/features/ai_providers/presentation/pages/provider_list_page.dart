// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import 'package:screen_memo/app/navigation/route_observer.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/core/widgets/model_logo.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/features/ai_providers/presentation/pages/provider_edit_page.dart';

/// 提供商列表页：
/// - 右上角「新建」
/// - 列表展示：名称、模型数量、Key 服务状态
/// - 操作：编辑、删除、设为默认、启用/禁用
/// - 点击列表项或编辑进入详情
class ProviderListPage extends StatefulWidget {
  const ProviderListPage({super.key});

  @override
  State<ProviderListPage> createState() => _ProviderListPageState();
}

class _ProviderListPageState extends State<ProviderListPage> with RouteAware {
  final _svc = AIProvidersService.instance;

  bool _loading = true;
  List<AIProvider> _list = <AIProvider>[];
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _svc.listProviders();
      if (!mounted) return;
      setState(() => _list = rows);
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).pleaseTryAgain);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatBalanceTotal(double value) {
    final rounded = value.toStringAsFixed(value.abs() >= 100 ? 2 : 4);
    return rounded
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String? _providerBalanceSummary(AIProvider provider) {
    final summary = provider.keySummary;
    if (!provider.hasBalanceQuery || summary.totalCount == 0) return null;
    if (!summary.hasKnownBalance) return '总余额 —';
    if (summary.numericBalanceCount == 0) {
      if (summary.totalCount == 1) {
        return '余额 ${summary.balanceDisplay ?? '已获取'}';
      }
      return '余额已获取 ${summary.knownBalanceCount}/${summary.totalCount}';
    }
    final currency = summary.balanceCurrency == null
        ? ''
        : ' ${summary.balanceCurrency}';
    final partial = summary.numericBalanceCount < summary.totalCount
        ? '（${summary.numericBalanceCount}/${summary.totalCount}）'
        : '';
    return '总余额 ${_formatBalanceTotal(summary.balanceTotal ?? 0)}$currency$partial';
  }

  Widget _buildProviderKeySummary(AIProvider p) {
    final theme = Theme.of(context);
    final summary = p.keySummary;
    final totalCount = summary.totalCount;
    final enabledCount = summary.enabledCount;
    final coolingCount = summary.coolingCount;
    final errorCount = summary.errorCount;
    final successTotal = summary.successTotal;
    final failureTotal = summary.failureTotal;
    final totalAttempts = successTotal + failureTotal;
    final successRate = totalAttempts == 0
        ? 1.0
        : successTotal / totalAttempts.clamp(1, 1 << 30);
    final availableCount = summary.availableCount;

    late final String statusLabel;
    late final Color statusColor;
    if (totalCount == 0) {
      statusLabel = '无密钥';
      statusColor = theme.colorScheme.onSurfaceVariant;
    } else if (enabledCount == 0) {
      statusLabel = '已停用';
      statusColor = theme.colorScheme.onSurfaceVariant;
    } else if (totalAttempts == 0) {
      statusLabel = '从未调用';
      statusColor = AppTheme.info;
    } else if (coolingCount > 0) {
      statusLabel = '冷却中';
      statusColor = AppTheme.warning;
    } else if (errorCount > 0 && availableCount > 0) {
      statusLabel = '部分异常';
      statusColor = AppTheme.warning;
    } else if (failureTotal > 0 && successTotal == 0) {
      statusLabel = '最近失败';
      statusColor = theme.colorScheme.error;
    } else if (successRate < 0.90) {
      statusLabel = '低成功率';
      statusColor = AppTheme.warning;
    } else if (errorCount > 0) {
      statusLabel = '部分异常';
      statusColor = AppTheme.warning;
    } else {
      statusLabel = '运行正常';
      statusColor = AppTheme.success;
    }

    final uptimeText = totalAttempts == 0
        ? '暂无调用记录'
        : '成功率 ${(successRate * 100).toStringAsFixed(2)}%';
    final availableText = '可用 $availableCount / 总计 $totalCount';
    final balanceSummary = _providerBalanceSummary(p);

    return Container(
      margin: const EdgeInsets.only(top: AppTheme.spacing2),
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.20),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.18),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                totalCount == 0 ? '密钥' : '$totalCount 个密钥 / $enabledCount 个启用',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                statusLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          _buildStatusBars(summary),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                totalAttempts == 0
                    ? '暂无记录'
                    : '成功 $successTotal / 失败 $failureTotal',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(height: 1),
                ),
              ),
              Text(
                uptimeText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(height: 1),
                ),
              ),
              Text(
                availableText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (balanceSummary != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  balanceSummary,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBars(AIProviderKeySummary summary) {
    final theme = Theme.of(context);
    const barCount = 72;
    if (summary.totalCount == 0 || summary.enabledCount == 0) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: List.generate(
            barCount,
            (index) => Expanded(
              child: Container(
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final totalAttempts = summary.successTotal + summary.failureTotal;
    if (totalAttempts == 0) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: List.generate(
            barCount,
            (index) => Expanded(
              child: Container(
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: AppTheme.info.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final failureRatio = summary.failureTotal / totalAttempts.clamp(1, 1 << 30);
    final issueRatio =
        ((failureRatio * barCount).ceil() +
                summary.errorCount +
                summary.coolingCount)
            .clamp(0, barCount);
    final coolingStart = (barCount * 0.56).round();
    final errorSeed =
        (summary.failureTotal +
            summary.errorCount * 7 +
            summary.coolingCount * 11) %
        barCount;
    final latestSuccessAt = summary.latestSuccessAt ?? 0;
    final latestFailureAt = summary.latestFailedAt ?? 0;
    final latestKnownResultIsFailure = latestFailureAt > latestSuccessAt;
    final placeIssueAtEnd =
        latestKnownResultIsFailure ||
        (latestSuccessAt == 0 &&
            latestFailureAt == 0 &&
            summary.successTotal == 0);

    bool isIssueSlot(int index) {
      if (issueRatio == 0) return false;
      return placeIssueAtEnd
          ? index >= barCount - issueRatio
          : index < issueRatio;
    }

    Color colorFor(int index) {
      if (issueRatio == 0) return AppTheme.success;
      final seededError = isIssueSlot(index) && ((index + errorSeed) % 23 == 0);
      final recentError = isIssueSlot(index);
      final cooling =
          summary.coolingCount > 0 &&
          index >= coolingStart &&
          index < coolingStart + summary.coolingCount.clamp(1, 6);
      if (recentError || seededError) return theme.colorScheme.error;
      if (cooling) return AppTheme.warning;
      return AppTheme.success;
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: List.generate(
          barCount,
          (index) => Expanded(
            child: Container(
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: colorFor(index),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onNew() async {
    final ok = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ProviderEditPage()));
    if (ok == true) await _load();
  }

  Future<void> _onEdit(AIProvider p) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProviderEditPage(providerId: p.id)),
    );
    if (ok == true) await _load();
  }

  Future<void> _onToggleEnable(AIProvider p) async {
    final ok = await _svc.updateProvider(id: p.id!, enabled: !p.enabled);
    if (!ok) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    await _load();
  }

  Future<void> _onSetDefault(AIProvider p) async {
    final ok = await _svc.setDefault(p.id!);
    if (!ok) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    UINotifier.success(context, AppLocalizations.of(context).saveSuccess);
    await _load();
  }

  Future<void> _onDelete(AIProvider p) async {
    final t = AppLocalizations.of(context);
    final confirm =
        await showUIDialog<bool>(
          context: context,
          title: t.deleteGroup,
          message: t.confirmDeleteProviderMessage(p.name),
          actions: [
            UIDialogAction<bool>(text: t.dialogCancel, result: false),
            UIDialogAction<bool>(
              text: t.actionDelete,
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
        ) ??
        false;
    if (!confirm) return;
    final ok = await _svc.deleteProvider(p.id!);
    if (!ok) {
      // 二次校验：若数据库中已无此记录，按成功处理，避免误报失败
      final still = await _svc.getProvider(p.id!);
      if (still != null) {
        UINotifier.error(context, t.deleteFailed);
        return;
      }
    }
    UINotifier.success(context, t.deletedToast);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).providersTitle),
        actions: [
          TextButton.icon(
            onPressed: _onNew,
            icon: Icon(Icons.add),
            label: Text(AppLocalizations.of(context).actionNew),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: _list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Text(
                            AppLocalizations.of(context).noProvidersYetHint,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.spacing2,
                      ),
                      itemCount: _list.length,
                      separatorBuilder: (context, _) => Container(
                        height: 1,
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.6),
                      ),
                      itemBuilder: (context, index) {
                        final p = _list[index];
                        final modelsCount = p.models.length;

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacing2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                              onTap: () => _onEdit(p),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.spacing3,
                                  vertical: AppTheme.spacing3,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceVariant
                                                .withOpacity(0.5),
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd,
                                            ),
                                          ),
                                          padding: const EdgeInsets.all(10),
                                          child: ProviderLogo(
                                            providerType: p.type,
                                            providerName: p.name,
                                            baseUrl: p.baseUrl,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(
                                          width: AppTheme.spacing3,
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      letterSpacing: 0.15,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondaryContainer
                                                .withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusSm,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline
                                                  .withOpacity(0.2),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.inventory_2_outlined,
                                                size: 15,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondaryContainer,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                modelsCount.toString(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSecondaryContainer,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(
                                          width: AppTheme.spacing2,
                                        ),
                                        IconButton(
                                          tooltip: AppLocalizations.of(
                                            context,
                                          ).actionDelete,
                                          icon: Icon(
                                            Icons.delete_outline,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                          onPressed: () => _onDelete(p),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppTheme.spacing2),
                                    _buildProviderKeySummary(p),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:screen_memo/widgets/ui_components.dart';
import 'package:screen_memo/widgets/ui_dialog.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../services/ai_providers_service.dart';
import '../utils/model_icon_utils.dart';
import '../theme/app_theme.dart';
import 'provider_edit_page.dart';

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

class _ProviderListPageState extends State<ProviderListPage> {
  final _svc = AIProvidersService.instance;

  bool _loading = true;
  List<AIProvider> _list = <AIProvider>[];
  final Map<int, List<AIProviderKey>> _keysByProvider =
      <int, List<AIProviderKey>>{};
  @override
  void initState() {
    super.initState();
    // 预加载图标清单，确保首屏动态图标匹配（含无 -color 后缀）
    ModelIconUtils.preload();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _svc.listProviders();
      final nextKeys = <int, List<AIProviderKey>>{};
      for (final provider in rows) {
        final id = provider.id;
        if (id == null) continue;
        nextKeys[id] = await _svc.listProviderKeys(id);
      }
      setState(() {
        _list = rows;
        _keysByProvider
          ..clear()
          ..addAll(nextKeys);
      });
    } catch (e) {
      UINotifier.error(context, AppLocalizations.of(context).pleaseTryAgain);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _typeLabel(String t) {
    switch (t) {
      case AIProviderTypes.openai:
        return 'OpenAI';
      case AIProviderTypes.azureOpenAI:
        return 'Azure OpenAI';
      case AIProviderTypes.claude:
        return 'Claude';
      case AIProviderTypes.gemini:
        return 'Gemini';
      case AIProviderTypes.custom:
        return AppLocalizations.of(context).customLabel;
      default:
        return t;
    }
  }

  String _briefUrl(String? url) {
    final s = (url ?? '').trim();
    if (s.isEmpty) return '-';
    return s.length > 48 ? '${s.substring(0, 48)}' + '…' : s;
  }

  Widget _buildProviderKeySummary(AIProvider p) {
    final theme = Theme.of(context);
    final keys = _keysByProvider[p.id ?? -1] ?? const <AIProviderKey>[];
    final totalCount = keys.length;
    final enabledCount = keys.where((key) => key.enabled).length;
    final coolingCount = keys.where((key) => key.isCoolingDown()).length;
    final errorCount = keys
        .where((key) => (key.lastErrorType ?? '').trim().isNotEmpty)
        .length;
    final successTotal = keys.fold<int>(
      0,
      (sum, key) => sum + key.successCount,
    );
    final failureTotal = keys.fold<int>(
      0,
      (sum, key) => sum + key.failureTotalCount,
    );
    final totalAttempts = successTotal + failureTotal;
    final successRate = totalAttempts == 0
        ? 1.0
        : successTotal / totalAttempts.clamp(1, 1 << 30);
    final availableCount = keys
        .where(
          (key) =>
              key.enabled &&
              !key.isCoolingDown() &&
              (key.lastErrorType ?? '').trim().isEmpty,
        )
        .length;

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
          _buildStatusBars(
            keys: keys,
            enabledCount: enabledCount,
            successTotal: successTotal,
            failureTotal: failureTotal,
            errorCount: errorCount,
            coolingCount: coolingCount,
          ),
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
        ],
      ),
    );
  }

  Widget _buildStatusBars({
    required List<AIProviderKey> keys,
    required int enabledCount,
    required int successTotal,
    required int failureTotal,
    required int errorCount,
    required int coolingCount,
  }) {
    final theme = Theme.of(context);
    const barCount = 72;
    if (keys.isEmpty || enabledCount == 0) {
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

    final totalAttempts = successTotal + failureTotal;
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

    final failureRatio = failureTotal / totalAttempts.clamp(1, 1 << 30);
    final issueRatio =
        ((failureRatio * barCount).ceil() + errorCount + coolingCount).clamp(
          0,
          barCount,
        );
    final coolingStart = (barCount * 0.56).round();
    final errorSeed =
        (failureTotal + errorCount * 7 + coolingCount * 11) % barCount;
    final latestSuccessAt = keys.fold<int>(0, (latest, key) {
      final value = key.lastSuccessAt ?? 0;
      return value > latest ? value : latest;
    });
    final latestFailureAt = keys.fold<int>(0, (latest, key) {
      final value = key.lastFailedAt ?? 0;
      return value > latest ? value : latest;
    });
    final latestKnownResultIsFailure = latestFailureAt > latestSuccessAt;
    final placeIssueAtEnd =
        latestKnownResultIsFailure ||
        (latestSuccessAt == 0 && latestFailureAt == 0 && successTotal == 0);

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
          coolingCount > 0 &&
          index >= coolingStart &&
          index < coolingStart + coolingCount.clamp(1, 6);
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

  // 厂商 SVG 图标路径（使用公共工具）
  String _vendorIconPath(String type) {
    return ModelIconUtils.getProviderIconPath(type);
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
                                          child: SvgPicture.asset(
                                            _vendorIconPath(p.type),
                                            width: 24,
                                            height: 24,
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

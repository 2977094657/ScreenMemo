part of 'provider_edit_page.dart';

extension _ProviderEditBatchPart on _ProviderEditPageState {
  Future<void> _refreshAllKeysAndProbeFailures() async {
    if (_batchRunning || _saving || _fetching) return;
    final AIProvider? provider = _currentProviderSnapshot();
    if (provider == null) {
      UINotifier.warning(
        context,
        AppLocalizations.of(context).providerSaveBeforeBatchTest,
      );
      return;
    }
    final enabledKeys = _keys
        .where((key) => key.enabled && key.apiKey.trim().isNotEmpty)
        .toList(growable: false);
    if (enabledKeys.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).providerKeepOneEnabledApiKey,
      );
      return;
    }
    final String base = _baseUrlCtrl.text.trim();
    if ((_type == AIProviderTypes.azureOpenAI ||
            _type == AIProviderTypes.claude ||
            _type == AIProviderTypes.gemini ||
            _type == AIProviderTypes.custom) &&
        base.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).baseUrlRequiredForAzureError,
      );
      return;
    }

    final bool confirm =
        await showUIDialog<bool>(
          context: context,
          title: '确认批量测试',
          message:
              '即将检查 ${enabledKeys.length} 个已启用 Key。系统会先刷新模型列表，再对失败的 Key 最多连续测试 3 次；若仍失败，将自动删除该 Key。',
          actions: [
            UIDialogAction<bool>(text: '取消', result: false),
            UIDialogAction<bool>(text: '开始测试', result: true),
          ],
        ) ??
        false;
    if (!confirm) return;

    _providerEditSetState(() {
      _batchRunning = true;
      _batchProgress = ProviderKeyBatchProgress(
        phaseLabel: '准备中',
        current: 0,
        total: enabledKeys.length,
        message: '正在准备批量测试任务...',
      );
    });
    try {
      final ProviderKeyBatchRefreshResult result = await _batchSvc
          .refreshModelsAndProbeFailures(
            provider: provider,
            keys: _keys,
            probeAttempts: 3,
            deleteAfterFailedProbe: true,
            onProgress: (progress) {
              if (!mounted) return;
              _providerEditSetState(() => _batchProgress = progress);
            },
          );
      await _reloadKeys();
      if (!mounted) return;
      UINotifier.success(
        context,
        '批量测试完成：刷新 ${result.refreshedCount} 个 Key，恢复 ${result.rescuedCount} 个，删除 ${result.deletedCount} 个。',
      );
      await _showBatchMaintenanceResult(result);
    } catch (e) {
      try {
        await FlutterLogger.nativeError(
          'AI',
          '批量测试失败 provider=${provider.id} type=${provider.type} error=$e',
        );
      } catch (_) {}
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).providerBatchTestFailed,
        );
      }
    } finally {
      if (mounted) {
        _providerEditSetState(() {
          _batchRunning = false;
          _batchProgress = null;
        });
      }
    }
  }

  Future<void> _showBatchMaintenanceResult(
    ProviderKeyBatchRefreshResult result,
  ) async {
    if (!mounted) return;
    final String summary = _buildBatchMaintenanceSummary(result);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).providerBatchTestResultTitle),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(child: SelectableText(summary)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context).actionClose),
          ),
        ],
      ),
    );
  }

  String _buildBatchMaintenanceSummary(ProviderKeyBatchRefreshResult result) {
    final lines = <String>[
      '已处理 Key：${result.processedKeyCount}',
      '刷新成功：${result.refreshedCount}',
      '模型刷新失败：${result.modelFailures.length}',
      '连续测试恢复：${result.rescuedCount}',
      '已删除：${result.deletedCount}',
      '跳过测试：${result.skippedProbeCount}',
    ];

    if (result.modelFailures.isNotEmpty) {
      lines.add('');
      lines.add('模型刷新失败明细：');
      for (final item in result.modelFailures) {
        lines.add('- ${item.key.name}: ${_clipDialogText(item.errorMessage)}');
      }
    }

    if (result.probeResults.isNotEmpty) {
      lines.add('');
      lines.add('失败 Key 连续测试结果：');
      for (final item in result.probeResults) {
        final String models = item.modelsTried.isEmpty
            ? '-'
            : item.modelsTried.join(', ');
        final String status = item.success
            ? '恢复成功'
            : (item.deleted ? '已删除' : (item.skipped ? '已跳过' : '仍然失败'));
        final String detail = item.success
            ? '成功模型：${item.successModel ?? '-'}；返回片段：${item.responsePreview ?? '-'}'
            : (item.failureMessages.isEmpty
                  ? '未记录失败原因'
                  : _clipDialogText(item.failureMessages.last));
        lines.add(
          '- ${item.key.name} [$status] 连续测试：${item.attemptsUsed} 次；模型：$models；$detail',
        );
      }
    }

    return lines.join('\n');
  }
}

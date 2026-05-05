part of 'provider_edit_page.dart';

extension _ProviderEditKeysPart on _ProviderEditPageState {
  String _keyNameForBatch({
    required String baseName,
    required int batchIndex,
    required int batchTotal,
    required int existingCount,
  }) {
    final trimmed = baseName.trim();
    if (batchTotal <= 1) {
      return trimmed.isEmpty ? 'Key ${existingCount + 1}' : trimmed;
    }
    final defaultPrefix = RegExp(r'^Key\s+\d+$').hasMatch(trimmed);
    if (trimmed.isEmpty || defaultPrefix) {
      return 'Key ${existingCount + batchIndex + 1}';
    }
    return '$trimmed ${batchIndex + 1}';
  }

  Future<void> _openKeyDialog({AIProviderKey? key}) async {
    final l10n = AppLocalizations.of(context);
    final providerId = _loaded?.id;
    if (providerId == null) {
      UINotifier.warning(context, l10n.providerSaveBeforeAddingKey);
      return;
    }
    final nameCtrl = TextEditingController(
      text: key?.name ?? l10n.providerDefaultKeyName(_keys.length + 1),
    );
    final apiCtrl = TextEditingController(text: key?.apiKey ?? '');
    final priorityCtrl = TextEditingController(
      text: (key?.priority ?? AIProviderKey.defaultPriority).toString(),
    );
    final modelsCtrl = TextEditingController(
      text: (key?.models ?? const <String>[]).join('\n'),
    );
    final enabled = key?.enabled ?? true;
    final fetchedBalancesByApiKey = <String, ProviderKeyBalance>{};
    bool dialogFetching = false;
    bool dialogSaving = false;
    ProviderKeyBatchProgress? dialogProgress;

    AIProvider buildDialogProviderSnapshot() {
      final base = _baseUrlCtrl.text.trim();
      return AIProvider(
        id: providerId,
        name: _nameCtrl.text.trim().isEmpty
            ? (_loaded?.name ?? 'Provider')
            : _nameCtrl.text.trim(),
        type: _type,
        baseUrl: base.isEmpty ? null : base,
        chatPath: _chatPathCtrl.text.trim().isEmpty
            ? null
            : _chatPathCtrl.text.trim(),
        modelsPath: _effectiveModelsPath(),
        useResponseApi: _useResponseApi,
        enabled: true,
        isDefault: false,
        models: const <String>[],
        extra: _buildExtra(),
        orderIndex: _loaded?.orderIndex ?? 0,
        balanceEndpointType: _balanceEndpointType,
        balanceAutoDeleteZeroKey: _balanceAutoDeleteZeroKey,
      );
    }

    List<String> parseDialogModels() {
      return modelsCtrl.text
          .split(RegExp(r'[\r\n,]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    String keyLabelForProgress({
      required int index,
      required int total,
      required String fallbackName,
    }) {
      if (total <= 1) {
        return fallbackName.trim().isEmpty
            ? l10n.providerKeyCurrent
            : fallbackName.trim();
      }
      return _keyNameForBatch(
        baseName: fallbackName,
        batchIndex: index,
        batchTotal: total,
        existingCount: _keys.length,
      );
    }

    bool validateBaseUrlForDialog() {
      final base = _baseUrlCtrl.text.trim();
      if ((_type == AIProviderTypes.azureOpenAI ||
              _type == AIProviderTypes.claude ||
              _type == AIProviderTypes.gemini ||
              _type == AIProviderTypes.custom) &&
          base.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).baseUrlRequiredForAzureError,
        );
        return false;
      }
      return true;
    }

    Future<void> fetchModelsInDialog(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (dialogFetching || dialogSaving) return;
      final apiKeys = _parseApiKeys(apiCtrl.text);
      if (apiKeys.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).apiKeyRequiredError,
        );
        return;
      }
      if (!validateBaseUrlForDialog()) return;

      final provider = buildDialogProviderSnapshot();
      final initialModels = parseDialogModels();
      final fetchedModelPool = <String>[];
      final failureHints = <String>[];
      int modelSuccessCount = 0;
      int balanceSuccessCount = 0;

      setDialogState(() {
        dialogFetching = true;
        dialogProgress = ProviderKeyBatchProgress(
          phaseLabel: l10n.providerKeyProgressFetchModels,
          current: 0,
          total: apiKeys.length,
          message: l10n.providerKeyProgressPreparingScan(apiKeys.length),
        );
      });

      try {
        for (var i = 0; i < apiKeys.length; i++) {
          final apiKey = apiKeys[i];
          final label = keyLabelForProgress(
            index: i,
            total: apiKeys.length,
            fallbackName: nameCtrl.text,
          );
          if (dialogContext.mounted) {
            setDialogState(() {
              dialogProgress = ProviderKeyBatchProgress(
                phaseLabel: l10n.providerKeyProgressFetchModels,
                current: i + 1,
                total: apiKeys.length,
                message: l10n.providerKeyProgressFetchingModels(label),
              );
            });
          }

          List<String> fetched = const <String>[];
          bool modelOk = false;
          try {
            fetched = await _svc.fetchModels(
              provider: provider,
              apiKey: apiKey,
            );
            fetchedModelPool.addAll(fetched);
            modelSuccessCount++;
            modelOk = true;
            final merged = _mergeModelNames(<Iterable<String>>[
              initialModels,
              fetchedModelPool,
            ]);
            if (dialogContext.mounted) {
              setDialogState(() => modelsCtrl.text = merged.join('\n'));
            }
          } catch (e) {
            final errorText = _clipDialogText(e.toString(), 120);
            failureHints.add(
              l10n.providerKeyProgressModelFetchFailed(label, errorText),
            );
            try {
              await FlutterLogger.nativeWarn(
                'AI',
                'add-key dialog model fetch failed provider=$providerId keyIndex=${i + 1}/${apiKeys.length} error=$errorText',
              );
            } catch (_) {}
          }

          String balanceMessage = '';
          if (provider.hasBalanceQuery) {
            if (dialogContext.mounted) {
              setDialogState(() {
                dialogProgress = ProviderKeyBatchProgress(
                  phaseLabel: l10n.providerKeyProgressFetchBalance,
                  current: i + 1,
                  total: apiKeys.length,
                  message: l10n.providerKeyProgressFetchingBalance(label),
                );
              });
            }
            try {
              final balance = await _svc.fetchBalance(
                provider: provider,
                apiKey: apiKey,
              );
              fetchedBalancesByApiKey[apiKey] = balance;
              balanceSuccessCount++;
              balanceMessage = l10n.providerKeyProgressBalanceDisplay(
                balance.display,
              );
            } catch (e) {
              final errorText = _clipDialogText(e.toString(), 120);
              balanceMessage = l10n.providerKeyProgressBalanceFailedShort;
              failureHints.add(
                l10n.providerKeyProgressBalanceFetchFailed(label, errorText),
              );
            }
          }

          if (dialogContext.mounted) {
            final modelMessage = modelOk
                ? l10n.providerKeyProgressModelsCount(fetched.length)
                : l10n.providerKeyProgressModelFailedSkipped;
            setDialogState(() {
              dialogProgress = ProviderKeyBatchProgress(
                phaseLabel: l10n.providerKeyProgressScanKeys,
                current: i + 1,
                total: apiKeys.length,
                message: '$label: $modelMessage$balanceMessage',
              );
            });
          }
        }

        if (!mounted || !dialogContext.mounted) return;
        if (modelSuccessCount > 0) {
          final fetchedCount = _mergeModelNames(<Iterable<String>>[
            fetchedModelPool,
          ]).length;
          UINotifier.success(
            context,
            provider.hasBalanceQuery
                ? l10n.providerKeyFetchCompleteToast(
                    modelSuccessCount,
                    apiKeys.length,
                    fetchedCount,
                    balanceSuccessCount,
                    apiKeys.length,
                    failureHints.length,
                  )
                : l10n.providerKeyFetchCompleteToastNoBalance(
                    modelSuccessCount,
                    apiKeys.length,
                    fetchedCount,
                    failureHints.length,
                  ),
          );
        } else {
          UINotifier.error(context, l10n.providerKeyNoModelsFetchedToast);
        }
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() {
            dialogFetching = false;
            dialogProgress = ProviderKeyBatchProgress(
              phaseLabel: l10n.providerKeyProgressFetchComplete,
              current: apiKeys.length,
              total: apiKeys.length,
              message: provider.hasBalanceQuery
                  ? l10n.providerKeyProgressFetchCompleteMessage(
                      modelSuccessCount,
                      apiKeys.length,
                      balanceSuccessCount,
                      apiKeys.length,
                    )
                  : l10n.providerKeyProgressFetchCompleteMessageNoBalance(
                      modelSuccessCount,
                      apiKeys.length,
                    ),
            );
          });
        }
      }
    }

    Future<void> saveKeyInDialog(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (dialogFetching || dialogSaving) return;
      final apiKeys = _parseApiKeys(apiCtrl.text);
      if (apiKeys.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).apiKeyRequiredError,
        );
        return;
      }
      if (key != null && apiKeys.length > 1) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).providerOnlyOneApiKeyCanEdit,
        );
        return;
      }
      final models = parseDialogModels();
      if (models.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).atLeastOneModelRequiredError,
        );
        return;
      }
      final providerSnapshot = _currentProviderSnapshot();
      if (providerSnapshot == null) {
        UINotifier.warning(context, l10n.providerSaveBeforeAddingKey);
        return;
      }
      final priority =
          int.tryParse(priorityCtrl.text.trim()) ??
          AIProviderKey.defaultPriority;

      final existingApiKeys = _keys.map((k) => k.apiKey.trim()).toSet();
      final keysToCreate = key == null
          ? apiKeys
                .where((item) => !existingApiKeys.contains(item.trim()))
                .toList(growable: false)
          : const <String>[];
      final skipped = key == null ? apiKeys.length - keysToCreate.length : 0;
      if (key == null && keysToCreate.isEmpty) {
        UINotifier.warning(context, l10n.providerNoNewApiKeyDuplicate);
        return;
      }

      final total = key == null ? keysToCreate.length : 1;
      int savedCount = 0;
      int balanceUpdatedCount = 0;
      bool shouldCloseDialog = false;

      setDialogState(() {
        dialogSaving = true;
        dialogProgress = ProviderKeyBatchProgress(
          phaseLabel: l10n.providerKeyProgressSaveKeys,
          current: 0,
          total: total,
          message: l10n.providerKeyProgressPreparingSave,
        );
      });

      try {
        if (key == null) {
          for (var i = 0; i < keysToCreate.length; i++) {
            final apiKey = keysToCreate[i];
            final keyName = _keyNameForBatch(
              baseName: nameCtrl.text,
              batchIndex: i,
              batchTotal: keysToCreate.length,
              existingCount: _keys.length,
            );
            if (dialogContext.mounted) {
              setDialogState(() {
                dialogProgress = ProviderKeyBatchProgress(
                  phaseLabel: l10n.providerKeyProgressSaveKeys,
                  current: i + 1,
                  total: total,
                  message: l10n.providerKeyProgressSaving(keyName),
                );
              });
            }
            final newId = await _svc.createProviderKey(
              providerId: providerId,
              name: keyName,
              apiKey: apiKey,
              models: models,
              enabled: enabled,
              priority: priority,
              orderIndex: _keys.length + i,
            );
            if (newId == null) continue;
            savedCount++;

            if (providerSnapshot.hasBalanceQuery) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  dialogProgress = ProviderKeyBatchProgress(
                    phaseLabel: l10n.providerKeyProgressSaveBalance,
                    current: i + 1,
                    total: total,
                    message: l10n.providerKeyProgressSavingBalance(keyName),
                  );
                });
              }
              final cachedBalance = fetchedBalancesByApiKey[apiKey];
              final balance = cachedBalance == null
                  ? await _svc.refreshBalanceForKey(
                      providerId: providerId,
                      keyId: newId,
                      providerOverride: providerSnapshot,
                    )
                  : await _svc.saveFetchedBalanceForKey(
                      providerId: providerId,
                      keyId: newId,
                      balance: cachedBalance,
                      providerOverride: providerSnapshot,
                    );
              if (balance != null) balanceUpdatedCount++;
            }
          }
        } else {
          if (dialogContext.mounted) {
            setDialogState(() {
              dialogProgress = ProviderKeyBatchProgress(
                phaseLabel: l10n.providerKeyProgressSaveKey,
                current: 1,
                total: 1,
                message: l10n.providerKeyProgressSaving(
                  nameCtrl.text.trim().isEmpty
                      ? key.name
                      : nameCtrl.text.trim(),
                ),
              );
            });
          }
          await _svc.updateProviderKey(
            id: key.id!,
            name: nameCtrl.text.trim(),
            apiKey: apiKeys.first,
            models: models,
            enabled: enabled,
            priority: priority,
          );
          savedCount = 1;
          if (providerSnapshot.hasBalanceQuery) {
            final cachedBalance = fetchedBalancesByApiKey[apiKeys.first];
            final balance = cachedBalance == null
                ? await _svc.refreshBalanceForKey(
                    providerId: providerId,
                    keyId: key.id!,
                    providerOverride: providerSnapshot,
                  )
                : await _svc.saveFetchedBalanceForKey(
                    providerId: providerId,
                    keyId: key.id!,
                    balance: cachedBalance,
                    providerOverride: providerSnapshot,
                  );
            if (balance != null) balanceUpdatedCount++;
          }
        }

        await _reloadKeys();
        if (!mounted || !dialogContext.mounted) return;
        UINotifier.success(
          context,
          key == null
              ? (providerSnapshot.hasBalanceQuery
                    ? l10n.providerKeySaveSuccessNew(
                        savedCount,
                        balanceUpdatedCount,
                        savedCount,
                        skipped,
                      )
                    : l10n.providerKeySaveSuccessNewNoBalance(
                        savedCount,
                        skipped,
                      ))
              : (providerSnapshot.hasBalanceQuery
                    ? l10n.providerKeySaveSuccessEdit(
                        balanceUpdatedCount,
                        savedCount,
                      )
                    : l10n.providerKeySaveSuccessEditNoBalance),
        );
        shouldCloseDialog = true;
        Navigator.of(dialogContext).pop(true);
      } catch (e) {
        try {
          await FlutterLogger.nativeError(
            'AI',
            'save API key failed provider=$providerId key=${key?.id ?? 'new'} error=$e',
          );
        } catch (_) {}
        if (mounted) {
          UINotifier.error(
            context,
            l10n.providerKeySaveFailedToast(_clipDialogText(e.toString())),
          );
        }
        if (dialogContext.mounted) {
          setDialogState(() {
            dialogProgress = ProviderKeyBatchProgress(
              phaseLabel: l10n.providerKeyProgressSaveFailed,
              current: savedCount,
              total: total,
              message: _clipDialogText(e.toString(), 160),
            );
          });
        }
      } finally {
        if (!shouldCloseDialog && dialogContext.mounted) {
          setDialogState(() => dialogSaving = false);
        }
      }
    }

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          final busy = dialogFetching || dialogSaving;
          return AlertDialog(
            title: Text(
              key == null ? l10n.providerAddApiKey : l10n.providerEditApiKey,
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildKeyDialogTextField(
                      controller: nameCtrl,
                      label: l10n.providerKeyNameLabel,
                    ),
                    _buildKeyDialogTextField(
                      controller: apiCtrl,
                      label: key == null
                          ? l10n.providerApiKeyMultiLineLabel
                          : l10n.providerApiKeySingleLineLabel,
                      hint: key == null
                          ? l10n.providerApiKeyMultiLineHint
                          : null,
                      obscure: key != null,
                      minLines: key == null ? 3 : 1,
                      maxLines: key == null ? 8 : 1,
                    ),
                    _buildKeyDialogTextField(
                      controller: priorityCtrl,
                      label: l10n.providerKeyPriorityLabel,
                      keyboardType: TextInputType.number,
                    ),
                    _buildKeyDialogTextField(
                      controller: modelsCtrl,
                      label: l10n.providerKeyModelsLabel,
                      minLines: 5,
                      maxLines: 10,
                    ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => fetchModelsInDialog(ctx, setDialogState),
                      icon: dialogFetching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined, size: 18),
                      label: Text(
                        AppLocalizations.of(
                          context,
                        ).providerFetchModelsAndBalance,
                      ),
                    ),
                    if (dialogProgress != null) ...[
                      const SizedBox(height: AppTheme.spacing3),
                      _buildProviderKeyDialogProgress(theme, dialogProgress!),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                child: Text(AppLocalizations.of(context).dialogCancel),
              ),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () => saveKeyInDialog(ctx, setDialogState),
                child: dialogSaving
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context).actionSaving),
                        ],
                      )
                    : Text(AppLocalizations.of(context).actionSave),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refreshProviderKey(AIProviderKey key) async {
    final providerId = _loaded?.id;
    if (providerId == null || key.id == null) return;
    final provider = _currentProviderSnapshot();
    if (provider == null) return;
    _providerEditSetState(() => _fetching = true);
    try {
      await _svc.refreshModelsForKey(
        providerId: providerId,
        keyId: key.id!,
        providerOverride: provider,
        awaitBalance: true,
      );
      await _reloadKeys();
      if (mounted) {
        UINotifier.success(
          context,
          provider.hasBalanceQuery ? '模型列表与余额已更新' : '模型列表已更新',
        );
      }
    } catch (_) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).providerFetchModelsFailedManual,
        );
      }
    } finally {
      if (mounted) _providerEditSetState(() => _fetching = false);
    }
  }

  Future<void> _deleteProviderKey(AIProviderKey key) async {
    if (key.id == null) return;
    await _svc.deleteProviderKey(key.id!);
    await _reloadKeys();
  }

  Future<void> _deleteAllProviderKeys() async {
    final providerId = _loaded?.id;
    if (providerId == null || _keys.isEmpty) return;
    final confirm =
        await showUIDialog<bool>(
          context: context,
          title: '删除全部 API Key',
          message: '确定删除当前提供商下的全部 ${_keys.length} 个 API Key 吗？此操作不可恢复。',
          actions: [
            UIDialogAction<bool>(text: '取消', result: false),
            UIDialogAction<bool>(
              text: '全部删除',
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
        ) ??
        false;
    if (!confirm) return;
    final deleted = await _svc.deleteAllProviderKeys(providerId);
    if (!mounted) return;
    await _reloadKeys();
    if (!mounted) return;
    UINotifier.success(
      context,
      AppLocalizations.of(context).providerDeletedApiKeys(deleted),
    );
  }

  String _formatKeyTime(int? millis) {
    if (millis == null || millis <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _normalizeOptionalLabel(String label) {
    return label
        .replaceAll(RegExp(r'（\s*可选\s*）'), '')
        .replaceAll(RegExp(r'\(\s*optional\s*\)', caseSensitive: false), '')
        .trim();
  }

  bool _labelLooksOptional(String label) {
    final lower = label.toLowerCase();
    return label.contains('可选') || lower.contains('optional');
  }

  String _priorityText(AIProviderKey key) {
    return key.usesDefaultPriority ? '动态分配' : '${key.priority}';
  }

  Widget _buildKeyStatCell({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinVerticalDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 32,
      color: theme.colorScheme.outline.withValues(alpha: 0.45),
    );
  }

  Widget _buildProviderKeyCard(AIProviderKey key, int displayIndex) {
    final theme = Theme.of(context);
    final cooling = key.isCoolingDown();
    final statusColor = key.enabled
        ? (cooling ? AppTheme.info : AppTheme.success)
        : theme.colorScheme.onSurfaceVariant;
    final lastError = (key.lastErrorType ?? '').trim();
    final errorMessage = (key.lastErrorMessage ?? '').trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.22),
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      key.enabled
                          ? Icons.vpn_key_rounded
                          : Icons.key_off_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          key.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '优先级 · ${_priorityText(key)} · ${key.models.length} 个模型',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor.withValues(
                        alpha: 0.8,
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.45,
                        ),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      '#${displayIndex + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.86,
                    child: Switch.adaptive(
                      value: key.enabled,
                      onChanged: (_fetching || _batchRunning)
                          ? null
                          : (v) => _toggleProviderKey(key, v),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing2,
              ),
              child: Row(
                children: [
                  _buildKeyStatCell(
                    icon: Icons.check_rounded,
                    value: '${key.successCount}',
                    label: '成功',
                    color: AppTheme.success,
                  ),
                  _buildThinVerticalDivider(theme),
                  _buildKeyStatCell(
                    icon: Icons.error_outline_rounded,
                    value: '${key.failureTotalCount}',
                    label: '失败',
                    color: theme.colorScheme.error,
                  ),
                  _buildThinVerticalDivider(theme),
                  _buildKeyStatCell(
                    icon: Icons.sync_alt_rounded,
                    value: '${key.failureCount}',
                    label: '连续失败',
                    color: key.failureCount > 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  if (AIBalanceEndpointTypes.isQueryable(
                    _balanceEndpointType,
                  )) ...[
                    _buildThinVerticalDivider(theme),
                    _buildKeyStatCell(
                      icon: Icons.account_balance_wallet_outlined,
                      value: key.balanceDisplay ?? '—',
                      label: '余额',
                      color: key.hasBalance
                          ? (key.isBalanceZero
                                ? theme.colorScheme.error
                                : AppTheme.info)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '上次成功',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatKeyTime(key.lastSuccessAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '上次失败',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatKeyTime(key.lastFailedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新模型',
                    icon: const Icon(Icons.refresh, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: (_fetching || _batchRunning)
                        ? null
                        : () => _refreshProviderKey(key),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: (_fetching || _batchRunning)
                        ? null
                        : () => _openKeyDialog(key: key),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    onPressed: (_fetching || _batchRunning)
                        ? null
                        : () => _deleteProviderKey(key),
                  ),
                ],
              ),
            ),
            if (cooling || !key.enabled || lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  lastError.isEmpty
                      ? (cooling ? '当前状态：冷却中' : '当前状态：已停用')
                      : (errorMessage.isEmpty
                            ? '最近错误：$lastError'
                            : '最近错误：$lastError  $errorMessage'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: lastError.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleProviderKey(AIProviderKey key, bool enabled) async {
    if (key.id == null) return;
    final ok = await _svc.updateProviderKey(id: key.id!, enabled: enabled);
    if (!mounted) return;
    if (!ok) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    await _reloadKeys();
  }
}

part of 'settings_page.dart';

extension _SettingsMcpPart on _SettingsPageState {
  Future<void> _loadMcpStatus() async {
    final l10n = AppLocalizations.of(context);
    if (_mcpLoading) return;
    _settingsSetState(() => _mcpLoading = true);
    try {
      final status = await McpService.getStatus();
      if (!mounted) return;
      _settingsSetState(() => _mcpStatus = status);
    } catch (e) {
      if (!mounted) return;
      _showMcpSnack(l10n.mcpLoadStatusFailed('$e'));
    } finally {
      if (mounted) _settingsSetState(() => _mcpLoading = false);
    }
  }

  Future<void> _toggleMcpServer(bool enabled) async {
    final l10n = AppLocalizations.of(context);
    if (_mcpLoading) return;
    _settingsSetState(() => _mcpLoading = true);
    try {
      var status = enabled ? await McpService.start() : await McpService.stop();
      if (enabled) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        status = await McpService.getStatus();
      }
      if (!mounted) return;
      _settingsSetState(() => _mcpStatus = status);
      if (enabled && status.lastError != null) {
        _showMcpSnack(status.lastError!);
      }
    } catch (e) {
      if (!mounted) return;
      _showMcpSnack(
        enabled ? l10n.mcpStartFailed('$e') : l10n.mcpStopFailed('$e'),
      );
    } finally {
      if (mounted) _settingsSetState(() => _mcpLoading = false);
    }
  }

  Future<void> _resetMcpToken() async {
    final l10n = AppLocalizations.of(context);
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: l10n.mcpResetTokenDialogTitle,
      message: l10n.mcpResetTokenDialogMessage,
      confirmText: l10n.mcpResetTokenConfirm,
      cancelText: l10n.dialogCancel,
      destructive: true,
    );
    if (!ok || _mcpLoading) return;
    _settingsSetState(() => _mcpLoading = true);
    try {
      final status = await McpService.resetToken();
      if (!mounted) return;
      _settingsSetState(() => _mcpStatus = status);
      _showMcpSnack(l10n.mcpTokenResetToast);
    } catch (e) {
      if (!mounted) return;
      _showMcpSnack(l10n.mcpResetTokenFailed('$e'));
    } finally {
      if (mounted) _settingsSetState(() => _mcpLoading = false);
    }
  }

  Future<void> _copyMcpText(String text, String label) async {
    final l10n = AppLocalizations.of(context);
    if (text.trim().isEmpty) {
      _showMcpSnack(l10n.mcpCopyValueEmpty(label));
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      _showMcpSnack(l10n.mcpCopiedToast(label));
    } catch (e) {
      if (!mounted) return;
      _showMcpSnack(l10n.mcpCopyFailed(label, '$e'));
    }
  }

  Widget _buildMcpServicePage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = _mcpStatus;
    final running = status?.running == true;
    final endpoint = status?.endpoint ?? '';
    final token = status?.token ?? '';
    final lastError = status?.lastError;
    final aiInstallText = _buildMcpAiInstallText(
      context,
      endpoint: endpoint,
      token: token,
    );
    final bool canCopyConnection = endpoint.isNotEmpty && token.isNotEmpty;

    return ListView(
      padding: _settingsListPadding(),
      children: [
        _buildCard(
          context: context,
          children: [
            SwitchListTile.adaptive(
              value: running,
              onChanged: _mcpLoading ? null : _toggleMcpServer,
              secondary: _buildMcpLeadingIcon(
                context,
                color: running ? theme.colorScheme.primary : null,
              ),
              title: Text(l10n.mcpLanServerTitle),
              subtitle: Text(
                running ? l10n.mcpRunningOnPort(37621) : l10n.mcpStopped,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_mcpLoading)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.spacing4,
                  0,
                  AppTheme.spacing4,
                  AppTheme.spacing3,
                ),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
        if (lastError != null) ...[
          const SizedBox(height: AppTheme.spacing3),
          _buildMcpInfoBlock(
            context: context,
            icon: Icons.error_outline,
            title: l10n.mcpLastErrorTitle,
            body: lastError,
            color: theme.colorScheme.error,
          ),
        ],
        const SizedBox(height: AppTheme.spacing3),
        _buildCard(
          context: context,
          children: [
            _buildMcpValueRow(
              context: context,
              icon: Icons.link_outlined,
              label: l10n.mcpEndpointLabel,
              value: endpoint.isEmpty ? l10n.mcpNoLanIpDetected : endpoint,
              showBottomBorder: true,
              onCopy: endpoint.isEmpty
                  ? null
                  : () => _copyMcpText(endpoint, l10n.mcpEndpointLabel),
            ),
            _buildMcpValueRow(
              context: context,
              icon: Icons.vpn_key_outlined,
              label: l10n.mcpBearerTokenLabel,
              value: token.isEmpty ? l10n.mcpUnavailable : token,
              showBottomBorder: true,
              onCopy: token.isEmpty
                  ? null
                  : () => _copyMcpText(token, l10n.mcpTokenCopyLabel),
            ),
            _buildMcpActionRow(
              context: context,
              icon: Icons.refresh_outlined,
              title: l10n.mcpResetTokenTitle,
              subtitle: l10n.mcpResetTokenSubtitle,
              showBottomBorder: false,
              onTap: _mcpLoading ? null : _resetMcpToken,
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing3),
        _buildMcpInfoBlock(
          context: context,
          icon: Icons.auto_fix_high_outlined,
          title: l10n.mcpAiInstallTitle,
          body: aiInstallText,
          copyLabel: l10n.mcpAiInstallCopyLabel,
          onCopy: canCopyConnection
              ? () => _copyMcpText(aiInstallText, l10n.mcpAiInstallCopyLabel)
              : null,
        ),
      ],
    );
  }

  Widget _buildMcpValueRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required bool showBottomBorder,
    VoidCallback? onCopy,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBottomBorder
              ? _settingsDividerSide(context)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, icon),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: AppLocalizations.of(context).actionCopy,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }

  Widget _buildMcpActionRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool showBottomBorder,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing3,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: showBottomBorder
                ? _settingsDividerSide(context)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            _buildSettingsLeadingIcon(context, icon),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMcpInfoBlock({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String body,
    Color? color,
    String? copyLabel,
    VoidCallback? onCopy,
  }) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurfaceVariant;
    return _buildCard(
      context: context,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsLeadingIcon(context, icon, color: fg),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    SelectableText(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color ?? theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (copyLabel != null) ...[
                      const SizedBox(height: AppTheme.spacing3),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onCopy,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: Text(copyLabel),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _buildMcpAiInstallText(
    BuildContext context, {
    required String endpoint,
    required String token,
  }) {
    final l10n = AppLocalizations.of(context);
    if (endpoint.isEmpty || token.isEmpty) {
      return l10n.mcpConnectionUnavailableHint;
    }
    return l10n.mcpAiInstallPrompt(endpoint, token);
  }

  void _showMcpSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

part of 'settings_page.dart';

// ========== 赞赏页面 ==========
extension _SettingsSupportPart on _SettingsPageState {
  static const String _supportWechatQrAsset = 'assets/donate/wechat_qr.png';
  static const String _supportAlipayQrAsset = 'assets/donate/alipay_qr.jpg';

  Widget _buildSupportPage(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: _settingsListPadding(),
      children: [
        _buildSupportIntroCard(context),
        const SizedBox(height: AppTheme.spacing3),
        _buildAboutSectionTitle(context, l10n.supportWishListTitle),
        _buildCard(
          context: context,
          children: [
            _buildSupportWishItem(
              context: context,
              icon: Icons.devices_other_outlined,
              text: l10n.supportWishMorePlatforms,
              showBottomBorder: true,
            ),
            _buildSupportWishItem(
              context: context,
              icon: Icons.auto_stories_outlined,
              text: l10n.supportWishReviewViews,
              showBottomBorder: true,
            ),
            _buildSupportWishItem(
              context: context,
              icon: Icons.phonelink_setup_outlined,
              text: l10n.supportWishCompatibility,
              showBottomBorder: false,
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing3),
        _buildAboutSectionTitle(context, l10n.supportDonationMethodsTitle),
        _buildCard(
          context: context,
          children: [_buildQrDonationMethods(context)],
        ),
        const SizedBox(height: AppTheme.spacing3),
        _buildSupportNoteCard(context),
      ],
    );
  }

  Widget _buildSupportIntroCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _buildCard(
      context: context,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacing5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                child: Icon(
                  Icons.volunteer_activism_outlined,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                l10n.supportIntroTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                l10n.supportIntroBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSupportWishItem({
    required BuildContext context,
    required IconData icon,
    required String text,
    required bool showBottomBorder,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingsLeadingIcon(context, icon),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrDonationMethods(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool stackVertically = constraints.maxWidth < 360;
        final wechat = _buildQrDonationMethod(
          context: context,
          assetPath: _supportWechatQrAsset,
        );
        final alipay = _buildQrDonationMethod(
          context: context,
          assetPath: _supportAlipayQrAsset,
        );

        return Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: stackVertically
              ? Column(
                  children: [
                    wechat,
                    const SizedBox(height: AppTheme.spacing3),
                    alipay,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: wechat),
                    const SizedBox(width: AppTheme.spacing3),
                    Expanded(child: alipay),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildQrDonationMethod({
    required BuildContext context,
    required String assetPath,
  }) {
    return GestureDetector(
      onTap: () => _showQrPreview(context, assetPath),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return AspectRatio(
                aspectRatio: 1,
                child: _buildQrMissingPlaceholder(context),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildQrMissingPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Text(
        AppLocalizations.of(context).supportQrMissing,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildSupportNoteCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _buildCard(
      context: context,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsLeadingIcon(context, Icons.info_outline),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Text(
                  l10n.supportVoluntaryNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showQrPreview(BuildContext context, String assetPath) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(AppTheme.spacing4),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildQrMissingPlaceholder(context);
                    },
                  ),
                ),
              ),
              Positioned(
                top: AppTheme.spacing2,
                right: AppTheme.spacing2,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

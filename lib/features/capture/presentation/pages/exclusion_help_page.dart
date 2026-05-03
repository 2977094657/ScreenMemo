import 'package:flutter/material.dart';
import 'package:screen_memo/features/capture/application/ime_exclusion_service.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

class ExclusionHelpPage extends StatefulWidget {
  const ExclusionHelpPage({super.key});

  @override
  State<ExclusionHelpPage> createState() => _ExclusionHelpPageState();
}

class _ExclusionHelpPageState extends State<ExclusionHelpPage> {
  List<Map<String, String>> _imeList = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ImeExclusionService.getEnabledImeList();
      if (!mounted) return;
      setState(() {
        _imeList = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.exclusionExcludedAppsTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              children: [
                Text(
                  l10n.excludedAppsIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppTheme.spacing3),
                Text(l10n.exclusionSelfAppBullet),
                const SizedBox(height: AppTheme.spacing3),
                Text(l10n.exclusionImeAppsBullet),
                const SizedBox(height: AppTheme.spacing2),
                if (_imeList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: AppTheme.spacing2),
                    child: Text(l10n.exclusionAutoFilteredBullet),
                  )
                else ...[
                  for (final m in _imeList)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppTheme.spacing2,
                        bottom: 6,
                      ),
                      child: Text(
                        l10n.exclusionImeAppBullet(
                          ((m['appName'] ?? '').trim().isNotEmpty)
                              ? (m['appName'] ?? '')
                              : l10n.exclusionUnknownIme,
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

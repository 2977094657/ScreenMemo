import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_components.dart';

class AIRequestLogsSheet extends StatelessWidget {
  const AIRequestLogsSheet({
    super.key,
    required this.title,
    required this.body,
    this.metaText,
    this.hintText,
  });

  final String title;
  final Widget body;
  final String? metaText;
  final String? hintText;

  static Future<void> show({
    required BuildContext context,
    required String title,
    required Widget body,
    String? metaText,
    String? hintText,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return AIRequestLogsSheet(
          title: title,
          body: body,
          metaText: metaText,
          hintText: hintText,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String meta = (metaText ?? '').trimRight();
    final String hint = (hintText ?? '').trim();
    final bool hasMeta = meta.isNotEmpty;
    final bool hasHint = hint.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext sheetCtx, ScrollController ctrl) {
        return UISheetSurface(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.spacing3),
              const UISheetHandle(),
              const SizedBox(height: AppTheme.spacing2),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacing4,
                    0,
                    AppTheme.spacing4,
                    AppTheme.spacing6,
                  ),
                  children: [
                    if (hasMeta) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppTheme.spacing3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.25),
                          ),
                        ),
                        child: SelectableText(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                    ],
                    if (hasHint) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppTheme.spacing3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                    ],
                    body,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

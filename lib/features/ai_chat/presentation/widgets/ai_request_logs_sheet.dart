import 'package:flutter/material.dart';

import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';

class AIRequestLogsSheet extends StatelessWidget {
  const AIRequestLogsSheet({
    super.key,
    required this.title,
    required this.body,
    this.metaText,
    this.hintText,
    this.expandBody = false,
  });

  final String title;
  final Widget body;
  final String? metaText;
  final String? hintText;
  final bool expandBody;

  static Future<void> show({
    required BuildContext context,
    required String title,
    required Widget body,
    String? metaText,
    String? hintText,
    bool expandBody = false,
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
          expandBody: expandBody,
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
    final EdgeInsets contentPadding = const EdgeInsets.fromLTRB(
      AppTheme.spacing4,
      0,
      AppTheme.spacing4,
      AppTheme.spacing6,
    );

    Widget buildMetaCard() {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacing3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
        ),
        child: SelectableText(
          meta,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      );
    }

    Widget buildHintCard() {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacing3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext sheetCtx, ScrollController ctrl) {
        if (expandBody) {
          final List<Widget> headerChildren = <Widget>[
            if (hasMeta) buildMetaCard(),
            if (hasMeta && hasHint) const SizedBox(height: AppTheme.spacing2),
            if (hasHint) buildHintCard(),
          ];

          return UISheetSurface(
            child: Column(
              children: [
                const SizedBox(height: AppTheme.spacing3),
                const UISheetHandle(),
                const SizedBox(height: AppTheme.spacing2),
                Expanded(
                  child: CustomScrollView(
                    controller: ctrl,
                    slivers: [
                      if (headerChildren.isNotEmpty)
                        SliverPadding(
                          padding: contentPadding.copyWith(
                            bottom: AppTheme.spacing2,
                          ),
                          sliver: SliverList.list(children: headerChildren),
                        ),
                      SliverPadding(
                        padding: contentPadding,
                        sliver: SliverFillRemaining(
                          hasScrollBody: false,
                          child: body,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return UISheetSurface(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.spacing3),
              const UISheetHandle(),
              const SizedBox(height: AppTheme.spacing2),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: contentPadding,
                  children: [
                    if (hasMeta) ...[
                      buildMetaCard(),
                      const SizedBox(height: AppTheme.spacing2),
                    ],
                    if (hasHint) ...[
                      buildHintCard(),
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

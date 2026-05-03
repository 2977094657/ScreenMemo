import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';

class AiMetaSheet {
  static Future<_AiMetaPayload?> _loadMeta(
    String filePath, {
    required bool includeOcr,
  }) async {
    final String p = filePath.trim();
    if (p.isEmpty) return null;

    try {
      final rowFut = ScreenshotDatabase.instance.getAiImageMetaByFilePath(p);
      final ocrFut = includeOcr
          ? ScreenshotDatabase.instance.getScreenshotByPath(p)
          : null;
      final row = await rowFut.catchError((_) => null);
      final rec = await ocrFut?.catchError((_) => null);
      final String ocrText =
          ((rec as dynamic)?.ocrText as String?)?.trim() ?? '';
      return _AiMetaPayload(row: row, ocrText: ocrText);
    } catch (_) {
      return null;
    }
  }

  static String _buildCopyText({
    required AppLocalizations l10n,
    required String range,
    required List<String> tags,
    required String description,
  }) {
    final List<String> parts = <String>[];

    final String r = range.trim();
    if (r.isNotEmpty) {
      parts.add(r);
    }

    if (tags.isNotEmpty) {
      parts.add('${l10n.aiImageTagsTitle}：\n${tags.join(' · ')}');
    }

    final String desc = description.trim();
    if (desc.isNotEmpty) {
      parts.add('${l10n.aiImageDescriptionsTitle}：\n$desc');
    }

    return parts.join('\n\n');
  }

  static Future<void> show(
    BuildContext context, {
    required String filePath,
    List<String>? fallbackTags,
    String? fallbackDescription,
    String? fallbackRange,
    String? fallbackOcrText,
  }) async {
    final String p = filePath.trim();
    if (p.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final String fallbackDesc = (fallbackDescription ?? '').trim();
        final String fallbackRangeText = (fallbackRange ?? '').trim();
        final List<String> fallbackTagsValue =
            fallbackTags
                ?.map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const <String>[];
        final bool hasFallback =
            fallbackDesc.isNotEmpty || fallbackTagsValue.isNotEmpty;
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (sheetCtx, ctrl) {
            return UISheetSurface(
              child: Column(
                children: [
                  const SizedBox(height: AppTheme.spacing3),
                  const UISheetHandle(),
                  const SizedBox(height: AppTheme.spacing3),
                  Expanded(
                    child: FutureBuilder<_AiMetaPayload?>(
                      future: _loadMeta(p, includeOcr: false),
                      builder: (c, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !hasFallback) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final row = snap.data?.row;
                        final String rawTagsJson =
                            (row?['tags_json'] as String?)?.trim() ?? '';
                        final List<String> tags = <String>[];
                        if (rawTagsJson.isNotEmpty) {
                          try {
                            final dynamic v = jsonDecode(rawTagsJson);
                            if (v is List) {
                              for (final t in v) {
                                final String s = t.toString().trim();
                                if (s.isNotEmpty) tags.add(s);
                              }
                            } else if (v is String) {
                              tags.addAll(
                                v
                                    .split(RegExp(r'[，,;；\s]+'))
                                    .map((e) => e.trim())
                                    .where((e) => e.isNotEmpty),
                              );
                            }
                          } catch (_) {
                            tags.addAll(
                              rawTagsJson
                                  .split(RegExp(r'[，,;；\s]+'))
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty),
                            );
                          }
                        }
                        if (tags.isEmpty && fallbackTagsValue.isNotEmpty) {
                          tags.addAll(fallbackTagsValue);
                        }

                        final String dbDesc =
                            (row?['description'] as String?)?.trim() ?? '';
                        final String dbRange =
                            (row?['description_range'] as String?)?.trim() ??
                            '';
                        final String desc = dbDesc.isNotEmpty
                            ? dbDesc
                            : fallbackDesc;
                        final String range = dbRange.isNotEmpty
                            ? dbRange
                            : (fallbackRangeText.isNotEmpty
                                  ? fallbackRangeText
                                  : p);

                        final bool hasAny = tags.isNotEmpty || desc.isNotEmpty;
                        if (!hasAny) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppTheme.spacing4),
                              child: Text(
                                l10n.noResultsForFilters,
                                style: Theme.of(c).textTheme.bodyMedium
                                    ?.copyWith(color: AppTheme.mutedForeground),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        return ListView(
                          controller: ctrl,
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacing4,
                            0,
                            AppTheme.spacing4,
                            AppTheme.spacing6,
                          ),
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'AI',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    range,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(c).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppTheme.mutedForeground,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: l10n.copyResultsTooltip,
                                  icon: const Icon(
                                    Icons.copy_all_outlined,
                                    size: 18,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: !hasAny
                                      ? null
                                      : () async {
                                          final String text = _buildCopyText(
                                            l10n: l10n,
                                            range: range,
                                            tags: tags,
                                            description: desc,
                                          );
                                          if (text.trim().isEmpty) return;
                                          try {
                                            await Clipboard.setData(
                                              ClipboardData(text: text),
                                            );
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(l10n.copySuccess),
                                              ),
                                            );
                                          } catch (_) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(l10n.copyFailed),
                                              ),
                                            );
                                          }
                                        },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (tags.isNotEmpty) ...[
                              Text(
                                l10n.aiImageTagsTitle,
                                style: Theme.of(c).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                tags.join(' · '),
                                style: Theme.of(c).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 14),
                            ],
                            Text(
                              l10n.aiImageDescriptionsTitle,
                              style: Theme.of(c).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              desc,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AiMetaPayload {
  const _AiMetaPayload({required this.row, required this.ocrText});

  final Map<String, dynamic>? row;
  final String ocrText;
}

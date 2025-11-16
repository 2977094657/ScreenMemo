import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/memory_models.dart';
import '../theme/app_theme.dart';

/// 显示标签层级结构，可折叠展开，多标签合并同一路径。
class TagHierarchyTree extends StatelessWidget {
  const TagHierarchyTree({
    super.key,
    required this.tags,
    required this.showConfirmAction,
    required this.onTapTag,
    required this.onConfirmTag,
    required this.onDeleteTag,
    required this.deletingTagIds,
    required this.confirmingTagIds,
    this.storagePrefix = 'tag_tree',
  });

  final List<MemoryTag> tags;
  final bool showConfirmAction;
  final ValueChanged<MemoryTag> onTapTag;
  final Future<void> Function(MemoryTag) onConfirmTag;
  final Future<void> Function(MemoryTag) onDeleteTag;
  final Set<int> deletingTagIds;
  final Set<int> confirmingTagIds;
  final String storagePrefix;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations t = AppLocalizations.of(context);
    final Map<String, Map<String, Map<String, List<MemoryTag>>>> hierarchy =
        _buildHierarchy(tags, t);

    if (hierarchy.isEmpty) {
      return const SizedBox.shrink();
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: hierarchy.entries
            .map((entry) => _buildLevel1(context, entry.key, entry.value))
            .toList(),
      ),
    );
  }

  Map<String, Map<String, Map<String, List<MemoryTag>>>> _buildHierarchy(
      List<MemoryTag> tags, AppLocalizations t) {
    final Map<String, Map<String, Map<String, List<MemoryTag>>>> result = {};
    for (final MemoryTag tag in tags) {
      final String level1 = _normalize(tag.level1, t.memoryCategoryOther);
      final String level2 = _normalize(tag.level2, t.memoryCategoryOther);
      final String level3 = _normalize(tag.level3, t.memoryCategoryOther);
      result
          .putIfAbsent(level1, () => <String, Map<String, List<MemoryTag>>>{})
          .putIfAbsent(level2, () => <String, List<MemoryTag>>{})
          .putIfAbsent(level3, () => <MemoryTag>[])
          .add(tag);
    }
    return result;
  }

  Widget _buildLevel1(BuildContext context, String level1,
      Map<String, Map<String, List<MemoryTag>>> level2Map) {
    final ThemeData theme = Theme.of(context);
    return ExpansionTile(
      key: PageStorageKey<String>('${storagePrefix}_level1_$level1'),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: false,
      title: Text(
        level1,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      children: level2Map.entries
          .map((entry) => _buildLevel2(context, level1, entry.key, entry.value))
          .toList(),
    );
  }

  Widget _buildLevel2(BuildContext context, String level1, String level2,
      Map<String, List<MemoryTag>> level3Map) {
    final ThemeData theme = Theme.of(context);
    return ExpansionTile(
      key: PageStorageKey<String>('${storagePrefix}_level2_${level1}_$level2'),
      tilePadding: const EdgeInsets.only(left: 16.0),
      initiallyExpanded: false,
      title: Text(
        level2,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      children: level3Map.entries
          .map((entry) => _buildLevel3(context, level1, level2, entry.key, entry.value))
          .toList(),
    );
  }

  Widget _buildLevel3(BuildContext context, String level1, String level2,
      String level3, List<MemoryTag> level4Tags) {
    final ThemeData theme = Theme.of(context);
    return ExpansionTile(
      key: PageStorageKey<String>(
          '${storagePrefix}_level3_${level1}_${level2}_$level3'),
      tilePadding: const EdgeInsets.only(left: 32.0),
      initiallyExpanded: false,
      title: Text(
        level3,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      children: level4Tags
          .map((tag) => _buildLeaf(context, tag))
          .toList(),
    );
  }

  Widget _buildLeaf(BuildContext context, MemoryTag tag) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations t = AppLocalizations.of(context);
    final bool confirming = confirmingTagIds.contains(tag.id);
    final bool deleting = deletingTagIds.contains(tag.id);
    final String label = _resolveLeafLabel(tag, t);
    final String detail = _buildTagDescription(tag, t);
    final ButtonStyle confirmButtonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      backgroundColor: theme.colorScheme.primaryContainer,
    );
    final ButtonStyle deleteButtonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      foregroundColor: theme.colorScheme.onErrorContainer,
      backgroundColor: theme.colorScheme.errorContainer,
    );

    return Padding(
      padding: const EdgeInsets.only(left: 48.0, top: 4.0, bottom: 4.0, right: 8.0),
      child: InkWell(
        onTap: () => onTapTag(tag),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                  children: [
                    TextSpan(
                      text: '$label：',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: detail),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacing2),
              Wrap(
                spacing: AppTheme.spacing2,
                runSpacing: AppTheme.spacing2,
                children: [
                  if (showConfirmAction)
                    FilledButton(
                      style: confirmButtonStyle,
                      onPressed: (confirming || deleting)
                          ? null
                          : () async {
                              await onConfirmTag(tag);
                            },
                      child: confirming
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  t.memoryConfirmAction,
                                  style: theme.textTheme.labelMedium,
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_outlined, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  t.memoryConfirmAction,
                                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                    ),
                  FilledButton(
                    style: deleteButtonStyle,
                    onPressed: deleting
                        ? null
                        : () async {
                            await onDeleteTag(tag);
                          },
                    child: deleting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.memoryDeleteTagAction,
                                style: theme.textTheme.labelMedium,
                              ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.delete_outline, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                t.memoryDeleteTagAction,
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildTagDescription(MemoryTag tag, AppLocalizations t) {
    final TagEvidence? evidence = tag.evidences.isNotEmpty ? tag.evidences.first : null;
    final String? notes = evidence?.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      return _ensureSentence(notes);
    }
    final String excerpt = evidence?.excerpt.trim() ?? '';
    if (excerpt.isNotEmpty) {
      return _ensureSentence(excerpt);
    }
    return _ensureSentence(t.memoryEvidenceNoNotes);
  }

  String _ensureSentence(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return '暂无更多说明。';
    final bool endsWithPunctuation = trimmed.endsWith('。') ||
        trimmed.endsWith('.') ||
        trimmed.endsWith('!') ||
        trimmed.endsWith('！') ||
        trimmed.endsWith('?') ||
        trimmed.endsWith('？');
    return endsWithPunctuation ? trimmed : '$trimmed。';
  }

  String _normalize(String value, String fallback) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _resolveLeafLabel(MemoryTag tag, AppLocalizations t) {
    final String explicit = tag.level4.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final String path = tag.fullPath.trim();
    if (path.isEmpty) {
      return t.memoryCategoryOther;
    }
    final List<String> segments = path
        .split(RegExp(r'[\/／\|｜]'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return t.memoryCategoryOther;
    }
    return segments.last;
  }
}


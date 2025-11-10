import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/memory_models.dart';
import '../services/memory_bridge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';

class TagDetailPage extends StatefulWidget {
  const TagDetailPage({
    super.key,
    required this.tagId,
    this.initialTag,
  });

  final int tagId;
  final MemoryTag? initialTag;

  @override
  State<TagDetailPage> createState() => _TagDetailPageState();
}

class _TagDetailPageState extends State<TagDetailPage> {
  final MemoryBridgeService _service = MemoryBridgeService.instance;
  MemoryTag? _tag;
  bool _loading = true;
  final Map<int, MemoryEventSummary> _eventCache = <int, MemoryEventSummary>{};

  @override
  void initState() {
    super.initState();
    _tag = widget.initialTag;
    _loading = widget.initialTag == null;
    scheduleMicrotask(_loadTag);
  }

  Future<void> _loadTag() async {
    setState(() => _loading = true);
    try {
      final MemoryTag? tag = await _service.fetchTagById(widget.tagId);
      if (!mounted) return;
      if (tag == null) {
        UINotifier.error(context, AppLocalizations.of(context).memoryTagDetailLoadFailed);
      }
      setState(() {
        _tag = tag ?? _tag;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      UINotifier.error(context, error.toString());
      setState(() => _loading = false);
    }
  }

  Future<MemoryEventSummary?> _getEvent(int eventId) async {
    if (_eventCache.containsKey(eventId)) {
      return _eventCache[eventId];
    }
    final MemoryEventSummary? summary = await _service.fetchEventById(eventId);
    if (summary != null) {
      _eventCache[eventId] = summary;
    }
    return summary;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final MemoryTag? tag = _tag;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.memoryTagDetailTitle),
        actions: [
          IconButton(
            tooltip: t.memoryTagDetailRefresh,
            onPressed: _loading ? null : _loadTag,
            icon: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: tag == null && _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTag,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing4,
                  vertical: AppTheme.spacing4,
                ),
                children: [
                  if (tag != null) ...[
                    _buildHeader(context, tag),
                    const SizedBox(height: AppTheme.spacing4),
                    _buildStatistics(context, tag),
                    const SizedBox(height: AppTheme.spacing4),
                    _buildEvidenceSection(context, tag),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing6),
                      child: Center(
                        child: Text(
                          t.memoryTagDetailLoadFailed,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context, MemoryTag tag) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations t = AppLocalizations.of(context);
    final Color accent = _accentForCategory(theme, tag.category, tag.isConfirmed);
    final IconData icon = _iconForCategory(tag.category);
    final String categoryLabel = _categoryLabel(context, tag.category);
    final String statusLabel = tag.isConfirmed ? t.memoryStatusConfirmed : t.memoryStatusPending;
    final double rawConfidence = tag.confidence > 1 ? tag.confidence : tag.confidence * 100;
    final double clampedConfidence = rawConfidence.clamp(0, 100);
    final String confidenceValue = clampedConfidence >= 10
        ? '${clampedConfidence.toStringAsFixed(0)}%'
        : '${clampedConfidence.toStringAsFixed(1)}%';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.18),
            theme.colorScheme.surfaceVariant.withOpacity(0.32),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: accent.withOpacity(0.28)),
      ),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.memoryTagDetailInfoTitle,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: accent.withOpacity(0.16),
                child: Icon(icon, color: accent, size: 32),
              ),
              const SizedBox(width: AppTheme.spacing4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.label,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    Wrap(
                      spacing: AppTheme.spacing3,
                      runSpacing: AppTheme.spacing2,
                      children: [
                        _buildBadge(
                          theme: theme,
                          label: statusLabel,
                          foreground: accent,
                          background: accent.withOpacity(0.12),
                          icon: tag.isConfirmed ? Icons.verified_outlined : Icons.hourglass_bottom_outlined,
                        ),
                        _buildBadge(
                          theme: theme,
                          label: categoryLabel,
                          foreground: theme.colorScheme.onSurface,
                          background: theme.colorScheme.surface.withOpacity(0.6),
                          icon: Icons.category_outlined,
                        ),
                        _buildBadge(
                          theme: theme,
                          label: t.memoryOccurrencesLabel(tag.occurrences),
                          foreground: theme.colorScheme.onSurface,
                          background: theme.colorScheme.surface.withOpacity(0.6),
                          icon: Icons.repeat,
                        ),
                        _buildBadge(
                          theme: theme,
                          label: t.memoryTagDetailConfidence(confidenceValue),
                          foreground: theme.colorScheme.onSurface,
                          background: theme.colorScheme.surface.withOpacity(0.6),
                          icon: Icons.trending_up_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics(BuildContext context, MemoryTag tag) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations t = AppLocalizations.of(context);
    final String confidenceValue = tag.confidence > 1
        ? '${tag.confidence.toStringAsFixed(0)}%'
        : '${(tag.confidence * 100).toStringAsFixed(0)}%';
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.memoryTagDetailStatisticsTitle,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Wrap(
            spacing: AppTheme.spacing3,
            runSpacing: AppTheme.spacing3,
            children: [
              _buildStatTile(
                context: context,
                icon: Icons.repeat,
                label: t.memoryTagDetailOccurrences(tag.occurrences),
              ),
              _buildStatTile(
                context: context,
                icon: Icons.trending_up_outlined,
                label: t.memoryTagDetailConfidence(confidenceValue),
              ),
              _buildStatTile(
                context: context,
                icon: Icons.calendar_today_outlined,
                label: t.memoryTagDetailFirstSeen(_formatDateTime(context, tag.firstSeenAt)),
              ),
              _buildStatTile(
                context: context,
                icon: Icons.update,
                label: t.memoryTagDetailLastSeen(_formatDateTime(context, tag.lastSeenAt)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withOpacity(0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: AppTheme.spacing2),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceSection(BuildContext context, MemoryTag tag) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations t = AppLocalizations.of(context);
    final List<TagEvidence> evidences = tag.evidences;

    if (tag.evidenceTotalCount == 0 && evidences.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.55),
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        child: Center(
          child: Text(
            t.memoryTagDetailNoEvidence,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.memoryTagDetailEvidenceTitle,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            t.memoryTagDetailEvidenceCount(tag.evidenceTotalCount),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppTheme.spacing3),
          if (evidences.isEmpty)
            Text(
              t.memoryTagDetailNoEvidence,
              style: theme.textTheme.bodyMedium,
            )
          else
            Column(
              children: evidences
                  .asMap()
                  .entries
                  .map((entry) => _buildEvidenceCard(context, entry.key + 1, entry.value))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildEvidenceCard(BuildContext context, int index, TagEvidence evidence) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations t = AppLocalizations.of(context);
    final String excerpt = evidence.excerpt.trim().isEmpty ? '...' : evidence.excerpt.trim();
    final bool hasNotes = evidence.notes != null && evidence.notes!.trim().isNotEmpty;
    final bool showInference = hasNotes && !evidence.isUserEdited;
    final String noteLabel = showInference ? t.memoryEvidenceInferenceLabel : t.memoryEvidenceNotesLabel;
    final String noteContent = hasNotes ? evidence.notes!.trim() : t.memoryEvidenceNoNotes;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing3),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '#$index',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            excerpt,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            '$noteLabel: $noteContent',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (evidence.isUserEdited)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spacing2),
              child: _buildBadge(
                theme: theme,
                label: t.memoryEvidenceUserEditedBadge,
                foreground: theme.colorScheme.secondary,
                background: theme.colorScheme.secondary.withOpacity(0.18),
                icon: Icons.edit_note_outlined,
              ),
            ),
          const SizedBox(height: AppTheme.spacing3),
          Text(
            t.memoryEvidenceEventHeading,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.spacing2),
          FutureBuilder<MemoryEventSummary?>(
            future: _getEvent(evidence.eventId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              final MemoryEventSummary? summary = snapshot.data;
              if (summary == null) {
                return Text(
                  t.memoryTagDetailNoEvidence,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.memoryEventTimeLabel(_formatDateTime(context, summary.occurredAt)),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  Text(
                    summary.content,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  Wrap(
                    spacing: AppTheme.spacing2,
                    runSpacing: AppTheme.spacing2,
                    children: [
                      _buildBadge(
                        theme: theme,
                        label: t.memoryEventSourceLabel(summary.source),
                        foreground: theme.colorScheme.onSurface,
                        background: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        icon: Icons.source_outlined,
                      ),
                      _buildBadge(
                        theme: theme,
                        label: t.memoryEventTypeLabel(summary.type),
                        foreground: theme.colorScheme.onSurface,
                        background: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        icon: Icons.label_outline,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _categoryLabel(BuildContext context, String category) {
    final AppLocalizations t = AppLocalizations.of(context);
    switch (category) {
      case MemoryTagCategory.identity:
        return t.memoryCategoryIdentity;
      case MemoryTagCategory.relationship:
        return t.memoryCategoryRelationship;
      case MemoryTagCategory.interest:
        return t.memoryCategoryInterest;
      case MemoryTagCategory.behavior:
        return t.memoryCategoryBehavior;
      case MemoryTagCategory.preference:
        return t.memoryCategoryPreference;
      default:
        return t.memoryCategoryOther;
    }
  }

  Color _accentForCategory(ThemeData theme, String category, bool isConfirmed) {
    final ColorScheme scheme = theme.colorScheme;
    switch (category) {
      case MemoryTagCategory.identity:
        return scheme.primary;
      case MemoryTagCategory.relationship:
        return scheme.secondary;
      case MemoryTagCategory.interest:
        return scheme.tertiary;
      case MemoryTagCategory.behavior:
        return scheme.error;
      case MemoryTagCategory.preference:
        return scheme.primaryContainer;
      default:
        return isConfirmed ? scheme.primary : scheme.secondary;
    }
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case MemoryTagCategory.identity:
        return Icons.person_outline;
      case MemoryTagCategory.relationship:
        return Icons.groups_outlined;
      case MemoryTagCategory.interest:
        return Icons.auto_awesome_outlined;
      case MemoryTagCategory.behavior:
        return Icons.track_changes_outlined;
      case MemoryTagCategory.preference:
        return Icons.favorite_border;
      default:
        return Icons.loyalty_outlined;
    }
  }

  Widget _buildBadge({
    required ThemeData theme,
    required String label,
    required Color foreground,
    Color? background,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: foreground.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: AppTheme.spacing1),
          ],
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(BuildContext context, DateTime? value) {
    if (value == null) {
      return '—';
    }
    return DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm().format(value);
  }
}


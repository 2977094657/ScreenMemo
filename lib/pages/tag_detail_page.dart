import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/memory_models.dart';
import '../services/memory_bridge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';

/// 标签详情页：展示指定标签的基础信息与片段列表。
class TagDetailPage extends StatefulWidget {
  const TagDetailPage({super.key, required this.tagId, required this.initialTag});

  final int tagId;
  final MemoryTag initialTag;

  @override
  State<TagDetailPage> createState() => _TagDetailPageState();
}

class _TagDetailPageState extends State<TagDetailPage> {
  final MemoryBridgeService _service = MemoryBridgeService.instance;

  MemoryTag? _tag;
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tag = widget.initialTag;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTag();
    });
  }

  Future<void> _loadTag() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final MemoryTag? fetched = await _service.fetchTagById(widget.tagId);
      if (!mounted) return;
      if (fetched != null) {
        setState(() {
          _tag = fetched;
        });
      } else {
        final AppLocalizations t = AppLocalizations.of(context);
        setState(() {
          _errorMessage = t.memoryTagDetailLoadFailed;
        });
        UINotifier.error(context, t.memoryTagDetailLoadFailed);
      }
    } catch (_) {
      if (!mounted) return;
      final AppLocalizations t = AppLocalizations.of(context);
      setState(() {
        _errorMessage = t.memoryTagDetailLoadFailed;
      });
      UINotifier.error(context, t.memoryTagDetailLoadFailed);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
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
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing3),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: t.memoryTagDetailRefresh,
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _loadTag,
            ),
        ],
      ),
      body: RefreshIndicator(
        color: theme.colorScheme.primary,
        onRefresh: _loadTag,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing4,
            vertical: AppTheme.spacing4,
          ),
          children: tag == null
              ? <Widget>[_buildPlaceholder(theme, t)]
              : <Widget>[
                  _buildOverviewCard(tag, t, theme),
                  const SizedBox(height: AppTheme.spacing4),
                  _buildFragmentCard(tag, t, theme),
                ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme, AppLocalizations t) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.4,
      child: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Text(
                _errorMessage ?? t.memoryTagDetailLoadFailed,
                style: theme.textTheme.bodyMedium,
              ),
      ),
    );
  }

  Widget _buildOverviewCard(MemoryTag tag, AppLocalizations t, ThemeData theme) {
    final String title = tag.label.isEmpty ? tag.fullPath : tag.label;
    final bool showPath = tag.fullPath.isNotEmpty && tag.fullPath.trim() != title.trim();
    final Widget? firstSeen = tag.firstSeenAt != null
        ? _buildMetaText(
            Icons.flag_outlined,
            t.memoryTagDetailFirstSeen(_formatDate(tag.firstSeenAt, t)),
            theme,
          )
        : null;
    final Widget? lastSeen = tag.lastSeenAt != null
        ? _buildMetaText(
            Icons.update_outlined,
            t.memoryTagDetailLastSeen(_formatDate(tag.lastSeenAt, t)),
            theme,
          )
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (showPath) ...[
              const SizedBox(height: AppTheme.spacing1),
              Text(
                tag.fullPath,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (firstSeen != null || lastSeen != null) ...[
              const SizedBox(height: AppTheme.spacing3),
              if (firstSeen != null && lastSeen != null)
                Row(
                  children: [
                    Expanded(child: firstSeen),
                    const SizedBox(width: AppTheme.spacing4),
                    Expanded(child: lastSeen),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: firstSeen ?? lastSeen!,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFragmentCard(MemoryTag tag, AppLocalizations t, ThemeData theme) {
    final List<TagEvidence> fragments = tag.evidences;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _fragmentTitle(t),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _fragmentCountLabel(t, tag.evidenceTotalCount),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            if (fragments.isEmpty)
              Text(
                _fragmentEmptyLabel(t),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._buildFragmentList(fragments, t, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFragmentList(
    List<TagEvidence> fragments,
    AppLocalizations t,
    ThemeData theme,
  ) {
    final List<Widget> widgets = <Widget>[];
    for (int i = 0; i < fragments.length; i += 1) {
      widgets.add(_buildFragmentItem(fragments[i], t, theme));
      if (i != fragments.length - 1) {
        widgets.add(const SizedBox(height: AppTheme.spacing3));
      }
    }
    return widgets;
  }

  Widget _buildFragmentItem(TagEvidence fragment, AppLocalizations t, ThemeData theme) {
    final String notes = (fragment.notes ?? '').trim();
    final String excerpt = fragment.excerpt.trim();
    final _FragmentText notesInfo = _normalizeFragmentText(notes);
    final _FragmentText excerptInfo = _normalizeFragmentText(excerpt);

    final String primary = notesInfo.cleaned.isNotEmpty ? notesInfo.cleaned : excerptInfo.cleaned;
    final String secondary =
        notesInfo.cleaned.isNotEmpty && excerptInfo.cleaned.isNotEmpty ? excerptInfo.cleaned : '';
    final String? reference = notesInfo.reference ?? excerptInfo.reference;
    final String metaValue = reference != null
        ? _formatReferenceLabel(reference, t)
        : _formatDateTime(fragment.lastModifiedAt ?? fragment.createdAt, t);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary.isEmpty ? _fragmentEmptyLabel(t) : primary,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.4),
          ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing1),
            Text(
              secondary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: AppTheme.spacing2),
          _buildMetaText(
            Icons.schedule_outlined,
            metaValue,
            theme,
          ),
        ],
      ),
    );
  }

  _FragmentText _normalizeFragmentText(String text) {
    if (text.isEmpty) {
      return const _FragmentText(cleaned: '');
    }
    final RegExp pattern = RegExp(r'\[ref=([^\]]+)\]');
    String? reference;
    String cleaned = text;
    cleaned = cleaned.replaceAllMapped(pattern, (Match match) {
      reference ??= match.group(1)?.trim();
      return '';
    });
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return _FragmentText(cleaned: cleaned, reference: reference);
  }

  String _formatReferenceLabel(String reference, AppLocalizations t) {
    final String trimmed = reference.trim();
    if (trimmed.isEmpty) {
      return '--';
    }
    String candidate = trimmed;
    final int colonIndex = trimmed.indexOf(':');
    if (colonIndex != -1 && colonIndex < trimmed.length - 1) {
      candidate = trimmed.substring(colonIndex + 1).trim();
    }
    final DateTime? parsed = DateTime.tryParse(candidate);
    if (parsed != null) {
      return _formatDate(parsed, t);
    }
    return candidate;
  }

  Widget _buildMetaText(IconData icon, String text, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16.0, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppTheme.spacing1),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing1 + 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16.0, color: foreground),
          const SizedBox(width: AppTheme.spacing1),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(AppLocalizations t, MemoryTag tag) {
    final String locale = t.localeName;
    final bool confirmed = tag.isConfirmed;
    switch (locale) {
      case 'zh':
        return confirmed ? '已确认' : '待确认';
      case 'ja':
        return confirmed ? '確認済み' : '確認待ち';
      case 'ko':
        return confirmed ? '확인됨' : '확인 대기';
      default:
        return confirmed ? 'Confirmed' : 'Pending';
    }
  }

  String _categoryLabel(AppLocalizations t, String category) {
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

  String _fragmentTitle(AppLocalizations t) {
    switch (t.localeName) {
      case 'zh':
        return '相关片段';
      case 'ja':
        return '関連スニペット';
      case 'ko':
        return '관련 스니펫';
      default:
        return 'Fragments';
    }
  }

  String _fragmentCountLabel(AppLocalizations t, int count) {
    switch (t.localeName) {
      case 'zh':
        return '片段数量：$count';
      case 'ja':
        return 'スニペット数: $count';
      case 'ko':
        return '조각 수: $count';
      default:
        return 'Fragments: $count';
    }
  }

  String _fragmentEmptyLabel(AppLocalizations t) {
    switch (t.localeName) {
      case 'zh':
        return '暂无片段';
      case 'ja':
        return 'スニペットがありません';
      case 'ko':
        return '등록된 조각이 없습니다';
      default:
        return 'No fragments yet';
    }
  }

  String _formatDate(DateTime? dateTime, AppLocalizations t) {
    if (dateTime == null) {
      return '--';
    }
    try {
      final DateFormat formatter = DateFormat.yMMMd(t.localeName);
      return formatter.format(dateTime);
    } catch (_) {
      return DateFormat('yyyy-MM-dd').format(dateTime);
    }
  }

  String _formatDateTime(DateTime? dateTime, AppLocalizations t) {
    if (dateTime == null) {
      return '--';
    }
    try {
      final DateFormat formatter = DateFormat.yMMMd(t.localeName).add_Hm();
      return formatter.format(dateTime);
    } catch (_) {
      return dateTime.toIso8601String();
    }
  }
}

class _FragmentText {
  const _FragmentText({required this.cleaned, this.reference});

  final String cleaned;
  final String? reference;
}

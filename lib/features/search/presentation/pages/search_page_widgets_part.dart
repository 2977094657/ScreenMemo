part of 'search_page.dart';

// ========== Markdown 结果卡片 Widget ==========
/// Markdown 自定义高亮标签渲染
class MarkBuilder extends MarkdownElementBuilder {
  MarkBuilder(this.decoration);

  final Decoration decoration;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final children = <InlineSpan>[];
    for (final node in element.children ?? <md.Node>[]) {
      if (node is md.Text) {
        children.add(TextSpan(text: node.text, style: preferredStyle));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: decoration,
      child: Text.rich(TextSpan(children: children)),
    );
  }
}

// 筛选面板Widget - 优化UI版本
class _FilterSheet extends StatefulWidget {
  final String timeFilter;
  final String sizeFilter;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final Function(
    String time,
    String size,
    DateTime? startDate,
    DateTime? endDate,
  )
  onApply;
  final VoidCallback onReset;

  const _FilterSheet({
    required this.timeFilter,
    required this.sizeFilter,
    this.customStartDate,
    this.customEndDate,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _timeFilter;
  late String _sizeFilter;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _timeFilter = widget.timeFilter;
    _sizeFilter = widget.sizeFilter;
    _customStartDate = widget.customStartDate;
    _customEndDate = widget.customEndDate;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return UISheetSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacing3,
          0,
          AppTheme.spacing3,
          AppTheme.spacing3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppTheme.spacing3),
            const Center(child: UISheetHandle()),
            const SizedBox(height: AppTheme.spacing3),
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.searchFiltersTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 大小筛选
            Text(
              l10n.filterBySize,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _buildFilterChip(
                  l10n.filterSizeAll,
                  'all',
                  _sizeFilter,
                  (v) => setState(() => _sizeFilter = v),
                ),
                _buildFilterChip(
                  l10n.filterSizeSmall,
                  'small',
                  _sizeFilter,
                  (v) => setState(() => _sizeFilter = v),
                ),
                _buildFilterChip(
                  l10n.filterSizeMedium,
                  'medium',
                  _sizeFilter,
                  (v) => setState(() => _sizeFilter = v),
                ),
                _buildFilterChip(
                  l10n.filterSizeLarge,
                  'large',
                  _sizeFilter,
                  (v) => setState(() => _sizeFilter = v),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 按钮栏
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.onReset();
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      l10n.resetFilters,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(
                        _timeFilter,
                        _sizeFilter,
                        _customStartDate,
                        _customEndDate,
                      );
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      l10n.applyFilters,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    String currentValue,
    Function(String) onSelected,
  ) {
    final isSelected = currentValue == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) => onSelected(value),
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
      checkmarkColor: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      side: isSelected
          ? BorderSide.none
          : BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_memo/app/navigation/bottom_navigation_config.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

class CustomizeBottomNavigationPage extends StatefulWidget {
  const CustomizeBottomNavigationPage({super.key, required this.initialItems});

  final List<BottomNavItemId> initialItems;

  @override
  State<CustomizeBottomNavigationPage> createState() =>
      _CustomizeBottomNavigationPageState();
}

class _CustomizeBottomNavigationPageState
    extends State<CustomizeBottomNavigationPage>
    with SingleTickerProviderStateMixin {
  late List<BottomNavItemId> _items;
  late final AnimationController _wiggleController;

  @override
  void initState() {
    super.initState();
    _items = BottomNavigationConfig.normalizeItems(widget.initialItems);
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    )..repeat();
  }

  @override
  void dispose() {
    _wiggleController.dispose();
    super.dispose();
  }

  void _addItem(BottomNavItemId id) {
    if (_items.contains(id)) return;
    if (_items.length >= BottomNavigationConfig.maxItems) {
      UINotifier.warning(
        context,
        AppLocalizations.of(context).bottomNavMaxTabsToast,
      );
      return;
    }
    setState(() => _items = <BottomNavItemId>[..._items, id]);
  }

  void _removeItem(BottomNavItemId id) {
    if (id == BottomNavItemId.home) return;
    if (_items.length <= BottomNavigationConfig.minItems) {
      UINotifier.warning(
        context,
        AppLocalizations.of(context).bottomNavMinTabsToast,
      );
      return;
    }
    setState(() {
      _items = _items.where((BottomNavItemId item) => item != id).toList();
    });
  }

  void _moveItem(int oldIndex, int newIndex) {
    if (oldIndex == 0) return;
    if (newIndex == 0) newIndex = 1;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(1, _items.length - 1);
    if (oldIndex == newIndex) return;
    setState(() {
      final BottomNavItemId item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _items = BottomNavigationConfig.normalizeItems(_items);
    });
  }

  void _confirm() {
    Navigator.of(
      context,
    ).pop<List<BottomNavItemId>>(BottomNavigationConfig.normalizeItems(_items));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final Color sheetBg = theme.colorScheme.surface;
    final Color pageBg = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        AppTheme.spacing3,
                        AppTheme.spacing4,
                        AppTheme.spacing2,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing5),
                          Text(
                            l10n.customizeBottomNavTitle,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppTheme.spacing2),
                          Text(
                            l10n.customizeBottomNavSubtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacing3,
                      AppTheme.spacing4,
                      AppTheme.spacing3,
                      AppTheme.spacing4,
                    ),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppTheme.spacing3,
                            mainAxisSpacing: AppTheme.spacing3,
                            childAspectRatio: 1.72,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final BottomNavItemId id =
                              BottomNavigationConfig.configurableItems[index];
                          return _CandidateCard(
                            key: ValueKey<String>(
                              'candidate_${id.storageValue}',
                            ),
                            item: bottomNavItemPresentation(context, id),
                            selected: _items.contains(id),
                            onAdd: () => _addItem(id),
                          );
                        },
                        childCount:
                            BottomNavigationConfig.configurableItems.length,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: sheetBg,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outline, width: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacing3,
                  AppTheme.spacing3,
                  AppTheme.spacing3,
                  AppTheme.spacing3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SelectedNavigationPreview(
                      items: _items,
                      wiggleController: _wiggleController,
                      onRemove: _removeItem,
                      onMove: _moveItem,
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        key: const ValueKey<String>('confirm_bottom_nav'),
                        onPressed: _confirm,
                        child: Text(
                          l10n.actionConfirm,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    super.key,
    required this.item,
    required this.selected,
    required this.onAdd,
  });

  final BottomNavItemPresentation item;
  final bool selected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color iconColor = selected
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        side: BorderSide(color: theme.colorScheme.outline, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: selected ? null : onAdd,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing3),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 30, color: iconColor),
                    const SizedBox(height: AppTheme.spacing3),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing1),
                    Text(
                      item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    selected ? Icons.check : Icons.add,
                    color: selected
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedNavigationPreview extends StatelessWidget {
  const _SelectedNavigationPreview({
    required this.items,
    required this.wiggleController,
    required this.onRemove,
    required this.onMove,
  });

  final List<BottomNavItemId> items;
  final AnimationController wiggleController;
  final ValueChanged<BottomNavItemId> onRemove;
  final void Function(int oldIndex, int newIndex) onMove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outline, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double itemWidth = constraints.maxWidth / items.length;
          return ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            onReorder: onMove,
            proxyDecorator:
                (Widget child, int index, Animation<double> animation) {
                  final BottomNavItemPresentation item =
                      bottomNavItemPresentation(context, items[index]);
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      final double scale =
                          1 + Curves.easeOut.transform(animation.value) * 0.04;
                      return Material(
                        type: MaterialType.transparency,
                        child: SizedBox(
                          width: itemWidth,
                          height: 78,
                          child: Center(
                            child: Transform.scale(
                              scale: scale,
                              child: _SelectedNavGlyph(
                                item: item,
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
            itemBuilder: (context, index) {
              final BottomNavItemId id = items[index];
              final bool locked = id == BottomNavItemId.home;
              return SizedBox(
                key: ValueKey<String>('selected_nav_${id.storageValue}'),
                width: itemWidth,
                child: _SelectedNavTile(
                  item: bottomNavItemPresentation(context, id),
                  locked: locked,
                  highlighted: false,
                  wiggleController: wiggleController,
                  dragIndex: locked ? null : index,
                  onRemove: () => onRemove(id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SelectedNavTile extends StatelessWidget {
  const _SelectedNavTile({
    required this.item,
    required this.locked,
    required this.highlighted,
    required this.wiggleController,
    required this.dragIndex,
    required this.onRemove,
  });

  final BottomNavItemPresentation item;
  final bool locked;
  final bool highlighted;
  final AnimationController wiggleController;
  final int? dragIndex;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = locked
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.50)
        : theme.colorScheme.onSurface;
    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 78,
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildGlyph(color),
          if (!locked)
            Positioned(
              top: 4,
              right: 8,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.remove,
                    color: theme.colorScheme.onSurface,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (locked) return content;
    return AnimatedBuilder(
      animation: wiggleController,
      child: content,
      builder: (context, child) {
        final double phase = wiggleController.value * math.pi * 2;
        final double wave = math.sin(phase);
        final double dx = wave * 1.4;
        final double angle = wave * 0.014;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.rotate(angle: angle, child: child),
        );
      },
    );
  }

  Widget _buildGlyph(Color color) {
    final Widget glyph = _SelectedNavGlyph(
      item: item,
      color: color,
      fontWeight: locked ? FontWeight.w500 : FontWeight.w600,
    );
    final int? index = dragIndex;
    if (index == null) return glyph;
    return ReorderableDragStartListener(index: index, child: glyph);
  }
}

class _SelectedNavGlyph extends StatelessWidget {
  const _SelectedNavGlyph({
    required this.item,
    required this.color,
    required this.fontWeight,
  });

  final BottomNavItemPresentation item;
  final Color color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(item.icon, size: 24, color: color),
        const SizedBox(height: 2),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: fontWeight,
            letterSpacing: 0,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

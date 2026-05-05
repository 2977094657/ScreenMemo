part of 'search_page.dart';

// ========== 筛选与详情弹窗逻辑 ==========
extension _SearchPageSheetsPart on _SearchPageState {
  /// 显示标签筛选底部弹窗
  void _showTagFilterSheet() {
    if (_availableTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).noAvailableTags)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: UISheetSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const Center(child: UISheetHandle()),
                    const SizedBox(height: AppTheme.spacing3),
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).tagFilterTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          if (_selectedTags.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setSheetState(() {
                                  _selectedTags.clear();
                                });
                                _searchSetState(() {});
                              },
                              child: Text(
                                AppLocalizations.of(context).clearAll,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    // 标签列表
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        child: Builder(
                          builder: (context) {
                            final List<String> tags =
                                _availableTags
                                    .map((t) => _cleanTagText(t))
                                    .where((t) => _isValidTag(t))
                                    .toList()
                                  ..sort((a, b) => a.compareTo(b));

                            return Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: tags.map((tag) {
                                final selected = _selectedTags.contains(tag);
                                return FilterChip(
                                  label: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: selected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  selected: selected,
                                  showCheckmark: false,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surface,
                                  selectedColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.15),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusSm,
                                    ),
                                  ),
                                  side: selected
                                      ? BorderSide.none
                                      : BorderSide(
                                          color: Colors.grey.withOpacity(0.2),
                                          width: 1,
                                        ),
                                  onSelected: (value) {
                                    setSheetState(() {
                                      if (value) {
                                        _selectedTags.add(tag);
                                      } else {
                                        _selectedTags.remove(tag);
                                      }
                                    });
                                    _searchSetState(() {});
                                  },
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    // 确认按钮
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        0,
                        AppTheme.spacing4,
                        AppTheme.spacing4,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            AppLocalizations.of(context).confirmSelectionLabel(
                              _selectedTags.isEmpty
                                  ? AppLocalizations.of(
                                      context,
                                    ).selectedAllLabel
                                  : AppLocalizations.of(
                                      context,
                                    ).selectedTagsCount(_selectedTags.length),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSemanticTagFilterSheet() {
    if (_semanticAvailableTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).noAvailableTags)),
      );
      return;
    }

    final List<String> ordered = _semanticAvailableTags.toList(growable: false)
      ..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: UISheetSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const Center(child: UISheetHandle()),
                    const SizedBox(height: AppTheme.spacing3),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).tagFilterTitle,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          if (_semanticSelectedTags.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setSheetState(
                                  () => _semanticSelectedTags.clear(),
                                );
                                _searchSetState(() {
                                  _semanticSelectedTags.clear();
                                  _applySemanticTagFilter();
                                });
                              },
                              child: Text(
                                AppLocalizations.of(context).actionClear,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ordered
                              .map((tag) {
                                final bool selected = _semanticSelectedTags
                                    .contains(tag);
                                return FilterChip(
                                  label: Text(
                                    tag,
                                    style: TextStyle(
                                      color: selected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  selected: selected,
                                  showCheckmark: false,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surface,
                                  selectedColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.15),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusSm,
                                    ),
                                  ),
                                  side: selected
                                      ? BorderSide.none
                                      : BorderSide(
                                          color: Colors.grey.withOpacity(0.2),
                                          width: 1,
                                        ),
                                  onSelected: (value) {
                                    setSheetState(() {
                                      if (value) {
                                        _semanticSelectedTags.add(tag);
                                      } else {
                                        _semanticSelectedTags.remove(tag);
                                      }
                                    });
                                    _searchSetState(() {
                                      if (value) {
                                        _semanticSelectedTags.add(tag);
                                      } else {
                                        _semanticSelectedTags.remove(tag);
                                      }
                                      _applySemanticTagFilter();
                                    });
                                  },
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        0,
                        AppTheme.spacing4,
                        AppTheme.spacing4,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            AppLocalizations.of(context).confirmSelectionLabel(
                              _semanticSelectedTags.isEmpty
                                  ? AppLocalizations.of(
                                      context,
                                    ).selectedAllLabel
                                  : AppLocalizations.of(
                                      context,
                                    ).selectedTagsCount(
                                      _semanticSelectedTags.length,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDocTypeFilterSheet() {
    final List<String> ordered = <String>[
      kSearchDocTypeDailySummary,
      kSearchDocTypeMorningInsights,
      kSearchDocTypeFavoriteNote,
    ];
    final Set<String> active =
        (_docSelectedTypes.isEmpty ||
            _docSelectedTypes.length == _SearchPageState._docTabTypes.length)
        ? <String>{}
        : Set<String>.from(_docSelectedTypes);
    final Set<String> temp = Set<String>.from(active);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: UISheetSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const Center(child: UISheetHandle()),
                    const SizedBox(height: AppTheme.spacing3),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).typeFilterTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          if (temp.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setSheetState(() => temp.clear());
                              },
                              child: Text(
                                AppLocalizations.of(context).clearFilter,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: ordered
                                .map((type) {
                                  final String label = _docTypeLabel(type);
                                  final bool selected = temp.contains(type);
                                  return FilterChip(
                                    label: Text(
                                      label,
                                      style: TextStyle(
                                        color: selected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    selected: selected,
                                    showCheckmark: false,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    selectedColor: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.15),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusSm,
                                      ),
                                    ),
                                    side: selected
                                        ? BorderSide.none
                                        : BorderSide(
                                            color: Colors.grey.withOpacity(0.2),
                                            width: 1,
                                          ),
                                    onSelected: (value) {
                                      setSheetState(() {
                                        if (value) {
                                          temp.add(type);
                                        } else {
                                          temp.remove(type);
                                        }
                                      });
                                    },
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        0,
                        AppTheme.spacing4,
                        AppTheme.spacing4,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final Set<String> nextRaw = Set<String>.from(temp);
                            final Set<String> next =
                                (nextRaw.isEmpty ||
                                    nextRaw.length ==
                                        _SearchPageState._docTabTypes.length)
                                ? <String>{}
                                : nextRaw;

                            bool equals(Set<String> a, Set<String> b) {
                              if (a.length != b.length) return false;
                              for (final v in a) {
                                if (!b.contains(v)) return false;
                              }
                              return true;
                            }

                            final bool changed = !equals(next, active);
                            Navigator.of(context).pop();
                            if (!changed) return;
                            _searchSetState(() {
                              _docSelectedTypes = next;
                            });
                            if (_docSearchFinished &&
                                _lastQuery.trim().isNotEmpty &&
                                _tabController.index == 3) {
                              // ignore: unawaited_futures
                              _searchDocs(_lastQuery);
                            }
                          },
                          child: Text(
                            AppLocalizations.of(context).confirmSelectionLabel(
                              (temp.isEmpty ||
                                      temp.length ==
                                          _SearchPageState._docTabTypes.length)
                                  ? AppLocalizations.of(
                                      context,
                                    ).selectedAllLabel
                                  : AppLocalizations.of(
                                      context,
                                    ).selectedTypesCount(temp.length),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

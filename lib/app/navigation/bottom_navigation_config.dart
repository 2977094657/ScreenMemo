import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/data/settings/user_settings_service.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

enum BottomNavItemId {
  home,
  favorites,
  ai,
  timeline,
  settings,
  dynamic,
  storage,
}

extension BottomNavItemIdCodec on BottomNavItemId {
  String get storageValue {
    switch (this) {
      case BottomNavItemId.home:
        return 'home';
      case BottomNavItemId.favorites:
        return 'favorites';
      case BottomNavItemId.ai:
        return 'ai';
      case BottomNavItemId.timeline:
        return 'timeline';
      case BottomNavItemId.settings:
        return 'settings';
      case BottomNavItemId.dynamic:
        return 'dynamic';
      case BottomNavItemId.storage:
        return 'storage';
    }
  }

  static BottomNavItemId? parse(String value) {
    for (final BottomNavItemId id in BottomNavItemId.values) {
      if (id.storageValue == value) return id;
    }
    return null;
  }
}

class BottomNavigationConfig {
  BottomNavigationConfig._();

  static const int minItems = 3;
  static const int maxItems = 6;

  static const List<BottomNavItemId> defaultItems = <BottomNavItemId>[
    BottomNavItemId.home,
    BottomNavItemId.favorites,
    BottomNavItemId.ai,
    BottomNavItemId.timeline,
    BottomNavItemId.settings,
  ];

  static const List<BottomNavItemId> configurableItems = <BottomNavItemId>[
    BottomNavItemId.favorites,
    BottomNavItemId.ai,
    BottomNavItemId.timeline,
    BottomNavItemId.settings,
    BottomNavItemId.dynamic,
    BottomNavItemId.storage,
  ];

  static Future<List<BottomNavItemId>> loadItems() async {
    final String? raw = await UserSettingsService.instance.getString(
      UserSettingKeys.bottomNavigationItems,
    );
    return normalizeItems(parseItems(raw));
  }

  static Future<void> saveItems(List<BottomNavItemId> items) async {
    final List<BottomNavItemId> normalized = normalizeItems(items);
    await UserSettingsService.instance.setString(
      UserSettingKeys.bottomNavigationItems,
      jsonEncode(
        normalized.map((BottomNavItemId id) => id.storageValue).toList(),
      ),
    );
  }

  static List<BottomNavItemId>? parseItems(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final List<BottomNavItemId> result = <BottomNavItemId>[];
      for (final Object? value in decoded) {
        if (value is! String) return null;
        final BottomNavItemId? id = BottomNavItemIdCodec.parse(value);
        if (id == null) return null;
        result.add(id);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  static List<BottomNavItemId> normalizeItems(List<BottomNavItemId>? items) {
    if (items == null) return List<BottomNavItemId>.from(defaultItems);

    final List<BottomNavItemId> result = <BottomNavItemId>[
      BottomNavItemId.home,
    ];
    final Set<BottomNavItemId> seen = <BottomNavItemId>{BottomNavItemId.home};

    for (final BottomNavItemId id in items) {
      if (id == BottomNavItemId.home) continue;
      if (!configurableItems.contains(id)) continue;
      if (seen.add(id)) result.add(id);
    }

    if (result.length < minItems || result.length > maxItems) {
      return List<BottomNavItemId>.from(defaultItems);
    }
    return result;
  }
}

@immutable
class BottomNavItemPresentation {
  const BottomNavItemPresentation({
    required this.id,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.description,
  });

  final BottomNavItemId id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String description;

  Widget buildIcon({
    required bool selected,
    required Color color,
    required double size,
  }) {
    return Icon(selected ? activeIcon : icon, size: size, color: color);
  }
}

BottomNavItemPresentation bottomNavItemPresentation(
  BuildContext context,
  BottomNavItemId id,
) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  switch (id) {
    case BottomNavItemId.home:
      return BottomNavItemPresentation(
        id: id,
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: l10n.bottomNavHome,
        description: l10n.bottomNavHomeDesc,
      );
    case BottomNavItemId.favorites:
      return BottomNavItemPresentation(
        id: id,
        icon: Icons.favorite_outline,
        activeIcon: Icons.favorite,
        label: l10n.bottomNavFavorites,
        description: l10n.bottomNavFavoritesDesc,
      );
    case BottomNavItemId.ai:
      return BottomNavItemPresentation(
        id: id,
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome,
        label: l10n.bottomNavAi,
        description: l10n.bottomNavAiDesc,
      );
    case BottomNavItemId.timeline:
      return BottomNavItemPresentation(
        id: id,
        icon: Icons.timeline_outlined,
        activeIcon: Icons.timeline,
        label: l10n.bottomNavTimeline,
        description: l10n.bottomNavTimelineDesc,
      );
    case BottomNavItemId.settings:
      return BottomNavItemPresentation(
        id: id,
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: l10n.bottomNavSettings,
        description: l10n.bottomNavSettingsDesc,
      );
    case BottomNavItemId.dynamic:
      return BottomNavItemPresentation(
        id: id,
        icon: Icons.interests_outlined,
        activeIcon: Icons.interests,
        label: l10n.bottomNavDynamic,
        description: l10n.bottomNavDynamicDesc,
      );
    case BottomNavItemId.storage:
      return BottomNavItemPresentation(
        id: id,
        icon: Icons.storage_outlined,
        activeIcon: Icons.storage,
        label: l10n.bottomNavStorage,
        description: l10n.bottomNavStorageDesc,
      );
  }
}

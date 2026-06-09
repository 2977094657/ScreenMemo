import 'dart:convert';

import 'package:screen_memo/features/capture/data/per_app_screenshot_settings_service.dart';

/// 每应用 Activity 黑名单服务。
/// 黑名单存储于 PerAppScreenshotSettingsService 中，键名为 activity_blacklist，
/// 值为 JSONArray 字符串。
class PerAppActivityBlacklistService {
  PerAppActivityBlacklistService._internal();
  static final PerAppActivityBlacklistService instance =
      PerAppActivityBlacklistService._internal();

  /// 获取指定应用的 Activity 黑名单列表。
  Future<List<String>> getBlacklist(String packageName) async {
    final raw = await PerAppScreenshotSettingsService.instance
        ._getRaw(packageName, 'activity_blacklist');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存指定应用的 Activity 黑名单。
  Future<void> saveBlacklist(
      String packageName, List<String> blacklist) async {
    final raw = jsonEncode(blacklist);
    await PerAppScreenshotSettingsService.instance
        ._setRaw(packageName, 'activity_blacklist', raw);
  }

  /// 添加一个 Activity 到黑名单。
  Future<void> addToBlacklist(String packageName, String activityClass) async {
    final list = await getBlacklist(packageName);
    if (list.contains(activityClass)) return;
    list.add(activityClass);
    await saveBlacklist(packageName, list);
  }

  /// 从黑名单中移除一个 Activity。
  Future<void> removeFromBlacklist(
      String packageName, String activityClass) async {
    final list = await getBlacklist(packageName);
    list.remove(activityClass);
    await saveBlacklist(packageName, list);
  }

  /// 清空指定应用的黑名单。
  Future<void> clearBlacklist(String packageName) async {
    await PerAppScreenshotSettingsService.instance
        ._setRaw(packageName, 'activity_blacklist', null);
  }
}

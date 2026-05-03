import 'dart:async';
import 'package:screen_memo/models/favorite_record.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';

/// 收藏变更事件类型
enum FavoriteChangeType { added, removed, updated }

/// 收藏变更事件
class FavoriteChangeEvent {
  final int screenshotId;
  final String appPackageName;
  final FavoriteChangeType type;

  const FavoriteChangeEvent({
    required this.screenshotId,
    required this.appPackageName,
    required this.type,
  });
}

/// 收藏服务类
/// 封装收藏相关的业务逻辑
class FavoriteService {
  static FavoriteService? _instance;
  static FavoriteService get instance => _instance ??= FavoriteService._();

  FavoriteService._();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  // 收藏变更事件流
  final StreamController<FavoriteChangeEvent> _changeController =
      StreamController<FavoriteChangeEvent>.broadcast();

  /// 监听收藏变更事件
  Stream<FavoriteChangeEvent> get onFavoriteChanged => _changeController.stream;

  /// 发送收藏变更事件
  void _notifyChange(
    int screenshotId,
    String appPackageName,
    FavoriteChangeType type,
  ) {
    _changeController.add(
      FavoriteChangeEvent(
        screenshotId: screenshotId,
        appPackageName: appPackageName,
        type: type,
      ),
    );
  }

  /// 切换收藏状态
  /// 如果已收藏则取消，否则添加收藏
  Future<bool> toggleFavorite({
    required int screenshotId,
    required String appPackageName,
    String? note,
  }) async {
    try {
      final isFav = await _db.isFavorite(
        screenshotId: screenshotId,
        appPackageName: appPackageName,
      );

      bool success;
      if (isFav) {
        success = await _db.removeFavorite(
          screenshotId: screenshotId,
          appPackageName: appPackageName,
        );
        if (success) {
          _notifyChange(
            screenshotId,
            appPackageName,
            FavoriteChangeType.removed,
          );
        }
      } else {
        success = await _db.addOrUpdateFavorite(
          screenshotId: screenshotId,
          appPackageName: appPackageName,
          note: note,
        );
        if (success) {
          _notifyChange(screenshotId, appPackageName, FavoriteChangeType.added);
        }
      }
      return success;
    } catch (e) {
      print('切换收藏状态失败: $e');
      return false;
    }
  }

  /// 添加收藏
  Future<bool> addFavorite({
    required int screenshotId,
    required String appPackageName,
    String? note,
  }) async {
    final success = await _db.addOrUpdateFavorite(
      screenshotId: screenshotId,
      appPackageName: appPackageName,
      note: note,
    );
    if (success) {
      _notifyChange(screenshotId, appPackageName, FavoriteChangeType.added);
    }
    return success;
  }

  /// 取消收藏
  Future<bool> removeFavorite({
    required int screenshotId,
    required String appPackageName,
  }) async {
    final success = await _db.removeFavorite(
      screenshotId: screenshotId,
      appPackageName: appPackageName,
    );
    if (success) {
      _notifyChange(screenshotId, appPackageName, FavoriteChangeType.removed);
    }
    return success;
  }

  /// 检查是否已收藏
  Future<bool> isFavorite({
    required int screenshotId,
    required String appPackageName,
  }) async {
    return await _db.isFavorite(
      screenshotId: screenshotId,
      appPackageName: appPackageName,
    );
  }

  /// 批量检查收藏状态
  Future<Map<int, bool>> checkFavorites({
    required List<int> screenshotIds,
    required String appPackageName,
  }) async {
    return await _db.checkFavorites(
      screenshotIds: screenshotIds,
      appPackageName: appPackageName,
    );
  }

  /// 获取所有收藏及其对应的截图记录
  Future<List<Map<String, dynamic>>> getFavoritesWithScreenshots({
    int? limit,
    int? offset,
  }) async {
    try {
      final favorites = await _db.getAllFavorites(limit: limit, offset: offset);
      final List<Map<String, dynamic>> result = [];

      for (final fav in favorites) {
        final screenshotId = fav['screenshot_id'] as int;
        final appPackageName = fav['app_package_name'] as String;

        // 获取对应的截图记录
        try {
          final screenshots = await ScreenshotService.instance
              .getScreenshotsByApp(appPackageName, limit: 1, offset: 0);

          ScreenshotRecord? screenshot;
          for (final s in screenshots) {
            if (s.id == screenshotId) {
              screenshot = s;
              break;
            }
          }

          // 如果在首页没找到，尝试通过ID直接获取
          if (screenshot == null) {
            // 这里需要添加一个通过ID获取单个截图的方法
            // 暂时跳过未找到的截图
            continue;
          }

          result.add({
            'favorite': FavoriteRecord.fromMap(fav),
            'screenshot': screenshot,
          });
        } catch (e) {
          print('获取截图记录失败 (id=$screenshotId): $e');
          continue;
        }
      }

      return result;
    } catch (e) {
      print('获取收藏列表失败: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// 获取收藏总数
  Future<int> getFavoritesCount() async {
    return await _db.getFavoritesCount();
  }

  /// 更新收藏备注
  Future<bool> updateNote({
    required int screenshotId,
    required String appPackageName,
    String? note,
  }) async {
    final success = await _db.updateFavoriteNote(
      screenshotId: screenshotId,
      appPackageName: appPackageName,
      note: note,
    );
    if (success) {
      _notifyChange(screenshotId, appPackageName, FavoriteChangeType.updated);
    }
    return success;
  }

  /// 释放资源
  void dispose() {
    _changeController.close();
  }

  /// 获取收藏详情
  Future<FavoriteRecord?> getFavoriteDetail({
    required int screenshotId,
    required String appPackageName,
  }) async {
    final detail = await _db.getFavoriteDetail(
      screenshotId: screenshotId,
      appPackageName: appPackageName,
    );
    if (detail == null) return null;
    return FavoriteRecord.fromMap(detail);
  }
}

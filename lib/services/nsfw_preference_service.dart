import 'dart:async';
import 'package:collection/collection.dart';
import '../models/screenshot_record.dart';
import 'screenshot_database.dart';
import '../widgets/nsfw_guard.dart';

/// NSFW 偏好服务：
/// - 管理并缓存“禁用域名清单”
/// - 批量/单张查询“手动 NSFW 标记”
/// - 聚合判断某截图是否应被遮罩（手动标记 > 域名规则 > 自动识别）
///
/// 注意：
/// - 本服务为内存缓存 + DB 持久化。建议在页面加载/分页追加后调用预加载接口，保证判定为 O(1)。
class NsfwPreferenceService {
  static NsfwPreferenceService? _instance;
  static NsfwPreferenceService get instance => _instance ??= NsfwPreferenceService._();

  NsfwPreferenceService._();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  // 规则缓存
  bool _rulesLoaded = false;
  final Set<String> _exactHosts = <String>{};       // 例：example.com
  final Set<String> _wildcardBases = <String>{};    // 例：example.com（对应 *.example.com）

  // 手动标记缓存：key = "$appPackageName#$screenshotId"
  final Set<String> _manualKeys = <String>{};

  // 简单并发保护
  Future<void>? _rulesLoading;
  final Map<String, Future<void>> _manualBatchLoadingByApp = <String, Future<void>>{};

  // ============ 规则加载与缓存 ============

  Future<void> ensureRulesLoaded() async {
    if (_rulesLoaded) return;
    _rulesLoading ??= _reloadRulesInternal();
    await _rulesLoading;
  }

  Future<void> reloadRules() async {
    await _reloadRulesInternal();
  }

  Future<void> _reloadRulesInternal() async {
    try {
      _exactHosts.clear();
      _wildcardBases.clear();
      final rows = await _db.listNsfwDomainRules();
      for (final r in rows) {
        final pattern = (r['pattern'] as String?)?.trim().toLowerCase();
        final isWildcard = ((r['is_wildcard'] as int?) ?? 0) == 1;
        if (pattern == null || pattern.isEmpty) continue;
        if (isWildcard) {
          _wildcardBases.add(pattern);
        } else {
          _exactHosts.add(pattern);
        }
      }
      _rulesLoaded = true;
    } finally {
      _rulesLoading = null;
    }
  }

  // ============ 规则增删查（包含规范化与校验） ============

  /// 规范化与校验域名输入。
  /// 返回 (host, isWildcard)。若非法，抛出 [FormatException]。
  (String host, bool isWildcard) normalizeAndValidate(String input) {
    String s = input.trim().toLowerCase();

    // 去协议
    final protoIdx = s.indexOf('://');
    if (protoIdx > 0) {
      s = s.substring(protoIdx + 3);
    }
    // 去 path/query/fragment
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    final qm = s.indexOf('?');
    if (qm >= 0) s = s.substring(0, qm);
    final sharp = s.indexOf('#');
    if (sharp >= 0) s = s.substring(0, sharp);
    // 去端口
    final colon = s.indexOf(':');
    if (colon >= 0) s = s.substring(0, colon);

    s = s.trim();
    s = s.replaceAll(RegExp(r'\s+'), '');
    s = s.replaceAll(RegExp(r'^\.+'), '');
    s = s.replaceAll(RegExp(r'\.+$'), '');

    if (s.isEmpty) {
      throw FormatException('Empty host');
    }

    bool isWildcard = false;
    if (s.startsWith('*.')) {
      isWildcard = true;
      s = s.substring(2);
      if (s.isEmpty) {
        throw FormatException('Invalid wildcard');
      }
    }

    // 仅允许字母数字、点和中横线
    if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(s)) {
      throw FormatException('Invalid characters in host');
    }
    // 必须包含至少一个点（避免单段 TLD/内网名误填）
    if (!s.contains('.')) {
      throw FormatException('Host must contain at least one dot');
    }

    return (s, isWildcard);
  }

  /// 预览匹配数量（用于 UI 确认）
  Future<int> previewMatchCount(String input) async {
    final (host, isWildcard) = normalizeAndValidate(input);
    await ensureRulesLoaded();
    return await _db.countScreenshotsMatchingDomain(host: host, includeSubdomains: isWildcard);
  }

  Future<bool> addRule(String input, {String? comment}) async {
    final (host, isWildcard) = normalizeAndValidate(input);
    final ok = await _db.addNsfwDomainRule(pattern: host, isWildcard: isWildcard, comment: comment);
    if (ok) {
      await reloadRules();
    }
    return ok;
  }

  Future<bool> removeRule(String input) async {
    // 删除时忽略通配符标记，只按规范化 host 删除（表唯一键为 pattern）
    final (host, _) = normalizeAndValidate(input);
    final ok = await _db.removeNsfwDomainRule(host);
    if (ok) await reloadRules();
    return ok;
  }

  Future<int> clearRules() async {
    final n = await _db.clearNsfwDomainRules();
    if (n >= 0) await reloadRules();
    return n;
  }

  Future<List<Map<String, dynamic>>> listRules() async {
    await ensureRulesLoaded();
    return await _db.listNsfwDomainRules();
  }

  // ============ 手动标记（批量预载 + 单次设置） ============

  Future<void> preloadManualFlags({
    required String appPackageName,
    required List<int> screenshotIds,
  }) async {
    if (screenshotIds.isEmpty) return;

    // 合并相同 app 的并发请求，避免风暴
    final key = appPackageName.toLowerCase();
    final future = _manualBatchLoadingByApp[key];
    if (future != null) {
      await future; // 等待在途加载完成，再做二次加载
    }

    final load = () async {
      try {
        final map = await _db.checkManualNsfw(
          screenshotIds: screenshotIds,
          appPackageName: appPackageName,
        );
        for (final entry in map.entries) {
          final id = entry.key;
          final flagged = entry.value;
          final k = _mkManualKey(appPackageName, id);
          if (flagged) {
            _manualKeys.add(k);
          } else {
            _manualKeys.remove(k);
          }
        }
      } finally {
        _manualBatchLoadingByApp.remove(key);
      }
    };

    final f = load();
    _manualBatchLoadingByApp[key] = f;
    await f;
  }

  Future<bool> setManualFlag({
    required int screenshotId,
    required String appPackageName,
    required bool flag,
  }) async {
    final ok = await _db.setManualNsfwFlag(
      screenshotId: screenshotId,
      appPackageName: appPackageName,
      flag: flag,
    );
    if (ok) {
      final k = _mkManualKey(appPackageName, screenshotId);
      if (flag) {
        _manualKeys.add(k);
      } else {
        _manualKeys.remove(k);
      }
    }
    return ok;
  }

  bool isManuallyFlaggedCached({
    required int screenshotId,
    required String appPackageName,
  }) {
    return _manualKeys.contains(_mkManualKey(appPackageName, screenshotId));
  }

  String _mkManualKey(String app, int id) => '${app.toLowerCase()}#$id';

  // ============ 聚合决策（同步，依赖预加载缓存） ============

  /// 同步判定：若未预加载，可能返回“保守假阴性”（不遮罩）。
  /// 建议：先调用 [preloadManualFlags] 与 [ensureRulesLoaded]。
  bool shouldMaskCached(ScreenshotRecord s, {String? imageUrl}) {
    // 1) 手动标记优先
    if (s.id != null && isManuallyFlaggedCached(screenshotId: s.id!, appPackageName: s.appPackageName)) {
      return true;
    }
    // 2) 域名规则（pageUrl / imageUrl）
    if (_matchesBlockedHost(s.pageUrl)) return true;
    if (_matchesBlockedHost(imageUrl)) return true;

    // 3) 现有自动识别（关键字/站点模式）
    return NsfwDetector.isNsfwUrl(s.pageUrl);
  }

  // ============ 规则匹配（仅依赖缓存） ============

  bool _matchesBlockedHost(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final host = _extractHost(url);
    if (host == null || host.isEmpty) return false;
    final h = host.toLowerCase();

    if (_exactHosts.contains(h)) return true;

    // 子域通配：以 ".base" 结尾
    // 例如 base=example.com，则 a.example.com 命中，但 example.com 本身不命中
    for (final base in _wildcardBases) {
      if (h.endsWith('.$base')) return true;
    }
    return false;
  }

  String? _extractHost(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {
      // 退化解析：去协议、端口、路径，大致提取 host
      var s = raw.trim().toLowerCase();
      final protoIdx = s.indexOf('://');
      if (protoIdx > 0) s = s.substring(protoIdx + 3);
      final slash = s.indexOf('/');
      if (slash >= 0) s = s.substring(0, slash);
      final qm = s.indexOf('?');
      if (qm >= 0) s = s.substring(0, qm);
      final sharp = s.indexOf('#');
      if (sharp >= 0) s = s.substring(0, sharp);
      final colon = s.indexOf(':');
      if (colon >= 0) s = s.substring(0, colon);
      s = s.replaceAll(RegExp(r'^\.+'), '').replaceAll(RegExp(r'\.+$'), '');
      if (RegExp(r'^[a-z0-9.-]+$').hasMatch(s)) return s;
    }
    return null;
  }
}
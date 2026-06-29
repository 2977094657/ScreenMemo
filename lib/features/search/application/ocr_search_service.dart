import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/models/screenshot_record.dart';

class OcrSearchService {
  OcrSearchService._();

  static final OcrSearchService instance = OcrSearchService._();

  final ScreenshotDatabase _database = ScreenshotDatabase.instance;

  bool _isLikelyCjkNoSpacesQuery(String query) {
    final String q = query.trim();
    if (q.isEmpty || RegExp(r'\s').hasMatch(q)) return false;
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
  }

  Future<bool> isOcrIndexAvailable() async {
    try {
      return await _database.isOcrIndexAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<List<ScreenshotRecord>> searchGlobal(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
    bool rankByRelevance = false,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    try {
      final String effectiveQuery = queryAdvanced?.toPlainText() ?? query;
      bool indexAvailable = false;
      try {
        indexAvailable = await _database.isOcrIndexAvailable();
      } catch (_) {}
      if (_isLikelyCjkNoSpacesQuery(effectiveQuery)) {
        int? likeCount;
        if (indexAvailable) {
          try {
            likeCount = await _database.countScreenshotsByOcrLike(
              effectiveQuery,
              startMillis: startMillis,
              endMillis: endMillis,
              minSize: minSize,
              maxSize: maxSize,
            );
          } catch (_) {}
        }
        List<ScreenshotRecord> likeResults = <ScreenshotRecord>[];
        try {
          likeResults = await _database.searchScreenshotsByOcrLike(
            effectiveQuery,
            limit: limit,
            offset: offset,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
        } catch (_) {}
        if (!indexAvailable ||
            likeResults.isNotEmpty ||
            (likeCount != null && likeCount > 0)) {
          return likeResults;
        }
        try {
          final List<ScreenshotRecord> ftsResults = await _database
              .searchScreenshotsByOcr(
                effectiveQuery,
                limit: limit,
                offset: offset,
                startMillis: startMillis,
                endMillis: endMillis,
                minSize: minSize,
                maxSize: maxSize,
                rankByRelevance: rankByRelevance,
                allowAdvanced: allowAdvanced,
                queryAdvanced: queryAdvanced,
              );
          return ftsResults.isNotEmpty ? ftsResults : likeResults;
        } catch (_) {
          return likeResults;
        }
      }
      if (indexAvailable) {
        try {
          final List<ScreenshotRecord> ftsResults = await _database
              .searchScreenshotsByOcr(
                effectiveQuery,
                limit: limit,
                offset: offset,
                startMillis: startMillis,
                endMillis: endMillis,
                minSize: minSize,
                maxSize: maxSize,
                rankByRelevance: rankByRelevance,
                allowAdvanced: allowAdvanced,
                queryAdvanced: queryAdvanced,
              );
          if (ftsResults.isNotEmpty) return ftsResults;
        } catch (_) {}
      }
      return await _database.searchScreenshotsByOcrLike(
        effectiveQuery,
        limit: limit,
        offset: offset,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (_) {
      return <ScreenshotRecord>[];
    }
  }

  Future<int> countGlobal(
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    try {
      final String effectiveQuery = queryAdvanced?.toPlainText() ?? query;
      bool indexAvailable = false;
      try {
        indexAvailable = await _database.isOcrIndexAvailable();
      } catch (_) {}
      if (_isLikelyCjkNoSpacesQuery(effectiveQuery)) {
        int likeCount = 0;
        try {
          likeCount = await _database.countScreenshotsByOcrLike(
            effectiveQuery,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
        } catch (_) {}
        if (likeCount > 0 || !indexAvailable) return likeCount;
        try {
          final int ftsCount = await _database.countScreenshotsByOcr(
            effectiveQuery,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
            allowAdvanced: allowAdvanced,
            queryAdvanced: queryAdvanced,
          );
          return ftsCount > 0 ? ftsCount : likeCount;
        } catch (_) {
          return likeCount;
        }
      }
      if (indexAvailable) {
        try {
          final int ftsCount = await _database.countScreenshotsByOcr(
            effectiveQuery,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
            allowAdvanced: allowAdvanced,
            queryAdvanced: queryAdvanced,
          );
          if (ftsCount > 0) return ftsCount;
        } catch (_) {}
      }
      return await _database.countScreenshotsByOcrLike(
        effectiveQuery,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (_) {
      return 0;
    }
  }

  Future<List<ScreenshotRecord>> searchForApp(
    String appPackageName,
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
    bool rankByRelevance = false,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    try {
      final String effectiveQuery = queryAdvanced?.toPlainText() ?? query;
      bool indexAvailable = false;
      try {
        indexAvailable = await _database.isOcrIndexAvailable();
      } catch (_) {}
      if (_isLikelyCjkNoSpacesQuery(effectiveQuery)) {
        int? likeCount;
        if (indexAvailable) {
          try {
            likeCount = await _database.countScreenshotsByOcrLikeForApp(
              appPackageName,
              effectiveQuery,
              startMillis: startMillis,
              endMillis: endMillis,
              minSize: minSize,
              maxSize: maxSize,
            );
          } catch (_) {}
        }
        List<ScreenshotRecord> likeResults = <ScreenshotRecord>[];
        try {
          likeResults = await _database.searchScreenshotsByOcrLikeForApp(
            appPackageName,
            effectiveQuery,
            limit: limit,
            offset: offset,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
        } catch (_) {}
        if (!indexAvailable ||
            likeResults.isNotEmpty ||
            (likeCount != null && likeCount > 0)) {
          return likeResults;
        }
        try {
          final List<ScreenshotRecord> ftsResults = await _database
              .searchScreenshotsByOcrForApp(
                appPackageName,
                effectiveQuery,
                limit: limit,
                offset: offset,
                startMillis: startMillis,
                endMillis: endMillis,
                minSize: minSize,
                maxSize: maxSize,
                rankByRelevance: rankByRelevance,
                allowAdvanced: allowAdvanced,
                queryAdvanced: queryAdvanced,
              );
          return ftsResults.isNotEmpty ? ftsResults : likeResults;
        } catch (_) {
          return likeResults;
        }
      }
      if (indexAvailable) {
        try {
          final List<ScreenshotRecord> ftsResults = await _database
              .searchScreenshotsByOcrForApp(
                appPackageName,
                effectiveQuery,
                limit: limit,
                offset: offset,
                startMillis: startMillis,
                endMillis: endMillis,
                minSize: minSize,
                maxSize: maxSize,
                rankByRelevance: rankByRelevance,
                allowAdvanced: allowAdvanced,
                queryAdvanced: queryAdvanced,
              );
          if (ftsResults.isNotEmpty) return ftsResults;
        } catch (_) {}
      }
      return await _database.searchScreenshotsByOcrLikeForApp(
        appPackageName,
        effectiveQuery,
        limit: limit,
        offset: offset,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (_) {
      return <ScreenshotRecord>[];
    }
  }

  Future<int> countForApp(
    String appPackageName,
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    try {
      final String effectiveQuery = queryAdvanced?.toPlainText() ?? query;
      bool indexAvailable = false;
      try {
        indexAvailable = await _database.isOcrIndexAvailable();
      } catch (_) {}
      if (_isLikelyCjkNoSpacesQuery(effectiveQuery)) {
        int likeCount = 0;
        try {
          likeCount = await _database.countScreenshotsByOcrLikeForApp(
            appPackageName,
            effectiveQuery,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
        } catch (_) {}
        if (likeCount > 0 || !indexAvailable) return likeCount;
        try {
          final int ftsCount = await _database.countScreenshotsByOcrForApp(
            appPackageName,
            effectiveQuery,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
            allowAdvanced: allowAdvanced,
            queryAdvanced: queryAdvanced,
          );
          return ftsCount > 0 ? ftsCount : likeCount;
        } catch (_) {
          return likeCount;
        }
      }
      if (indexAvailable) {
        try {
          final int ftsCount = await _database.countScreenshotsByOcrForApp(
            appPackageName,
            effectiveQuery,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
            allowAdvanced: allowAdvanced,
            queryAdvanced: queryAdvanced,
          );
          if (ftsCount > 0) return ftsCount;
        } catch (_) {}
      }
      return await _database.countScreenshotsByOcrLikeForApp(
        appPackageName,
        effectiveQuery,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (_) {
      return 0;
    }
  }
}

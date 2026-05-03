part of 'screenshot_database.dart';

/// Structured (AI-friendly) advanced search query.
///
/// The model should NOT write raw SQLite FTS query syntax. Instead it fills this
/// structure, and the app will compile it to a safe FTS5 MATCH string (and a
/// best-effort LIKE fallback spec for CJK / non-FTS paths).
class AdvancedSearchQuery {
  const AdvancedSearchQuery({
    this.must = const <String>[],
    this.any = const <String>[],
    this.mustNot = const <String>[],
    this.phrases = const <String>[],
    this.phrasesAny = const <String>[],
    this.near = const <AdvancedSearchNearClause>[],
    this.prefix = true,
  });

  /// All of these keyword groups must match (AND).
  final List<String> must;

  /// At least one of these keyword groups must match (OR group).
  final List<String> any;

  /// Exclude results matching these keyword groups.
  final List<String> mustNot;

  /// All of these phrases must match.
  final List<String> phrases;

  /// At least one of these phrases must match.
  final List<String> phrasesAny;

  /// Proximity constraints (FTS5 NEAR).
  final List<AdvancedSearchNearClause> near;

  /// Whether to use prefix matching for keyword tokens (default true).
  final bool prefix;

  /// Returns true if there is no positive constraint (i.e. only mustNot).
  bool get isEmptyPositive =>
      must.isEmpty &&
      any.isEmpty &&
      phrases.isEmpty &&
      phrasesAny.isEmpty &&
      near.isEmpty;

  bool get isEmpty => isEmptyPositive && mustNot.isEmpty;

  static List<String> _readStringList(Object? raw) {
    final List<String> out = <String>[];
    if (raw is String) {
      final String t = raw.trim();
      if (t.isNotEmpty) out.add(t);
      return out;
    }
    if (raw is List) {
      for (final v in raw) {
        final String t = (v ?? '').toString().trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  static String _collapseSpaces(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _cleanTermText(String text) {
    String t = text.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    // Remove characters that can introduce FTS syntax.
    t = t.replaceAll(RegExp(r'["():^*:]+'), ' ');
    return _collapseSpaces(t);
  }

  static List<String> _termTokens(String term, {int maxTokens = 6}) {
    final String t = _cleanTermText(term);
    if (t.isEmpty) return const <String>[];
    final List<String> parts = t
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return const <String>[];
    final List<String> limited = parts.length > maxTokens
        ? parts.sublist(0, maxTokens)
        : parts;
    return limited;
  }

  static String _cleanPhraseText(String text) {
    String t = text.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    // We wrap phrases in quotes; strip embedded quotes to avoid syntax errors.
    t = t.replaceAll('"', '');
    return _collapseSpaces(t);
  }

  /// Parse from tool JSON args (query_advanced).
  ///
  /// Returns null when input is missing/invalid or when there is no positive
  /// constraint (only must_not).
  static AdvancedSearchQuery? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> m = Map<String, dynamic>.from(raw as Map);

    final bool prefix = (m['prefix'] is bool) ? (m['prefix'] as bool) : true;

    final List<String> must = _readStringList(
      m['must'],
    ).map(_cleanTermText).where((e) => e.isNotEmpty).toList(growable: false);
    final List<String> any = _readStringList(
      m['any'],
    ).map(_cleanTermText).where((e) => e.isNotEmpty).toList(growable: false);
    final List<String> mustNot = _readStringList(
      m['must_not'],
    ).map(_cleanTermText).where((e) => e.isNotEmpty).toList(growable: false);

    final List<String> phrases = _readStringList(
      m['phrases'],
    ).map(_cleanPhraseText).where((e) => e.isNotEmpty).toList(growable: false);
    final List<String> phrasesAny = _readStringList(
      m['phrases_any'],
    ).map(_cleanPhraseText).where((e) => e.isNotEmpty).toList(growable: false);

    final List<AdvancedSearchNearClause> near = <AdvancedSearchNearClause>[];
    final Object? nearRaw = m['near'];
    if (nearRaw is List) {
      for (final v in nearRaw) {
        if (v is! Map) continue;
        final Map<String, dynamic> nm = Map<String, dynamic>.from(v as Map);
        final List<String> terms = _readStringList(nm['terms'])
            .map(_cleanTermText)
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
        if (terms.isEmpty) continue;
        final int? dist = (() {
          final Object? d = nm['distance'];
          if (d == null) return null;
          if (d is int) return d;
          if (d is num) return d.toInt();
          return int.tryParse(d.toString().trim());
        })();
        near.add(AdvancedSearchNearClause(terms: terms, distance: dist));
      }
    }

    final AdvancedSearchQuery out = AdvancedSearchQuery(
      must: must,
      any: any,
      mustNot: mustNot,
      phrases: phrases,
      phrasesAny: phrasesAny,
      near: near,
      prefix: prefix,
    );

    // A query with only exclusions is not representable in FTS5 MATCH safely.
    if (out.isEmptyPositive) return null;
    return out;
  }

  String toPlainText({int maxParts = 16}) {
    final List<String> parts = <String>[];
    void addAll(Iterable<String> xs) {
      for (final x in xs) {
        if (parts.length >= maxParts) break;
        final String t = x.trim();
        if (t.isEmpty) continue;
        parts.add(t);
      }
    }

    addAll(must);
    addAll(any);
    addAll(phrases);
    addAll(phrasesAny);
    for (final n in near) {
      addAll(n.terms);
      if (parts.length >= maxParts) break;
    }
    return parts.join(' ').trim();
  }

  String _formatToken(String token) {
    final String t = token.replaceAll('"', '').trim();
    if (t.isEmpty) return '';
    final String quoted = '"$t"';
    return prefix ? '$quoted*' : quoted;
  }

  String _formatTokenGroup(List<String> tokens) {
    final List<String> fs = <String>[];
    for (final tok in tokens) {
      final String f = _formatToken(tok);
      if (f.isNotEmpty) fs.add(f);
    }
    if (fs.isEmpty) return '';
    if (fs.length == 1) return fs.single;
    return '(${fs.join(' AND ')})';
  }

  /// Compile into an FTS5 MATCH expression.
  String toFtsMatch({
    int maxGroups = 12,
    int maxTokensPerGroup = 6,
    int maxNotGroups = 8,
    int maxNearClauses = 6,
  }) {
    final List<String> clauses = <String>[];

    // must: AND groups
    for (final String term in must.take(maxGroups)) {
      final List<String> tokens = _termTokens(
        term,
        maxTokens: maxTokensPerGroup,
      );
      final String g = _formatTokenGroup(tokens);
      if (g.isNotEmpty) clauses.add(g);
    }

    // phrases: AND phrases
    for (final String phrase in phrases.take(maxGroups)) {
      final String p = _cleanPhraseText(phrase);
      if (p.isEmpty) continue;
      clauses.add('"$p"');
    }

    // near: AND NEAR clauses
    for (final AdvancedSearchNearClause n in near.take(maxNearClauses)) {
      final List<String> toks = <String>[];
      for (final String term in n.terms) {
        toks.addAll(_termTokens(term, maxTokens: maxTokensPerGroup));
        if (toks.length >= (maxTokensPerGroup * 3)) break;
      }
      final List<String> formatted = <String>[];
      for (final t in toks) {
        final String f = _formatToken(t);
        if (f.isNotEmpty) formatted.add(f);
      }
      if (formatted.isEmpty) continue;
      final int? dist0 = n.distance;
      final int? dist = (dist0 == null) ? null : dist0.clamp(1, 50);
      final String inside = formatted.join(' ');
      clauses.add(dist == null ? 'NEAR($inside)' : 'NEAR($inside, $dist)');
    }

    // any: OR groups
    final List<String> anyGroups = <String>[];
    for (final String term in any.take(maxGroups)) {
      final List<String> tokens = _termTokens(
        term,
        maxTokens: maxTokensPerGroup,
      );
      final String g = _formatTokenGroup(tokens);
      if (g.isNotEmpty) anyGroups.add(g);
    }
    if (anyGroups.isNotEmpty) {
      clauses.add(
        anyGroups.length == 1
            ? anyGroups.single
            : '(${anyGroups.join(' OR ')})',
      );
    }

    // phrases_any: OR phrases
    final List<String> anyPhrases = <String>[];
    for (final String phrase in phrasesAny.take(maxGroups)) {
      final String p = _cleanPhraseText(phrase);
      if (p.isEmpty) continue;
      anyPhrases.add('"$p"');
    }
    if (anyPhrases.isNotEmpty) {
      clauses.add(
        anyPhrases.length == 1
            ? anyPhrases.single
            : '(${anyPhrases.join(' OR ')})',
      );
    }

    if (clauses.isEmpty) return '';
    final String positive = (clauses.length == 1)
        ? clauses.single
        : '(${clauses.join(' AND ')})';

    // must_not: binary NOT (positive NOT negative)
    final List<String> notGroups = <String>[];
    for (final String term in mustNot.take(maxNotGroups)) {
      final List<String> tokens = _termTokens(
        term,
        maxTokens: maxTokensPerGroup,
      );
      final String g = _formatTokenGroup(tokens);
      if (g.isNotEmpty) notGroups.add(g);
    }
    if (notGroups.isEmpty) return positive;

    final String negative = (notGroups.length == 1)
        ? notGroups.single
        : '(${notGroups.join(' OR ')})';
    return '$positive NOT $negative';
  }

  AdvancedSearchLikeQuery toLikeSpec({
    int maxGroups = 12,
    int maxTokensPerGroup = 6,
    int maxNotGroups = 8,
    int maxNearClauses = 6,
  }) {
    List<List<String>> buildGroups(List<String> src, int limit) {
      final List<List<String>> out = <List<String>>[];
      for (final String term in src.take(limit)) {
        final List<String> tokens = _termTokens(
          term,
          maxTokens: maxTokensPerGroup,
        );
        if (tokens.isEmpty) continue;
        out.add(tokens);
      }
      return out;
    }

    final List<List<String>> mustGroups = <List<String>>[
      ...buildGroups(must, maxGroups),
    ];
    // Near is approximated as an AND of its tokens for LIKE fallback.
    for (final AdvancedSearchNearClause n in near.take(maxNearClauses)) {
      final List<String> toks = <String>[];
      for (final String term in n.terms) {
        toks.addAll(_termTokens(term, maxTokens: maxTokensPerGroup));
        if (toks.length >= (maxTokensPerGroup * 3)) break;
      }
      if (toks.isNotEmpty) mustGroups.add(toks);
    }

    return AdvancedSearchLikeQuery(
      mustGroups: mustGroups,
      anyGroups: buildGroups(any, maxGroups),
      notGroups: buildGroups(mustNot, maxNotGroups),
      mustPhrases: phrases
          .take(maxGroups)
          .map(_cleanPhraseText)
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
      anyPhrases: phrasesAny
          .take(maxGroups)
          .map(_cleanPhraseText)
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class AdvancedSearchNearClause {
  const AdvancedSearchNearClause({required this.terms, this.distance});

  final List<String> terms;
  final int? distance;
}

class AdvancedSearchLikeQuery {
  const AdvancedSearchLikeQuery({
    required this.mustGroups,
    required this.anyGroups,
    required this.notGroups,
    required this.mustPhrases,
    required this.anyPhrases,
  });

  final List<List<String>> mustGroups;
  final List<List<String>> anyGroups;
  final List<List<String>> notGroups;
  final List<String> mustPhrases;
  final List<String> anyPhrases;

  bool get isEmptyPositive =>
      mustGroups.isEmpty &&
      anyGroups.isEmpty &&
      mustPhrases.isEmpty &&
      anyPhrases.isEmpty;
}

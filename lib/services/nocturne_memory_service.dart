import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'screenshot_database.dart';

class NocturneUri {
  const NocturneUri({required this.domain, required this.path});

  final String domain;
  final String path;

  String get uri => path.isEmpty ? '$domain://' : '$domain://$path';
}

class NocturneMemoryService {
  NocturneMemoryService._internal();
  static final NocturneMemoryService instance = NocturneMemoryService._internal();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  static final RegExp _domainRe = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
  static final RegExp _titleRe = RegExp(r'^[a-z0-9_-]+$');

  NocturneUri parseUri(String uri) {
    final String u = uri.trim();
    final int idx = u.indexOf('://');
    if (idx <= 0) {
      // Legacy fallback: treat as core://<path>
      final String p = u.replaceAll(RegExp(r'^/+|/+$'), '');
      return NocturneUri(domain: 'core', path: p);
    }
    final String domain = u.substring(0, idx).trim().toLowerCase();
    final String path = u.substring(idx + 3).trim().replaceAll(
          RegExp(r'^/+|/+$'),
          '',
        );
    if (domain.isEmpty || !_domainRe.hasMatch(domain)) {
      throw ArgumentError('invalid domain in uri: $uri');
    }
    return NocturneUri(domain: domain, path: path);
  }

  String makeUri(String domain, String path) {
    final String d = domain.trim().toLowerCase();
    final String p = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return p.isEmpty ? '$d://' : '$d://$p';
  }

  // ---------------------------------------------------------------------------
  // Read APIs
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> readMemory(String uri) async {
    final NocturneUri parsed = parseUri(uri);

    if (parsed.domain == 'system') {
      return _readSystem(parsed.path);
    }

    final Database db = await _db.database;
    final String domain = parsed.domain;
    final String path = parsed.path;

    if (path.isEmpty) {
      final List<Map<String, dynamic>> children = await _getChildren(
        db,
        nodeUuid: nocturneRootNodeUuid,
        contextDomain: domain,
        contextPath: null,
      );
      return <String, dynamic>{
        'uri': makeUri(domain, ''),
        'domain': domain,
        'path': '',
        'node_uuid': nocturneRootNodeUuid,
        'memory_id': null,
        'content': null,
        'priority': null,
        'disclosure': null,
        'alias_count': 0,
        'children': children,
      };
    }

    final Map<String, dynamic>? row = await _getMemoryByPath(db, domain, path);
    if (row == null) {
      throw StateError("memory not found: ${makeUri(domain, path)}");
    }

    final String nodeUuid = (row['node_uuid'] ?? '').toString();
    final List<Map<String, dynamic>> children = await _getChildren(
      db,
      nodeUuid: nodeUuid,
      contextDomain: domain,
      contextPath: path,
    );

    return <String, dynamic>{...row, 'children': children};
  }

  Future<List<Map<String, dynamic>>> searchMemory(
    String query, {
    String? domain,
    int limit = 10,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return <Map<String, dynamic>>[];
    limit = limit.clamp(1, 100);

    final Database db = await _db.database;
    final String likeLiteral = _escapeLikeLiteral(q);
    final String pat = '%$likeLiteral%';

    final List<Object?> args = <Object?>[pat, pat];
    final StringBuffer where = StringBuffer(
      '(p.path LIKE ? ESCAPE \'\\\' OR m.content LIKE ? ESCAPE \'\\\')',
    );
    if (domain != null && domain.trim().isNotEmpty) {
      where.write(' AND p.domain = ?');
      args.add(domain.trim().toLowerCase());
    }
    args.add(limit);

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        m.id AS memory_id,
        e.child_uuid AS node_uuid,
        m.content AS content,
        m.created_at AS created_at,
        e.priority AS priority,
        e.disclosure AS disclosure,
        p.domain AS domain,
        p.path AS path
      FROM paths p
      JOIN edges e ON p.edge_id = e.id
      JOIN memories m ON m.node_uuid = e.child_uuid AND m.deprecated = 0
      WHERE ${where.toString()}
      ORDER BY e.priority ASC, m.created_at DESC
      LIMIT ?
      ''',
      args,
    );

    final Set<int> seenMemoryIds = <int>{};
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Map<String, Object?> r in rows) {
      final int id = _toInt(r['memory_id']);
      if (id <= 0 || seenMemoryIds.contains(id)) continue;
      seenMemoryIds.add(id);
      final String d = (r['domain'] ?? '').toString();
      final String p = (r['path'] ?? '').toString();
      out.add(<String, dynamic>{
        'memory_id': id,
        'uri': makeUri(d, p),
        'domain': d,
        'path': p,
        'node_uuid': (r['node_uuid'] ?? '').toString(),
        'priority': _toInt(r['priority']),
        'disclosure': (r['disclosure'] as String?)?.trim().isEmpty ?? true
            ? null
            : (r['disclosure'] as String),
        'created_at': _toInt(r['created_at']),
        'content_snippet': _snippet((r['content'] ?? '').toString(), q),
      });
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> getAllPaths({String? domain}) async {
    final Database db = await _db.database;
    final List<Object?> args = <Object?>[];
    final StringBuffer where = StringBuffer();
    if (domain != null && domain.trim().isNotEmpty) {
      where.write('WHERE p.domain = ?');
      args.add(domain.trim().toLowerCase());
    }

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        p.domain AS domain,
        p.path AS path,
        e.priority AS priority,
        m.id AS memory_id,
        e.child_uuid AS node_uuid
      FROM paths p
      JOIN edges e ON p.edge_id = e.id
      JOIN memories m ON m.node_uuid = e.child_uuid AND m.deprecated = 0
      ${where.toString()}
      ORDER BY p.domain ASC, p.path ASC
      ''',
      args,
    );

    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final String d = (r['domain'] ?? '').toString();
      final String p = (r['path'] ?? '').toString();
      out.add(<String, dynamic>{
        'domain': d,
        'path': p,
        'uri': makeUri(d, p),
        'name': p.contains('/') ? p.split('/').last : p,
        'priority': _toInt(r['priority']),
        'memory_id': _toInt(r['memory_id']),
        'node_uuid': (r['node_uuid'] ?? '').toString(),
      });
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> getRecentMemories({int limit = 10}) async {
    limit = limit.clamp(1, 100);
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        m.id AS memory_id,
        m.created_at AS created_at,
        e.priority AS priority,
        e.disclosure AS disclosure,
        p.domain AS domain,
        p.path AS path
      FROM paths p
      JOIN edges e ON p.edge_id = e.id
      JOIN memories m ON m.node_uuid = e.child_uuid AND m.deprecated = 0
      ORDER BY m.created_at DESC
      ''',
    );

    final Set<int> seen = <int>{};
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final int id = _toInt(r['memory_id']);
      if (id <= 0 || seen.contains(id)) continue;
      seen.add(id);
      final String d = (r['domain'] ?? '').toString();
      final String p = (r['path'] ?? '').toString();
      out.add(<String, dynamic>{
        'memory_id': id,
        'uri': makeUri(d, p),
        'priority': _toInt(r['priority']),
        'disclosure': (r['disclosure'] as String?)?.trim().isEmpty ?? true
            ? null
            : (r['disclosure'] as String),
        'created_at': _toInt(r['created_at']),
      });
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Write APIs
  // ---------------------------------------------------------------------------

  /// Clear all Nocturne-memory tables and reset the sentinel root node.
  ///
  /// This is used by the “一键重建” flow. It does NOT touch other app tables.
  Future<void> resetAll() async {
    final Database db = await _db.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('paths');
      await txn.delete('edges');
      await txn.delete('memories');
      await txn.delete(
        'nodes',
        where: 'uuid <> ?',
        whereArgs: <Object?>[nocturneRootNodeUuid],
      );
      try {
        await txn.insert(
          'nodes',
          <String, Object?>{'uuid': nocturneRootNodeUuid, 'created_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (_) {}
    });
  }

  Future<Map<String, dynamic>> createMemory({
    required String parentUri,
    required String content,
    required int priority,
    String? title,
    String? disclosure,
  }) async {
    final NocturneUri parent = parseUri(parentUri);
    if (parent.domain == 'system') {
      throw ArgumentError('cannot create under system://');
    }
    final String domain = parent.domain;
    final String parentPath = parent.path;

    if (title != null && title.trim().isNotEmpty) {
      final String t = title.trim();
      if (!_titleRe.hasMatch(t)) {
        throw ArgumentError(
          'invalid title: only [a-z0-9_-] allowed (no spaces, slashes, or uppercase)',
        );
      }
      title = t;
    } else {
      title = null;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await _db.database;

    return db.transaction((txn) async {
      final String parentUuid = parentPath.isEmpty
          ? nocturneRootNodeUuid
          : await _requireNodeUuidByPath(txn, domain, parentPath);

      final String finalPath;
      if (title != null) {
        finalPath = parentPath.isEmpty ? title : '$parentPath/$title';
      } else {
        final int nextNum = await _getNextChildNumber(txn, parentUuid);
        finalPath = parentPath.isEmpty ? '$nextNum' : '$parentPath/$nextNum';
      }

      final bool exists = await _pathExists(txn, domain, finalPath);
      if (exists) {
        throw StateError("path already exists: ${makeUri(domain, finalPath)}");
      }

      final String nodeUuid = _uuidV4();
      await txn.insert('nodes', <String, Object?>{
        'uuid': nodeUuid,
        'created_at': now,
      });
      final int memoryId = await txn.insert('memories', <String, Object?>{
        'node_uuid': nodeUuid,
        'content': content,
        'deprecated': 0,
        'created_at': now,
      });

      final String edgeName = title ?? finalPath.split('/').last;
      final int edgeId = await txn.insert('edges', <String, Object?>{
        'parent_uuid': parentUuid,
        'child_uuid': nodeUuid,
        'name': edgeName,
        'priority': priority,
        'disclosure': (disclosure ?? '').trim().isEmpty ? null : disclosure,
        'created_at': now,
      });

      await txn.insert('paths', <String, Object?>{
        'domain': domain,
        'path': finalPath,
        'edge_id': edgeId,
        'created_at': now,
      });

      return <String, dynamic>{
        'uri': makeUri(domain, finalPath),
        'domain': domain,
        'path': finalPath,
        'node_uuid': nodeUuid,
        'memory_id': memoryId,
        'edge_id': edgeId,
        'priority': priority,
      };
    });
  }

  Future<Map<String, dynamic>> updateMemory({
    required String uri,
    String? oldString,
    String? newString,
    String? append,
    int? priority,
    String? disclosure,
  }) async {
    final NocturneUri u = parseUri(uri);
    if (u.domain == 'system') {
      throw ArgumentError('system:// is read-only');
    }
    if (u.path.isEmpty) {
      throw ArgumentError('cannot update domain root');
    }

    final bool hasPatch = (oldString != null || newString != null);
    final bool hasAppend = append != null;
    if (hasPatch && hasAppend) {
      throw ArgumentError('patch mode and append mode are mutually exclusive');
    }
    if (hasPatch) {
      if ((oldString ?? '').isEmpty || newString == null) {
        throw ArgumentError('patch mode requires old_string and new_string');
      }
    }
    if (!hasPatch && !hasAppend && priority == null && disclosure == null) {
      throw ArgumentError('no update fields provided');
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await _db.database;

    return db.transaction((txn) async {
      final Map<String, dynamic> resolved = await _requireResolvedPath(
        txn,
        domain: u.domain,
        path: u.path,
      );

      final int edgeId = resolved['edge_id'] as int;
      final String nodeUuid = resolved['node_uuid'] as String;
      final int oldMemoryId = resolved['memory_id'] as int;
      final String oldContent = resolved['content'] as String;

      if (priority != null || disclosure != null) {
        final Map<String, Object?> updates = <String, Object?>{};
        if (priority != null) updates['priority'] = priority;
        if (disclosure != null) {
          updates['disclosure'] = disclosure.trim().isEmpty ? null : disclosure;
        }
        if (updates.isNotEmpty) {
          await txn.update(
            'edges',
            updates,
            where: 'id = ?',
            whereArgs: <Object?>[edgeId],
          );
        }
      }

      int newMemoryId = oldMemoryId;
      if (hasPatch || hasAppend) {
        final String newContent;
        if (hasPatch) {
          final String os = oldString!;
          final int first = oldContent.indexOf(os);
          if (first < 0) {
            throw StateError('old_string not found in memory content');
          }
          final int second = oldContent.indexOf(os, first + os.length);
          if (second >= 0) {
            throw StateError('old_string matches multiple locations; must be unique');
          }
          newContent = oldContent.replaceFirst(os, newString ?? '');
        } else {
          newContent = oldContent + (append ?? '');
        }

        newMemoryId = await txn.insert('memories', <String, Object?>{
          'node_uuid': nodeUuid,
          'content': newContent,
          'deprecated': 1, // temporary; will be activated after deprecation
          'created_at': now,
        });

        await txn.update(
          'memories',
          <String, Object?>{'deprecated': 1, 'migrated_to': newMemoryId},
          where: 'node_uuid = ? AND deprecated = 0 AND id != ?',
          whereArgs: <Object?>[nodeUuid, newMemoryId],
        );

        await txn.update(
          'memories',
          <String, Object?>{'deprecated': 0, 'migrated_to': null},
          where: 'id = ?',
          whereArgs: <Object?>[newMemoryId],
        );
      }

      return <String, dynamic>{
        'uri': makeUri(u.domain, u.path),
        'domain': u.domain,
        'path': u.path,
        'node_uuid': nodeUuid,
        'old_memory_id': oldMemoryId,
        'new_memory_id': newMemoryId,
      };
    });
  }

  Future<Map<String, dynamic>> addAlias({
    required String newUri,
    required String targetUri,
    int priority = 0,
    String? disclosure,
  }) async {
    final NocturneUri n = parseUri(newUri);
    final NocturneUri t = parseUri(targetUri);
    if (n.domain == 'system' || t.domain == 'system') {
      throw ArgumentError('system:// does not support aliases');
    }
    if (n.path.isEmpty) {
      throw ArgumentError('new_uri must include a non-empty path');
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await _db.database;

    return db.transaction((txn) async {
      final String targetNodeUuid =
          await _requireNodeUuidByPath(txn, t.domain, t.path);

      final String parentUuid;
      if (n.path.contains('/')) {
        final int cut = n.path.lastIndexOf('/');
        final String parentPath = cut > 0 ? n.path.substring(0, cut) : '';
        parentUuid = await _requireNodeUuidByPath(txn, n.domain, parentPath);
      } else {
        parentUuid = nocturneRootNodeUuid;
      }

      final bool exists = await _pathExists(txn, n.domain, n.path);
      if (exists) {
        throw StateError("path already exists: ${makeUri(n.domain, n.path)}");
      }

      final bool wouldCycle = await _wouldCreateCycle(
        txn,
        parentUuid: parentUuid,
        childUuid: targetNodeUuid,
      );
      if (wouldCycle) {
        throw StateError(
          'cannot create alias: would create a cycle in the memory graph',
        );
      }

      final String edgeName = n.path.split('/').last;
      final Map<String, dynamic> edgeRes = await _getOrCreateEdge(
        txn,
        parentUuid: parentUuid,
        childUuid: targetNodeUuid,
        name: edgeName,
        priority: priority,
        disclosure: disclosure,
        now: now,
      );
      final int edgeId = edgeRes['edge_id'] as int;
      final bool edgeCreated = edgeRes['created'] as bool;

      await txn.insert('paths', <String, Object?>{
        'domain': n.domain,
        'path': n.path,
        'edge_id': edgeId,
        'created_at': now,
      });

      await _cascadeCreatePaths(
        txn,
        nodeUuid: targetNodeUuid,
        domain: n.domain,
        basePath: n.path,
        visited: <String>{},
      );

      return <String, dynamic>{
        'new_uri': makeUri(n.domain, n.path),
        'target_uri': makeUri(t.domain, t.path),
        'node_uuid': targetNodeUuid,
        'edge_id': edgeId,
        'edge_created': edgeCreated,
      };
    });
  }

  Future<Map<String, dynamic>> deleteMemory({required String uri}) async {
    final NocturneUri u = parseUri(uri);
    if (u.domain == 'system') {
      throw ArgumentError('system:// is read-only');
    }
    if (u.path.isEmpty) {
      throw ArgumentError('cannot delete domain root');
    }

    final Database db = await _db.database;
    return db.transaction((txn) async {
      final Map<String, dynamic> resolved = await _requireResolvedPath(
        txn,
        domain: u.domain,
        path: u.path,
      );
      final int edgeId = resolved['edge_id'] as int;
      final String nodeUuid = resolved['node_uuid'] as String;

      final List<Map<String, Object?>> childEdges = await txn.query(
        'edges',
        columns: <String>['id', 'child_uuid', 'name'],
        where: 'parent_uuid = ?',
        whereArgs: <Object?>[nodeUuid],
      );

      final List<Map<String, Object?>> wouldOrphan = <Map<String, Object?>>[];
      for (final e in childEdges) {
        final String child = (e['child_uuid'] ?? '').toString();
        final int surviving = await _countIncomingPaths(
          txn,
          nodeUuid: child,
          excludeDomain: u.domain,
          excludePathPrefix: u.path,
        );
        if (surviving <= 0) wouldOrphan.add(e);
      }

      if (wouldOrphan.isNotEmpty) {
        final String details = wouldOrphan
            .map((e) => (e['name'] ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
        throw StateError(
          'cannot delete: would orphan child node(s): $details. Create an alias path for those children first.',
        );
      }

      final int deletedPaths = await _deleteSubtreePaths(
        txn,
        domain: u.domain,
        pathPrefix: u.path,
      );

      await _gcEdgeIfPathless(txn, edgeId: edgeId);
      await _gcNodeSoft(txn, nodeUuid: nodeUuid);

      return <String, dynamic>{
        'uri': makeUri(u.domain, u.path),
        'domain': u.domain,
        'path': u.path,
        'deleted_paths': deletedPaths,
      };
    });
  }

  // ---------------------------------------------------------------------------
  // System URIs
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _readSystem(String path) async {
    final String p = path.trim().toLowerCase();

    if (p == 'boot') {
      // ScreenMemo has no .env; keep this configurable via user_settings key.
      // Default to the canonical Nocturne anchors.
      final List<String> defaultUris = const <String>[
        'core://agent',
        'core://my_user',
        'core://agent/my_user',
      ];
      final List<String> uris = await _loadBootUrisFallback(defaultUris);
      final List<Map<String, dynamic>> memories = <Map<String, dynamic>>[];
      final List<String> missing = <String>[];
      for (final u in uris) {
        try {
          memories.add(await readMemory(u));
        } catch (_) {
          missing.add(u);
        }
      }
      return <String, dynamic>{
        'uri': 'system://boot',
        'core_memory_uris': uris,
        'memories': memories,
        'missing': missing,
      };
    }

    if (p == 'index' || p.startsWith('index/')) {
      final String? domainFilter = p == 'index'
          ? null
          : p.substring('index/'.length).trim().isEmpty
              ? null
              : p.substring('index/'.length).trim();
      final List<Map<String, dynamic>> items =
          await getAllPaths(domain: domainFilter);
      return <String, dynamic>{
        'uri': domainFilter == null ? 'system://index' : 'system://index/$domainFilter',
        'domain_filter': domainFilter,
        'count': items.length,
        'items': items,
      };
    }

    if (p == 'recent' || p.startsWith('recent/')) {
      int limit = 10;
      if (p.startsWith('recent/')) {
        final String suf = p.substring('recent/'.length).trim();
        final int? n = int.tryParse(suf);
        if (n != null) limit = n;
      }
      limit = limit.clamp(1, 100);
      final List<Map<String, dynamic>> items =
          await getRecentMemories(limit: limit);
      return <String, dynamic>{
        'uri': p == 'recent' ? 'system://recent' : 'system://recent/$limit',
        'count': items.length,
        'items': items,
      };
    }

    throw ArgumentError('unknown system uri: system://$path');
  }

  Future<List<String>> _loadBootUrisFallback(List<String> fallback) async {
    try {
      final Database db = await _db.database;
      final List<Map<String, Object?>> rows = await db.query(
        'user_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>['nocturne_core_memory_uris'],
        limit: 1,
      );
      if (rows.isEmpty) return fallback;
      final String raw = (rows.first['value'] ?? '').toString();
      final List<String> parts = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return parts.isEmpty ? fallback : parts;
    } catch (_) {
      return fallback;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers (SQL)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _getMemoryByPath(
    DatabaseExecutor db,
    String domain,
    String path,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        m.id AS memory_id,
        e.child_uuid AS node_uuid,
        m.content AS content,
        m.created_at AS created_at,
        e.priority AS priority,
        e.disclosure AS disclosure,
        p.domain AS domain,
        p.path AS path
      FROM paths p
      JOIN edges e ON p.edge_id = e.id
      JOIN memories m ON m.node_uuid = e.child_uuid AND m.deprecated = 0
      WHERE p.domain = ? AND p.path = ?
      ORDER BY m.created_at DESC, m.id DESC
      LIMIT 1
      ''',
      <Object?>[domain, path],
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> r = rows.first;

    final String nodeUuid = (r['node_uuid'] ?? '').toString();
    final int incomingPaths = await _countIncomingPaths(
      db,
      nodeUuid: nodeUuid,
      excludeDomain: null,
      excludePathPrefix: null,
    );
    final int aliasCount = max(0, incomingPaths - 1);

    return <String, dynamic>{
      'uri': makeUri((r['domain'] ?? '').toString(), (r['path'] ?? '').toString()),
      'domain': (r['domain'] ?? '').toString(),
      'path': (r['path'] ?? '').toString(),
      'node_uuid': nodeUuid,
      'memory_id': _toInt(r['memory_id']),
      'content': (r['content'] ?? '').toString(),
      'created_at': _toInt(r['created_at']),
      'priority': _toInt(r['priority']),
      'disclosure': (r['disclosure'] as String?)?.trim().isEmpty ?? true
          ? null
          : (r['disclosure'] as String),
      'alias_count': aliasCount,
    };
  }

  Future<Map<String, dynamic>?> _resolvePath(
    DatabaseExecutor db, {
    required String domain,
    required String path,
  }) async {
    if (path.isEmpty) {
      return <String, dynamic>{
        'domain': domain,
        'path': '',
        'edge_id': null,
        'node_uuid': nocturneRootNodeUuid,
      };
    }
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        e.id AS edge_id,
        e.parent_uuid AS parent_uuid,
        e.child_uuid AS child_uuid,
        e.name AS name
      FROM paths p
      JOIN edges e ON p.edge_id = e.id
      WHERE p.domain = ? AND p.path = ?
      LIMIT 1
      ''',
      <Object?>[domain, path],
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> r = rows.first;
    return <String, dynamic>{
      'domain': domain,
      'path': path,
      'edge_id': _toInt(r['edge_id']),
      'parent_uuid': (r['parent_uuid'] ?? '').toString(),
      'node_uuid': (r['child_uuid'] ?? '').toString(),
      'name': (r['name'] ?? '').toString(),
    };
  }

  Future<String> _requireNodeUuidByPath(
    DatabaseExecutor db,
    String domain,
    String path,
  ) async {
    if (path.isEmpty) return nocturneRootNodeUuid;
    final Map<String, dynamic>? res = await _resolvePath(
      db,
      domain: domain,
      path: path,
    );
    if (res == null) {
      throw StateError("path not found: ${makeUri(domain, path)}");
    }
    final String uuid = (res['node_uuid'] ?? '').toString();
    if (uuid.trim().isEmpty) {
      throw StateError("invalid node_uuid for: ${makeUri(domain, path)}");
    }
    return uuid;
  }

  Future<Map<String, dynamic>> _requireResolvedPath(
    DatabaseExecutor db, {
    required String domain,
    required String path,
  }) async {
    final Map<String, dynamic>? row = await _getMemoryByPath(db, domain, path);
    if (row == null) {
      throw StateError("memory not found: ${makeUri(domain, path)}");
    }

    final List<Map<String, Object?>> edgeRows = await db.rawQuery(
      '''
      SELECT e.id AS edge_id
      FROM paths p
      JOIN edges e ON p.edge_id = e.id
      WHERE p.domain = ? AND p.path = ?
      LIMIT 1
      ''',
      <Object?>[domain, path],
    );
    if (edgeRows.isEmpty) {
      throw StateError("edge not found for: ${makeUri(domain, path)}");
    }

    return <String, dynamic>{
      'edge_id': _toInt(edgeRows.first['edge_id']),
      'node_uuid': (row['node_uuid'] ?? '').toString(),
      'memory_id': _toInt(row['memory_id']),
      'content': (row['content'] ?? '').toString(),
    };
  }

  Future<List<Map<String, dynamic>>> _getChildren(
    DatabaseExecutor db, {
    required String nodeUuid,
    String? contextDomain,
    String? contextPath,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        e.id AS edge_id,
        e.child_uuid AS node_uuid,
        e.name AS name,
        e.priority AS priority,
        e.disclosure AS disclosure,
        m.content AS content
      FROM edges e
      JOIN memories m ON m.node_uuid = e.child_uuid AND m.deprecated = 0
      WHERE e.parent_uuid = ?
      ORDER BY e.priority ASC, e.name ASC
      ''',
      <Object?>[nodeUuid],
    );

    if (rows.isEmpty) return <Map<String, dynamic>>[];

    final List<int> edgeIds = <int>[];
    final Set<String> childUuids = <String>{};
    for (final r in rows) {
      final int eid = _toInt(r['edge_id']);
      if (eid > 0) edgeIds.add(eid);
      final String cu = (r['node_uuid'] ?? '').toString();
      if (cu.trim().isNotEmpty) childUuids.add(cu);
    }

    final Map<int, List<Map<String, String>>> pathsByEdge =
        await _fetchPathsByEdgeIds(db, edgeIds);
    final Map<String, int> approxChildrenCount =
        await _countChildrenByParentUuids(db, childUuids.toList());

    final String? prefix =
        (contextPath != null && contextPath.trim().isNotEmpty)
            ? '${contextPath.trim()}/'
            : null;
    final String? dom =
        (contextDomain != null && contextDomain.trim().isNotEmpty)
            ? contextDomain.trim().toLowerCase()
            : null;

    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final int edgeId = _toInt(r['edge_id']);
      final String child = (r['node_uuid'] ?? '').toString();
      final List<Map<String, String>> paths = pathsByEdge[edgeId] ?? const [];

      final Map<String, String>? best = _pickBestPath(paths, dom, prefix);
      final String bestDomain = best?['domain'] ?? (dom ?? 'core');
      final String bestPath = best?['path'] ?? (r['name'] ?? '').toString();

      final String content = (r['content'] ?? '').toString();
      final String snippet =
          content.length > 100 ? '${content.substring(0, 100)}...' : content;

      out.add(<String, dynamic>{
        'node_uuid': child,
        'edge_id': edgeId,
        'name': (r['name'] ?? '').toString(),
        'domain': bestDomain,
        'path': bestPath,
        'uri': makeUri(bestDomain, bestPath),
        'content_snippet': snippet,
        'priority': _toInt(r['priority']),
        'disclosure': (r['disclosure'] as String?)?.trim().isEmpty ?? true
            ? null
            : (r['disclosure'] as String),
        'approx_children_count': approxChildrenCount[child] ?? 0,
      });
    }
    return out;
  }

  Map<String, String>? _pickBestPath(
    List<Map<String, String>> paths,
    String? contextDomain,
    String? prefix,
  ) {
    if (paths.isEmpty) return null;
    if (paths.length == 1) return paths.first;

    if (contextDomain != null && prefix != null) {
      for (final p in paths) {
        if (p['domain'] == contextDomain &&
            (p['path'] ?? '').startsWith(prefix)) {
          return p;
        }
      }
    }

    if (contextDomain != null) {
      for (final p in paths) {
        if (p['domain'] == contextDomain) return p;
      }
    }

    return paths.first;
  }

  Future<Map<int, List<Map<String, String>>>> _fetchPathsByEdgeIds(
    DatabaseExecutor db,
    List<int> edgeIds,
  ) async {
    if (edgeIds.isEmpty) return <int, List<Map<String, String>>>{};
    final List<int> uniq = <int>{...edgeIds}.toList();
    final List<String> qs = List<String>.filled(uniq.length, '?');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT domain, path, edge_id FROM paths WHERE edge_id IN (${qs.join(',')})',
      uniq,
    );
    final Map<int, List<Map<String, String>>> out =
        <int, List<Map<String, String>>>{};
    for (final r in rows) {
      final int id = _toInt(r['edge_id']);
      out.putIfAbsent(id, () => <Map<String, String>>[]).add(<String, String>{
        'domain': (r['domain'] ?? '').toString(),
        'path': (r['path'] ?? '').toString(),
      });
    }
    return out;
  }

  Future<Map<String, int>> _countChildrenByParentUuids(
    DatabaseExecutor db,
    List<String> parentUuids,
  ) async {
    if (parentUuids.isEmpty) return <String, int>{};
    final List<String> uniq = <String>{...parentUuids}.toList();
    final List<String> qs = List<String>.filled(uniq.length, '?');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT parent_uuid, COUNT(id) AS cnt
      FROM edges
      WHERE parent_uuid IN (${qs.join(',')})
      GROUP BY parent_uuid
      ''',
      uniq,
    );
    final Map<String, int> out = <String, int>{};
    for (final r in rows) {
      out[(r['parent_uuid'] ?? '').toString()] = _toInt(r['cnt']);
    }
    return out;
  }

  Future<bool> _pathExists(
    DatabaseExecutor db,
    String domain,
    String path,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'paths',
      columns: const <String>['domain'],
      where: 'domain = ? AND path = ?',
      whereArgs: <Object?>[domain, path],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> _getNextChildNumber(DatabaseExecutor db, String parentUuid) async {
    final List<Map<String, Object?>> rows = await db.query(
      'edges',
      columns: const <String>['name'],
      where: 'parent_uuid = ?',
      whereArgs: <Object?>[parentUuid],
    );
    int maxNum = 0;
    for (final r in rows) {
      final String name = (r['name'] ?? '').toString();
      final int? n = int.tryParse(name);
      if (n != null) maxNum = max(maxNum, n);
    }
    return maxNum + 1;
  }

  Future<Map<String, dynamic>> _getOrCreateEdge(
    DatabaseExecutor db, {
    required String parentUuid,
    required String childUuid,
    required String name,
    required int priority,
    required String? disclosure,
    required int now,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'edges',
      columns: const <String>['id'],
      where: 'parent_uuid = ? AND child_uuid = ?',
      whereArgs: <Object?>[parentUuid, childUuid],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return <String, dynamic>{
        'edge_id': _toInt(rows.first['id']),
        'created': false,
      };
    }
    final int edgeId = await db.insert('edges', <String, Object?>{
      'parent_uuid': parentUuid,
      'child_uuid': childUuid,
      'name': name,
      'priority': priority,
      'disclosure': (disclosure ?? '').trim().isEmpty ? null : disclosure,
      'created_at': now,
    });
    return <String, dynamic>{'edge_id': edgeId, 'created': true};
  }

  Future<void> _cascadeCreatePaths(
    DatabaseExecutor db, {
    required String nodeUuid,
    required String domain,
    required String basePath,
    required Set<String> visited,
  }) async {
    if (visited.contains(nodeUuid)) return;
    visited.add(nodeUuid);
    try {
      final List<Map<String, Object?>> edges = await db.query(
        'edges',
        columns: const <String>['id', 'child_uuid', 'name'],
        where: 'parent_uuid = ?',
        whereArgs: <Object?>[nodeUuid],
      );
      for (final e in edges) {
        final String name = (e['name'] ?? '').toString();
        final int edgeId = _toInt(e['id']);
        if (edgeId <= 0 || name.trim().isEmpty) continue;
        final String child = (e['child_uuid'] ?? '').toString();

        final String childPath = basePath.isEmpty ? name : '$basePath/$name';
        final bool exists = await _pathExists(db, domain, childPath);
        if (!exists) {
          await db.insert('paths', <String, Object?>{
            'domain': domain,
            'path': childPath,
            'edge_id': edgeId,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
        }

        await _cascadeCreatePaths(
          db,
          nodeUuid: child,
          domain: domain,
          basePath: childPath,
          visited: visited,
        );
      }
    } finally {
      visited.remove(nodeUuid);
    }
  }

  Future<bool> _wouldCreateCycle(
    DatabaseExecutor db, {
    required String parentUuid,
    required String childUuid,
  }) async {
    if (parentUuid == nocturneRootNodeUuid) return false;
    if (parentUuid == childUuid) return true;

    final Set<String> visited = <String>{childUuid};
    final List<String> queue = <String>[childUuid];
    while (queue.isNotEmpty) {
      final String current = queue.removeAt(0);
      final List<Map<String, Object?>> rows = await db.query(
        'edges',
        columns: const <String>['child_uuid'],
        where: 'parent_uuid = ?',
        whereArgs: <Object?>[current],
      );
      for (final r in rows) {
        final String next = (r['child_uuid'] ?? '').toString();
        if (next == parentUuid) return true;
        if (next.trim().isEmpty) continue;
        if (!visited.contains(next)) {
          visited.add(next);
          queue.add(next);
        }
      }
    }
    return false;
  }

  Future<int> _countIncomingPaths(
    DatabaseExecutor db, {
    required String nodeUuid,
    required String? excludeDomain,
    required String? excludePathPrefix,
  }) async {
    final List<Object?> args = <Object?>[nodeUuid];
    final StringBuffer where = StringBuffer('e.child_uuid = ?');
    if (excludeDomain != null &&
        excludeDomain.trim().isNotEmpty &&
        excludePathPrefix != null &&
        excludePathPrefix.trim().isNotEmpty) {
      final String dom = excludeDomain.trim().toLowerCase();
      final String prefix = excludePathPrefix.trim();
      final String safe = _escapeLikeLiteral(prefix);
      final String like = '$safe/%';
      where.write(
        ' AND NOT (p.domain = ? AND (p.path = ? OR p.path LIKE ? ESCAPE \'\\\'))',
      );
      args.add(dom);
      args.add(prefix);
      args.add(like);
    }

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS cnt
      FROM paths p
      JOIN edges e ON p.edge_id = e.id
      WHERE ${where.toString()}
      ''',
      args,
    );
    if (rows.isEmpty) return 0;
    return _toInt(rows.first['cnt']);
  }

  Future<int> _deleteSubtreePaths(
    DatabaseExecutor db, {
    required String domain,
    required String pathPrefix,
  }) async {
    final String safe = _escapeLikeLiteral(pathPrefix);
    final String like = '$safe/%';
    return await db.delete(
      'paths',
      where: 'domain = ? AND (path = ? OR path LIKE ? ESCAPE \'\\\')',
      whereArgs: <Object?>[domain, pathPrefix, like],
    );
  }

  Future<void> _gcEdgeIfPathless(
    DatabaseExecutor db, {
    required int edgeId,
  }) async {
    if (edgeId <= 0) return;
    final List<Map<String, Object?>> rows = await db.query(
      'paths',
      columns: const <String>['domain'],
      where: 'edge_id = ?',
      whereArgs: <Object?>[edgeId],
      limit: 1,
    );
    if (rows.isNotEmpty) return;
    await db.delete('edges', where: 'id = ?', whereArgs: <Object?>[edgeId]);
  }

  Future<void> _cascadeDeleteEdge(
    DatabaseExecutor db, {
    required int edgeId,
  }) async {
    if (edgeId <= 0) return;
    final List<Map<String, Object?>> pathRows = await db.query(
      'paths',
      columns: const <String>['domain', 'path'],
      where: 'edge_id = ?',
      whereArgs: <Object?>[edgeId],
    );
    for (final p in pathRows) {
      final String dom = (p['domain'] ?? '').toString();
      final String path = (p['path'] ?? '').toString();
      if (dom.trim().isEmpty || path.trim().isEmpty) continue;
      await _deleteSubtreePaths(db, domain: dom, pathPrefix: path);
    }
    await db.delete('edges', where: 'id = ?', whereArgs: <Object?>[edgeId]);
  }

  Future<void> _gcNodeSoft(
    DatabaseExecutor db, {
    required String nodeUuid,
  }) async {
    if (nodeUuid == nocturneRootNodeUuid) return;
    final int incoming = await _countIncomingPaths(
      db,
      nodeUuid: nodeUuid,
      excludeDomain: null,
      excludePathPrefix: null,
    );
    if (incoming > 0) return;

    // Incoming edges should be pathless; delete them.
    final List<Map<String, Object?>> incomingEdges = await db.query(
      'edges',
      columns: const <String>['id'],
      where: 'child_uuid = ?',
      whereArgs: <Object?>[nodeUuid],
    );
    for (final e in incomingEdges) {
      final int id = _toInt(e['id']);
      if (id > 0) await _gcEdgeIfPathless(db, edgeId: id);
    }

    // Outgoing edges: remove their paths (all aliases) + edge rows.
    final List<Map<String, Object?>> outgoingEdges = await db.query(
      'edges',
      columns: const <String>['id'],
      where: 'parent_uuid = ?',
      whereArgs: <Object?>[nodeUuid],
    );
    for (final e in outgoingEdges) {
      final int id = _toInt(e['id']);
      if (id > 0) await _cascadeDeleteEdge(db, edgeId: id);
    }

    // Deprecate active memories for orphan nodes (keep content recoverable).
    await db.update(
      'memories',
      <String, Object?>{'deprecated': 1, 'migrated_to': null},
      where: 'node_uuid = ? AND deprecated = 0',
      whereArgs: <Object?>[nodeUuid],
    );
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static String _escapeLikeLiteral(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  static String _snippet(String content, String query) {
    if (content.isEmpty) return '';
    final String q = query.trim();
    if (q.isEmpty) {
      return content.length > 120 ? '${content.substring(0, 120)}...' : content;
    }
    final int pos = content.toLowerCase().indexOf(q.toLowerCase());
    if (pos < 0) {
      return content.length > 120 ? '${content.substring(0, 120)}...' : content;
    }
    final int start = max(0, pos - 30);
    final int end = min(content.length, pos + q.length + 30);
    final String mid = content.substring(start, end);
    final String prefix = start > 0 ? '...' : '';
    final String suffix = end < content.length ? '...' : '';
    return '$prefix$mid$suffix';
  }

  static String _uuidV4() {
    final Random rng = Random.secure();
    final List<int> b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10

    String hex(int i) => i.toRadixString(16).padLeft(2, '0');
    final String s = b.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}

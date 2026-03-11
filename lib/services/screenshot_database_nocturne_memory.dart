part of 'screenshot_database.dart';

/// Nocturne Memory schema (URI graph).
///
/// This mirrors the core architecture of `nocturne_memory`:
/// - Node: stable UUID (conceptual entity)
/// - Memory: content versions for a node (append-only; one active version)
/// - Edge: parent->child relationship (priority/disclosure bound to edge)
/// - Path: materialized URI routing cache (domain://path -> edge)
const String nocturneRootNodeUuid = '00000000-0000-0000-0000-000000000000';

extension ScreenshotDatabaseNocturneMemoryExt on ScreenshotDatabase {
  Future<void> _createNocturneMemoryTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nodes (
        uuid TEXT PRIMARY KEY,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_uuid TEXT,
        content TEXT NOT NULL,
        deprecated INTEGER NOT NULL DEFAULT 0,
        migrated_to INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        FOREIGN KEY(node_uuid) REFERENCES nodes(uuid)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memories_node_active ON memories(node_uuid, deprecated, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS edges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_uuid TEXT NOT NULL,
        child_uuid TEXT NOT NULL,
        name TEXT NOT NULL,
        priority INTEGER NOT NULL DEFAULT 0,
        disclosure TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        FOREIGN KEY(parent_uuid) REFERENCES nodes(uuid),
        FOREIGN KEY(child_uuid) REFERENCES nodes(uuid),
        UNIQUE(parent_uuid, child_uuid)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_edges_parent ON edges(parent_uuid, priority ASC, name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_edges_child ON edges(child_uuid)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS paths (
        domain TEXT NOT NULL,
        path TEXT NOT NULL,
        edge_id INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        PRIMARY KEY (domain, path),
        FOREIGN KEY(edge_id) REFERENCES edges(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_paths_edge ON paths(edge_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_paths_domain_path ON paths(domain, path)',
    );

    // Ensure the sentinel root node exists.
    try {
      await db.execute(
        'INSERT OR IGNORE INTO nodes(uuid) VALUES(?)',
        <Object?>[nocturneRootNodeUuid],
      );
    } catch (_) {}
  }
}


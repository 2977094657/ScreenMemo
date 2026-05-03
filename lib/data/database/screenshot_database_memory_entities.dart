part of 'screenshot_database.dart';

extension ScreenshotDatabaseMemoryEntitiesExt on ScreenshotDatabase {
  Future<void> _createMemoryEntityTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entities (
        entity_id TEXT PRIMARY KEY,
        root_uri TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        preferred_name TEXT NOT NULL,
        preferred_name_norm TEXT NOT NULL,
        canonical_key TEXT NOT NULL,
        display_uri TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'candidate',
        current_summary TEXT NOT NULL DEFAULT '',
        latest_content TEXT NOT NULL DEFAULT '',
        visual_signature_summary TEXT NOT NULL DEFAULT '',
        raw_score REAL NOT NULL DEFAULT 0,
        decayed_score REAL NOT NULL DEFAULT 0,
        activation_score REAL NOT NULL DEFAULT 0,
        evidence_count INTEGER NOT NULL DEFAULT 0,
        distinct_segment_count INTEGER NOT NULL DEFAULT 0,
        distinct_day_count INTEGER NOT NULL DEFAULT 0,
        strong_signal_count INTEGER NOT NULL DEFAULT 0,
        min_distinct_days INTEGER NOT NULL DEFAULT 1,
        allow_single_strong_activation INTEGER NOT NULL DEFAULT 0,
        allow_root_materialization INTEGER NOT NULL DEFAULT 0,
        evidence_satisfied INTEGER NOT NULL DEFAULT 0,
        ready_to_activate INTEGER NOT NULL DEFAULT 0,
        root_materialization_blocked INTEGER NOT NULL DEFAULT 0,
        missing_activation_score REAL NOT NULL DEFAULT 0,
        missing_distinct_days INTEGER NOT NULL DEFAULT 0,
        needs_review INTEGER NOT NULL DEFAULT 0,
        review_reason TEXT,
        lifecycle_status TEXT,
        first_seen_at INTEGER,
        last_seen_at INTEGER,
        activated_at INTEGER,
        archived_at INTEGER,
        last_materialized_at INTEGER,
        last_evidence_summary TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(root_uri, entity_type, canonical_key),
        UNIQUE(display_uri)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entities_root_status ON memory_entities(root_uri, status, decayed_score DESC, last_seen_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entities_type_norm ON memory_entities(root_uri, entity_type, preferred_name_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entities_status_seen ON memory_entities(status, last_seen_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_signal_profiles (
        entity_id TEXT PRIMARY KEY,
        root_uri TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        preferred_name TEXT NOT NULL,
        preferred_name_norm TEXT NOT NULL,
        canonical_key TEXT NOT NULL,
        uri TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'candidate',
        current_summary TEXT NOT NULL DEFAULT '',
        latest_content TEXT NOT NULL DEFAULT '',
        visual_signature_summary TEXT NOT NULL DEFAULT '',
        raw_score REAL NOT NULL DEFAULT 0,
        decayed_score REAL NOT NULL DEFAULT 0,
        activation_score REAL NOT NULL DEFAULT 0,
        evidence_count INTEGER NOT NULL DEFAULT 0,
        distinct_segment_count INTEGER NOT NULL DEFAULT 0,
        distinct_day_count INTEGER NOT NULL DEFAULT 0,
        strong_signal_count INTEGER NOT NULL DEFAULT 0,
        min_distinct_days INTEGER NOT NULL DEFAULT 1,
        allow_single_strong_activation INTEGER NOT NULL DEFAULT 0,
        allow_root_materialization INTEGER NOT NULL DEFAULT 0,
        evidence_satisfied INTEGER NOT NULL DEFAULT 0,
        ready_to_activate INTEGER NOT NULL DEFAULT 0,
        root_materialization_blocked INTEGER NOT NULL DEFAULT 0,
        missing_activation_score REAL NOT NULL DEFAULT 0,
        missing_distinct_days INTEGER NOT NULL DEFAULT 0,
        needs_review INTEGER NOT NULL DEFAULT 0,
        review_reason TEXT,
        lifecycle_status TEXT,
        first_seen_at INTEGER,
        last_seen_at INTEGER,
        activated_at INTEGER,
        archived_at INTEGER,
        last_materialized_at INTEGER,
        last_evidence_summary TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(uri)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_signal_profiles_root_status ON memory_signal_profiles(root_uri, status, decayed_score DESC, last_seen_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_signal_profiles_uri ON memory_signal_profiles(uri)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_signal_episodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_id TEXT NOT NULL,
        root_uri TEXT NOT NULL,
        uri TEXT NOT NULL,
        segment_id INTEGER NOT NULL,
        batch_index INTEGER NOT NULL DEFAULT 0,
        first_seen_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        score REAL NOT NULL DEFAULT 0,
        strong_signal INTEGER NOT NULL DEFAULT 0,
        action_kind TEXT NOT NULL DEFAULT '',
        evidence_summary TEXT,
        app_names_json TEXT,
        content_snapshot TEXT NOT NULL DEFAULT '',
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(entity_id, segment_id, batch_index)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_signal_episodes_entity_seen ON memory_signal_episodes(entity_id, last_seen_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_signal_episodes_root_seen ON memory_signal_episodes(root_uri, last_seen_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_id TEXT NOT NULL,
        alias TEXT NOT NULL,
        alias_text TEXT,
        alias_norm TEXT NOT NULL,
        alias_type TEXT NOT NULL DEFAULT 'semantic',
        source TEXT,
        confidence REAL NOT NULL DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(entity_id, alias_norm)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_aliases_norm ON memory_entity_aliases(alias_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_aliases_entity ON memory_entity_aliases(entity_id)',
    );
    try {
      await db.execute(
        'ALTER TABLE memory_entity_aliases ADD COLUMN alias_text TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE memory_entity_aliases ADD COLUMN alias_type TEXT NOT NULL DEFAULT 'semantic'",
      );
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_claims (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        claim_id TEXT,
        entity_id TEXT NOT NULL,
        fact_type TEXT NOT NULL,
        slot_key TEXT,
        value TEXT NOT NULL,
        value_text TEXT,
        value_norm TEXT NOT NULL,
        cardinality TEXT NOT NULL DEFAULT 'multi',
        status TEXT NOT NULL DEFAULT 'active',
        confidence REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        valid_from INTEGER,
        valid_to INTEGER,
        evidence_frames_json TEXT,
        source_batch_id TEXT,
        source TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(entity_id, fact_type, slot_key, value_norm)
      )
    ''');
    try {
      await db.execute(
        'ALTER TABLE memory_entity_claims ADD COLUMN evidence_frames_json TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_claims ADD COLUMN source_batch_id TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_claims ADD COLUMN claim_id TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_claims ADD COLUMN value_text TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE memory_entity_claims ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_claims ADD COLUMN valid_from INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_claims ADD COLUMN valid_to INTEGER',
      );
    } catch (_) {}
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_claims_entity ON memory_entity_claims(entity_id, fact_type, slot_key)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_id TEXT NOT NULL,
        event_note TEXT NOT NULL,
        evidence_frames_json TEXT,
        source_batch_id TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(entity_id, event_note)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_events_entity ON memory_entity_events(entity_id, updated_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_episodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_id TEXT NOT NULL,
        root_uri TEXT NOT NULL,
        display_uri TEXT NOT NULL,
        segment_id INTEGER NOT NULL,
        batch_index INTEGER NOT NULL DEFAULT 0,
        day_key TEXT NOT NULL,
        first_seen_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        score REAL NOT NULL DEFAULT 0,
        strong_signal INTEGER NOT NULL DEFAULT 0,
        action_kind TEXT NOT NULL DEFAULT '',
        evidence_summary TEXT,
        app_names_json TEXT,
        content_snapshot TEXT NOT NULL DEFAULT '',
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(entity_id, segment_id, batch_index)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_episodes_entity_seen ON memory_entity_episodes(entity_id, last_seen_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_episodes_root_seen ON memory_entity_episodes(root_uri, last_seen_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_evidence (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_id TEXT NOT NULL,
        segment_id INTEGER NOT NULL,
        batch_index INTEGER NOT NULL DEFAULT 0,
        evidence_summary TEXT NOT NULL,
        apps_json TEXT,
        app_names_json TEXT,
        sample_ids_json TEXT,
        frame_count INTEGER NOT NULL DEFAULT 0,
        start_at INTEGER,
        end_at INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_evidence_entity ON memory_entity_evidence(entity_id, created_at DESC)',
    );
    try {
      await db.execute(
        'ALTER TABLE memory_entity_evidence ADD COLUMN app_names_json TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_evidence ADD COLUMN sample_ids_json TEXT',
      );
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_exemplars (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_id TEXT NOT NULL,
        segment_id INTEGER NOT NULL,
        batch_index INTEGER NOT NULL DEFAULT 0,
        sample_id INTEGER,
        capture_time INTEGER,
        app_name TEXT,
        file_path TEXT,
        position_index INTEGER NOT NULL DEFAULT 0,
        rank INTEGER NOT NULL DEFAULT 0,
        reason TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(entity_id, segment_id, batch_index, sample_id, file_path)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_exemplars_entity ON memory_entity_exemplars(entity_id, capture_time DESC)',
    );
    try {
      await db.execute(
        'ALTER TABLE memory_entity_exemplars ADD COLUMN rank INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_exemplars ADD COLUMN reason TEXT',
      );
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_resolution_audits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_id TEXT,
        segment_id INTEGER NOT NULL,
        batch_index INTEGER NOT NULL DEFAULT 0,
        candidate_id TEXT,
        stage TEXT NOT NULL,
        action TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 0,
        model_name TEXT,
        input_json TEXT,
        output_json TEXT,
        payload_json TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    try {
      await db.execute(
        'ALTER TABLE memory_entity_resolution_audits ADD COLUMN model_name TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_resolution_audits ADD COLUMN input_json TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE memory_entity_resolution_audits ADD COLUMN output_json TEXT',
      );
    } catch (_) {}
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_resolution_audits_entity ON memory_entity_resolution_audits(entity_id, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_resolution_audits_segment ON memory_entity_resolution_audits(segment_id, batch_index, created_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_review_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        candidate_id TEXT NOT NULL,
        root_uri TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        preferred_name TEXT NOT NULL,
        segment_id INTEGER NOT NULL,
        batch_index INTEGER NOT NULL DEFAULT 0,
        review_stage TEXT NOT NULL,
        review_reason TEXT NOT NULL,
        suggested_entity_id TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        evidence_summary TEXT,
        app_names_json TEXT,
        candidate_json TEXT NOT NULL,
        shortlist_json TEXT NOT NULL,
        resolution_json TEXT NOT NULL,
        merge_plan_json TEXT NOT NULL,
        audit_json TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(candidate_id, segment_id, batch_index)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_review_queue_status ON memory_entity_review_queue(status, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_review_queue_root ON memory_entity_review_queue(root_uri, status, created_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entity_batch_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        segment_id INTEGER NOT NULL,
        batch_index INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        sample_count INTEGER NOT NULL DEFAULT 0,
        candidate_count INTEGER NOT NULL DEFAULT 0,
        applied_count INTEGER NOT NULL DEFAULT 0,
        review_count INTEGER NOT NULL DEFAULT 0,
        skipped_count INTEGER NOT NULL DEFAULT 0,
        model_name TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(segment_id, batch_index)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_entity_batch_runs_status ON memory_entity_batch_runs(status, created_at DESC)',
    );

    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS memory_entity_search_fts
      USING fts5(
        entity_id UNINDEXED,
        search_text,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    ''');
  }
}

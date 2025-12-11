part of 'screenshot_database.dart';

// 将 AI 配置、消息、会话、提供商与上下文相关方法拆分为扩展
extension ScreenshotDatabaseAI on ScreenshotDatabase {
  Future<void> _createAiTables(DatabaseExecutor db) async {
    // ai_settings: 单行键值存储
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    // ai_messages: 简单会话历史（默认会话：conversation_id='default'）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        reasoning_content TEXT,
        reasoning_duration_ms INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_messages_conv ON ai_messages(conversation_id, id)');

    // 新增：会话列表（独立于模型/提供商选择）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cid TEXT NOT NULL UNIQUE,
        title TEXT,
        provider_id INTEGER,
        model TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_conversations_updated ON ai_conversations(updated_at DESC, pinned DESC, id DESC)');

    // 首次升级/创建时，将 ai_messages 中的会话ID迁移为显式会话条目，并初始化激活会话
    try { await _migrateLegacyConversations(db); } catch (_) {}

    // [v6] legacy removed: ai_site_groups 已移除（统一走 ai_providers + ai_contexts）

    // 新增：AI Providers（通用提供商管理）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_providers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,                           -- openai | gemini | claude | azure_openai | custom
        base_url TEXT,
        chat_path TEXT,
        models_path TEXT,
        use_response_api INTEGER NOT NULL DEFAULT 0,  -- OpenAI Response API 兼容
        enabled INTEGER NOT NULL DEFAULT 1,
        is_default INTEGER NOT NULL DEFAULT 0,
        api_key TEXT,
        models_json TEXT,                             -- 缓存的模型列表，JSON 数组
        extra_json TEXT,                              -- 各类型特定配置（如 Vertex 字段等）
        order_index INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_providers_enabled ON ai_providers(enabled, order_index, id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_providers_name ON ai_providers(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_providers_default ON ai_providers(is_default)');

    // AI 上下文选中（chat/segments 等各自独立）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_contexts (
        context TEXT PRIMARY KEY,
        provider_id INTEGER NOT NULL,
        model TEXT NOT NULL,
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    // 段落与结果表（与原生侧保持一致）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        duration_sec INTEGER NOT NULL,
        sample_interval_sec INTEGER NOT NULL,
        status TEXT NOT NULL,
        app_packages TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_segments_time ON segments(start_time, end_time)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS segment_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        segment_id INTEGER NOT NULL,
        capture_time INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        app_package_name TEXT NOT NULL,
        app_name TEXT NOT NULL,
        position_index INTEGER NOT NULL,
        p_hash INTEGER,
        is_keyframe INTEGER NOT NULL DEFAULT 0,
        hash_distance INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(segment_id, file_path)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_segment_samples_seg ON segment_samples(segment_id, position_index)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sample_id INTEGER UNIQUE,
        segment_id INTEGER,
        embedding BLOB,
        model_version TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_segment ON embeddings(segment_id)');

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_content USING fts5(
          sample_id UNINDEXED,
          segment_id UNINDEXED,
          ocr_text,
          summary,
          app_name
        )
      ''');
    } catch (e) {
      try { FlutterLogger.nativeWarn('DB', 'FTS5 for fts_content not supported: ' + e.toString()); } catch (_) {}
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS segment_results (
        segment_id INTEGER PRIMARY KEY,
        ai_provider TEXT,
        ai_model TEXT,
        output_text TEXT,
        structured_json TEXT,
        categories TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    // 每日总结表：按日期聚合（YYYY-MM-DD）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_summaries (
        date_key TEXT PRIMARY KEY,
        ai_provider TEXT,
        ai_model TEXT,
        output_text TEXT,
        structured_json TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    await _createWeeklySummariesTable(db);

    await _createMorningInsightsTable(db);
    await _createPersonaArticlesTable(db);
    
    // 创建动态搜索 FTS 索引
    await _createSegmentResultsFts(db);
    await _backfillSegmentResultsFts(db);
  }

  // v6: 清理旧的 AI 分组表与老配置键（首次打开/升级时执行）
  Future<void> _cleanupLegacyAiArtifacts(DatabaseExecutor db) async {
    try {
      await db.execute('DROP TABLE IF EXISTS ai_site_groups');
    } catch (_) {}
    try {
      await db.execute(
        "DELETE FROM ai_settings WHERE key IN ('base_url','api_key','model','active_group_id')"
      );
    } catch (_) {}
  }

  // ===================== AI 配置与会话 便捷方法 =====================
  Future<String?> getAiSetting(String key) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ai_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setAiSetting(String key, String? value) async {
    final db = await database;
    if (value == null) {
      try { await db.delete('ai_settings', where: 'key = ?', whereArgs: [key]); } catch (_) {}
      return;
    }
    try {
      await db.execute(
        'INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)',
        [key, value],
      );
    } catch (_) {
      try {
        final count = await db.update('ai_settings', {'value': value}, where: 'key = ?', whereArgs: [key]);
        if (count == 0) {
          await db.insert('ai_settings', {'key': key, 'value': value});
        }
      } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> getAiMessages(String conversationId, {int? limit, int? offset}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ai_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'id ASC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 仅返回会话的“最新 N 条”消息，按 id DESC 读取后再倒序为升序返回
  Future<List<Map<String, dynamic>>> getAiMessagesTail(String conversationId, {int limit = 40}) async {
    try {
      final db = await database;
      final rowsDesc = await db.query(
        'ai_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'id DESC',
        limit: limit,
      );
      // UI 仍按时间顺序展示
      return rowsDesc.reversed.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> appendAiMessage(String conversationId, String role, String content, {int? createdAt, String? reasoningContent, int? reasoningDurationMs}) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 确保会话条目存在（若无则占位创建）
      try {
        await db.execute(
          'INSERT OR IGNORE INTO ai_conversations(cid, title, created_at, updated_at) VALUES(?, ?, ?, ?)',
          [conversationId, null, now, now],
        );
      } catch (_) {}

      await db.insert('ai_messages', {
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        if (reasoningContent != null) 'reasoning_content': reasoningContent,
        if (reasoningDurationMs != null) 'reasoning_duration_ms': reasoningDurationMs,
        if (createdAt != null) 'created_at': createdAt,
      });

      // 更新会话的最近更新时间
      try {
        await db.update('ai_conversations', {'updated_at': now}, where: 'cid = ?', whereArgs: [conversationId]);
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> clearAiConversation(String conversationId) async {
    try {
      final db = await database;
      await db.delete('ai_messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
    } catch (_) {}
  }

  // ===================== 会话（Conversations）便捷方法 =====================
  Future<void> _migrateLegacyConversations(DatabaseExecutor exec) async {
    try {
      // 若已有会话条目：兜底写入激活键（直接使用 exec，避免递归打开 DB）
      final exists = await exec.query('ai_conversations', columns: ['id'], limit: 1);
      if (exists.isNotEmpty) {
        try {
          final activeRows = await exec.query(
            'ai_settings',
            columns: ['value'],
            where: 'key = ?',
            whereArgs: ['chat_active_cid'],
            limit: 1,
          );
          final hasActive = activeRows.isNotEmpty && ((activeRows.first['value'] as String?)?.trim().isNotEmpty == true);
          if (!hasActive) {
            final r2 = await exec.query(
              'ai_conversations',
              columns: ['cid'],
              orderBy: 'pinned DESC, updated_at DESC, id DESC',
              limit: 1,
            );
            final cid = r2.isNotEmpty ? ((r2.first['cid'] as String?) ?? 'default') : 'default';
            await exec.execute('INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)', ['chat_active_cid', cid]);
          }
        } catch (_) {}
        return;
      }

      // 从历史消息推断所有会话ID并生成会话条目
      List<Map<String, Object?>> mids = [];
      try {
        mids = await exec.rawQuery('SELECT DISTINCT conversation_id AS cid FROM ai_messages');
      } catch (_) {}

      final now = DateTime.now().millisecondsSinceEpoch;
      if (mids.isEmpty) {
        // 初始化默认会话
        try {
          await exec.insert('ai_conversations', {
            'cid': 'default',
            'title': '默认会话',
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
        try {
          await exec.execute('INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)', ['chat_active_cid', 'default']);
        } catch (_) {}
        return;
      }

      for (final m in mids) {
        final cid = (m['cid'] as String?) ?? 'default';
        final String title = (cid == 'default')
            ? '默认会话'
            : (cid.startsWith('group:') ? ('模型会话 ' + cid.substring(6)) : ('会话 ' + cid));
        try {
          await exec.insert('ai_conversations', {
            'cid': cid,
            'title': title,
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }

      // 初始化激活会话：优先 default -> 否则取最近更新
      try {
        final r = await exec.query('ai_conversations', columns: ['cid'], where: 'cid = ?', whereArgs: ['default'], limit: 1);
        String cid;
        if (r.isNotEmpty) {
          cid = (r.first['cid'] as String?) ?? 'default';
        } else {
          final r2 = await exec.query('ai_conversations', columns: ['cid'], orderBy: 'updated_at DESC, id DESC', limit: 1);
          cid = r2.isNotEmpty ? ((r2.first['cid'] as String?) ?? 'default') : 'default';
        }
        await exec.execute('INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)', ['chat_active_cid', cid]);
      } catch (_) {}
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listAiConversations({int? limit, int? offset}) async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_conversations',
        orderBy: 'pinned DESC, updated_at DESC, id DESC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getAiConversationByCid(String cid) async {
    final db = await database;
    try {
      final rows = await db.query('ai_conversations', where: 'cid = ?', whereArgs: [cid], limit: 1);
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  String _genConvCid() => 'c' + DateTime.now().millisecondsSinceEpoch.toString();

  Future<String> createAiConversation({String? title, int? providerId, String? model, String? cid}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final theCid = (cid == null || cid.trim().isEmpty) ? _genConvCid() : cid.trim();
    try {
      await db.insert('ai_conversations', {
        'cid': theCid,
        // 不默认写入本地化文本，保持空字符串以便 UI 统一按 l10n 占位显示
        'title': (title == null) ? '' : title.trim(),
        'provider_id': providerId,
        'model': model,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return theCid;
    } catch (_) {
      return theCid; // 已存在则直接返回
    }
  }

  Future<bool> renameAiConversation(String cid, String title) async {
    final db = await database;
    try {
      final count = await db.update(
        'ai_conversations',
        {'title': title.trim(), 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'cid = ?',
        whereArgs: [cid],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteAiConversation(String cid) async {
    final db = await database;
    try {
      final swTotal = Stopwatch()..start();
      await db.transaction((txn) async {
        final swMsg = Stopwatch()..start();
        try { await txn.delete('ai_messages', where: 'conversation_id = ?', whereArgs: [cid]); } catch (_) {}
        swMsg.stop();
        final swConv = Stopwatch()..start();
        await txn.delete('ai_conversations', where: 'cid = ?', whereArgs: [cid]);
        swConv.stop();
        try { await FlutterLogger.nativeInfo('DB', 'deleteAiConversation txn parts ms msg='+swMsg.elapsedMilliseconds.toString()+' conv='+swConv.elapsedMilliseconds.toString()); } catch (_) {}
      });
      swTotal.stop();
      try { await FlutterLogger.nativeInfo('DB', 'deleteAiConversation total ms='+swTotal.elapsedMilliseconds.toString()+' cid='+cid); } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> touchAiConversation(String cid) async {
    final db = await database;
    try {
      await db.update('ai_conversations', {'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'cid = ?', whereArgs: [cid]);
    } catch (_) {}
  }

  // ===================== AI 提供商（Providers）便捷方法 =====================
  Future<List<Map<String, dynamic>>> listAIProviders() async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_providers',
        orderBy: 'enabled DESC, order_index ASC, id ASC'
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getAIProviderById(int id) async {
    final db = await database;
    try {
      final rows = await db.query('ai_providers', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<int?> insertAIProvider({
    required String name,
    required String type,
    String? baseUrl,
    String? chatPath,
    String? modelsPath,
    bool useResponseApi = false,
    bool enabled = true,
    bool isDefault = false,
    String? modelsJson,
    String? extraJson,
    int? orderIndex,
    String? apiKey,
  }) async {
    final db = await database;
    try {
      final id = await db.insert('ai_providers', {
        'name': name.trim(),
        'type': type.trim(),
        'base_url': baseUrl?.trim(),
        'chat_path': chatPath?.trim(),
        'models_path': modelsPath?.trim(),
        'use_response_api': useResponseApi ? 1 : 0,
        'enabled': enabled ? 1 : 0,
        'is_default': isDefault ? 1 : 0,
        'api_key': apiKey?.trim(),
        'models_json': modelsJson,
        'extra_json': extraJson,
        'order_index': orderIndex ?? 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      if (isDefault && id != null) {
        await setDefaultAIProvider(id);
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateAIProvider({
    required int id,
    String? name,
    String? type,
    String? baseUrl,
    String? chatPath,
    String? modelsPath,
    bool setModelsPath = false,
    bool? useResponseApi,
    bool? enabled,
    bool? isDefault,
    String? modelsJson,
    String? extraJson,
    int? orderIndex,
    String? apiKey,
  }) async {
    final db = await database;
    try {
      final data = <String, Object?>{};
      if (name != null) data['name'] = name.trim();
      if (type != null) data['type'] = type.trim();
      if (baseUrl != null) data['base_url'] = baseUrl.trim();
      if (chatPath != null) data['chat_path'] = chatPath.trim();
      if (setModelsPath) data['models_path'] = modelsPath?.trim();
      if (useResponseApi != null) data['use_response_api'] = useResponseApi ? 1 : 0;
      if (enabled != null) data['enabled'] = enabled ? 1 : 0;
      if (isDefault != null) data['is_default'] = isDefault ? 1 : 0;
      if (modelsJson != null) data['models_json'] = modelsJson;
      if (extraJson != null) data['extra_json'] = extraJson;
      if (orderIndex != null) data['order_index'] = orderIndex;
      if (apiKey != null) data['api_key'] = apiKey.trim();

      if (data.isEmpty) {
        final exists = await getAIProviderById(id);
        if (exists == null) {
          return false;
        }
        if (isDefault == true) {
          await setDefaultAIProvider(id);
        }
        return true;
      }

      final count = await db.update('ai_providers', data, where: 'id = ?', whereArgs: [id]);
      if (count > 0) {
        if (isDefault == true) {
          await setDefaultAIProvider(id);
        }
        return true;
      }

      final exists = await getAIProviderById(id);
      if (exists == null) {
        return false;
      }
      if (isDefault == true) {
        await setDefaultAIProvider(id);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteAIProvider(int id) async {
    final db = await database;
    try {
      final count = await db.delete('ai_providers', where: 'id = ?', whereArgs: [id]);
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDefaultAIProvider(int id) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        await txn.update('ai_providers', {'is_default': 0}, where: 'is_default = 1');
        await txn.update('ai_providers', {'is_default': 1}, where: 'id = ?', whereArgs: [id]);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDefaultAIProvider() async {
    final db = await database;
    try {
      final rows = await db.query('ai_providers', where: 'is_default = 1', limit: 1);
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveAIProviderModelsJson({required int id, required String modelsJson}) async {
    final db = await database;
    try {
      final count = await db.update('ai_providers', {'models_json': modelsJson}, where: 'id = ?', whereArgs: [id]);
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  // ======= 新增：API Key 存取 =======
  Future<String?> getAIProviderApiKey(int id) async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_providers',
        columns: ['api_key'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return (rows.first['api_key'] as String?);
    } catch (_) {
      return null;
    }
  }

  Future<void> setAIProviderApiKey({required int id, String? apiKey}) async {
    final db = await database;
    try {
      await db.update(
        'ai_providers',
        {'api_key': (apiKey == null || apiKey.trim().isEmpty) ? null : apiKey.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  // ===================== AI 上下文选中（chat / segments） =====================
  Future<Map<String, dynamic>?> getAIContext(String context) async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_contexts',
        where: 'context = ?',
        whereArgs: [context],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setAIContext({
    required String context,
    required int providerId,
    required String model,
  }) async {
    final db = await database;
    try {
      await db.execute('''
        INSERT INTO ai_contexts (context, provider_id, model, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(context) DO UPDATE SET
          provider_id = excluded.provider_id,
          model = excluded.model,
          updated_at = excluded.updated_at
      ''', [context, providerId, model, DateTime.now().millisecondsSinceEpoch]);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ======= 段落查询接口 =======
  Future<Map<String, dynamic>?> getActiveSegment() async {
    final db = await database;
    try {
      final rows = await db.query(
        'segments',
        where: 'status = ?',
        whereArgs: ['collecting'],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>> listSegments({int limit = 50, int offset = 0}) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segments',
        orderBy: 'id DESC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (_) { return <Map<String, dynamic>>[]; }
  }

  /// 列出段落（带是否有总结标记），可选仅返回“无总结”的事件
  /// - has_summary: 0 表示无总结；1 表示已有总结
  /// - 仅返回“至少有一张样本图片”的事件，避免前端渲染后再隐藏导致滚动抖动
  /// - 可选按 start_time 进行时间范围过滤（用于“动态”页按日期窗口增量加载）
  Future<List<Map<String, dynamic>>> listSegmentsEx({
    int limit = 50,
    bool onlyNoSummary = false,
    int? startMillis,
    int? endMillis,
  }) async {
    final db = await database;
    try {
      const String noSummaryCond =
          "r.segment_id IS NULL OR ((r.output_text IS NULL OR LOWER(TRIM(r.output_text)) IN ('','null')) AND (r.structured_json IS NULL OR LOWER(TRIM(r.structured_json)) IN ('','null')))";
      const String hasSamplesCond =
          "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
      // 组合 WHERE 子句
      final List<String> whereClauses = <String>[hasSamplesCond];
      final List<Object?> params = <Object?>[];

      if (startMillis != null) {
        whereClauses.add('s.start_time >= ?');
        params.add(startMillis);
      }
      if (endMillis != null) {
        whereClauses.add('s.start_time <= ?');
        params.add(endMillis);
      }
      if (onlyNoSummary) {
        whereClauses.add('(' + noSummaryCond + ')');
      }
      final String whereSql = whereClauses.isEmpty ? '' : ('WHERE ' + whereClauses.join(' AND '));
      final String sql = '''
        SELECT
          s.*,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary,
          (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count,
          -- 若 segments.app_packages 为空，回退为样本表去重聚合
          COALESCE(
            NULLIF(TRIM(s.app_packages), ''),
            (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
          ) AS app_packages_display,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        $whereSql
        ORDER BY s.start_time DESC, s.id DESC
        LIMIT ?
      ''';
      params.add(limit);
      final rows = await db.rawQuery(sql, params);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 触发一次原生端的段落推进/补救扫描（用于点击刷新时重试缺失总结）
  Future<bool> triggerSegmentTick() async {
    try {
      final res = await ScreenshotDatabase._channel.invokeMethod('triggerSegmentTick');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// 通过原生接口按ID批量重试生成总结
  /// force=true 时无视已有结果与时间范围，直接强制重跑
  Future<int> retrySegments(List<int> ids, {bool force = false}) async {
    try {
      final res = await ScreenshotDatabase._channel.invokeMethod('retrySegments', {
        'ids': ids,
        'force': force,
      });
      if (res is int) return res;
      if (res is num) return res.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> listSegmentSamples(int segmentId) async {
    final db = await database;
    try {
      final String sql = 'SELECT id, segment_id, capture_time, file_path, app_package_name, app_name, position_index FROM segment_samples WHERE segment_id = ? ORDER BY position_index ASC';
      try { await FlutterLogger.nativeDebug('DB', 'SQL: ' + sql.replaceAll('?', segmentId.toString())); } catch (_) {}
      final rows = await db.query(
        'segment_samples',
        where: 'segment_id = ?',
        whereArgs: [segmentId],
        orderBy: 'position_index ASC',
      );
      return rows;
    } catch (_) { return <Map<String, dynamic>>[]; }
  }

  Future<List<Map<String, dynamic>>> listLatestSamples({int limit = 10}) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segment_samples',
        orderBy: 'capture_time DESC, id DESC',
        limit: limit,
      );
      return rows;
    } catch (_) { return <Map<String, dynamic>>[]; }
  }

  Future<void> saveEmbeddingForSample({
    required int sampleId,
    required int segmentId,
    required List<double> embedding,
    required String modelVersion,
  }) async {
    final db = await database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Float32List floats = Float32List(embedding.length);
    for (int i = 0; i < embedding.length; i++) {
      floats[i] = embedding[i].toDouble();
    }
    final Uint8List bytes = floats.buffer.asUint8List();
    await db.insert(
      'embeddings',
      <String, Object?>{
        'sample_id': sampleId,
        'segment_id': segmentId,
        'embedding': bytes,
        'model_version': modelVersion,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSegmentResult(int segmentId) async {
    final db = await database;
    try {
      final String sql = 'SELECT segment_id, ai_provider, ai_model, output_text, structured_json, categories, created_at FROM segment_results WHERE segment_id = ? LIMIT 1';
      try { await FlutterLogger.nativeDebug('DB', 'SQL: ' + sql.replaceAll('?', segmentId.toString())); } catch (_) {}
      final rows = await db.query(
        'segment_results',
        where: 'segment_id = ?',
        whereArgs: [segmentId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) { return null; }
  }

  /// 搜索动态（segment）内容
  /// 支持搜索 AI 摘要文本和分类标签
  Future<List<Map<String, dynamic>>> searchSegmentsByText(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
  }) async {
    final db = await database;
    try {
      final String q = query.trim();
      if (q.isEmpty) return <Map<String, dynamic>>[];

      final int fetchLimit = limit ?? 50;
      final int fetchOffset = offset ?? 0;

      // 构建 FTS MATCH 字符串
      String buildMatch(String text) {
        final parts = text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
        if (parts.isEmpty) return text;
        final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
        return limited.map((w) => '${w.replaceAll('"', '')}*').join(' AND ');
      }

      final String match = buildMatch(q);
      final List<Object?> args = <Object?>[match];
      final List<String> filters = <String>[];

      if (startMillis != null) {
        filters.add('s.start_time >= ?');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('s.start_time <= ?');
        args.add(endMillis);
      }

      final String whereClause = filters.isEmpty ? '' : 'AND ${filters.join(' AND ')}';

      // 尝试 FTS 搜索
      try {
        final String sql = '''
          SELECT
            s.*,
            r.output_text,
            r.structured_json,
            r.categories,
            r.ai_provider,
            r.ai_model,
            COALESCE(
              NULLIF(TRIM(s.app_packages), ''),
              (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
            ) AS app_packages_display,
            (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count
          FROM segment_results_fts fts
          JOIN segment_results r ON r.segment_id = fts.rowid
          JOIN segments s ON s.id = r.segment_id
          WHERE segment_results_fts MATCH ?
            $whereClause
          ORDER BY s.start_time DESC
          LIMIT ? OFFSET ?
        ''';
        args.add(fetchLimit);
        args.add(fetchOffset);

        final rows = await db.rawQuery(sql, args);
        return rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (ftsError) {
        // FTS 不可用，回退到 LIKE 搜索
        try { await FlutterLogger.nativeWarn('DB', 'FTS search failed, fallback to LIKE: $ftsError'); } catch (_) {}
        
        final String likeTerm = '%$q%';
        final List<Object?> likeArgs = <Object?>[];
        final List<String> likeFilters = <String>[
          "(r.output_text LIKE ? OR r.categories LIKE ?)"
        ];
        likeArgs.add(likeTerm);
        likeArgs.add(likeTerm);

        if (startMillis != null) {
          likeFilters.add('s.start_time >= ?');
          likeArgs.add(startMillis);
        }
        if (endMillis != null) {
          likeFilters.add('s.start_time <= ?');
          likeArgs.add(endMillis);
        }

        likeArgs.add(fetchLimit);
        likeArgs.add(fetchOffset);

        final String likeSql = '''
          SELECT
            s.*,
            r.output_text,
            r.structured_json,
            r.categories,
            r.ai_provider,
            r.ai_model,
            COALESCE(
              NULLIF(TRIM(s.app_packages), ''),
              (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
            ) AS app_packages_display,
            (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count
          FROM segments s
          JOIN segment_results r ON r.segment_id = s.id
          WHERE ${likeFilters.join(' AND ')}
          ORDER BY s.start_time DESC
          LIMIT ? OFFSET ?
        ''';

        final rows = await db.rawQuery(likeSql, likeArgs);
        return rows.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      try { await FlutterLogger.nativeError('DB', 'searchSegmentsByText failed: $e'); } catch (_) {}
      return <Map<String, dynamic>>[];
    }
  }

  /// 统计搜索动态结果总数
  Future<int> countSegmentsByText(
    String query, {
    int? startMillis,
    int? endMillis,
  }) async {
    final db = await database;
    try {
      final String q = query.trim();
      if (q.isEmpty) return 0;

      String buildMatch(String text) {
        final parts = text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
        if (parts.isEmpty) return text;
        final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
        return limited.map((w) => '${w.replaceAll('"', '')}*').join(' AND ');
      }

      final String match = buildMatch(q);
      final List<Object?> args = <Object?>[match];
      final List<String> filters = <String>[];

      if (startMillis != null) {
        filters.add('s.start_time >= ?');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('s.start_time <= ?');
        args.add(endMillis);
      }

      final String whereClause = filters.isEmpty ? '' : 'AND ${filters.join(' AND ')}';

      try {
        final String sql = '''
          SELECT COUNT(*) AS c
          FROM segment_results_fts fts
          JOIN segment_results r ON r.segment_id = fts.rowid
          JOIN segments s ON s.id = r.segment_id
          WHERE segment_results_fts MATCH ?
            $whereClause
        ''';

        final rows = await db.rawQuery(sql, args);
        return (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
      } catch (_) {
        // 回退 LIKE
        final String likeTerm = '%$q%';
        final List<Object?> likeArgs = <Object?>[likeTerm, likeTerm];
        final List<String> likeFilters = <String>[
          "(r.output_text LIKE ? OR r.categories LIKE ?)"
        ];

        if (startMillis != null) {
          likeFilters.add('s.start_time >= ?');
          likeArgs.add(startMillis);
        }
        if (endMillis != null) {
          likeFilters.add('s.start_time <= ?');
          likeArgs.add(endMillis);
        }

        final String likeSql = '''
          SELECT COUNT(*) AS c
          FROM segments s
          JOIN segment_results r ON r.segment_id = s.id
          WHERE ${likeFilters.join(' AND ')}
        ''';

        final rows = await db.rawQuery(likeSql, likeArgs);
        return (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
      }
    } catch (_) {
      return 0;
    }
  }

  /// 删除单个段落事件（仅删除事件及其结果/样本，不删除月表中的图片记录/文件）
  Future<bool> deleteSegmentOnly(int segmentId) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        await txn.delete('segment_results', where: 'segment_id = ?', whereArgs: [segmentId]);
        await txn.delete('segment_samples', where: 'segment_id = ?', whereArgs: [segmentId]);
        await txn.delete('segments', where: 'id = ?', whereArgs: [segmentId]);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ======= 每日总结（daily_summaries） =======
  Future<Map<String, dynamic>?> getDailySummary(String dateKey) async {
    final db = await database;
    try {
      final rows = await db.query(
        'daily_summaries',
        where: 'date_key = ?',
        whereArgs: [dateKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertDailySummary({
    required String dateKey,
    String? aiProvider,
    String? aiModel,
    required String outputText,
    String? structuredJson,
  }) async {
    final db = await database;
    try {
      await db.insert(
        'daily_summaries',
        {
          'date_key': dateKey,
          'ai_provider': aiProvider,
          'ai_model': aiModel,
          'output_text': outputText,
          'structured_json': structuredJson,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getWeeklySummary(String weekStartDate) async {
    final db = await database;
    try {
      final rows = await db.query(
        'weekly_summaries',
        where: 'week_start_date = ?',
        whereArgs: [weekStartDate],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertWeeklySummary({
    required String weekStartDate,
    required String weekEndDate,
    String? aiProvider,
    String? aiModel,
    required String outputText,
    String? structuredJson,
  }) async {
    final db = await database;
    try {
      await db.insert(
        'weekly_summaries',
        {
          'week_start_date': weekStartDate,
          'week_end_date': weekEndDate,
          'ai_provider': aiProvider,
          'ai_model': aiModel,
          'output_text': outputText,
          'structured_json': structuredJson,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listWeeklySummaries({int? limit, int? offset}) async {
    final db = await database;
    try {
      final rows = await db.query(
        'weekly_summaries',
        orderBy: 'week_start_date DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getMorningInsights(String dateKey) async {
    final db = await database;
    try {
      final rows = await db.query(
        'morning_insights',
        where: 'date_key = ?',
        whereArgs: [dateKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertMorningInsights({
    required String dateKey,
    required String sourceDateKey,
    required String tipsJson,
    String? rawResponse,
  }) async {
    final db = await database;
    try {
      await db.insert(
        'morning_insights',
        {
          'date_key': dateKey,
          'source_date_key': sourceDateKey,
          'tips_json': tipsJson,
          if (rawResponse != null) 'raw_response': rawResponse,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> deleteMorningInsights(String dateKey) async {
    final db = await database;
    try {
      return await db.delete('morning_insights', where: 'date_key = ?', whereArgs: [dateKey]);
    } catch (_) {
      return 0;
    }
  }

  /// 按时间范围获取“已有AI结果”的段落（含结果元数据），用于拼装每日总结上下文
  Future<List<Map<String, dynamic>>> listSegmentsWithResultsBetween({
    required int startMillis,
    required int endMillis,
  }) async {
    final db = await database;
    try {
      final String sql = '''
        SELECT
          s.*,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        JOIN segment_results r ON r.segment_id = s.id
        WHERE s.start_time >= ? AND s.start_time <= ?
        ORDER BY s.start_time ASC
      ''';
      try { await FlutterLogger.nativeDebug('DB', 'SQL: ' + sql.replaceFirst('?', startMillis.toString()).replaceFirst('?', endMillis.toString())); } catch (_) {}
      final rows = await db.rawQuery(sql, [startMillis, endMillis]);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 列出与时间窗“有重叠”的段落（要求至少有样本图片），同时返回可能存在的 AI 结果
  /// - 选择逻辑：s.start_time <= endMillis AND s.end_time >= startMillis
  /// - 目的：避免仅按 start_time 命中导致跨窗事件被漏掉
  Future<List<Map<String, dynamic>>> listSegmentsOverlapWithSamplesBetween({
    required int startMillis,
    required int endMillis,
  }) async {
    final db = await database;
    try {
      final String sql = '''
        SELECT
          s.*,
          -- 展示用应用集合：优先 segments.app_packages；为空则回退样本去重聚合
          COALESCE(
            NULLIF(TRIM(s.app_packages), ''),
            (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
          ) AS app_packages_display,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        WHERE s.start_time <= ? AND s.end_time >= ?
          AND EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)
        ORDER BY s.start_time ASC
      ''';
      try { await FlutterLogger.nativeDebug('DB', 'SQL: ' + sql.replaceFirst('?', endMillis.toString()).replaceFirst('?', startMillis.toString())); } catch (_) {}
      final rows = await db.rawQuery(sql, [endMillis, startMillis]);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  // ===================== Persona 画像文章缓存 =====================
  Future<Map<String, dynamic>?> getPersonaArticle(String style) async {
    final db = await database;
    try {
      final rows = await db.query(
        'persona_articles',
        where: 'style = ?',
        whereArgs: [style],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertPersonaArticle({
    required String style,
    required String article,
    String? locale,
    String? aiProvider,
    String? aiModel,
  }) async {
    final db = await database;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'persona_articles',
        {
          'style': style,
          'article': article,
          'locale': locale,
          'ai_provider': aiProvider,
          'ai_model': aiModel,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearPersonaArticles({String? style}) async {
    final db = await database;
    try {
      if (style == null) {
        await db.delete('persona_articles');
      } else {
        await db.delete(
          'persona_articles',
          where: 'style = ?',
          whereArgs: [style],
        );
      }
    } catch (_) {}
  }
}

Future<void> _createWeeklySummariesTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS weekly_summaries (
      week_start_date TEXT PRIMARY KEY,
      week_end_date TEXT NOT NULL,
      ai_provider TEXT,
      ai_model TEXT,
      output_text TEXT,
      structured_json TEXT,
      created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_weekly_summaries_created ON weekly_summaries(created_at DESC)');
}

Future<void> _createMorningInsightsTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS morning_insights (
      date_key TEXT PRIMARY KEY,
      source_date_key TEXT NOT NULL,
      tips_json TEXT NOT NULL,
      raw_response TEXT,
      created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
    )
  ''');
}

Future<void> _createPersonaArticlesTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS persona_articles (
      style TEXT PRIMARY KEY,
      article TEXT NOT NULL,
      locale TEXT,
      ai_provider TEXT,
      ai_model TEXT,
      created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
      updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
    )
  ''');
}

/// 创建 segment_results 的 FTS5 全文搜索索引
Future<void> _createSegmentResultsFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS segment_results_fts USING fts5(
        output_text,
        categories,
        content='segment_results',
        content_rowid='segment_id'
      )
    ''');
    // 创建触发器保持 FTS 同步
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS segment_results_ai AFTER INSERT ON segment_results BEGIN
        INSERT INTO segment_results_fts(rowid, output_text, categories)
        VALUES (NEW.segment_id, NEW.output_text, NEW.categories);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS segment_results_ad AFTER DELETE ON segment_results BEGIN
        INSERT INTO segment_results_fts(segment_results_fts, rowid, output_text, categories)
        VALUES ('delete', OLD.segment_id, OLD.output_text, OLD.categories);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS segment_results_au AFTER UPDATE ON segment_results BEGIN
        INSERT INTO segment_results_fts(segment_results_fts, rowid, output_text, categories)
        VALUES ('delete', OLD.segment_id, OLD.output_text, OLD.categories);
        INSERT INTO segment_results_fts(rowid, output_text, categories)
        VALUES (NEW.segment_id, NEW.output_text, NEW.categories);
      END
    ''');
  } catch (e) {
    try { FlutterLogger.nativeWarn('DB', 'FTS5 for segment_results not supported: $e'); } catch (_) {}
  }
}

/// 回填已有数据到 FTS 索引
Future<void> _backfillSegmentResultsFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      INSERT OR IGNORE INTO segment_results_fts(rowid, output_text, categories)
      SELECT segment_id, output_text, categories FROM segment_results
      WHERE output_text IS NOT NULL AND TRIM(output_text) != ''
    ''');
  } catch (e) {
    try { FlutterLogger.nativeWarn('DB', 'Backfill segment_results_fts failed: $e'); } catch (_) {}
  }
}



part of 'screenshot_database.dart';

class DynamicRebuildWorkerStatus {
  DynamicRebuildWorkerStatus._();

  static const String idle = 'idle';
  static const String running = 'running';
  static const String retrying = 'retrying';
  static const String completed = 'completed';
  static const String failedWaiting = 'failed_waiting';
}

class DynamicRebuildWorkerState {
  final int slotId;
  final String status;
  final String dayKey;
  final int totalSegments;
  final int processedSegments;
  final String currentRangeLabel;
  final String currentStageLabel;
  final String currentStageDetail;
  final int currentSegmentId;
  final int retryCount;
  final int retryLimit;
  final List<String> recentStreamChunks;

  const DynamicRebuildWorkerState({
    required this.slotId,
    required this.status,
    required this.dayKey,
    required this.totalSegments,
    required this.processedSegments,
    required this.currentRangeLabel,
    required this.currentStageLabel,
    required this.currentStageDetail,
    required this.currentSegmentId,
    required this.retryCount,
    required this.retryLimit,
    required this.recentStreamChunks,
  });

  factory DynamicRebuildWorkerState.fromMap(Map<dynamic, dynamic>? map) {
    final data = map ?? const <dynamic, dynamic>{};
    return DynamicRebuildWorkerState(
      slotId: DynamicRebuildTaskStatus.safeTaskInt(data['slotId']),
      status: (data['status'] as String?)?.trim().isNotEmpty == true
          ? (data['status'] as String).trim()
          : DynamicRebuildWorkerStatus.idle,
      dayKey: (data['dayKey'] as String?)?.trim() ?? '',
      totalSegments: DynamicRebuildTaskStatus.safeTaskInt(
        data['totalSegments'],
      ),
      processedSegments: DynamicRebuildTaskStatus.safeTaskInt(
        data['processedSegments'],
      ),
      currentRangeLabel: (data['currentRangeLabel'] as String?)?.trim() ?? '',
      currentStageLabel: (data['currentStageLabel'] as String?)?.trim() ?? '',
      currentStageDetail: (data['currentStageDetail'] as String?)?.trim() ?? '',
      currentSegmentId: DynamicRebuildTaskStatus.safeTaskInt(
        data['currentSegmentId'],
      ),
      retryCount: DynamicRebuildTaskStatus.safeTaskInt(data['retryCount']),
      retryLimit: DynamicRebuildTaskStatus.safeTaskInt(data['retryLimit']),
      recentStreamChunks:
          ((data['recentStreamChunks'] as List?) ?? const <Object?>[])
              .map((Object? value) => value?.toString().trim() ?? '')
              .where((String value) => value.isNotEmpty)
              .take(3)
              .toList(growable: false),
    );
  }

  bool get isIdle => status == DynamicRebuildWorkerStatus.idle;
  bool get isRunning => status == DynamicRebuildWorkerStatus.running;
  bool get isRetrying => status == DynamicRebuildWorkerStatus.retrying;
  bool get isCompleted => status == DynamicRebuildWorkerStatus.completed;
  bool get isFailedWaiting =>
      status == DynamicRebuildWorkerStatus.failedWaiting;
}

class DynamicRebuildTaskStatus {
  final String taskId;
  final String status;
  final int startedAt;
  final int updatedAt;
  final int completedAt;
  final int dayConcurrency;
  final int totalSegments;
  final int processedSegments;
  final int failedSegments;
  final int totalDays;
  final int completedDays;
  final int pendingDays;
  final int failedDays;
  final String currentDayKey;
  final String timelineCutoffDayKey;
  final int currentSegmentId;
  final String currentRangeLabel;
  final String currentStage;
  final String currentStageLabel;
  final String currentStageDetail;
  final String? lastError;
  final bool isActive;
  final String progressPercent;
  final String aiModel;
  final List<String> recentLogs;
  final List<DynamicRebuildWorkerState> workers;

  const DynamicRebuildTaskStatus({
    required this.taskId,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    required this.completedAt,
    required this.dayConcurrency,
    required this.totalSegments,
    required this.processedSegments,
    required this.failedSegments,
    required this.totalDays,
    required this.completedDays,
    required this.pendingDays,
    required this.failedDays,
    required this.currentDayKey,
    required this.timelineCutoffDayKey,
    required this.currentSegmentId,
    required this.currentRangeLabel,
    required this.currentStage,
    required this.currentStageLabel,
    required this.currentStageDetail,
    required this.lastError,
    required this.isActive,
    required this.progressPercent,
    required this.aiModel,
    required this.recentLogs,
    required this.workers,
  });

  factory DynamicRebuildTaskStatus.fromMap(Map<dynamic, dynamic>? map) {
    final data = map ?? const <dynamic, dynamic>{};
    final String? lastErrorRaw = (data['lastError'] as String?)?.trim();
    final String? lastError =
        lastErrorRaw == null ||
            lastErrorRaw.isEmpty ||
            lastErrorRaw.toLowerCase() == 'null'
        ? null
        : lastErrorRaw;
    return DynamicRebuildTaskStatus(
      taskId: (data['taskId'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'idle',
      startedAt: _safeTaskInt(data['startedAt']),
      updatedAt: _safeTaskInt(data['updatedAt']),
      completedAt: _safeTaskInt(data['completedAt']),
      dayConcurrency: _safeTaskInt(data['dayConcurrency']) <= 0
          ? 1
          : _safeTaskInt(data['dayConcurrency']),
      totalSegments: _safeTaskInt(data['totalSegments']),
      processedSegments: _safeTaskInt(data['processedSegments']),
      failedSegments: _safeTaskInt(data['failedSegments']),
      totalDays: _safeTaskInt(data['totalDays']),
      completedDays: _safeTaskInt(data['completedDays']),
      pendingDays: _safeTaskInt(data['pendingDays']),
      failedDays: _safeTaskInt(data['failedDays']),
      currentDayKey: (data['currentDayKey'] as String?) ?? '',
      timelineCutoffDayKey: (data['timelineCutoffDayKey'] as String?) ?? '',
      currentSegmentId: _safeTaskInt(data['currentSegmentId']),
      currentRangeLabel: (data['currentRangeLabel'] as String?) ?? '',
      currentStage: (data['currentStage'] as String?) ?? '',
      currentStageLabel: (data['currentStageLabel'] as String?) ?? '',
      currentStageDetail: (data['currentStageDetail'] as String?) ?? '',
      lastError: lastError,
      isActive: data['isActive'] == true,
      progressPercent: (data['progressPercent'] as String?) ?? '0%',
      aiModel: (data['aiModel'] as String?)?.trim() ?? '',
      recentLogs: ((data['recentLogs'] as List?) ?? const <Object?>[])
          .map((Object? value) => value?.toString() ?? '')
          .where((String value) => value.trim().isNotEmpty)
          .toList(growable: false),
      workers: ((data['workers'] as List?) ?? const <Object?>[])
          .map((Object? value) {
            if (value is Map) return DynamicRebuildWorkerState.fromMap(value);
            return const DynamicRebuildWorkerState(
              slotId: 0,
              status: DynamicRebuildWorkerStatus.idle,
              dayKey: '',
              totalSegments: 0,
              processedSegments: 0,
              currentRangeLabel: '',
              currentStageLabel: '',
              currentStageDetail: '',
              currentSegmentId: 0,
              retryCount: 0,
              retryLimit: 0,
              recentStreamChunks: <String>[],
            );
          })
          .where((DynamicRebuildWorkerState value) => value.slotId > 0)
          .toList(growable: false),
    );
  }

  static int _safeTaskInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int safeTaskInt(Object? value) => _safeTaskInt(value);

  bool get isIdle => status == 'idle' || taskId.isEmpty;
  bool get isPreparing => status == 'preparing';
  bool get isPending => status == 'pending';
  bool get isRunning => status == 'running';
  bool get isCompleted => status == 'completed';
  bool get isCompletedWithFailures => status == 'completed_with_failures';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get hasStageInfo =>
      currentStageLabel.trim().isNotEmpty ||
      currentStageDetail.trim().isNotEmpty;
  bool get canContinue {
    if (taskId.isEmpty || isActive || isIdle) {
      return false;
    }
    final bool hasRemainingDays =
        pendingDays > 0 || failedDays > 0 || completedDays < totalDays;
    final bool hasRemainingSegments =
        totalSegments > 0 && processedSegments < totalSegments;
    final bool canResumeFromPreparing =
        (isFailed || isCancelled || isCompletedWithFailures) &&
        totalSegments <= 0 &&
        totalDays <= 0;
    return hasRemainingDays || hasRemainingSegments || canResumeFromPreparing;
  }

  String toText() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('ScreenMemo 动态全量重建');
    sb.writeln('taskId: ${taskId.isEmpty ? '(none)' : taskId}');
    sb.writeln('status: $status');
    sb.writeln(
      'startedAt: ${startedAt > 0 ? _fmtTaskTime(startedAt) : '(null)'}',
    );
    sb.writeln(
      'updatedAt: ${updatedAt > 0 ? _fmtTaskTime(updatedAt) : '(null)'}',
    );
    sb.writeln(
      'completedAt: ${completedAt > 0 ? _fmtTaskTime(completedAt) : '(null)'}',
    );
    sb.writeln('dayConcurrency: $dayConcurrency');
    sb.writeln(
      'progress: $processedSegments/$totalSegments ($progressPercent)',
    );
    sb.writeln('failedSegments: $failedSegments');
    sb.writeln(
      'days: completed=$completedDays total=$totalDays pending=$pendingDays failed=$failedDays',
    );
    if (currentDayKey.isNotEmpty || currentRangeLabel.isNotEmpty) {
      sb.writeln(
        'current: ${[if (currentDayKey.isNotEmpty) currentDayKey, if (currentRangeLabel.isNotEmpty) currentRangeLabel].join(' / ')}',
      );
    }
    if (timelineCutoffDayKey.isNotEmpty) {
      sb.writeln('timelineCutoffDayKey: $timelineCutoffDayKey');
    }
    if (currentSegmentId > 0) {
      sb.writeln('currentSegmentId: $currentSegmentId');
    }
    if (currentStageLabel.trim().isNotEmpty) {
      sb.writeln('currentStage: $currentStageLabel');
    }
    if (currentStageDetail.trim().isNotEmpty) {
      sb.writeln('stageDetail: $currentStageDetail');
    }
    if (lastError != null) {
      sb.writeln('lastError: $lastError');
    }
    if (aiModel.trim().isNotEmpty) {
      sb.writeln('aiModel: $aiModel');
    }
    if (recentLogs.isNotEmpty) {
      sb.writeln('recentLogs:');
      for (final String line in recentLogs) {
        sb.writeln('- $line');
      }
    }
    if (workers.isNotEmpty) {
      sb.writeln('workers:');
      for (final DynamicRebuildWorkerState worker in workers) {
        sb.writeln(
          '- T${worker.slotId} ${worker.status} ${worker.dayKey} ${worker.processedSegments}/${worker.totalSegments} retry=${worker.retryCount}/${worker.retryLimit}',
        );
      }
    }
    return sb.toString().trimRight();
  }

  static String _fmtTaskTime(int millis) {
    return DateTime.fromMillisecondsSinceEpoch(millis).toString();
  }
}

class SegmentTimelineBatch {
  final List<Map<String, dynamic>> segments;
  final List<String> dayKeys;
  final bool hasMoreOlder;

  const SegmentTimelineBatch({
    required this.segments,
    required this.dayKeys,
    required this.hasMoreOlder,
  });
}

// 将 AI 配置、消息、会话、提供商与上下文相关方法拆分为扩展
extension ScreenshotDatabaseAI on ScreenshotDatabase {
  Future<void> _createAiProviderKeysTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_provider_keys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        provider_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        api_key TEXT NOT NULL,
        models_json TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        priority INTEGER NOT NULL DEFAULT 100,
        order_index INTEGER NOT NULL DEFAULT 0,
        failure_count INTEGER NOT NULL DEFAULT 0,
        cooldown_until_ms INTEGER,
        last_error_type TEXT,
        last_error_message TEXT,
        last_failed_at INTEGER,
        last_success_at INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_provider_keys_provider ON ai_provider_keys(provider_id, enabled, priority, order_index, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_provider_keys_cooldown ON ai_provider_keys(cooldown_until_ms)',
    );
  }

  Future<void> _migrateLegacyProviderKeys(DatabaseExecutor db) async {
    try {
      final providers = await db.query(
        'ai_providers',
        columns: ['id', 'api_key', 'models_json'],
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (final row in providers) {
        final int? providerId = row['id'] as int?;
        if (providerId == null) continue;
        final existing = await db.query(
          'ai_provider_keys',
          columns: ['id'],
          where: 'provider_id = ?',
          whereArgs: <Object?>[providerId],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final String key = ((row['api_key'] as String?) ?? '').trim();
        if (key.isEmpty) continue;
        await db.insert('ai_provider_keys', <String, Object?>{
          'provider_id': providerId,
          'name': 'Default key',
          'api_key': key,
          'models_json': (row['models_json'] as String?) ?? '[]',
          'enabled': 1,
          'priority': 100,
          'order_index': 0,
          'failure_count': 0,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (_) {}
  }

  Future<void> _createAiTables(DatabaseExecutor db) async {
    // ai_settings: 单行键值存储
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // ai_model_prompt_caps: 全局模型 prompt/context 上限（用户可覆盖）。
    // - provider-agnostic: 仅按 model_key 匹配，不绑定提供商
    // - model_key 建议存储为 trim + lowercase 的规范化值
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_model_prompt_caps (
        model_key TEXT PRIMARY KEY,
        model_display TEXT,
        prompt_cap_tokens INTEGER NOT NULL,
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_model_prompt_caps_updated ON ai_model_prompt_caps(updated_at DESC)',
    );
    // ai_messages: 简单会话历史（默认会话：conversation_id='default'）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        reasoning_content TEXT,
        reasoning_duration_ms INTEGER,
        ui_thinking_json TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_messages_conv ON ai_messages(conversation_id, id)',
    );

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
        -- Conversation context memory (Codex-style)
        summary TEXT,
        summary_updated_at INTEGER,
        summary_tokens INTEGER,
        compaction_count INTEGER NOT NULL DEFAULT 0,
        last_compaction_reason TEXT,
        tool_memory_json TEXT,
        tool_memory_updated_at INTEGER,
        last_prompt_tokens INTEGER,
        last_prompt_at INTEGER,
        last_prompt_breakdown_json TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_conversations_updated ON ai_conversations(updated_at DESC, pinned DESC, id DESC)',
    );

    // Full (append-only) transcript used for context compaction and recovery.
    // UI still reads from ai_messages tail; this table is for background context.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_messages_full (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_messages_full_conv ON ai_messages_full(conversation_id, id)',
    );

    // Raw prompt transcript (strict-full context): keeps cross-turn tool protocol
    // messages and multimodal/api-content fields for replay.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_messages_raw (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT,
        api_content_json TEXT,
        tool_calls_json TEXT,
        tool_call_id TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_messages_raw_conv ON ai_messages_raw(conversation_id, id)',
    );

    // Per-request prompt usage events (chat only): supports detailed timeline +
    // conversation cumulative statistics.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_prompt_usage_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        model TEXT,
        prompt_est_before INTEGER,
        prompt_est_sent INTEGER,
        usage_prompt_tokens INTEGER,
        usage_completion_tokens INTEGER,
        usage_total_tokens INTEGER,
        usage_source TEXT,
        is_tool_loop INTEGER NOT NULL DEFAULT 0,
        include_history INTEGER NOT NULL DEFAULT 1,
        tools_count INTEGER NOT NULL DEFAULT 0,
        strict_full_attempted INTEGER NOT NULL DEFAULT 0,
        fallback_triggered INTEGER NOT NULL DEFAULT 0,
        breakdown_json TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_prompt_usage_events_conv ON ai_prompt_usage_events(conversation_id, id)',
    );

    // Context/compaction diagnostics (lightweight rollout log).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_context_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        type TEXT NOT NULL,
        payload_json TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_context_events_conv ON ai_context_events(conversation_id, id)',
    );

    // SimpleMem-style atomic memories (facts/rules) for chat personalization.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_atomic_memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        kind TEXT NOT NULL,           -- fact | rule
        memory_key TEXT,              -- optional stable key for upserts (e.g. user.name)
        content TEXT NOT NULL,        -- atomic, lossless restatement
        content_hash TEXT NOT NULL,   -- stable hash for de-dup (computed in Dart)
        keywords_json TEXT,           -- optional JSON array of keywords
        confidence REAL,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_atomic_memories_conv ON ai_atomic_memories(conversation_id, updated_at DESC, id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_atomic_memories_kind ON ai_atomic_memories(conversation_id, kind, updated_at DESC, id DESC)',
    );
    try {
      await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS uniq_ai_atomic_memories_key ON ai_atomic_memories(conversation_id, memory_key) WHERE memory_key IS NOT NULL AND memory_key != ''",
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uniq_ai_atomic_memories_hash ON ai_atomic_memories(conversation_id, content_hash)',
      );
    } catch (_) {}
    await _createAtomicMemoriesFts(db);
    await _backfillAtomicMemoriesFts(db);

    // Global, cross-conversation user memory (profile + atomic facts/rules/habits + evidence).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_memory_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        user_markdown TEXT,
        auto_markdown TEXT,
        user_updated_at INTEGER,
        auto_updated_at INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_memory_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,           -- rule | fact | habit
        memory_key TEXT,              -- optional stable key for upserts (e.g. user.language)
        content TEXT NOT NULL,        -- atomic, durable restatement
        content_hash TEXT NOT NULL,   -- stable hash for de-dup (computed in Dart)
        keywords_json TEXT,           -- optional JSON array of keywords
        confidence REAL,
        pinned INTEGER NOT NULL DEFAULT 0,
        user_edited INTEGER NOT NULL DEFAULT 0,
        first_seen_at INTEGER,
        last_seen_at INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_memory_items_kind ON user_memory_items(kind, pinned DESC, updated_at DESC, id DESC)',
    );
    try {
      await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS uniq_user_memory_items_key ON user_memory_items(memory_key) WHERE memory_key IS NOT NULL AND TRIM(memory_key) != ''",
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uniq_user_memory_items_hash ON user_memory_items(content_hash)',
      );
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_memory_evidence (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        memory_item_id INTEGER NOT NULL,
        source_type TEXT NOT NULL,          -- segment | chat | daily_summary | weekly_summary | morning_insights
        source_id TEXT NOT NULL,            -- e.g. segment:123
        evidence_filenames_json TEXT,       -- optional JSON array of basenames (max ~5)
        start_time INTEGER,
        end_time INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(memory_item_id, source_type, source_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_memory_evidence_item ON user_memory_evidence(memory_item_id, created_at DESC, id DESC)',
    );

    await _createUserMemoryItemEventsTable(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_memory_index_state (
        source TEXT PRIMARY KEY,
        status TEXT NOT NULL,               -- idle | running | paused | error | done
        cursor_json TEXT,
        stats_json TEXT,
        started_at INTEGER,
        finished_at INTEGER,
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        error TEXT
      )
    ''');
    await _createUserMemoryItemsFts(db);
    await _backfillUserMemoryItemsFts(db);

    // 首次升级/创建时，将 ai_messages 中的会话ID迁移为显式会话条目，并初始化激活会话
    try {
      await _migrateLegacyConversations(db);
    } catch (_) {}

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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_providers_enabled ON ai_providers(enabled, order_index, id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_providers_name ON ai_providers(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_providers_default ON ai_providers(is_default)',
    );
    await _createAiProviderKeysTable(db);
    await _migrateLegacyProviderKeys(db);

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
        segment_kind TEXT NOT NULL DEFAULT 'global',
        app_packages TEXT,
        merge_attempted INTEGER NOT NULL DEFAULT 0,
        merged_flag INTEGER NOT NULL DEFAULT 0,
        merged_into_id INTEGER,
        merge_prev_id INTEGER,
        merge_decision_json TEXT,
        merge_decision_reason TEXT,
        merge_forced INTEGER NOT NULL DEFAULT 0,
        merge_decision_at INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segments_time ON segments(start_time, end_time)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segments_status_id_desc ON segments(status, id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segments_start_id_desc ON segments(start_time DESC, id DESC)',
    );
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_segments_merged_into ON segments(merged_into_id)',
      );
    } catch (_) {}

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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segment_samples_seg ON segment_samples(segment_id, position_index)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segment_samples_seg_pkg ON segment_samples(segment_id, app_package_name)',
    );

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
      try {
        FlutterLogger.nativeWarn('DB', 'FTS5（fts_content）不支持：' + e.toString());
      } catch (_) {}
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS segment_results (
        segment_id INTEGER PRIMARY KEY,
        ai_provider TEXT,
        ai_model TEXT,
        output_text TEXT,
        structured_json TEXT,
        categories TEXT,
        raw_request TEXT,
        raw_response TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    // AI 图片元数据表：按 file_path 存储标签/自然语言描述（可跨页面复用）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_image_meta (
        file_path TEXT PRIMARY KEY,
        tags_json TEXT,
        description TEXT,
        description_range TEXT,
        nsfw INTEGER NOT NULL DEFAULT 0,
        segment_id INTEGER,
        capture_time INTEGER,
        lang TEXT,
        updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_image_meta_nsfw ON ai_image_meta(nsfw, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_image_meta_updated ON ai_image_meta(updated_at DESC)',
    );
    await _createAiImageMetaFts(db);
    await _backfillAiImageMetaFts(db);
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
        "DELETE FROM ai_settings WHERE key IN ('base_url','api_key','model','active_group_id')",
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
      try {
        await db.delete('ai_settings', where: 'key = ?', whereArgs: [key]);
      } catch (_) {}
      return;
    }
    try {
      await db.execute(
        'INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)',
        [key, value],
      );
    } catch (_) {
      try {
        final count = await db.update(
          'ai_settings',
          {'value': value},
          where: 'key = ?',
          whereArgs: [key],
        );
        if (count == 0) {
          await db.insert('ai_settings', {'key': key, 'value': value});
        }
      } catch (_) {}
    }
  }

  // ===================== Model prompt-cap overrides =====================
  Future<int?> getAiModelPromptCapTokens(String modelKey) async {
    final String k = modelKey.trim().toLowerCase();
    if (k.isEmpty) return null;
    try {
      final db = await database;
      final rows = await db.query(
        'ai_model_prompt_caps',
        columns: <String>['prompt_cap_tokens'],
        where: 'model_key = ?',
        whereArgs: <Object?>[k],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final Object? v = rows.first['prompt_cap_tokens'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> setAiModelPromptCapTokens({
    required String modelKey,
    required int promptCapTokens,
    String? modelDisplay,
  }) async {
    final String k = modelKey.trim().toLowerCase();
    if (k.isEmpty) return;
    final int cap = promptCapTokens.clamp(256, 1 << 30);
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final db = await database;
      await db.execute(
        'INSERT OR REPLACE INTO ai_model_prompt_caps(model_key, model_display, prompt_cap_tokens, updated_at) VALUES(?, ?, ?, ?)',
        <Object?>[k, modelDisplay?.trim(), cap, now],
      );
    } catch (_) {}
  }

  Future<void> deleteAiModelPromptCapTokens(String modelKey) async {
    final String k = modelKey.trim().toLowerCase();
    if (k.isEmpty) return;
    try {
      final db = await database;
      await db.delete(
        'ai_model_prompt_caps',
        where: 'model_key = ?',
        whereArgs: <Object?>[k],
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAiMessages(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
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

  /// 按时间范围读取所有会话的 AI 消息（created_at 毫秒时间戳，按 created_at/id 升序）。
  ///
  /// 注意：部分历史数据 created_at 可能为空，这里会按 0 处理并被过滤掉。
  Future<List<Map<String, dynamic>>> getAiMessagesBetween({
    required int startMs,
    required int endMs,
    int? limit,
    int? offset,
  }) async {
    try {
      final db = await database;
      // SQLite 的 OFFSET 语法需要搭配 LIMIT；当仅提供 offset 时用 LIMIT -1。
      final bool hasLimit = limit != null;
      final bool hasOffset = offset != null;
      final String sql =
          '''
SELECT *
FROM ai_messages
WHERE COALESCE(created_at, 0) >= ?
  AND COALESCE(created_at, 0) < ?
ORDER BY created_at ASC, id ASC
${hasLimit ? 'LIMIT ?' : (hasOffset ? 'LIMIT -1' : '')}
${hasOffset ? 'OFFSET ?' : ''}
''';
      final List<dynamic> args = <dynamic>[
        startMs,
        endMs,
        if (limit != null) limit,
        if (offset != null) offset,
      ];
      final rows = await db.rawQuery(sql, args);
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 获取 ai_messages 中出现过的日期列表（按本地时区转换为 yyyy-MM-dd）。
  Future<List<String>> listAiMessageDays({int? startMs, int? endMs}) async {
    try {
      final db = await database;
      final String where = (startMs != null && endMs != null)
          ? 'WHERE COALESCE(created_at, 0) >= ? AND COALESCE(created_at, 0) < ?'
          : '';
      final List<dynamic> args = <dynamic>[
        if (startMs != null && endMs != null) ...<dynamic>[startMs, endMs],
      ];
      final rows = await db.rawQuery('''
SELECT DISTINCT date(COALESCE(created_at, 0) / 1000, 'unixepoch', 'localtime') AS day
FROM ai_messages
$where
ORDER BY day ASC
''', args);
      return rows
          .map((e) => (e['day'] as String?)?.trim() ?? '')
          .where((e) => e.isNotEmpty && e != '1970-01-01')
          .toList(growable: false);
    } catch (_) {
      return <String>[];
    }
  }

  /// 仅返回会话的“最新 N 条”消息，按 id DESC 读取后再倒序为升序返回
  Future<List<Map<String, dynamic>>> getAiMessagesTail(
    String conversationId, {
    int limit = 40,
  }) async {
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
      return rowsDesc.reversed
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// Fetch the persisted `ui_thinking_json` for a specific assistant message.
  ///
  /// We identify the message by (conversation_id, role='assistant', created_at)
  /// so background tool-loop updates can patch the same placeholder bubble even
  /// after the UI detached.
  Future<String?> getAiAssistantUiThinkingJson(
    String conversationId,
    int createdAtMs,
  ) async {
    final String cid = conversationId.trim();
    if (cid.isEmpty || createdAtMs <= 0) return null;
    try {
      final db = await database;
      final rows = await db.query(
        'ai_messages',
        columns: const <String>['ui_thinking_json'],
        where: 'conversation_id = ? AND role = ? AND created_at = ?',
        whereArgs: <Object?>[cid, 'assistant', createdAtMs],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final String? raw = rows.first['ui_thinking_json'] as String?;
      final String t = (raw ?? '').trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Update `ui_thinking_json` for a specific assistant message.
  ///
  /// Returns the number of updated rows.
  Future<int> updateAiAssistantUiThinkingJson(
    String conversationId,
    int createdAtMs,
    String uiThinkingJson,
  ) async {
    final String cid = conversationId.trim();
    final String raw = uiThinkingJson.trim();
    if (cid.isEmpty || createdAtMs <= 0 || raw.isEmpty) return 0;
    try {
      final db = await database;
      final int rows = await db.update(
        'ai_messages',
        <String, Object?>{'ui_thinking_json': raw},
        where: 'conversation_id = ? AND role = ? AND created_at = ?',
        whereArgs: <Object?>[cid, 'assistant', createdAtMs],
      );
      return rows;
    } catch (_) {
      return 0;
    }
  }

  Future<void> appendAiMessage(
    String conversationId,
    String role,
    String content, {
    int? createdAt,
    String? reasoningContent,
    int? reasoningDurationMs,
    String? uiThinkingJson,
  }) async {
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
        if (reasoningDurationMs != null)
          'reasoning_duration_ms': reasoningDurationMs,
        if (uiThinkingJson != null) 'ui_thinking_json': uiThinkingJson,
        if (createdAt != null) 'created_at': createdAt,
      });

      // 更新会话的最近更新时间
      try {
        await db.update(
          'ai_conversations',
          {'updated_at': now},
          where: 'cid = ?',
          whereArgs: [conversationId],
        );
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> clearAiConversation(String conversationId) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        try {
          await txn.delete(
            'ai_messages',
            where: 'conversation_id = ?',
            whereArgs: [conversationId],
          );
        } catch (_) {}
        // Conversation context system (v25): clear compacted memory + transcript + diagnostics.
        try {
          await txn.execute(
            'UPDATE ai_conversations SET summary = NULL, summary_updated_at = NULL, summary_tokens = NULL, compaction_count = 0, last_compaction_reason = NULL, tool_memory_json = NULL, tool_memory_updated_at = NULL, last_prompt_tokens = NULL, last_prompt_at = NULL, last_prompt_breakdown_json = NULL WHERE cid = ?',
            <Object?>[conversationId],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_messages_full',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[conversationId],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_messages_raw',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[conversationId],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_context_events',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[conversationId],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_prompt_usage_events',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[conversationId],
          );
        } catch (_) {}
      });
    } catch (_) {}
  }

  // ===================== 会话（Conversations）便捷方法 =====================
  Future<void> _migrateLegacyConversations(DatabaseExecutor exec) async {
    try {
      // 若已有会话条目：兜底写入激活键（直接使用 exec，避免递归打开 DB）
      final exists = await exec.query(
        'ai_conversations',
        columns: ['id'],
        limit: 1,
      );
      if (exists.isNotEmpty) {
        try {
          final activeRows = await exec.query(
            'ai_settings',
            columns: ['value'],
            where: 'key = ?',
            whereArgs: ['chat_active_cid'],
            limit: 1,
          );
          final hasActive =
              activeRows.isNotEmpty &&
              ((activeRows.first['value'] as String?)?.trim().isNotEmpty ==
                  true);
          if (!hasActive) {
            final r2 = await exec.query(
              'ai_conversations',
              columns: ['cid'],
              orderBy: 'pinned DESC, updated_at DESC, id DESC',
              limit: 1,
            );
            final cid = r2.isNotEmpty
                ? ((r2.first['cid'] as String?) ?? 'default')
                : 'default';
            await exec.execute(
              'INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)',
              ['chat_active_cid', cid],
            );
          }
        } catch (_) {}
        return;
      }

      // 从历史消息推断所有会话ID并生成会话条目
      List<Map<String, Object?>> mids = [];
      try {
        mids = await exec.rawQuery(
          'SELECT DISTINCT conversation_id AS cid FROM ai_messages',
        );
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
          await exec.execute(
            'INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)',
            ['chat_active_cid', 'default'],
          );
        } catch (_) {}
        return;
      }

      for (final m in mids) {
        final cid = (m['cid'] as String?) ?? 'default';
        final String title = (cid == 'default')
            ? '默认会话'
            : (cid.startsWith('group:')
                  ? ('模型会话 ' + cid.substring(6))
                  : ('会话 ' + cid));
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
        final r = await exec.query(
          'ai_conversations',
          columns: ['cid'],
          where: 'cid = ?',
          whereArgs: ['default'],
          limit: 1,
        );
        String cid;
        if (r.isNotEmpty) {
          cid = (r.first['cid'] as String?) ?? 'default';
        } else {
          final r2 = await exec.query(
            'ai_conversations',
            columns: ['cid'],
            orderBy: 'updated_at DESC, id DESC',
            limit: 1,
          );
          cid = r2.isNotEmpty
              ? ((r2.first['cid'] as String?) ?? 'default')
              : 'default';
        }
        await exec.execute(
          'INSERT OR REPLACE INTO ai_settings(key, value) VALUES(?, ?)',
          ['chat_active_cid', cid],
        );
      } catch (_) {}
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listAiConversations({
    int? limit,
    int? offset,
  }) async {
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
      final rows = await db.query(
        'ai_conversations',
        where: 'cid = ?',
        whereArgs: [cid],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  String _genConvCid() =>
      'c' + DateTime.now().millisecondsSinceEpoch.toString();

  Future<String> createAiConversation({
    String? title,
    int? providerId,
    String? model,
    String? cid,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final theCid = (cid == null || cid.trim().isEmpty)
        ? _genConvCid()
        : cid.trim();
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
        {
          'title': title.trim(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
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
        try {
          await txn.delete(
            'ai_messages',
            where: 'conversation_id = ?',
            whereArgs: [cid],
          );
        } catch (_) {}
        swMsg.stop();
        final swCtx = Stopwatch()..start();
        try {
          await txn.delete(
            'ai_messages_full',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[cid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_messages_raw',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[cid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_context_events',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[cid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_prompt_usage_events',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[cid],
          );
        } catch (_) {}
        swCtx.stop();
        final swConv = Stopwatch()..start();
        await txn.delete(
          'ai_conversations',
          where: 'cid = ?',
          whereArgs: [cid],
        );
        swConv.stop();
        try {
          await FlutterLogger.nativeInfo(
            'DB',
            'deleteAiConversation 事务耗时(毫秒)：msg=' +
                swMsg.elapsedMilliseconds.toString() +
                ' ctx=' +
                swCtx.elapsedMilliseconds.toString() +
                ' conv=' +
                swConv.elapsedMilliseconds.toString(),
          );
        } catch (_) {}
      });
      swTotal.stop();
      try {
        await FlutterLogger.nativeInfo(
          'DB',
          'deleteAiConversation 总耗时(毫秒)=' +
              swTotal.elapsedMilliseconds.toString() +
              ' cid=' +
              cid,
        );
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> touchAiConversation(String cid) async {
    final db = await database;
    try {
      await db.update(
        'ai_conversations',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'cid = ?',
        whereArgs: [cid],
      );
    } catch (_) {}
  }

  // ===================== AI 提供商（Providers）便捷方法 =====================
  Future<List<Map<String, dynamic>>> listAIProviders() async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_providers',
        orderBy: 'enabled DESC, order_index ASC, id ASC',
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getAIProviderById(int id) async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_providers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
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

      if (isDefault) {
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
      if (useResponseApi != null)
        data['use_response_api'] = useResponseApi ? 1 : 0;
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

      final count = await db.update(
        'ai_providers',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
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
      final count = await db.delete(
        'ai_providers',
        where: 'id = ?',
        whereArgs: [id],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDefaultAIProvider(int id) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        await txn.update('ai_providers', {
          'is_default': 0,
        }, where: 'is_default = 1');
        await txn.update(
          'ai_providers',
          {'is_default': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDefaultAIProvider() async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_providers',
        where: 'is_default = 1',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveAIProviderModelsJson({
    required int id,
    required String modelsJson,
  }) async {
    final db = await database;
    try {
      final count = await db.update(
        'ai_providers',
        {'models_json': modelsJson},
        where: 'id = ?',
        whereArgs: [id],
      );
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
        {
          'api_key': (apiKey == null || apiKey.trim().isEmpty)
              ? null
              : apiKey.trim(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  // ===================== AI 上下文选中（chat / segments） =====================

  Future<int> cleanupExpiredRawResponses({
    required int cutoffMs,
    bool includeMorningInsights = true,
  }) async {
    final db = await database;
    int total = 0;
    Future<void> clearTable(String table, String column) async {
      try {
        total += await db.update(
          table,
          <String, Object?>{column: null},
          where: 'created_at < ? AND $column IS NOT NULL',
          whereArgs: <Object?>[cutoffMs],
        );
      } catch (_) {}
    }

    await clearTable('segment_results', 'raw_response');
    if (includeMorningInsights) {
      await clearTable('morning_insights', 'raw_response');
    }
    try {
      total += await db.delete(
        'ai_messages_raw',
        where: 'created_at < ?',
        whereArgs: <Object?>[cutoffMs],
      );
    } catch (_) {}
    return total;
  }

  Future<List<Map<String, dynamic>>> listAIProviderKeys(int providerId) async {
    final db = await database;
    try {
      return await db.query(
        'ai_provider_keys',
        where: 'provider_id = ?',
        whereArgs: <Object?>[providerId],
        orderBy: 'enabled DESC, priority ASC, order_index ASC, id ASC',
      );
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getAIProviderKeyById(int id) async {
    final db = await database;
    try {
      final rows = await db.query(
        'ai_provider_keys',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<int?> insertAIProviderKey({
    required int providerId,
    required String name,
    required String apiKey,
    String? modelsJson,
    bool enabled = true,
    int priority = 100,
    int? orderIndex,
  }) async {
    final db = await database;
    try {
      return await db.insert('ai_provider_keys', <String, Object?>{
        'provider_id': providerId,
        'name': name.trim(),
        'api_key': apiKey.trim(),
        'models_json': modelsJson ?? '[]',
        'enabled': enabled ? 1 : 0,
        'priority': priority,
        'order_index': orderIndex ?? 0,
        'failure_count': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateAIProviderKey({
    required int id,
    String? name,
    String? apiKey,
    String? modelsJson,
    bool? enabled,
    int? priority,
    int? orderIndex,
    bool clearErrorState = false,
  }) async {
    final db = await database;
    try {
      final data = <String, Object?>{};
      if (name != null) data['name'] = name.trim();
      if (apiKey != null) data['api_key'] = apiKey.trim();
      if (modelsJson != null) data['models_json'] = modelsJson;
      if (enabled != null) data['enabled'] = enabled ? 1 : 0;
      if (priority != null) data['priority'] = priority;
      if (orderIndex != null) data['order_index'] = orderIndex;
      if (clearErrorState) {
        data['failure_count'] = 0;
        data['cooldown_until_ms'] = null;
        data['last_error_type'] = null;
        data['last_error_message'] = null;
        data['last_failed_at'] = null;
      }
      if (data.isEmpty) return (await getAIProviderKeyById(id)) != null;
      final count = await db.update(
        'ai_provider_keys',
        data,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return count > 0 || (await getAIProviderKeyById(id)) != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteAIProviderKey(int id) async {
    final db = await database;
    try {
      final count = await db.delete(
        'ai_provider_keys',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> markAIProviderKeySuccess(int keyId) async {
    final db = await database;
    try {
      await db.update(
        'ai_provider_keys',
        <String, Object?>{
          'failure_count': 0,
          'cooldown_until_ms': null,
          'last_error_type': null,
          'last_error_message': null,
          'last_failed_at': null,
          'last_success_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[keyId],
      );
    } catch (_) {}
  }

  Future<void> markAIProviderKeyFailure({
    required int keyId,
    required String errorType,
    required String errorMessage,
    bool incrementFailure = true,
    int? cooldownUntilMs,
    bool resetFailureCount = false,
  }) async {
    final db = await database;
    try {
      final row = await getAIProviderKeyById(keyId);
      final int current = (row?['failure_count'] as int?) ?? 0;
      final int nextCount = resetFailureCount
          ? 0
          : (incrementFailure ? current + 1 : current);
      await db.update(
        'ai_provider_keys',
        <String, Object?>{
          'failure_count': nextCount,
          'cooldown_until_ms': cooldownUntilMs,
          'last_error_type': errorType,
          'last_error_message': errorMessage.length > 1000
              ? errorMessage.substring(0, 1000)
              : errorMessage,
          'last_failed_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[keyId],
      );
    } catch (_) {}
  }

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
      await db.execute(
        '''
        INSERT INTO ai_contexts (context, provider_id, model, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(context) DO UPDATE SET
          provider_id = excluded.provider_id,
          model = excluded.model,
          updated_at = excluded.updated_at
      ''',
        [context, providerId, model, DateTime.now().millisecondsSinceEpoch],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ======= 段落查询接口 =======
  /// Root segments are those not merged into another segment.
  ///
  /// Historical/edge cases we need to tolerate:
  /// - Some DBs may store "no merged target" as 0 instead of NULL.
  /// - Users may delete a root segment, leaving children with a stale merged_into_id.
  ///   In that case we treat those rows as roots again so the UI/search won't go empty.
  String _segmentsRootWhere([String? alias]) {
    final String p = (alias == null || alias.isEmpty) ? '' : '$alias.';
    return '(${p}merged_into_id IS NULL OR ${p}merged_into_id <= 0 OR NOT EXISTS (SELECT 1 FROM segments t WHERE t.id = ${p}merged_into_id))';
  }

  Future<Map<String, dynamic>?> getActiveSegment() async {
    final db = await database;
    try {
      // 兜底：若某段已产出总结（segment_results 有内容）但 status 仍是 collecting，
      // 不应在 UI 顶部继续显示“进行中”（常见于原生链路合并/网络卡住导致状态未及时落库）。
      // Avoid LOWER(TRIM(..)) on large TEXT values; it can be very expensive and may OOM on some devices.
      const String noSummaryCond =
          "r.segment_id IS NULL OR ((r.output_text IS NULL OR (LENGTH(r.output_text) <= 256 AND LOWER(TRIM(r.output_text)) IN ('','null'))) AND (r.structured_json IS NULL OR (LENGTH(r.structured_json) <= 256 AND LOWER(TRIM(r.structured_json)) IN ('','null'))))";
      final rows = await db.rawQuery(
        '''
        SELECT s.*
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        WHERE s.status = ?
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND ($noSummaryCond)
        ORDER BY s.id DESC
        LIMIT 1
        ''',
        ['collecting'],
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listSegments({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segments',
        where:
            "${_segmentsRootWhere()} AND (segment_kind IS NULL OR segment_kind = 'global')",
        orderBy: 'id DESC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<SegmentTimelineBatch> listSegmentTimelineBatch({
    required int distinctDayCount,
    String? beforeDateKey,
    String? pinnedDateKey,
    String? maxDateKeyInclusive,
    bool requireSamples = true,
  }) async {
    final db = await database;
    final int safeDayCount = math.max(1, distinctDayCount);
    final String beforeKey = (beforeDateKey ?? '').trim();
    final String pinnedKey = (pinnedDateKey ?? '').trim();
    final String maxKeyInclusive = (maxDateKeyInclusive ?? '').trim();
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
    const String dayExpr =
        "date(s.start_time / 1000, 'unixepoch', 'localtime')";

    List<String> buildWhereClauses({
      String? beforeKey,
      String? exactKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      String? olderThanKey,
    }) {
      final List<String> whereClauses = <String>[
        _segmentsRootWhere('s'),
        "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
      ];
      if (requireSamples) {
        whereClauses.add(hasSamplesCond);
      }
      final String before = (beforeKey ?? '').trim();
      if (before.isNotEmpty) {
        whereClauses.add("$dayExpr < ?");
      }
      final String exact = (exactKey ?? '').trim();
      if (exact.isNotEmpty) {
        whereClauses.add("$dayExpr = ?");
      }
      final String minKey = (minKeyInclusive ?? '').trim();
      if (minKey.isNotEmpty) {
        whereClauses.add("$dayExpr >= ?");
      }
      final String maxKey = (maxKeyInclusive ?? '').trim();
      if (maxKey.isNotEmpty) {
        whereClauses.add("$dayExpr <= ?");
      }
      final String olderThan = (olderThanKey ?? '').trim();
      if (olderThan.isNotEmpty) {
        whereClauses.add("$dayExpr < ?");
      }
      return whereClauses;
    }

    List<Object?> buildWhereParams({
      String? beforeKey,
      String? exactKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      String? olderThanKey,
    }) {
      final List<Object?> whereParams = <Object?>[];
      final String before = (beforeKey ?? '').trim();
      if (before.isNotEmpty) {
        whereParams.add(before);
      }
      final String exact = (exactKey ?? '').trim();
      if (exact.isNotEmpty) {
        whereParams.add(exact);
      }
      final String minKey = (minKeyInclusive ?? '').trim();
      if (minKey.isNotEmpty) {
        whereParams.add(minKey);
      }
      final String maxKey = (maxKeyInclusive ?? '').trim();
      if (maxKey.isNotEmpty) {
        whereParams.add(maxKey);
      }
      final String olderThan = (olderThanKey ?? '').trim();
      if (olderThan.isNotEmpty) {
        whereParams.add(olderThan);
      }
      return whereParams;
    }

    Future<List<String>> queryDayKeys({
      String? beforeKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      required int limit,
    }) async {
      final List<String> whereClauses = buildWhereClauses(
        beforeKey: beforeKey,
        minKeyInclusive: minKeyInclusive,
        maxKeyInclusive: maxKeyInclusive,
      );
      final List<Object?> whereParams = buildWhereParams(
        beforeKey: beforeKey,
        minKeyInclusive: minKeyInclusive,
        maxKeyInclusive: maxKeyInclusive,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery(
        '''
        SELECT day_key
        FROM (
          SELECT DISTINCT $dayExpr AS day_key
          FROM segments s
          $whereSql
        )
        ORDER BY day_key DESC
        LIMIT ?
        ''',
        <Object?>[...whereParams, limit],
      );
      return rows
          .map((Map<String, Object?> row) => (row['day_key'] as String?) ?? '')
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);
    }

    Future<bool> dayKeyExists(String dateKey) async {
      final String normalized = dateKey.trim();
      if (normalized.isEmpty) return false;
      final List<String> whereClauses = buildWhereClauses(
        exactKey: normalized,
        maxKeyInclusive: maxKeyInclusive,
      );
      final List<Object?> whereParams = buildWhereParams(
        exactKey: normalized,
        maxKeyInclusive: maxKeyInclusive,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT 1
        FROM segments s
        $whereSql
        LIMIT 1
        ''', whereParams);
      return rows.isNotEmpty;
    }

    Future<bool> hasOlderThan(String dateKey) async {
      final String normalized = dateKey.trim();
      if (normalized.isEmpty) return false;
      final List<String> whereClauses = buildWhereClauses(
        maxKeyInclusive: maxKeyInclusive,
        olderThanKey: normalized,
      );
      final List<Object?> whereParams = buildWhereParams(
        maxKeyInclusive: maxKeyInclusive,
        olderThanKey: normalized,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT 1
        FROM (
          SELECT DISTINCT $dayExpr AS day_key
          FROM segments s
          $whereSql
        )
        LIMIT 1
        ''', whereParams);
      return rows.isNotEmpty;
    }

    if (maxKeyInclusive.isEmpty && maxDateKeyInclusive != null) {
      return const SegmentTimelineBatch(
        segments: <Map<String, dynamic>>[],
        dayKeys: <String>[],
        hasMoreOlder: false,
      );
    }

    List<String> dayKeys = await queryDayKeys(
      beforeKey: beforeKey,
      maxKeyInclusive: maxKeyInclusive,
      limit: safeDayCount,
    );
    if (dayKeys.isEmpty) {
      return const SegmentTimelineBatch(
        segments: <Map<String, dynamic>>[],
        dayKeys: <String>[],
        hasMoreOlder: false,
      );
    }

    if (beforeKey.isEmpty &&
        pinnedKey.isNotEmpty &&
        !dayKeys.contains(pinnedKey)) {
      final bool pinnedExists = await dayKeyExists(pinnedKey);
      if (pinnedExists) {
        final List<String> expanded = await queryDayKeys(
          minKeyInclusive: pinnedKey,
          maxKeyInclusive: maxKeyInclusive,
          limit: 1 << 20,
        );
        if (expanded.isNotEmpty) {
          dayKeys = expanded;
        }
      }
    }

    final String newestDayKey = dayKeys.first;
    final String oldestDayKey = dayKeys.last;
    final int? oldestStartMillis = _parseYmdToStartMillis(oldestDayKey);
    final int? newestStartMillis = _parseYmdToStartMillis(newestDayKey);
    if (oldestStartMillis == null || newestStartMillis == null) {
      return const SegmentTimelineBatch(
        segments: <Map<String, dynamic>>[],
        dayKeys: <String>[],
        hasMoreOlder: false,
      );
    }
    final int newestEndMillis =
        DateTime.fromMillisecondsSinceEpoch(
          newestStartMillis,
        ).add(const Duration(days: 1)).millisecondsSinceEpoch -
        1;
    final List<Map<String, dynamic>> segments = await listSegmentsEx(
      limit: 1 << 30,
      onlyNoSummary: false,
      requireSamples: requireSamples,
      startMillis: oldestStartMillis,
      endMillis: newestEndMillis,
    );
    final bool hasMoreOlder = await hasOlderThan(oldestDayKey);
    return SegmentTimelineBatch(
      segments: segments,
      dayKeys: dayKeys,
      hasMoreOlder: hasMoreOlder,
    );
  }

  Future<List<Map<String, dynamic>>> _attachSegmentSampleStats(
    Database db,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;

    final List<int> segmentIds = <int>[];
    final Set<int> seenSegmentIds = <int>{};
    for (final Map<String, dynamic> row in rows) {
      final int segmentId = ((row['id'] as num?) ?? 0).toInt();
      if (segmentId > 0 && seenSegmentIds.add(segmentId)) {
        segmentIds.add(segmentId);
      }
    }

    final Map<int, int> sampleCountBySegmentId = <int, int>{};
    final Map<int, String> appPackagesBySegmentId = <int, String>{};
    if (segmentIds.isNotEmpty) {
      try {
        const int chunkSize = 400;
        for (int i = 0; i < segmentIds.length; i += chunkSize) {
          final int end = (i + chunkSize) > segmentIds.length
              ? segmentIds.length
              : (i + chunkSize);
          final List<int> chunk = segmentIds.sublist(i, end);
          final String placeholders = List.filled(chunk.length, '?').join(',');
          final List<Map<String, Object?>> statsRows = await db.rawQuery('''
            SELECT
              segment_id,
              COUNT(*) AS sample_count,
              GROUP_CONCAT(DISTINCT app_package_name) AS app_packages_display
            FROM segment_samples
            WHERE segment_id IN ($placeholders)
            GROUP BY segment_id
            ''', chunk);
          for (final Map<String, Object?> item in statsRows) {
            final int segmentId = ((item['segment_id'] as num?) ?? 0).toInt();
            if (segmentId <= 0) continue;
            sampleCountBySegmentId[segmentId] =
                ((item['sample_count'] as num?) ?? 0).toInt();
            final String appPackages =
                ((item['app_packages_display'] as String?) ?? '').trim();
            if (appPackages.isNotEmpty) {
              appPackagesBySegmentId[segmentId] = appPackages;
            }
          }
        }
      } catch (e) {
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'attachSegmentSampleStats failed err=${e.toString()} rows=${rows.length}',
          );
        } catch (_) {}
      }
    }

    for (final Map<String, dynamic> row in rows) {
      final int segmentId = ((row['id'] as num?) ?? 0).toInt();
      final String appPackages = ((row['app_packages'] as String?) ?? '')
          .trim();
      final String aggregatedPackages =
          (appPackagesBySegmentId[segmentId] ?? '').trim();
      row['sample_count'] = sampleCountBySegmentId[segmentId] ?? 0;
      final String appPackagesDisplay = appPackages.isNotEmpty
          ? appPackages
          : aggregatedPackages;
      row['app_packages_display'] = appPackagesDisplay.isEmpty
          ? null
          : appPackagesDisplay;
    }
    return rows;
  }

  /// 列出段落（带是否有总结标记），可选仅返回“无总结”的事件
  /// - has_summary: 0 表示无总结；1 表示已有总结
  /// - 默认仅返回“至少有一张样本图片”的事件（避免前端渲染后再隐藏导致滚动抖动）
  ///   - requireSamples=false 时允许返回“样本数为 0”的段落（用于故障排查/降级展示）
  /// - 可选按 start_time 进行时间范围过滤（用于“动态”页按日期窗口增量加载）
  /// - 可选按 appPackageName / appPackageNames 过滤（按 segment_samples.app_package_name）。
  Future<List<Map<String, dynamic>>> listSegmentsEx({
    int limit = 50,
    int offset = 0,
    bool onlyNoSummary = false,
    bool requireSamples = true,
    int? startMillis,
    int? endMillis,
    List<String>? appPackageNames,
    String? appPackageName,
  }) async {
    final db = await database;
    int safeOffset = offset;
    if (safeOffset < 0) safeOffset = 0;

    // Avoid LOWER(TRIM(..)) on huge TEXT blobs (can cause CursorWindow/oom when scanning many rows).
    const String noSummaryCond =
        "r.segment_id IS NULL OR ((r.output_text IS NULL OR (LENGTH(r.output_text) <= 256 AND LOWER(TRIM(r.output_text)) IN ('','null'))) AND (r.structured_json IS NULL OR (LENGTH(r.structured_json) <= 256 AND LOWER(TRIM(r.structured_json)) IN ('','null'))))";
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";

    // 组合 WHERE 子句
    final List<String> whereClauses = <String>[
      _segmentsRootWhere('s'),
      "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
    ];
    final List<Object?> whereParams = <Object?>[];

    List<String> pkgs = (appPackageNames ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (pkgs.isEmpty) {
      final String single = (appPackageName ?? '').trim();
      if (single.isNotEmpty) pkgs = <String>[single];
    }
    pkgs.sort();
    if (pkgs.length > 30) {
      pkgs = pkgs.take(30).toList(growable: false);
    }

    if (pkgs.isNotEmpty) {
      final String placeholders = List.filled(pkgs.length, '?').join(',');
      whereClauses.add(
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id AND ss.app_package_name IN ($placeholders))",
      );
      whereParams.addAll(pkgs);
    } else if (requireSamples) {
      whereClauses.add(hasSamplesCond);
    }

    if (startMillis != null) {
      whereClauses.add('s.start_time >= ?');
      whereParams.add(startMillis);
    }
    if (endMillis != null) {
      whereClauses.add('s.start_time <= ?');
      whereParams.add(endMillis);
    }
    if (onlyNoSummary) {
      whereClauses.add('(' + noSummaryCond + ')');
    }

    final String whereSql = whereClauses.isEmpty
        ? ''
        : ('WHERE ' + whereClauses.join(' AND '));

    final String sql =
        '''
        SELECT
          s.*,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        $whereSql
        ORDER BY s.start_time DESC, s.id DESC
        LIMIT ? OFFSET ?
      ''';

    try {
      final List<Object?> params = <Object?>[...whereParams, limit, safeOffset];
      final rows = await db.rawQuery(sql, params);
      return _attachSegmentSampleStats(
        db,
        rows.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    } catch (e) {
      try {
        await FlutterLogger.nativeError(
          'DB',
          'listSegmentsEx failed err=${e.toString()} onlyNoSummary=$onlyNoSummary requireSamples=$requireSamples startMillis=${startMillis?.toString() ?? 'null'} endMillis=${endMillis?.toString() ?? 'null'} limit=$limit offset=$offset',
        );
      } catch (_) {}

      // Fallback: Some Android devices/DB states can hit CursorWindow/row-too-big errors when
      // selecting large TEXT columns (output_text / structured_json) across many rows.
      // Retry with truncated result columns so the timeline won't go empty.
      try {
        const int maxOutputTextChars = 4096;
        const int maxStructuredJsonChars = 204800;
        const int maxCategoriesChars = 4096;
        final String fallbackSql =
            '''
        SELECT
          s.*,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary,
          SUBSTR(r.output_text, 1, ?) AS output_text,
          CASE
            WHEN r.structured_json IS NULL THEN NULL
            -- Small JSON blobs are safe to return whole (keeps key_actions/image_tags usable on UI).
            WHEN LENGTH(r.structured_json) <= ? THEN r.structured_json
            -- For large JSON, return a window around overall_summary so the timeline can still show the summary
            -- without fetching megabytes into CursorWindow.
            ELSE SUBSTR(
              r.structured_json,
              MAX(1, INSTR(r.structured_json, '"overall_summary"')),
              ?
            )
          END AS structured_json,
          SUBSTR(r.categories, 1, ?) AS categories,
          CASE WHEN r.output_text IS NOT NULL AND LENGTH(r.output_text) > ? THEN 1 ELSE 0 END AS output_text_truncated,
          CASE WHEN r.structured_json IS NOT NULL AND LENGTH(r.structured_json) > ? THEN 1 ELSE 0 END AS structured_json_truncated,
          CASE WHEN r.categories IS NOT NULL AND LENGTH(r.categories) > ? THEN 1 ELSE 0 END AS categories_truncated
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        $whereSql
        ORDER BY s.start_time DESC, s.id DESC
        LIMIT ? OFFSET ?
      ''';

        final List<Object?> fallbackParams = <Object?>[
          // Placeholders appear in SELECT first (SUBSTR), then WHERE, then LIMIT/OFFSET.
          maxOutputTextChars,
          maxStructuredJsonChars,
          maxStructuredJsonChars,
          maxCategoriesChars,
          maxOutputTextChars,
          maxStructuredJsonChars,
          maxCategoriesChars,
          ...whereParams,
          limit,
          safeOffset,
        ];
        final rows = await db.rawQuery(fallbackSql, fallbackParams);
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'listSegmentsEx fallback used (truncated result columns) limit=$limit offset=$offset',
          );
        } catch (_) {}
        return _attachSegmentSampleStats(
          db,
          rows.map((e) => Map<String, dynamic>.from(e)).toList(),
        );
      } catch (e2) {
        try {
          await FlutterLogger.nativeError(
            'DB',
            'listSegmentsEx fallback failed err=${e2.toString()}',
          );
        } catch (_) {}
        return <Map<String, dynamic>>[];
      }
    }
  }

  /// 触发一次原生端的段落推进/补救扫描（用于点击刷新时重试缺失总结）
  Future<bool> triggerSegmentTick() async {
    try {
      try {
        await FlutterLogger.nativeInfo('DB', 'triggerSegmentTick 调用');
      } catch (_) {}
      final res = await ScreenshotDatabase._channel.invokeMethod(
        'triggerSegmentTick',
      );
      try {
        await FlutterLogger.nativeInfo(
          'DB',
          'triggerSegmentTick 结果=${res == true} raw=${res?.toString() ?? 'null'}',
        );
      } catch (_) {}
      return res == true;
    } catch (e) {
      try {
        await FlutterLogger.nativeError(
          'DB',
          'triggerSegmentTick 失败 err=${e.toString()}',
        );
      } catch (_) {}
      return false;
    }
  }

  Future<bool> getDynamicAutoRepairEnabled() async {
    try {
      final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
        'getDynamicAutoRepairEnabled',
      );
      return raw == null ? true : raw == true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> setDynamicAutoRepairEnabled(bool enabled) async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'setDynamicAutoRepairEnabled',
      <String, dynamic>{'enabled': enabled},
    );
    return raw == null ? enabled : raw == true;
  }

  /// 通过原生接口按ID批量重试生成总结
  /// force=true 时无视已有结果与时间范围，直接强制重跑
  Future<int> retrySegments(List<int> ids, {bool force = false}) async {
    try {
      final res = await ScreenshotDatabase._channel.invokeMethod(
        'retrySegments',
        {'ids': ids, 'force': force},
      );
      if (res is int) return res;
      if (res is num) return res.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<DynamicRebuildTaskStatus> startDynamicRebuildTask({
    bool resumeExisting = false,
    int dayConcurrency = 1,
  }) async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'startDynamicRebuildTask',
      <String, dynamic>{
        'resumeExisting': resumeExisting,
        'dayConcurrency': dayConcurrency,
      },
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  Future<DynamicRebuildTaskStatus> getDynamicRebuildTaskStatus() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'getDynamicRebuildTaskStatus',
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  Future<DynamicRebuildTaskStatus> ensureDynamicRebuildTaskResumed() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'ensureDynamicRebuildTaskResumed',
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  Future<DynamicRebuildTaskStatus> cancelDynamicRebuildTask() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'cancelDynamicRebuildTask',
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  /// 供“记忆重建”使用的轻量段落列表（避免拉取 segment_results 的大字段）。
  ///
  /// - 默认按 start_time DESC 排序（与“动态”一致）。
  /// - requireSamples=true 时只返回至少有一张样本的段落；false 时允许无图段落（由上层跳过）。
  Future<List<Map<String, dynamic>>> listSegmentsForMemoryRebuild({
    int limit = 200,
    int offset = 0,
    bool requireSamples = true,
    int? startMillis,
    int? endMillis,
  }) async {
    final db = await database;
    int safeOffset = offset;
    if (safeOffset < 0) safeOffset = 0;

    final List<String> whereClauses = <String>[
      _segmentsRootWhere('s'),
      "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
    ];
    final List<Object?> whereParams = <Object?>[];

    if (requireSamples) {
      whereClauses.add(
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)",
      );
    }
    if (startMillis != null) {
      whereClauses.add('s.start_time >= ?');
      whereParams.add(startMillis);
    }
    if (endMillis != null) {
      whereClauses.add('s.start_time <= ?');
      whereParams.add(endMillis);
    }

    final String whereSql = whereClauses.isEmpty
        ? ''
        : ('WHERE ' + whereClauses.join(' AND '));

    final String sql =
        '''
        SELECT
          s.id AS id,
          s.start_time AS start_time,
          s.end_time AS end_time,
          (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count,
          COALESCE(
            NULLIF(TRIM(s.app_packages), ''),
            (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
          ) AS app_packages_display
        FROM segments s
        $whereSql
        ORDER BY s.start_time ASC, s.id ASC
        LIMIT ? OFFSET ?
      ''';

    try {
      final List<Object?> params = <Object?>[...whereParams, limit, safeOffset];
      final rows = await db.rawQuery(sql, params);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 强制将某个事件与其上一事件合并（跳过 same_event 判定，直接执行合并总结）
  /// - prevId 可选：指定要合并的上一事件ID（否则由原生侧自动选择）
  Future<bool> forceMergeSegment(int id, {int? prevId}) async {
    try {
      final res = await ScreenshotDatabase._channel.invokeMethod(
        'forceMergeSegment',
        {'id': id, if (prevId != null && prevId > 0) 'prev_id': prevId},
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listSegmentSamples(int segmentId) async {
    final db = await database;
    try {
      final String sql = '''
        SELECT
          s.id,
          s.segment_id,
          s.capture_time,
          s.file_path,
          s.app_package_name,
          s.app_name,
          s.position_index,
          totals.appearance_count,
          totals.appearance_count AS segment_occurrence_count,
          totals.distinct_day_count,
          totals.distinct_day_count AS cross_day_count
        FROM segment_samples s
        JOIN (
          SELECT
            segment_id,
            COUNT(*) AS appearance_count,
            COUNT(
              DISTINCT strftime(
                '%Y-%m-%d',
                datetime(capture_time / 1000, 'unixepoch', 'localtime')
              )
            ) AS distinct_day_count
          FROM segment_samples
          WHERE segment_id = ?
          GROUP BY segment_id
        ) totals ON totals.segment_id = s.segment_id
        WHERE s.segment_id = ?
        ORDER BY s.position_index ASC
      ''';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ${sql.replaceAll('?', segmentId.toString())}',
        );
      } catch (_) {}
      final List<Map<String, Object?>> rows = await db.rawQuery(sql, <Object?>[
        segmentId,
        segmentId,
      ]);
      return rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
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
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 列出某个 segment 内最新的 N 条样本（按 capture_time DESC）。
  Future<List<Map<String, dynamic>>> listLatestSamplesInSegment(
    int segmentId, {
    int limit = 1000,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segment_samples',
        where: 'segment_id = ?',
        whereArgs: <Object?>[segmentId],
        orderBy: 'capture_time DESC, id DESC',
        limit: limit,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getSegmentResult(int segmentId) async {
    final db = await database;
    try {
      final String sql =
          'SELECT segment_id, ai_provider, ai_model, output_text, structured_json, categories, created_at FROM segment_results WHERE segment_id = ? LIMIT 1';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ' + sql.replaceAll('?', segmentId.toString()),
        );
      } catch (_) {}
      final rows = await db.query(
        'segment_results',
        where: 'segment_id = ?',
        whereArgs: [segmentId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  // ===================== AI 图片元数据（全局复用） =====================

  Future<Map<String, dynamic>?> getAiImageMetaByFilePath(
    String filePath,
  ) async {
    final String p = filePath.trim();
    if (p.isEmpty) return null;
    final db = await database;
    try {
      final rows = await db.query(
        'ai_image_meta',
        where: 'file_path = ?',
        whereArgs: <Object?>[p],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// 批量查询 AI 图片元数据（key=file_path）。
  ///
  /// - 内部会自动去重与分批，避免 SQLite 参数上限。
  Future<Map<String, Map<String, dynamic>>> getAiImageMetaByFilePaths(
    List<String> filePaths,
  ) async {
    final List<String> paths = filePaths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (paths.isEmpty) return <String, Map<String, dynamic>>{};

    final db = await database;
    final Map<String, Map<String, dynamic>> out =
        <String, Map<String, dynamic>>{};

    // SQLite 参数默认上限 999，这里保守分批。
    const int chunkSize = 400;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final int end = (i + chunkSize) > paths.length
          ? paths.length
          : (i + chunkSize);
      final List<String> chunk = paths.sublist(i, end);
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final List<Map<String, Object?>> rows = await db.query(
        'ai_image_meta',
        where: 'file_path IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final r in rows) {
        final String? fp = r['file_path'] as String?;
        if (fp == null || fp.isEmpty) continue;
        out[fp] = Map<String, dynamic>.from(r);
      }
    }
    return out;
  }

  /// 批量查询“动态（segment）里标记为 NSFW”的截图文件路径集合。
  ///
  /// 说明：
  /// - 用于把“动态里的 NSFW 标签”传播到全局（截图列表/时间线/搜索）。
  /// - 仅返回命中 NSFW 的 file_path 集合；未命中的 file_path 视为“非 NSFW”。
  Future<Set<String>> getSegmentNsfwFilePaths(List<String> filePaths) async {
    final List<String> paths = filePaths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (paths.isEmpty) return <String>{};

    final db = await database;

    String basenameOf(String path) {
      final normalized = path.trim().replaceAll('\\', '/');
      final int idx = normalized.lastIndexOf('/');
      return idx >= 0 ? normalized.substring(idx + 1) : normalized;
    }

    Set<String> parseNsfwBasenamesFromStructuredJson(String raw) {
      final String s = raw.trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return <String>{};
      try {
        final decoded = jsonDecode(s);
        if (decoded is! Map) return <String>{};
        final dynamic rawTags = decoded['image_tags'];
        if (rawTags is! List) return <String>{};
        final Set<String> out = <String>{};

        bool containsExactNsfw(dynamic tags) {
          if (tags == null) return false;
          if (tags is List) {
            return tags.any((t) => t.toString().trim().toLowerCase() == 'nsfw');
          }
          if (tags is String) {
            final String tt = tags.trim();
            if (tt.isEmpty) return false;
            try {
              final dynamic v = jsonDecode(tt);
              if (v is List) {
                return v.any(
                  (t) => t.toString().trim().toLowerCase() == 'nsfw',
                );
              }
              if (v is String) {
                return v
                    .split(RegExp(r'[，,;；\s]+'))
                    .any((e) => e.trim().toLowerCase() == 'nsfw');
              }
            } catch (_) {}
            return tt
                .split(RegExp(r'[，,;；\s]+'))
                .any((e) => e.trim().toLowerCase() == 'nsfw');
          }
          return false;
        }

        for (final e in rawTags) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final String file = (m['file'] ?? '').toString().trim();
          if (file.isEmpty) continue;
          final String bn = basenameOf(file);

          final bool nsfw = containsExactNsfw(m['tags']);

          if (nsfw) out.add(bn);
        }
        return out;
      } catch (_) {
        return <String>{};
      }
    }

    // 1) 先查 file_path -> segment_id 映射
    final Map<int, List<String>> filePathsBySegment = <int, List<String>>{};
    const int chunkSize = 400;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final int end = (i + chunkSize) > paths.length
          ? paths.length
          : (i + chunkSize);
      final List<String> chunk = paths.sublist(i, end);
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final String sql =
          '''
        SELECT file_path, segment_id
        FROM segment_samples
        WHERE file_path IN ($placeholders)
      ''';
      final rows = await db.rawQuery(sql, chunk);
      for (final r in rows) {
        final String? fp = r['file_path'] as String?;
        final int sid = (r['segment_id'] as int?) ?? 0;
        if (fp == null || fp.trim().isEmpty) continue;
        if (sid <= 0) continue;
        filePathsBySegment.putIfAbsent(sid, () => <String>[]).add(fp.trim());
      }
    }
    if (filePathsBySegment.isEmpty) return <String>{};

    // 2) 批量取 segment_results.structured_json，并解析 image_tags[] 里的 nsfw 文件名
    final List<int> segmentIds = filePathsBySegment.keys.toList(
      growable: false,
    );
    final Map<int, Set<String>> nsfwBasenamesBySegment = <int, Set<String>>{};

    for (int i = 0; i < segmentIds.length; i += chunkSize) {
      final int end = (i + chunkSize) > segmentIds.length
          ? segmentIds.length
          : (i + chunkSize);
      final List<int> chunk = segmentIds.sublist(i, end);
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final String sql =
          '''
        SELECT segment_id, structured_json
        FROM segment_results
        WHERE segment_id IN ($placeholders)
      ''';
      final rows = await db.rawQuery(sql, chunk);
      for (final r in rows) {
        final int sid = (r['segment_id'] as int?) ?? 0;
        if (sid <= 0) continue;
        final String sj = (r['structured_json'] as String?)?.toString() ?? '';
        final Set<String> basenames = parseNsfwBasenamesFromStructuredJson(sj);
        if (basenames.isNotEmpty) {
          nsfwBasenamesBySegment[sid] = basenames;
        }
      }
    }

    // 3) 将 nsfw basenames 映射回入参 file_path（按 basename 匹配）
    final Set<String> out = <String>{};
    for (final entry in filePathsBySegment.entries) {
      final Set<String>? basenames = nsfwBasenamesBySegment[entry.key];
      if (basenames == null || basenames.isEmpty) continue;
      for (final fp in entry.value) {
        final String bn = basenameOf(fp);
        if (basenames.contains(bn)) {
          out.add(fp);
        }
      }
    }
    return out;
  }

  /// 索引可用性：检测 SQLite 是否支持 AI 图片元数据 FTS（fts5）。
  Future<bool> isAiImageMetaIndexAvailable() async {
    try {
      final db = await database;
      return await _tableExists(db, 'ai_image_meta_fts');
    } catch (_) {
      return false;
    }
  }

  /// Resolve app package names by app display names using app_registry.
  ///
  /// Notes:
  /// - Tool calling prefers human app names to avoid hallucinated package names.
  /// - We still search/filter by package name internally (more stable/unique).
  Future<List<String>> findPackagesByAppNames(List<String> appNames) async {
    final List<String> names = appNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (names.isEmpty) return <String>[];

    // Guard: SQLite has a hard parameter limit; keep this small.
    final List<String> limited = (names.length > 30)
        ? (names..sort()).take(30).toList(growable: false)
        : (names..sort());

    try {
      final db = await database;
      final String placeholders = List.filled(limited.length, '?').join(',');
      final rows = await db.query(
        'app_registry',
        columns: ['app_package_name'],
        where: 'app_name COLLATE NOCASE IN ($placeholders)',
        whereArgs: limited,
      );
      return rows
          .map((r) => (r['app_package_name'] as String?)?.trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } catch (_) {
      return <String>[];
    }
  }

  /// 列出“有动态总结”的应用显示名（去重）。
  ///
  /// 口径：
  /// - 仅统计全局段落（global），并排除已被合并的子段。
  /// - 仅包含存在有效总结结果的段落（output_text / structured_json 任一非空且非 "null"）。
  /// - 应用名优先取 segment_samples.app_name；为空时回退 app_registry.app_name。
  Future<List<String>> listAppDisplayNamesWithSegmentSummaries({
    int limit = 200,
  }) async {
    final int safeLimit = limit.clamp(1, 500).toInt();
    try {
      final db = await database;
      final String sql =
          '''
        SELECT DISTINCT
          COALESCE(NULLIF(TRIM(ss.app_name), ''), NULLIF(TRIM(ar.app_name), '')) AS app_name
        FROM segments s
        JOIN segment_results r ON r.segment_id = s.id
        JOIN segment_samples ss ON ss.segment_id = s.id
        LEFT JOIN app_registry ar ON ar.app_package_name = ss.app_package_name
        WHERE ${_segmentsRootWhere('s')}
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND (
            (r.output_text IS NOT NULL AND LOWER(TRIM(r.output_text)) NOT IN ('','null'))
            OR
            (r.structured_json IS NOT NULL AND LOWER(TRIM(r.structured_json)) NOT IN ('','null'))
          )
          AND COALESCE(NULLIF(TRIM(ss.app_name), ''), NULLIF(TRIM(ar.app_name), '')) IS NOT NULL
        ORDER BY LOWER(app_name) COLLATE NOCASE ASC
        LIMIT ?
      ''';
      final List<Map<String, Object?>> rows = await db.rawQuery(sql, <Object?>[
        safeLimit,
      ]);
      final List<String> out = <String>[];
      final Set<String> dedup = <String>{};
      for (final Map<String, Object?> row in rows) {
        final String name = (row['app_name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final String key = name.toLowerCase();
        if (dedup.add(key)) out.add(name);
      }
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  /// 搜索 AI 图片元数据（tags/description），用于“无 OCR 或 OCR 不足”的图片检索。
  ///
  /// - 优先使用 FTS；如 FTS 不可用或命中为空，则回退 LIKE（更适配中文子串）。
  /// - 支持按时间范围过滤（capture_time）。
  Future<List<Map<String, dynamic>>> searchAiImageMetaByText(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    bool includeNsfw = false,
    List<String>? appPackageNames,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database;
    final AdvancedSearchQuery? adv = queryAdvanced;
    final String q0 = query.trim();
    final String q = (adv != null) ? adv.toPlainText() : q0;
    if (q.isEmpty) return <Map<String, dynamic>>[];

    final int fetchLimit = (limit ?? 50).clamp(1, 50);
    int fetchOffset = offset ?? 0;
    if (fetchOffset < 0) fetchOffset = 0;

    bool isLikelyCjkNoSpaces() {
      if (q.contains(' ')) return false;
      return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
    }

    Future<List<Map<String, dynamic>>> runFts() async {
      final bool ftsExists = await _tableExists(db, 'ai_image_meta_fts');
      if (!ftsExists) return <Map<String, dynamic>>[];

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 6,
              matchAllTerms: true,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
      final List<Object?> args = <Object?>[match];
      final List<String> filters = <String>[];
      if (!includeNsfw) {
        filters.add('m.nsfw = 0');
      }
      if (startMillis != null) {
        filters.add('m.capture_time >= ?');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('m.capture_time <= ?');
        args.add(endMillis);
      }

      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        filters.add('ss.app_package_name IN ($placeholders)');
        args.addAll(appPkgs);
      }

      final String whereClause = filters.isEmpty
          ? ''
          : 'AND ${filters.join(' AND ')}';
      final String sql =
          '''
        SELECT
          m.file_path,
          m.tags_json,
          m.description,
          m.description_range,
          m.nsfw,
          m.segment_id,
          m.capture_time,
          m.lang,
          m.updated_at,
          ss.app_package_name,
          ss.app_name
        FROM ai_image_meta_fts fts
        JOIN ai_image_meta m ON m.rowid = fts.rowid
        LEFT JOIN segment_samples ss
          ON ss.segment_id = m.segment_id AND ss.file_path = m.file_path
        WHERE ai_image_meta_fts MATCH ?
          $whereClause
        ORDER BY bm25(ai_image_meta_fts, 3.0, 2.0, 1.0) ASC, m.capture_time DESC
        LIMIT ? OFFSET ?
      ''';
      args.add(fetchLimit);
      args.add(fetchOffset);
      final rows = await db.rawQuery(sql, args);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    Future<List<Map<String, dynamic>>> runLike() async {
      bool addTermLike(String term, List<Object?> args, List<String> filters) {
        final String t = term.trim();
        if (t.isEmpty) return false;
        final String likeTerm = '%$t%';
        args.add(likeTerm);
        args.add(likeTerm);
        filters.add('(m.description LIKE ? OR m.tags_json LIKE ?)');
        return true;
      }

      // Build LIKE filters from advanced spec when provided.
      final List<Object?> args = <Object?>[];
      final List<String> filters = <String>[];

      if (adv != null) {
        final AdvancedSearchLikeQuery like = adv.toLikeSpec(
          maxGroups: 10,
          maxTokensPerGroup: 6,
        );

        for (final phrase in like.mustPhrases) {
          addTermLike(phrase, args, filters);
        }

        for (final group in like.mustGroups) {
          for (final tok in group) {
            addTermLike(tok, args, filters);
          }
        }

        final List<String> anyClauses = <String>[];
        final List<Object?> anyArgs = <Object?>[];
        for (final phrase in like.anyPhrases) {
          final List<Object?> gArgs = <Object?>[];
          final List<String> gFilters = <String>[];
          if (addTermLike(phrase, gArgs, gFilters)) {
            anyClauses.add(gFilters.single);
            anyArgs.addAll(gArgs);
          }
        }
        for (final group in like.anyGroups) {
          final List<String> gClauses = <String>[];
          final List<Object?> gArgs = <Object?>[];
          for (final tok in group) {
            final List<Object?> tArgs = <Object?>[];
            final List<String> tFilters = <String>[];
            if (addTermLike(tok, tArgs, tFilters)) {
              gClauses.add(tFilters.single);
              gArgs.addAll(tArgs);
            }
          }
          if (gClauses.isNotEmpty) {
            anyClauses.add(
              gClauses.length == 1
                  ? gClauses.single
                  : '(${gClauses.join(' AND ')})',
            );
            anyArgs.addAll(gArgs);
          }
        }
        if (anyClauses.isNotEmpty) {
          filters.add(
            anyClauses.length == 1
                ? anyClauses.single
                : '(${anyClauses.join(' OR ')})',
          );
          args.addAll(anyArgs);
        }

        for (final group in like.notGroups) {
          final List<String> gClauses = <String>[];
          final List<Object?> gArgs = <Object?>[];
          for (final tok in group) {
            final String t = tok.trim();
            if (t.isEmpty) continue;
            final String likeTerm = '%$t%';
            gArgs.addAll(<Object?>[likeTerm, likeTerm]);
            gClauses.add('(m.description LIKE ? OR m.tags_json LIKE ?)');
          }
          if (gClauses.isNotEmpty) {
            final String inner = gClauses.length == 1
                ? gClauses.single
                : '(${gClauses.join(' AND ')})';
            filters.add('NOT ($inner)');
            args.addAll(gArgs);
          }
        }
      } else {
        // Simple query: substring match (better for CJK) across description/tags.
        addTermLike(q, args, filters);
      }

      if (filters.isEmpty) return <Map<String, dynamic>>[];
      if (!includeNsfw) {
        filters.add('m.nsfw = 0');
      }
      if (startMillis != null) {
        filters.add('m.capture_time >= ?');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('m.capture_time <= ?');
        args.add(endMillis);
      }

      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        filters.add('ss.app_package_name IN ($placeholders)');
        args.addAll(appPkgs);
      }
      args.add(fetchLimit);
      args.add(fetchOffset);
      final String sql =
          '''
        SELECT
          m.file_path,
          m.tags_json,
          m.description,
          m.description_range,
          m.nsfw,
          m.segment_id,
          m.capture_time,
          m.lang,
          m.updated_at,
          ss.app_package_name,
          ss.app_name
        FROM ai_image_meta m
        LEFT JOIN segment_samples ss
          ON ss.segment_id = m.segment_id AND ss.file_path = m.file_path
        WHERE ${filters.join(' AND ')}
        ORDER BY m.capture_time DESC
        LIMIT ? OFFSET ?
      ''';
      final rows = await db.rawQuery(sql, args);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    try {
      // 中文无空格关键词更偏向子串检索，先走 LIKE 可减少“FTS 命中为空”的误判。
      if (isLikelyCjkNoSpaces()) {
        final likeRows = await runLike();
        if (likeRows.isNotEmpty) return likeRows;
      }

      final ftsRows = await runFts();
      if (ftsRows.isNotEmpty) return ftsRows;

      // FTS 命中为空时再回退 LIKE，提升中文/短词命中率。
      return await runLike();
    } catch (e) {
      try {
        await FlutterLogger.nativeWarn(
          'DB',
          'searchAiImageMetaByText failed, fallback to LIKE: $e',
        );
      } catch (_) {}
      try {
        return await runLike();
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
  }

  /// 搜索动态（segment）内容
  /// 支持搜索 AI 摘要文本和分类标签
  Future<List<Map<String, dynamic>>> searchSegmentsByText(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    List<String>? appPackageNames,
    bool matchAllTerms = true,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database;
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
      if (q.isEmpty) return <Map<String, dynamic>>[];

      final int fetchLimit = limit ?? 50;
      final int fetchOffset = offset ?? 0;

      bool isLikelyCjkNoSpaces() {
        if (q.contains(' ')) return false;
        return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
      }

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: matchAllTerms,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
      final List<String> baseFilters = <String>[];
      final List<Object?> baseArgs = <Object?>[];

      baseFilters.add(_segmentsRootWhere('s'));
      if (startMillis != null) {
        baseFilters.add('s.start_time >= ?');
        baseArgs.add(startMillis);
      }
      if (endMillis != null) {
        baseFilters.add('s.start_time <= ?');
        baseArgs.add(endMillis);
      }
      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        baseFilters.add(
          'EXISTS (SELECT 1 FROM segment_samples ss0 WHERE ss0.segment_id = s.id AND ss0.app_package_name IN ($placeholders))',
        );
        baseArgs.addAll(appPkgs);
      }

      final String whereClause = baseFilters.isEmpty
          ? ''
          : 'AND ${baseFilters.join(' AND ')}';

      Future<List<Map<String, dynamic>>> runFts() async {
        final bool ftsExists = await _tableExists(db, 'segment_results_fts');
        if (!ftsExists) return <Map<String, dynamic>>[];

        final List<Object?> args = <Object?>[
          match,
          ...baseArgs,
          fetchLimit,
          fetchOffset,
        ];
        final String sql =
            '''
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
          ORDER BY bm25(segment_results_fts, 4.0, 1.0, 3.0) ASC, s.start_time DESC
          LIMIT ? OFFSET ?
        ''';
        final rows = await db.rawQuery(sql, args);
        return rows.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      Future<List<Map<String, dynamic>>> runLike() async {
        bool addLikeTermClause(
          String term,
          List<Object?> args,
          List<String> clauses,
        ) {
          final String t = term.trim();
          if (t.isEmpty) return false;
          final String likeTerm = '%$t%';
          args.addAll(<Object?>[likeTerm, likeTerm, likeTerm]);
          clauses.add(
            '(r.output_text LIKE ? OR r.categories LIKE ? OR r.structured_json LIKE ?)',
          );
          return true;
        }

        final List<Object?> args = <Object?>[];
        final List<String> filters = <String>[];

        if (adv != null) {
          final AdvancedSearchLikeQuery like = adv.toLikeSpec(
            maxGroups: 10,
            maxTokensPerGroup: 6,
          );

          // Required phrases.
          for (final phrase in like.mustPhrases) {
            addLikeTermClause(phrase, args, filters);
          }

          // Required keyword groups (AND across groups; within group: AND).
          for (final group in like.mustGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              filters.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              args.addAll(gArgs);
            }
          }

          // Optional OR group(s).
          final List<String> anyClauses = <String>[];
          final List<Object?> anyArgs = <Object?>[];

          for (final phrase in like.anyPhrases) {
            final List<String> pClauses = <String>[];
            final List<Object?> pArgs = <Object?>[];
            if (addLikeTermClause(phrase, pArgs, pClauses)) {
              anyClauses.add(pClauses.single);
              anyArgs.addAll(pArgs);
            }
          }

          for (final group in like.anyGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              anyClauses.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              anyArgs.addAll(gArgs);
            }
          }

          if (anyClauses.isNotEmpty) {
            filters.add(
              anyClauses.length == 1
                  ? anyClauses.single
                  : '(${anyClauses.join(' OR ')})',
            );
            args.addAll(anyArgs);
          }

          // Exclusions.
          for (final group in like.notGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              final String inner = gClauses.length == 1
                  ? gClauses.single
                  : '(${gClauses.join(' AND ')})';
              filters.add('NOT ($inner)');
              args.addAll(gArgs);
            }
          }
        } else {
          final parts = q
              .split(RegExp(r'\s+'))
              .where((e) => e.isNotEmpty)
              .toList();
          final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
          final List<String> tokenFilters = <String>[];
          for (final w in limited) {
            final List<String> tClauses = <String>[];
            final List<Object?> tArgs = <Object?>[];
            if (addLikeTermClause(w, tArgs, tClauses)) {
              tokenFilters.add(tClauses.single);
              args.addAll(tArgs);
            }
          }
          final String tokensClause = tokenFilters.isEmpty
              ? '1 = 1'
              : (tokenFilters.length == 1
                    ? tokenFilters.single
                    : '(${tokenFilters.join(matchAllTerms ? ' AND ' : ' OR ')})');
          filters.insert(0, tokensClause);
        }

        // Keep arg order aligned: LIKE terms first, then base filters.
        filters.addAll(baseFilters);
        if (filters.isEmpty) return <Map<String, dynamic>>[];
        args.addAll(baseArgs);
        args.addAll(<Object?>[fetchLimit, fetchOffset]);
        final String sql =
            '''
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
          WHERE ${filters.join(' AND ')}
          ORDER BY s.start_time DESC
          LIMIT ? OFFSET ?
        ''';
        final rows = await db.rawQuery(sql, args);
        return rows.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      try {
        // 中文无空格：优先 LIKE，减少“FTS 命中为空”的误判。
        if (isLikelyCjkNoSpaces()) {
          final likeRows = await runLike();
          if (likeRows.isNotEmpty) return likeRows;
        }

        final ftsRows = await runFts();
        if (ftsRows.isNotEmpty) return ftsRows;

        // FTS 命中为空时回退 LIKE，覆盖 structured_json（合并原始事件等）与短词场景。
        return await runLike();
      } catch (ftsError) {
        // FTS 不可用/异常：回退 LIKE
        try {
          await FlutterLogger.nativeWarn('DB', 'FTS 搜索失败，回退到 LIKE：$ftsError');
        } catch (_) {}
        return await runLike();
      }
    } catch (e) {
      try {
        await FlutterLogger.nativeError('DB', 'searchSegmentsByText 失败：$e');
      } catch (_) {}
      return <Map<String, dynamic>>[];
    }
  }

  /// 统计搜索动态结果总数
  Future<int> countSegmentsByText(
    String query, {
    int? startMillis,
    int? endMillis,
    List<String>? appPackageNames,
    bool matchAllTerms = true,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database;
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
      if (q.isEmpty) return 0;

      bool isLikelyCjkNoSpaces() {
        if (q.contains(' ')) return false;
        return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
      }

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: matchAllTerms,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
      final List<String> baseFilters = <String>[];
      final List<Object?> baseArgs = <Object?>[];

      baseFilters.add(_segmentsRootWhere('s'));
      if (startMillis != null) {
        baseFilters.add('s.start_time >= ?');
        baseArgs.add(startMillis);
      }
      if (endMillis != null) {
        baseFilters.add('s.start_time <= ?');
        baseArgs.add(endMillis);
      }
      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        baseFilters.add(
          'EXISTS (SELECT 1 FROM segment_samples ss0 WHERE ss0.segment_id = s.id AND ss0.app_package_name IN ($placeholders))',
        );
        baseArgs.addAll(appPkgs);
      }

      final String whereClause = baseFilters.isEmpty
          ? ''
          : 'AND ${baseFilters.join(' AND ')}';

      Future<int> runFtsCount() async {
        final bool ftsExists = await _tableExists(db, 'segment_results_fts');
        if (!ftsExists) return 0;
        final List<Object?> args = <Object?>[match, ...baseArgs];
        final String sql =
            '''
          SELECT COUNT(*) AS c
          FROM segment_results_fts fts
          JOIN segment_results r ON r.segment_id = fts.rowid
          JOIN segments s ON s.id = r.segment_id
          WHERE segment_results_fts MATCH ?
            $whereClause
        ''';
        final rows = await db.rawQuery(sql, args);
        return (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
      }

      Future<int> runLikeCount() async {
        bool addLikeTermClause(
          String term,
          List<Object?> args,
          List<String> clauses,
        ) {
          final String t = term.trim();
          if (t.isEmpty) return false;
          final String likeTerm = '%$t%';
          args.addAll(<Object?>[likeTerm, likeTerm, likeTerm]);
          clauses.add(
            '(r.output_text LIKE ? OR r.categories LIKE ? OR r.structured_json LIKE ?)',
          );
          return true;
        }

        final List<Object?> args = <Object?>[];
        final List<String> filters = <String>[];

        if (adv != null) {
          final AdvancedSearchLikeQuery like = adv.toLikeSpec(
            maxGroups: 10,
            maxTokensPerGroup: 6,
          );

          for (final phrase in like.mustPhrases) {
            addLikeTermClause(phrase, args, filters);
          }

          for (final group in like.mustGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              filters.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              args.addAll(gArgs);
            }
          }

          final List<String> anyClauses = <String>[];
          final List<Object?> anyArgs = <Object?>[];

          for (final phrase in like.anyPhrases) {
            final List<String> pClauses = <String>[];
            final List<Object?> pArgs = <Object?>[];
            if (addLikeTermClause(phrase, pArgs, pClauses)) {
              anyClauses.add(pClauses.single);
              anyArgs.addAll(pArgs);
            }
          }

          for (final group in like.anyGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              anyClauses.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              anyArgs.addAll(gArgs);
            }
          }

          if (anyClauses.isNotEmpty) {
            filters.add(
              anyClauses.length == 1
                  ? anyClauses.single
                  : '(${anyClauses.join(' OR ')})',
            );
            args.addAll(anyArgs);
          }

          for (final group in like.notGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              final String inner = gClauses.length == 1
                  ? gClauses.single
                  : '(${gClauses.join(' AND ')})';
              filters.add('NOT ($inner)');
              args.addAll(gArgs);
            }
          }
        } else {
          final parts = q
              .split(RegExp(r'\s+'))
              .where((e) => e.isNotEmpty)
              .toList();
          final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
          final List<String> tokenFilters = <String>[];
          for (final w in limited) {
            final List<String> tClauses = <String>[];
            final List<Object?> tArgs = <Object?>[];
            if (addLikeTermClause(w, tArgs, tClauses)) {
              tokenFilters.add(tClauses.single);
              args.addAll(tArgs);
            }
          }
          final String tokensClause = tokenFilters.isEmpty
              ? '1 = 1'
              : (tokenFilters.length == 1
                    ? tokenFilters.single
                    : '(${tokenFilters.join(matchAllTerms ? ' AND ' : ' OR ')})');
          filters.add(tokensClause);
        }

        filters.addAll(baseFilters);
        args.addAll(baseArgs);
        final String sql =
            '''
          SELECT COUNT(*) AS c
          FROM segments s
          JOIN segment_results r ON r.segment_id = s.id
          WHERE ${filters.join(' AND ')}
        ''';
        final rows = await db.rawQuery(sql, args);
        return (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
      }

      try {
        if (isLikelyCjkNoSpaces()) {
          final c = await runLikeCount();
          if (c > 0) return c;
        }
        final c = await runFtsCount();
        if (c > 0) return c;
        return await runLikeCount();
      } catch (ftsError) {
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'countSegmentsByText: FTS 失败，回退 LIKE：$ftsError',
          );
        } catch (_) {}
        return await runLikeCount();
      }
    } catch (e) {
      try {
        await FlutterLogger.nativeError('DB', 'countSegmentsByText 失败：$e');
      } catch (_) {}
      return 0;
    }
  }

  /// 删除单个段落事件（仅删除事件及其结果/样本，不删除月表中的图片记录/文件）
  Future<bool> deleteSegmentOnly(int segmentId) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        final int now = DateTime.now().millisecondsSinceEpoch;

        // If the user deletes a root segment that other segments were merged into,
        // those children become "orphaned" and would disappear from the UI if we
        // only query merged_into_id IS NULL. Unmerge them back to roots.
        try {
          await txn.update(
            'segments',
            {'merged_into_id': null, 'updated_at': now},
            where: 'merged_into_id = ?',
            whereArgs: [segmentId],
          );
        } catch (_) {
          try {
            await txn.update(
              'segments',
              {'merged_into_id': null},
              where: 'merged_into_id = ?',
              whereArgs: [segmentId],
            );
          } catch (_) {}
        }
        // Clear stale merge_prev_id pointers so "force merge" won't reference a deleted row.
        try {
          await txn.update(
            'segments',
            {'merge_prev_id': null, 'updated_at': now},
            where: 'merge_prev_id = ?',
            whereArgs: [segmentId],
          );
        } catch (_) {
          try {
            await txn.update(
              'segments',
              {'merge_prev_id': null},
              where: 'merge_prev_id = ?',
              whereArgs: [segmentId],
            );
          } catch (_) {}
        }

        // 先抓取该段落关联的图片路径：即使 ai_image_meta.segment_id 被后续流程覆盖，
        // 也能按 file_path 兜底清理，避免“图片描述/标签”残留在查看器/搜索中。
        final List<String> sampleFilePaths = <String>[];
        try {
          final rows = await txn.query(
            'segment_samples',
            columns: const ['file_path'],
            where: 'segment_id = ?',
            whereArgs: [segmentId],
          );
          for (final r in rows) {
            final String p = (r['file_path'] as String?)?.trim() ?? '';
            if (p.isNotEmpty) sampleFilePaths.add(p);
          }
        } catch (_) {}

        await txn.delete(
          'segment_results',
          where: 'segment_id = ?',
          whereArgs: [segmentId],
        );
        await txn.delete(
          'segment_samples',
          where: 'segment_id = ?',
          whereArgs: [segmentId],
        );
        // 同步删除该段落生成的图片标签/描述，避免删除事件后“图片描述”仍残留在查看器/搜索中。
        try {
          await txn.delete(
            'ai_image_meta',
            where: 'segment_id = ?',
            whereArgs: [segmentId],
          );
        } catch (_) {}

        // 兜底：按 file_path 再删一遍（分批避免 SQLite 参数上限）。
        final List<String> paths = sampleFilePaths
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(growable: false);
        if (paths.isNotEmpty) {
          const int chunkSize = 400;
          for (int i = 0; i < paths.length; i += chunkSize) {
            final int end = (i + chunkSize) > paths.length
                ? paths.length
                : (i + chunkSize);
            final List<String> chunk = paths.sublist(i, end);
            final String placeholders = List.filled(
              chunk.length,
              '?',
            ).join(',');
            try {
              await txn.delete(
                'ai_image_meta',
                where: 'file_path IN ($placeholders)',
                whereArgs: chunk,
              );
            } catch (_) {}
          }
        }
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
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('daily_summaries', {
        'date_key': dateKey,
        'ai_provider': aiProvider,
        'ai_model': aiModel,
        'output_text': outputText,
        'structured_json': structuredJson,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // ignore: unawaited_futures
      this.upsertSearchDoc(
        docKey: _dailySummaryDocKey(dateKey),
        docType: kSearchDocTypeDailySummary,
        title: '每日总结 $dateKey',
        content: outputText,
        dateKey: dateKey,
        startTime: _parseYmdToStartMillis(dateKey),
        updatedAt: now,
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
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('weekly_summaries', {
        'week_start_date': weekStartDate,
        'week_end_date': weekEndDate,
        'ai_provider': aiProvider,
        'ai_model': aiModel,
        'output_text': outputText,
        'structured_json': structuredJson,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final String title = weekEndDate.trim().isEmpty
          ? '周总结 $weekStartDate'
          : '周总结 $weekStartDate ~ $weekEndDate';
      // ignore: unawaited_futures
      this.upsertSearchDoc(
        docKey: _weeklySummaryDocKey(weekStartDate),
        docType: kSearchDocTypeWeeklySummary,
        title: title,
        content: outputText,
        dateKey: weekStartDate,
        startTime: _parseYmdToStartMillis(weekStartDate),
        updatedAt: now,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listWeeklySummaries({
    int? limit,
    int? offset,
  }) async {
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
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('morning_insights', {
        'date_key': dateKey,
        'source_date_key': sourceDateKey,
        'tips_json': tipsJson,
        if (rawResponse != null) 'raw_response': rawResponse,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // ignore: unawaited_futures
      this.upsertSearchDoc(
        docKey: _morningInsightsDocKey(dateKey),
        docType: kSearchDocTypeMorningInsights,
        title: '早报 $dateKey',
        content: _renderMorningInsightsMarkdown(
          (rawResponse != null && rawResponse.trim().isNotEmpty)
              ? rawResponse
              : tipsJson,
        ),
        dateKey: dateKey,
        startTime: _parseYmdToStartMillis(dateKey),
        updatedAt: now,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> deleteMorningInsights(String dateKey) async {
    final db = await database;
    try {
      return await db.delete(
        'morning_insights',
        where: 'date_key = ?',
        whereArgs: [dateKey],
      );
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
      final String sql =
          '''
        SELECT
          s.*,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        JOIN segment_results r ON r.segment_id = s.id
        WHERE ${_segmentsRootWhere('s')}
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND s.start_time >= ? AND s.start_time <= ?
        ORDER BY s.start_time ASC
      ''';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ' +
              sql
                  .replaceFirst('?', startMillis.toString())
                  .replaceFirst('?', endMillis.toString()),
        );
      } catch (_) {}
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
      final String sql =
          '''
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
        WHERE ${_segmentsRootWhere('s')}
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND s.start_time <= ? AND s.end_time >= ?
          AND EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)
        ORDER BY s.start_time ASC
      ''';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ' +
              sql
                  .replaceFirst('?', endMillis.toString())
                  .replaceFirst('?', startMillis.toString()),
        );
      } catch (_) {}
      final rows = await db.rawQuery(sql, [endMillis, startMillis]);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}

Future<void> _createUserMemoryItemEventsTable(DatabaseExecutor db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_memory_item_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        memory_item_id INTEGER NOT NULL,
        kind TEXT NOT NULL,                -- rule | fact | habit
        content TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        keywords_json TEXT,
        confidence REAL,
        source_type TEXT NOT NULL,         -- segment | chat | daily_summary | weekly_summary | morning_insights
        source_id TEXT NOT NULL,           -- e.g. segment:123 / chat:cid=...#ts=...
        evidence_filenames_json TEXT,      -- optional JSON array of basenames (max ~5)
        start_time INTEGER,
        end_time INTEGER,
        created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
        UNIQUE(memory_item_id, source_type, source_id, content_hash)
      )
    ''');
  } catch (_) {}

  // Expression index for stable chronological reads; best-effort for older SQLite.
  try {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_memory_item_events_item
      ON user_memory_item_events(memory_item_id, COALESCE(start_time, created_at) ASC, id ASC)
      ''');
  } catch (_) {}
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
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_weekly_summaries_created ON weekly_summaries(created_at DESC)',
  );
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

/// 创建 segment_results 的 FTS5 全文搜索索引
Future<void> _createSegmentResultsFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS segment_results_fts USING fts5(
        output_text,
        structured_json,
        categories,
        content='segment_results',
        content_rowid='segment_id',
        prefix='2 3 4'
      )
    ''');
    // 创建触发器保持 FTS 同步
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS segment_results_ai AFTER INSERT ON segment_results BEGIN
        INSERT INTO segment_results_fts(rowid, output_text, structured_json, categories)
        VALUES (NEW.segment_id, NEW.output_text, NEW.structured_json, NEW.categories);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS segment_results_ad AFTER DELETE ON segment_results BEGIN
        INSERT INTO segment_results_fts(segment_results_fts, rowid, output_text, structured_json, categories)
        VALUES ('delete', OLD.segment_id, OLD.output_text, OLD.structured_json, OLD.categories);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS segment_results_au AFTER UPDATE ON segment_results BEGIN
        INSERT INTO segment_results_fts(segment_results_fts, rowid, output_text, structured_json, categories)
        VALUES ('delete', OLD.segment_id, OLD.output_text, OLD.structured_json, OLD.categories);
        INSERT INTO segment_results_fts(rowid, output_text, structured_json, categories)
        VALUES (NEW.segment_id, NEW.output_text, NEW.structured_json, NEW.categories);
      END
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', 'FTS5（segment_results）不支持：$e');
    } catch (_) {}
  }
}

/// 回填已有数据到 FTS 索引
Future<void> _backfillSegmentResultsFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      INSERT OR IGNORE INTO segment_results_fts(rowid, output_text, structured_json, categories)
      SELECT segment_id, output_text, structured_json, categories FROM segment_results
      WHERE (output_text IS NOT NULL AND TRIM(output_text) != '')
         OR (structured_json IS NOT NULL AND TRIM(structured_json) != '')
         OR (categories IS NOT NULL AND TRIM(categories) != '')
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', '回填 segment_results_fts 失败：$e');
    } catch (_) {}
  }
}

/// 创建 ai_image_meta 的 FTS5 全文搜索索引（用于按图片标签/描述检索）。
Future<void> _createAiImageMetaFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS ai_image_meta_fts USING fts5(
        tags_json,
        description,
        description_range,
        content='ai_image_meta',
        content_rowid='rowid',
        prefix='2 3 4'
      )
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ai_image_meta_ai AFTER INSERT ON ai_image_meta BEGIN
        INSERT INTO ai_image_meta_fts(rowid, tags_json, description, description_range)
        VALUES (NEW.rowid, NEW.tags_json, NEW.description, NEW.description_range);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ai_image_meta_ad AFTER DELETE ON ai_image_meta BEGIN
        INSERT INTO ai_image_meta_fts(ai_image_meta_fts, rowid, tags_json, description, description_range)
        VALUES ('delete', OLD.rowid, OLD.tags_json, OLD.description, OLD.description_range);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ai_image_meta_au AFTER UPDATE ON ai_image_meta BEGIN
        INSERT INTO ai_image_meta_fts(ai_image_meta_fts, rowid, tags_json, description, description_range)
        VALUES ('delete', OLD.rowid, OLD.tags_json, OLD.description, OLD.description_range);
        INSERT INTO ai_image_meta_fts(rowid, tags_json, description, description_range)
        VALUES (NEW.rowid, NEW.tags_json, NEW.description, NEW.description_range);
      END
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', 'FTS5（ai_image_meta）不支持：$e');
    } catch (_) {}
  }
}

/// 回填已有数据到 ai_image_meta_fts 索引
Future<void> _backfillAiImageMetaFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      INSERT OR IGNORE INTO ai_image_meta_fts(rowid, tags_json, description, description_range)
      SELECT rowid, tags_json, description, description_range FROM ai_image_meta
      WHERE
        (description IS NOT NULL AND TRIM(description) != '')
        OR (tags_json IS NOT NULL AND TRIM(tags_json) != '')
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', '回填 ai_image_meta_fts 失败：$e');
    } catch (_) {}
  }
}

/// Create FTS5 index for ai_atomic_memories (atomic facts/rules).
Future<void> _createAtomicMemoriesFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS ai_atomic_memories_fts USING fts5(
        memory_key,
        content,
        keywords_json,
        content='ai_atomic_memories',
        content_rowid='rowid',
        prefix='2 3 4'
      )
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ai_atomic_memories_ai AFTER INSERT ON ai_atomic_memories BEGIN
        INSERT INTO ai_atomic_memories_fts(rowid, memory_key, content, keywords_json)
        VALUES (NEW.rowid, NEW.memory_key, NEW.content, NEW.keywords_json);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ai_atomic_memories_ad AFTER DELETE ON ai_atomic_memories BEGIN
        INSERT INTO ai_atomic_memories_fts(ai_atomic_memories_fts, rowid, memory_key, content, keywords_json)
        VALUES ('delete', OLD.rowid, OLD.memory_key, OLD.content, OLD.keywords_json);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ai_atomic_memories_au AFTER UPDATE ON ai_atomic_memories BEGIN
        INSERT INTO ai_atomic_memories_fts(ai_atomic_memories_fts, rowid, memory_key, content, keywords_json)
        VALUES ('delete', OLD.rowid, OLD.memory_key, OLD.content, OLD.keywords_json);
        INSERT INTO ai_atomic_memories_fts(rowid, memory_key, content, keywords_json)
        VALUES (NEW.rowid, NEW.memory_key, NEW.content, NEW.keywords_json);
      END
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', 'FTS5（ai_atomic_memories）不支持：$e');
    } catch (_) {}
  }
}

/// Backfill existing rows into ai_atomic_memories_fts.
Future<void> _backfillAtomicMemoriesFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      INSERT OR IGNORE INTO ai_atomic_memories_fts(rowid, memory_key, content, keywords_json)
      SELECT rowid, memory_key, content, keywords_json FROM ai_atomic_memories
      WHERE
        (content IS NOT NULL AND TRIM(content) != '')
        OR (memory_key IS NOT NULL AND TRIM(memory_key) != '')
        OR (keywords_json IS NOT NULL AND TRIM(keywords_json) != '')
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', '回填 ai_atomic_memories_fts 失败：$e');
    } catch (_) {}
  }
}

/// Create FTS5 index for user_memory_items (global user memory).
Future<void> _createUserMemoryItemsFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS user_memory_items_fts USING fts5(
        memory_key,
        content,
        keywords_json,
        content='user_memory_items',
        content_rowid='rowid',
        prefix='2 3 4'
      )
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS user_memory_items_ai AFTER INSERT ON user_memory_items BEGIN
        INSERT INTO user_memory_items_fts(rowid, memory_key, content, keywords_json)
        VALUES (NEW.rowid, NEW.memory_key, NEW.content, NEW.keywords_json);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS user_memory_items_ad AFTER DELETE ON user_memory_items BEGIN
        INSERT INTO user_memory_items_fts(user_memory_items_fts, rowid, memory_key, content, keywords_json)
        VALUES ('delete', OLD.rowid, OLD.memory_key, OLD.content, OLD.keywords_json);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS user_memory_items_au AFTER UPDATE ON user_memory_items BEGIN
        INSERT INTO user_memory_items_fts(user_memory_items_fts, rowid, memory_key, content, keywords_json)
        VALUES ('delete', OLD.rowid, OLD.memory_key, OLD.content, OLD.keywords_json);
        INSERT INTO user_memory_items_fts(rowid, memory_key, content, keywords_json)
        VALUES (NEW.rowid, NEW.memory_key, NEW.content, NEW.keywords_json);
      END
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', 'FTS5（user_memory_items）不支持：$e');
    } catch (_) {}
  }
}

/// Backfill existing rows into user_memory_items_fts.
Future<void> _backfillUserMemoryItemsFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      INSERT OR IGNORE INTO user_memory_items_fts(rowid, memory_key, content, keywords_json)
      SELECT rowid, memory_key, content, keywords_json FROM user_memory_items
      WHERE
        (content IS NOT NULL AND TRIM(content) != '')
        OR (memory_key IS NOT NULL AND TRIM(memory_key) != '')
        OR (keywords_json IS NOT NULL AND TRIM(keywords_json) != '')
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', '回填 user_memory_items_fts 失败：$e');
    } catch (_) {}
  }
}

/// v32 migration: Recreate AI-related FTS tables so new options (e.g. prefix)
/// take effect even when the virtual tables already existed.
Future<void> _recreateAiFtsTablesWithPrefix(DatabaseExecutor db) async {
  Future<void> drop(String name) async {
    try {
      await db.execute('DROP TABLE IF EXISTS $name');
    } catch (_) {}
  }

  // These are derived indexes; safe to rebuild from their content tables.
  await drop('segment_results_fts');
  await drop('ai_image_meta_fts');
  await drop('ai_atomic_memories_fts');
  await drop('user_memory_items_fts');

  try {
    await _createSegmentResultsFts(db);
  } catch (_) {}
  try {
    await _backfillSegmentResultsFts(db);
  } catch (_) {}

  try {
    await _createAiImageMetaFts(db);
  } catch (_) {}
  try {
    await _backfillAiImageMetaFts(db);
  } catch (_) {}

  try {
    await _createAtomicMemoriesFts(db);
  } catch (_) {}
  try {
    await _backfillAtomicMemoriesFts(db);
  } catch (_) {}

  try {
    await _createUserMemoryItemsFts(db);
  } catch (_) {}
  try {
    await _backfillUserMemoryItemsFts(db);
  } catch (_) {}
}

package com.fqyw.screen_memo.memory.service

import android.content.Context
import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.SegmentDatabaseHelper
import com.fqyw.screen_memo.memory.data.MemoryRepository
import com.fqyw.screen_memo.memory.data.db.MemoryDatabase
import com.fqyw.screen_memo.memory.data.db.MemoryEventEntity
import com.fqyw.screen_memo.memory.model.MemoryEventSummary
import com.fqyw.screen_memo.memory.model.MemoryProgressState
import com.fqyw.screen_memo.memory.model.MemorySnapshot
import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.model.PersonaProfile
import com.fqyw.screen_memo.memory.model.PersonaProfilePatch
import com.fqyw.screen_memo.memory.processor.LlmEndpointConfigurationException
import com.fqyw.screen_memo.memory.processor.LlmHttpException
import com.fqyw.screen_memo.memory.processor.LlmUserSignalExtractor
import com.fqyw.screen_memo.memory.processor.UserSignalExtractionResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.HashMap
import java.util.LinkedHashMap
import java.util.LinkedHashSet
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

class MemoryEngine private constructor(
    private val repository: MemoryRepository
) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _snapshotState = MutableStateFlow(MemorySnapshot(personaSummary = DEFAULT_PERSONA_SUMMARY))
    val snapshotState: StateFlow<MemorySnapshot> = _snapshotState

    private val _progressState = MutableStateFlow<MemoryProgressState>(MemoryProgressState.Idle)
    val progressState: StateFlow<MemoryProgressState> = _progressState

    private val _personaSummaryState = MutableStateFlow(DEFAULT_PERSONA_SUMMARY)
    private var usingFallbackSummary = true
    val personaSummaryState: StateFlow<String> = _personaSummaryState

    private val _personaProfileState = MutableStateFlow(PersonaProfile.default())
    val personaProfileState: StateFlow<PersonaProfile> = _personaProfileState

    private val initializing = AtomicBoolean(false)
    private var initializationJob: Job? = null
    @Volatile
    private var extractionContext: ExtractionContext? = null
    private val llmExtractor = LlmUserSignalExtractor()
    private val systemZone: ZoneId = ZoneId.systemDefault()
    private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val timeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm:ss")

    init {
        observeSnapshotStreams()
        scope.launch {
            try {
                val storedProfile = repository.loadPersonaProfile()
                if (storedProfile != null) {
                    _personaProfileState.value = storedProfile
                    val markdown = storedProfile.toMarkdown()
                    _personaSummaryState.value = markdown
                    usingFallbackSummary = false
                } else {
                    val storedSummary = repository.loadPersonaSummary()?.trim().orEmpty()
                    if (storedSummary.isNotEmpty()) {
                        _personaSummaryState.value = storedSummary
                        _personaProfileState.value = PersonaProfile.fromLegacySummary(storedSummary)
                        usingFallbackSummary = false
                    }
                }
            } catch (t: Throwable) {
                FileLogger.e(TAG, "从仓库加载人设状态失败", t)
            }
        }
    }

    suspend fun syncSegments(context: Context, batchSize: Int = SEGMENT_SYNC_BATCH): Int {
        return withContext(scope.coroutineContext) {
            val totalSegments = SegmentDatabaseHelper.countSegments(context)
            if (totalSegments == 0) {
                FileLogger.i(TAG, "syncSegments：未找到段落")
                return@withContext 0
            }

            var processed = 0
            var offset = 0
            val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

            while (true) {
                val segments = SegmentDatabaseHelper.listSegmentsAscending(context, batchSize, offset)
                if (segments.isEmpty()) break
                segments.forEach { segment ->
                    try {
                        val result = SegmentDatabaseHelper.getSegmentResult(context, segment.id)
                        val samples = SegmentDatabaseHelper.getSegmentSamples(context, segment.id)
                        val metadata = HashMap<String, String>()
                        metadata["segment_id"] = segment.id.toString()
                        metadata["segment_start"] = segment.startTime.toString()
                        metadata["segment_end"] = segment.endTime.toString()
                        metadata["segment_duration_sec"] = segment.durationSec.toString()
                        metadata["segment_sample_interval_sec"] = segment.sampleIntervalSec.toString()
                        metadata["segment_status"] = segment.status
                        segment.appPackages?.let { if (it.isNotBlank()) metadata["segment_app_packages"] = it }
                        segment.createdAt?.let { metadata["segment_created_at"] = it.toString() }
                        segment.updatedAt?.let { metadata["segment_updated_at"] = it.toString() }

                        result?.aiProvider?.let { if (it.isNotBlank()) metadata["ai_provider"] = it }
                        result?.aiModel?.let { if (it.isNotBlank()) metadata["ai_model"] = it }
                        result?.outputText?.let { if (it.isNotBlank()) metadata["ai_output_text"] = truncate(it.trim(), MAX_METADATA_TEXT) }
                        result?.structuredJson?.let { if (it.isNotBlank()) metadata["ai_structured_json"] = truncate(it.trim(), MAX_METADATA_TEXT) }
                        result?.categories?.let { if (it.isNotBlank()) metadata["ai_categories"] = it }

                        if (samples.isNotEmpty()) {
                            val sampleArray = JSONArray()
                            samples.sortedBy { it.captureTime }.forEach { sample ->
                                val obj = JSONObject()
                                obj.put("file_path", sample.filePath)
                                obj.put("capture_time", sample.captureTime)
                                obj.put("app_package", sample.appPackageName)
                                obj.put("app_name", sample.appName)
                                obj.put("position_index", sample.positionIndex)
                                sampleArray.put(obj)
                            }
                            metadata["segment_samples"] = sampleArray.toString()
                            metadata["segment_sample_count"] = samples.size.toString()
                        }

                        val summary = result?.outputText?.trim().orEmpty()
                        val content = if (summary.isNotEmpty()) {
                            summary
                        } else {
                            buildString {
                                append("Segment from ")
                                append(formatter.format(segment.startTime))
                                append(" to ")
                                append(formatter.format(segment.endTime))
                                append(", duration ")
                                append(segment.durationSec)
                                append(" seconds.")
                                if (segment.status.isNotEmpty()) {
                                    append(" Status: ")
                                    append(segment.status)
                                }
                            }
                        }

                        val event = UserEvent(
                            externalId = "segment:${segment.id}",
                            occurredAt = segment.startTime,
                            type = "segment",
                            source = "dynamic",
                            content = content,
                            metadata = metadata
                        )
                        repository.upsertEvent(event)
                    } catch (t: Throwable) {
                        FileLogger.e(TAG, "syncSegments：导入段落失败 id=${segment.id}", t)
                    }
                    processed += 1
                }
                offset += segments.size
            }

            FileLogger.i(TAG, "syncSegments completed: processed=$processed total=$totalSegments")
            processed
        }
    }

    fun setExtractionContext(context: ExtractionContext?) {
        extractionContext = context
        FileLogger.i(TAG, "Extraction context updated: ${context?.toLogSafeString() ?: "cleared"}")
    }

    fun getLastExtractionRequestDebug(): Map<String, Any?>? {
        return LlmUserSignalExtractor.getLastRequestDebug()
    }

    private suspend fun extractWithLlm(event: UserEvent): UserSignalExtractionResult {
        val context = extractionContext
        if (context == null || !context.isValid) {
            FileLogger.w(TAG, "LLM 提取已跳过：缺少提取上下文")
            return UserSignalExtractionResult(
                personaProfilePatch = null,
                personaSummaryFallback = null
            )
        }
        val currentPersona = personaSummaryState.value
        val currentProfile = personaProfileState.value
        return llmExtractor.extractSignals(
            event = event,
            context = context,
            currentPersonaSummary = currentPersona,
            currentPersonaProfile = currentProfile
        )
    }

    private fun observeSnapshotStreams() {
        scope.launch {
            combine(
                repository.observeRecentEvents(SNAPSHOT_RECENT_EVENT_LIMIT),
                personaSummaryState,
                personaProfileState
            ) { events: List<MemoryEventSummary>, persona: String, profile: PersonaProfile ->
                MemorySnapshot(
                    recentEvents = events,
                    recentEventTotalCount = events.size,
                    lastUpdatedAt = System.currentTimeMillis(),
                    personaSummary = persona,
                    personaProfile = profile
                )
            }.collect { snapshot ->
                _snapshotState.value = snapshot
                maybeRefreshPersonaSummary(snapshot)
            }
        }
    }

    suspend fun ingestEvent(event: UserEvent) {
        withContext(scope.coroutineContext) {
            val entity = repository.upsertEvent(event)
            val extraction = extractWithLlm(event)
            val beforePersona = _personaSummaryState.value
            applyPersonaUpdateFromLlm(extraction.personaProfilePatch, extraction.personaSummaryFallback)

            repository.applyGraphUpdates(
                eventId = entity.id,
                eventTimestamp = event.occurredAt,
                eventContent = event.content,
                graphEntities = extraction.graphEntities,
                graphEdges = extraction.graphEdges,
                graphEdgeClosures = extraction.graphEdgeClosures
            )

            val personaUpdated = _personaSummaryState.value != beforePersona
            val graphUpdated = extraction.graphEntities.isNotEmpty() ||
                extraction.graphEdges.isNotEmpty() ||
                extraction.graphEdgeClosures.isNotEmpty()
            val containsContext = personaUpdated || graphUpdated

            repository.markEventProcessed(entity.id, containsUserContext = containsContext)
        }
    }

    fun initializeHistoricalProcessing(
        forceReprocess: Boolean = false,
        batchSize: Int = DEFAULT_BATCH_SIZE,
        targetEndExclusiveMillis: Long? = null
    ) {
        if (initializing.compareAndSet(false, true).not()) {
            return
        }

        initializationJob = scope.launch {
            val startTime = System.currentTimeMillis()
            val processOnlyPending = !forceReprocess
            val totalDays = countRemainingDays(forceReprocess, targetEndExclusiveMillis)
            var processedDays = 0
            var offset = 0
            try {
                _progressState.value = MemoryProgressState.Running(
                    processedCount = 0,
                    totalCount = totalDays,
                    progress = if (totalDays == 0) 1f else 0f,
                    currentEventId = null,
                    currentEventExternalId = null,
                    currentEventType = null
                )

                if (totalDays == 0 && processOnlyPending) {
                    _progressState.value = MemoryProgressState.Completed(
                        totalCount = 0,
                        durationMillis = System.currentTimeMillis() - startTime
                    )
                    return@launch
                }

                if (processOnlyPending) {
                    while (true) {
                        val earliest = repository.getEarliestUnprocessedEvent() ?: break
                        if (targetEndExclusiveMillis != null && earliest.occurredAt >= targetEndExclusiveMillis) {
                            break
                        }
                        val day = epochMillisToLocalDate(earliest.occurredAt)
                        val (startMs, endMs) = dayRangeMillis(day)
                        if (targetEndExclusiveMillis != null && startMs >= targetEndExclusiveMillis) {
                            break
                        }
                        val effectiveEnd = targetEndExclusiveMillis?.let { min(endMs, it) } ?: endMs
                        val dayEvents = repository.loadUnprocessedEventsBetween(startMs, effectiveEnd)
                        if (dayEvents.isEmpty()) {
                            repository.markEventProcessed(earliest.id, containsUserContext = false)
                            continue
                        }
                        val result = processDailyAggregate(day, dayEvents, forceReprocess = false)
                        if (result.aggregatedEntity == null && result.processedEvents == 0) {
                            continue
                        }
                        processedDays += 1
                        val progress = if (totalDays == 0) {
                            1f
                        } else {
                            (processedDays.toFloat() / totalDays.toFloat()).coerceAtMost(1f)
                        }
                        _progressState.value = MemoryProgressState.Running(
                            processedCount = processedDays,
                            totalCount = totalDays,
                            progress = progress,
                            currentEventId = result.aggregatedEntity?.id,
                            currentEventExternalId = result.aggregatedEntity?.externalId,
                            currentEventType = result.aggregatedEntity?.type
                        )
                    }
                } else {
                    val processedDaySet = LinkedHashSet<LocalDate>()
                    while (true) {
                        val batch = repository.loadEventsAscending(batchSize, offset)
                        if (batch.isEmpty()) break
                        batch.forEach { entity ->
                            if (targetEndExclusiveMillis != null && entity.occurredAt >= targetEndExclusiveMillis) {
                                return@forEach
                            }
                            val day = epochMillisToLocalDate(entity.occurredAt)
                            val (startMs, endMs) = dayRangeMillis(day)
                            if (targetEndExclusiveMillis != null && startMs >= targetEndExclusiveMillis) {
                                return@forEach
                            }
                            if (!processedDaySet.add(day)) {
                                return@forEach
                            }
                            val effectiveEnd = targetEndExclusiveMillis?.let { min(endMs, it) } ?: endMs
                            val dayEvents = repository.loadEventsBetween(startMs, effectiveEnd)
                            if (dayEvents.isEmpty()) {
                                return@forEach
                            }
                            val result = processDailyAggregate(day, dayEvents, forceReprocess = true)
                            processedDays = processedDaySet.size
                            val progress = if (totalDays == 0) 1f else (processedDays.toFloat() / totalDays.toFloat()).coerceAtMost(1f)
                            _progressState.value = MemoryProgressState.Running(
                                processedCount = processedDays,
                                totalCount = totalDays,
                                progress = progress,
                                currentEventId = result.aggregatedEntity?.id,
                                currentEventExternalId = result.aggregatedEntity?.externalId,
                                currentEventType = result.aggregatedEntity?.type
                            )
                        }
                        offset += batch.size
                    }
                }

                val duration = System.currentTimeMillis() - startTime
                _progressState.value = MemoryProgressState.Completed(
                    totalCount = processedDays,
                    durationMillis = duration
                )
            } catch (t: Throwable) {
                when (t) {
                    is CancellationException -> {
                        FileLogger.i(TAG, "历史处理已取消")
                        _progressState.value = MemoryProgressState.Idle
                    }
                    is LlmHttpException -> {
                        FileLogger.e(TAG, "历史处理失败：HTTP ${t.statusCode}", t)
                        val raw = truncate(t.responseBody, MAX_METADATA_TEXT)
                        _progressState.value = MemoryProgressState.Failed(
                            processedCount = processedDays,
                            totalCount = totalDays,
                            errorMessage = "HTTP ${t.statusCode}",
                            rawResponse = raw,
                            failureCode = "http_${t.statusCode}",
                            failedEventExternalId = t.eventExternalId
                        )
                    }
                    is LlmEndpointConfigurationException -> {
                        FileLogger.e(TAG, "历史处理接口错误：${t.message}", t)
                        _progressState.value = MemoryProgressState.Failed(
                            processedCount = processedDays,
                            totalCount = totalDays,
                            errorMessage = t.message ?: FAILURE_ENDPOINT_INVALID,
                            failureCode = FAILURE_ENDPOINT_INVALID,
                            failedEventExternalId = t.eventExternalId
                        )
                    }
                    else -> {
                        FileLogger.e(TAG, "历史处理失败", t)
                        _progressState.value = MemoryProgressState.Failed(
                            processedCount = processedDays,
                            totalCount = totalDays,
                            errorMessage = t.message ?: t.toString()
                        )
                    }
                }
            } finally {
                initializing.set(false)
            }
        }
    }

    suspend fun getEventSummary(eventId: Long) = repository.getEventSummary(eventId)

    suspend fun searchGraph(
        query: String,
        depth: Int = 2,
        limit: Int = 80,
        includeHistory: Boolean = true
    ): Map<String, Any?> = withContext(scope.coroutineContext) {
        repository.searchGraph(query, depth, limit, includeHistory)
    }

    suspend fun buildWorkingMemory(
        query: String?,
        edgeLimit: Int = 60,
        includeHistoryEdges: Boolean = false
    ): Map<String, Any?> = withContext(scope.coroutineContext) {
        val normalizedQuery = query?.trim().orEmpty()
        val safeEdgeLimit = edgeLimit.coerceIn(10, 200)

        val personaSummary = personaSummaryState.value
        val personaProfile = personaProfileState.value
        val graphQuery = if (normalizedQuery.isBlank()) "我" else normalizedQuery
        val graph = repository.searchGraph(
            query = graphQuery,
            depth = 2,
            limit = safeEdgeLimit,
            includeHistory = includeHistoryEdges
        )
        val markdown = buildWorkingMemoryMarkdown(
            query = normalizedQuery,
            personaSummary = personaSummary,
            graph = graph,
            edgeLimit = safeEdgeLimit
        )
        mapOf(
            "query" to normalizedQuery,
            "generated_at" to System.currentTimeMillis(),
            "persona_summary" to personaSummary,
            "persona_profile" to personaProfile.toMap(),
            "graph" to graph,
            "working_memory_markdown" to markdown
        )
    }

    fun cancelInitialization() {
        initializationJob?.cancel()
        initializationJob = null
        initializing.set(false)
        _progressState.value = MemoryProgressState.Idle
    }

    private data class DailyAggregationResult(
        val processedEvents: Int,
        val aggregatedEntity: MemoryEventEntity?
    )

    private fun buildWorkingMemoryMarkdown(
        query: String,
        personaSummary: String,
        graph: Map<String, Any?>,
        edgeLimit: Int
    ): String {
        val sb = StringBuilder()
        sb.append("## 工作记忆（自动装配）\n")
        if (query.isNotBlank()) {
            sb.append("- query: ").append(query).append('\n')
        }
        sb.append('\n')

        val persona = personaSummary.trim()
        if (persona.isNotEmpty()) {
            sb.append("### Persona\n\n")
            sb.append(persona).append("\n\n")
        }

        val edges = (graph["edges"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
        if (edges.isNotEmpty()) {
            sb.append("### 相关图谱边\n\n")
            val maxEdges = edgeLimit.coerceIn(10, 60)
            edges.take(maxEdges).forEach { raw ->
                val subject = raw["subject_key"]?.toString().orEmpty()
                val predicate = raw["predicate"]?.toString().orEmpty()
                val objKey = raw["object_key"]?.toString()
                val objValue = raw["object_value"]?.toString()
                val objectText = when {
                    !objKey.isNullOrBlank() -> objKey
                    !objValue.isNullOrBlank() -> objValue
                    else -> "?"
                }
                sb.append("- ").append(subject).append(" --").append(predicate).append("--> ").append(objectText)
                val qualifiers = raw["qualifiers"]
                if (qualifiers is Map<*, *> && qualifiers.isNotEmpty()) {
                    sb.append(" ").append(qualifiers.entries.joinToString(prefix = "{", postfix = "}") { (k, v) ->
                        "${k.toString()}:${v.toString()}"
                    })
                }
                val evidence = raw["evidence"] as? List<*>
                val excerpt = (evidence?.firstOrNull() as? Map<*, *>)?.get("excerpt")?.toString()?.trim().orEmpty()
                if (excerpt.isNotBlank()) {
                    sb.append(" 证据：").append(truncate(excerpt, 120))
                }
                sb.append('\n')
            }
            sb.append('\n')
        }

        return sb.toString().trim()
    }

    private suspend fun countRemainingDays(
        forceReprocess: Boolean,
        targetEndExclusiveMillis: Long?
    ): Int {
        val timestamps = if (forceReprocess) {
            repository.loadAllTimestampsExcludingType(DAILY_EVENT_TYPE)
        } else {
            repository.loadUnprocessedTimestampsExcludingType(DAILY_EVENT_TYPE)
        }
        val filtered = targetEndExclusiveMillis?.let { cutoff ->
            timestamps.filter { it < cutoff }
        } ?: timestamps
        return countDistinctDays(filtered)
    }

    private fun countDistinctDays(timestamps: List<Long>): Int {
        if (timestamps.isEmpty()) return 0
        val days = LinkedHashSet<LocalDate>()
        timestamps.forEach { millis ->
            days.add(epochMillisToLocalDate(millis))
        }
        return days.size
    }

    private suspend fun processDailyAggregate(
        day: LocalDate,
        dayEvents: List<MemoryEventEntity>,
        forceReprocess: Boolean
    ): DailyAggregationResult {
        if (dayEvents.isEmpty()) {
            return DailyAggregationResult(0, null)
        }

        val baseEvents = dayEvents.filter { it.type != DAILY_EVENT_TYPE }.sortedBy { it.occurredAt }
        val existingAggregate = dayEvents.firstOrNull { it.type == DAILY_EVENT_TYPE }
        val processedEvents = baseEvents.size

        if (baseEvents.isEmpty() && existingAggregate == null) {
            return DailyAggregationResult(processedEvents, null)
        }

        val aggregateExternalId = buildAggregateExternalId(day)
        val aggregateMetadata: Map<String, String> = when {
            baseEvents.isNotEmpty() -> buildAggregateMetadata(day, baseEvents)
            existingAggregate != null -> existingAggregate.metadata
            else -> buildAggregateMetadata(day, emptyList())
        }
        val aggregateContent: String = when {
            baseEvents.isNotEmpty() -> buildAggregateContent(day, baseEvents)
            existingAggregate != null -> existingAggregate.content
            else -> ""
        }
        val aggregateOccurredAt = dayRangeMillis(day).first
        val aggregateEvent = UserEvent(
            externalId = aggregateExternalId,
            occurredAt = aggregateOccurredAt,
            type = DAILY_EVENT_TYPE,
            source = DAILY_EVENT_SOURCE,
            content = aggregateContent,
            metadata = aggregateMetadata
        )

        val aggregateEntity = repository.upsertEvent(aggregateEvent)
        FileLogger.i(
            TAG,
            "processDailyAggregate day=${day} baseEvents=${baseEvents.size} aggregateId=${aggregateEntity.id} force=$forceReprocess"
        )
        val userEvent = aggregateEntity.toDomain()
        val extraction = extractWithLlm(userEvent)
        val beforePersona = _personaSummaryState.value
        applyPersonaUpdateFromLlm(extraction.personaProfilePatch, extraction.personaSummaryFallback)

        val graphTimestamp = baseEvents.lastOrNull()?.occurredAt ?: aggregateEntity.occurredAt
        repository.applyGraphUpdates(
            eventId = aggregateEntity.id,
            eventTimestamp = graphTimestamp,
            eventContent = userEvent.content,
            graphEntities = extraction.graphEntities,
            graphEdges = extraction.graphEdges,
            graphEdgeClosures = extraction.graphEdgeClosures
        )

        val personaUpdated = _personaSummaryState.value != beforePersona
        val graphUpdated = extraction.graphEntities.isNotEmpty() ||
            extraction.graphEdges.isNotEmpty() ||
            extraction.graphEdgeClosures.isNotEmpty()
        val containsContext = personaUpdated || graphUpdated
        repository.markEventProcessed(aggregateEntity.id, containsUserContext = containsContext)
        baseEvents.forEach { repository.markEventProcessed(it.id, containsUserContext = containsContext) }

        return DailyAggregationResult(
            processedEvents = processedEvents,
            aggregatedEntity = aggregateEntity
        )
    }

    private fun epochMillisToLocalDate(millis: Long): LocalDate {
        return Instant.ofEpochMilli(millis).atZone(systemZone).toLocalDate()
    }

    private fun dayRangeMillis(day: LocalDate): Pair<Long, Long> {
        val start = day.atStartOfDay(systemZone).toInstant().toEpochMilli()
        val end = day.plusDays(1).atStartOfDay(systemZone).toInstant().toEpochMilli()
        return start to end
    }

    private fun buildAggregateExternalId(day: LocalDate): String {
        return "daily:${day.toString()}"
    }

    private fun buildAggregateMetadata(
        day: LocalDate,
        events: List<MemoryEventEntity>
    ): Map<String, String> {
        val (startMs, endMs) = dayRangeMillis(day)
        val payload = JSONArray()
        events.forEachIndexed { index, entity ->
            val item = JSONObject()
            item.put("index", index + 1)
            item.put("event_id", entity.externalId ?: entity.id.toString())
            item.put("occurred_at", entity.occurredAt)
            item.put("type", entity.type)
            item.put("source", entity.source)
            item.put("contains_user_context", entity.containsUserContext)
            val metadata = JSONObject()
            entity.metadata.forEach { (k, v) -> metadata.put(k, v) }
            item.put("metadata", metadata)
            item.put("content_preview", entity.content.take(400))
            payload.put(item)
        }
        val result = LinkedHashMap<String, String>()
        val isoTimestamp = DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(
            Instant.ofEpochMilli(startMs).atOffset(ZoneOffset.UTC)
        )
        result["event_id"] = buildAggregateExternalId(day)
        result["event_date"] = day.format(dateFormatter)
        result["event_timestamp"] = isoTimestamp
        result["aggregation_scope"] = "daily"
        result["day_start"] = startMs.toString()
        result["day_end_exclusive"] = endMs.toString()
        result["events_count"] = events.size.toString()
        result["aggregated_events"] = payload.toString()
        return result
    }

    private fun buildAggregateContent(
        day: LocalDate,
        events: List<MemoryEventEntity>
    ): String {
        if (events.isEmpty()) return ""
        val sorted = events.sortedBy { it.occurredAt }
        val selected = buildList {
            val preferred = sorted.filter { it.type != "segment" }
            addAll(preferred.take(DAILY_AGG_MAX_EVENT_ITEMS))
            if (size < DAILY_AGG_MAX_EVENT_ITEMS) {
                val remaining = DAILY_AGG_MAX_EVENT_ITEMS - size
                addAll(sorted.filter { it.type == "segment" }.take(remaining))
            }
        }.distinctBy { it.id }
        val selectedIds = selected.mapTo(LinkedHashSet()) { it.id }
        val omitted = sorted.filter { !selectedIds.contains(it.id) }
        val omittedCount = omitted.size
        val sb = StringBuilder()
        sb.append("日期：").append(day.format(dateFormatter)).append('\n')
        sb.append("事件数量：").append(sorted.size).append('\n')
        if (omittedCount > 0) {
            sb.append("（已筛选 ").append(selected.size).append(" 条高信息量事件；省略 ").append(omittedCount).append(" 条）\n")
        }
        sb.append('\n')
        selected.forEachIndexed { index, entity ->
            sb.append("【事件 ").append(index + 1).append("】")
            sb.append(formatEventTimeRange(entity))
            val originParts = mutableListOf<String>()
            if (entity.source.isNotBlank()) originParts += "来源：${entity.source}"
            if (entity.type.isNotBlank()) originParts += "类型：${entity.type}"
            if (originParts.isNotEmpty()) {
                sb.append(' ').append(originParts.joinToString(" | "))
            }
            sb.append('\n')
            sb.append(truncate(entity.content.trim(), DAILY_AGG_EVENT_CONTENT_LIMIT)).append('\n')
            val metaSummary = summarizeMetadata(entity.metadata)
            if (metaSummary.isNotEmpty()) {
                sb.append(metaSummary).append('\n')
            }
            sb.append('\n')
        }
        if (omittedCount > 0) {
            val typeCounts = omitted
                .groupingBy { it.type.ifBlank { "(unknown)" } }
                .eachCount()
                .entries
                .sortedByDescending { it.value }
                .take(8)
                .joinToString("，") { (k, v) -> "$k=$v" }
            if (typeCounts.isNotBlank()) {
                sb.append("省略事件类型统计：").append(typeCounts).append('\n')
            }
        }
        return sb.toString().trim()
    }

    private fun formatEventTimeRange(entity: MemoryEventEntity): String {
        val start = entity.metadata["segment_start"]?.toLongOrNull()
        val end = entity.metadata["segment_end"]?.toLongOrNull()
        return if (start != null && end != null) {
            val startLocal = Instant.ofEpochMilli(start).atZone(systemZone).toLocalTime().format(timeFormatter)
            val endLocal = Instant.ofEpochMilli(end).atZone(systemZone).toLocalTime().format(timeFormatter)
            "时间：$startLocal-$endLocal"
        } else {
            val ts = Instant.ofEpochMilli(entity.occurredAt).atZone(systemZone).toLocalTime().format(timeFormatter)
            "时间：$ts"
        }
    }

    private fun summarizeMetadata(metadata: Map<String, String>): String {
        if (metadata.isEmpty()) return ""
        val keys = listOf(
            "segment_id",
            "segment_app_packages",
            "segment_status",
            "ai_provider",
            "ai_model",
            "conversation_cid",
            "role"
        )
        val parts = keys.mapNotNull { key ->
            metadata[key]?.takeIf { it.isNotBlank() }?.let { "$key=$it" }
        }
        return if (parts.isEmpty()) "" else "关键信息：" + parts.joinToString("，")
    }

    private fun MemoryEventEntity.toDomain(): UserEvent {
        return UserEvent(
            externalId = externalId,
            occurredAt = occurredAt,
            type = type,
            source = source,
            content = content,
            metadata = metadata
        )
    }

    private fun truncate(text: String, maxLength: Int): String {
        if (text.length <= maxLength) return text
        return text.substring(0, maxLength - 3) + "..."
    }

    private suspend fun applyPersonaUpdateFromLlm(
        patch: PersonaProfilePatch?,
        fallbackSummary: String?
    ) {
        if (patch == null) {
            val sanitized = fallbackSummary?.trim()
            if (!sanitized.isNullOrEmpty()) {
                _personaSummaryState.value = sanitized
                if (usingFallbackSummary) {
                    _personaProfileState.value = PersonaProfile.fromLegacySummary(sanitized)
                }
                usingFallbackSummary = false
                try {
                    repository.savePersonaSummary(sanitized)
                } catch (t: Throwable) {
                    FileLogger.e(TAG, "持久化人设摘要兜底结果失败", t)
                }
            }
            return
        }

        val currentProfile = _personaProfileState.value
        val updatedProfile = currentProfile.applyPatch(patch)
        _personaProfileState.value = updatedProfile
        val markdown = updatedProfile.toMarkdown()
        _personaSummaryState.value = markdown
        usingFallbackSummary = false
        try {
            repository.savePersonaProfile(updatedProfile)
            repository.savePersonaSummary(markdown)
        } catch (t: Throwable) {
            FileLogger.e(TAG, "持久化人设档案失败", t)
        }
    }

    private fun maybeRefreshPersonaSummary(snapshot: MemorySnapshot) {
        val current = _personaSummaryState.value
        if (current.isBlank()) {
            val regenerated = snapshot.personaProfile.toMarkdown().ifBlank { DEFAULT_PERSONA_SUMMARY }
            _personaSummaryState.value = regenerated
        }
    }

    private fun buildFallbackPersonaSummary(snapshot: MemorySnapshot): String {
        val markdown = snapshot.personaProfile.toMarkdown()
        return if (markdown.isNotBlank()) markdown else DEFAULT_PERSONA_SUMMARY
    }

    suspend fun loadRecentEvents(
        limit: Int,
        offset: Int
    ): List<MemoryEventSummary> = repository.loadRecentEventsPaged(limit, offset)

    suspend fun clearAllMemoryData() {
        withContext(scope.coroutineContext) {
            repository.clearAllMemoryData()
            _snapshotState.value = MemorySnapshot(
                recentEvents = emptyList(),
                recentEventTotalCount = 0,
                lastUpdatedAt = System.currentTimeMillis(),
                personaSummary = DEFAULT_PERSONA_SUMMARY,
                personaProfile = PersonaProfile.default()
            )
            _progressState.value = MemoryProgressState.Idle
            _personaSummaryState.value = DEFAULT_PERSONA_SUMMARY
            _personaProfileState.value = PersonaProfile.default()
            usingFallbackSummary = true
            try {
                repository.clearPersonaSummary()
            } catch (t: Throwable) {
                FileLogger.e(TAG, "清理人设摘要元数据失败", t)
            }
            try {
                repository.clearPersonaProfile()
            } catch (t: Throwable) {
                FileLogger.e(TAG, "清理人设档案元数据失败", t)
            }
        }
    }

    suspend fun processSampleHistoricalEvents(limit: Int = SAMPLE_TEST_EVENT_LIMIT): Int {
        return withContext(scope.coroutineContext) {
            if (initializing.get()) {
                FileLogger.w(TAG, "跳过处理历史样本事件：初始化进行中")
                return@withContext 0
            }
            val safeLimit = limit.coerceAtLeast(1)
            val totalPendingDays = countRemainingDays(
                forceReprocess = false,
                targetEndExclusiveMillis = null
            )
            val targetDays = min(safeLimit, totalPendingDays)
            if (targetDays == 0) {
                _progressState.value = MemoryProgressState.Idle
                return@withContext 0
            }

            val start = System.currentTimeMillis()
            _progressState.value = MemoryProgressState.Running(
                processedCount = 0,
                totalCount = targetDays,
                progress = 0f,
                currentEventId = null,
                currentEventExternalId = null,
                currentEventType = null
            )

            var processedDays = 0
            while (processedDays < targetDays) {
                val earliest = repository.getEarliestUnprocessedEvent() ?: break
                val day = epochMillisToLocalDate(earliest.occurredAt)
                val (startMs, endMs) = dayRangeMillis(day)
                val dayEvents = repository.loadUnprocessedEventsBetween(startMs, endMs)
                if (dayEvents.isEmpty()) {
                    repository.markEventProcessed(earliest.id, containsUserContext = false)
                    continue
                }
                val result = processDailyAggregate(day, dayEvents, forceReprocess = false)
                if (result.aggregatedEntity == null && result.processedEvents == 0) {
                    continue
                }
                processedDays += 1
                val progress = (processedDays.toFloat() / targetDays.toFloat()).coerceAtMost(1f)
                _progressState.value = MemoryProgressState.Running(
                    processedCount = min(processedDays, targetDays),
                    totalCount = targetDays,
                    progress = progress,
                    currentEventId = result.aggregatedEntity?.id,
                    currentEventExternalId = result.aggregatedEntity?.externalId,
                    currentEventType = result.aggregatedEntity?.type
                )
                if (processedDays >= targetDays) {
                    break
                }
            }

            val duration = System.currentTimeMillis() - start
            _progressState.value = if (processedDays > 0) {
                MemoryProgressState.Completed(
                    totalCount = min(processedDays, targetDays),
                    durationMillis = duration
                )
            } else {
                MemoryProgressState.Idle
            }
            processedDays
        }
    }

    companion object {
        private const val TAG = "MemoryEngine"
        private const val SNAPSHOT_RECENT_EVENT_LIMIT = 20
        private const val DEFAULT_BATCH_SIZE = 40
        private const val SEGMENT_SYNC_BATCH = 50
        private const val MAX_METADATA_TEXT = 4000
        private const val DEFAULT_PERSONA_SUMMARY = ""
        private const val FAILURE_ENDPOINT_INVALID = "endpoint_invalid"
        private const val DAILY_EVENT_TYPE = "daily_aggregate"
        private const val DAILY_EVENT_SOURCE = "memory_engine"
        private const val DAILY_AGG_MAX_EVENT_ITEMS = 40
        private const val DAILY_AGG_EVENT_CONTENT_LIMIT = 280
        const val SAMPLE_TEST_EVENT_LIMIT = 30

        @Volatile
        private var instance: MemoryEngine? = null

        fun getInstance(context: Context): MemoryEngine {
            return instance ?: synchronized(this) {
                instance ?: createInstance(context.applicationContext).also { instance = it }
            }
        }

        private fun createInstance(appContext: Context): MemoryEngine {
            val database = MemoryDatabase.getInstance(appContext)
            val repository = MemoryRepository(database.memoryDao())
            return MemoryEngine(repository)
        }
    }
}

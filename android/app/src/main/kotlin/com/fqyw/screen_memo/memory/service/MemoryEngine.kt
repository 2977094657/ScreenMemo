package com.fqyw.screen_memo.memory.service

import android.content.Context
import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.SegmentDatabaseHelper
import com.fqyw.screen_memo.memory.data.MemoryRepository
import com.fqyw.screen_memo.memory.data.MemoryRepository.TagUpdateResult
import com.fqyw.screen_memo.memory.data.db.MemoryDatabase
import com.fqyw.screen_memo.memory.data.db.MemoryEventEntity
import com.fqyw.screen_memo.memory.model.MemoryEventSummary
import com.fqyw.screen_memo.memory.model.MemoryProgressState
import com.fqyw.screen_memo.memory.model.MemorySnapshot
import com.fqyw.screen_memo.memory.model.TagStatus
import com.fqyw.screen_memo.memory.model.TagCategory
import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.model.UserTag
import com.fqyw.screen_memo.memory.processor.LlmEndpointConfigurationException
import com.fqyw.screen_memo.memory.processor.LlmHttpException
import com.fqyw.screen_memo.memory.processor.LlmUserSignalExtractor
import com.fqyw.screen_memo.memory.processor.UserSignalExtractionResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.HashMap
import java.util.LinkedHashMap
import java.util.LinkedHashSet
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

class MemoryEngine private constructor(
    private val repository: MemoryRepository
) {

    data class TagUpdateEvent(
        val tag: UserTag,
        val isNewTag: Boolean,
        val statusChanged: Boolean
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _snapshotState = MutableStateFlow(MemorySnapshot(personaSummary = DEFAULT_PERSONA_SUMMARY))
    val snapshotState: StateFlow<MemorySnapshot> = _snapshotState

    private val _progressState = MutableStateFlow<MemoryProgressState>(MemoryProgressState.Idle)
    val progressState: StateFlow<MemoryProgressState> = _progressState

    private val _personaSummaryState = MutableStateFlow(DEFAULT_PERSONA_SUMMARY)
    private var usingFallbackSummary = true
    val personaSummaryState: StateFlow<String> = _personaSummaryState

    private val _tagUpdateEvents = MutableSharedFlow<TagUpdateEvent>(
        replay = 0,
        extraBufferCapacity = 64
    )
    val tagUpdateEvents: SharedFlow<TagUpdateEvent> = _tagUpdateEvents

    private val initializing = AtomicBoolean(false)
    private var initializationJob: Job? = null
    @Volatile
    private var extractionContext: ExtractionContext? = null
    private val llmExtractor = LlmUserSignalExtractor()

    init {
        observeSnapshotStreams()
        scope.launch {
            try {
                val stored = repository.loadPersonaSummary()
                val sanitized = stored?.trim().orEmpty()
                if (sanitized.isNotEmpty()) {
                    _personaSummaryState.value = sanitized
                    usingFallbackSummary = false
                }
            } catch (t: Throwable) {
                FileLogger.e(TAG, "Failed to load persona summary from repository", t)
            }
        }
    }

    suspend fun syncSegments(context: Context, batchSize: Int = SEGMENT_SYNC_BATCH): Int {
        return withContext(scope.coroutineContext) {
            val totalSegments = SegmentDatabaseHelper.countSegments(context)
            if (totalSegments == 0) {
                FileLogger.i(TAG, "syncSegments: no segments found")
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
                        FileLogger.e(TAG, "syncSegments: failed to ingest segment ${segment.id}", t)
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

    private suspend fun extractWithLlm(event: UserEvent): UserSignalExtractionResult {
        val context = extractionContext
        if (context == null || !context.isValid) {
            FileLogger.w(TAG, "LLM extraction skipped due to missing extraction context")
            return UserSignalExtractionResult(emptyList(), null)
        }
        val existingTagPaths = repository.listAllTagPaths()
        val currentPersona = personaSummaryState.value
        return llmExtractor.extractSignals(event, context, existingTagPaths, currentPersona)
    }

    private fun observeSnapshotStreams() {
        scope.launch {
            val baseSnapshotFlow = combine(
                repository.observeTagsByStatus(TagStatus.PENDING, SNAPSHOT_PENDING_LIMIT),
                repository.observeTagsByStatus(TagStatus.CONFIRMED, SNAPSHOT_CONFIRMED_LIMIT),
                repository.observeRecentEvents(SNAPSHOT_RECENT_EVENT_LIMIT),
                repository.observeTagCountByStatus(TagStatus.PENDING),
                repository.observeTagCountByStatus(TagStatus.CONFIRMED)
            ) { pending: List<UserTag>,
                confirmed: List<UserTag>,
                events: List<MemoryEventSummary>,
                pendingCount: Int,
                confirmedCount: Int ->
                MemorySnapshot(
                    pendingTags = pending,
                    confirmedTags = confirmed,
                    recentEvents = events,
                    pendingTotalCount = pendingCount,
                    confirmedTotalCount = confirmedCount,
                    recentEventTotalCount = events.size,
                    lastUpdatedAt = System.currentTimeMillis(),
                    personaSummary = ""
                )
            }

            baseSnapshotFlow
                .combine(personaSummaryState) { snapshot, persona ->
                    snapshot.copy(personaSummary = persona)
                }
                .collect { snapshot ->
                _snapshotState.value = snapshot
                maybeRefreshPersonaSummary(snapshot)
                }
        }
    }

    suspend fun ingestEvent(event: UserEvent) {
        withContext(scope.coroutineContext) {
            val entity = repository.upsertEvent(event)
            val extraction = extractWithLlm(event)
            updatePersonaSummaryFromLlm(extraction.personaSummary)
            if (extraction.candidates.isEmpty()) {
                repository.markEventProcessed(entity.id, containsUserContext = false)
                return@withContext
            }

            val tagEvents = mutableListOf<TagUpdateEvent>()
            extraction.candidates.forEach { candidate ->
                val result = repository.upsertTagWithEvidence(
                    candidate = candidate,
                    eventId = entity.id,
                    eventTimestamp = event.occurredAt
                )
                tagEvents += result.toUpdateEvent()
            }

            repository.markEventProcessed(entity.id, containsUserContext = true)

            // 发出标签更新事件
            tagEvents.forEach { update -> _tagUpdateEvents.emit(update) }
        }
    }

    fun initializeHistoricalProcessing(forceReprocess: Boolean = false, batchSize: Int = DEFAULT_BATCH_SIZE) {
        if (initializing.compareAndSet(false, true).not()) {
            return
        }

        initializationJob = scope.launch {
            val startTime = System.currentTimeMillis()
            val total = repository.countAllEvents()
            var processed = 0
            var offset = 0
            try {
                _progressState.value = MemoryProgressState.Running(
                    processedCount = 0,
                    totalCount = total,
                    progress = if (total == 0) 1f else 0f,
                    currentEventId = null,
                    currentEventExternalId = null,
                    currentEventType = null,
                    newlyDiscoveredTags = emptyList()
                )

                while (true) {
                    val batch = repository.loadEventsAscending(batchSize, offset)
                    if (batch.isEmpty()) break
                    batch.forEach { entity ->
                        val shouldProcess = forceReprocess || entity.processedAt == null
                        val newlyDiscovered = if (shouldProcess) {
                            processHistoricalEvent(entity)
                        } else {
                            emptyList()
                        }
                        processed += 1
                        val progress = if (total == 0) 1f else processed.toFloat() / total.toFloat()
                        _progressState.value = MemoryProgressState.Running(
                            processedCount = processed,
                            totalCount = total,
                            progress = progress,
                            currentEventId = entity.id,
                            currentEventExternalId = entity.externalId,
                            currentEventType = entity.type,
                            newlyDiscoveredTags = newlyDiscovered
                        )
                    }
                    offset += batch.size
                }

                val duration = System.currentTimeMillis() - startTime
                _progressState.value = MemoryProgressState.Completed(
                    totalCount = total,
                    durationMillis = duration
                )
            } catch (t: Throwable) {
                when (t) {
                    is CancellationException -> {
                        FileLogger.i(TAG, "Historical processing cancelled")
                        _progressState.value = MemoryProgressState.Idle
                    }
                    is LlmHttpException -> {
                        FileLogger.e(TAG, "Historical processing failed with HTTP ${t.statusCode}", t)
                        val raw = truncate(t.responseBody, MAX_METADATA_TEXT)
                        _progressState.value = MemoryProgressState.Failed(
                            processedCount = processed,
                            totalCount = total,
                            errorMessage = "HTTP ${t.statusCode}",
                            rawResponse = raw,
                            failureCode = "http_${t.statusCode}",
                            failedEventExternalId = t.eventExternalId
                        )
                    }
                    is LlmEndpointConfigurationException -> {
                        FileLogger.e(TAG, "Historical processing endpoint error: ${t.message}", t)
                        _progressState.value = MemoryProgressState.Failed(
                            processedCount = processed,
                            totalCount = total,
                            errorMessage = t.message ?: FAILURE_ENDPOINT_INVALID,
                            failureCode = FAILURE_ENDPOINT_INVALID,
                            failedEventExternalId = t.eventExternalId
                        )
                    }
                    else -> {
                        FileLogger.e(TAG, "Historical processing failed", t)
                        _progressState.value = MemoryProgressState.Failed(
                            processedCount = processed,
                            totalCount = total,
                            errorMessage = t.message ?: t.toString()
                        )
                    }
                }
            } finally {
                initializing.set(false)
            }
        }
    }

    suspend fun confirmTag(tagId: Long, confirmedByUser: Boolean = true): UserTag? {
        return repository.confirmTag(tagId, confirmedByUser)?.also {
            _tagUpdateEvents.emit(TagUpdateEvent(it, isNewTag = false, statusChanged = true))
        }
    }

    suspend fun updateEvidence(
        evidenceId: Long,
        newExcerpt: String,
        notes: String?,
        markAsUserEdited: Boolean
    ) = repository.updateEvidence(evidenceId, newExcerpt, notes, markAsUserEdited)

    suspend fun getTag(tagId: Long): UserTag? = repository.getTagById(tagId)

    suspend fun getEventSummary(eventId: Long) = repository.getEventSummary(eventId)

    suspend fun deleteTag(tagId: Long): Boolean = withContext(scope.coroutineContext) {
        val removed = repository.deleteTag(tagId)
        if (removed) {
            val current = _snapshotState.value
            val pendingFiltered = current.pendingTags.filterNot { it.id.toLong() == tagId }
            val confirmedFiltered = current.confirmedTags.filterNot { it.id.toLong() == tagId }
            val pendingRemoved = current.pendingTags.size - pendingFiltered.size
            val confirmedRemoved = current.confirmedTags.size - confirmedFiltered.size
            _snapshotState.value = current.copy(
                pendingTags = pendingFiltered,
                confirmedTags = confirmedFiltered,
                pendingTotalCount = (current.pendingTotalCount - pendingRemoved).coerceAtLeast(0),
                confirmedTotalCount = (current.confirmedTotalCount - confirmedRemoved).coerceAtLeast(0)
            )
        }
        removed
    }

    fun cancelInitialization() {
        initializationJob?.cancel()
        initializationJob = null
        initializing.set(false)
        _progressState.value = MemoryProgressState.Idle
    }

    private suspend fun processHistoricalEvent(entity: MemoryEventEntity): List<String> {
        val event = entity.toDomain()
        val extraction = extractWithLlm(event)
        updatePersonaSummaryFromLlm(extraction.personaSummary)
        if (extraction.candidates.isEmpty()) {
            repository.markEventProcessed(entity.id, containsUserContext = false)
            return emptyList()
        }

        val newTags = mutableListOf<String>()
        extraction.candidates.forEach { candidate ->
            val result = repository.upsertTagWithEvidence(
                candidate = candidate,
                eventId = entity.id,
                eventTimestamp = entity.occurredAt
            )
            if (result.isNewTag || result.statusChanged) {
                newTags += result.tag.label
                _tagUpdateEvents.emit(result.toUpdateEvent())
            }
        }

        repository.markEventProcessed(entity.id, containsUserContext = true)
        return newTags
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

    private fun TagUpdateResult.toUpdateEvent(): TagUpdateEvent {
        return TagUpdateEvent(
            tag = tag,
            isNewTag = isNewTag,
            statusChanged = statusChanged
        )
    }

    private fun truncate(text: String, maxLength: Int): String {
        if (text.length <= maxLength) return text
        return text.substring(0, maxLength - 3) + "..."
    }

    private suspend fun updatePersonaSummaryFromLlm(summary: String?) {
        val sanitized = summary?.trim()
        if (!sanitized.isNullOrEmpty()) {
            _personaSummaryState.value = sanitized
            usingFallbackSummary = false
            try {
                repository.savePersonaSummary(sanitized)
            } catch (t: Throwable) {
                FileLogger.e(TAG, "Failed to persist persona summary", t)
            }
        }
    }

    private fun maybeRefreshPersonaSummary(snapshot: MemorySnapshot) {
        val current = _personaSummaryState.value
        if (current.isBlank()) {
            _personaSummaryState.value = DEFAULT_PERSONA_SUMMARY
        }
    }

    private fun buildFallbackPersonaSummary(snapshot: MemorySnapshot): String {
        return DEFAULT_PERSONA_SUMMARY
    }

    private fun buildTagExplanation(tag: UserTag): String {
        val evidence = tag.evidences.firstOrNull()
        val raw = evidence?.notes?.takeIf { !it.isNullOrBlank() }?.trim()
            ?: evidence?.excerpt?.takeIf { !it.isNullOrBlank() }?.trim()
        val text = raw?.replace('\n', ' ')?.take(MAX_EXPLANATION_LENGTH)
        val sentence = text?.let {
            val t = it.trim()
            if (t.isEmpty()) null else t
        } ?: "该特征仍需更多上下文支撑。"
        val endsWithPunctuation = sentence.endsWith('。') ||
            sentence.endsWith('.') ||
            sentence.endsWith('!') ||
            sentence.endsWith('！') ||
            sentence.endsWith('?') ||
            sentence.endsWith('？')
        return if (endsWithPunctuation) sentence else "$sentence。"
    }

    suspend fun loadTagsByStatus(
        status: TagStatus,
        limit: Int,
        offset: Int
    ): List<UserTag> = repository.loadTagsByStatus(status, limit, offset)

    suspend fun loadRecentEvents(
        limit: Int,
        offset: Int
    ): List<MemoryEventSummary> = repository.loadRecentEventsPaged(limit, offset)

    suspend fun clearAllMemoryData() {
        withContext(scope.coroutineContext) {
            repository.clearAllMemoryData()
            _snapshotState.value = MemorySnapshot(
                pendingTags = emptyList(),
                confirmedTags = emptyList(),
                recentEvents = emptyList(),
                pendingTotalCount = 0,
                confirmedTotalCount = 0,
                recentEventTotalCount = 0,
                lastUpdatedAt = System.currentTimeMillis(),
                personaSummary = DEFAULT_PERSONA_SUMMARY
            )
            _progressState.value = MemoryProgressState.Idle
            _personaSummaryState.value = DEFAULT_PERSONA_SUMMARY
            usingFallbackSummary = true
            try {
                repository.clearPersonaSummary()
            } catch (t: Throwable) {
                FileLogger.e(TAG, "Failed to clear persona summary metadata", t)
            }
        }
    }

    suspend fun processSampleHistoricalEvents(limit: Int = SAMPLE_TEST_EVENT_LIMIT): Int {
        return withContext(scope.coroutineContext) {
            if (initializing.get()) {
                FileLogger.w(TAG, "processSampleHistoricalEvents skipped: initialization in progress")
                return@withContext 0
            }
            val safeLimit = limit.coerceAtLeast(1)
            val totalUnprocessed = repository.countUnprocessedEvents()
            val target = min(safeLimit, totalUnprocessed)
            if (target == 0) {
                _progressState.value = MemoryProgressState.Idle
                return@withContext 0
            }

            val start = System.currentTimeMillis()
            _progressState.value = MemoryProgressState.Running(
                processedCount = 0,
                totalCount = target,
                progress = 0f,
                currentEventId = null,
                currentEventExternalId = null,
                currentEventType = null,
                newlyDiscoveredTags = emptyList()
            )

            var processed = 0
            while (processed < target) {
                val batchSize = min(DEFAULT_BATCH_SIZE, target - processed)
                val batch = repository.loadUnprocessedEvents(batchSize)
                if (batch.isEmpty()) {
                    break
                }
                for (entity in batch) {
                    val newlyDiscovered = processHistoricalEvent(entity)
                    processed += 1
                    val progress = processed.toFloat() / target.toFloat()
                    _progressState.value = MemoryProgressState.Running(
                        processedCount = processed,
                        totalCount = target,
                        progress = progress,
                        currentEventId = entity.id,
                        currentEventExternalId = entity.externalId,
                        currentEventType = entity.type,
                        newlyDiscoveredTags = newlyDiscovered
                    )
                    if (processed >= target) {
                        break
                    }
                }
            }

            val duration = System.currentTimeMillis() - start
            _progressState.value = if (processed > 0) {
                MemoryProgressState.Completed(
                    totalCount = processed,
                    durationMillis = duration
                )
            } else {
                MemoryProgressState.Idle
            }
            processed
        }
    }

    companion object {
        private const val TAG = "MemoryEngine"
        private const val SNAPSHOT_PENDING_LIMIT = 20
        private const val SNAPSHOT_CONFIRMED_LIMIT = 20
        private const val SNAPSHOT_RECENT_EVENT_LIMIT = 20
        private const val DEFAULT_BATCH_SIZE = 40
        private const val SEGMENT_SYNC_BATCH = 50
        private const val MAX_METADATA_TEXT = 4000
        private const val FALLBACK_SUMMARY_TAG_LIMIT = 3
        private const val DEFAULT_PERSONA_SUMMARY = ""
        private const val MAX_EXPLANATION_LENGTH = 160
        private const val FAILURE_ENDPOINT_INVALID = "endpoint_invalid"
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


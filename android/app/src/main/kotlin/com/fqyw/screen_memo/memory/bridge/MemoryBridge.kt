package com.fqyw.screen_memo.memory.bridge

import android.content.Context
import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.memory.model.MemoryEventSummary
import com.fqyw.screen_memo.memory.model.MemoryProgressState
import com.fqyw.screen_memo.memory.model.MemorySnapshot
import com.fqyw.screen_memo.memory.model.TagEvidence
import com.fqyw.screen_memo.memory.model.TagStatus
import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.model.UserTag
import com.fqyw.screen_memo.memory.service.ExtractionContext
import com.fqyw.screen_memo.memory.service.MemoryBackendService
import com.fqyw.screen_memo.memory.service.MemoryEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MemoryBridge(
    private val appContext: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val snapshotChannel = EventChannel(messenger, SNAPSHOT_CHANNEL_NAME)
    private val progressChannel = EventChannel(messenger, PROGRESS_CHANNEL_NAME)
    private val tagUpdateChannel = EventChannel(messenger, TAG_UPDATE_CHANNEL_NAME)

    private val scope = CoroutineScope(Dispatchers.Main.immediate + Job())
    private val memoryEngine = MemoryEngine.getInstance(appContext)

    init {
        methodChannel.setMethodCallHandler(this)
        snapshotChannel.setStreamHandler(SnapshotStreamHandler())
        progressChannel.setStreamHandler(ProgressStreamHandler())
        tagUpdateChannel.setStreamHandler(TagUpdateStreamHandler())
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "memory#startService" -> handleStartService(result)
            "memory#setExtractionContext" -> handleSetExtractionContext(call, result)
            "memory#initialize" -> handleInitialize(call, result)
            "memory#syncSegments" -> handleSyncSegments(result)
            "memory#loadTags" -> handleLoadTags(call, result)
            "memory#loadRecentEvents" -> handleLoadRecentEvents(call, result)
            "memory#ingestEvent" -> handleIngestEvent(call, result)
            "memory#confirmTag" -> handleConfirmTag(call, result)
            "memory#updateEvidence" -> handleUpdateEvidence(call, result)
            "memory#deleteTag" -> handleDeleteTag(call, result)
            "memory#getSnapshot" -> handleGetSnapshot(result)
            "memory#getTag" -> handleGetTag(call, result)
            "memory#getEvent" -> handleGetEvent(call, result)
            "memory#processSampleEvents" -> handleProcessSampleEvents(call, result)
            "memory#clearMemoryData" -> handleClearMemoryData(result)
            "memory#cancelInitialization" -> handleCancelInitialization(result)
            else -> result.notImplemented()
        }
    }

    private fun handleSyncSegments(result: MethodChannel.Result) {
        scope.launch {
            try {
                val count = memoryEngine.syncSegments(appContext)
                result.success(count)
            } catch (t: Throwable) {
                FileLogger.e(TAG, "syncSegments failed", t)
                result.error("sync_segments_failed", t.message, null)
            }
        }
    }

    private fun handleLoadTags(call: MethodCall, result: MethodChannel.Result) {
        val statusStr = call.argument<String>("status")
        val offset = (call.argument<Number>("offset") ?: 0).toInt().coerceAtLeast(0)
        val limit = (call.argument<Number>("limit") ?: SNAPSHOT_TAG_LIMIT).toInt().coerceAtLeast(1)
        val status = when (statusStr) {
            "pending" -> TagStatus.PENDING
            "confirmed" -> TagStatus.CONFIRMED
            else -> {
                result.error("invalid_args", "status must be pending or confirmed", statusStr)
                return
            }
        }
        scope.launch {
            try {
                val tags = memoryEngine.loadTagsByStatus(status, limit, offset)
                result.success(tags.map { it.toMap() })
            } catch (t: Throwable) {
                FileLogger.e(TAG, "loadTags failed", t)
                result.error("load_tags_failed", t.message, null)
            }
        }
    }

    private fun handleLoadRecentEvents(call: MethodCall, result: MethodChannel.Result) {
        val offset = (call.argument<Number>("offset") ?: 0).toInt().coerceAtLeast(0)
        val limit = (call.argument<Number>("limit") ?: SNAPSHOT_EVENT_LIMIT).toInt().coerceAtLeast(1)
        scope.launch {
            try {
                val events = memoryEngine.loadRecentEvents(limit, offset)
                result.success(events.map { it.toMap() })
            } catch (t: Throwable) {
                FileLogger.e(TAG, "loadRecentEvents failed", t)
                result.error("load_events_failed", t.message, null)
            }
        }
    }

    private fun handleSetExtractionContext(call: MethodCall, result: MethodChannel.Result) {
        val ctxMap = call.argument<Map<String, Any?>>("context")
        val ctx = ExtractionContext.fromMap(ctxMap)
        memoryEngine.setExtractionContext(ctx)
        result.success(true)
    }

    fun dispose() {
        scope.cancel()
        methodChannel.setMethodCallHandler(null)
        snapshotChannel.setStreamHandler(null)
        progressChannel.setStreamHandler(null)
        tagUpdateChannel.setStreamHandler(null)
        memoryEngine.setExtractionContext(null)
    }

    private fun handleStartService(result: MethodChannel.Result) {
        try {
            MemoryBackendService.start(appContext)
            result.success(true)
        } catch (t: Throwable) {
            FileLogger.e(TAG, "Failed to start MemoryBackendService", t)
            result.error("start_service_failed", t.message, null)
        }
    }

    private fun handleInitialize(call: MethodCall, result: MethodChannel.Result) {
        val forceReprocess = call.argument<Boolean>("forceReprocess") ?: false
        MemoryBackendService.startHistoricalProcessing(appContext, forceReprocess)
        result.success(true)
    }

    private fun handleCancelInitialization(result: MethodChannel.Result) {
        memoryEngine.cancelInitialization()
        result.success(true)
    }

    private fun handleIngestEvent(call: MethodCall, result: MethodChannel.Result) {
        val eventMap = call.argument<Map<String, Any?>>("event")
        if (eventMap == null) {
            result.error("invalid_args", "event map is required", null)
            return
        }
        val event = eventMap.toUserEvent()
        if (event == null) {
            result.error("invalid_args", "event map missing required fields", eventMap)
            return
        }
        scope.launch {
            try {
                memoryEngine.ingestEvent(event)
                result.success(true)
            } catch (t: Throwable) {
                FileLogger.e(TAG, "ingestEvent failed", t)
                result.error("ingest_failed", t.message, null)
            }
        }
    }

    private fun handleConfirmTag(call: MethodCall, result: MethodChannel.Result) {
        val tagId = call.argument<Number>("tagId")?.toLong()
        if (tagId == null) {
            result.error("invalid_args", "tagId is required", null)
            return
        }
        scope.launch {
            val tag = memoryEngine.confirmTag(tagId, confirmedByUser = true)
            result.success(tag?.toMap())
        }
    }

    private fun handleUpdateEvidence(call: MethodCall, result: MethodChannel.Result) {
        val evidenceId = call.argument<Number>("evidenceId")?.toLong()
        val excerpt = call.argument<String>("excerpt") ?: ""
        val notes = call.argument<String>("notes")
        val markEdited = call.argument<Boolean>("markUserEdited") ?: true
        if (evidenceId == null) {
            result.error("invalid_args", "evidenceId is required", null)
            return
        }
        scope.launch {
            val evidence = memoryEngine.updateEvidence(evidenceId, excerpt, notes, markEdited)
            result.success(evidence?.toMap())
        }
    }
    
    private fun handleDeleteTag(call: MethodCall, result: MethodChannel.Result) {
        val tagId = call.argument<Number>("tagId")?.toLong()
        if (tagId == null) {
            result.error("invalid_args", "tagId is required", null)
            return
        }
        scope.launch {
            try {
                val removed = memoryEngine.deleteTag(tagId)
                result.success(removed)
            } catch (t: Throwable) {
                FileLogger.e(TAG, "deleteTag failed", t)
                result.error("delete_tag_failed", t.message, null)
            }
        }
    }

    private fun handleGetSnapshot(result: MethodChannel.Result) {
        result.success(memoryEngine.snapshotState.value.toMap())
    }

    private fun handleGetTag(call: MethodCall, result: MethodChannel.Result) {
        val tagId = call.argument<Number>("tagId")?.toLong()
        if (tagId == null) {
            result.error("invalid_args", "tagId is required", null)
            return
        }
        scope.launch {
            val tag = memoryEngine.getTag(tagId)
            result.success(tag?.toMap())
        }
    }

    private fun handleGetEvent(call: MethodCall, result: MethodChannel.Result) {
        val eventId = call.argument<Number>("eventId")?.toLong()
        if (eventId == null) {
            result.error("invalid_args", "eventId is required", null)
            return
        }
        scope.launch {
            val summary = memoryEngine.getEventSummary(eventId)
            result.success(summary?.toMap())
        }
    }

    private fun handleProcessSampleEvents(call: MethodCall, result: MethodChannel.Result) {
        val limit = (call.argument<Number>("limit") ?: MemoryEngine.SAMPLE_TEST_EVENT_LIMIT).toInt().coerceAtLeast(1)
        scope.launch {
            try {
                val processed = memoryEngine.processSampleHistoricalEvents(limit)
                result.success(processed)
            } catch (t: Throwable) {
                FileLogger.e(TAG, "processSampleEvents failed", t)
                result.error("process_sample_failed", t.message, null)
            }
        }
    }

    private fun handleClearMemoryData(result: MethodChannel.Result) {
        scope.launch {
            try {
                memoryEngine.clearAllMemoryData()
                result.success(true)
            } catch (t: Throwable) {
                FileLogger.e(TAG, "clearMemoryData failed", t)
                result.error("clear_memory_failed", t.message, null)
            }
        }
    }

    private inner class SnapshotStreamHandler : EventChannel.StreamHandler {
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            job = scope.launch {
                memoryEngine.snapshotState.collectLatest { snapshot ->
                    events.success(snapshot.toMap())
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
        }
    }

    private inner class ProgressStreamHandler : EventChannel.StreamHandler {
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            job = scope.launch {
                memoryEngine.progressState.collectLatest { progress ->
                    events.success(progress.toMap())
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
        }
    }

    private inner class TagUpdateStreamHandler : EventChannel.StreamHandler {
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            job = scope.launch {
                memoryEngine.tagUpdateEvents.collectLatest { update ->
                    events.success(
                        mapOf(
                            "tag" to update.tag.toMap(),
                            "isNewTag" to update.isNewTag,
                            "statusChanged" to update.statusChanged
                        )
                    )
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
        }
    }

    private fun Map<String, Any?>.toUserEvent(): UserEvent? {
        val occurredAt = (this["occurredAt"] as? Number)?.toLong() ?: return null
        val type = this["type"] as? String ?: return null
        val source = this["source"] as? String ?: return null
        val content = this["content"] as? String ?: return null
        val externalId = this["externalId"] as? String
        val metadata = (this["metadata"] as? Map<*, *>)?.mapNotNull {
            val key = it.key as? String ?: return@mapNotNull null
            val value = it.value as? String ?: return@mapNotNull null
            key to value
        }?.toMap() ?: emptyMap()
        return UserEvent(
            externalId = externalId,
            occurredAt = occurredAt,
            type = type,
            source = source,
            content = content,
            metadata = metadata
        )
    }

    private fun MemorySnapshot.toMap(): Map<String, Any?> {
        val limitedPending = pendingTags.take(SNAPSHOT_TAG_LIMIT).map { it.toMap() }
        val limitedConfirmed = confirmedTags.take(SNAPSHOT_TAG_LIMIT).map { it.toMap() }
        val limitedEvents = recentEvents.take(SNAPSHOT_EVENT_LIMIT).map { it.toMap() }
        return mapOf(
            "pendingTags" to limitedPending,
            "pendingTotalCount" to pendingTotalCount,
            "confirmedTags" to limitedConfirmed,
            "confirmedTotalCount" to confirmedTotalCount,
            "recentEvents" to limitedEvents,
            "recentEventTotalCount" to recentEventTotalCount,
            "lastUpdatedAt" to lastUpdatedAt,
            "personaSummary" to personaSummary,
            "personaProfile" to personaProfile.toMap()
        )
    }

    private fun UserTag.toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "tagKey" to tagKey,
            "label" to label,
            "level1" to level1,
            "level2" to level2,
            "level3" to level3,
            "level4" to level4,
            "fullPath" to fullPath,
            "category" to category.storageValue,
            "status" to status.storageValue,
            "occurrences" to occurrences,
            "confidence" to confidence,
            "firstSeenAt" to firstSeenAt,
            "lastSeenAt" to lastSeenAt,
            "autoConfirmedAt" to autoConfirmedAt,
            "manualConfirmedAt" to manualConfirmedAt,
            "evidences" to evidences.map { it.toMap() },
            "evidenceTotalCount" to evidenceTotalCount
        )
    }

    private fun TagEvidence.toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "tagId" to tagId,
            "eventId" to eventId,
            "excerpt" to excerpt,
            "confidence" to confidence,
            "createdAt" to createdAt,
            "lastModifiedAt" to lastModifiedAt,
            "isUserEdited" to isUserEdited,
            "notes" to notes
        )
    }

    private fun MemoryEventSummary.toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "externalId" to externalId,
            "occurredAt" to occurredAt,
            "type" to type,
            "source" to source,
            "content" to content,
            "containsUserContext" to containsUserContext,
            "relatedTagIds" to relatedTagIds
        )
    }

    private fun MemoryProgressState.toMap(): Map<String, Any?> = when (this) {
        is MemoryProgressState.Idle -> mapOf("state" to "idle")
        is MemoryProgressState.Running -> mapOf(
            "state" to "running",
            "processedCount" to processedCount,
            "totalCount" to totalCount,
            "progress" to progress,
            "currentEventId" to currentEventId,
            "currentEventExternalId" to currentEventExternalId,
            "currentEventType" to currentEventType,
            "newlyDiscoveredTags" to newlyDiscoveredTags
        )
        is MemoryProgressState.Completed -> mapOf(
            "state" to "completed",
            "totalCount" to totalCount,
            "durationMillis" to durationMillis
        )
        is MemoryProgressState.Failed -> mapOf(
            "state" to "failed",
            "processedCount" to processedCount,
            "totalCount" to totalCount,
            "errorMessage" to errorMessage,
            "rawResponse" to rawResponse,
            "failureCode" to failureCode,
            "failedEventExternalId" to failedEventExternalId
        )
    }

    companion object {
        private const val TAG = "MemoryBridge"
        private const val METHOD_CHANNEL_NAME = "com.fqyw.screen_memo/memory"
        private const val SNAPSHOT_CHANNEL_NAME = "com.fqyw.screen_memo/memory/snapshot"
        private const val PROGRESS_CHANNEL_NAME = "com.fqyw.screen_memo/memory/progress"
        private const val TAG_UPDATE_CHANNEL_NAME = "com.fqyw.screen_memo/memory/tag_updates"
        private const val SNAPSHOT_TAG_LIMIT = 60
        private const val SNAPSHOT_EVENT_LIMIT = 60
    }
}


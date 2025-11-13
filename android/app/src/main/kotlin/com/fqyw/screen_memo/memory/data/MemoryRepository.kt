package com.fqyw.screen_memo.memory.data

import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.memory.data.db.EventWithTagIds
import com.fqyw.screen_memo.memory.data.db.MemoryDao
import com.fqyw.screen_memo.memory.data.db.MemoryEventEntity
import com.fqyw.screen_memo.memory.data.db.MemoryMetadataEntity
import com.fqyw.screen_memo.memory.data.db.MemoryTagEvidenceEntity
import com.fqyw.screen_memo.memory.data.db.MemoryTagEntity
import com.fqyw.screen_memo.memory.data.db.TagWithEvidence
import com.fqyw.screen_memo.memory.model.MemoryEventSummary
import com.fqyw.screen_memo.memory.model.PersonaProfile
import com.fqyw.screen_memo.memory.model.TagEvidence
import com.fqyw.screen_memo.memory.model.TagStatus
import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.model.UserTag
import com.fqyw.screen_memo.memory.processor.TagCandidate
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlin.math.max

class MemoryRepository(
    private val memoryDao: MemoryDao,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {

    data class TagUpdateResult(
        val tag: UserTag,
        val isNewTag: Boolean,
        val statusChanged: Boolean
    )

    suspend fun upsertEvent(event: UserEvent): MemoryEventEntity = withContext(ioDispatcher) {
        val now = System.currentTimeMillis()
        val existing = event.externalId?.let { memoryDao.findEventByExternalId(it) }
        if (existing != null) {
            val shouldUpdateContent = event.content.isNotBlank() && event.content != existing.content
            val updated = existing.copy(
                content = if (shouldUpdateContent) event.content else existing.content,
                metadata = if (event.metadata.isNotEmpty()) event.metadata else existing.metadata,
                lastModifiedAt = now
            )
            if (updated != existing) {
                memoryDao.updateEvent(updated)
            }
            return@withContext updated
        }

        val entity = MemoryEventEntity(
            externalId = event.externalId,
            occurredAt = event.occurredAt,
            type = event.type,
            source = event.source,
            content = event.content,
            metadata = event.metadata
        )
        val newId = memoryDao.insertEvent(entity)
        if (newId == -1L) {
            val fallback = event.externalId?.let { memoryDao.findEventByExternalId(it) }
            return@withContext fallback ?: throw IllegalStateException("Failed to insert event and no fallback found")
        }
        memoryDao.getEventById(newId) ?: throw IllegalStateException("Event inserted but not found: $newId")
    }

    suspend fun markEventProcessed(
        eventId: Long,
        containsUserContext: Boolean,
        processedAt: Long = System.currentTimeMillis()
    ) = withContext(ioDispatcher) {
        memoryDao.markEventProcessed(eventId, processedAt, containsUserContext)
    }

    suspend fun getEarliestUnprocessedEvent(): MemoryEventEntity? = withContext(ioDispatcher) {
        memoryDao.loadEarliestUnprocessedEvent()
    }

    suspend fun loadUnprocessedEventsBetween(
        startMillis: Long,
        endMillis: Long
    ): List<MemoryEventEntity> = withContext(ioDispatcher) {
        memoryDao.loadUnprocessedEventsBetween(startMillis, endMillis)
    }

    suspend fun loadEventsBetween(
        startMillis: Long,
        endMillis: Long
    ): List<MemoryEventEntity> = withContext(ioDispatcher) {
        memoryDao.loadEventsBetween(startMillis, endMillis)
    }

    suspend fun loadUnprocessedTimestampsExcludingType(excludedType: String): List<Long> =
        withContext(ioDispatcher) {
            memoryDao.loadUnprocessedTimestampsExcludingType(excludedType)
        }

    suspend fun loadAllTimestampsExcludingType(excludedType: String): List<Long> =
        withContext(ioDispatcher) {
            memoryDao.loadAllTimestampsExcludingType(excludedType)
        }

    fun observeTagsByStatus(status: TagStatus, limit: Int): Flow<List<UserTag>> {
        return memoryDao.observeTagsByStatus(status.storageValue, limit)
            .map { list -> list.map { it.toDomain(SNAPSHOT_EVIDENCE_LIMIT) } }
    }

    fun observeRecentEvents(limit: Int): Flow<List<MemoryEventSummary>> {
        return memoryDao.observeRecentEventsWithTags(limit)
            .map { list -> list.map { it.toSummary() } }
    }

    fun observeTagCountByStatus(status: TagStatus): Flow<Int> {
        return memoryDao.observeTagCountByStatus(status.storageValue)
    }

    fun observeEventCount(): Flow<Int> {
        return memoryDao.observeEventCount()
    }

    suspend fun loadUnprocessedEvents(batchSize: Int): List<MemoryEventEntity> = withContext(ioDispatcher) {
        memoryDao.loadUnprocessedEvents(batchSize)
    }

    suspend fun loadEventsAscending(batchSize: Int, offset: Int): List<MemoryEventEntity> = withContext(ioDispatcher) {
        memoryDao.loadEventsAscending(batchSize, offset)
    }

    suspend fun countAllEvents(): Int = withContext(ioDispatcher) { memoryDao.countAllEvents() }

    suspend fun countAllEventsExcludingType(excludedType: String): Int = withContext(ioDispatcher) {
        memoryDao.countAllEventsExcludingType(excludedType)
    }

    suspend fun countUnprocessedEventsExcludingType(excludedType: String): Int = withContext(ioDispatcher) {
        memoryDao.countUnprocessedEventsExcludingType(excludedType)
    }

    suspend fun findEventByExternalId(externalId: String): MemoryEventEntity? = withContext(ioDispatcher) {
        memoryDao.findEventByExternalId(externalId)
    }

    suspend fun loadTagsByStatus(
        status: TagStatus,
        limit: Int,
        offset: Int
    ): List<UserTag> = withContext(ioDispatcher) {
        memoryDao.loadTagsByStatus(status.storageValue, limit, offset)
            .map { it.toDomain(SNAPSHOT_EVIDENCE_LIMIT) }
    }

    suspend fun loadRecentEventsPaged(
        limit: Int,
        offset: Int
    ): List<MemoryEventSummary> = withContext(ioDispatcher) {
        memoryDao.loadEventsDescending(limit, offset).map { it.toSummary() }
    }

    suspend fun listAllTagPaths(): List<String> = withContext(ioDispatcher) {
        memoryDao.getAllTags().map { resolveHierarchy(it).fullPath }
    }

    suspend fun countUnprocessedEvents(): Int = withContext(ioDispatcher) { memoryDao.countUnprocessedEvents() }

    suspend fun upsertTagWithEvidence(
        candidate: TagCandidate,
        eventId: Long,
        eventTimestamp: Long
    ): TagUpdateResult = withContext(ioDispatcher) {
        val now = System.currentTimeMillis()
        val existing = memoryDao.findTagByKey(candidate.tagKey)

        if (existing == null) {
            val hierarchy = candidate.hierarchy
            val tagEntity = MemoryTagEntity(
                tagKey = candidate.tagKey,
                label = hierarchy.fullPath,
                level1 = hierarchy.level1,
                level2 = hierarchy.level2,
                level3 = hierarchy.level3,
                level4 = hierarchy.level4,
                fullPath = hierarchy.fullPath,
                category = candidate.category,
                status = TagStatus.PENDING,
                occurrences = 1,
                confidence = candidate.confidence,
                firstSeenAt = eventTimestamp,
                lastSeenAt = eventTimestamp
            )
            val newId = memoryDao.insertTag(tagEntity)
            val inserted = memoryDao.getTagById(newId)
                ?: throw IllegalStateException("Failed to retrieve tag after insert")
            upsertEvidence(
                tagId = inserted.id,
                eventId = eventId,
                candidate = candidate,
                timestamp = now
            )
            val domain = memoryDao.getTagWithEvidence(inserted.id)?.toDomain(UNBOUNDED_EVIDENCE_LIMIT)
                ?: throw IllegalStateException("Failed to load tag with evidence after insert")
            return@withContext TagUpdateResult(domain, isNewTag = true, statusChanged = false)
        }

        val occurrences = existing.occurrences + 1
        val averagedConfidence = max(0.0, (existing.confidence + candidate.confidence) / 2.0)
        var updated = existing.copy(
            occurrences = occurrences,
            confidence = averagedConfidence,
            lastSeenAt = eventTimestamp
        )

        val hierarchy = candidate.hierarchy
        if (hierarchy.isValid() && hierarchy.fullPath != existing.fullPath) {
            updated = updated.copy(
                label = hierarchy.fullPath,
                level1 = hierarchy.level1,
                level2 = hierarchy.level2,
                level3 = hierarchy.level3,
                level4 = hierarchy.level4,
                fullPath = hierarchy.fullPath
            )
        }

        var statusChanged = false
        if (existing.status == TagStatus.PENDING && occurrences >= candidate.autoConfirmThreshold) {
            updated = updated.copy(
                status = TagStatus.CONFIRMED,
                autoConfirmedAt = now
            )
            statusChanged = true
        }

        // 始终保持最新更清晰的标签名称
        if (candidate.shouldOverrideLabel && candidate.label.isNotBlank() && candidate.label != existing.label) {
            updated = updated.copy(label = candidate.label)
        }

        memoryDao.updateTag(updated)
        upsertEvidence(tagId = updated.id, eventId = eventId, candidate = candidate, timestamp = now)
        val domain = memoryDao.getTagWithEvidence(updated.id)?.toDomain(UNBOUNDED_EVIDENCE_LIMIT)
            ?: throw IllegalStateException("Failed to load tag with evidence after update")
        TagUpdateResult(domain, isNewTag = false, statusChanged = statusChanged)
    }

    suspend fun confirmTag(tagId: Long, confirmedByUser: Boolean): UserTag? = withContext(ioDispatcher) {
        val existing = memoryDao.getTagById(tagId) ?: return@withContext null
        val now = System.currentTimeMillis()
        if (existing.status == TagStatus.CONFIRMED && (!confirmedByUser || existing.manualConfirmedAt != null)) {
            return@withContext memoryDao.getTagWithEvidence(existing.id)?.toDomain(UNBOUNDED_EVIDENCE_LIMIT)
        }
        val updated = existing.copy(
            status = TagStatus.CONFIRMED,
            manualConfirmedAt = if (confirmedByUser) now else existing.manualConfirmedAt,
            autoConfirmedAt = if (confirmedByUser) existing.autoConfirmedAt else existing.autoConfirmedAt
        )
        memoryDao.updateTag(updated)
        memoryDao.getTagWithEvidence(updated.id)?.toDomain(UNBOUNDED_EVIDENCE_LIMIT)
    }

    suspend fun updateEvidence(
        evidenceId: Long,
        newExcerpt: String,
        notes: String?,
        markAsUserEdited: Boolean
    ): TagEvidence? = withContext(ioDispatcher) {
        val existing = memoryDao.getEvidenceById(evidenceId) ?: return@withContext null
        val updated = existing.copy(
            excerpt = if (newExcerpt.isNotBlank()) newExcerpt else existing.excerpt,
            notes = notes,
            isUserEdited = markAsUserEdited || existing.isUserEdited,
            lastModifiedAt = System.currentTimeMillis()
        )
        memoryDao.updateEvidence(updated)
        updated.toDomain()
    }

    suspend fun clearAllMemoryData() = withContext(ioDispatcher) {
        memoryDao.clearMemoryData()
    }

    suspend fun savePersonaSummary(summary: String) = withContext(ioDispatcher) {
        memoryDao.upsertMetadata(MemoryMetadataEntity(PERSONA_SUMMARY_KEY, summary))
    }

    suspend fun loadPersonaSummary(): String? = withContext(ioDispatcher) {
        memoryDao.getMetadataValue(PERSONA_SUMMARY_KEY)
    }

    suspend fun clearPersonaSummary() = withContext(ioDispatcher) {
        memoryDao.deleteMetadata(PERSONA_SUMMARY_KEY)
    }

    suspend fun savePersonaProfile(profile: PersonaProfile) = withContext(ioDispatcher) {
        memoryDao.upsertMetadata(
            MemoryMetadataEntity(
                PERSONA_PROFILE_KEY,
                profile.toJsonString()
            )
        )
    }

    suspend fun loadPersonaProfile(): PersonaProfile? = withContext(ioDispatcher) {
        val raw = memoryDao.getMetadataValue(PERSONA_PROFILE_KEY)
        PersonaProfile.fromJsonString(raw)
    }

    suspend fun clearPersonaProfile() = withContext(ioDispatcher) {
        memoryDao.deleteMetadata(PERSONA_PROFILE_KEY)
    }

    suspend fun deleteTag(tagId: Long): Boolean = withContext(ioDispatcher) {
        memoryDao.deleteEvidenceByTag(tagId)
        memoryDao.deleteTagById(tagId) > 0
    }

    suspend fun getTagById(tagId: Long): UserTag? = withContext(ioDispatcher) {
        memoryDao.getTagWithEvidence(tagId)?.toDomain(UNBOUNDED_EVIDENCE_LIMIT)
    }

    suspend fun getEventSummary(eventId: Long): MemoryEventSummary? = withContext(ioDispatcher) {
        memoryDao.getEventWithTags(eventId)?.toSummary()
    }

    private suspend fun upsertEvidence(
        tagId: Long,
        eventId: Long,
        candidate: TagCandidate,
        timestamp: Long
    ) {
        val existing = memoryDao.findEvidenceByTagAndEvent(tagId, eventId)
        if (existing == null) {
            val entity = MemoryTagEvidenceEntity(
                tagId = tagId,
                eventId = eventId,
                excerpt = candidate.evidence,
                confidence = candidate.confidence,
                createdAt = timestamp,
                lastModifiedAt = timestamp,
                isUserEdited = false,
                notes = candidate.inference ?: candidate.notes
            )
            val inserted = memoryDao.insertEvidence(entity)
            if (inserted == -1L) {
                FileLogger.w(TAG, "Duplicate evidence insertion ignored (tagId=$tagId, eventId=$eventId)")
            }
            return
        }

        val excerptChanged = candidate.evidence.isNotBlank() && candidate.evidence != existing.excerpt
        val higherConfidence = candidate.confidence >= existing.confidence
        val allowOverride = !existing.isUserEdited || candidate.forceOverrideEvidence

        if (allowOverride && excerptChanged && (higherConfidence || candidate.forceOverrideEvidence)) {
            val updated = existing.copy(
                excerpt = candidate.evidence,
                confidence = max(existing.confidence, candidate.confidence),
                notes = candidate.inference ?: candidate.notes ?: existing.notes,
                lastModifiedAt = timestamp
            )
            memoryDao.updateEvidence(updated)
        }
    }

    private fun TagWithEvidence.toDomain(evidenceLimit: Int): UserTag {
        val sorted = evidences.sortedByDescending { it.lastModifiedAt ?: it.createdAt }
        val limited = if (evidenceLimit == UNBOUNDED_EVIDENCE_LIMIT) {
            sorted
        } else {
            sorted.take(evidenceLimit)
        }
        val domainEvidences = limited.map { it.toDomain() }
        val resolvedHierarchy = resolveHierarchy(tag)
        return UserTag(
            id = tag.id,
            tagKey = tag.tagKey,
            label = resolvedHierarchy.fullPath,
            level1 = resolvedHierarchy.level1,
            level2 = resolvedHierarchy.level2,
            level3 = resolvedHierarchy.level3,
            level4 = resolvedHierarchy.level4,
            fullPath = resolvedHierarchy.fullPath,
            category = tag.category,
            status = tag.status,
            occurrences = tag.occurrences,
            confidence = tag.confidence,
            firstSeenAt = tag.firstSeenAt,
            lastSeenAt = tag.lastSeenAt,
            autoConfirmedAt = tag.autoConfirmedAt,
            manualConfirmedAt = tag.manualConfirmedAt,
            evidences = domainEvidences,
            evidenceTotalCount = evidences.size
        )
    }

    private fun MemoryTagEvidenceEntity.toDomain(): TagEvidence {
        return TagEvidence(
            id = id,
            tagId = tagId,
            eventId = eventId,
            excerpt = excerpt,
            confidence = confidence,
            createdAt = createdAt,
            lastModifiedAt = lastModifiedAt,
            isUserEdited = isUserEdited,
            notes = notes
        )
    }

    private fun EventWithTagIds.toSummary(): MemoryEventSummary {
        return MemoryEventSummary(
            id = event.id,
            externalId = event.externalId,
            occurredAt = event.occurredAt,
            type = event.type,
            source = event.source,
            content = event.content,
            containsUserContext = event.containsUserContext,
            relatedTagIds = relatedTagIds
        )
    }

    companion object {
        private const val TAG = "MemoryRepository"
        private const val SNAPSHOT_EVIDENCE_LIMIT = 2
        private const val UNBOUNDED_EVIDENCE_LIMIT = Int.MAX_VALUE
        private const val PERSONA_SUMMARY_KEY = "persona_summary"
        private const val PERSONA_PROFILE_KEY = "persona_profile_v1"
    }

    private data class ResolvedHierarchy(
        val level1: String,
        val level2: String,
        val level3: String,
        val level4: String,
        val fullPath: String
    )

    private fun resolveHierarchy(entity: MemoryTagEntity): ResolvedHierarchy {
        val defaultFullPath = entity.fullPath.ifBlank { entity.label }
        val storedLevels = listOf(entity.level1, entity.level2, entity.level3, entity.level4)
        val hasStoredLevels = storedLevels.all { it.isNotBlank() }
        if (hasStoredLevels) {
            val fullPath = if (defaultFullPath.isNotBlank()) defaultFullPath
            else storedLevels.joinToString(" / ") { it.trim() }
            return ResolvedHierarchy(
                level1 = entity.level1.trim(),
                level2 = entity.level2.trim(),
                level3 = entity.level3.trim(),
                level4 = entity.level4.trim(),
                fullPath = fullPath
            )
        }

        // fallback for legacy rows
        val fallbackSource = defaultFullPath.ifBlank { entity.tagKey.substringAfter(':', entity.tagKey) }
        val parts = fallbackSource.split('/', '／', '|', '｜')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val padded = (parts + List(4) { "" }).take(4)
        val fullPath = if (parts.size >= 4) {
            parts.take(4).joinToString(" / ")
        } else {
            entity.label.ifBlank { entity.tagKey }
        }
        return ResolvedHierarchy(
            level1 = padded[0].ifBlank { "待分类" },
            level2 = padded[1].ifBlank { "未分组" },
            level3 = padded[2].ifBlank { "未知专题" },
            level4 = padded[3].ifBlank { fullPath },
            fullPath = fullPath
        )
    }

}


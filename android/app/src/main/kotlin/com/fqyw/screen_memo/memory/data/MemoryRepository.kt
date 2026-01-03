package com.fqyw.screen_memo.memory.data

import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.memory.data.db.EventWithTagIds
import com.fqyw.screen_memo.memory.data.db.MemoryDao
import com.fqyw.screen_memo.memory.data.db.MemoryEdgeEntity
import com.fqyw.screen_memo.memory.data.db.MemoryEdgeEvidenceEntity
import com.fqyw.screen_memo.memory.data.db.MemoryEntityEntity
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
import com.fqyw.screen_memo.memory.processor.GraphEdgeCandidate
import com.fqyw.screen_memo.memory.processor.GraphEdgeClosureCandidate
import com.fqyw.screen_memo.memory.processor.GraphEntityCandidate
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

    data class GraphApplyResult(
        val entitiesTouched: Int,
        val edgesUpserted: Int,
        val edgesClosed: Int
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

    suspend fun applyGraphUpdates(
        eventId: Long,
        eventTimestamp: Long,
        eventContent: String,
        graphEntities: List<GraphEntityCandidate>,
        graphEdges: List<GraphEdgeCandidate>,
        graphEdgeClosures: List<GraphEdgeClosureCandidate>
    ): GraphApplyResult = withContext(ioDispatcher) {
        if (graphEntities.isEmpty() && graphEdges.isEmpty() && graphEdgeClosures.isEmpty()) {
            return@withContext GraphApplyResult(0, 0, 0)
        }

        val now = System.currentTimeMillis()
        val cache = HashMap<String, MemoryEntityEntity>()
        var touchedEntities = 0
        var upsertedEdges = 0
        var closedEdges = 0

        graphEntities
            .map { it.copy(entityKey = it.entityKey.trim()) }
            .filter { it.entityKey.isNotBlank() }
            .distinctBy { it.entityKey }
            .forEach { candidate ->
                val entity = upsertEntityCandidate(candidate, now)
                cache[entity.entityKey] = entity
                touchedEntities += 1
            }

        graphEdgeClosures.forEach { closure ->
            val subjectKey = closure.subjectKey.trim()
            val predicate = closure.predicate.trim()
            if (subjectKey.isBlank() || predicate.isBlank()) return@forEach
            val subject = resolveEntity(cache, subjectKey, now)
            val objEntityId = closure.objectKey?.trim()?.takeIf { it.isNotBlank() }?.let { key ->
                resolveEntity(cache, key, now).id
            }
            val objValue = closure.objectValue?.trim()?.takeIf { it.isNotBlank() }
            val qualifierFilter = normalizeStringMap(closure.qualifiers)
            val active = memoryDao.findActiveEdgesBySubjectPredicate(subject.id, predicate)
            val toClose = active.filter { edge -> edgeMatchesClosure(edge, objEntityId, objValue, qualifierFilter) }
            if (toClose.isEmpty()) return@forEach
            memoryDao.closeEdges(toClose.map { it.id }, eventTimestamp)
            closedEdges += toClose.size
            val excerpt = buildEdgeEvidenceExcerpt(preferred = closure.reason, fallback = eventContent)
            toClose.forEach { edge ->
                upsertEdgeEvidence(
                    edgeId = edge.id,
                    eventId = eventId,
                    excerpt = excerpt,
                    confidence = 0.6,
                    notes = closure.reason?.trim()?.takeIf { it.isNotBlank() }
                )
            }
        }

        graphEdges.forEach { candidateRaw ->
            val candidate = candidateRaw.copy(
                subjectKey = candidateRaw.subjectKey.trim(),
                predicate = candidateRaw.predicate.trim(),
                objectKey = candidateRaw.objectKey?.trim(),
                objectValue = candidateRaw.objectValue?.trim(),
                qualifiers = normalizeStringMap(candidateRaw.qualifiers)
            )
            if (candidate.subjectKey.isBlank() || candidate.predicate.isBlank()) return@forEach
            val subject = resolveEntity(cache, candidate.subjectKey, now)
            val objectKey = candidate.objectKey?.takeIf { it.isNotBlank() }
            val objectValue = if (objectKey == null) candidate.objectValue?.takeIf { it.isNotBlank() } else null
            if (objectKey == null && objectValue == null) return@forEach
            val objectEntityId = objectKey?.let { resolveEntity(cache, it, now).id }

            val isState = candidate.isState ?: isDefaultStatePredicate(candidate.predicate)
            val active = memoryDao.findActiveEdgesBySubjectPredicate(subject.id, candidate.predicate)
            val exact = active.firstOrNull { edge -> edgeEquals(edge, objectEntityId, objectValue, candidate.qualifiers) }

            if (isState) {
                val onlyExactActive = exact != null && active.size == 1
                if (!onlyExactActive && active.isNotEmpty()) {
                    memoryDao.closeEdges(active.map { it.id }, eventTimestamp)
                    closedEdges += active.size
                }
            }

            val edgeId: Long = if (exact != null && (!isState || (isState && active.size == 1))) {
                val newConfidence = max(exact.confidence, candidate.confidence.coerceIn(0.0, 1.0))
                val updated = exact.copy(
                    qualifiers = candidate.qualifiers,
                    confidence = newConfidence,
                    lastModifiedAt = now
                )
                memoryDao.updateEdge(updated)
                exact.id
            } else {
                val edge = MemoryEdgeEntity(
                    subjectEntityId = subject.id,
                    predicate = candidate.predicate,
                    objectEntityId = objectEntityId,
                    objectValue = objectValue,
                    qualifiers = candidate.qualifiers,
                    validFrom = eventTimestamp,
                    validTo = null,
                    confidence = candidate.confidence.coerceIn(0.0, 1.0),
                    createdAt = now,
                    lastModifiedAt = now
                )
                val newId = memoryDao.insertEdge(edge)
                if (newId > 0L) {
                    upsertedEdges += 1
                    newId
                } else {
                    val fallback = memoryDao.findActiveEdge(subject.id, candidate.predicate, objectEntityId, objectValue)
                    fallback?.id ?: return@forEach
                }
            }

            val excerpt = buildEdgeEvidenceExcerpt(preferred = candidate.evidenceExcerpt, fallback = eventContent)
            upsertEdgeEvidence(
                edgeId = edgeId,
                eventId = eventId,
                excerpt = excerpt,
                confidence = candidate.confidence.coerceIn(0.0, 1.0),
                notes = null
            )
        }

        GraphApplyResult(
            entitiesTouched = touchedEntities,
            edgesUpserted = upsertedEdges,
            edgesClosed = closedEdges
        )
    }

    suspend fun searchGraph(
        query: String,
        depth: Int,
        limit: Int,
        includeHistory: Boolean
    ): Map<String, Any?> = withContext(ioDispatcher) {
        val normalizedQuery = query.trim()
        val safeDepth = depth.coerceIn(1, 4)
        val maxEdges = limit.coerceIn(10, 200)
        val maxNodes = (maxEdges * 3).coerceIn(30, 500)

        val seedEntities = LinkedHashMap<Long, MemoryEntityEntity>()
        if (shouldIncludeUserNode(normalizedQuery)) {
            memoryDao.findEntityByKey(USER_ENTITY_KEY)?.let { seedEntities[it.id] = it }
        }

        val tokens = extractSearchTokens(normalizedQuery)
        tokens.forEach { token ->
            if (seedEntities.size >= GRAPH_MAX_SEED_ENTITIES) return@forEach
            val hits = memoryDao.searchEntities(token, limit = GRAPH_SEED_SEARCH_LIMIT)
            hits.forEach { e ->
                if (seedEntities.size < GRAPH_MAX_SEED_ENTITIES) {
                    seedEntities.putIfAbsent(e.id, e)
                }
            }
        }

        if (seedEntities.isEmpty()) {
            return@withContext mapOf(
                "query" to normalizedQuery,
                "depth" to safeDepth,
                "include_history" to includeHistory,
                "seed_keys" to emptyList<String>(),
                "entities" to emptyList<Map<String, Any?>>(),
                "edges" to emptyList<Map<String, Any?>>(),
                "stats" to mapOf("node_count" to 0, "edge_count" to 0)
            )
        }

        val visited = LinkedHashSet<Long>()
        val frontier = LinkedHashSet<Long>()
        seedEntities.values.forEach { e ->
            visited.add(e.id)
            frontier.add(e.id)
        }

        val edgesById = LinkedHashMap<Long, MemoryEdgeEntity>()
        var currentFrontier = frontier
        repeat(safeDepth) {
            if (currentFrontier.isEmpty() || edgesById.size >= maxEdges || visited.size >= maxNodes) return@repeat
            val edges = if (includeHistory) {
                memoryDao.loadEdgesConnectedToEntities(currentFrontier.toList(), maxEdges)
            } else {
                memoryDao.loadActiveEdgesConnectedToEntities(currentFrontier.toList(), maxEdges)
            }
            val nextFrontier = LinkedHashSet<Long>()
            edges.forEach { edge ->
                if (edgesById.size < maxEdges) {
                    edgesById.putIfAbsent(edge.id, edge)
                }
                if (visited.size < maxNodes && visited.add(edge.subjectEntityId)) {
                    nextFrontier.add(edge.subjectEntityId)
                }
                val oid = edge.objectEntityId
                if (oid != null && visited.size < maxNodes && visited.add(oid)) {
                    nextFrontier.add(oid)
                }
            }
            currentFrontier = nextFrontier
        }

        val entities = memoryDao.loadEntitiesByIds(visited.toList())
        val idToKey = entities.associate { it.id to it.entityKey }

        val entityMaps = entities
            .sortedByDescending { it.lastModifiedAt }
            .map { e ->
                mapOf(
                    "id" to e.id,
                    "entity_key" to e.entityKey,
                    "type" to e.type,
                    "name" to e.name,
                    "aliases" to (e.aliases ?: emptyList<String>()),
                    "metadata" to (e.metadata ?: emptyMap<String, String>()),
                    "created_at" to e.createdAt,
                    "last_modified_at" to e.lastModifiedAt
                )
            }

        val edgeMaps = edgesById.values
            .sortedByDescending { it.validFrom }
            .map { edge ->
                val evidence = memoryDao.loadEdgeEvidence(edge.id, GRAPH_EDGE_EVIDENCE_LIMIT)
                    .sortedByDescending { it.lastModifiedAt }
                    .map { ev ->
                        mapOf(
                            "id" to ev.id,
                            "event_id" to ev.eventId,
                            "excerpt" to ev.excerpt,
                            "confidence" to ev.confidence,
                            "created_at" to ev.createdAt,
                            "last_modified_at" to ev.lastModifiedAt,
                            "is_user_edited" to ev.isUserEdited,
                            "notes" to ev.notes
                        )
                    }
                mapOf(
                    "id" to edge.id,
                    "subject_entity_id" to edge.subjectEntityId,
                    "subject_key" to (idToKey[edge.subjectEntityId] ?: ""),
                    "predicate" to edge.predicate,
                    "object_entity_id" to edge.objectEntityId,
                    "object_key" to edge.objectEntityId?.let { idToKey[it] },
                    "object_value" to edge.objectValue,
                    "qualifiers" to (edge.qualifiers ?: emptyMap<String, String>()),
                    "valid_from" to edge.validFrom,
                    "valid_to" to edge.validTo,
                    "confidence" to edge.confidence,
                    "created_at" to edge.createdAt,
                    "last_modified_at" to edge.lastModifiedAt,
                    "evidence" to evidence
                )
            }

        mapOf(
            "query" to normalizedQuery,
            "depth" to safeDepth,
            "include_history" to includeHistory,
            "seed_keys" to seedEntities.values.map { it.entityKey },
            "entities" to entityMaps,
            "edges" to edgeMaps,
            "stats" to mapOf(
                "seed_count" to seedEntities.size,
                "node_count" to entityMaps.size,
                "edge_count" to edgeMaps.size
            )
        )
    }

    private suspend fun resolveEntity(
        cache: MutableMap<String, MemoryEntityEntity>,
        entityKey: String,
        now: Long
    ): MemoryEntityEntity {
        cache[entityKey]?.let { return it }
        val existing = memoryDao.findEntityByKey(entityKey)
        if (existing != null) {
            cache[entityKey] = existing
            return existing
        }
        val inferredType = entityKey.substringBefore(':', missingDelimiterValue = "Unknown").ifBlank { "Unknown" }
        val inferredName = entityKey.substringAfter(':', missingDelimiterValue = entityKey).ifBlank { entityKey }
        val created = MemoryEntityEntity(
            entityKey = entityKey,
            type = inferredType,
            name = inferredName,
            aliases = emptyList(),
            metadata = emptyMap(),
            createdAt = now,
            lastModifiedAt = now
        )
        val insertedId = memoryDao.insertEntity(created)
        val row = if (insertedId > 0L) memoryDao.getEntityById(insertedId) else memoryDao.findEntityByKey(entityKey)
        val resolved = row ?: created.copy(id = insertedId)
        cache[entityKey] = resolved
        return resolved
    }

    private suspend fun upsertEntityCandidate(candidate: GraphEntityCandidate, now: Long): MemoryEntityEntity {
        val key = candidate.entityKey.trim()
        val existing = memoryDao.findEntityByKey(key)
        if (existing == null) {
            val aliases = mergeAliases(emptyList(), candidate.aliases, candidate.name, key).take(GRAPH_MAX_ALIASES)
            val entity = MemoryEntityEntity(
                entityKey = key,
                type = candidate.type.trim().ifBlank { key.substringBefore(':', missingDelimiterValue = "Unknown") },
                name = candidate.name.trim().ifBlank { key.substringAfter(':', missingDelimiterValue = key) },
                aliases = aliases,
                metadata = normalizeStringMap(candidate.metadata),
                createdAt = now,
                lastModifiedAt = now
            )
            val newId = memoryDao.insertEntity(entity)
            val row = if (newId > 0L) memoryDao.getEntityById(newId) else memoryDao.findEntityByKey(key)
            return row ?: entity.copy(id = newId)
        }

        val mergedAliases =
            mergeAliases(existing.aliases ?: emptyList(), candidate.aliases, candidate.name, key).take(GRAPH_MAX_ALIASES)
        val mergedMetadata = (existing.metadata ?: emptyMap()) + normalizeStringMap(candidate.metadata)
        val updated = existing.copy(
            type = candidate.type.trim().ifBlank { existing.type },
            name = candidate.name.trim().ifBlank { existing.name },
            aliases = mergedAliases,
            metadata = mergedMetadata,
            lastModifiedAt = now
        )
        if (updated != existing) {
            memoryDao.updateEntity(updated)
        }
        return updated
    }

    private suspend fun upsertEdgeEvidence(
        edgeId: Long,
        eventId: Long,
        excerpt: String,
        confidence: Double,
        notes: String?
    ) {
        val safeExcerpt = excerpt.trim().ifBlank { "(no excerpt)" }
        val now = System.currentTimeMillis()
        val existing = memoryDao.findEdgeEvidenceByEdgeAndEvent(edgeId, eventId)
        if (existing == null) {
            val entity = MemoryEdgeEvidenceEntity(
                edgeId = edgeId,
                eventId = eventId,
                excerpt = safeExcerpt,
                confidence = confidence.coerceIn(0.0, 1.0),
                createdAt = now,
                lastModifiedAt = now,
                isUserEdited = false,
                notes = notes
            )
            memoryDao.insertEdgeEvidence(entity)
            return
        }
        val updated = existing.copy(
            excerpt = safeExcerpt,
            confidence = max(existing.confidence, confidence.coerceIn(0.0, 1.0)),
            lastModifiedAt = now,
            notes = notes ?: existing.notes
        )
        if (updated != existing) {
            memoryDao.updateEdgeEvidence(updated)
        }
    }

    private fun buildEdgeEvidenceExcerpt(preferred: String?, fallback: String): String {
        val raw = preferred?.trim().takeIf { !it.isNullOrBlank() } ?: fallback.trim()
        if (raw.isBlank()) return "(empty)"
        return if (raw.length <= GRAPH_MAX_EVIDENCE_EXCERPT) raw else raw.substring(0, GRAPH_MAX_EVIDENCE_EXCERPT)
    }

    private fun edgeEquals(
        edge: MemoryEdgeEntity,
        objectEntityId: Long?,
        objectValue: String?,
        qualifiers: Map<String, String>
    ): Boolean {
        if (objectEntityId != null) {
            if (edge.objectEntityId != objectEntityId) return false
        } else if (edge.objectEntityId != null) {
            return false
        }
        if (objectValue != null) {
            if (edge.objectValue != objectValue) return false
        } else if (edge.objectValue != null) {
            return false
        }
        return normalizeStringMap(edge.qualifiers) == qualifiers
    }

    private fun edgeMatchesClosure(
        edge: MemoryEdgeEntity,
        objectEntityId: Long?,
        objectValue: String?,
        qualifierFilter: Map<String, String>
    ): Boolean {
        if (objectEntityId != null && edge.objectEntityId != objectEntityId) return false
        if (objectValue != null && edge.objectValue != objectValue) return false
        if (qualifierFilter.isNotEmpty()) {
            qualifierFilter.forEach { (k, v) ->
                if (edge.qualifiers?.get(k) != v) return false
            }
        }
        return true
    }

    private fun mergeAliases(
        existing: List<String>,
        incoming: List<String>,
        name: String,
        key: String
    ): List<String> {
        val seen = LinkedHashSet<String>()
        (existing + incoming + listOf(name, key)).forEach { raw ->
            val v = raw.trim()
            if (v.isNotEmpty()) seen.add(v)
        }
        return seen.toList()
    }

    private fun normalizeStringMap(map: Map<String, String>?): Map<String, String> {
        if (map == null || map.isEmpty()) return emptyMap()
        val out = LinkedHashMap<String, String>()
        map.forEach { (k0, v0) ->
            val k = k0.trim()
            val v = v0.trim()
            if (k.isNotEmpty() && v.isNotEmpty()) out[k] = v
        }
        return out
    }

    private fun isDefaultStatePredicate(predicateRaw: String): Boolean {
        val predicate = predicateRaw.trim().lowercase()
        if (predicate.isBlank()) return false
        return STATEFUL_PREDICATES.contains(predicate)
    }

    private fun shouldIncludeUserNode(query: String): Boolean {
        if (query.isBlank()) return true
        if (query.contains("我")) return true
        val lowered = query.lowercase()
        return Regex("\\b(i|me|my|myself)\\b").containsMatchIn(lowered)
    }

    private fun extractSearchTokens(query: String): List<String> {
        if (query.isBlank()) return emptyList()
        val trimmed = query.trim()
        val tokens = LinkedHashSet<String>()
        if (trimmed.length in 2..64) {
            tokens.add(trimmed)
        }

        trimmed.split(Regex("[\\s,，。！？、;；:：()（）\\[\\]{}<>《》“”\"'`]+"))
            .map { it.trim() }
            .filter { it.length in 2..48 }
            .forEach { tokens.add(it) }

        Regex("[A-Za-z0-9_]{2,}").findAll(trimmed).forEach { m ->
            tokens.add(m.value)
        }

        // Best-effort CJK tokenization: include short windows to allow matching entity names embedded in a sentence.
        Regex("[\\u4e00-\\u9fff]{2,}").findAll(trimmed).forEach { m ->
            val run = m.value
            if (run.length <= 4) {
                tokens.add(run)
            } else {
                tokens.add(run.take(4))
                tokens.add(run.takeLast(4))
                val windowCount = minOf(8, run.length - 1)
                for (i in 0 until windowCount) {
                    tokens.add(run.substring(i, i + 2))
                }
            }
        }

        return tokens
            .filter { it.length in 2..64 }
            .take(GRAPH_MAX_TOKENS)
            .toList()
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
        private const val GRAPH_MAX_ALIASES = 20
        private const val GRAPH_MAX_EVIDENCE_EXCERPT = 600
        private const val USER_ENTITY_KEY = "person:user"
        private const val GRAPH_MAX_TOKENS = 12
        private const val GRAPH_MAX_SEED_ENTITIES = 12
        private const val GRAPH_SEED_SEARCH_LIMIT = 8
        private const val GRAPH_EDGE_EVIDENCE_LIMIT = 3
        private val STATEFUL_PREDICATES = setOf(
            "works_at",
            "employed_by",
            "lives_in",
            "located_in",
            "status",
            "owns",
            "uses",
            "has_role",
            "role_at"
        )
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

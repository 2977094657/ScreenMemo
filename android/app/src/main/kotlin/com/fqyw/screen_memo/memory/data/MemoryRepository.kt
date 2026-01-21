package com.fqyw.screen_memo.memory.data

import com.fqyw.screen_memo.memory.data.db.MemoryDao
import com.fqyw.screen_memo.memory.data.db.MemoryEdgeEntity
import com.fqyw.screen_memo.memory.data.db.MemoryEdgeEvidenceEntity
import com.fqyw.screen_memo.memory.data.db.MemoryEntityEntity
import com.fqyw.screen_memo.memory.data.db.MemoryEntityAliasEntity
import com.fqyw.screen_memo.memory.data.db.MemoryEventEntity
import com.fqyw.screen_memo.memory.data.db.MemoryMetadataEntity
import com.fqyw.screen_memo.memory.model.MemoryEventSummary
import com.fqyw.screen_memo.memory.model.PersonaProfile
import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.processor.GraphEdgeCandidate
import com.fqyw.screen_memo.memory.processor.GraphEdgeClosureCandidate
import com.fqyw.screen_memo.memory.processor.GraphEntityCandidate
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

    fun observeRecentEvents(limit: Int): Flow<List<MemoryEventSummary>> {
        return memoryDao.observeRecentEvents(limit)
            .map { list -> list.map { it.toSummary() } }
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

    suspend fun loadRecentEventsPaged(
        limit: Int,
        offset: Int
    ): List<MemoryEventSummary> = withContext(ioDispatcher) {
        memoryDao.loadEventsDescending(limit, offset).map { it.toSummary() }
    }

    suspend fun countUnprocessedEvents(): Int = withContext(ioDispatcher) { memoryDao.countUnprocessedEvents() }

    private suspend fun upsertEntityAliasIfNeeded(aliasKey: String, entityId: Long) {
        val key = aliasKey.trim()
        if (key.isBlank()) return
        val canonical = memoryDao.getEntityById(entityId)?.entityKey?.trim().orEmpty()
        if (canonical.isNotBlank() && canonical == key) return
        memoryDao.insertEntityAlias(
            MemoryEntityAliasEntity(
                aliasKey = key,
                entityId = entityId,
                createdAt = System.currentTimeMillis()
            )
        )
    }

    private fun canonicalizePredicate(predicateRaw: String?): String {
        if (predicateRaw.isNullOrBlank()) return ""
        val snake = toSnakeLower(predicateRaw)
        if (snake.isBlank()) return ""
        return PREDICATE_SYNONYMS[snake] ?: snake
    }

    private fun predicateLookupVariants(predicateRaw: String?, canonicalPredicate: String): List<String> {
        if (canonicalPredicate.isBlank()) return emptyList()
        val variants = LinkedHashSet<String>()
        variants.add(canonicalPredicate)
        val rawSnake = predicateRaw?.let { toSnakeLower(it) }.orEmpty()
        if (rawSnake.isNotBlank()) variants.add(rawSnake)
        PREDICATE_SYNONYMS.forEach { (variant, canonical) ->
            if (canonical == canonicalPredicate) {
                variants.add(variant)
            }
        }
        return variants.toList()
    }

    private fun canonicalizeEntityKey(entityKeyRaw: String): String {
        val raw = entityKeyRaw.trim()
        if (raw.isBlank()) return ""
        val idx = raw.indexOf(':')
        if (idx <= 0 || idx >= raw.length - 1) return raw
        val typeRaw = raw.substring(0, idx).trim().lowercase()
        val nameRaw = raw.substring(idx + 1).trim()
        val type = ENTITY_TYPE_ALIASES[typeRaw] ?: typeRaw
        val name = nameRaw.replace("\\s+".toRegex(), "_")
        return "$type:$name"
    }

    private fun toSnakeLower(input: String): String {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return ""
        val out = StringBuilder(trimmed.length + 8)
        trimmed.forEachIndexed { index, ch ->
            when {
                ch.isLetterOrDigit() -> {
                    val lower = ch.lowercaseChar()
                    if (ch.isUpperCase() && out.isNotEmpty() && out[out.length - 1] != '_') {
                        out.append('_')
                    }
                    out.append(lower)
                }
                ch == '_' || ch == '-' || ch.isWhitespace() -> {
                    if (out.isNotEmpty() && out[out.length - 1] != '_') {
                        out.append('_')
                    }
                }
                else -> {
                    // drop other punctuation
                }
            }
        }
        return out.toString().trim('_').replace(Regex("_+"), "_")
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

    suspend fun getEventSummary(eventId: Long): MemoryEventSummary? = withContext(ioDispatcher) {
        memoryDao.getEventById(eventId)?.toSummary()
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
                val canonicalKey = canonicalizeEntityKey(entity.entityKey)
                if (canonicalKey.isNotBlank()) {
                    cache[canonicalKey] = entity
                }
                touchedEntities += 1
            }

        graphEdgeClosures.forEach { closure ->
            val subjectKey = closure.subjectKey.trim()
            val predicateRaw = closure.predicate.trim()
            if (subjectKey.isBlank() || predicateRaw.isBlank()) return@forEach
            val predicate = canonicalizePredicate(predicateRaw)
            val predicateVariants = predicateLookupVariants(predicateRaw, predicate)
            val subject = resolveEntity(cache, subjectKey, now)
            val objEntityId = closure.objectKey?.trim()?.takeIf { it.isNotBlank() }?.let { key ->
                resolveEntity(cache, key, now).id
            }
            val objValue = closure.objectValue?.trim()?.takeIf { it.isNotBlank() }
            val qualifierFilter = normalizeStringMap(closure.qualifiers)
            val active = predicateVariants
                .flatMap { p -> memoryDao.findActiveEdgesBySubjectPredicate(subject.id, p) }
                .distinctBy { it.id }
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
                predicate = canonicalizePredicate(candidateRaw.predicate),
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
            val predicateVariants = predicateLookupVariants(candidateRaw.predicate, candidate.predicate)
            val active = predicateVariants
                .flatMap { p -> memoryDao.findActiveEdgesBySubjectPredicate(subject.id, p) }
                .distinctBy { it.id }
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
                    predicate = candidate.predicate,
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
                    var fallback: MemoryEdgeEntity? = null
                    for (p in predicateVariants) {
                        fallback = memoryDao.findActiveEdge(subject.id, p, objectEntityId, objectValue)
                        if (fallback != null) break
                    }
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

        // If the query itself is an entity key (e.g. "person:user"), seed it directly to avoid tokenizer issues.
        if (normalizedQuery.contains(':') && normalizedQuery.length in 2..96) {
            val canonical = canonicalizeEntityKey(normalizedQuery)
            (memoryDao.findEntityByKey(canonical) ?: memoryDao.findEntityByKey(normalizedQuery))?.let { e ->
                seedEntities.putIfAbsent(e.id, e)
            }
        }

        val tokens = extractSearchTokens(normalizedQuery)
        val seedEdgeIds = LinkedHashSet<Long>()
        val seedEventIds = LinkedHashSet<Long>()

        tokens.forEach { token ->
            if (seedEntities.size >= GRAPH_MAX_SEED_ENTITIES) return@forEach
            val hits = searchEntitiesHybrid(token, limit = GRAPH_SEED_SEARCH_LIMIT)
            hits.forEach { e ->
                if (seedEntities.size < GRAPH_MAX_SEED_ENTITIES) {
                    seedEntities.putIfAbsent(e.id, e)
                }
            }
        }

        // Episode/evidence seeding (Graphiti-style): if the query matches event text or edge evidence,
        // pull in those edges so older-but-relevant facts are not drowned out by recency-only ordering.
        val episodeTokens = tokens.take(GRAPH_SEED_EPISODE_TOKENS)
        episodeTokens.forEach { token ->
            if (seedEventIds.size < GRAPH_MAX_SEED_EVENTS) {
                val hits = searchEventsHybrid(token, limit = GRAPH_SEED_EVENT_SEARCH_LIMIT)
                hits.forEach { ev ->
                    if (seedEventIds.size < GRAPH_MAX_SEED_EVENTS) seedEventIds.add(ev.id)
                }
            }
            if (seedEdgeIds.size < GRAPH_MAX_SEED_EDGES) {
                val evHits = searchEdgeEvidenceHybrid(
                    token = token,
                    limit = GRAPH_SEED_EVIDENCE_SEARCH_LIMIT
                )
                evHits.forEach { ev ->
                    if (seedEdgeIds.size < GRAPH_MAX_SEED_EDGES) seedEdgeIds.add(ev.edgeId)
                    if (seedEventIds.size < GRAPH_MAX_SEED_EVENTS) seedEventIds.add(ev.eventId)
                }
            }
        }

        if (seedEventIds.isNotEmpty() && seedEdgeIds.size < GRAPH_MAX_SEED_EDGES) {
            val extra = memoryDao.findEdgeIdsByEventIds(
                eventIds = seedEventIds.toList(),
                limit = GRAPH_MAX_SEED_EDGES - seedEdgeIds.size
            )
            extra.forEach { eid ->
                if (seedEdgeIds.size < GRAPH_MAX_SEED_EDGES) seedEdgeIds.add(eid)
            }
        }

        val seedEdges = if (seedEdgeIds.isEmpty()) {
            emptyList()
        } else {
            memoryDao.loadEdgesByIds(seedEdgeIds.toList())
        }

        if (seedEntities.isEmpty() && seedEdges.isNotEmpty()) {
            val extraIds = LinkedHashSet<Long>()
            seedEdges.forEach { edge ->
                extraIds.add(edge.subjectEntityId)
                edge.objectEntityId?.let { extraIds.add(it) }
            }
            memoryDao.loadEntitiesByIds(extraIds.toList())
                .sortedByDescending { it.lastModifiedAt }
                .forEach { e ->
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
        if (seedEdges.isNotEmpty()) {
            // Include evidence-matched edges for visibility, but do not expand from their nodes unless
            // they are also part of the main seed set.
            seedEdges
                .sortedByDescending { it.validFrom }
                .forEach { edge ->
                    if (edgesById.size < maxEdges) edgesById.putIfAbsent(edge.id, edge)
                    visited.add(edge.subjectEntityId)
                    edge.objectEntityId?.let { visited.add(it) }
                }
        }
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

        val orderTokens = tokens.filter { it.length in 2..64 }.take(8)
        val edgeMaps = edgesById.values
            .sortedWith(
                compareByDescending<MemoryEdgeEntity> { seedEdgeIds.contains(it.id) }
                    .thenByDescending { edgeMatchScore(it, idToKey, orderTokens) }
                    .thenByDescending { it.confidence }
                    .thenByDescending { it.validFrom }
            )
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
        val rawKey = entityKey.trim()
        if (rawKey.isBlank()) {
            val fallback = MemoryEntityEntity(
                entityKey = "",
                type = "Unknown",
                name = "",
                aliases = emptyList(),
                metadata = emptyMap(),
                createdAt = now,
                lastModifiedAt = now
            )
            return fallback
        }

        val canonicalKey = canonicalizeEntityKey(rawKey)
        cache[canonicalKey]?.let { return it }

        memoryDao.findEntityByKey(canonicalKey)?.let { existing ->
            cache[canonicalKey] = existing
            upsertEntityAliasIfNeeded(aliasKey = rawKey, entityId = existing.id)
            return existing
        }

        memoryDao.findEntityByKey(rawKey)?.let { existing ->
            cache[canonicalKey] = existing
            if (canonicalKey != rawKey) {
                upsertEntityAliasIfNeeded(aliasKey = canonicalKey, entityId = existing.id)
            }
            return existing
        }

        memoryDao.findEntityIdByAlias(rawKey)
            ?.let { id -> memoryDao.getEntityById(id) }
            ?.let { aliased ->
                cache[canonicalKey] = aliased
                if (canonicalKey != rawKey) {
                    upsertEntityAliasIfNeeded(aliasKey = canonicalKey, entityId = aliased.id)
                }
                return aliased
            }

        memoryDao.findEntityIdByAlias(canonicalKey)
            ?.let { id -> memoryDao.getEntityById(id) }
            ?.let { aliased ->
                cache[canonicalKey] = aliased
                upsertEntityAliasIfNeeded(aliasKey = rawKey, entityId = aliased.id)
                return aliased
            }

        val inferredType = canonicalKey.substringBefore(':', missingDelimiterValue = "Unknown").ifBlank { "Unknown" }
        val inferredName = canonicalKey.substringAfter(':', missingDelimiterValue = canonicalKey).ifBlank { canonicalKey }
        val created = MemoryEntityEntity(
            entityKey = canonicalKey,
            type = inferredType,
            name = inferredName,
            aliases = emptyList(),
            metadata = emptyMap(),
            createdAt = now,
            lastModifiedAt = now
        )
        val insertedId = memoryDao.insertEntity(created)
        val row = if (insertedId > 0L) memoryDao.getEntityById(insertedId) else memoryDao.findEntityByKey(canonicalKey)
        val resolved = row ?: created.copy(id = insertedId)
        cache[canonicalKey] = resolved
        if (canonicalKey != rawKey) {
            upsertEntityAliasIfNeeded(aliasKey = rawKey, entityId = resolved.id)
        }
        return resolved
    }

    private suspend fun upsertEntityCandidate(candidate: GraphEntityCandidate, now: Long): MemoryEntityEntity {
        val rawKey = candidate.entityKey.trim()
        if (rawKey.isBlank()) {
            throw IllegalArgumentException("entity_key is blank")
        }
        val canonicalKey = canonicalizeEntityKey(rawKey)

        val existing = memoryDao.findEntityByKey(canonicalKey)
            ?: memoryDao.findEntityByKey(rawKey)
            ?: memoryDao.findEntityIdByAlias(rawKey)?.let { id -> memoryDao.getEntityById(id) }
            ?: memoryDao.findEntityIdByAlias(canonicalKey)?.let { id -> memoryDao.getEntityById(id) }

        if (existing == null) {
            val aliases = mergeAliases(emptyList(), candidate.aliases, candidate.name, rawKey).take(GRAPH_MAX_ALIASES)
            val entity = MemoryEntityEntity(
                entityKey = canonicalKey,
                type = candidate.type.trim().ifBlank { canonicalKey.substringBefore(':', missingDelimiterValue = "Unknown") },
                name = candidate.name.trim().ifBlank { canonicalKey.substringAfter(':', missingDelimiterValue = canonicalKey) },
                aliases = aliases,
                metadata = normalizeStringMap(candidate.metadata),
                createdAt = now,
                lastModifiedAt = now
            )
            val newId = memoryDao.insertEntity(entity)
            val row = if (newId > 0L) memoryDao.getEntityById(newId) else memoryDao.findEntityByKey(canonicalKey)
            val created = row ?: entity.copy(id = newId)
            if (rawKey != canonicalKey) {
                upsertEntityAliasIfNeeded(aliasKey = rawKey, entityId = created.id)
            }
            return created
        }

        if (rawKey != existing.entityKey) {
            upsertEntityAliasIfNeeded(aliasKey = rawKey, entityId = existing.id)
        }
        if (canonicalKey != existing.entityKey) {
            upsertEntityAliasIfNeeded(aliasKey = canonicalKey, entityId = existing.id)
        }

        val mergedAliases =
            mergeAliases(existing.aliases ?: emptyList(), candidate.aliases, candidate.name, rawKey).take(GRAPH_MAX_ALIASES)
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

    private fun toFtsPrefixQuery(token: String): String? {
        val t = token.trim()
        if (t.isBlank()) return null
        // Keep the query syntax simple and safe for FTS MATCH.
        if (!Regex("^[A-Za-z0-9_\\u4e00-\\u9fff]{2,64}$").matches(t)) return null
        return "${t}*"
    }

    private suspend fun searchEntitiesHybrid(
        token: String,
        limit: Int
    ): List<MemoryEntityEntity> {
        val out = LinkedHashMap<Long, MemoryEntityEntity>()
        val ftsQuery = toFtsPrefixQuery(token)
        if (ftsQuery != null) {
            try {
                memoryDao.searchEntitiesByFts(ftsQuery, limit).forEach { e ->
                    out.putIfAbsent(e.id, e)
                }
            } catch (_: Throwable) {
                // FTS is optional. Fall back to LIKE-based search.
            }
        }
        try {
            memoryDao.searchEntities(token, limit).forEach { e ->
                out.putIfAbsent(e.id, e)
            }
        } catch (_: Throwable) {
        }
        return out.values.toList()
    }

    private suspend fun searchEventsHybrid(token: String, limit: Int): List<MemoryEventEntity> {
        val ftsQuery = toFtsPrefixQuery(token)
        if (ftsQuery != null) {
            try {
                val out = memoryDao.searchEventsByFts(ftsQuery, limit)
                if (out.isNotEmpty()) return out
            } catch (_: Throwable) {
            }
        }
        return try {
            memoryDao.searchEventsByContent(token, limit)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private suspend fun searchEdgeEvidenceHybrid(
        token: String,
        limit: Int
    ): List<MemoryEdgeEvidenceEntity> {
        val ftsQuery = toFtsPrefixQuery(token)
        if (ftsQuery != null) {
            try {
                val out = memoryDao.searchEdgeEvidenceByFts(ftsQuery, limit)
                if (out.isNotEmpty()) return out
            } catch (_: Throwable) {
            }
        }
        return try {
            memoryDao.searchEdgeEvidenceByExcerpt(token, limit)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun edgeMatchScore(
        edge: MemoryEdgeEntity,
        idToKey: Map<Long, String>,
        tokens: List<String>
    ): Int {
        if (tokens.isEmpty()) return 0
        val subject = idToKey[edge.subjectEntityId].orEmpty()
        val obj = edge.objectEntityId?.let { idToKey[it].orEmpty() }.orEmpty()
        val value = edge.objectValue.orEmpty()
        val text = "$subject $obj $value".lowercase()
        var score = 0
        tokens.forEach { raw ->
            val t = raw.trim().lowercase()
            if (t.length >= 2 && text.contains(t)) score += 1
        }
        return score
    }

    private fun MemoryEventEntity.toSummary(): MemoryEventSummary {
        return MemoryEventSummary(
            id = id,
            externalId = externalId,
            occurredAt = occurredAt,
            type = type,
            source = source,
            content = content,
            containsUserContext = containsUserContext
        )
    }

    companion object {
        private const val TAG = "MemoryRepository"
        private const val PERSONA_SUMMARY_KEY = "persona_summary"
        private const val PERSONA_PROFILE_KEY = "persona_profile_v1"
        private const val GRAPH_MAX_ALIASES = 20
        private const val GRAPH_MAX_EVIDENCE_EXCERPT = 600
        private const val USER_ENTITY_KEY = "person:user"
        private const val GRAPH_MAX_TOKENS = 12
        private const val GRAPH_MAX_SEED_ENTITIES = 12
        private const val GRAPH_SEED_SEARCH_LIMIT = 8
        private const val GRAPH_SEED_EPISODE_TOKENS = 6
        private const val GRAPH_SEED_EVENT_SEARCH_LIMIT = 6
        private const val GRAPH_SEED_EVIDENCE_SEARCH_LIMIT = 8
        private const val GRAPH_MAX_SEED_EVENTS = 24
        private const val GRAPH_MAX_SEED_EDGES = 30
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

        private val ENTITY_TYPE_ALIASES = mapOf(
            "org" to "org",
            "organization" to "org",
            "company" to "org",
            "corporation" to "org",
            "institution" to "org",
            "person" to "person",
            "human" to "person",
            "user" to "person",
            "place" to "place",
            "location" to "place",
            "city" to "place",
            "country" to "place",
            "project" to "project",
            "product" to "product",
            "brand" to "brand",
            "app" to "app",
            "application" to "app",
            "software" to "software",
            "service" to "service",
            "concept" to "concept",
            "tech" to "tech",
            "technology" to "tech"
        )

        private val PREDICATE_SYNONYMS = mapOf(
            "work_at" to "works_at",
            "worksat" to "works_at",
            "live_in" to "lives_in",
            "livesin" to "lives_in",
            "resides_in" to "lives_in",
            "reside_in" to "lives_in",
            "locatedat" to "located_in",
            "located_at" to "located_in",
            "location_in" to "located_in"
        )
    }
}

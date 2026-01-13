package com.fqyw.screen_memo.memory.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface MemoryDao {

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertEvent(entity: MemoryEventEntity): Long

    @Update
    suspend fun updateEvent(entity: MemoryEventEntity)

    @Query("SELECT * FROM memory_events WHERE external_id = :externalId LIMIT 1")
    suspend fun findEventByExternalId(externalId: String): MemoryEventEntity?

    @Query(
        """
            UPDATE memory_events
            SET processed_at = :processedAt,
                contains_user_context = :containsUserContext,
                last_modified_at = :processedAt
            WHERE id = :eventId
        """
    )
    suspend fun markEventProcessed(
        eventId: Long,
        processedAt: Long,
        containsUserContext: Boolean
    )

    @Query("SELECT COUNT(*) FROM memory_events")
    suspend fun countAllEvents(): Int

    @Query("SELECT COUNT(*) FROM memory_events WHERE processed_at IS NULL")
    suspend fun countUnprocessedEvents(): Int

    @Query("SELECT COUNT(*) FROM memory_events WHERE processed_at IS NULL AND type != :excludedType")
    suspend fun countUnprocessedEventsExcludingType(excludedType: String): Int

    @Query("SELECT COUNT(*) FROM memory_events WHERE type != :excludedType")
    suspend fun countAllEventsExcludingType(excludedType: String): Int

    @Query(
        """
            SELECT * FROM memory_events
            ORDER BY occurred_at ASC
            LIMIT :limit OFFSET :offset
        """
    )
    suspend fun loadEventsAscending(limit: Int, offset: Int): List<MemoryEventEntity>

    @Query(
        """
            SELECT * FROM memory_events
            WHERE processed_at IS NULL
            ORDER BY occurred_at ASC
            LIMIT :limit
        """
    )
    suspend fun loadUnprocessedEvents(limit: Int): List<MemoryEventEntity>

    @Query(
        """
            SELECT * FROM memory_events
            WHERE processed_at IS NULL
            ORDER BY occurred_at ASC
            LIMIT 1
        """
    )
    suspend fun loadEarliestUnprocessedEvent(): MemoryEventEntity?

    @Query(
        """
            SELECT occurred_at FROM memory_events
            WHERE processed_at IS NULL
              AND type != :excludedType
        """
    )
    suspend fun loadUnprocessedTimestampsExcludingType(excludedType: String): List<Long>

    @Query(
        """
            SELECT occurred_at FROM memory_events
            WHERE type != :excludedType
        """
    )
    suspend fun loadAllTimestampsExcludingType(excludedType: String): List<Long>

    @Query(
        """
            SELECT * FROM memory_events
            WHERE processed_at IS NULL
              AND occurred_at >= :startMillis
              AND occurred_at < :endMillis
            ORDER BY occurred_at ASC
        """
    )
    suspend fun loadUnprocessedEventsBetween(startMillis: Long, endMillis: Long): List<MemoryEventEntity>

    @Query(
        """
            SELECT * FROM memory_events
            WHERE occurred_at >= :startMillis
              AND occurred_at < :endMillis
            ORDER BY occurred_at ASC
        """
    )
    suspend fun loadEventsBetween(startMillis: Long, endMillis: Long): List<MemoryEventEntity>

    @Transaction
    @Query(
        """
            SELECT * FROM memory_events
            ORDER BY occurred_at DESC
            LIMIT :limit
        """
    )
    fun observeRecentEvents(limit: Int): Flow<List<MemoryEventEntity>>

    @Query(
        """
            SELECT * FROM memory_events
            ORDER BY occurred_at DESC
            LIMIT :limit OFFSET :offset
        """
    )
    suspend fun loadEventsDescending(limit: Int, offset: Int): List<MemoryEventEntity>

    @Query("SELECT * FROM memory_events WHERE id = :eventId LIMIT 1")
    suspend fun getEventById(eventId: Long): MemoryEventEntity?

    @Query("SELECT COUNT(*) FROM memory_events")
    fun observeEventCount(): Flow<Int>

    @Query("DELETE FROM memory_events")
    suspend fun clearEvents()

    // ========== Temporal Knowledge Graph (Entities / Edges / Evidence) ==========

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertEntity(entity: MemoryEntityEntity): Long

    @Update
    suspend fun updateEntity(entity: MemoryEntityEntity)

    @Query("SELECT * FROM memory_entities WHERE entity_key = :entityKey LIMIT 1")
    suspend fun findEntityByKey(entityKey: String): MemoryEntityEntity?

    @Query("SELECT * FROM memory_entities WHERE id = :id LIMIT 1")
    suspend fun getEntityById(id: Long): MemoryEntityEntity?

    @Query("SELECT * FROM memory_entities WHERE id IN (:ids)")
    suspend fun loadEntitiesByIds(ids: List<Long>): List<MemoryEntityEntity>

    @Query(
        """
            SELECT * FROM memory_entities
            WHERE entity_key LIKE '%' || :query || '%'
               OR name LIKE '%' || :query || '%'
               OR aliases LIKE '%' || :query || '%'
            ORDER BY last_modified_at DESC
            LIMIT :limit
        """
    )
    suspend fun searchEntities(query: String, limit: Int): List<MemoryEntityEntity>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertEdge(entity: MemoryEdgeEntity): Long

    @Update
    suspend fun updateEdge(entity: MemoryEdgeEntity)

    @Query(
        """
            SELECT * FROM memory_edges
            WHERE subject_entity_id = :subjectEntityId
              AND predicate = :predicate
              AND valid_to IS NULL
        """
    )
    suspend fun findActiveEdgesBySubjectPredicate(subjectEntityId: Long, predicate: String): List<MemoryEdgeEntity>

    @Query(
        """
            SELECT * FROM memory_edges
            WHERE subject_entity_id = :subjectEntityId
              AND predicate = :predicate
              AND (
                (:objectEntityId IS NOT NULL AND object_entity_id = :objectEntityId)
                OR (:objectEntityId IS NULL AND :objectValue IS NOT NULL AND object_value = :objectValue)
              )
              AND valid_to IS NULL
            ORDER BY valid_from DESC
            LIMIT 1
        """
    )
    suspend fun findActiveEdge(
        subjectEntityId: Long,
        predicate: String,
        objectEntityId: Long?,
        objectValue: String?
    ): MemoryEdgeEntity?

    @Query(
        """
            UPDATE memory_edges
            SET valid_to = :validTo,
                last_modified_at = :validTo
            WHERE id IN (:edgeIds)
        """
    )
    suspend fun closeEdges(edgeIds: List<Long>, validTo: Long)

    @Query(
        """
            SELECT * FROM memory_edges
            WHERE (subject_entity_id IN (:entityIds) OR object_entity_id IN (:entityIds))
            ORDER BY valid_from DESC
            LIMIT :limit
        """
    )
    suspend fun loadEdgesConnectedToEntities(entityIds: List<Long>, limit: Int): List<MemoryEdgeEntity>

    @Query(
        """
            SELECT * FROM memory_edges
            WHERE (subject_entity_id IN (:entityIds) OR object_entity_id IN (:entityIds))
              AND valid_to IS NULL
            ORDER BY valid_from DESC
            LIMIT :limit
        """
    )
    suspend fun loadActiveEdgesConnectedToEntities(entityIds: List<Long>, limit: Int): List<MemoryEdgeEntity>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertEdgeEvidence(entity: MemoryEdgeEvidenceEntity): Long

    @Update
    suspend fun updateEdgeEvidence(entity: MemoryEdgeEvidenceEntity)

    @Query("SELECT * FROM memory_edge_evidence WHERE edge_id = :edgeId AND event_id = :eventId LIMIT 1")
    suspend fun findEdgeEvidenceByEdgeAndEvent(edgeId: Long, eventId: Long): MemoryEdgeEvidenceEntity?

    @Query(
        """
            SELECT * FROM memory_edge_evidence
            WHERE edge_id = :edgeId
            ORDER BY last_modified_at DESC
            LIMIT :limit
        """
    )
    suspend fun loadEdgeEvidence(edgeId: Long, limit: Int): List<MemoryEdgeEvidenceEntity>

    @Query("DELETE FROM memory_edge_evidence")
    suspend fun clearEdgeEvidence()

    @Query("DELETE FROM memory_edges")
    suspend fun clearEdges()

    @Query("DELETE FROM memory_entities")
    suspend fun clearEntities()

    // ========== Alias (Entity) ==========

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertEntityAlias(entity: MemoryEntityAliasEntity): Long

    @Query("SELECT entity_id FROM memory_entity_aliases WHERE alias_key = :aliasKey LIMIT 1")
    suspend fun findEntityIdByAlias(aliasKey: String): Long?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMetadata(entity: MemoryMetadataEntity)

    @Query("SELECT value FROM memory_metadata WHERE `key` = :key LIMIT 1")
    suspend fun getMetadataValue(key: String): String?

    @Query("DELETE FROM memory_metadata WHERE `key` = :key")
    suspend fun deleteMetadata(key: String)

    @Query("DELETE FROM memory_metadata")
    suspend fun clearMetadata()

    @Transaction
    suspend fun clearMemoryData() {
        clearEdgeEvidence()
        clearEdges()
        clearEntities()
        clearEvents()
        clearMetadata()
    }
}

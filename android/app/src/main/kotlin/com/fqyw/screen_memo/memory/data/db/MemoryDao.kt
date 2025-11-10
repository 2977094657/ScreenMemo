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

    @Transaction
    @Query(
        """
            SELECT * FROM memory_events
            ORDER BY occurred_at DESC
            LIMIT :limit
        """
    )
    fun observeRecentEventsWithTags(limit: Int): Flow<List<EventWithTagIds>>

    @Transaction
    @Query(
        """
            SELECT * FROM memory_tags
            WHERE status = :status
            ORDER BY last_seen_at DESC
            LIMIT :limit OFFSET :offset
        """
    )
    suspend fun loadTagsByStatus(status: String, limit: Int, offset: Int): List<TagWithEvidence>

    @Transaction
    @Query(
        """
            SELECT * FROM memory_events
            ORDER BY occurred_at DESC
            LIMIT :limit OFFSET :offset
        """
    )
    suspend fun loadEventsDescending(limit: Int, offset: Int): List<EventWithTagIds>

    @Query("SELECT * FROM memory_events WHERE id = :eventId LIMIT 1")
    suspend fun getEventById(eventId: Long): MemoryEventEntity?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertTag(entity: MemoryTagEntity): Long

    @Update
    suspend fun updateTag(entity: MemoryTagEntity)

    @Query("SELECT * FROM memory_tags WHERE tag_key = :tagKey LIMIT 1")
    suspend fun findTagByKey(tagKey: String): MemoryTagEntity?

    @Query("SELECT * FROM memory_tags WHERE id = :tagId LIMIT 1")
    suspend fun getTagById(tagId: Long): MemoryTagEntity?

    @Transaction
    @Query(
        """
            SELECT * FROM memory_tags
            WHERE status = :status
            ORDER BY last_seen_at DESC
            LIMIT :limit
        """
    )
    fun observeTagsByStatus(status: String, limit: Int): Flow<List<TagWithEvidence>>

    @Query("SELECT COUNT(*) FROM memory_tags WHERE status = :status")
    fun observeTagCountByStatus(status: String): Flow<Int>

    @Query("SELECT COUNT(*) FROM memory_events")
    fun observeEventCount(): Flow<Int>

    @Transaction
    @Query("SELECT * FROM memory_tags WHERE id = :tagId LIMIT 1")
    suspend fun getTagWithEvidence(tagId: Long): TagWithEvidence?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertEvidence(entity: MemoryTagEvidenceEntity): Long

    @Update
    suspend fun updateEvidence(entity: MemoryTagEvidenceEntity)

    @Query("SELECT * FROM memory_tag_evidence WHERE id = :id LIMIT 1")
    suspend fun getEvidenceById(id: Long): MemoryTagEvidenceEntity?

    @Query("SELECT * FROM memory_tag_evidence WHERE tag_id = :tagId AND event_id = :eventId LIMIT 1")
    suspend fun findEvidenceByTagAndEvent(tagId: Long, eventId: Long): MemoryTagEvidenceEntity?

    @Query("SELECT tag_id FROM memory_tag_evidence WHERE event_id = :eventId")
    suspend fun findTagIdsForEvent(eventId: Long): List<Long>

    @Transaction
    @Query("SELECT * FROM memory_events WHERE id = :eventId LIMIT 1")
    suspend fun getEventWithTags(eventId: Long): EventWithTagIds?

    @Query("SELECT COUNT(*) FROM memory_tag_evidence WHERE tag_id = :tagId")
    suspend fun countEvidenceForTag(tagId: Long): Int

    @Query("SELECT * FROM memory_tags ORDER BY last_seen_at DESC")
    suspend fun getAllTags(): List<MemoryTagEntity>

    @Query("DELETE FROM memory_tag_evidence")
    suspend fun clearTagEvidence()

    @Query("DELETE FROM memory_tag_evidence WHERE tag_id = :tagId")
    suspend fun deleteEvidenceByTag(tagId: Long)

    @Query("DELETE FROM memory_tags")
    suspend fun clearTags()

    @Query("DELETE FROM memory_tags WHERE id = :tagId")
    suspend fun deleteTagById(tagId: Long): Int

    @Query("DELETE FROM memory_events")
    suspend fun clearEvents()

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
        clearTagEvidence()
        clearTags()
        clearEvents()
        clearMetadata()
    }
}


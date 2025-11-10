package com.fqyw.screen_memo.memory.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "memory_events",
    indices = [
        Index(value = ["external_id"], unique = true),
        Index(value = ["occurred_at"])
    ]
)
data class MemoryEventEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0L,
    @ColumnInfo(name = "external_id")
    val externalId: String? = null,
    @ColumnInfo(name = "occurred_at")
    val occurredAt: Long,
    @ColumnInfo(name = "type")
    val type: String,
    @ColumnInfo(name = "source")
    val source: String,
    @ColumnInfo(name = "content")
    val content: String,
    @ColumnInfo(name = "metadata")
    val metadata: Map<String, String> = emptyMap(),
    @ColumnInfo(name = "contains_user_context")
    val containsUserContext: Boolean = false,
    @ColumnInfo(name = "processed_at")
    val processedAt: Long? = null,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "last_modified_at")
    val lastModifiedAt: Long = System.currentTimeMillis()
)


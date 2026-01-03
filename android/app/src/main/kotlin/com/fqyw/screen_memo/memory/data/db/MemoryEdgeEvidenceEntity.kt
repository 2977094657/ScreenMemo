package com.fqyw.screen_memo.memory.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "memory_edge_evidence",
    foreignKeys = [
        ForeignKey(
            entity = MemoryEdgeEntity::class,
            parentColumns = ["id"],
            childColumns = ["edge_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = MemoryEventEntity::class,
            parentColumns = ["id"],
            childColumns = ["event_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["edge_id"], name = "idx_memory_edge_evidence_edge"),
        Index(value = ["event_id"], name = "idx_memory_edge_evidence_event"),
        Index(value = ["edge_id", "event_id"], unique = true, name = "idx_memory_edge_evidence_pair")
    ]
)
data class MemoryEdgeEvidenceEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0L,
    @ColumnInfo(name = "edge_id")
    val edgeId: Long,
    @ColumnInfo(name = "event_id")
    val eventId: Long,
    @ColumnInfo(name = "excerpt")
    val excerpt: String,
    @ColumnInfo(name = "confidence")
    val confidence: Double = 0.6,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "last_modified_at")
    val lastModifiedAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "is_user_edited")
    val isUserEdited: Boolean = false,
    @ColumnInfo(name = "notes")
    val notes: String? = null
)
